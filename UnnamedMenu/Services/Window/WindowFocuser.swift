import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

enum WindowFocuser {
    static func focus(pid: pid_t, windowTitle: String, targetWid: CGWindowID = 0) {
        print("[WindowFocuser] focus called: pid=\(pid) windowTitle=\"\(windowTitle)\" targetWid=\(targetWid)")

        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        var axWindows: [AXUIElement] = []
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let windows = windowsValue as? [AXUIElement] {
            axWindows = windows
        }
        print("[WindowFocuser] kAXWindowsAttribute returned \(axWindows.count) windows")

        // If standard AX returned nothing, use brute-force enumeration.
        if axWindows.isEmpty {
            axWindows = windowsByBruteForce(pid)
            print("[WindowFocuser] brute-force returned \(axWindows.count) windows")
        }

        for (i, window) in axWindows.enumerated() {
            var wid = CGWindowID(0)
            _AXUIElementGetWindow(window, &wid)
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""
            var minimizedValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = minimizedValue as? Bool ?? false
            print("[WindowFocuser]   [\(i)] wid=\(wid) title=\"\(title)\" minimized=\(minimized)")
        }

        // Try to find the window by CGWindowID first (most reliable).
        if targetWid != 0 {
            for window in axWindows {
                var wid = CGWindowID(0)
                _AXUIElementGetWindow(window, &wid)
                if wid == targetWid {
                    print("[WindowFocuser] MATCHED by wid=\(targetWid)")
                    raise(window: window, pid: pid)
                    return
                }
            }
            print("[WindowFocuser] NO wid match found for targetWid=\(targetWid)")
        }

        // Fall back to title matching.
        for window in axWindows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? ""
            if title == windowTitle {
                print("[WindowFocuser] MATCHED by title=\"\(windowTitle)\"")
                raise(window: window, pid: pid)
                return
            }
        }

        print("[WindowFocuser] NO match at all — falling back to activate()")
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private static func raise(window: AXUIElement, pid: pid_t) {
        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
           let isMinimized = minimizedValue as? Bool, isMinimized {
            print("[WindowFocuser] unminimizing window")
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        print("[WindowFocuser] AXRaise result: \(raiseResult.rawValue) (0=success)")
        let app = NSRunningApplication(processIdentifier: pid)
        let activateResult = app?.activate() ?? false
        print("[WindowFocuser] activate result: \(activateResult)")
    }

    private static func windowsByBruteForce(_ pid: pid_t) -> [AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var results = [AXUIElement]()
        let start = Date()
        for id: UInt64 in 0..<1000 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: id) { Data($0) })
            if let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() {
                var subrole: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
                   let subroleStr = subrole as? String,
                   [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subroleStr) {
                    results.append(element)
                }
            }
            if Date().timeIntervalSince(start) > 0.1 { break }
        }
        return results
    }
}
