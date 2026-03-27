# Plan: 03_status_bar_menu — Add macOS menu bar icon with reload and loaded-files display

## Checklist

- [x] Create `AppState.swift` — shared `ObservableObject` holding commands + loaded file names
- [x] Update `MenuLoader` to return a result struct with items and loaded file names
- [x] Add `NSStatusItem` to `AppDelegate` with a menu (Reload + file list)
- [x] Change activation policy to `.accessory` (no Dock icon)
- [x] Wire `LauncherView` to read commands from `AppState` via `@EnvironmentObject`

---

## Context / Problem

The app currently has no persistent presence; it opens a floating panel and loads config once on appear. There is no way to reload configuration without restarting. Users also have no visibility into which JSON files were picked up. A menu bar icon gives a permanent entry point for both.

---

## Behaviour spec

- A menu bar icon (SF Symbol `"terminal"` or similar) is always visible in the system menu bar.
- Left-clicking (or right-clicking) the icon opens an `NSMenu` with:
  1. **"Reload Configuration"** — triggers `MenuLoader.load()` and pushes updated state to `AppState`
  2. A separator
  3. One disabled item per loaded JSON file showing its filename (e.g. `dev.json`, `work.json`). If no files loaded, one disabled item reads `"No config files loaded"`.
- The panel launcher continues to work independently (toggled by whatever gesture/shortcut is already in place or simply by the app activating).

---

## macOS capability note

- `NSStatusItem` must be created on the main thread and retained for the app lifetime (store it in `AppDelegate`).
- Using `NSMenu` (not SwiftUI `Menu`) for the status item is the correct approach — SwiftUI menus cannot be attached directly to `NSStatusItem`.
- The activation policy must be `.accessory` so the app has no Dock icon and does not steal focus from other apps when the menu is opened.
- `NSStatusItem.button` is the `NSStatusBarButton` to set an image on; setting `.image` with an SF Symbol requires `NSImage(systemSymbolName:accessibilityDescription:)` (macOS 11+).

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/AppState.swift` | **New file** — `ObservableObject` with `commands` and `loadedFileNames` |
| `UnnamedMenu/MenuLoader.swift` | Modify — `load()` returns `MenuLoader.LoadResult` instead of `[CommandItem]` |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — add `NSStatusItem`, activation policy `.accessory`, inject `AppState` |
| `UnnamedMenu/LauncherView.swift` | Modify — consume `AppState` via `@EnvironmentObject` instead of calling `MenuLoader` directly |

---

## Implementation Steps

### 1. Create `AppState`

A simple `ObservableObject` that is the single source of truth for loaded data. `AppDelegate` owns it and publishes it into the SwiftUI environment.

```swift
import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var commands: [CommandItem] = []
    @Published var loadedFileNames: [String] = []

    func reload() {
        let result = MenuLoader.load()
        commands = result.items
        loadedFileNames = result.fileNames
    }
}
```

### 2. Update `MenuLoader` to return a `LoadResult`

Add a value type `LoadResult` so both items and file names travel together. Keep the function signature compatible by returning this struct from `load()`.

```swift
enum MenuLoader {
    struct LoadResult {
        let items: [CommandItem]
        let fileNames: [String]   // basenames of successfully loaded files, in load order
    }

    static func load() -> LoadResult {
        // ... existing directory scan ...
        // collect fileNames alongside items
        var items: [CommandItem] = []
        var fileNames: [String] = []
        for url in jsonFiles {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([CommandItem].self, from: data)
            else { continue }
            items.append(contentsOf: decoded)
            fileNames.append(url.lastPathComponent)
        }
        return LoadResult(items: items, fileNames: fileNames)
    }
}
```

### 3. Add status item to `AppDelegate`

Add `NSStatusItem` and `AppState` as stored properties. Build the menu lazily after load so file names are known.

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        // Status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "UnnamedMenu")
        statusItem.button?.image?.isTemplate = true   // respects dark/light menu bar

        appState.reload()
        rebuildMenu()

        // Panel setup (unchanged) ...
    }

    func rebuildMenu() {
        let menu = NSMenu()
        let reload = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)
        menu.addItem(.separator())

        if appState.loadedFileNames.isEmpty {
            let none = NSMenuItem(title: "No config files loaded", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for name in appState.loadedFileNames {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        statusItem.menu = menu
    }

    @objc private func reloadConfig() {
        appState.reload()
        rebuildMenu()
    }
}
```

### 4. Inject `AppState` into the SwiftUI environment

In `UnnamedMenuApp.body` (or when constructing the hosting view in `AppDelegate`), pass `appState` as an environment object:

```swift
let hostingView = NSHostingView(
    rootView: ContentView().environmentObject(appDelegate.appState)
)
```

Since `AppDelegate` is accessed via `@NSApplicationDelegateAdaptor`, the cleanest approach is to construct the hosting view inside `AppDelegate.applicationDidFinishLaunching` (already the case) and reference `self.appState` directly.

### 5. Update `LauncherView` to use `AppState`

Remove the direct `MenuLoader.load()` call. Read commands from `AppState` instead.

```swift
struct LauncherView: View {
    @EnvironmentObject var appState: AppState
    // remove: @State private var commands: [CommandItem] = []

    var filteredCommands: [CommandItem] {
        guard !searchText.isEmpty else { return appState.commands }
        return appState.commands.filter { ... }
    }

    // in onAppear, remove: commands = MenuLoader.load()
    // The panel shows whatever appState.commands holds at open time.
}
```

---

## Key Technical Notes

- `NSStatusItem` is retained by the system's `NSStatusBar`; still, keep a strong reference in `AppDelegate` to avoid accidental dealloc.
- `isTemplate = true` on the status icon makes it render correctly in both light and dark menu bars automatically.
- `rebuildMenu()` must run on the main thread — it is always called from `@objc reloadConfig` (main thread) or `applicationDidFinishLaunching` (main thread), so no extra dispatch is needed.
- Changing activation policy to `.accessory` means `NSApp.activate(ignoringOtherApps: true)` in `applicationDidFinishLaunching` is still needed to bring the panel to front on first launch.
- `@Published` properties on `AppState` trigger SwiftUI re-renders in `LauncherView` automatically when `reload()` is called, so the command list refreshes without the panel needing to be closed/reopened.
- The panel's `.onAppear` no longer needs to call `MenuLoader`; remove that call to avoid double-loading on every panel open.

---

## Verification

1. Launch app → menu bar icon appears, no Dock icon visible
2. Click menu bar icon → menu shows "Reload Configuration", separator, and names of all loaded `.json` files
3. Add a new `.json` file to `~/.config/unnamed/menu/` → click "Reload Configuration" → new file appears in the menu file list and its commands appear in the launcher panel
4. Remove a file → "Reload Configuration" → file disappears from list
5. Remove all files → "Reload Configuration" → menu shows "No config files loaded"
6. Open launcher panel after reload → shows the reloaded command set (not a stale one)
7. Malformed JSON file present → "Reload Configuration" → valid files still listed; bad file absent from the list
