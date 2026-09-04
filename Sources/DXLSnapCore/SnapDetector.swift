import Foundation

public struct SnapPolicy: Equatable, Sendable {
    public var edgeThickness: Double
    public var cornerSize: Double
    public var topPickerThickness: Double

    public static let `default` = SnapPolicy(
        edgeThickness: 20,
        cornerSize: 40,
        topPickerThickness: 80
    )

    public init(edgeThickness: Double, cornerSize: Double, topPickerThickness: Double) {
        self.edgeThickness = edgeThickness
        self.cornerSize = cornerSize
        self.topPickerThickness = topPickerThickness
    }
}

public enum DragTarget: Equatable, Sendable {
    case none
    case maximize
    case layoutPicker
    case zone(layoutID: String, zoneIndex: Int)

    public var layoutID: String? {
        switch self {
        case .none, .layoutPicker:
            return nil
        case .maximize:
            return LayoutCatalog.maximize.id
        case let .zone(layoutID, _):
            return layoutID
        }
    }

    public var zoneIndex: Int? {
        switch self {
        case let .zone(_, zoneIndex):
            return zoneIndex
        case .maximize:
            return 0
        case .none, .layoutPicker:
            return nil
        }
    }
}

public enum SnapDetector {
    /// Resolves a cursor position in top-left coordinates.
    /// `display` is the full monitor (including the menu bar). `visible` is the desktop
    /// under the menu bar and dock. Dragging to the physical top hits the menu bar, so
    /// the picker must use `display`, not only `visible`.
    public static func target(
        cursor: Point,
        screen: Rect,
        policy: SnapPolicy = .default
    ) -> DragTarget {
        target(cursor: cursor, display: screen, visible: screen, policy: policy)
    }

    public static func target(
        cursor: Point,
        display: Rect,
        visible: Rect,
        policy: SnapPolicy = .default
    ) -> DragTarget {
        guard display.contains(cursor) || visible.contains(cursor) else { return .none }

        let corner = min(policy.cornerSize, display.width / 3, display.height / 3)
        let edge = policy.edgeThickness
        let inLeft = cursor.x <= display.minX + edge
        let inRight = cursor.x >= display.maxX - edge
        let inTop = cursor.y <= display.minY + edge
        let inBottom = cursor.y >= display.maxY - edge
        let tightCorner = min(40.0, corner)
        let inTightLeft = cursor.x <= display.minX + tightCorner
        let inTightRight = cursor.x >= display.maxX - tightCorner
        let inTightTop = cursor.y <= display.minY + tightCorner
        let inTightBottom = cursor.y >= display.maxY - tightCorner

        if inTightLeft && inTightTop {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 0)
        }
        if inTightRight && inTightTop {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 1)
        }
        if inTightLeft && inTightBottom {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 2)
        }
        if inTightRight && inTightBottom {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 3)
        }

        let pickerBottom = visible.minY + policy.topPickerThickness
        if cursor.y >= display.minY && cursor.y <= pickerBottom {
            return .layoutPicker
        }

        if inLeft && !inTop && !inBottom {
            return .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 0)
        }
        if inRight && !inTop && !inBottom {
            return .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 1)
        }
        if inTop {
            return .maximize
        }
        if inBottom {
            return .zone(layoutID: LayoutCatalog.topBottom.id, zoneIndex: 1)
        }

        return .none
    }

    public static func remainingZoneIndices(layout: SnapLayout, filled: Int) -> [Int] {
        layout.zones.indices.filter { $0 != filled }
    }

    public static func matchingZone(
        frame: Rect,
        screen: Rect,
        gap: Double,
        layouts: [SnapLayout] = LayoutRegistry.shared.allLayouts
    ) -> (layout: SnapLayout, index: Int)? {
        for layout in layouts {
            for (index, zone) in layout.zones.enumerated() {
                if RestoreMath.isNearlyEqual(frame, zone.frame(in: screen, gap: gap), tolerance: 12) {
                    return (layout, index)
                }
            }
        }
        return nil
    }
}

public struct PickerHit: Equatable, Sendable {
    public var layoutID: String
    public var zoneIndex: Int

    public init(layoutID: String, zoneIndex: Int) {
        self.layoutID = layoutID
        self.zoneIndex = zoneIndex
    }
}

public struct LayoutPickerGeometry: Equatable, Sendable {
    public var bar: Rect
    public var items: [PickerItem]

    public struct PickerItem: Equatable, Sendable {
        public var layout: SnapLayout
        public var frame: Rect
        public var zoneFrames: [Rect]
    }

    public static func make(
        screen: Rect,
        layouts: [SnapLayout] = LayoutRegistry.shared.pickerLayouts,
        anchor: Point? = nil
    ) -> LayoutPickerGeometry {
        let itemWidth = 120.0
        let itemHeight = 80.0
        let gap = 14.0
        let padding = 20.0
        let count = Double(max(layouts.count, 1))
        let barWidth = padding * 2 + count * itemWidth + max(0, count - 1) * gap
        let barHeight = itemHeight + padding * 2 + 18
        var barX = screen.midX - barWidth / 2
        var barY = screen.minY + 20
        if let anchor {
            barX = anchor.x
            barY = anchor.y
        }
        barX = min(max(barX, screen.minX + 8), max(screen.minX + 8, screen.maxX - barWidth - 8))
        barY = min(max(barY, screen.minY + 8), max(screen.minY + 8, screen.maxY - barHeight - 8))
        let bar = Rect(
            x: barX,
            y: barY,
            width: barWidth,
            height: barHeight
        )

        var items: [PickerItem] = []
        items.reserveCapacity(layouts.count)
        for (index, layout) in layouts.enumerated() {
            let frame = Rect(
                x: bar.minX + padding + Double(index) * (itemWidth + gap),
                y: bar.minY + padding,
                width: itemWidth,
                height: itemHeight
            )
            let inner = frame.inset(by: 8)
            let zoneFrames = layout.zones.map { $0.frame(in: inner, gap: 3) }
            items.append(PickerItem(layout: layout, frame: frame, zoneFrames: zoneFrames))
        }

        return LayoutPickerGeometry(bar: bar, items: items)
    }

    public func hitTest(_ cursor: Point, columnFallback: Bool = false) -> PickerHit? {
        for item in items {
            for (index, zone) in item.zoneFrames.enumerated() where zone.contains(cursor) {
                return PickerHit(layoutID: item.layout.id, zoneIndex: index)
            }
            if item.frame.contains(cursor), let first = item.zoneFrames.indices.first {
                return PickerHit(layoutID: item.layout.id, zoneIndex: first)
            }
        }
        if columnFallback {
            for item in items where cursor.x >= item.frame.minX && cursor.x <= item.frame.maxX {
                if let nearest = item.zoneFrames.enumerated().min(by: {
                    abs($0.element.midX - cursor.x) < abs($1.element.midX - cursor.x)
                }) {
                    return PickerHit(layoutID: item.layout.id, zoneIndex: nearest.offset)
                }
            }
        }
        return nil
    }
}
