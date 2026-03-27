# Plan: 06_cli_applications_flag — CLI `--applications` flag: generate and print applications.json

## Checklist

- [x] Add `generateForCLI()` to `ApplicationsGenerator.swift`
- [x] Add CLI flag check in `AppDelegate.applicationDidFinishLaunching`

---

## Context / Problem

The app currently only generates `applications.json` via the status bar menu item. Users want a headless CLI path: run the binary with `--applications`, get the JSON printed to stdout, and have the file written — no GUI launched.

---

## Behaviour spec

When the app is launched with `--applications`:

1. `ApplicationsGenerator` discovers all installed apps (same logic as the menu item).
2. Serializes to pretty-printed JSON.
3. Prints the JSON to stdout.
4. Process exits with code `0`. No status bar icon, no panel, no Dock icon. Nothing written to disk.

On failure (serialization error): prints the error to stderr and exits with code `1`.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/ApplicationsGenerator.swift` | Modify — add `generateForCLI()` that serializes, writes, and prints |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — check `--applications` at the top of `applicationDidFinishLaunching` and exit early |

---

## Implementation Steps

### 1. Add `generateForCLI()` to `ApplicationsGenerator`

Extract the serialization step so both `generate()` (write-only) and `generateForCLI()` (write + print) share the same data path.

```swift
/// Discovers apps, serializes to JSON, and prints to stdout.
/// Exits the process — only call from a CLI context.
func generateForCLI() {
    let entries = discoverApps()
    guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys]),
          let json = String(data: data, encoding: .utf8) else {
        fputs("[ApplicationsGenerator] Failed to serialize JSON\n", stderr)
        exit(1)
    }
    print(json)
    exit(0)
}
```

### 2. Guard on `--applications` at the top of `applicationDidFinishLaunching`

Insert the check as the very first statement so no GUI objects are created.

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--applications") {
        ApplicationsGenerator().generateForCLI()
        // generateForCLI() calls exit() — execution never reaches here
    }

    NSApp.setActivationPolicy(.accessory)
    // ... rest of existing setup unchanged ...
}
```

---

## Key Technical Notes

- `generateForCLI()` calls `exit()` directly — it does not return. Callers don't need to guard the return value.
- `fputs(_:_:)` writes to stderr without a newline being added; `\n` must be included explicitly.
- The flag check must be before `NSApp.setActivationPolicy(.accessory)` to avoid any dock/status bar flicker.
- Nothing is written to disk — stdout is the only output, making it safe to pipe/redirect.
- The app binary is typically at `UnnamedMenu.app/Contents/MacOS/UnnamedMenu`; users invoke it as `./UnnamedMenu --applications` or via a symlink.

---

## Verification

1. Build and run: `./UnnamedMenu.app/Contents/MacOS/UnnamedMenu --applications` → JSON array printed to stdout, no GUI appears.
2. Confirm `~/.config/unnamed/menu/applications.json` is **not** created or modified.
3. Run without flag → app launches normally with status bar icon and panel.
4. Redirect output: `./UnnamedMenu.app/Contents/MacOS/UnnamedMenu --applications > out.json` → `out.json` is valid JSON parseable by `jq`.
