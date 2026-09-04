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

    func showHighlight(on context: ScreenSnapContext, zone: Rect) {
        pickerHUD.hide()
        highlightHUD.show(context: context, zone: zone, candidates: [], onSelect: nil, onCancel: nil)
    }

    func showPicker(
        on context: ScreenSnapContext,
        picker: LayoutPickerGeometry,
        hit: PickerHit?,
        zone: Rect?,
        clickable: Bool = false,
        onSelect: ((PickerHit) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        if let zone {
            highlightHUD.show(context: context, zone: zone, candidates: [], onSelect: nil, onCancel: nil)
        } else {
            highlightHUD.hide()
        }
        let becameVisible = !pickerHUD.isVisible
        pickerHUD.show(
            context: context,
            picker: picker,
            hit: hit,
            clickable: clickable,
            onSelect: onSelect,
            onCancel: onCancel
        )
        if becameVisible {
            AppLog.info("picker HUD shown clickable=\(clickable) hit=\(hit?.layoutID ?? "none")")
        }
    }

    func showAssist(
        on context: ScreenSnapContext,
        zone: Rect,
        candidates: [SnapCandidate],
        onSelect: @escaping (SnapCandidate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        pickerHUD.hide()
        highlightHUD.show(context: context, zone: zone, candidates: candidates, onSelect: onSelect, onCancel: onCancel)
    }

    func hide() {
        pickerHUD.hide()
        highlightHUD.hide()
    }

    func handlesInteractiveClick(at point: NSPoint) -> Bool {
        pickerHUD.handlesInteractiveClick(at: point)
            || highlightHUD.handlesInteractiveClick(at: point)
    }
}

private final class HUDWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PickerHUD {
    private let window: HUDWindow
    private let pickerView = PickerHUDView()

    init() {
        window = HUDWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 156),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 8)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.title = "DXL Snap Layouts"
        window.contentView = pickerView
        window.animationBehavior = .none
        window.alphaValue = 1
    }

    func show(
        context: ScreenSnapContext,
        picker: LayoutPickerGeometry,
        hit: PickerHit?,
        clickable: Bool,
        onSelect: ((PickerHit) -> Void)?,
        onCancel: (() -> Void)?
    ) {
        let frame = context.cocoaRect(fromLocal: picker.bar)
        window.setFrame(frame, display: true)
        window.ignoresMouseEvents = !clickable
        window.acceptsMouseMovedEvents = clickable
        pickerView.geometry = picker
        pickerView.hit = hit
        pickerView.onSelect = onSelect
        pickerView.onCancel = onCancel
        pickerView.needsDisplay = true
        window.orderFrontRegardless()
        window.displayIfNeeded()
    }

    var isVisible: Bool { window.isVisible }

    func handlesInteractiveClick(at point: NSPoint) -> Bool {
        window.isVisible && !window.ignoresMouseEvents && window.frame.contains(point)
    }

    func hide() {
        window.orderOut(nil)
    }
}

private final class PickerHUDView: NSView {
    var geometry: LayoutPickerGeometry?
    var hit: PickerHit?
    var onSelect: ((PickerHit) -> Void)?
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        bounds.fill()

        let caption = NSAttributedString(
            string: "DXL layouts — drop on a pane",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        caption.draw(at: NSPoint(x: 16, y: 8))

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
            NSColor.white.withAlphaComponent(selected ? 0.22 : 0.1).setFill()
            NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()

            let name = NSAttributedString(
                string: item.layout.name,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.white,
                ]
            )
            name.draw(at: NSPoint(x: frame.minX + 6, y: frame.maxY - 14))

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
        let screenPoint = window?.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
            ?? NSEvent.mouseLocation
        guard let context = CoordinateSpace.snapContext(at: screenPoint) else {
            onCancel?()
            return
        }
        if let picked = geometry.nearest(context.cursor) {
            onSelect?(picked)
        } else {
            onCancel?()
        }
    }
}

private final class HighlightHUD {
    private let window: HUDWindow
    private let fillView = HighlightView()

    init() {
        window = HUDWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 7)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = fillView
        window.animationBehavior = .none
    }

    func show(
        context: ScreenSnapContext,
        zone: Rect,
        candidates: [SnapCandidate],
        onSelect: ((SnapCandidate) -> Void)?,
        onCancel: (() -> Void)?
    ) {
        let frame = context.cocoaRect(fromLocal: zone).insetBy(dx: 6, dy: 6)
        window.setFrame(frame, display: true)
        window.ignoresMouseEvents = candidates.isEmpty
        fillView.candidates = candidates
        fillView.onSelect = onSelect
        fillView.onCancel = onCancel
        fillView.rebuild()
        window.orderFrontRegardless()
    }

    func hide() {
        fillView.candidates = []
        fillView.rebuild()
        window.orderOut(nil)
    }

    func handlesInteractiveClick(at point: NSPoint) -> Bool {
        window.isVisible && !window.ignoresMouseEvents && window.frame.contains(point)
    }
}

private final class HighlightView: NSView {
    var candidates: [SnapCandidate] = []
    var onSelect: ((SnapCandidate) -> Void)?
    var onCancel: (() -> Void)?
    private var buttons: [AssistButton] = []

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        if candidates.isEmpty {
            NSColor.systemBlue.withAlphaComponent(0.28).setFill()
        } else {
            NSColor(calibratedWhite: 0.045, alpha: 0.96).setFill()
        }
        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3
        path.fill()
        path.stroke()

        guard !candidates.isEmpty else { return }
        let heading = NSAttributedString(
            string: WindowEngine.hasScreenCaptureAccess
                ? "Choose a window"
                : "Choose a window · enable Screen Recording for previews",
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        heading.draw(
            in: NSRect(x: 18, y: 15, width: max(0, bounds.width - 36), height: 22)
        )
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

        let columns = min(bounds.width >= 520 ? 3 : 2, max(1, candidates.count))
        let rows = Int(ceil(Double(candidates.count) / Double(columns)))
        let horizontalPadding: CGFloat = 16
        let topPadding: CGFloat = 48
        let bottomPadding: CGFloat = 16
        let gap: CGFloat = 12
        let cellWidth =
            (bounds.width - horizontalPadding * 2 - gap * CGFloat(columns - 1))
            / CGFloat(columns)
        let cellHeight =
            (bounds.height - topPadding - bottomPadding - gap * CGFloat(rows - 1))
            / CGFloat(rows)

        for (index, candidate) in candidates.enumerated() {
            let col = index % columns
            let row = index / columns
            let button = AssistButton(candidate: candidate)
            button.frame = NSRect(
                x: horizontalPadding + CGFloat(col) * (cellWidth + gap),
                y: topPadding + CGFloat(row) * (cellHeight + gap),
                width: cellWidth,
                height: max(52, cellHeight)
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
    private var trackingArea: NSTrackingArea?
    private var hovered = false

    init(candidate: SnapCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: hovered ? 0.22 : 0.12, alpha: 1).setFill()
        NSColor.systemBlue.withAlphaComponent(hovered ? 1 : 0.55).setStroke()
        path.lineWidth = hovered ? 3 : 1
        path.fill()
        path.stroke()

        let titleHeight: CGFloat = 34
        let previewRect = NSRect(
            x: 8,
            y: 8,
            width: max(0, bounds.width - 16),
            height: max(0, bounds.height - titleHeight - 12)
        )
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: previewRect, xRadius: 6, yRadius: 6).fill()

        if let thumbnail = candidate.thumbnail {
            thumbnail.draw(
                in: aspectFit(size: thumbnail.size, inside: previewRect.insetBy(dx: 4, dy: 4)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else if let icon = candidate.icon {
            let side = min(64, max(24, previewRect.height - 12))
            icon.draw(
                in: NSRect(
                    x: previewRect.midX - side / 2,
                    y: previewRect.midY - side / 2,
                    width: side,
                    height: side
                )
            )
        }

        let iconRect = NSRect(
            x: 9,
            y: bounds.height - titleHeight + 5,
            width: 20,
            height: 20
        )
        candidate.icon?.draw(in: iconRect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let title = NSAttributedString(
            string: candidate.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )
        title.draw(
            in: NSRect(
                x: 35,
                y: bounds.height - titleHeight + 7,
                width: max(0, bounds.width - 44),
                height: 20
            )
        )
    }

    private func aspectFit(size: NSSize, inside rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
