import AppKit
import DXLSnapCore

final class LayoutEditorController: NSObject {
    private var window: NSWindow?
    private var list: NSPopUpButton?
    private var nameField: NSTextField?
    private var zonesView: NSTextView?
    private var preview: LayoutPreviewView?

    func show() {
        if window == nil {
            window = makeWindow()
        }
        reloadList()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Custom Snap Layouts"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))
        content.wantsLayer = true

        let list = NSPopUpButton(frame: NSRect(x: 20, y: 410, width: 280, height: 26))
        list.target = self
        list.action = #selector(selectionChanged)
        self.list = list

        let nameField = NSTextField(frame: NSRect(x: 20, y: 372, width: 280, height: 24))
        nameField.placeholderString = "Layout name"
        self.nameField = nameField

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 70, width: 280, height: 290))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        text.isRichText = false
        text.autoresizingMask = [.width, .height]
        scroll.documentView = text
        self.zonesView = text

        let help = NSTextField(wrappingLabelWithString: "One zone per line: x y width height as fractions from 0 to 1, top-left origin.")
        help.frame = NSRect(x: 20, y: 40, width: 280, height: 28)

        let preview = LayoutPreviewView(frame: NSRect(x: 320, y: 70, width: 380, height: 350))
        self.preview = preview

        let newButton = NSButton(title: "New", target: self, action: #selector(newLayout))
        newButton.frame = NSRect(x: 20, y: 16, width: 70, height: 24)
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveLayout))
        saveButton.frame = NSRect(x: 96, y: 16, width: 70, height: 24)
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteLayout))
        deleteButton.frame = NSRect(x: 172, y: 16, width: 70, height: 24)
        let previewButton = NSButton(title: "Preview", target: self, action: #selector(refreshPreview))
        previewButton.frame = NSRect(x: 320, y: 16, width: 80, height: 24)

        content.addSubview(list)
        content.addSubview(nameField)
        content.addSubview(scroll)
        content.addSubview(help)
        content.addSubview(preview)
        content.addSubview(newButton)
        content.addSubview(saveButton)
        content.addSubview(deleteButton)
        content.addSubview(previewButton)
        window.contentView = content
        return window
    }

    private func reloadList(select id: String? = nil) {
        guard let list else { return }
        list.removeAllItems()
        let layouts = LayoutRegistry.shared.customLayouts
        if layouts.isEmpty {
            list.addItem(withTitle: "(no custom layouts)")
        } else {
            layouts.forEach { list.addItem(withTitle: $0.name) }
            if let id, let index = layouts.firstIndex(where: { $0.id == id }) {
                list.selectItem(at: index)
            }
        }
        selectionChanged()
    }

    private var selected: SnapLayout? {
        let layouts = LayoutRegistry.shared.customLayouts
        let index = list?.indexOfSelectedItem ?? -1
        guard layouts.indices.contains(index) else { return nil }
        return layouts[index]
    }

    @objc private func selectionChanged() {
        guard let layout = selected else {
            nameField?.stringValue = ""
            zonesView?.string = "0 0 0.5 1\n0.5 0 0.5 1\n"
            preview?.layout = nil
            return
        }
        nameField?.stringValue = layout.name
        zonesView?.string = layout.zones.map { "\($0.x) \($0.y) \($0.width) \($0.height)" }.joined(separator: "\n") + "\n"
        preview?.layout = layout
    }

    @objc private func newLayout() {
        let layout = SnapLayout(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: "Custom \(LayoutRegistry.shared.customLayouts.count + 1)",
            zones: LayoutCatalog.twoEqual.zones
        )
        LayoutStore.add(layout)
        reloadList(select: layout.id)
    }

    @objc private func saveLayout() {
        let name = nameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty, let parsed = parseZones(zonesView?.string ?? "") else {
            AppLog.error("custom layout save failed: name or zones invalid")
            return
        }
        let id = selected?.id ?? "custom-\(UUID().uuidString.prefix(8))"
        LayoutStore.add(SnapLayout(id: id, name: name, zones: parsed))
        reloadList(select: id)
        AppLog.info("saved custom layout \(name)")
    }

    @objc private func deleteLayout() {
        guard let selected else { return }
        LayoutStore.remove(id: selected.id)
        reloadList()
    }

    @objc private func refreshPreview() {
        if let parsed = parseZones(zonesView?.string ?? "") {
            preview?.layout = SnapLayout(id: "preview", name: nameField?.stringValue ?? "", zones: parsed)
        }
    }

    private func parseZones(_ text: String) -> [ZoneFractions]? {
        let lines = text.split(whereSeparator: \.isNewline)
        var zones: [ZoneFractions] = []
        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            guard parts.count == 4 else { continue }
            let zone = ZoneFractions(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            if zone.width <= 0 || zone.height <= 0 { return nil }
            zones.append(zone)
        }
        return zones.isEmpty ? nil : zones
    }
}

final class LayoutPreviewView: NSView {
    var layout: SnapLayout? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()

        guard let layout else { return }
        let canvas = bounds.insetBy(dx: 16, dy: 16)
        NSColor.black.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: canvas, xRadius: 8, yRadius: 8).fill()

        for (index, zone) in layout.zones.enumerated() {
            let rect = NSRect(
                x: canvas.minX + canvas.width * zone.x,
                y: canvas.minY + canvas.height * zone.y,
                width: canvas.width * zone.width,
                height: canvas.height * zone.height
            ).insetBy(dx: 4, dy: 4)
            NSColor.systemBlue.withAlphaComponent(0.25).setFill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            path.lineWidth = 2
            path.fill()
            path.stroke()
            let label = NSAttributedString(
                string: "\(index + 1)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            label.draw(at: NSPoint(x: rect.midX - 4, y: rect.midY - 8))
        }
    }
}
