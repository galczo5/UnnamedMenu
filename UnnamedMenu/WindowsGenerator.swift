import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
private func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

struct WindowsGenerator {

    // Enumerates windows from all spaces by probing AX element IDs directly.
    // Standard kAXWindowsAttribute only returns windows on the current space;
    // this approach (borrowed from alt-tab-macos) finds windows on other spaces too.
    private func windowsByBruteForce(_ pid: pid_t) -> [AXUIElement] {
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

    func generateForCLI(allScreens: Bool = false) {
        let options: CGWindowListOption = allScreens
            ? [.excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[]")
            exit(0)
        }

        // Determine current screen filter (CGWindow coords: origin top-left of primary screen)
        let primaryScreenHeight = NSScreen.screens.first.map { $0.frame.height + $0.frame.origin.y } ?? 0
        let currentScreen: NSScreen? = {
            if allScreens { return nil }
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        }()

        // Convert NSScreen frame to CGWindow coordinate space for intersection checks
        func cgFrame(of screen: NSScreen) -> CGRect {
            let f = screen.frame
            return CGRect(x: f.origin.x, y: primaryScreenHeight - f.origin.y - f.height,
                          width: f.width, height: f.height)
        }

        let screenCGFrame = currentScreen.map { cgFrame(of: $0) }

        // Only include user-facing apps (excludes GPU processes, helper services, etc.)
        let regularPIDs = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier })

        // Collect unique PIDs in z-order, preserving app name
        var pids: [pid_t] = []
        var pidToAppName: [pid_t: String] = [:]
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  regularPIDs.contains(pid),
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  !appName.isEmpty else { continue }
            if let screenFrame = screenCGFrame,
               let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] {
                let windowFrame = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                        width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
                guard screenFrame.intersects(windowFrame) else { continue }
            }
            if pidToAppName[pid] == nil {
                pids.append(pid)
                pidToAppName[pid] = appName
            }
        }

        var items: [[String: String]] = []
        for pid in pids {
            guard let appName = pidToAppName[pid] else { continue }
            let command = "osascript -e 'tell application \"System Events\" to set frontmost of first process whose unix id is \(pid) to true'"

            let appBundlePath = NSRunningApplication(processIdentifier: pid)?.bundleURL?.path
            let iconValue = appBundlePath ?? "macwindow"

            // Get windows via standard AX (current space only)
            var axWindows: [AXUIElement] = []
            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue) == .success,
               let windows = windowsValue as? [AXUIElement] {
                axWindows = windows
            }

            if allScreens {
                // Supplement with brute force to get windows from other spaces.
                // Deduplicate by CGWindowID.
                var seenWids = Set<CGWindowID>()
                for w in axWindows {
                    var wid = CGWindowID(0)
                    _AXUIElementGetWindow(w, &wid)
                    if wid != 0 { seenWids.insert(wid) }
                }
                for w in windowsByBruteForce(pid) {
                    var wid = CGWindowID(0)
                    _AXUIElementGetWindow(w, &wid)
                    if wid == 0 || seenWids.insert(wid).inserted {
                        axWindows.append(w)
                    }
                }
            }

            if axWindows.isEmpty {
                items.append(["name": appName, "command": command, "systemImage": iconValue])
            } else {
                var seenTitles = Set<String>()
                for window in axWindows {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                    let windowTitle = titleValue as? String ?? ""
                    guard seenTitles.insert(windowTitle).inserted else { continue }
                    let name = windowTitle.isEmpty ? appName : "\(appName) - \(windowTitle)"
                    items.append(["name": name, "command": command, "systemImage": iconValue])
                }
            }
        }

        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
