import Foundation
import CoreGraphics
import ApplicationServices

struct WindowsGenerator {
    func generateForCLI() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[]")
            exit(0)
        }

        // Collect unique PIDs in z-order, preserving app name
        var pids: [pid_t] = []
        var pidToAppName: [pid_t: String] = [:]
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  !appName.isEmpty else { continue }
            if pidToAppName[pid] == nil {
                pids.append(pid)
                pidToAppName[pid] = appName
            }
        }

        var items: [[String: String]] = []
        for pid in pids {
            guard let appName = pidToAppName[pid] else { continue }
            let command = "osascript -e 'tell application \"System Events\" to set frontmost of first process whose unix id is \(pid) to true'"

            let appElement = AXUIElementCreateApplication(pid)
            var windowsValue: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

            if axResult == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty {
                for window in windows {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                    let windowTitle = titleValue as? String ?? ""
                    let name = windowTitle.isEmpty ? appName : windowTitle
                    items.append(["name": name, "command": command, "systemImage": "macwindow"])
                }
            } else {
                items.append(["name": appName, "command": command, "systemImage": "macwindow"])
            }
        }

        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
