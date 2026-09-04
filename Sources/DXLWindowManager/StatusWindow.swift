import AppKit

final class StatusWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            window = makeWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DXL Window Manager"
        window.isReleasedWhenClosed = false
        window.center()

        let view = NSView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "DXL Window Manager is running")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 24, y: 160, width: 372, height: 24)

        let body = NSTextField(wrappingLabelWithString: bodyText)
        body.frame = NSRect(x: 24, y: 56, width: 372, height: 96)

        let access = NSButton(title: "Request Accessibility Access…", target: nil, action: nil)
        access.bezelStyle = .rounded
        access.frame = NSRect(x: 24, y: 20, width: 240, height: 28)
        access.target = self
        access.action = #selector(requestAccess)

        view.addSubview(title)
        view.addSubview(body)
        view.addSubview(access)
        window.contentView = view
        return window
    }

    private var bodyText: String {
        let granted = AccessibilityPermission.isGranted
        let accessLine = granted
            ? "Accessibility is granted. Drag a window to a screen edge, corner, or the top."
            : "Accessibility is not granted yet. Click the button below, enable DXL Window Manager, then drag a window to an edge."
        return "\(accessLine)\n\nLog: \(AppLog.fileURL.path)\nLook for the split-rectangle icon in the menu bar."
    }

    @objc private func requestAccess() {
        AccessibilityPermission.promptIfNeeded()
        AccessibilityPermission.openSystemSettings()
        AppLog.info("status window requested Accessibility")
    }
}
