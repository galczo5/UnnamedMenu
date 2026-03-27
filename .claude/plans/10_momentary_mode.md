# Plan: 10_momentary_mode — --momentary: execute on cmd release

## Checklist

- [x] Add `momentaryMode: Bool` to `AppState`
- [x] Parse `--momentary` in `AppDelegate`, set `appState.momentaryMode = true` and `showAll = true`
- [x] Add cmd-release NSEvent monitor to `LauncherView` (start on appear, stop on hide)
- [x] On cmd release: run selected item then close panel

---

## Context / Problem

The user wants a keyboard-driven "cmd+key → tab cycle → release cmd" workflow, identical to macOS app-switcher (cmd+tab) but for UnnamedMenu items.

**Flow:**
1. External shortcut tool (Hammerspoon, skhd, etc.) launches `UnnamedMenu --momentary --open` while the user holds cmd.
2. Panel appears with all items visible. The selected index starts at 0.
3. Each Tab press advances the selection.
4. When cmd is released, the currently selected item executes and the panel closes.
5. Escape still cancels without executing.

---

## macOS event monitoring note

`NSEvent.addLocalMonitorForEvents(matching:handler:)` catches events only when **our app is the key application**. Because the panel calls `NSApp.activate(ignoringOtherApps: true)` before displaying, local monitoring is sufficient once the panel is on screen.

A global monitor (`addGlobalMonitorForEvents`) is not needed and requires no extra entitlements, but it fires **in addition to** local monitors — using only a local monitor keeps things simpler and avoids double-firing.

The monitor must be stored as `Any?` and removed with `NSEvent.removeMonitor(_:)` when the panel closes, otherwise it leaks.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/AppState.swift` | Modify — add `momentaryMode: Bool` |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — parse `--momentary`, set flags on appState |
| `UnnamedMenu/LauncherView.swift` | Modify — install/remove cmd-release monitor in momentary mode |

---

## Implementation Steps

### 1. Add `momentaryMode` to AppState

Add a single published property. No other logic changes needed here — `showAll` is already the mechanism that makes items visible without typing.

```swift
@Published var momentaryMode: Bool = false
```

`clearFilter()` should **not** reset `momentaryMode` — it's a startup mode, not a per-invocation filter.

### 2. Parse `--momentary` in AppDelegate

After the existing flag parsing block, add:

```swift
let momentaryFlag = CommandLine.arguments.contains("--momentary")
// ...
appState.momentaryMode = momentaryFlag
if momentaryFlag {
    appState.showAll = true
}
```

This runs after `appState.reload()` and before `showPanel()`, so `showAll` is set before the view renders.

When relaying to an existing instance via `--open`, the notification already carries the `all` field. Add a `momentary` field to the `userInfo` dict for the `showPanelNotification` similarly to how `all` is handled:

```swift
// In the --open relay block:
userInfo: ["all": showAllFlag ? "1" : "0", "momentary": momentaryFlag ? "1" : "0"]

// In showPanelFromNotification:
appState.momentaryMode = note.userInfo?["momentary"] as? String == "1"
if appState.momentaryMode { appState.showAll = true }
```

### 3. Cmd-release monitor in LauncherView

Add a `@State private var cmdMonitor: Any? = nil` to `LauncherView`.

Install the monitor in `.onAppear` (guarded by `appState.momentaryMode`) and remove it in a shared `stopMomentaryMonitor()` helper called from both `hideWindow()` and the monitor's own callback.

```swift
private func startMomentaryMonitor() {
    guard cmdMonitor == nil else { return }
    cmdMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [self] event in
        if !event.modifierFlags.contains(.command) {
            stopMomentaryMonitor()
            runSelected()   // runSelected already calls hideWindow()
        }
        return event
    }
}

private func stopMomentaryMonitor() {
    if let m = cmdMonitor { NSEvent.removeMonitor(m) }
    cmdMonitor = nil
}
```

Update `.onAppear`:
```swift
.onAppear {
    isSearchFocused = true
    if appState.momentaryMode { startMomentaryMonitor() }
}
```

Update `hideWindow()` to always clean up the monitor:
```swift
private func hideWindow() {
    stopMomentaryMonitor()
    appState.clearFilter()
    NSApp.keyWindow?.close()
}
```

No changes to `runSelected()` — it already calls `hideWindow()`.

---

## Key Technical Notes

- `addLocalMonitorForEvents` returns `Any?`; store it or the monitor is immediately removed.
- The monitor closure captures `self` (the View struct). Use `[self]` capture — SwiftUI Views are value types so there is no retain cycle.
- `runSelected()` calls `hideWindow()` which calls `stopMomentaryMonitor()`, so the monitor is always removed before the panel closes regardless of execution path.
- Tab already cycles selection in `LauncherView` (line 105). No change needed for tab handling.
- In momentary mode, `showAll = true` is set at launch, making all items visible immediately without the user typing anything.
- `clearFilter()` does **not** reset `momentaryMode`, so if the user somehow closes and reopens the panel in the same process instance, it remains in momentary mode as expected.
- Escape calls `hideWindow()` → `stopMomentaryMonitor()` → panel closes without executing. Correct behaviour.
- The `--momentary` flag composes naturally with `--config` and stdin pipe: those set the item list, `--momentary` controls how execution is triggered.

---

## Verification

1. Launch `UnnamedMenu --momentary` — panel opens with all items visible, no typing needed.
2. Hold cmd, press Tab → selection advances one row. Press Tab again → advances again.
3. Release cmd → selected item executes, panel closes.
4. Launch `UnnamedMenu --momentary` again, press Escape → panel closes, nothing executes.
5. Launch `UnnamedMenu --momentary` again, release cmd immediately before tabbing → first item executes (index 0).
6. Launch `UnnamedMenu --momentary --config path/to/config.json` → only items from that config are shown; cmd-release executes selected.
7. Normal launch without `--momentary` → cmd release does nothing (no monitor installed).
