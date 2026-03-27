import Foundation

final class MenuConfig {
    static let shared = MenuConfig()
    private var data: MenuConfigData

    private init() {
        data = MenuConfigLoader.load()
    }

    var openShortcut: String { data.config!.shortcuts!.open! }
    var openWindowsShortcut: String { data.config!.shortcuts!.openWindows! }

    func reload() {
        data = MenuConfigLoader.load()
    }
}
