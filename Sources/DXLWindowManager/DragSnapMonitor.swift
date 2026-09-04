import AppKit
import DXLSnapCore

final class DragSnapMonitor {
    private var monitors: [Any] = []
    private var drag: DragSession?
    private var lastLoggedTarget: DragTarget?

    private struct DragSession {
        var window: AXWindow
        var initialFrame: Rect
        var startMouse: NSPoint
        var moved: Bool
        var unsnapping: Bool
        var restoreFrame: Rect?
    }

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        AppLog.info("drag monitor started")
    }

    func stop() {
        let wasRunning = !monitors.isEmpty
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        SnapRuntime.shared.isDragging = false
        SnapRuntime.shared.hideOverlays()
        drag = nil
        if wasRunning {
            AppLog.info("drag monitor stopped")
        }
    }

    private func handle(_ event: NSEvent) {
        guard Settings.snapEnabled, AccessibilityPermission.isGranted else { return }

        switch event.type {
        case .leftMouseDown:
            beginDrag(at: event)
        case .leftMouseDragged:
            updateDrag(at: event)
        case .leftMouseUp:
            finishDrag(at: event)
        default:
            break
        }
    }

    private func beginDrag(at event: NSEvent) {
        SnapRuntime.shared.hideOverlays()
        let point = NSEvent.mouseLocation
        guard let window = WindowEngine.windowAtCocoaPoint(point), let frame = window.frame else {
            drag = nil
            SnapRuntime.shared.isDragging = false
            return
        }

        let screen = CoordinateSpace.screenContaining(cocoaPoint: point)
        let visible = screen.map { CoordinateSpace.visibleTopLeftRect(for: $0) }
        var unsnapping = RestoreStore.shared.isCurrentlySnapped(key: window.restoreKey, frame: frame)
        var restore = RestoreStore.shared.original(for: window.restoreKey)
        if !unsnapping, let visible, SnapDetector.matchingZone(frame: frame, screen: visible, gap: Settings.gap) != nil {
            unsnapping = true
            restore = restore ?? RestoreMath.defaultFloating(on: visible)
        }

        drag = DragSession(
            window: window,
            initialFrame: frame,
            startMouse: point,
            moved: false,
            unsnapping: unsnapping,
            restoreFrame: restore
        )
        SnapRuntime.shared.isDragging = true
    }

    private func updateDrag(at event: NSEvent) {
        guard var session = drag, let current = session.window.frame else { return }
        if session.unsnapping, let original = session.restoreFrame, !session.moved {
            let mouse = NSEvent.mouseLocation
            let mouseDelta = hypot(mouse.x - session.startMouse.x, mouse.y - session.startMouse.y)
            guard mouseDelta > 6 else { return }
            if let screen = CoordinateSpace.screenContaining(cocoaPoint: mouse) {
                let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
                let cursor = CoordinateSpace.cocoaPointToTopLeft(mouse)
                let restored = RestoreMath.followCursor(
                    original: original,
                    snapped: session.initialFrame,
                    cursor: cursor,
                    screen: visible
                )
                if session.window.setFrame(restored) {
                    AppLog.info("unsnap restore pid=\(session.window.pid) to \(Int(restored.width))x\(Int(restored.height))")
                } else {
                    AppLog.error("unsnap restore failed pid=\(session.window.pid)")
                }
            }
            session.moved = true
            drag = session
            presentTarget()
            return
        }

        if !session.moved {
            let mouse = NSEvent.mouseLocation
            let mouseDelta = hypot(mouse.x - session.startMouse.x, mouse.y - session.startMouse.y)
            let originMoved =
                abs(current.x - session.initialFrame.x) > 4
                || abs(current.y - session.initialFrame.y) > 4
            guard originMoved || mouseDelta > 8 else { return }
            session.moved = true
            drag = session
        }
        presentTarget()
    }

    private func finishDrag(at event: NSEvent) {
        defer {
            drag = nil
            SnapRuntime.shared.isDragging = false
        }
        guard let session = drag, session.moved else {
            SnapRuntime.shared.hideOverlays()
            return
        }
        guard let resolved = resolveTarget() else {
            if session.unsnapping {
                RestoreStore.shared.markFloating(key: session.window.restoreKey)
                AppLog.info("unsnap complete pid=\(session.window.pid)")
            }
            SnapRuntime.shared.hideOverlays()
            return
        }
        SnapRuntime.shared.apply(
            layout: resolved.layout,
            index: resolved.index,
            window: session.window,
            screen: resolved.screen,
            reason: "drag \(resolved.layout.id)[\(resolved.index)]"
        )
    }

    private func presentTarget() {
        guard let screen = CoordinateSpace.screenContaining(cocoaPoint: NSEvent.mouseLocation) else { return }
        let display = CoordinateSpace.displayTopLeftRect(for: screen)
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let cursor = CoordinateSpace.cocoaPointToTopLeft(NSEvent.mouseLocation)
        let target = SnapDetector.target(cursor: cursor, display: display, visible: visible)
        let overlay = SnapRuntime.shared.overlay
        if lastLoggedTarget != target {
            lastLoggedTarget = target
            AppLog.info("drag target=\(target) cursor=\(Int(cursor.x)),\(Int(cursor.y))")
        }

        switch target {
        case .none:
            overlay.hide()
        case .maximize:
            let zone = LayoutCatalog.maximize.zones[0].frame(in: visible, gap: Settings.gap)
            overlay.showHighlight(on: screen, zone: zone)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: visible)
            let hit = picker.hitTest(cursor, columnFallback: true)
            let zone: Rect?
            if let hit, let layout = LayoutCatalog.layout(id: hit.layoutID) {
                zone = layout.zones[hit.zoneIndex].frame(in: visible, gap: Settings.gap)
            } else {
                zone = nil
            }
            overlay.showPicker(on: screen, picker: picker, hit: hit, zone: zone)
        case let .zone(layoutID, zoneIndex):
            guard let layout = LayoutCatalog.layout(id: layoutID) else { return }
            let zone = layout.zones[zoneIndex].frame(in: visible, gap: Settings.gap)
            overlay.showHighlight(on: screen, zone: zone)
        }
    }

    private func resolveTarget() -> (layout: SnapLayout, index: Int, screen: NSScreen)? {
        guard let screen = CoordinateSpace.screenContaining(cocoaPoint: NSEvent.mouseLocation) else { return nil }
        let display = CoordinateSpace.displayTopLeftRect(for: screen)
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let cursor = CoordinateSpace.cocoaPointToTopLeft(NSEvent.mouseLocation)
        let target = SnapDetector.target(cursor: cursor, display: display, visible: visible)

        switch target {
        case .none:
            return nil
        case .maximize:
            return (LayoutCatalog.maximize, 0, screen)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: visible)
            if let hit = picker.hitTest(cursor, columnFallback: true), let layout = LayoutCatalog.layout(id: hit.layoutID) {
                return (layout, hit.zoneIndex, screen)
            }
            return (LayoutCatalog.maximize, 0, screen)
        case let .zone(layoutID, zoneIndex):
            guard let layout = LayoutCatalog.layout(id: layoutID) else { return nil }
            return (layout, zoneIndex, screen)
        }
    }
}
