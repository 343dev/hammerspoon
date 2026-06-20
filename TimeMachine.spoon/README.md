# TimeMachine.spoon

Hammerspoon Spoon that displays active Time Machine backup progress in the macOS menubar.

The Spoon polls macOS `tmutil status` and shows a compact two-line menubar item only while a Time Machine backup is running. It displays backup progress and estimated remaining time when available; otherwise it stays hidden.

## Requirements

- Hammerspoon
- macOS with Time Machine and `/usr/bin/tmutil` available

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/TimeMachine.spoon/
```

Or distribute it as `TimeMachine.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("TimeMachine")
spoon.TimeMachine:start()
```

Click the menubar item while a backup is visible to open Time Machine settings.

## Configuration

Configure public properties before calling `start()`:

```lua
hs.loadSpoon("TimeMachine")

spoon.TimeMachine.checkInterval = 60 -- seconds between checks when idle
spoon.TimeMachine.fastInterval = 1   -- seconds between checks during backup

spoon.TimeMachine:start()
```

## Hotkeys

Hotkeys are optional:

```lua
spoon.TimeMachine:bindHotkeys({
  check = {{"cmd", "alt", "ctrl"}, "t"},
  openPreferences = {{"cmd", "alt", "ctrl"}, "b"},
})
```

## Behavior

1. `start()` creates a menubar item and schedules periodic checks.
2. The Spoon runs `/usr/bin/tmutil status` asynchronously via `hs.task`.
3. When a backup is running, the menubar shows `Time Machine` plus progress/remaining time.
4. When no backup is running, the menubar item is hidden.
5. `stop()` terminates any active `tmutil` task, stops timers, and removes the menubar item.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `TimeMachine:start()` — start periodic Time Machine monitoring.
- `TimeMachine:stop()` — stop timers and remove the menubar item.
- `TimeMachine:check()` — run one status check immediately.
- `TimeMachine:openPreferences()` — open Time Machine settings.
- `TimeMachine:bindHotkeys(mapping)` — bind optional hotkeys.

Public properties:

- `TimeMachine.checkInterval`
- `TimeMachine.fastInterval`
- `TimeMachine.logger`

## License

MIT — see <https://opensource.org/licenses/MIT>.
