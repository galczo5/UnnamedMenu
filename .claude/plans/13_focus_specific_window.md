# Plan: 13_focus_specific_window — Fix window switcher to focus the selected window, not just the app

## Checklist

- [x] Store pid + windowTitle per window item instead of relying on shared shell command
- [x] Add native window-focus function using AXUIElement perform AXRaise + app activate
- [x] Update `runSelected()` flow to call native focus for window items
- [ ] ~~Remove the osascript shell command path for window switching~~ (kept as fallback for non-window items)

---

## Context / Problem

When the user selects a specific window from a multi-window app (e.g. "Firefox - Tab B"), the switcher always raises the **first** window instead of the chosen one.

**Root cause** — `WindowsGenerator.generateItems()` (line 88) builds a single osascript command per PID:

```
osascript -e 'tell application "System Events" to set frontmost of first process whose unix id is <PID> to true'
```

Every window of the same app shares this identical command. It brings the app to front but has no mechanism to target a specific window. macOS raises whichever window it considers frontmost for that app — typically window A.

**Goal** — When the user selects "Firefox - Tab B", window B is raised and focused.

---

## macOS capability note

`AXUIElement` can target an individual window. Calling `AXUIElementPerformAction(windowElement, kAXRaiseAction)` raises that specific window within its app, then `NSRunningApplication.activate()` brings the app forward. Together these focus the exact window. This is the approach used by alt-tab-macos and other window switchers.

The current architecture passes a shell command string through the item dictionary and executes it via `CommandRunner.run()`. To focus a specific window we need to keep a reference to the `AXUIElement` and call the Accessibility API directly — a shell command cannot carry an AXUIElement reference.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/Services/Window/WindowFocuser.swift` | **New file** — raises a specific AXUIElement window and activates its app |
| `UnnamedMenu/Services/Window/WindowsGenerator.swift` | Modify — store window AXUIElement references alongside items; stop generating osascript commands for windows |
| `UnnamedMenu/Models/LauncherItem.swift` | Modify — add optional `AXUIElement` (or window-focus closure) to the item model |
| `UnnamedMenu/Views/LauncherView.swift` | Modify — call `WindowFocuser` when item has a window reference, fall back to `CommandRunner` otherwise |

---

## Implementation Steps

### 1. Create `WindowFocuser`

A small utility that focuses a specific window given its `AXUIElement` and owning PID.

```swift
// WindowFocuser.swift
import AppKit
import ApplicationServices

enum WindowFocuser {
    static func focus(window: AXUIElement, pid: pid_t) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }
}
```

`AXRaise` moves the window above its siblings within the app. `activate()` brings the app to the foreground. Order matters — raise first, then activate, so macOS doesn't re-sort windows before our raise takes effect.

### 2. Extend the item model to carry a window reference

The current item model uses `[String: String]` dictionaries with a `command` key. Add an optional `windowElement: AXUIElement?` and `pid: pid_t?` to whichever model backs `filteredCommands`. The exact shape depends on whether items are structs or dictionaries — check `LauncherItem` / the type of `filteredCommands`.

If items are `[String: String]` dicts today, refactoring to a struct (or adding a parallel lookup) is needed since `AXUIElement` cannot be stored as a `String`. A lightweight approach: give `WindowsGenerator` a `windowElements: [Int: (AXUIElement, pid_t)]` dictionary keyed by item index, and store the index in the item dict as `"windowIndex"`.

### 3. Update `WindowsGenerator.generateItems()`

For each enumerated window:

1. Store the `AXUIElement` and `pid` in the side table.
2. Put the side-table key (e.g. `"windowIndex": "\(idx)"`) in the item dict.
3. Stop generating the osascript command for window items (keep it as fallback for items without an AX element).

```swift
// Inside the axWindows loop (lines 122-129):
let idx = windowElements.count
windowElements[idx] = (window, pid)
items.append([
    "name": name,
    "windowIndex": "\(idx)",
    "systemImage": iconValue
])
```

### 4. Update `runSelected()` in `LauncherView`

```swift
private func runSelected() {
    guard filteredCommands.indices.contains(selectedIndex) else { return }
    let item = filteredCommands[selectedIndex]
    hideWindow()
    if let windowIndex = item.windowIndex,
       let (axWindow, pid) = windowStore[windowIndex] {
        WindowFocuser.focus(window: axWindow, pid: pid)
    } else if let command = item.command {
        try? CommandRunner.run(command)
    }
}
```

---

## Key Technical Notes

- `AXUIElement` references are only valid while the window exists. If a window closes between enumeration and selection, `AXRaise` will fail silently — this is acceptable (same as the current osascript failing for a dead PID).
- The brute-force enumerated windows from other spaces may not respond to `AXRaise` until the user switches to that space. `activate()` will switch to the space if the app has no windows on the current space, which is the correct behavior.
- `AXUIElementPerformAction` requires accessibility permissions — the app already has these since it uses `AXUIElementCopyAttributeValue` today.
- The osascript command path should remain as a fallback for any items that lack an AXUIElement (e.g. apps with no enumerable windows).
- Window visit tracking (`WindowVisitTracker`) currently tracks by PID only. This plan does not change that — per-window visit tracking can be a follow-up.

---

## Verification

1. Open two Firefox windows with different tabs (distinct titles) → open switcher → confirm both listed as "Firefox - Tab A" and "Firefox - Tab B"
2. Select "Firefox - Tab B" → window B is raised and focused, not window A
3. Repeat with window A → window A is raised
4. Test with a single-window app (e.g. Calculator) → behaves as before
5. Test with an app that has no AX windows (edge case) → falls back to osascript, app comes to front
6. Close one Firefox window → select the remaining one → still works
7. Test with windows on different spaces → selecting a window switches to the correct space
