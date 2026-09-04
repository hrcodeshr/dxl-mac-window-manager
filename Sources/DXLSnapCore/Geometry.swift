import Foundation

/// A point in a top-left origin space (y increases downward).
public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A rectangle in a top-left origin space (y increases downward).
public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func inset(by amount: Double) -> Rect {
        Rect(
            x: x + amount,
            y: y + amount,
            width: max(0, width - amount * 2),
            height: max(0, height - amount * 2)
        )
    }

    public func contains(_ point: Point) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersection(_ other: Rect) -> Rect {
        let x1 = max(minX, other.minX)
        let y1 = max(minY, other.minY)
        let x2 = min(maxX, other.maxX)
        let y2 = min(maxY, other.maxY)
        return Rect(x: x1, y: y1, width: max(0, x2 - x1), height: max(0, y2 - y1))
    }
}

public struct ZoneFractions: Equatable, Sendable, Codable {
    /// Unit rectangle inside a screen, origin top-left, values 0...1.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func frame(in screen: Rect, gap: Double = 0) -> Rect {
        let raw = Rect(
            x: screen.x + screen.width * x,
            y: screen.y + screen.height * y,
            width: screen.width * width,
            height: screen.height * height
        )
        return gap > 0 ? raw.inset(by: gap / 2) : raw
    }
}

public struct SnapLayout: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var zones: [ZoneFractions]

    public init(id: String, name: String, zones: [ZoneFractions]) {
        self.id = id
        self.name = name
        self.zones = zones
    }
}

public enum LayoutCatalog {
    public static let twoEqual = SnapLayout(
        id: "twoEqual",
        name: "Two columns",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 0.5, height: 1),
            ZoneFractions(x: 0.5, y: 0, width: 0.5, height: 1),
        ]
    )

    public static let twoThirdsLeft = SnapLayout(
        id: "twoThirdsLeft",
        name: "Two-thirds left",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 2.0 / 3.0, height: 1),
            ZoneFractions(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
        ]
    )

    public static let twoThirdsRight = SnapLayout(
        id: "twoThirdsRight",
        name: "Two-thirds right",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 1.0 / 3.0, height: 1),
            ZoneFractions(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1),
        ]
    )

    public static let threeColumns = SnapLayout(
        id: "threeColumns",
        name: "Three columns",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 1.0 / 3.0, height: 1),
            ZoneFractions(x: 1.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
            ZoneFractions(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1),
        ]
    )

    public static let leftAndStacked = SnapLayout(
        id: "leftAndStacked",
        name: "Left and stacked",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 0.5, height: 1),
            ZoneFractions(x: 0.5, y: 0, width: 0.5, height: 0.5),
            ZoneFractions(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ]
    )

    public static let stackedAndRight = SnapLayout(
        id: "stackedAndRight",
        name: "Stacked and right",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 0.5, height: 0.5),
            ZoneFractions(x: 0, y: 0.5, width: 0.5, height: 0.5),
            ZoneFractions(x: 0.5, y: 0, width: 0.5, height: 1),
        ]
    )

    public static let quadrants = SnapLayout(
        id: "quadrants",
        name: "Quadrants",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 0.5, height: 0.5),
            ZoneFractions(x: 0.5, y: 0, width: 0.5, height: 0.5),
            ZoneFractions(x: 0, y: 0.5, width: 0.5, height: 0.5),
            ZoneFractions(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ]
    )

    public static let topBottom = SnapLayout(
        id: "topBottom",
        name: "Two rows",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 1, height: 0.5),
            ZoneFractions(x: 0, y: 0.5, width: 1, height: 0.5),
        ]
    )

    public static let maximize = SnapLayout(
        id: "maximize",
        name: "Maximize",
        zones: [
            ZoneFractions(x: 0, y: 0, width: 1, height: 1),
        ]
    )

    public static let builtInPicker: [SnapLayout] = [
        twoEqual,
        twoThirdsLeft,
        threeColumns,
        leftAndStacked,
        quadrants,
        topBottom,
    ]

    public static var pickerLayouts: [SnapLayout] {
        LayoutRegistry.shared.pickerLayouts
    }

    public static func layout(id: String) -> SnapLayout? {
        LayoutRegistry.shared.layout(id: id)
    }

    public static func builtIn(id: String) -> SnapLayout? {
        let all = builtInPicker + [twoThirdsRight, stackedAndRight, maximize]
        return all.first { $0.id == id }
    }
}

public final class LayoutRegistry: @unchecked Sendable {
    public static let shared = LayoutRegistry()

    public var customLayouts: [SnapLayout] = []

    public init() {}

    public var pickerLayouts: [SnapLayout] {
        LayoutCatalog.builtInPicker + customLayouts
    }

    public func layout(id: String) -> SnapLayout? {
        if let builtIn = LayoutCatalog.builtIn(id: id) {
            return builtIn
        }
        return customLayouts.first { $0.id == id }
    }

    public var allLayouts: [SnapLayout] {
        pickerLayouts + [LayoutCatalog.twoThirdsRight, LayoutCatalog.stackedAndRight, LayoutCatalog.maximize]
    }
}
