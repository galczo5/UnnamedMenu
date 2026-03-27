# Plan: 07_cli_config_flag — CLI `--config <path>` flag: scoped fuzzy search to one file

## Checklist

- [x] Extend `MenuLoader.LoadResult` with `itemsByURL: [URL: [CommandItem]]`
- [x] Populate `itemsByURL` in `MenuLoader.load()`
- [x] Add `activeFilter`, `visibleCommands`, and `applyFilter(url:)` to `AppState`
- [x] Change `LauncherView.filteredCommands` to use `appState.visibleCommands`
- [x] Clear `activeFilter` when the panel hides
- [x] Add `--config` flag handling in `AppDelegate.applicationDidFinishLaunching`
- [x] Register for `filterConfig` distributed notification in `AppDelegate`
- [x] Add `filterConfigFromNotification(_:)` handler to `AppDelegate`

---

## Context / Problem

Users want to open the launcher scoped to a single JSON file — e.g. a project-specific commands file — without showing all globally loaded commands. The flag `--config /abs/path/to/file.json` should open (or activate) the panel showing only items from that file. Like `--open`, it must not spawn a second app instance.

---

## Behaviour spec

- If an instance is already running:
  1. New instance posts a `com.unnamedmenu.filterConfig` distributed notification with the resolved absolute path.
  2. New instance exits.
  3. Running instance receives the notification, calls `applyFilter(url:)`, and shows the panel.
- If no instance is running:
  1. App launches normally (full setup).
  2. After setup, calls `applyFilter(url:)` and shows the panel.
- **Cache hit**: if `itemsByURL[url]` already exists (file was part of the normal config scan or a previous `--config` call), no disk read occurs — `activeFilter` is set directly.
- **Cache miss**: the file is decoded from disk and stored in `itemsByURL`; it is not merged into the global `commands` list (keeping the normal reload state clean).
- `activeFilter` is cleared when the panel hides, so the next normal open shows all commands.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/MenuLoader.swift` | Modify — add `itemsByURL` to `LoadResult`; populate it in `load()` |
| `UnnamedMenu/AppState.swift` | Modify — add `activeFilter`, `visibleCommands`, `applyFilter(url:)` |
| `UnnamedMenu/LauncherView.swift` | Modify — use `appState.visibleCommands`; clear filter on hide |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — handle `--config` flag; register/handle `filterConfig` notification |

---

## Implementation Steps

### 1. Extend `MenuLoader.LoadResult` and `load()`

Add `itemsByURL` so `AppState` can look up items per file without re-reading disk.

```swift
struct LoadResult {
    let items: [CommandItem]
    let fileNames: [String]
    let itemsByURL: [URL: [CommandItem]]
}
```

In `load()`, build the dictionary alongside the existing loop:

```swift
var itemsByURL: [URL: [CommandItem]] = [:]
// inside the loop:
itemsByURL[url] = decoded
// at the end:
return LoadResult(items: items, fileNames: fileNames, itemsByURL: itemsByURL)
```

### 2. Update `AppState`

```swift
final class AppState: ObservableObject {
    @Published var commands: [CommandItem] = []
    @Published var loadedFileNames: [String] = []
    @Published var activeFilter: URL? = nil

    private var itemsByURL: [URL: [CommandItem]] = [:]

    var visibleCommands: [CommandItem] {
        if let filter = activeFilter {
            return itemsByURL[filter] ?? []
        }
        return commands
    }

    func reload() {
        let result = MenuLoader.load()
        commands = result.items
        loadedFileNames = result.fileNames
        itemsByURL = result.itemsByURL
    }

    func applyFilter(url: URL) {
        if itemsByURL[url] == nil {
            // cache miss — load from disk without touching global state
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([CommandItem].self, from: data) {
                itemsByURL[url] = decoded
            }
        }
        activeFilter = url
    }

    func clearFilter() {
        activeFilter = nil
    }
}
```

### 3. Update `LauncherView`

Change the one reference from `appState.commands` to `appState.visibleCommands`:

```swift
var filteredCommands: [CommandItem] {
    guard !searchText.isEmpty else { return [] }
    return appState.visibleCommands   // was appState.commands
        .compactMap { ... }
        ...
}
```

Clear the filter when the panel hides so the next normal open shows all commands:

```swift
private func hideWindow() {
    appState.clearFilter()
    NSApp.keyWindow?.close()
}
```

### 4. Handle `--config` in `AppDelegate`

Add the notification name constant alongside the existing one:

```swift
private static let filterConfigNotification = "com.unnamedmenu.filterConfig"
```

At the top of `applicationDidFinishLaunching`, before GUI setup:

```swift
if let configIndex = CommandLine.arguments.firstIndex(of: "--config"),
   CommandLine.arguments.indices.contains(configIndex + 1) {
    let path = CommandLine.arguments[configIndex + 1]
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let myPID = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        .filter { $0.processIdentifier != myPID }
    if others.first != nil {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(AppDelegate.filterConfigNotification),
            object: nil,
            userInfo: ["path": url.path],
            deliverImmediately: true
        )
        exit(0)
    }
    // No running instance — store path; apply after setup below
    pendingConfigURL = url
}
```

Add a private stored property `pendingConfigURL: URL?` to `AppDelegate`. After the panel is shown, apply the pending filter:

```swift
// at the end of applicationDidFinishLaunching, after panel.orderFrontRegardless():
if let url = pendingConfigURL {
    appState.applyFilter(url: url)
}
```

### 5. Register for the notification and add the handler

Inside `applicationDidFinishLaunching`, alongside the existing `showPanel` observer:

```swift
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(filterConfigFromNotification(_:)),
    name: NSNotification.Name(AppDelegate.filterConfigNotification),
    object: nil
)
```

Handler:

```swift
@objc private func filterConfigFromNotification(_ note: Notification) {
    guard let path = note.userInfo?["path"] as? String else { return }
    let url = URL(fileURLWithPath: path)
    appState.applyFilter(url: url)
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

---

## Key Technical Notes

- `DistributedNotificationCenter` delivers on the main thread when the receiver is a Cocoa app, so `filterConfigFromNotification` can safely update `@Published` properties and touch UI.
- `URL.standardizedFileURL` resolves `~`, `.`, and `..` before sending over IPC, so the receiver always gets an absolute path.
- Cache misses load from disk synchronously on the main thread — acceptable because JSON files are small. If a file fails to decode, `visibleCommands` returns `[]` (empty launcher) rather than crashing.
- `activeFilter` is `@Published`, so changing it automatically re-renders `LauncherView` via the `@EnvironmentObject` chain without extra wiring.
- The global `commands` list is never modified by `applyFilter` — only `itemsByURL` and `activeFilter` change — keeping `reload()` semantics clean.
- `clearFilter()` in `hideWindow()` means the filter is scoped to a single panel session; reopening via the menu bar or `--open` always shows all commands.

---

## Verification

1. Launch app normally → panel shows all commands → close.
2. `--config /path/to/file.json` (app running) → no new Dock icon; panel opens showing only items from that file.
3. Close panel → `--open` → panel shows all commands (filter cleared).
4. `--config /path/to/file.json` twice in a row → second call hits cache (no disk read, check via log absence).
5. `--config /path/to/file.json` with app not running → app launches, panel opens filtered to that file.
6. `--config /nonexistent.json` → panel opens with empty list, no crash.
7. Normal reload via menu → global commands unaffected by prior filter calls.
