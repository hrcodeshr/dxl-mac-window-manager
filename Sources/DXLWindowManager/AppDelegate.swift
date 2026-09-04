import AppKit

@main
enum DXLMain {
    static func main() {
        AppLog.infoSync("main entered")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var dragMonitor: DragSnapMonitor?
    private var hotkeys: HotkeyMonitor?
    private var accessTimer: Timer?
    private var statusWindow: StatusWindowController?
    private var servicesRunning = false
    private var lastTrusted: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("launched accessibility=\(AccessibilityPermission.isGranted) log=\(AppLog.fileURL.path)")
        menuBar = MenuBarController(appDelegate: self)
        dragMonitor = DragSnapMonitor()
        hotkeys = HotkeyMonitor()
        statusWindow = StatusWindowController()
        statusWindow?.show()
        refreshAccess()

        accessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAccess()
        }
        if let accessTimer {
            RunLoop.main.add(accessTimer, forMode: .common)
        }
    }

    func refreshAccess() {
        let granted = AccessibilityPermission.isGranted
        if granted && !servicesRunning {
            AppLog.info("accessibility granted; starting snap services")
            dragMonitor?.start()
            hotkeys?.start()
            servicesRunning = true
        } else if !granted && servicesRunning {
            AppLog.info("accessibility lost; stopping snap services")
            dragMonitor?.stop()
            hotkeys?.stop()
            servicesRunning = false
        }
        if lastTrusted != granted {
            lastTrusted = granted
            menuBar?.rebuildMenu()
        }
    }

    func showStatusWindow() {
        statusWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.info("terminating")
    }
}
