import Foundation
import DXLSnapCore

@main
enum DXLSnapCoreCheck {
    static func main() {
        var failures = 0

        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            if passed {
                print("ok   \(name)")
            } else {
                failures += 1
                let suffix = detail.isEmpty ? "" : " — \(detail)"
                print("FAIL \(name)\(suffix)")
            }
        }

        func close(_ a: Double, _ b: Double, _ accuracy: Double = 0.5) -> Bool {
            abs(a - b) <= accuracy
        }

        let screen = Rect(x: 0, y: 0, width: 1920, height: 1080)
        let policy = SnapPolicy.default

        check(
            "left edge snaps to left half",
            SnapDetector.target(cursor: Point(x: 4, y: 540), screen: screen, policy: policy)
                == .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 0)
        )
        check(
            "right edge snaps to right half",
            SnapDetector.target(cursor: Point(x: 1916, y: 540), screen: screen, policy: policy)
                == .zone(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 1)
        )
        check(
            "top-left corner snaps to quadrant",
            SnapDetector.target(cursor: Point(x: 8, y: 8), screen: screen, policy: policy)
                == .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 0)
        )
        check(
            "top center opens layout picker",
            SnapDetector.target(cursor: Point(x: 960, y: 10), screen: screen, policy: policy)
                == .layoutPicker
        )
        check(
            "deeper top strip still opens layout picker",
            SnapDetector.target(cursor: Point(x: 960, y: 50), screen: screen, policy: policy)
                == .layoutPicker
        )
        let display = Rect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = Rect(x: 0, y: 25, width: 1920, height: 1055)
        check(
            "menu-bar strip still opens layout picker",
            SnapDetector.target(
                cursor: Point(x: 960, y: 8),
                display: display,
                visible: visible,
                policy: policy
            ) == .layoutPicker
        )
        check(
            "center does not snap",
            SnapDetector.target(cursor: Point(x: 960, y: 540), screen: screen, policy: policy)
                == .none
        )
        check(
            "bottom-left corner snaps to quadrant",
            SnapDetector.target(cursor: Point(x: 8, y: 1072), screen: screen, policy: policy)
                == .zone(layoutID: LayoutCatalog.quadrants.id, zoneIndex: 2)
        )

        let left = LayoutCatalog.twoEqual.zones[0].frame(in: screen)
        let right = LayoutCatalog.twoEqual.zones[1].frame(in: screen)
        check("two-column left width", close(left.width, 960) && close(left.height, 1080))
        check("two-column right origin", close(right.x, 960))

        let picker = LayoutPickerGeometry.make(screen: screen)
        if let item = picker.items.first(where: { $0.layout.id == LayoutCatalog.twoEqual.id }) {
            let hit = picker.hitTest(Point(x: item.zoneFrames[1].midX, y: item.zoneFrames[1].midY))
            check(
                "picker hit selects zone",
                hit == PickerHit(layoutID: LayoutCatalog.twoEqual.id, zoneIndex: 1)
            )
        } else {
            check("picker includes two-equal layout", false)
        }

        check(
            "remaining zones exclude filled",
            SnapDetector.remainingZoneIndices(layout: LayoutCatalog.threeColumns, filled: 1) == [0, 2]
        )

        let a = Rect(x: 0, y: 0, width: 960, height: 1080)
        let b = Rect(x: 3, y: 2, width: 958, height: 1079)
        check("nearly equal within tolerance", RestoreMath.isNearlyEqual(a, b))
        check(
            "nearly equal rejects distant frame",
            !RestoreMath.isNearlyEqual(a, Rect(x: 40, y: 0, width: 960, height: 1080))
        )

        let restored = RestoreMath.followCursor(
            original: Rect(x: 200, y: 200, width: 640, height: 480),
            snapped: Rect(x: 0, y: 0, width: 960, height: 1080),
            cursor: Point(x: 480, y: 20),
            screen: screen
        )
        check(
            "follow cursor keeps relative title-bar position",
            close(restored.width, 640)
                && close(restored.height, 480)
                && close(restored.x, 160)
                && close(restored.y, 20 - RestoreMath.titleBarOffset)
        )

        let clamped = RestoreMath.followCursor(
            original: Rect(x: 0, y: 0, width: 800, height: 600),
            snapped: Rect(x: 0, y: 0, width: 1920, height: 1080),
            cursor: Point(x: 10, y: 4),
            screen: screen
        )
        check(
            "follow cursor clamps to screen",
            clamped.x >= 0 && clamped.y >= 0 && clamped.maxX <= 1920 && clamped.maxY <= 1080
        )

        let store = RestoreStore()
        let key = WindowKey(pid: 42, windowID: 7)
        let floating = Rect(x: 100, y: 80, width: 700, height: 500)
        let leftSnap = Rect(x: 0, y: 0, width: 960, height: 1080)
        let rightSnap = Rect(x: 960, y: 0, width: 960, height: 1080)
        store.prepareForSnap(key: key, currentFrame: floating)
        store.markSnapped(key: key, frame: leftSnap)
        store.prepareForSnap(key: key, currentFrame: leftSnap)
        store.markSnapped(key: key, frame: rightSnap)
        check(
            "store keeps original when resnapping",
            store.original(for: key) == floating && store.isCurrentlySnapped(key: key, frame: rightSnap)
        )

        let store2 = RestoreStore()
        let key2 = WindowKey(pid: 1, windowID: 2)
        store2.prepareForSnap(key: key2, currentFrame: Rect(x: 10, y: 10, width: 400, height: 300))
        store2.markSnapped(key: key2, frame: Rect(x: 0, y: 0, width: 960, height: 1080))
        store2.markFloating(key: key2)
        check(
            "store clears after unsnap",
            store2.original(for: key2) == nil
                && !store2.isCurrentlySnapped(
                    key: key2,
                    frame: Rect(x: 0, y: 0, width: 960, height: 1080)
                )
        )

        let snappedLeft = LayoutCatalog.twoEqual.zones[0].frame(in: screen, gap: 8)
        if let match = SnapDetector.matchingZone(frame: snappedLeft, screen: screen, gap: 8) {
            check("matching zone finds left half", match.layout.id == LayoutCatalog.twoEqual.id && match.index == 0)
        } else {
            check("matching zone finds left half", false)
        }

        let custom = SnapLayout(
            id: "custom-test",
            name: "Custom test",
            zones: [ZoneFractions(x: 0, y: 0, width: 0.25, height: 1), ZoneFractions(x: 0.25, y: 0, width: 0.75, height: 1)]
        )
        LayoutRegistry.shared.customLayouts = [custom]
        check("registry exposes custom layout", LayoutCatalog.layout(id: "custom-test")?.name == "Custom test")
        let customPicker = LayoutPickerGeometry.make(screen: screen)
        check("picker includes custom layout", customPicker.items.contains { $0.layout.id == "custom-test" })
        LayoutRegistry.shared.customLayouts = []

        let fallback = RestoreMath.defaultFloating(on: screen)
        check("default floating is smaller than the screen", fallback.width < screen.width && fallback.height < screen.height)

        if failures == 0 {
            print("All checks passed.")
            exit(0)
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }
}
