import AppKit
import ServiceManagement

final class MenuBarController {
    private let statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "DXL Window Manager")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    func setDragStatus(_ text: String?) {
        statusItem.button?.title = text.map { " \($0)" } ?? ""
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let trusted = AccessibilityPermission.isGranted

        let status = NSMenuItem(
            title: trusted ? "Accessibility: granted" : "Accessibility: needed",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        if !trusted {
            let grant = NSMenuItem(
                title: "Request Accessibility Access…",
                action: #selector(requestAccess),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())

        let snap = NSMenuItem(
            title: "Snap while dragging",
            action: #selector(toggleSnap),
            keyEquivalent: ""
        )
        snap.target = self
        snap.state = Settings.snapEnabled ? .on : .off
        menu.addItem(snap)

        let assist = NSMenuItem(
            title: "Suggest windows after snap",
            action: #selector(toggleAssist),
            keyEquivalent: ""
        )
        assist.target = self
        assist.state = Settings.snapAssistEnabled ? .on : .off
        menu.addItem(assist)

        let green = NSMenuItem(
            title: "Layout picker on green button",
            action: #selector(toggleGreen),
            keyEquivalent: ""
        )
        green.target = self
        green.state = Settings.greenButtonPickerEnabled ? .on : .off
        menu.addItem(green)

        let layouts = NSMenuItem(
            title: "Edit Custom Layouts…",
            action: #selector(editLayouts),
            keyEquivalent: ""
        )
        layouts.target = self
        menu.addItem(layouts)

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Open at login",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let showStatusItem = NSMenuItem(
            title: "Show Status Window",
            action: #selector(showStatus),
            keyEquivalent: ""
        )
        showStatusItem.target = self
        menu.addItem(showStatusItem)

        let openLog = NSMenuItem(
            title: "Open Log",
            action: #selector(openLogFile),
            keyEquivalent: ""
        )
        openLog.target = self
        menu.addItem(openLog)

        let revealLog = NSMenuItem(
            title: "Reveal Log in Finder",
            action: #selector(revealLogFile),
            keyEquivalent: ""
        )
        revealLog.target = self
        menu.addItem(revealLog)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit DXL Window Manager", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func requestAccess() {
        AccessibilityPermission.openSystemSettings()
        appDelegate?.refreshAccess()
        rebuildMenu()
    }

    @objc private func toggleSnap() {
        Settings.snapEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleAssist() {
        Settings.snapAssistEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleGreen() {
        Settings.greenButtonPickerEnabled.toggle()
        rebuildMenu()
    }

    @objc private func editLayouts() {
        appDelegate?.showLayoutEditor()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            AppLog.error("login item failed: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    @objc private func showStatus() {
        appDelegate?.showStatusWindow()
    }

    @objc private func openLogFile() {
        AppLog.info("opening log file")
        AppLog.openInConsole()
    }

    @objc private func revealLogFile() {
        AppLog.revealInFinder()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
