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
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) {
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
        guard let context = CoordinateSpace.snapContext(at: mouse) else { return }

        guard let window = WindowEngine.windowAtCocoaPoint(mouse) else {
            if visible {
                let picker = LayoutPickerGeometry.make(screen: context.visible)
                if picker.bar.contains(context.cursor) {
                    return
                }
                hide()
            }
            return
        }

        let button = window.zoomButtonFrame ?? trafficLightFallback(for: window)
        guard let button else {
            if visible { hide() }
            return
        }

        let slop = button.inset(by: -14)
        let cursorAX = CoordinateSpace.cocoaPointToTopLeft(mouse)
        let overButton = slop.contains(cursorAX)
        guard overButton || visible else { return }

        let displayAX = CoordinateSpace.displayTopLeftRect(for: context.screen)
        let anchor = Point(x: button.maxX + 10, y: max(context.visible.minY + 8, button.maxY - displayAX.minY + 8))
        let picker = LayoutPickerGeometry.make(screen: context.visible, anchor: anchor)
        if visible && !overButton && !picker.bar.contains(context.cursor) {
            hide()
            return
        }

        let hit = picker.nearest(context.cursor)
        let zone: Rect?
        if let hit, let layout = LayoutCatalog.layout(id: hit.layoutID) {
            zone = layout.zones[hit.zoneIndex].frame(in: context.visible, gap: Settings.gap)
        } else {
            zone = nil
        }

        hoveredWindow = window
        visible = true
        SnapRuntime.shared.overlay.showPicker(
            on: context,
            picker: picker,
            hit: hit,
            zone: zone,
            clickable: true,
            onSelect: { [weak self] selected in
                self?.select(selected, window: window, screen: context.screen)
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

    private func trafficLightFallback(for window: AXWindow) -> Rect? {
        guard let frame = window.frame else { return nil }
        return Rect(x: frame.x + 8, y: frame.y + 4, width: 72, height: 28)
    }

    private func hide() {
        if visible {
            SnapRuntime.shared.overlay.hide()
        }
        visible = false
        hoveredWindow = nil
    }
}
