import AppKit
import ApplicationServices
import DXLSnapCore

@_silgen_name("_AXUIElementGetWindow")
func DXL_AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

struct AXWindow {
    let element: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID

    var restoreKey: WindowKey {
        WindowKey(pid: pid, windowID: UInt32(windowID), title: title ?? "")
    }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var title: String? { string(kAXTitleAttribute) }

    var frame: Rect? {
        guard let origin = position, let size = size else { return nil }
        return Rect(x: origin.x, y: origin.y, width: size.x, height: size.y)
    }

    var position: Point? {
        guard let value = copy(kAXPositionAttribute) else { return nil }
        var point = CGPoint.zero
        let ok = AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return ok ? Point(x: Double(point.x), y: Double(point.y)) : nil
    }

    var size: Point? {
        guard let value = copy(kAXSizeAttribute) else { return nil }
        var cgSize = CGSize.zero
        let ok = AXValueGetValue(value as! AXValue, .cgSize, &cgSize)
        return ok ? Point(x: Double(cgSize.width), y: Double(cgSize.height)) : nil
    }

    var zoomButtonFrame: Rect? {
        guard let button = copy(kAXZoomButtonAttribute) else { return nil }
        let element = button as! AXUIElement
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard
            let posValue,
            let sizeValue,
            AXValueGetValue(posValue as! AXValue, .cgPoint, &origin),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return Rect(x: Double(origin.x), y: Double(origin.y), width: Double(size.width), height: Double(size.height))
    }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        return result == .success && settable.boolValue
    }

    @discardableResult
    func setFrame(_ rect: Rect) -> Bool {
        var origin = CGPoint(x: rect.x, y: rect.y)
        var cgSize = CGSize(width: rect.width, height: rect.height)
        guard
            let posValue = AXValueCreate(.cgPoint, &origin),
            let sizeValue = AXValueCreate(.cgSize, &cgSize)
        else { return false }

        // Position, then size, then position again. Many apps clamp size and shift origin.
        let first = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        let second = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        return first == .success || second == .success
    }

    func bringToFront() {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            element
        )
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])

        // Activation can raise the app's previously focused window, so assert the
        // selected window again after AppKit finishes bringing the app forward.
        let selectedElement = element
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let selectedApp = AXUIElementCreateApplication(self.pid)
            AXUIElementSetAttributeValue(
                selectedApp,
                kAXFocusedWindowAttribute as CFString,
                selectedElement
            )
            AXUIElementPerformAction(selectedElement, kAXRaiseAction as CFString)
        }
    }

    private func copy(_ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private func string(_ attribute: String) -> String? {
        copy(attribute) as? String
    }
}

enum WindowEngine {
    static var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCaptureAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        AppLog.info("screen recording permission granted=\(granted)")
        if !granted,
           let url = URL(
               string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
           ) {
            NSWorkspace.shared.open(url)
        }
        return granted
    }

    static func windowAtCocoaPoint(_ point: NSPoint) -> AXWindow? {
        let quartzPoint = CGPoint(x: point.x, y: CoordinateSpace.primaryHeight - point.y)
        guard let info = windowInfo(at: quartzPoint) else {
            return axWindow(atQuartzPoint: quartzPoint)
        }
        return axWindow(pid: info.pid, matching: info.bounds) ?? axWindow(atQuartzPoint: quartzPoint)
    }

    static func focusedWindow() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard result == .success, let window = focused else { return nil }
        return make(element: window as! AXUIElement, pid: app.processIdentifier)
    }

    static func candidateWindows(excluding excludedPID: pid_t?) -> [SnapCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<Int>()
        var candidates: [SnapCandidate] = []
        let canCapture = hasScreenCaptureAccess

        for entry in list {
            guard
                let windowPID = ownerPID(from: entry[kCGWindowOwnerPID as String]),
                windowPID != ourPID,
                windowPID != excludedPID,
                let layer = number(entry[kCGWindowLayer as String])?.intValue,
                layer == 0,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let x = cgFloat(boundsDict["X"]),
                let y = cgFloat(boundsDict["Y"]),
                let w = cgFloat(boundsDict["Width"]),
                let h = cgFloat(boundsDict["Height"]),
                w >= 120, h >= 80
            else { continue }

            let windowNumber = number(entry[kCGWindowNumber as String])?.intValue ?? 0
            if windowNumber != 0 {
                if seen.contains(windowNumber) { continue }
                seen.insert(windowNumber)
            }

            let appName = entry[kCGWindowOwnerName as String] as? String ?? "Window"
            let windowName = (entry[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = windowName.flatMap { $0.isEmpty ? nil : $0 } ?? appName
            let app = NSRunningApplication(processIdentifier: windowPID)
            candidates.append(
                SnapCandidate(
                    pid: windowPID,
                    windowID: CGWindowID(windowNumber),
                    appName: appName,
                    title: title,
                    icon: app?.icon,
                    thumbnail: canCapture ? thumbnail(for: CGWindowID(windowNumber)) : nil,
                    bounds: Rect(x: Double(x), y: Double(y), width: Double(w), height: Double(h))
                )
            )
            if candidates.count == 9 {
                break
            }
        }

        return candidates
    }

    private static func thumbnail(for windowID: CGWindowID) -> NSImage? {
        guard windowID != kCGNullWindowID,
              let image = CGWindowListCreateImage(
                  .null,
                  .optionIncludingWindow,
                  windowID,
                  [.boundsIgnoreFraming, .nominalResolution]
              )
        else {
            return nil
        }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    static func window(forPID pid: pid_t, matching bounds: Rect? = nil) -> AXWindow? {
        if let bounds {
            return axWindow(pid: pid, matching: bounds)
        }
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = windows(of: appElement) else { return nil }
        return windows.first.map { make(element: $0, pid: pid) }
    }

    private static func ownerPID(from value: Any?) -> pid_t? {
        if let number = value as? NSNumber {
            return Int32(truncating: number)
        }
        return nil
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        return value as? CGFloat
    }

    private struct WindowInfo {
        var pid: pid_t
        var bounds: Rect
    }

    private static func windowInfo(at quartzPoint: CGPoint) -> WindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ourPID = ProcessInfo.processInfo.processIdentifier

        for entry in list {
            guard
                let owner = ownerPID(from: entry[kCGWindowOwnerPID as String]),
                owner != ourPID,
                let layer = number(entry[kCGWindowLayer as String])?.intValue,
                layer == 0,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let x = cgFloat(boundsDict["X"]),
                let y = cgFloat(boundsDict["Y"]),
                let w = cgFloat(boundsDict["Width"]),
                let h = cgFloat(boundsDict["Height"])
            else { continue }

            let bounds = CGRect(x: x, y: y, width: w, height: h)
            if bounds.contains(quartzPoint) {
                return WindowInfo(
                    pid: owner,
                    bounds: Rect(x: Double(x), y: Double(y), width: Double(w), height: Double(h))
                )
            }
        }
        return nil
    }

    private static func axWindow(atQuartzPoint point: CGPoint) -> AXWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if let window = windowElement(from: element) {
            return make(element: window, pid: pid)
        }
        return nil
    }

    private static func axWindow(pid: pid_t, matching bounds: Rect) -> AXWindow? {
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows = windows(of: appElement) else { return nil }
        let matches = windows.compactMap { element -> (AXUIElement, Double)? in
            let window = make(element: element, pid: pid)
            guard let frame = window.frame else { return nil }
            let overlap = frame.intersection(bounds)
            let area = overlap.width * overlap.height
            return area > 0 ? (element, area) : nil
        }
        guard let best = matches.max(by: { $0.1 < $1.1 }) else { return nil }
        return make(element: best.0, pid: pid)
    }

    private static func make(element: AXUIElement, pid: pid_t) -> AXWindow {
        AXWindow(element: element, pid: pid, windowID: readWindowID(element))
    }

    private static func readWindowID(_ element: AXUIElement) -> CGWindowID {
        var identifier: CGWindowID = 0
        let result = DXL_AXUIElementGetWindow(element, &identifier)
        return result == .success ? identifier : 0
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement]? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func windowElement(from element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<8 {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
            if (role as? String) == kAXWindowRole {
                return current
            }
            var parent: AnyObject?
            let result = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent)
            guard result == .success, let parent else { return nil }
            current = parent as! AXUIElement
        }
        return nil
    }
}

struct SnapCandidate {
    var pid: pid_t
    var windowID: CGWindowID
    var appName: String
    var title: String
    var icon: NSImage?
    var thumbnail: NSImage?
    var bounds: Rect
}
