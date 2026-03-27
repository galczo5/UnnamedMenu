import Foundation
import CoreGraphics

struct WindowsGenerator {
    func generateForCLI() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[]")
            exit(0)
        }

        var items: [[String: String]] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  !appName.isEmpty else { continue }

            let windowTitle = info[kCGWindowName as String] as? String ?? ""
            let displayName = windowTitle.isEmpty ? appName : "\(windowTitle) — \(appName)"
            let command = "osascript -e 'tell application \"System Events\" to set frontmost of first process whose unix id is \(pid) to true'"

            items.append([
                "name": displayName,
                "command": command,
                "systemImage": "macwindow"
            ])
        }

        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
