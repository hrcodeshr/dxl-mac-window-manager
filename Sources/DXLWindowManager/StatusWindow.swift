import AppKit

final class StatusWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var bodyField: NSTextField?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        refresh()
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func refresh() {
        bodyField?.stringValue = bodyText
        window?.title = "DXL Window Manager \(AppVersion.string)"
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DXL Window Manager \(AppVersion.string)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let view = NSView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "DXL Window Manager \(AppVersion.string) is running")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 24, y: 220, width: 392, height: 24)

        let body = NSTextField(wrappingLabelWithString: bodyText)
        body.frame = NSRect(x: 24, y: 56, width: 392, height: 156)
        bodyField = body

        let access = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(requestAccess))
        access.bezelStyle = .rounded
        access.frame = NSRect(x: 24, y: 20, width: 220, height: 28)

        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.frame = NSRect(x: 252, y: 20, width: 80, height: 28)

        view.addSubview(title)
        view.addSubview(body)
        view.addSubview(access)
        view.addSubview(close)
        window.contentView = view
        return window
    }

    private var bodyText: String {
        let granted = AccessibilityPermission.isGranted
        let accessLine = granted
            ? "Accessibility is granted. You can close this window. Drag to an edge, a corner, or the top for layouts."
            : "Accessibility is not granted yet. Open Accessibility Settings, enable DXL Window Manager, then close this window."
        return "\(accessLine)\n\nReopen anytime from the menu-bar icon → Show Status Window.\n\nIf macOS still maximizes on top, turn off Desktop & Dock → Drag windows to screen edges to tile.\nLog: \(AppLog.fileURL.path)"
    }

    @objc private func requestAccess() {
        AccessibilityPermission.openSystemSettings()
        AppLog.info("status window opened Accessibility settings")
    }

    @objc private func closeWindow() {
        hide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
