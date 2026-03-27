import Foundation

enum MenuLoader {
    static let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/unnamed/menu", isDirectory: true)
    }()

    static func load() -> [CommandItem] {
        let fm = FileManager.default
        print("[MenuLoader] Scanning \(configURL.path)")
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: configURL, includingPropertiesForKeys: nil)
        } catch {
            print("[MenuLoader] Cannot read directory: \(error)")
            return []
        }

        let jsonFiles = entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let items = jsonFiles.flatMap { url -> [CommandItem] in
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([CommandItem].self, from: data)
            else {
                print("[MenuLoader] Failed to load \(url.lastPathComponent)")
                return []
            }
            print("[MenuLoader] Loaded \(url.lastPathComponent) — \(decoded.count) item(s)")
            return decoded
        }

        print("[MenuLoader] Total: \(items.count) option(s) from \(jsonFiles.count) file(s)")
        return items
    }
}
