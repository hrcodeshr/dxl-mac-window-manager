import AppKit
import Foundation

enum AppLog {
    private static let queue = DispatchQueue(label: "com.dxl.windowmanager.log")

    static var fileURL: URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("dxl-window-manager.log")
    }

    static func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    static func infoSync(_ message: String) {
        write(level: "INFO", message: message, sync: true)
    }

    static func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    static func openInConsole() {
        NSWorkspace.shared.open(fileURL)
    }

    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static func write(level: String, message: String, sync: Bool = false) {
        let timestamp = iso8601.string(from: Date())
        let line = "\(timestamp) [\(level)] \(message)\n"
        NSLog("%@", "DXL \(level): \(message)")
        let work = {
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        }
        if sync {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
