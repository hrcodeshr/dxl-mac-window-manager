import Foundation

public struct SnapPolicy: Equatable, Sendable {
    public var edgeThickness: Double
    public var cornerSize: Double
    public var topPickerThickness: Double

    public static let `default` = SnapPolicy(
        edgeThickness: 18,
        cornerSize: 80,
        topPickerThickness: 32
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
    /// Resolves a cursor position in local top-left screen coordinates.
    public static func target(
        cursor: Point,
        screen: Rect,
        policy: SnapPolicy = .default
    ) -> DragTarget {
        guard screen.contains(cursor) else { return .none }

        let corner = min(policy.cornerSize, screen.width / 3, screen.height / 3)
        let edge = policy.edgeThickness
        let inLeft = cursor.x <= screen.minX + edge
        let inRight = cursor.x >= screen.maxX - edge
        let inTop = cursor.y <= screen.minY + edge
        let inBottom = cursor.y >= screen.maxY - edge
        let inLeftCorner = cursor.x <= screen.minX + corner
        let inRightCorner = cursor.x >= screen.maxX - corner
        let inTopCorner = cursor.y <= screen.minY + corner
        let inBottomCorner = cursor.y >= screen.maxY - corner

        if inLeftCorner && inTopCorner {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 0)
        }
        if inRightCorner && inTopCorner {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 1)
        }
        if inLeftCorner && inBottomCorner {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 2)
        }
        if inRightCorner && inBottomCorner {
            return .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 3)
        }

        if cursor.y <= screen.minY + policy.topPickerThickness {
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
        layouts: [SnapLayout] = LayoutCatalog.pickerLayouts
    ) -> LayoutPickerGeometry {
        let itemWidth = 92.0
        let itemHeight = 62.0
        let gap = 12.0
        let padding = 16.0
        let count = Double(layouts.count)
        let barWidth = padding * 2 + count * itemWidth + max(0, count - 1) * gap
        let barHeight = itemHeight + padding * 2
        let bar = Rect(
            x: screen.midX - barWidth / 2,
            y: screen.minY + 12,
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

    public func hitTest(_ cursor: Point) -> PickerHit? {
        for item in items {
            for (index, zone) in item.zoneFrames.enumerated() where zone.contains(cursor) {
                return PickerHit(layoutID: item.layout.id, zoneIndex: index)
            }
            if item.frame.contains(cursor), let first = item.zoneFrames.indices.first {
                return PickerHit(layoutID: item.layout.id, zoneIndex: first)
            }
        }
        return nil
    }
}
