import AppKit
import DXLSnapCore

final class OverlayController {
    private var windows: [ObjectIdentifier: OverlayWindow] = [:]

    func showHighlight(on screen: NSScreen, zone: Rect) {
        hide(except: screen)
        overlay(for: screen).show(state: OverlayState(highlightedZone: zone))
    }

    func showPicker(on screen: NSScreen, picker: LayoutPickerGeometry, hit: PickerHit?, zone: Rect?) {
        hide(except: screen)
        overlay(for: screen).show(state: OverlayState(highlightedZone: zone, picker: picker, pickerHit: hit))
    }

    func showAssist(
        on screen: NSScreen,
        zone: Rect,
        candidates: [SnapCandidate],
        onSelect: @escaping (SnapCandidate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        hide(except: screen)
        let overlay = overlay(for: screen)
        if let view = overlay.contentView as? OverlayView {
            view.onAssistSelect = onSelect
            view.onAssistCancel = onCancel
        }
        overlay.show(state: OverlayState(assistZone: zone, assistCandidates: candidates))
        overlay.makeKeyAndOrderFront(nil)
    }

    func hide() {
        windows.values.forEach { $0.hide() }
    }

    private func hide(except screen: NSScreen) {
        let keep = ObjectIdentifier(screen)
        for (id, window) in windows where id != keep {
            window.hide()
        }
    }

    private func overlay(for screen: NSScreen) -> OverlayWindow {
        let id = ObjectIdentifier(screen)
        if let existing = windows[id] {
            existing.setFrame(screen.frame, display: false)
            return existing
        }
        let created = OverlayWindow(screen: screen)
        windows[id] = created
        return created
    }
}
