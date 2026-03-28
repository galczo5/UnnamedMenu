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

    func generateItems(recentPIDs: [pid_t] = []) -> [[String: String]] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let screenCGFrame: CGRect? = nil

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

        // Reorder by recency when a history is provided.
        if !recentPIDs.isEmpty {
            let pidsSet = Set(pids)
            var sorted = recentPIDs.filter { pidsSet.contains($0) }
            let seen = Set(sorted)
            sorted += pids.filter { !seen.contains($0) }
            // Move the current app (front of recency list) to the end so the
            // previously visited app appears first.
            if sorted.count > 1 { sorted.append(sorted.removeFirst()) }
            pids = sorted
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

            if axWindows.isEmpty {
                items.append(["name": appName, "command": command, "pid": "\(pid)", "systemImage": iconValue])
            } else {
                var seenTitles = Set<String>()
                for window in axWindows {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                    let windowTitle = titleValue as? String ?? ""
                    guard seenTitles.insert(windowTitle).inserted else { continue }
                    let name = windowTitle.isEmpty ? appName : "\(appName) - \(windowTitle)"
                    var item = ["name": name, "command": command, "pid": "\(pid)", "windowTitle": windowTitle, "systemImage": iconValue]
                    var wid = CGWindowID(0)
                    _AXUIElementGetWindow(window, &wid)
                    if wid != 0 { item["wid"] = "\(wid)" }
                    items.append(item)
                }
            }
        }

        return items
    }

    func generateForCLI() {
        let items = generateItems()
        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
