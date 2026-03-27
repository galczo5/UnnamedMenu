import Foundation

final class ApplicationsGenerator {
    private let outputURL: URL

    init(outputURL: URL = MenuLoader.configURL.appendingPathComponent("applications.json")) {
        self.outputURL = outputURL
    }

    /// Discovers all installed apps and writes applications.json.
    /// Returns `true` on success, `false` on write failure.
    @discardableResult
    func generate() -> Bool {
        let entries = discoverApps()
        return write(entries)
    }

    // MARK: - Private

    private func discoverApps() -> [[String: String]] {
        let fm = FileManager.default
        let searchDirs: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var entries: [[String: String]] = []

        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                let displayName = fm.displayName(atPath: url.path)
                entries.append([
                    "name": displayName,
                    "command": "open -a \"\(url.lastPathComponent)\"",
                    "systemImage": url.path
                ])
            }
        }

        return entries.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
    }

    private func write(_ entries: [[String: String]]) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: .atomic)
            print("[ApplicationsGenerator] Wrote \(entries.count) app(s) to \(outputURL.path)")
            return true
        } catch {
            print("[ApplicationsGenerator] Failed to write applications.json: \(error)")
            return false
        }
    }
}
