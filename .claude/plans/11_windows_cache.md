# Plan: 11_windows_cache — Live window cache for fast --windows output

## Checklist

- [x] Extract `generateItems(allScreens:) -> [[String: String]]` from `WindowsGenerator`
- [x] Create `WindowCache.swift` — build/read cache file in `$TMPDIR`
- [x] Call `WindowCache.rebuild()` from `AppDelegate` on launch (main instance only)
- [x] Subscribe to `NSWorkspace` notifications → rebuild cache on app open/close/space change
- [x] Modify `--windows` early-exit path to read cache file before live enumeration

---

## Context / Problem

`--windows` currently re-enumerates all windows via `CGWindowListCopyWindowInfo` and AX every invocation. This is slow (~200–400 ms) and wakes the GPU compositor.

The main instance is a persistent background process. It should observe window lifecycle events and maintain a pre-built JSON cache on disk. When `--windows` is invoked (always as a secondary process after the first launch), it reads the cache file and prints it immediately, then exits.

---

## Behaviour spec

- Main instance writes `$TMPDIR/com.unnamedmenu.windows.json` on:
  - Launch (initial build)
  - App launch / terminate (workspace notifications)
  - Active Space change
  - App activation (z-order changes for front-to-back ordering)
- Always enumerates windows from all screens (no single-screen filter).
- `--windows` reads the cache file; if absent (main instance not yet started), falls back to live enumeration.
- Cache file is replaced atomically (`.atomic` write option) — no torn reads.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/WindowsGenerator.swift` | Modify — extract `generateItems(allScreens:)` returning `[[String: String]]`; `generateForCLI` delegates to it |
| `UnnamedMenu/WindowCache.swift` | **New file** — `rebuild()` writes both cache files; `read(allScreens:)` returns cached JSON string |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — call `WindowCache.rebuild()` on launch + workspace observer; read cache in `--windows` path |

---

## Implementation Steps

### 1. Extract `generateItems` from `WindowsGenerator`

Rename the body of `generateForCLI` into a new method that returns items without printing or calling `exit()`:

```swift
func generateItems(allScreens: Bool = false) -> [[String: String]] {
    // ... existing logic, return items instead of serializing/printing
}

func generateForCLI(allScreens: Bool = false) {
    let items = generateItems(allScreens: allScreens)
    let data = (try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted])) ?? Data("[]".utf8)
    print(String(data: data, encoding: .utf8) ?? "[]")
    exit(0)
}
```

### 2. Create `WindowCache.swift`

```swift
import Foundation

enum WindowCache {
    private static func cachePath(allScreens: Bool) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(allScreens
                ? "com.unnamedmenu.windows-all.json"
                : "com.unnamedmenu.windows.json")
    }

    static func rebuild() {
        let generator = WindowsGenerator()
        for allScreens in [false, true] {
            let items = generator.generateItems(allScreens: allScreens)
            guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]) else { continue }
            try? data.write(to: cachePath(allScreens: allScreens), options: .atomic)
        }
    }

    static func read(allScreens: Bool) -> String? {
        try? String(contentsOf: cachePath(allScreens: allScreens), encoding: .utf8)
    }
}
```

### 3. Call `WindowCache.rebuild()` on launch (main instance only)

In `AppDelegate.applicationDidFinishLaunching`, after `appState.reload()`:

```swift
WindowCache.rebuild()
```

### 4. Subscribe to workspace notifications

Still inside `applicationDidFinishLaunching`, after the rebuild call:

```swift
let nc = NSWorkspace.shared.notificationCenter
for name in [
    NSWorkspace.didLaunchApplicationNotification,
    NSWorkspace.didTerminateApplicationNotification,
    NSWorkspace.activeSpaceDidChangeNotification,
    NSWorkspace.didActivateApplicationNotification,
] {
    nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        WindowCache.rebuild()
    }
}
```

### 5. Read cache in `--windows` early-exit path

Replace the existing `--windows` block in `applicationDidFinishLaunching`:

```swift
if CommandLine.arguments.contains("--windows") {
    let allScreens = CommandLine.arguments.contains("--all-screens")
    if let cached = WindowCache.read(allScreens: allScreens) {
        print(cached)
        exit(0)
    }
    // Main instance not running or cache not yet written — fall back to live enumeration
    WindowsGenerator().generateForCLI(allScreens: allScreens)
}
```

---

## Key Technical Notes

- Both cache files are always rebuilt together in `rebuild()` — one call covers both `--windows` and `--windows --all-screens` cases.
- `rebuild()` runs on the main queue (workspace notifications arrive there). `WindowsGenerator.generateItems` uses `NSWorkspace.shared.runningApplications` and `NSScreen.screens`, both of which must be called on the main thread.
- `--windows` is in the early-exit path before the lock-file check, so it runs in both main and secondary instances. The secondary instance reads the cache written by the main instance.
- If the main instance is not running (first ever launch, or user killed it), `WindowCache.read` returns `nil` and the fallback path does a live enumeration — same behaviour as before this plan.
- `.atomic` write (`write(to:options:.atomic)`) is a rename of a temp file, so a concurrent reader never sees a partial file.
- `NSWorkspace.didActivateApplicationNotification` fires on every app switch, which may be frequent. `generateItems` is cheap (~10 ms) so this is acceptable; no debouncing needed for MVP.
- Per-window AX events (`kAXWindowCreatedNotification`) are out of scope — app-level events cover the common cases (new app, closed app, Space switch).

---

## Verification

1. Launch app, open several apps → `UnnamedMenu --windows` prints instantly (no perceptible delay).
2. Open a new app → within one activation cycle, `UnnamedMenu --windows` includes it.
3. Close an app → `UnnamedMenu --windows` no longer lists it after the next workspace event.
4. Switch Spaces → `UnnamedMenu --windows` reflects windows on the new Space.
5. Kill the main instance → `UnnamedMenu --windows` falls back to live enumeration (still works).
6. `UnnamedMenu --windows --all-screens` reads the `-all` cache variant correctly.
7. Pipe still works: `UnnamedMenu --windows | UnnamedMenu` → launcher populated from cache.
