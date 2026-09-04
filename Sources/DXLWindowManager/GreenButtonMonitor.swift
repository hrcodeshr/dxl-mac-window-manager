import AppKit
import DXLSnapCore

final class GreenButtonMonitor {
    private var monitors: [Any] = []
    private var visible = false
    private var hoveredWindow: AXWindow?

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.update()
        }
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(moved)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        AppLog.info("green-button monitor started")
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        hide()
    }

    private func update() {
        guard Settings.snapEnabled, Settings.greenButtonPickerEnabled, AccessibilityPermission.isGranted else {
            hide()
            return
        }
        guard !SnapRuntime.shared.isDragging else {
            hide()
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let window = WindowEngine.windowAtCocoaPoint(mouse), let button = window.zoomButtonFrame else {
            if visible {
                let cursor = CoordinateSpace.cocoaPointToTopLeft(mouse)
                if let screen = CoordinateSpace.screenContaining(cocoaPoint: mouse) {
                    let picker = LayoutPickerGeometry.make(
                        screen: CoordinateSpace.visibleTopLeftRect(for: screen),
                        anchor: nil
                    )
                    if picker.bar.contains(cursor) {
                        return
                    }
                }
                hide()
            }
            return
        }

        let slop = button.inset(by: -10)
        let cursor = CoordinateSpace.cocoaPointToTopLeft(mouse)
        let overButton = slop.contains(cursor)
        guard overButton || visible else { return }

        guard let screen = CoordinateSpace.screenContaining(cocoaPoint: mouse) else { return }
        let visibleFrame = CoordinateSpace.visibleTopLeftRect(for: screen)
        let anchor = Point(x: button.maxX + 10, y: button.maxY + 8)
        let picker = LayoutPickerGeometry.make(screen: visibleFrame, anchor: anchor)
        if visible && !overButton && !picker.bar.contains(cursor) {
            hide()
            return
        }

        let hit = picker.hitTest(cursor)
        let zone: Rect?
        if let hit, let layout = LayoutCatalog.layout(id: hit.layoutID) {
            zone = layout.zones[hit.zoneIndex].frame(in: visibleFrame, gap: Settings.gap)
        } else {
            zone = nil
        }

        hoveredWindow = window
        visible = true
        SnapRuntime.shared.overlay.showPicker(
            on: screen,
            picker: picker,
            hit: hit,
            zone: zone,
            clickable: true,
            onSelect: { [weak self] selected in
                self?.select(selected, window: window, screen: screen)
            },
            onCancel: { [weak self] in
                self?.hide()
            }
        )
    }

    private func select(_ hit: PickerHit, window: AXWindow, screen: NSScreen) {
        guard let layout = LayoutCatalog.layout(id: hit.layoutID) else { return }
        AppLog.info("green-button snap \(layout.id)[\(hit.zoneIndex)]")
        SnapRuntime.shared.apply(
            layout: layout,
            index: hit.zoneIndex,
            window: window,
            screen: screen,
            reason: "green-button \(layout.id)[\(hit.zoneIndex)]"
        )
        visible = false
        hoveredWindow = nil
    }

    private func hide() {
        if visible {
            SnapRuntime.shared.overlay.hide()
        }
        visible = false
        hoveredWindow = nil
    }
}
