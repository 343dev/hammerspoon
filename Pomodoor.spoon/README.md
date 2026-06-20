# Pomodoor.spoon

Hammerspoon Spoon that provides a Pomodoro timer with work/break cycles, menubar countdown, bundled notification sounds, and a daily pomodoro count.

## Requirements

- Hammerspoon
- Optional: Raycast, if you want confetti after completed work sessions

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/Pomodoor.spoon/
```

Or distribute it as `Pomodoor.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("Pomodoor")
spoon.Pomodoor:start()
```

## Hotkeys

Bind hotkeys explicitly from your Hammerspoon config:

```lua
hs.loadSpoon("Pomodoor")

spoon.Pomodoor:bindHotkeys({
  start = {{"cmd", "alt", "ctrl"}, "9"},
  pause = {{"cmd", "alt", "ctrl"}, "0"},
})

spoon.Pomodoor:start()
```

Supported hotkey actions are `start`, `pause`, and `stop`.

## Configuration

Configure public properties before calling `start()`:

```lua
hs.loadSpoon("Pomodoor")

spoon.Pomodoor.workingTime = 25 * 60
spoon.Pomodoor.breakTime = 5 * 60
spoon.Pomodoor.longBreakTime = 30 * 60
spoon.Pomodoor.longBreakEach = 6
spoon.Pomodoor.showRaycastConfetti = true

spoon.Pomodoor:start()
```

## Behavior

1. `init()` only prepares state and does not start timers/watchers or bind hotkeys.
2. `start()` creates the menubar item and starts or resumes the current session.
3. Completed work sessions increment the daily pomodoro count stored in `hs.settings`.
4. Every `longBreakEach` completed work sessions starts a long break; other completed work sessions start a short break.
5. When a break ends, Pomodoor plays `work.mp3` and centers a dialog asking whether to start the next work session.
6. `pause()` pauses the active timer without resetting remaining time; calling it again while the current work or break session is paused resets it.
7. `stop()` stops background activity, resets the current session, and removes the menubar item.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `Pomodoor:init()` - initialize the Spoon without side effects.
- `Pomodoor:start()` - start or resume the timer.
- `Pomodoor:pause()` - pause the active timer, or reset the current work/break session when already paused.
- `Pomodoor:stop()` - stop the Spoon and reset the current session.
- `Pomodoor:bindHotkeys(mapping)` - bind hotkeys for `start`, `pause`, and `stop` actions.

Public properties:

- `Pomodoor.workingTime`
- `Pomodoor.breakTime`
- `Pomodoor.longBreakTime`
- `Pomodoor.longBreakEach`
- `Pomodoor.breakSound`
- `Pomodoor.workSound`
- `Pomodoor.showRaycastConfetti`
- `Pomodoor.defaultHotkeys`

## License

MIT - see <https://opensource.org/licenses/MIT>.
