import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

struct WindowsGenerator {
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

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

            if axResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty {
                for window in windows {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                    let windowTitle = titleValue as? String ?? ""
                    let name = windowTitle.isEmpty ? appName : "\(appName) - \(windowTitle)"
                    items.append(["name": name, "command": command, "systemImage": iconValue])
                }
            } else {
                items.append(["name": appName, "command": command, "systemImage": iconValue])
            }
        }

        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
