import XCTest
import DXLSnapCore

final class RestoreMathTests: XCTestCase {
    let screen = Rect(x: 0, y: 0, width: 1920, height: 1080)

    func testNearlyEqualUsesTolerance() {
        let a = Rect(x: 0, y: 0, width: 960, height: 1080)
        let b = Rect(x: 3, y: 2, width: 958, height: 1079)
        XCTAssertTrue(RestoreMath.isNearlyEqual(a, b))
        XCTAssertFalse(RestoreMath.isNearlyEqual(a, Rect(x: 40, y: 0, width: 960, height: 1080)))
    }

    func testFollowCursorKeepsRelativeTitleBarPosition() {
        let snapped = Rect(x: 0, y: 0, width: 960, height: 1080)
        let original = Rect(x: 200, y: 200, width: 640, height: 480)
        let cursor = Point(x: 480, y: 20)
        let restored = RestoreMath.followCursor(
            original: original,
            snapped: snapped,
            cursor: cursor,
            screen: screen
        )
        XCTAssertEqual(restored.width, 640)
        XCTAssertEqual(restored.height, 480)
        XCTAssertEqual(restored.x, 160, accuracy: 0.5)
        XCTAssertEqual(restored.y, 20 - RestoreMath.titleBarOffset, accuracy: 0.5)
    }

    func testFollowCursorClampsToScreen() {
        let snapped = Rect(x: 0, y: 0, width: 1920, height: 1080)
        let original = Rect(x: 0, y: 0, width: 800, height: 600)
        let cursor = Point(x: 10, y: 4)
        let restored = RestoreMath.followCursor(
            original: original,
            snapped: snapped,
            cursor: cursor,
            screen: screen
        )
        XCTAssertGreaterThanOrEqual(restored.x, 0)
        XCTAssertGreaterThanOrEqual(restored.y, 0)
        XCTAssertLessThanOrEqual(restored.maxX, 1920)
        XCTAssertLessThanOrEqual(restored.maxY, 1080)
    }

    func testStoreKeepsOriginalWhenResnapping() {
        let store = RestoreStore()
        let key = WindowKey(pid: 42, windowID: 7)
        let floating = Rect(x: 100, y: 80, width: 700, height: 500)
        let left = Rect(x: 0, y: 0, width: 960, height: 1080)
        let right = Rect(x: 960, y: 0, width: 960, height: 1080)

        store.prepareForSnap(key: key, currentFrame: floating)
        store.markSnapped(key: key, frame: left)
        XCTAssertTrue(store.isCurrentlySnapped(key: key, frame: left))

        store.prepareForSnap(key: key, currentFrame: left)
        store.markSnapped(key: key, frame: right)
        XCTAssertEqual(store.original(for: key), floating)
        XCTAssertTrue(store.isCurrentlySnapped(key: key, frame: right))
    }

    func testStoreClearsAfterUnsnap() {
        let store = RestoreStore()
        let key = WindowKey(pid: 1, windowID: 2)
        store.prepareForSnap(key: key, currentFrame: Rect(x: 10, y: 10, width: 400, height: 300))
        store.markSnapped(key: key, frame: Rect(x: 0, y: 0, width: 960, height: 1080))
        store.markFloating(key: key)
        XCTAssertNil(store.original(for: key))
        XCTAssertFalse(store.isCurrentlySnapped(key: key, frame: Rect(x: 0, y: 0, width: 960, height: 1080)))
    }
}
