# Plan: 14_theme_and_display_config — Theme, icon, placeholder, and max-results in config.yml

## Checklist

- [x] Add `theme`, `searchIcon`, `searchPlaceholder`, `maxResults` to `MenuConfigData`
- [x] Update `MenuConfigData.defaults` and `mergedWithDefaults()`
- [x] Update `MenuConfigLoader.format()` to emit new fields with comments
- [x] Expose new accessors on `MenuConfig`
- [x] Update `VisualEffectView` to accept and apply a theme
- [x] Wire config values into `LauncherView` (icon, placeholder, max results, theme)

---

## Context / Problem

The launcher UI has several values currently hardcoded in Swift:
- Appearance is forced to `.aqua` (always light) in `VisualEffectView`
- Search icon is hardcoded to `"magnifyingglass"` in `LauncherView`
- Search placeholder is hardcoded to `"Search commands…"` in `LauncherView`
- Max visible results is hardcoded to `5` (normal) / `25` (show-all / windows mode) in `LauncherView`

The goal is to expose all four settings under a `display:` section in `~/.config/unnamed/menu.yml`, defaulting to the current behaviour (theme: light, icon: magnifyingglass, placeholder: "Search commands…", maxResults: 5).

---

## Behaviour spec

| Config value | Type | Default | Effect |
|---|---|---|---|
| `display.theme` | string | `light` | `light` → `.aqua`, `dark` → `.darkAqua`, `system` → nil (follows OS) |
| `display.searchIcon` | string | `magnifyingglass` | SF Symbol name shown left of the search field |
| `display.searchPlaceholder` | string | `Search commands…` | Placeholder text in the search field |
| `display.maxResults` | int | `5` | Max rows shown in the result list; show-all/windows mode uses `maxResults * 5` |

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/Config/MenuConfigData.swift` | Modify — add `DisplayConfig` nested struct and wire into defaults/merge |
| `UnnamedMenu/Config/MenuConfig.swift` | Modify — expose four new computed properties |
| `UnnamedMenu/Config/MenuConfigLoader.swift` | Modify — emit `display:` block in `format()` |
| `UnnamedMenu/Views/VisualEffectView.swift` | Modify — accept `theme: String` init param, map to `NSAppearance` |
| `UnnamedMenu/Views/LauncherView.swift` | Modify — read config for icon, placeholder, maxResults, theme |

---

## Implementation Steps

### 1. Extend `MenuConfigData` with a `DisplayConfig` section

Add a new nested struct and plug it into the top-level config:

```swift
struct DisplayConfig: Codable {
    var theme: String?
    var searchIcon: String?
    var searchPlaceholder: String?
    var maxResults: Int?
}

struct ConfigSection: Codable {
    var shortcuts: ShortcutsConfig?
    var display: DisplayConfig?
}
```

Update `defaults` to include `display`:

```swift
static let defaults = MenuConfigData(config: ConfigSection(
    shortcuts: ShortcutsConfig(open: "cmd+space", openWindows: "opt+tab"),
    display: DisplayConfig(
        theme: "light",
        searchIcon: "magnifyingglass",
        searchPlaceholder: "Search commands…",
        maxResults: 5
    )
))
```

Update `missingKeys` to check each display key, and update `mergedWithDefaults()` to fill in the display defaults the same way shortcuts are filled in.

### 2. Expose accessors on `MenuConfig`

```swift
var theme: String            { data.config!.display!.theme! }
var searchIcon: String       { data.config!.display!.searchIcon! }
var searchPlaceholder: String { data.config!.display!.searchPlaceholder! }
var maxResults: Int          { data.config!.display!.maxResults! }
```

### 3. Emit the `display:` block in `MenuConfigLoader.format()`

Add a `display:` section after `shortcuts:` in the formatted YAML string, with inline comments explaining each field. Example structure:

```yaml
display:
  # Colour scheme: light, dark, system
  theme: "light"
  # SF Symbol name for the search field icon
  searchIcon: "magnifyingglass"
  # Placeholder text in the search field
  searchPlaceholder: "Search commands…"
  # Maximum number of results shown (show-all/windows uses maxResults × 5)
  maxResults: 5
```

### 4. Update `VisualEffectView` to accept a theme

```swift
struct VisualEffectView: NSViewRepresentable {
    var theme: String = "light"

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        switch theme {
        case "dark":   nsView.appearance = NSAppearance(named: .darkAqua)
        case "system": nsView.appearance = nil
        default:       nsView.appearance = NSAppearance(named: .aqua)
        }
    }
}
```

Move the appearance assignment to `updateNSView` so it reacts if the value ever changes at runtime.

### 5. Wire config into `LauncherView`

Replace hardcoded constants with reads from `MenuConfig.shared`:

```swift
private var maxResults: Int {
    let base = MenuConfig.shared.maxResults
    return (appState.showAll || appState.windowsMode) ? base * 5 : base
}
```

In `body`, replace the hardcoded icon and placeholder:

```swift
Image(systemName: MenuConfig.shared.searchIcon)

TextField(MenuConfig.shared.searchPlaceholder, text: $searchText)
```

Pass the theme to `VisualEffectView`:

```swift
.background(VisualEffectView(theme: MenuConfig.shared.theme))
```

---

## Key Technical Notes

- `VisualEffectView.appearance = nil` means the view inherits the OS appearance — this is the correct "system" behaviour, not a bug.
- `makeNSView` runs once; appearance changes must go in `updateNSView` to take effect on reload.
- `MenuConfig.shared` is read at view body evaluation time; config is loaded once at launch, so changes to `menu.yml` require restart (consistent with existing shortcuts behaviour).
- The `maxResults * 5` multiplier for show-all/windows mode preserves the current 5/25 ratio when using the default `maxResults: 5`.
- `mergedWithDefaults()` must be updated carefully: each display field follows the same nil-coalescing pattern as shortcuts fields.

---

## Verification

1. Launch app with no existing `menu.yml` → file is created with `display:` block containing all four fields with defaults.
2. Open launcher → icon is magnifying glass, placeholder is "Search commands…", at most 5 results appear.
3. Set `theme: dark` in `menu.yml`, restart → launcher panel renders in dark mode regardless of OS appearance.
4. Set `theme: system`, restart → launcher follows OS appearance toggle in System Settings.
5. Set `searchIcon: "star"`, restart → star icon appears left of search field.
6. Set `searchPlaceholder: "Run…"`, restart → placeholder text changes.
7. Set `maxResults: 3`, restart → at most 3 results in search mode; press cmd+space twice (show-all) → at most 15 results.
8. Set `maxResults: 10`, switch to windows mode → at most 50 windows listed.
