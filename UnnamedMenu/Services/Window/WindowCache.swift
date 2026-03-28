import Foundation
import AppKit

enum WindowCache {
    private static var cachePath: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("com.unnamedmenu.windows.json")
    }

    static func rebuild(trigger: String = "", recentPIDs: [pid_t] = []) {
        let t0 = Date()
        let items = WindowsGenerator().generateItems(recentPIDs: recentPIDs)
        let t1 = Date()
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) else { return }
        try? data.write(to: cachePath, options: .atomic)
        let t2 = Date()
        print("[WindowCache] rebuild(\(trigger)): generateItems \(Int(t1.timeIntervalSince(t0) * 1000))ms  write \(Int(t2.timeIntervalSince(t1) * 1000))ms  total \(Int(t2.timeIntervalSince(t0) * 1000))ms")
    }

    static func read() -> String? {
        try? String(contentsOf: cachePath, encoding: .utf8)
    }

    /// Reorder cached items by current visit history (always fresh, updated synchronously on main thread).
    static func reorderedByVisitHistory(_ items: [[String: String]]) -> [[String: String]] {
        func pid(from item: [String: String]) -> pid_t {
            guard let cmd = item["command"],
                  let range = cmd.range(of: "(?<=unix id is )\\d+", options: .regularExpression) else { return 0 }
            return pid_t(cmd[range]) ?? 0
        }

        var groups: [pid_t: [[String: String]]] = [:]
        var seen: [pid_t] = []
        for item in items {
            let p = pid(from: item)
            if groups[p] == nil { seen.append(p) }
            groups[p, default: []].append(item)
        }

        return WindowVisitTracker.shared.ordered(seen).flatMap { groups[$0] ?? [] }
    }
}
