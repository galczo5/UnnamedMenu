# Plan: 12_menu_yml_keybindings — Global hotkeys via menu.yml config

## Checklist

- [x] Add Yams SPM dependency to Xcode project
- [x] Create MenuConfigData.swift with Codable structs
- [x] Create MenuConfigLoader.swift to load/create menu.yml
- [x] Create MenuConfig.swift facade for runtime access
- [x] Create KeybindingService.swift with CGEventTap registration
- [x] Wire KeybindingService into AppDelegate (start, restart, reload)
- [x] Remove sendEvent override and tabKeyPressed notification
- [x] Update LauncherView to use KeybindingService for Tab cycling
- [x] Add Open/Reload/Reset config menu items to status bar menu
---

## Context / Problem

UnnamedMenu currently relies on UnnamedWindowManager's `commands` config to register global hotkeys (`cmd+space` → open, `opt+tab` → open windows). The problem: when UnnamedMenu's panel is visible and active, UWM's CGEventTap consumes the `opt+tab` event at the HID level before it reaches the panel's `sendEvent`. This makes `opt+tab` unable to cycle selection within the open panel.

**Goal:** UnnamedMenu registers its own CGEventTap for `open` and `openWindows` shortcuts via a `~/.config/unnamed/menu.yml` config file, following the same pattern as UWM's `config.yml`. When a shortcut fires:
- Panel **not visible** → show the panel (in the appropriate mode)
- Panel **already visible** → cycle selection forward

This eliminates the external dependency on UWM for hotkey registration and solves the modifier-Tab conflict.

---

## Config file spec

**Path:** `~/.config/unnamed/menu.yml`

```yaml
config:
  shortcuts:
    # Global shortcut to open UnnamedMenu. When already open, cycles selection.
    open: "cmd+space"
    # Global shortcut to open UnnamedMenu in windows mode. When already open, cycles selection.
    openWindows: "opt+tab"
```

- All fields optional, defaults used for missing keys
- Same shortcut format as UWM: `modifier+key` (e.g. `cmd+space`, `opt+tab`)
- Empty string disables a shortcut
- Parsed identically to UWM's `KeybindingService.parse()`

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu.xcodeproj/project.pbxproj` | Add Yams SPM package dependency |
| `UnnamedMenu/Config/MenuConfigData.swift` | **New file** — Codable structs + defaults |
| `UnnamedMenu/Config/MenuConfigLoader.swift` | **New file** — Load/create menu.yml |
| `UnnamedMenu/Config/MenuConfig.swift` | **New file** — Static facade |
| `UnnamedMenu/Services/KeybindingService.swift` | **New file** — CGEventTap registration |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — wire KeybindingService, remove sendEvent override and Notification.Name extension, add config menu items |
| `UnnamedMenu/LauncherView.swift` | Modify — remove `.onReceive(.tabKeyPressed)`, Tab cycling handled by KeybindingService |

---

## Implementation Steps

### 1. Add Yams dependency

Add `https://github.com/jpsim/Yams` as an SPM package in Xcode (version 5.4.0+). The UnnamedWindowManager already uses this exact library.

### 2. MenuConfigData

Minimal Codable struct mirroring UWM's pattern:

```swift
struct MenuConfigData: Codable {
    var config: ConfigSection?

    struct ConfigSection: Codable {
        var shortcuts: ShortcutsConfig?
    }

    struct ShortcutsConfig: Codable {
        var open: String?
        var openWindows: String?
    }

    static let defaults = MenuConfigData(config: ConfigSection(
        shortcuts: ShortcutsConfig(open: "cmd+space", openWindows: "opt+tab")
    ))

    func mergedWithDefaults() -> MenuConfigData { ... }
}
```

### 3. MenuConfigLoader

Same pattern as UWM's `ConfigLoader`:
- Directory: `~/.config/unnamed/` (shared with UWM)
- File: `~/.config/unnamed/menu.yml`
- Creates file from defaults if missing
- Parses with `YAMLDecoder`, merges with defaults
- Manual YAML formatter for pretty output with comments

### 4. MenuConfig facade

```swift
final class MenuConfig {
    static let shared = MenuConfig()
    private var data: MenuConfigData

    var openShortcut: String { data.config!.shortcuts!.open! }
    var openWindowsShortcut: String { data.config!.shortcuts!.openWindows! }

    func reload() { data = MenuConfigLoader.load() }
}
```

### 5. KeybindingService

Port UWM's `KeybindingService` — simplified for two bindings only:
- Same `parse()` logic (modifier+key → ModifierFlags + key/keyCode)
- Same `CGEvent.tapCreate` with `.cghidEventTap` + `.headInsertEventTap`
- Same duplicate detection and normalization
- Same re-enable on timeout/user-input disable

**Action callback pattern:**
```swift
// For both "open" and "openWindows":
// If panel visible → post moveSelection notification
// If panel not visible → show panel (with windows mode flag for openWindows)
```

The service needs a reference to `AppDelegate` (or uses `NotificationCenter`) to show the panel or cycle selection. Use notifications:
- `.menuShowPanel` — show the panel (with userInfo for windows mode + showAll)
- `.menuCycleSelection` — move selection forward (replaces `.tabKeyPressed`)

### 6. Wire into AppDelegate

- Call `KeybindingService.shared.start()` after panel setup in `applicationDidFinishLaunching`
- In `reloadConfig()`, also call `MenuConfig.shared.reload()` + `KeybindingService.shared.restart()`
- Remove `sendEvent` override from `KeyablePanel`
- Remove `Notification.Name.tabKeyPressed` extension
- Add observers for `.menuShowPanel` and `.menuCycleSelection`

### 7. Add config menu items to status bar menu

Add three menu items to `rebuildMenu()`, following UWM's pattern:

- **Open config file** — `NSWorkspace.shared.open(URL(fileURLWithPath: MenuConfigLoader.filePath))` to open `menu.yml` in the default editor
- **Reload config file** — calls `MenuConfig.shared.reload()` + `KeybindingService.shared.restart()`
- **Reset config file** — calls `MenuConfigLoader.write(MenuConfigData.defaults)` then reload + restart

### 8. Update LauncherView

- Replace `.onReceive(.tabKeyPressed)` with `.onReceive(.menuCycleSelection)`
- No other changes needed

---

## Key Technical Notes

- CGEventTap requires Accessibility permission (`AXIsProcessTrusted()`). The app should prompt for permission at startup if not granted.
- CGEventTap at `.cghidEventTap` fires before ALL apps' `sendEvent`, including UWM's event tap. Registration order matters — whichever tap is registered first gets priority. Since both apps register on launch, the order depends on launch sequence. The fix is to **remove the `opt+tab` and `cmd+space` commands from UWM's config.yml** so there's no conflict.
- The `sendEvent` override on `KeyablePanel` becomes unnecessary — the CGEventTap handles both opening and cycling. Remove it to avoid double-handling.
- `menu.yml` lives alongside `config.yml` in `~/.config/unnamed/` — both apps share the directory but use separate config files.
- The panel visibility check can use `panel.isVisible` or `NSApp.keyWindow != nil`.

---

## Verification

1. Delete `~/.config/unnamed/menu.yml` → launch app → file is created with defaults
2. Press `cmd+space` when panel is hidden → panel opens
3. Press `cmd+space` when panel is visible → selection cycles down
4. Press `opt+tab` when panel is hidden → panel opens in windows mode
5. Press `opt+tab` when panel is visible → selection cycles down
6. Edit `menu.yml` to change `open: "cmd+shift+space"` → reload config → new shortcut works
7. Set `open: ""` in menu.yml → reload → shortcut disabled, no crash
8. Manually remove `opt+tab` and `cmd+space` commands from UWM `config.yml` → no conflict between apps
9. Status bar menu → "Open config file" → opens `menu.yml` in default editor
10. Status bar menu → "Reset config file" → `menu.yml` reverts to defaults, shortcuts update
11. Status bar menu → "Reload config file" → picks up manual edits to `menu.yml`
