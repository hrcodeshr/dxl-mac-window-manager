import Foundation

public struct CodableRect: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ rect: Rect) {
        x = rect.x
        y = rect.y
        width = rect.width
        height = rect.height
    }

    public var rect: Rect {
        Rect(x: x, y: y, width: width, height: height)
    }
}

public struct WindowKey: Hashable, Sendable {
    public var pid: Int32
    public var windowID: UInt32
    public var title: String

    public init(pid: Int32, windowID: UInt32, title: String = "") {
        self.pid = pid
        self.windowID = windowID
        self.title = windowID == 0 ? title : ""
    }
}

public enum RestoreMath {
    public static let defaultTolerance = 8.0
    public static let titleBarOffset = 16.0

    public static func isNearlyEqual(_ a: Rect, _ b: Rect, tolerance: Double = defaultTolerance) -> Bool {
        abs(a.x - b.x) < tolerance
            && abs(a.y - b.y) < tolerance
            && abs(a.width - b.width) < tolerance
            && abs(a.height - b.height) < tolerance
    }

    /// Resize a snapped window back to its original size, keeping the cursor on the title bar.
    public static func followCursor(
        original: Rect,
        snapped: Rect,
        cursor: Point,
        screen: Rect
    ) -> Rect {
        let width = min(original.width, screen.width)
        let height = min(original.height, screen.height)
        let denom = max(snapped.width, 1)
        let ratio = min(1, max(0, (cursor.x - snapped.x) / denom))
        var x = cursor.x - ratio * width
        var y = cursor.y - titleBarOffset
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - height))
        return Rect(x: x, y: y, width: width, height: height)
    }

    public static func defaultFloating(on screen: Rect) -> Rect {
        Rect(
            x: screen.x + screen.width * 0.2,
            y: screen.y + screen.height * 0.15,
            width: screen.width * 0.6,
            height: screen.height * 0.7
        )
    }
}

/// Remembers the floating size of a window so a later drag can unsnap it.
public final class RestoreStore: @unchecked Sendable {
    public static let shared = RestoreStore()

    private var originals: [WindowKey: Rect] = [:]
    private var snapped: [WindowKey: Rect] = [:]
    private var byTitle: [String: Rect] = [:]
    public var persistURL: URL?

    public init() {}

    public func original(for key: WindowKey) -> Rect? {
        originals[key] ?? titleOriginal(key.title)
    }

    public func snappedFrame(for key: WindowKey) -> Rect? {
        snapped[key]
    }

    public func isCurrentlySnapped(key: WindowKey, frame: Rect) -> Bool {
        if let snappedFrame = snapped[key] {
            return RestoreMath.isNearlyEqual(frame, snappedFrame)
        }
        return false
    }

    public func prepareForSnap(key: WindowKey, currentFrame: Rect) {
        if let snappedFrame = snapped[key], RestoreMath.isNearlyEqual(currentFrame, snappedFrame) {
            return
        }
        originals[key] = currentFrame
        if !key.title.isEmpty {
            byTitle[key.title] = currentFrame
        }
        persist()
    }

    public func markSnapped(key: WindowKey, frame: Rect) {
        snapped[key] = frame
        persist()
    }

    public func markFloating(key: WindowKey) {
        snapped[key] = nil
        originals[key] = nil
        if !key.title.isEmpty {
            byTitle[key.title] = nil
        }
        persist()
    }

    public func load() {
        guard let persistURL, let data = try? Data(contentsOf: persistURL) else { return }
        guard let file = try? JSONDecoder().decode(PersistFile.self, from: data) else { return }
        byTitle = Dictionary(uniqueKeysWithValues: file.titles.map { ($0.key, $0.value.rect) })
    }

    private func titleOriginal(_ title: String) -> Rect? {
        title.isEmpty ? nil : byTitle[title]
    }

    private func persist() {
        guard let persistURL else { return }
        let file = PersistFile(titles: byTitle.map { PersistEntry(key: $0.key, value: CodableRect($0.value)) })
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(at: persistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistURL, options: .atomic)
    }

    private struct PersistFile: Codable {
        var titles: [PersistEntry]
    }

    private struct PersistEntry: Codable {
        var key: String
        var value: CodableRect
    }
}
