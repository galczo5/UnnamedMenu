import Foundation

enum MenuLoader {
    struct LoadResult {
        let items: [CommandItem]
        let fileNames: [String]
        let itemsByURL: [URL: [CommandItem]]
    }

    static let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/unnamed/menu", isDirectory: true)
    }()

    static func load() -> LoadResult {
        let fm = FileManager.default
        print("[MenuLoader] Scanning \(configURL.path)")
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: configURL, includingPropertiesForKeys: nil)
        } catch {
            print("[MenuLoader] Cannot read directory: \(error)")
            return LoadResult(items: [], fileNames: [], itemsByURL: [:])
        }

        let jsonFiles = entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var items: [CommandItem] = []
        var fileNames: [String] = []
        var itemsByURL: [URL: [CommandItem]] = [:]

        for url in jsonFiles {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([CommandItem].self, from: data)
            else {
                print("[MenuLoader] Failed to load \(url.lastPathComponent)")
                continue
            }
            print("[MenuLoader] Loaded \(url.lastPathComponent) — \(decoded.count) item(s)")
            items.append(contentsOf: decoded)
            fileNames.append(url.lastPathComponent)
            itemsByURL[url.standardizedFileURL] = decoded
        }

        print("[MenuLoader] Total: \(items.count) option(s) from \(fileNames.count) file(s)")
        return LoadResult(items: items, fileNames: fileNames, itemsByURL: itemsByURL)
    }
}
