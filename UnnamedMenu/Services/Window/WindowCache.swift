import Foundation
import AppKit

enum WindowCache {
    private static var cachePath: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("com.unnamedmenu.windows.json")
    }

    static func rebuild(trigger: String = "") {
        let t0 = Date()
        let items = WindowsGenerator().generateItems()
        let t1 = Date()
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) else { return }
        try? data.write(to: cachePath, options: .atomic)
        let t2 = Date()
        print("[WindowCache] rebuild(\(trigger)): generateItems \(Int(t1.timeIntervalSince(t0) * 1000))ms  write \(Int(t2.timeIntervalSince(t1) * 1000))ms  total \(Int(t2.timeIntervalSince(t0) * 1000))ms")
    }

    static func read() -> String? {
        try? String(contentsOf: cachePath, encoding: .utf8)
    }
}
