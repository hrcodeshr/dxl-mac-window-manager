import XCTest
import DXLSnapCore

final class SnapDetectorTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1920, height: 1080)
    let policy = SnapPolicy.default

    func testLeftEdgeSnapsToLeftHalf() {
        let target = SnapDetector.target(
            cursor: Point(x: 4, y: 540),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 0))
    }

    func testRightEdgeSnapsToRightHalf() {
        let target = SnapDetector.target(
            cursor: Point(x: 1916, y: 540),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 1))
    }

    func testTopLeftCornerSnapsToQuadrant() {
        let target = SnapDetector.target(
            cursor: Point(x: 8, y: 8),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 0))
    }

    func testTopCenterOpensLayoutPicker() {
        let target = SnapDetector.target(
            cursor: Point(x: 960, y: 10),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .layoutPicker)
    }

    func testCenterDoesNotSnap() {
        let target = SnapDetector.target(
            cursor: Point(x: 960, y: 540),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .none)
    }

    func testBottomLeftCornerSnapsToQuadrant() {
        let target = SnapDetector.target(
            cursor: Point(x: 8, y: 1072),
            screen: screen,
            policy: policy
        )
        XCTAssertEqual(target, .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 2))
    }

    func testZoneFramesCoverTheScreen() {
        let layout = LayoutCatalog.twoEqual
        let left = layout.zones[0].frame(in: screen)
        let right = layout.zones[1].frame(in: screen)
        XCTAssertEqual(left.width, 960)
        XCTAssertEqual(right.x, 960)
        XCTAssertEqual(left.height, 1080)
    }

    func testPickerHitSelectsZoneInsideDiagram() {
        let picker = LayoutPickerGeometry.make(screen: screen)
        let twoEqual = picker.items.first { $0.layout.id == LayoutCatalog.twoEqual.id }
        XCTAssertNotNil(twoEqual)
        guard let item = twoEqual else { return }
        let hit = picker.hitTest(Point(x: item.zoneFrames[1].midX, y: item.zoneFrames[1].midY))
        XCTAssertEqual(hit, PickerHit(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 1))
    }

    func testRemainingZonesExcludeFilled() {
        let remaining = SnapDetector.remainingZoneIndices(layout: LayoutCatalog.threeColumns, filled: 1)
        XCTAssertEqual(remaining, [0, 2])
    }
}
