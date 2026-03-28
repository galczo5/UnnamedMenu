import Foundation

final class MenuConfig {
    static let shared = MenuConfig()
    private var data: MenuConfigData

    private init() {
        data = MenuConfigLoader.load()
    }

    var openShortcut: String { data.config!.shortcuts!.open! }
    var openWindowsShortcut: String { data.config!.shortcuts!.openWindows! }

    var theme: String             { data.config!.display!.theme! }
    var searchIcon: String        { data.config!.display!.searchIcon! }
    var searchPlaceholder: String { data.config!.display!.searchPlaceholder! }
    var maxResults: Int           { data.config!.display!.maxResults! }
    var maxResultsAll: Int        { data.config!.display!.maxResultsAll! }

    func reload() {
        data = MenuConfigLoader.load()
    }
}
