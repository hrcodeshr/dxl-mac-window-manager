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
        NSScreen.screens.first { $0.frame.insetBy(dx: -4, dy: -4).contains(cocoaPoint) }
            ?? NSScreen.main
    }

    /// Top-left space for snap targeting on one display. Y = 0 at that screen's physical top.
    static func snapContext(at cocoaPoint: NSPoint = NSEvent.mouseLocation) -> ScreenSnapContext? {
        guard let screen = screenContaining(cocoaPoint: cocoaPoint) else { return nil }
        return ScreenSnapContext(screen: screen, cocoaCursor: cocoaPoint)
    }

    static func visibleTopLeftRect(for screen: NSScreen) -> Rect {
        cocoaRectToTopLeft(screen.visibleFrame)
    }

    static func displayTopLeftRect(for screen: NSScreen) -> Rect {
        cocoaRectToTopLeft(screen.frame)
    }
}

struct ScreenSnapContext {
    let screen: NSScreen
    let cocoaCursor: NSPoint
    let cursor: Point
    let display: Rect
    let visible: Rect

    init(screen: NSScreen, cocoaCursor: NSPoint) {
        self.screen = screen
        self.cocoaCursor = cocoaCursor
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        cursor = Point(x: Double(cocoaCursor.x), y: Double(frame.maxY - cocoaCursor.y))
        display = Rect(x: Double(frame.minX), y: 0, width: Double(frame.width), height: Double(frame.height))
        visible = Rect(
            x: Double(visibleFrame.minX),
            y: Double(frame.maxY - visibleFrame.maxY),
            width: Double(visibleFrame.width),
            height: Double(visibleFrame.height)
        )
    }

    func cocoaRect(fromLocal rect: Rect) -> NSRect {
        NSRect(
            x: rect.x,
            y: Double(screen.frame.maxY) - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
