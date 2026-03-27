# Plan: 04_generate_applications_json — Add "Generate applications.json" to status bar menu

## Checklist

- [x] Create `ApplicationsGenerator.swift` — new class with discovery and write logic
- [x] Add "Generate applications.json" `NSMenuItem` to `rebuildMenu()` in `UnnamedMenuApp.swift`
- [x] Wire menu item action to call `ApplicationsGenerator` and then reload

---

## Context / Problem

Users need a way to bootstrap their config with all installed macOS applications. Currently they must hand-write JSON entries for every app they want to launch. A "Generate applications.json" menu item will scan the standard application directories, produce a valid `applications.json` in the config folder, and trigger a reload — letting users get a working launcher immediately.

---

## Behaviour spec

- Clicking "Generate applications.json" in the status bar menu:
  1. Scans `/Applications`, `/System/Applications`, and `~/Applications` for `.app` bundles (non-recursive, top-level only).
  2. Builds one `CommandItem`-compatible JSON object per app:
     - `name`: display name from `NSWorkspace` (falls back to bundle name without `.app`)
     - `command`: `open -a "<BundleName>.app"`
     - `systemImage`: `"app.badge"` (static default)
  3. Writes the array to `~/.config/unnamed/menu/applications.json`, creating intermediate directories if needed. Overwrites any existing file.
  4. Caller triggers `appState.reload()` and `rebuildMenu()` so the launcher is immediately up to date.
- On success: no dialog needed — the reload itself is the confirmation.
- On failure (write error): `generate()` returns `false`; caller prints/logs and skips reload.

---

## macOS capability note

- `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` is per-bundle; for bulk discovery, a directory scan with `FileManager` is simpler and does not require extra entitlements.
- `NSWorkspace.shared.localizedName(forFile:)` returns the user-visible app name (respects `CFBundleDisplayName`).
- No special sandbox entitlement is needed to read `/Applications` or write to `~/.config`.
- Scanning is synchronous and fast enough at top-level depth — no need for async.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/ApplicationsGenerator.swift` | **New file** — discovers apps, writes `applications.json` |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — add menu item in `rebuildMenu()`, call `ApplicationsGenerator` from action |

---

## Implementation Steps

### 1. Create `ApplicationsGenerator`

All discovery and write logic lives here. `AppDelegate` stays thin — it only calls `generate()` and reacts to the result.

```swift
import AppKit
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
        let ws = NSWorkspace.shared
        var entries: [[String: String]] = []

        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                let displayName = ws.localizedName(forFile: url.path)
                    ?? url.deletingPathExtension().lastPathComponent
                entries.append([
                    "name": displayName,
                    "command": "open -a \"\(url.lastPathComponent)\"",
                    "systemImage": "app.badge"
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
```

### 2. Add menu item in `rebuildMenu()` and wire the action in `AppDelegate`

In `UnnamedMenuApp.swift`, add the item to the menu and handle it with a slim `@objc` method that delegates to `ApplicationsGenerator`.

```swift
// In rebuildMenu():
let generate = NSMenuItem(title: "Generate applications.json", action: #selector(generateApplicationsJSON), keyEquivalent: "")
generate.target = self
menu.addItem(generate)
menu.addItem(.separator())
// ... existing Reload item ...

// New action method on AppDelegate:
@objc private func generateApplicationsJSON() {
    guard ApplicationsGenerator().generate() else { return }
    appState.reload()
    rebuildMenu()
}
```

---

## Key Technical Notes

- `NSWorkspace.localizedName(forFile:)` returns `nil` if the path does not exist or is not an app bundle — the fallback strips `.app` from the last path component.
- Bundles inside app bundles (e.g. helper agents inside `/Applications/Foo.app/Contents/`) are not scanned because we only look at top-level entries of each directory.
- `open -a "Safari.app"` works identically to `open -a "Safari"` — including the extension is harmless and avoids ambiguity when app names contain dots.
- Overwriting `applications.json` on every generation is intentional; it keeps the file in sync with the current app set.
- `JSONSerialization` (not `JSONEncoder`) is used because `CommandItem` has `id = UUID()` that is not `Encodable` by default — building `[String: String]` dicts avoids that friction without touching `CommandItem`.
- The menu rebuild after generation ensures the newly written filename appears in the loaded-files section immediately.

---

## Verification

1. Click "Generate applications.json" → `~/.config/unnamed/menu/applications.json` is created.
2. Open the file → JSON array with `name`, `command`, `systemImage` keys for each app.
3. Open launcher panel → apps from `/Applications` appear as runnable commands.
4. Click an app entry → `open -a "App.app"` launches the app.
5. Add a new app to `/Applications` → click "Generate applications.json" again → new app appears in launcher.
6. Delete `~/.config/unnamed/menu/` entirely → click "Generate applications.json" → directory and file are recreated.
7. Make `~/.config/unnamed/menu/` read-only → click "Generate applications.json" → error printed to console, app does not crash.
