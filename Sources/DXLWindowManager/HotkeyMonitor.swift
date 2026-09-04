import AppKit
import Carbon
import DXLSnapCore

final class HotkeyMonitor {
    private var monitors: [Any] = []

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            if self.handle(event) {
                return nil
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard Settings.snapEnabled, AccessibilityPermission.isGranted else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.control) && mods.contains(.option) else { return false }
        guard !mods.contains(.command) else { return false }

        let mapping: (String, Int)?
        switch event.keyCode {
        case UInt16(kVK_LeftArrow):
            mapping = (LayoutCatalog.twoEqual.id, 0)
        case UInt16(kVK_RightArrow):
            mapping = (LayoutCatalog.twoEqual.id, 1)
        case UInt16(kVK_UpArrow):
            mapping = (LayoutCatalog.maximize.id, 0)
        case UInt16(kVK_DownArrow):
            mapping = (LayoutCatalog.topBottom.id, 1)
        case UInt16(kVK_ANSI_U):
            mapping = (LayoutCatalog.quadrants.id, 0)
        case UInt16(kVK_ANSI_I):
            mapping = (LayoutCatalog.quadrants.id, 1)
        case UInt16(kVK_ANSI_J):
            mapping = (LayoutCatalog.quadrants.id, 2)
        case UInt16(kVK_ANSI_K):
            mapping = (LayoutCatalog.quadrants.id, 3)
        default:
            mapping = nil
        }

        guard let mapping, let layout = LayoutCatalog.layout(id: mapping.0) else { return false }
        guard let window = WindowEngine.focusedWindow(), let current = window.frame else { return false }
        let windowCenter = CoordinateSpace.topLeftPointToCocoa(Point(x: current.midX, y: current.midY))
        let screen = CoordinateSpace.screenContaining(cocoaPoint: windowCenter) ?? NSScreen.main
        guard let screen else { return false }
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let frame = layout.zones[mapping.1].frame(in: visible, gap: Settings.gap)
        return SnapApply.snap(window, to: frame, reason: "hotkey \(mapping.0)")
    }
}
