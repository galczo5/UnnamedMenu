import Foundation

struct MenuConfigData: Codable {
    var config: ConfigSection?

    struct ConfigSection: Codable {
        var shortcuts: ShortcutsConfig?
    }

    struct ShortcutsConfig: Codable {
        var open: String?
        var openWindows: String?
    }

    static let defaults = MenuConfigData(config: ConfigSection(
        shortcuts: ShortcutsConfig(open: "cmd+space", openWindows: "opt+tab")
    ))

    var missingKeys: [String] {
        var missing: [String] = []
        func check<T>(_ val: T?, _ path: String) { if val == nil { missing.append(path) } }
        check(config?.shortcuts?.open,        "config.shortcuts.open")
        check(config?.shortcuts?.openWindows, "config.shortcuts.openWindows")
        return missing
    }

    func mergedWithDefaults() -> MenuConfigData {
        let d = MenuConfigData.defaults.config!
        return MenuConfigData(config: ConfigSection(
            shortcuts: ShortcutsConfig(
                open:        config?.shortcuts?.open        ?? d.shortcuts!.open,
                openWindows: config?.shortcuts?.openWindows ?? d.shortcuts!.openWindows
            )
        ))
    }
}
