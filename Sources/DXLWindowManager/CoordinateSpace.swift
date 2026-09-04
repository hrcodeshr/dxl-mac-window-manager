import AppKit
import DXLSnapCore

enum CoordinateSpace {
    /// Height of the display that contains Cocoa origin (0,0), used for AX ↔ Cocoa conversion.
    static var primaryHeight: CGFloat {
        let originScreen = NSScreen.screens.first { $0.frame.origin == .zero }
        return originScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0
    }

    static func cocoaPointToTopLeft(_ point: NSPoint) -> Point {
        Point(x: Double(point.x), y: Double(primaryHeight - point.y))
    }

    static func topLeftPointToCocoa(_ point: Point) -> NSPoint {
        NSPoint(x: point.x, y: primaryHeight - CGFloat(point.y))
    }

    static func cocoaRectToTopLeft(_ rect: NSRect) -> Rect {
        Rect(
            x: Double(rect.origin.x),
            y: Double(primaryHeight - rect.origin.y - rect.height),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    static func topLeftRectToCocoa(_ rect: Rect) -> NSRect {
        NSRect(
            x: rect.x,
            y: Double(primaryHeight) - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func screenContaining(cocoaPoint: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(cocoaPoint) } ?? NSScreen.main
    }

    static func visibleTopLeftRect(for screen: NSScreen) -> Rect {
        cocoaRectToTopLeft(screen.visibleFrame)
    }
}
