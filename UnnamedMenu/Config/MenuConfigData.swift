import Foundation

struct MenuConfigData: Codable {
    var config: ConfigSection?

    struct ConfigSection: Codable {
        var shortcuts: ShortcutsConfig?
        var display: DisplayConfig?
    }

    struct ShortcutsConfig: Codable {
        var open: String?
        var openWindows: String?
    }

    struct DisplayConfig: Codable {
        var theme: String?
        var searchIcon: String?
        var searchPlaceholder: String?
        var maxResults: Int?
        var maxResultsAll: Int?
        var dimEnabled: Bool?
        var dimOpacity: Double?
    }

    static let defaults = MenuConfigData(config: ConfigSection(
        shortcuts: ShortcutsConfig(open: "cmd+space", openWindows: "opt+tab"),
        display: DisplayConfig(
            theme: "light",
            searchIcon: "magnifyingglass",
            searchPlaceholder: "Search commands…",
            maxResults: 5,
            maxResultsAll: 25,
            dimEnabled: true,
            dimOpacity: 0.6
        )
    ))

    var missingKeys: [String] {
        var missing: [String] = []
        func check<T>(_ val: T?, _ path: String) { if val == nil { missing.append(path) } }
        check(config?.shortcuts?.open,              "config.shortcuts.open")
        check(config?.shortcuts?.openWindows,       "config.shortcuts.openWindows")
        check(config?.display?.theme,               "config.display.theme")
        check(config?.display?.searchIcon,          "config.display.searchIcon")
        check(config?.display?.searchPlaceholder,   "config.display.searchPlaceholder")
        check(config?.display?.maxResults,          "config.display.maxResults")
        check(config?.display?.maxResultsAll,       "config.display.maxResultsAll")
        check(config?.display?.dimEnabled,          "config.display.dimEnabled")
        check(config?.display?.dimOpacity,          "config.display.dimOpacity")
        return missing
    }

    func mergedWithDefaults() -> MenuConfigData {
        let d = MenuConfigData.defaults.config!
        return MenuConfigData(config: ConfigSection(
            shortcuts: ShortcutsConfig(
                open:        config?.shortcuts?.open        ?? d.shortcuts!.open,
                openWindows: config?.shortcuts?.openWindows ?? d.shortcuts!.openWindows
            ),
            display: DisplayConfig(
                theme:             config?.display?.theme             ?? d.display!.theme,
                searchIcon:        config?.display?.searchIcon        ?? d.display!.searchIcon,
                searchPlaceholder: config?.display?.searchPlaceholder ?? d.display!.searchPlaceholder,
                maxResults:        config?.display?.maxResults        ?? d.display!.maxResults,
                maxResultsAll:     config?.display?.maxResultsAll     ?? d.display!.maxResultsAll,
                dimEnabled:        config?.display?.dimEnabled        ?? d.display!.dimEnabled,
                dimOpacity:        config?.display?.dimOpacity        ?? d.display!.dimOpacity
            )
        ))
    }
}
