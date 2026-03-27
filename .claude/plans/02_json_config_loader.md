# Plan: 02_json_config_loader — Load menu items from JSON files in ~/.config/unnamed/menu

## Checklist

- [ ] Define `Codable` struct for JSON menu item format
- [ ] Create `MenuLoader.swift` with directory scan + JSON parsing
- [ ] Update `LauncherView` to load items from disk at startup
- [ ] Remove hardcoded `CommandItem.defaults`

---

## Context / Problem

All menu items are currently hardcoded in `CommandItem.defaults` as a static Swift array. The goal is to allow users to define their own commands by placing JSON files in `~/.config/unnamed/menu/`. Multiple files can coexist and are all loaded at launch; each file is an array of command objects.

---

## JSON format spec

Each file is a JSON array. Every element must have these fields:

```json
[
  {
    "name": "List Home",
    "command": "ls -la ~",
    "systemImage": "folder"
  }
]
```

`systemImage` is an SF Symbol name. Files must have a `.json` extension. Loading order within a directory is alphabetical by filename (stable but not user-visible).

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/MenuLoader.swift` | **New file** — scans `~/.config/unnamed/menu`, decodes all `.json` files |
| `UnnamedMenu/CommandItem.swift` | Modify — make `CommandItem` `Decodable`, remove `defaults` |
| `UnnamedMenu/LauncherView.swift` | Modify — load items via `MenuLoader` on appear, fall back to empty |

---

## Implementation Steps

### 1. Make `CommandItem` decodable

`CommandItem` already has the right fields. Add `Decodable` conformance. The `id` field is auto-generated and must not come from JSON, so use a custom `CodingKeys` enum that excludes it.

```swift
struct CommandItem: Identifiable, Decodable {
    let id = UUID()
    let name: String
    let command: String
    let systemImage: String

    private enum CodingKeys: String, CodingKey {
        case name, command, systemImage
    }
}
```

Remove `static let defaults`.

### 2. Create `MenuLoader`

`MenuLoader` is a value-type namespace (enum with no cases). It exposes one function: `load() -> [CommandItem]`.

```swift
enum MenuLoader {
    static let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/unnamed/menu", isDirectory: true)
    }()

    static func load() -> [CommandItem] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: configURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { url -> [CommandItem] in
                guard let data = try? Data(contentsOf: url),
                      let items = try? JSONDecoder().decode([CommandItem].self, from: data)
                else { return [] }
                return items
            }
    }
}
```

### 3. Update `LauncherView` to load from disk

Add a `@State private var commands: [CommandItem] = []` property. On `.onAppear`, call `MenuLoader.load()` and assign the result. Replace all references to `CommandItem.defaults` with `commands`.

```swift
@State private var commands: [CommandItem] = []

// inside body, replace CommandItem.defaults references:
var filteredCommands: [CommandItem] {
    guard !searchText.isEmpty else { return commands }
    return commands.filter {
        $0.name.localizedCaseInsensitiveContains(searchText) ||
        $0.command.localizedCaseInsensitiveContains(searchText)
    }
}

// in onAppear:
.onAppear {
    isSearchFocused = true
    commands = MenuLoader.load()
}
```

---

## Key Technical Notes

- `contentsOfDirectory` returns an empty result (not an error) if the directory does not exist on some OS versions, but will throw on others — the `try?` guard covers both.
- `id = UUID()` with `let` is synthesized once per instance, so two decode calls for the same JSON produce items with different IDs. This is intentional — IDs only need to be stable within a single load.
- Files are decoded independently; a malformed file is silently skipped (`flatMap` returns `[]` for it). This prevents one bad file from blocking all others.
- Loading is synchronous on the main thread, which is fine for a local directory scan over small JSON files. Async loading is unnecessary complexity here.
- The config directory (`~/.config/unnamed/menu`) is not created automatically — users must create it. The app handles a missing directory gracefully (empty command list).

---

## Verification

1. Create `~/.config/unnamed/menu/` and add a `.json` file with one command object → launch app → that command appears in the list
2. Add a second `.json` file → relaunch → commands from both files appear, ordered by filename then by position within each file
3. Add a third file with invalid JSON → relaunch → valid files still load correctly, invalid file is silently skipped
4. Remove all `.json` files (or delete the directory) → relaunch → app shows an empty list without crashing
5. Search still filters the loaded items correctly
6. Arrow-key navigation and Enter-to-run still work
