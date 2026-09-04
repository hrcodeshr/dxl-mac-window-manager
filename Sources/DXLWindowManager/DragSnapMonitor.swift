import AppKit
import DXLSnapCore

final class DragSnapMonitor {
    var statusHandler: ((String?) -> Void)?

    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var drag: DragSession?
    private var lastLoggedTarget: DragTarget?
    private var buttonWasDown = false

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

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollMouse()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        AppLog.info("drag monitor started (events + poll)")
    }

    func stop() {
        let wasRunning = !monitors.isEmpty || pollTimer != nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        SnapRuntime.shared.isDragging = false
        SnapRuntime.shared.hideOverlays()
        drag = nil
        buttonWasDown = false
        statusHandler?(nil)
        if wasRunning {
            AppLog.info("drag monitor stopped")
        }
    }

    private func handle(_ event: NSEvent) {
        guard Settings.snapEnabled, AccessibilityPermission.isGranted else { return }

        switch event.type {
        case .leftMouseDown:
            buttonWasDown = true
            beginDrag()
        case .leftMouseDragged:
            buttonWasDown = true
            updateDrag()
        case .leftMouseUp:
            finishDrag()
            buttonWasDown = false
        default:
            break
        }
    }

    /// Do not depend on dragged events. Recent macOS often delivers only down/up to global monitors.
    private func pollMouse() {
        guard Settings.snapEnabled, AccessibilityPermission.isGranted else { return }
        let down = NSEvent.pressedMouseButtons & (1 << 0) != 0
        if down && !buttonWasDown {
            buttonWasDown = true
            beginDrag()
        } else if down && buttonWasDown {
            updateDrag()
        } else if !down && buttonWasDown {
            finishDrag()
            buttonWasDown = false
        }
    }

    private func beginDrag() {
        guard drag == nil else { return }
        SnapRuntime.shared.hideOverlays()
        lastLoggedTarget = nil
        let point = NSEvent.mouseLocation
        guard let window = WindowEngine.windowAtCocoaPoint(point), let frame = window.frame else {
            AppLog.info("drag begin missed window at \(Int(point.x)),\(Int(point.y))")
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
        AppLog.info("drag begin pid=\(window.pid) title=\(window.title ?? "")")
    }

    private func updateDrag() {
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

    private func finishDrag() {
        guard let session = drag else { return }
        drag = nil
        SnapRuntime.shared.isDragging = false
        statusHandler?(nil)

        let mouse = NSEvent.mouseLocation
        let mouseDelta = hypot(mouse.x - session.startMouse.x, mouse.y - session.startMouse.y)
        let moved = session.moved || mouseDelta > 8
        guard moved else {
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
        guard let context = CoordinateSpace.snapContext() else { return }
        let target = SnapDetector.target(cursor: context.cursor, display: context.display, visible: context.visible)
        let overlay = SnapRuntime.shared.overlay
        statusHandler?(Self.label(for: target))
        if lastLoggedTarget != target {
            lastLoggedTarget = target
            AppLog.info(
                "drag target=\(target) cocoa=\(Int(context.cocoaCursor.x)),\(Int(context.cocoaCursor.y)) local=\(Int(context.cursor.x)),\(Int(context.cursor.y))"
            )
        }

        switch target {
        case .none:
            overlay.hide()
        case .maximize:
            let zone = LayoutCatalog.maximize.zones[0].frame(in: context.visible, gap: Settings.gap)
            overlay.showHighlight(on: context, zone: zone)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: context.visible)
            let hit = picker.nearest(context.cursor)
            let zone: Rect?
            if let hit, let layout = LayoutCatalog.layout(id: hit.layoutID) {
                zone = layout.zones[hit.zoneIndex].frame(in: context.visible, gap: Settings.gap)
            } else {
                zone = nil
            }
            overlay.showPicker(on: context, picker: picker, hit: hit, zone: zone)
        case let .zone(layoutID, zoneIndex):
            guard let layout = LayoutCatalog.layout(id: layoutID) else { return }
            let zone = layout.zones[zoneIndex].frame(in: context.visible, gap: Settings.gap)
            overlay.showHighlight(on: context, zone: zone)
        }
    }

    private func resolveTarget() -> (layout: SnapLayout, index: Int, screen: NSScreen)? {
        guard let context = CoordinateSpace.snapContext() else { return nil }
        let target = SnapDetector.target(cursor: context.cursor, display: context.display, visible: context.visible)

        switch target {
        case .none:
            return nil
        case .maximize:
            return (LayoutCatalog.maximize, 0, context.screen)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: context.visible)
            if let hit = picker.nearest(context.cursor), let layout = LayoutCatalog.layout(id: hit.layoutID) {
                return (layout, hit.zoneIndex, context.screen)
            }
            return nil
        case let .zone(layoutID, zoneIndex):
            guard let layout = LayoutCatalog.layout(id: layoutID) else { return nil }
            return (layout, zoneIndex, context.screen)
        }
    }

    private static func label(for target: DragTarget) -> String? {
        switch target {
        case .none:
            return "Drag"
        case .maximize:
            return "Max"
        case .layoutPicker:
            return "Picker"
        case let .zone(layoutID, zoneIndex):
            switch layoutID {
            case LayoutCatalog.twoEqual.id:
                return zoneIndex == 0 ? "Left" : "Right"
            case LayoutCatalog.quadrants.id:
                return ["TL", "TR", "BL", "BR"][safe: zoneIndex] ?? "Corner"
            case LayoutCatalog.topBottom.id:
                return zoneIndex == 0 ? "Top" : "Bottom"
            default:
                return "Snap"
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
