# Plan: 05_fuzzy_search — Replace substring search with fuzzy matching

## Checklist

- [x] Create `FuzzyMatcher.swift` with custom subsequence-matching algorithm
- [x] Replace `filteredCommands` in `LauncherView` with scored + sorted fuzzy results
- [ ] Verify search feels snappy and rankings are sensible

---

## Context / Problem

Current filtering uses `localizedCaseInsensitiveContains`, which only matches substrings.
A user typing "gc" gets no results for "Git Commit", and "vsc" won't find "Visual Studio Code".
Fuzzy search (subsequence matching with scoring) is the standard for launchers like Alfred, Raycast, and Spotlight — it dramatically improves usability when you have many items.

---

## Library Research

The Swift ecosystem has no dominant fuzzy search library (the most-starred option, fuse-swift at 944 stars, was archived in 2022; all active alternatives have <200 stars). A self-contained implementation is the right call: ~70 lines, zero dependencies, zero maintenance risk, full control over scoring heuristics.

**Algorithm: scored subsequence matching**

A query matches a string if all query characters appear in order within the string (subsequence check). The score rewards:
- Consecutive character runs (typing "git" matches all three in a row → high score)
- Start-of-word matches (character follows a space, dash, or slash)
- Earlier match position (match near the start of the string ranks higher)

This is the same approach used by VS Code's command palette and most terminal launchers.

---

## Files to create / modify

| File | Action |
|------|--------|
| `UnnamedMenu/FuzzyMatcher.swift` | **New file** — self-contained fuzzy match + score function |
| `UnnamedMenu/LauncherView.swift` | Modify — replace `filteredCommands` with scored + sorted fuzzy results |

---

## Implementation Steps

### 1. Create `FuzzyMatcher.swift`

```swift
import Foundation

struct FuzzyMatcher {
    /// Returns nil if query is not a subsequence of string; otherwise returns a score
    /// where higher is a better match.
    static func score(query: String, in string: String) -> Double? {
        let q = query.lowercased()
        let s = string.lowercased()
        guard !q.isEmpty else { return 1.0 }

        var qi = q.startIndex
        var si = s.startIndex
        var score = 0.0
        var consecutive = 0
        var prevMatched = false

        while si < s.endIndex && qi < q.endIndex {
            let sc = s[si]
            let qc = q[qi]

            if sc == qc {
                // Consecutive bonus
                consecutive += 1
                score += Double(consecutive) * 2.0

                // Start-of-word bonus
                if si == s.startIndex {
                    score += 8.0
                } else {
                    let prev = s[s.index(before: si)]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
                        score += 6.0
                    }
                }

                // Earlier position bonus (decays linearly)
                let position = s.distance(from: s.startIndex, to: si)
                score += max(0, 10.0 - Double(position) * 0.5)

                prevMatched = true
                qi = q.index(after: qi)
            } else {
                if prevMatched { consecutive = 0 }
                prevMatched = false
            }

            si = s.index(after: si)
        }

        // All query characters must be matched
        guard qi == q.endIndex else { return nil }
        return score
    }
}
```

### 2. Replace `filteredCommands` in `LauncherView.swift`

Replace the existing `filteredCommands` computed property (lines 17–23):

```swift
var filteredCommands: [CommandItem] {
    guard !searchText.isEmpty else { return appState.commands }

    return appState.commands
        .compactMap { item -> (score: Double, item: CommandItem)? in
            let nameScore = FuzzyMatcher.score(query: searchText, in: item.name)
            let cmdScore  = FuzzyMatcher.score(query: searchText, in: item.command)
            guard let best = [nameScore, cmdScore].compactMap({ $0 }).max() else { return nil }
            return (best, item)
        }
        .sorted { $0.score > $1.score }   // higher score = better match
        .map { $0.item }
}
```

---

## Key Technical Notes

- Score is higher-is-better (opposite of Fuse.js). Sort descending.
- `consecutive` resets to 0 on a non-matching character so only actual runs are rewarded.
- The `position` penalty ensures "Safari" ranks above "Accessories/Safari" for query "sa".
- Both `name` and `command` are scored; the best of the two determines the item's rank.
- The algorithm is O(n × m) per item (n = string length, m = query length) and is fast enough for thousands of items on the main thread without any background dispatch.
- `selectedIndex` reset on `searchText` change is already wired in `onChange(of: searchText)` — no change needed there.

---

## Verification

1. Launch the panel, type `gc` → "Git Commit" (or similar) appears ranked at top
2. Type `vsc` → "Visual Studio Code" appears if present in applications.json
3. Type an exact name → exact match is ranked first, before partial matches
4. Clear the search field → all items reappear in original order
5. Type gibberish (e.g. `zzzzz`) → list is empty, no crash
6. Navigate with arrow keys after fuzzy results appear → selection works correctly
