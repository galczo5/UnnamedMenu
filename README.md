# UnnamedMenu

A macOS status bar application providing a floating command launcher with fuzzy search. Commands are configured in JSON files under `~/.config/unnamed/menu/`.

## CLI Options

| Option | Description |
|--------|-------------|
| `--open` | Show the launcher panel |
| `--config <path>` | Load a specific JSON config file |
| `--all` | Show all search results (default: top 5) |
| `--applications` | Print all installed applications as JSON and exit |
| `--windows` | Print all open windows as JSON and exit |
| `--all-screens` | Modifier for `--windows`: include windows from all screens (default: current screen only) |

## Notes

- Only one instance runs at a time; subsequent invocations communicate with the running instance via notifications.
- `--applications` and `--windows` are CLI-only modes — no UI is started.
- Piped JSON input is automatically detected and processed.
