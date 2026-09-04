import AppKit
import DXLSnapCore

final class DragSnapMonitor {
    private var monitors: [Any] = []
    private let overlay = OverlayController()
    private var drag: DragSession?
    private var assist: AssistSession?

    private struct DragSession {
        var window: AXWindow
        var initialFrame: Rect
        var startMouse: NSPoint
        var moved: Bool
        var unsnapping: Bool
        var restoreFrame: Rect?
    }

    private struct AssistSession {
        var layout: SnapLayout
        var filled: Set<Int>
        var screen: NSScreen
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
        overlay.hide()
        drag = nil
        if wasRunning {
            AppLog.info("drag monitor stopped")
        }
    }

    private func handle(_ event: NSEvent) {
        guard Settings.snapEnabled, AccessibilityPermission.isGranted else { return }

        switch event.type {
        case .leftMouseDown:
            if assist != nil {
                if event.window == nil {
                    assist = nil
                    overlay.hide()
                }
                return
            }
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
        assist = nil
        overlay.hide()
        let point = NSEvent.mouseLocation
        guard let window = WindowEngine.windowAtCocoaPoint(point), let frame = window.frame else {
            drag = nil
            return
        }
        let unsnapping = RestoreStore.shared.isCurrentlySnapped(key: window.restoreKey, frame: frame)
        drag = DragSession(
            window: window,
            initialFrame: frame,
            startMouse: point,
            moved: false,
            unsnapping: unsnapping,
            restoreFrame: RestoreStore.shared.original(for: window.restoreKey)
        )
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
            AppLog.info("drag pid=\(session.window.pid) title=\(session.window.title ?? "") unsnap=true")
            presentTarget(for: session.window)
            return
        }

        if !session.moved {
            let mouse = NSEvent.mouseLocation
            let mouseDelta = hypot(mouse.x - session.startMouse.x, mouse.y - session.startMouse.y)
            let originMoved =
                abs(current.x - session.initialFrame.x) > 4
                || abs(current.y - session.initialFrame.y) > 4
            let sameSize =
                abs(current.width - session.initialFrame.width) < 2
                && abs(current.height - session.initialFrame.height) < 2
            guard sameSize && (originMoved || mouseDelta > 8) else { return }
            session.moved = true
            drag = session
            AppLog.info("drag pid=\(session.window.pid) title=\(session.window.title ?? "") unsnap=false")
        }
        presentTarget(for: session.window)
    }

    private func finishDrag(at event: NSEvent) {
        defer { drag = nil }
        guard let session = drag, session.moved else {
            overlay.hide()
            return
        }
        guard let resolved = resolveTarget() else {
            if session.unsnapping {
                RestoreStore.shared.markFloating(key: session.window.restoreKey)
                AppLog.info("unsnap complete pid=\(session.window.pid)")
            }
            overlay.hide()
            return
        }
        apply(resolved, to: session.window)
    }

    private func presentTarget(for window: AXWindow) {
        guard let screen = CoordinateSpace.screenContaining(cocoaPoint: NSEvent.mouseLocation) else { return }
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let cursor = CoordinateSpace.cocoaPointToTopLeft(NSEvent.mouseLocation)
        let target = SnapDetector.target(cursor: cursor, screen: visible)

        switch target {
        case .none:
            overlay.hide()
        case .maximize:
            let zone = LayoutCatalog.maximize.zones[0].frame(in: visible, gap: Settings.gap)
            overlay.showHighlight(on: screen, zone: zone)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: visible)
            let hit = picker.hitTest(cursor)
            let zone: Rect?
            if let hit, let layout = LayoutCatalog.layout(id: hit.layoutID) {
                zone = layout.zones[hit.zoneIndex].frame(in: visible, gap: Settings.gap)
            } else {
                zone = LayoutCatalog.maximize.zones[0].frame(in: visible, gap: Settings.gap)
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
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let cursor = CoordinateSpace.cocoaPointToTopLeft(NSEvent.mouseLocation)
        let target = SnapDetector.target(cursor: cursor, screen: visible)

        switch target {
        case .none:
            return nil
        case .maximize:
            return (LayoutCatalog.maximize, 0, screen)
        case .layoutPicker:
            let picker = LayoutPickerGeometry.make(screen: visible)
            if let hit = picker.hitTest(cursor), let layout = LayoutCatalog.layout(id: hit.layoutID) {
                return (layout, hit.zoneIndex, screen)
            }
            return (LayoutCatalog.maximize, 0, screen)
        case let .zone(layoutID, zoneIndex):
            guard let layout = LayoutCatalog.layout(id: layoutID) else { return nil }
            return (layout, zoneIndex, screen)
        }
    }

    private func apply(_ resolved: (layout: SnapLayout, index: Int, screen: NSScreen), to window: AXWindow) {
        let visible = CoordinateSpace.visibleTopLeftRect(for: resolved.screen)
        let frame = resolved.layout.zones[resolved.index].frame(in: visible, gap: Settings.gap)
        _ = SnapApply.snap(window, to: frame, reason: "drag \(resolved.layout.id)[\(resolved.index)]")

        let remaining = SnapDetector.remainingZoneIndices(layout: resolved.layout, filled: resolved.index)
        if Settings.snapAssistEnabled, let next = remaining.first {
            let candidates = WindowEngine.candidateWindows(excluding: window.pid)
            if !candidates.isEmpty {
                let zone = resolved.layout.zones[next].frame(in: visible, gap: Settings.gap)
                assist = AssistSession(layout: resolved.layout, filled: [resolved.index], screen: resolved.screen)
                overlay.showAssist(
                    on: resolved.screen,
                    zone: zone,
                    candidates: candidates,
                    onSelect: { [weak self] candidate in
                        self?.fillAssist(with: candidate)
                    },
                    onCancel: { [weak self] in
                        self?.assist = nil
                        self?.overlay.hide()
                    }
                )
                return
            }
        }
        overlay.hide()
    }

    private func fillAssist(with candidate: SnapCandidate) {
        guard let assist else { return }
        let remaining = assist.layout.zones.indices.filter { !assist.filled.contains($0) }
        guard let next = remaining.first, let window = WindowEngine.window(forPID: candidate.pid, matching: candidate.bounds) else {
            self.assist = nil
            overlay.hide()
            return
        }
        let visible = CoordinateSpace.visibleTopLeftRect(for: assist.screen)
        let frame = assist.layout.zones[next].frame(in: visible, gap: Settings.gap)
        _ = SnapApply.snap(window, to: frame, reason: "assist \(assist.layout.id)[\(next)]")

        var filled = assist.filled
        filled.insert(next)
        let stillOpen = assist.layout.zones.indices.filter { !filled.contains($0) }
        if let following = stillOpen.first {
            self.assist = AssistSession(layout: assist.layout, filled: filled, screen: assist.screen)
            let zone = assist.layout.zones[following].frame(in: visible, gap: Settings.gap)
            let candidates = WindowEngine.candidateWindows(excluding: candidate.pid)
            if candidates.isEmpty {
                self.assist = nil
                overlay.hide()
                return
            }
            overlay.showAssist(
                on: assist.screen,
                zone: zone,
                candidates: candidates,
                onSelect: { [weak self] nextCandidate in
                    self?.fillAssist(with: nextCandidate)
                },
                onCancel: { [weak self] in
                    self?.assist = nil
                    self?.overlay.hide()
                }
            )
        } else {
            self.assist = nil
            overlay.hide()
        }
    }
}
