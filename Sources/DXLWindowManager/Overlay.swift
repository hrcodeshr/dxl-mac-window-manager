import AppKit
import DXLSnapCore

struct OverlayState {
    var highlightedZone: Rect?
    var picker: LayoutPickerGeometry?
    var pickerHit: PickerHit?
    var assistZone: Rect?
    var assistCandidates: [SnapCandidate] = []
    var clickable = false
}

final class OverlayController {
    private let pickerHUD = PickerHUD()
    private let highlightHUD = HighlightHUD()

    func showHighlight(on screen: NSScreen, zone: Rect) {
        pickerHUD.hide()
        highlightHUD.show(zone: zone, candidates: [], onSelect: nil, onCancel: nil)
    }

    func showPicker(
        on screen: NSScreen,
        picker: LayoutPickerGeometry,
        hit: PickerHit?,
        zone: Rect?,
        clickable: Bool = false,
        onSelect: ((PickerHit) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        if let zone {
            highlightHUD.show(zone: zone, candidates: [], onSelect: nil, onCancel: nil)
        } else {
            highlightHUD.hide()
        }
        pickerHUD.show(picker: picker, hit: hit, clickable: clickable, onSelect: onSelect, onCancel: onCancel)
        AppLog.info("picker HUD shown clickable=\(clickable) hit=\(hit?.layoutID ?? "none")")
    }

    func showAssist(
        on screen: NSScreen,
        zone: Rect,
        candidates: [SnapCandidate],
        onSelect: @escaping (SnapCandidate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        pickerHUD.hide()
        highlightHUD.show(zone: zone, candidates: candidates, onSelect: onSelect, onCancel: onCancel)
    }

    func hide() {
        pickerHUD.hide()
        highlightHUD.hide()
    }
}

private final class PickerHUD: NSPanel {
    private let pickerView = PickerHUDView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 140),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = true
        backgroundColor = NSColor.black.withAlphaComponent(0.92)
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        title = "DXL Snap Layouts"
        contentView = pickerView
    }

    func show(
        picker: LayoutPickerGeometry,
        hit: PickerHit?,
        clickable: Bool,
        onSelect: ((PickerHit) -> Void)?,
        onCancel: (() -> Void)?
    ) {
        let frame = CoordinateSpace.topLeftRectToCocoa(picker.bar)
        setFrame(frame, display: true)
        ignoresMouseEvents = !clickable
        acceptsMouseMovedEvents = clickable
        pickerView.geometry = picker
        pickerView.hit = hit
        pickerView.onSelect = onSelect
        pickerView.onCancel = onCancel
        pickerView.needsDisplay = true
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

private final class PickerHUDView: NSView {
    var geometry: LayoutPickerGeometry?
    var hit: PickerHit?
    var onSelect: ((PickerHit) -> Void)?
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.92).setFill()
        bounds.fill()

        let caption = NSAttributedString(
            string: "DXL layouts — drop or click a pane",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        caption.draw(at: NSPoint(x: 16, y: 6))

        guard let geometry else { return }
        let origin = geometry.bar
        for item in geometry.items {
            let frame = NSRect(
                x: item.frame.x - origin.x,
                y: item.frame.y - origin.y,
                width: item.frame.width,
                height: item.frame.height
            )
            let selected = hit?.layoutID == item.layout.id
            NSColor.white.withAlphaComponent(selected ? 0.2 : 0.1).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()

            for (index, zone) in item.zoneFrames.enumerated() {
                let zoneRect = NSRect(
                    x: zone.x - origin.x,
                    y: zone.y - origin.y,
                    width: zone.width,
                    height: zone.height
                )
                let isHit = hit?.layoutID == item.layout.id && hit?.zoneIndex == index
                NSColor.systemBlue.withAlphaComponent(isHit ? 0.95 : 0.45).setFill()
                NSBezierPath(roundedRect: zoneRect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let geometry else {
            onCancel?()
            return
        }
        let cursor = CoordinateSpace.cocoaPointToTopLeft(
            window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin ?? NSEvent.mouseLocation
        )
        if let picked = geometry.hitTest(cursor, columnFallback: true) {
            onSelect?(picked)
        } else {
            onCancel?()
        }
    }
}

private final class HighlightHUD: NSPanel {
    private let fillView = HighlightView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = fillView
    }

    func show(
        zone: Rect,
        candidates: [SnapCandidate],
        onSelect: ((SnapCandidate) -> Void)?,
        onCancel: (() -> Void)?
    ) {
        let frame = CoordinateSpace.topLeftRectToCocoa(zone).insetBy(dx: 6, dy: 6)
        setFrame(frame, display: true)
        ignoresMouseEvents = candidates.isEmpty
        fillView.candidates = candidates
        fillView.onSelect = onSelect
        fillView.onCancel = onCancel
        fillView.rebuild()
        orderFrontRegardless()
    }

    func hide() {
        fillView.candidates = []
        fillView.rebuild()
        orderOut(nil)
    }
}

private final class HighlightView: NSView {
    var candidates: [SnapCandidate] = []
    var onSelect: ((SnapCandidate) -> Void)?
    var onCancel: (() -> Void)?
    private var buttons: [AssistButton] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3
        path.fill()
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if !candidates.isEmpty {
            onCancel?()
        }
    }

    func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        guard !candidates.isEmpty else { return }

        let columns = min(3, max(1, candidates.count))
        let rows = Int(ceil(Double(candidates.count) / Double(columns)))
        let padding: CGFloat = 20
        let gap: CGFloat = 10
        let cellWidth = (bounds.width - padding * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = min(72, (bounds.height - padding * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows))

        for (index, candidate) in candidates.enumerated() {
            let col = index % columns
            let row = index / columns
            let button = AssistButton(candidate: candidate)
            button.frame = NSRect(
                x: padding + CGFloat(col) * (cellWidth + gap),
                y: padding + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: cellHeight
            )
            button.onSelect = { [weak self] in
                self?.onSelect?(candidate)
            }
            addSubview(button)
            buttons.append(button)
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
        NSColor.white.withAlphaComponent(0.16).setFill()
        path.fill()

        let iconRect = NSRect(x: 12, y: (bounds.height - 28) / 2, width: 28, height: 28)
        candidate.icon?.draw(in: iconRect)
        let title = NSAttributedString(
            string: candidate.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )
        title.draw(in: NSRect(x: 48, y: 0, width: max(0, bounds.width - 56), height: bounds.height))
    }
}
