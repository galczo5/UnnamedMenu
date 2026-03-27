# Plan: 09_windows_flag — --windows flag: list & focus desktop windows

## Checklist

- [x] Create `WindowsGenerator.swift` with CGWindowList enumeration and JSON output
- [x] Add `--windows` flag handling in `UnnamedMenuApp.swift` (print + exit)

---

## Context / Problem

There is no way to switch between open windows from the launcher. The `--windows` flag should enumerate all visible windows on the current desktop (Space), print them as a `[CommandItem]` JSON array, then exit — matching the pattern of `--applications`. When the user selects an item, the command focuses that window's application process.

---

## Behaviour spec

- `UnnamedMenu --windows` prints a JSON array to stdout and exits (no GUI).
- One entry per visible on-screen window with a title (excluding desktop, dock, menu bar, etc.).
- Entry shape:
  ```json
  { "name": "Window Title — App Name", "command": "...", "systemImage": "macwindow" }
  ```
- `name`: `"WindowTitle — AppName"` when a title exists; `"AppName"` when the window has no title.
- `command`: activates the owning process by PID so the OS raises all its windows to front.
- Entries are ordered front-to-back (CGWindowList natural order).

---

## macOS capability note

`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)` returns only windows that belong to the current Space (Spaces hides offscreen windows). Window layer 0 (`kCGWindowLayer == 0`) is the normal application layer; filtering to layer 0 excludes HUD overlays, tooltips, and system chrome.

To focus a specific process by PID from a shell command:

```swift
"osascript -e 'tell application \"System Events\" to set frontmost of first process whose unix id is \(pid) to true'"
```

This brings the entire app (all its windows on the current Space) to the front. True single-window raise would require Accessibility API; that can be a future enhancement.

`CGWindowListCopyWindowInfo` requires the `Screen Recording` permission at runtime. When the permission is absent, the call returns an empty list; the generator should print `[]` and exit cleanly rather than crashing.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/WindowsGenerator.swift` | **New file** — enumerate CGWindowList, build `[CommandItem]`, print JSON |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — add `--windows` early-exit block (same pattern as `--applications`) |

---

## Implementation Steps

### 1. Create `WindowsGenerator.swift`

```swift
import Foundation
import CoreGraphics

struct WindowsGenerator {
    func generateForCLI() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[]")
            exit(0)
        }

        var items: [[String: String]] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let appName = info[kCGWindowOwnerName as String] as? String,
                  !appName.isEmpty else { continue }

            let windowTitle = info[kCGWindowName as String] as? String ?? ""
            let displayName = windowTitle.isEmpty ? appName : "\(windowTitle) — \(appName)"
            let command = "osascript -e 'tell application \"System Events\" to set frontmost of first process whose unix id is \(pid) to true'"

            items.append([
                "name": displayName,
                "command": command,
                "systemImage": "macwindow"
            ])
        }

        let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
        print(String(data: data, encoding: .utf8) ?? "[]")
        exit(0)
    }
}
```

### 2. Add `--windows` flag in `UnnamedMenuApp.swift`

Insert after the `--applications` block, before the `--config` block:

```swift
if CommandLine.arguments.contains("--windows") {
    WindowsGenerator().generateForCLI()
}
```

`generateForCLI()` calls `exit(0)` internally, so no early-return is needed.

---

## Key Technical Notes

- `CGWindowListCopyWindowInfo` must be called before `NSApp.setActivationPolicy(.accessory)` to avoid any activation side-effects; it's already in the early-exit path so this is satisfied.
- `kCGWindowLayer == 0` is the correct filter for normal app windows — do not filter by `kCGWindowIsOnscreen`; that key is always true for results from `.optionOnScreenOnly`.
- `kCGWindowName` is absent (not just empty) when the window has no title — the `as? String ?? ""` pattern handles both cases.
- When Screen Recording permission is denied, `CGWindowListCopyWindowInfo` returns `nil` (not an empty array). The `guard` handles this by printing `[]` and exiting.
- `pid_t` is `Int32`; string interpolation into the osascript command is safe.
- The osascript command uses single quotes wrapping double-quoted app names; app names that contain single quotes would break it. This is an edge case not worth handling in the MVP.
- The output is a raw `[CommandItem]`-compatible JSON array — pipe it directly: `UnnamedMenu --windows | UnnamedMenu`.

---

## Verification

1. `UnnamedMenu --windows` with several apps open → prints a JSON array, one entry per visible window, exits.
2. Pipe into the launcher: `UnnamedMenu --windows | UnnamedMenu` → launcher shows only window entries.
3. Select a window entry → the corresponding app activates and comes to front.
4. App with multiple windows (e.g. two Finder windows) → both appear as separate entries; selecting either brings Finder to front.
5. Window with no title (some utility windows) → entry uses app name alone.
6. Revoke Screen Recording permission → `UnnamedMenu --windows` prints `[]` and exits without crashing.
7. `UnnamedMenu --windows --all` → `--all` is ignored (windows flag exits before `--all` is applied to `AppState`).
