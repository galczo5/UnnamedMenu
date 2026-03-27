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

        return """
        config:
          shortcuts:
            # Global shortcut to open UnnamedMenu. When already open, cycles selection. Empty string disables.
            # Format: modifier+key (e.g. cmd+space, cmd+shift+o).
            open: "\(sh.open ?? d.shortcuts!.open!)"
            # Global shortcut to open UnnamedMenu in windows mode. When already open, cycles selection. Empty string disables.
            openWindows: "\(sh.openWindows ?? d.shortcuts!.openWindows!)"
        """
    }
}
