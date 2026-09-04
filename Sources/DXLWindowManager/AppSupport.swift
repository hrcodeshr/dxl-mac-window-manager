import Foundation

enum AppSupport {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = base.appendingPathComponent("DXL Window Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var layoutsURL: URL {
        directory.appendingPathComponent("layouts.json")
    }

    static var restoreURL: URL {
        directory.appendingPathComponent("restore.json")
    }
}
