import Foundation

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
}

/// Remembers the floating size of a window so a later drag can unsnap it.
public final class RestoreStore: @unchecked Sendable {
    public static let shared = RestoreStore()

    private var originals: [WindowKey: Rect] = [:]
    private var snapped: [WindowKey: Rect] = [:]

    public init() {}

    public func original(for key: WindowKey) -> Rect? {
        originals[key]
    }

    public func snappedFrame(for key: WindowKey) -> Rect? {
        snapped[key]
    }

    public func isCurrentlySnapped(key: WindowKey, frame: Rect) -> Bool {
        guard let snappedFrame = snapped[key] else { return false }
        return RestoreMath.isNearlyEqual(frame, snappedFrame)
    }

    public func prepareForSnap(key: WindowKey, currentFrame: Rect) {
        if let snappedFrame = snapped[key], RestoreMath.isNearlyEqual(currentFrame, snappedFrame) {
            return
        }
        originals[key] = currentFrame
    }

    public func markSnapped(key: WindowKey, frame: Rect) {
        snapped[key] = frame
    }

    public func markFloating(key: WindowKey) {
        snapped[key] = nil
        originals[key] = nil
    }
}
