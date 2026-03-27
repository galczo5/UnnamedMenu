# Plan: 08_stdin_pipe_config — Pipe JSON into the launcher via stdin

## Checklist

- [x] Add `pipedItems`, `applyItems(_:)`, and update `visibleCommands`/`clearFilter()` in `AppState`
- [x] Detect stdin pipe and handle IPC or direct apply in `AppDelegate.applicationDidFinishLaunching`
- [x] Register for `pipeConfig` distributed notification and add handler in `AppDelegate`

---

## Context / Problem

`--config <path>` requires a file on disk. Users want to pipe JSON directly: `cat file.json | UnnamedMenu` or `echo '[...]' | UnnamedMenu`. The piped data should scope the launcher to those items, with the same single-instance rule as `--open` and `--config`.

---

## Behaviour spec

- If stdin is a pipe (not a TTY) and parses as `[CommandItem]`:
  - If an instance is already running: re-encode the items as a JSON string, post `com.unnamedmenu.pipeConfig` notification, exit.
  - If no instance is running: store items as `pendingPipedItems`, launch normally, apply after setup.
- If stdin is not a pipe, or the data fails to decode: ignore and proceed as normal.
- Piped items are not cached by URL (there is no file). `clearFilter()` also clears them, so the next normal open shows all commands.

---

## macOS / stdin note

`isatty(STDIN_FILENO) == 0` reliably detects a pipe when the binary is invoked directly from a shell. If stdin is `/dev/null` (Launch Services launch), reading it yields empty data which fails JSON decoding — so the app falls through without any special-case handling needed.

`FileHandle.standardInput.readDataToEndOfFile()` is synchronous and must be called before the run loop starts. It is safe here because it runs before any GUI setup in `applicationDidFinishLaunching`.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/AppState.swift` | Modify — add `pipedItems`, `applyItems(_:)`, update `visibleCommands` and `clearFilter()` |
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — detect stdin, handle IPC, register/handle `pipeConfig` notification |

---

## Implementation Steps

### 1. Extend `AppState`

Add a separate property for piped items (no URL key needed — there is no backing file).

```swift
@Published var pipedItems: [CommandItem]? = nil

var visibleCommands: [CommandItem] {
    if let piped = pipedItems        { return piped }
    if let filter = activeFilter     { return itemsByURL[filter] ?? [] }
    return commands
}

func applyItems(_ items: [CommandItem]) {
    pipedItems = items
}

func clearFilter() {
    activeFilter = nil
    pipedItems = nil
}
```

### 2. Detect stdin pipe in `AppDelegate`

Add a stored property and read stdin at the very top of `applicationDidFinishLaunching`, before the `--applications` / `--config` checks:

```swift
private var pendingPipedItems: [CommandItem]?
```

```swift
// Top of applicationDidFinishLaunching, before other flag checks:
if isatty(STDIN_FILENO) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let items = try? JSONDecoder().decode([CommandItem].self, from: data), !items.isEmpty {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != myPID }
        if others.first != nil {
            if let json = String(data: data, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.pipeConfigNotification),
                    object: nil,
                    userInfo: ["json": json],
                    deliverImmediately: true
                )
            }
            exit(0)
        }
        pendingPipedItems = items
    }
}
```

### 3. Apply pending piped items after setup

After `panel.orderFrontRegardless()`, alongside the existing `pendingConfigURL` check:

```swift
if let items = pendingPipedItems {
    appState.applyItems(items)
}
```

### 4. Register for the notification and add the handler

Add the constant alongside the others:

```swift
private static let pipeConfigNotification = "com.unnamedmenu.pipeConfig"
```

Register in `applicationDidFinishLaunching` alongside the existing observers:

```swift
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(pipeConfigFromNotification(_:)),
    name: NSNotification.Name(AppDelegate.pipeConfigNotification),
    object: nil
)
```

Handler:

```swift
@objc private func pipeConfigFromNotification(_ note: Notification) {
    guard let json = note.userInfo?["json"] as? String,
          let data = json.data(using: .utf8),
          let items = try? JSONDecoder().decode([CommandItem].self, from: data) else { return }
    appState.applyItems(items)
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

---

## Key Technical Notes

- `isatty` and `readDataToEndOfFile` require `import Darwin` (already available via Foundation on macOS).
- `readDataToEndOfFile` blocks until the pipe writer closes — for `cat file.json | app` this is immediate. For a long-running producer it would block launch, but that is expected behaviour for a pipe consumer.
- The JSON string is re-encoded from the original `data` bytes (not from the decoded struct) to avoid any re-serialisation roundtrip issues with UUID ids.
- `DistributedNotificationCenter` userInfo values must be property-list types. A JSON string fits; raw `Data` does not.
- `pipedItems` takes priority over `activeFilter` in `visibleCommands` so that `cat ... | app --config file.json` (unlikely but possible) uses the pipe.
- `clearFilter()` already resets search text indirectly via `@Published activeFilter` re-render; adding `pipedItems = nil` there is sufficient.

---

## Verification

1. `cat test.json | UnnamedMenu` (app not running) → launches, panel shows only items from `test.json`.
2. `cat test.json | UnnamedMenu` (app running) → no new instance; panel activates showing only piped items.
3. Close panel → `--open` → panel shows all commands (piped filter cleared).
4. `echo 'not json' | UnnamedMenu` → app launches normally with all commands (graceful ignore).
5. `UnnamedMenu` with no pipe → behaviour unchanged.
6. `cat test.json | UnnamedMenu --applications` → `--applications` check runs first, prints JSON, exits — pipe is irrelevant.
