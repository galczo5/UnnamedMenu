import Foundation
import Yams

struct MenuConfigLoader {
    static let directoryPath = NSHomeDirectory() + "/.config/unnamed"
    static let filePath = directoryPath + "/menu.yml"

    static func load() -> MenuConfigData {
        let fm = FileManager.default

        if !fm.fileExists(atPath: directoryPath) {
            try? fm.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: filePath) {
            write(MenuConfigData.defaults)
            print("MenuConfig: created default config at \(filePath)")
            return MenuConfigData.defaults
        }

        guard let contents = fm.contents(atPath: filePath),
              let yaml = String(data: contents, encoding: .utf8) else {
            print("MenuConfig: could not read \(filePath), using defaults")
            return MenuConfigData.defaults
        }

        do {
            let parsed = try YAMLDecoder().decode(MenuConfigData.self, from: yaml)
            for key in parsed.missingKeys {
                print("MenuConfig: missing '\(key)', using default")
            }
            return parsed.mergedWithDefaults()
        } catch {
            print("MenuConfig: parse error — \(error.localizedDescription), using defaults")
            return MenuConfigData.defaults
        }
    }

    static func write(_ data: MenuConfigData) {
        let yaml = format(data)
        do {
            try yaml.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("MenuConfig: failed to write config — \(error.localizedDescription)")
        }
    }

    private static func format(_ data: MenuConfigData) -> String {
        let d = MenuConfigData.defaults.config!
        let sh = data.config?.shortcuts ?? d.shortcuts!
        let di = data.config?.display ?? d.display!

        return """
        config:
          shortcuts:
            # Global shortcut to open UnnamedMenu. When already open, cycles selection. Empty string disables.
            # Format: modifier+key (e.g. cmd+space, cmd+shift+o).
            open: "\(sh.open ?? d.shortcuts!.open!)"
            # Global shortcut to open UnnamedMenu in windows mode. When already open, cycles selection. Empty string disables.
            openWindows: "\(sh.openWindows ?? d.shortcuts!.openWindows!)"
          display:
            # Colour scheme: light, dark, system
            theme: "\(di.theme ?? d.display!.theme!)"
            # SF Symbol name shown left of the search field.
            # Browse available icons in the SF Symbols app (install from https://developer.apple.com/sf-symbols/)
            # or run: open "/System/Applications/SF Symbols.app"
            searchIcon: "\(di.searchIcon ?? d.display!.searchIcon!)"
            # Placeholder text in the search field
            searchPlaceholder: "\(di.searchPlaceholder ?? d.display!.searchPlaceholder!)"
            # Maximum results shown in search mode
            maxResults: \(di.maxResults ?? d.display!.maxResults!)
            # Maximum results shown in show-all / windows mode
            maxResultsAll: \(di.maxResultsAll ?? d.display!.maxResultsAll!)
            # Dim the screen behind the launcher panel
            dimEnabled: \(di.dimEnabled ?? d.display!.dimEnabled!)
            # Opacity of the dim overlay (0.0 = invisible, 1.0 = fully black)
            dimOpacity: \(di.dimOpacity ?? d.display!.dimOpacity!)
        """
    }
}
