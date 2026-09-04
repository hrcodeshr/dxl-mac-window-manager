import AppKit
import DXLSnapCore

final class SnapRuntime {
    static let shared = SnapRuntime()

    let overlay = OverlayController()
    var isDragging = false
    private var assist: AssistSession?

    private struct AssistSession {
        var layout: SnapLayout
        var filled: Set<Int>
        var screen: NSScreen
    }

    func apply(layout: SnapLayout, index: Int, window: AXWindow, screen: NSScreen, reason: String) {
        let visible = CoordinateSpace.visibleTopLeftRect(for: screen)
        let frame = layout.zones[index].frame(in: visible, gap: Settings.gap)
        _ = SnapApply.snap(window, to: frame, reason: reason)

        let remaining = SnapDetector.remainingZoneIndices(layout: layout, filled: index)
        if Settings.snapAssistEnabled, let next = remaining.first {
            let candidates = WindowEngine.candidateWindows(excluding: window.pid)
            if !candidates.isEmpty {
                let context = ScreenSnapContext(screen: screen, cocoaCursor: NSEvent.mouseLocation)
                let zone = layout.zones[next].frame(in: context.visible, gap: Settings.gap)
                assist = AssistSession(layout: layout, filled: [index], screen: screen)
                overlay.showAssist(
                    on: context,
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

    func hideOverlays() {
        assist = nil
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
        let context = ScreenSnapContext(screen: assist.screen, cocoaCursor: NSEvent.mouseLocation)
        let frame = assist.layout.zones[next].frame(in: visible, gap: Settings.gap)
        _ = SnapApply.snap(window, to: frame, reason: "assist \(assist.layout.id)[\(next)]")

        var filled = assist.filled
        filled.insert(next)
        let stillOpen = assist.layout.zones.indices.filter { !filled.contains($0) }
        if let following = stillOpen.first {
            self.assist = AssistSession(layout: assist.layout, filled: filled, screen: assist.screen)
            let zone = assist.layout.zones[following].frame(in: context.visible, gap: Settings.gap)
            let candidates = WindowEngine.candidateWindows(excluding: candidate.pid)
            if candidates.isEmpty {
                self.assist = nil
                overlay.hide()
                return
            }
            overlay.showAssist(
                on: context,
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
