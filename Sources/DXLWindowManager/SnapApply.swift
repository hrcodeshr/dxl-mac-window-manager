import Foundation
import DXLSnapCore

enum SnapApply {
    @discardableResult
    static func snap(_ window: AXWindow, to frame: Rect, reason: String) -> Bool {
        let key = window.restoreKey
        if let current = window.frame {
            RestoreStore.shared.prepareForSnap(key: key, currentFrame: current)
        }
        let ok = window.setFrame(frame)
        if ok {
            RestoreStore.shared.markSnapped(key: key, frame: frame)
            AppLog.info("snap \(reason) pid=\(window.pid) id=\(window.windowID) title=\(window.title ?? "") frame=\(describe(frame))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                _ = window.setFrame(frame)
            }
        } else {
            AppLog.error("snap failed \(reason) pid=\(window.pid) id=\(window.windowID)")
        }
        return ok
    }

    private static func describe(_ rect: Rect) -> String {
        String(format: "%.0f,%.0f %.0fx%.0f", rect.x, rect.y, rect.width, rect.height)
    }
}
