# Plan: 01_ui_polish — Fix window chrome, unify colors, scroll, and list height

## Checklist

- [x] Remove window controls and title bar
- [x] Unify background color (transparent List over vibrancy)
- [x] Fix arrow-key auto-scroll with ScrollViewReader
- [x] Lock visible list height to exactly 5 rows

---

## Context / Problem

The launcher window currently has four visual/functional issues:

1. **Window controls visible** — Traffic lights (close/minimize/zoom) and the title "UnnamedMenu" appear even though the code sets `.borderless`. This happens because `WindowGroup` creates a standard `NSWindow` first, and SwiftUI's window management can re-apply the title bar after the async override.
2. **Colors not unified** — The `List` renders with its own opaque white/dark background, breaking the frosted-glass look. The vibrancy material is visible above/below the list but not behind it.
3. **Arrow-key scroll broken** — `selectedIndex` updates correctly, but `List` doesn't scroll to the selected row because SwiftUI's `List` doesn't auto-scroll to items styled with a manual `isSelected` flag. A `ScrollViewReader` + `scrollTo()` is needed.
4. **List height** — The user wants exactly 5 options visible at all times (the current 8 defaults should scroll).

---

## macOS window note

`WindowGroup` always creates an `NSWindow` with a standard title bar. Overriding `styleMask` in `applicationDidFinishLaunching` races with SwiftUI's own window setup. The clean fix is to replace the `DispatchQueue.main.async` hack with the `.windowStyle(.hiddenTitleBar)` scene modifier **and** hide the traffic-light buttons explicitly in `applicationDidFinishLaunching`. This avoids the race entirely.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/UnnamedMenuApp.swift` | Modify — add `.windowStyle(.hiddenTitleBar)`, hide traffic lights, set window background |
| `UnnamedMenu/LauncherView.swift` | Modify — wrap List in ScrollViewReader, add `scrollTo` on selection change, make List background transparent, fix list height to 5 rows |

---

## Implementation Steps

### 1. Remove window controls and title bar

In `UnnamedMenuApp.swift`:

- Add `.windowStyle(.hiddenTitleBar)` to the `WindowGroup` scene to prevent the title bar from appearing.
- In `applicationDidFinishLaunching`, explicitly hide the traffic-light buttons:

```swift
window.standardWindowButton(.closeButton)?.isHidden = true
window.standardWindowButton(.miniaturizeButton)?.isHidden = true
window.standardWindowButton(.zoomButton)?.isHidden = true
```

- Keep the existing `.borderless` style mask, `backgroundColor = .clear`, `isOpaque = false`, floating level, and shadow.

### 2. Unify background colors

In `LauncherView.swift`:

- Add `.scrollContentBackground(.hidden)` to the `List` so SwiftUI removes the default opaque list background. This lets the `VisualEffectView` show through uniformly behind the entire panel.

### 3. Fix arrow-key auto-scroll

In `LauncherView.swift`:

- Wrap the `List` in a `ScrollViewReader`.
- After updating `selectedIndex` in `moveSelection(_:)`, call `proxy.scrollTo(targetID, anchor: ...)` to ensure the newly selected row is visible.
- This requires storing a reference to the `ScrollViewProxy` (e.g., via a `@State` or by using an `onChange(of: selectedIndex)` inside the `ScrollViewReader` scope).

```swift
ScrollViewReader { proxy in
    List(Array(filteredCommands.enumerated()), id: \.element.id) { index, item in
        CommandRow(item: item, isSelected: index == selectedIndex)
            .id(item.id)
            // ... existing modifiers
    }
    .onChange(of: selectedIndex) { _, newIndex in
        guard filteredCommands.indices.contains(newIndex) else { return }
        withAnimation {
            proxy.scrollTo(filteredCommands[newIndex].id, anchor: nil)
        }
    }
}
```

### 4. Lock visible list height to 5 rows

Each `CommandRow` is roughly 50pt tall (6pt vertical padding x2 + ~14pt title + ~12pt subtitle + 2pt spacing + row insets). Five rows = ~270pt. Replace `.frame(maxHeight: 260)` with a fixed `.frame(height: 270)` to always show exactly 5 rows regardless of how many items exist.

Fine-tune the exact pixel value after step 3 is done — measure a single row's rendered height and multiply by 5.

---

## Key Technical Notes

- `.scrollContentBackground(.hidden)` requires macOS 13+. The project already uses `.onKeyPress` which requires macOS 14+, so this is fine.
- `scrollTo` with `anchor: nil` lets SwiftUI pick the minimal scroll to make the item visible (no jump if already on-screen).
- The `VisualEffectView` with `.hudWindow` material adapts to light/dark mode automatically — no manual color management needed.
- The `WindowGroup` + `.windowStyle(.hiddenTitleBar)` combo still creates a proper key window that can receive keyboard events, unlike a pure programmatic `NSPanel` approach which would require more boilerplate.

---

## Verification

1. Launch the app — window should have no traffic lights and no title bar
2. The entire panel background should show uniform frosted-glass vibrancy (no white/opaque list area)
3. Press down arrow repeatedly past the 5th item — list should scroll to keep the selected item visible
4. Press up arrow from a scrolled position — list should scroll back up
5. Exactly 5 rows should be visible at all times without scrolling
6. Search filtering, Enter to run, and Escape to close should still work
7. Verify in both light and dark mode — vibrancy should look correct in both
