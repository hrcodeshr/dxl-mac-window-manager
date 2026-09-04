import AppKit
import DXLSnapCore

final class OverlayWindow: NSPanel {
    private let overlayView: OverlayView

    init(screen: NSScreen) {
        overlayView = OverlayView()
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        contentView = overlayView
    }

    func show(state: OverlayState) {
        ignoresMouseEvents = state.assistCandidates.isEmpty
        overlayView.apply(state)
        orderFrontRegardless()
    }

    func hide() {
        overlayView.apply(OverlayState())
        ignoresMouseEvents = true
        orderOut(nil)
    }
}

struct OverlayState {
    var highlightedZone: Rect?
    var picker: LayoutPickerGeometry?
    var pickerHit: PickerHit?
    var assistZone: Rect?
    var assistCandidates: [SnapCandidate] = []
}

final class OverlayView: NSView {
    var state = OverlayState()
    var onAssistSelect: ((SnapCandidate) -> Void)?
    var onAssistCancel: (() -> Void)?
    private var assistButtons: [AssistButton] = []

    override var isFlipped: Bool { true }

    func apply(_ state: OverlayState) {
        self.state = state
        needsDisplay = true
        rebuildAssistButtons()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.screen != nil else { return }
        let origin = CoordinateSpace.cocoaRectToTopLeft(window?.screen?.frame ?? .zero)

        func local(_ rect: Rect) -> NSRect {
            NSRect(
                x: rect.x - origin.x,
                y: rect.y - origin.y,
                width: rect.width,
                height: rect.height
            )
        }

        if let zone = state.highlightedZone {
            drawZone(local(zone), highlighted: true)
        }

        if let picker = state.picker {
            drawPicker(picker, origin: origin)
        }

        if let assist = state.assistZone {
            let rect = local(assist)
            NSColor.black.withAlphaComponent(0.28).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        }
    }

    override var acceptsFirstResponder: Bool { !state.assistCandidates.isEmpty }

    override func mouseDown(with event: NSEvent) {
        guard !state.assistCandidates.isEmpty else { return }
        onAssistCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onAssistCancel?()
            return
        }
        super.keyDown(with: event)
    }

    private func drawZone(_ rect: NSRect, highlighted: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 12, yRadius: 12)
        if highlighted {
            NSColor.systemBlue.withAlphaComponent(0.28).setFill()
            NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        } else {
            NSColor.white.withAlphaComponent(0.12).setFill()
            NSColor.white.withAlphaComponent(0.4).setStroke()
        }
        path.lineWidth = 2
        path.fill()
        path.stroke()
    }

    private func drawPicker(_ picker: LayoutPickerGeometry, origin: Rect) {
        let bar = NSRect(
            x: picker.bar.x - origin.x,
            y: picker.bar.y - origin.y,
            width: picker.bar.width,
            height: picker.bar.height
        )
        let barPath = NSBezierPath(roundedRect: bar, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.72).setFill()
        barPath.fill()

        for item in picker.items {
            let frame = NSRect(
                x: item.frame.x - origin.x,
                y: item.frame.y - origin.y,
                width: item.frame.width,
                height: item.frame.height
            )
            let selectedLayout = state.pickerHit?.layoutID == item.layout.id
            NSColor.white.withAlphaComponent(selectedLayout ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()

            for (index, zone) in item.zoneFrames.enumerated() {
                let zoneRect = NSRect(
                    x: zone.x - origin.x,
                    y: zone.y - origin.y,
                    width: zone.width,
                    height: zone.height
                )
                let hit = state.pickerHit?.layoutID == item.layout.id && state.pickerHit?.zoneIndex == index
                let path = NSBezierPath(roundedRect: zoneRect, xRadius: 3, yRadius: 3)
                if hit {
                    NSColor.systemBlue.withAlphaComponent(0.85).setFill()
                } else {
                    NSColor.white.withAlphaComponent(0.35).setFill()
                }
                path.fill()
            }
        }
    }

    private func rebuildAssistButtons() {
        assistButtons.forEach { $0.removeFromSuperview() }
        assistButtons.removeAll()
        window?.ignoresMouseEvents = state.assistCandidates.isEmpty

        guard
            let assist = state.assistZone,
            !state.assistCandidates.isEmpty,
            let screenFrame = window?.screen?.frame
        else { return }

        let origin = CoordinateSpace.cocoaRectToTopLeft(screenFrame)
        let local = NSRect(
            x: assist.x - origin.x,
            y: assist.y - origin.y,
            width: assist.width,
            height: assist.height
        )

        let columns = min(3, max(1, state.assistCandidates.count))
        let rows = Int(ceil(Double(state.assistCandidates.count) / Double(columns)))
        let padding: CGFloat = 24
        let gap: CGFloat = 12
        let cellWidth = (local.width - padding * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = min(88, (local.height - padding * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))

        for (index, candidate) in state.assistCandidates.enumerated() {
            let col = index % columns
            let row = index / columns
            let frame = NSRect(
                x: local.minX + padding + CGFloat(col) * (cellWidth + gap),
                y: local.minY + padding + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
            let button = AssistButton(candidate: candidate)
            button.frame = frame
            button.onSelect = { [weak self] in
                self?.onAssistSelect?(candidate)
            }
            addSubview(button)
            assistButtons.append(button)
        }
    }
}

private final class AssistButton: NSControl {
    let candidate: SnapCandidate
    var onSelect: (() -> Void)?

    init(candidate: SnapCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.14).setFill()
        path.fill()

        let iconRect = NSRect(x: 16, y: (bounds.height - 36) / 2, width: 36, height: 36)
        candidate.icon?.draw(in: iconRect)

        let titleRect = NSRect(
            x: 60,
            y: 0,
            width: max(0, bounds.width - 72),
            height: bounds.height
        )
        let title = NSAttributedString(
            string: candidate.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        title.draw(in: titleRect)
    }
}
