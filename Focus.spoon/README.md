# Focus.spoon

`Focus.spoon` is a Hammerspoon Spoon for focus/break cycles. It runs a configurable focus timer, shows a blocking break overlay, can play notification sounds, and provides a menu bar item plus optional hotkeys for quick control.

## Features

- Configurable focus and break intervals.
- Full-screen break overlay with a short wellness tip.
- Optional countdown display.
- Optional notification sound at break transitions.
- Menu bar controls for flow mode and manual breaks.
- Flow mode for pausing focus/break cycles while staying in deep work.
- Configurable hotkeys via the standard Spoon `bindHotkeys(mapping)` pattern.
- Sleep/lock handling to stop and restore timer state safely.

## Installation

Place `Focus.spoon` in your Hammerspoon Spoons directory:

```text
~/.hammerspoon/Spoons/Focus.spoon
```

Then load it from your Hammerspoon config:

```lua
hs.loadSpoon("Focus")
```

## Quick start

```lua
hs.loadSpoon("Focus")
spoon.Focus:start()
```

By default, Focus uses:

- `focusTime = 55` minutes
- `breakTime = 5` minutes
- `postponeTime = 5` minutes
- `playSound = true`
- `showTimer = true`
- `showMenuBar = true`

## Configuration on start

You can configure the Spoon when starting it:

```lua
hs.loadSpoon("Focus")

spoon.Focus:start({
  focusTime = 55,
  breakTime = 5,
  postponeTime = 5,
  playSound = true,
  showTimer = true,
  hotkeys = {
    toggleFlow = {{"cmd", "alt", "ctrl"}, "f"},
    takeBreak = {{"cmd", "alt", "ctrl"}, "b"},
    start = {{"cmd", "alt", "ctrl"}, "s"},
    stop = {{"cmd", "alt", "ctrl"}, "x"},
  },
})
```

Time values are specified in minutes and must be positive numbers.

## Hotkeys

Supported hotkey actions:

| Action | Description |
| --- | --- |
| `toggleFlow` | Toggle flow mode. In flow mode, the focus timer is paused. |
| `takeBreak` | Start a break immediately. |
| `start` | Start Focus. |
| `stop` | Stop Focus and clean up timers, watchers, overlays, and the menu bar item. |

You can also bind hotkeys separately:

```lua
spoon.Focus:bindHotkeys({
  toggleFlow = {{"cmd", "alt", "ctrl"}, "f"},
  takeBreak = {{"cmd", "alt", "ctrl"}, "b"},
})

spoon.Focus:start()
```

## Menu bar

When `showMenuBar` is enabled, Focus adds a menu bar item with:

- `Flow` — toggles flow mode.
- `Take a Break` — starts a break immediately.

## Public API

### `Focus:init()`

Initializes the Spoon. Called automatically by `hs.loadSpoon("Focus")`.

### `Focus:start([config])`

Configures and starts Focus.

Optional `config` fields:

- `focusTime` — focus interval length in minutes; must be a positive number.
- `breakTime` — break interval length in minutes; must be a positive number.
- `postponeTime` — postpone duration in minutes; must be a positive number.
- `playSound` — boolean, enables or disables notification sounds.
- `showTimer` — boolean, enables or disables the on-screen countdown.
- `hotkeys` — hotkey mapping table passed to `Focus:bindHotkeys(mapping)`.

Returns the Focus object.

### `Focus:stop()`

Stops Focus and removes all timers, watchers, event taps, overlays, and menu bar items.

Returns the Focus object.

### `Focus:configure([config])`

Applies configuration without starting the timer.

Returns the Focus object.

### `Focus:bindHotkeys(mapping)`

Binds hotkeys for supported Focus actions.

Returns the Focus object.

### `Focus:toggleFlow()`

Toggles flow mode.

Returns the Focus object.

### `Focus:takeBreak()`

Starts a break immediately.

Returns the Focus object.

### `Focus:getStatus()`

Returns a table with current runtime state, including timer phase, remaining time, configured durations, flow mode state, sound/timer settings, and related flags.

### Configuration setters

All setters return the Focus object:

- `Focus:setFocusTime(minutes)` — `minutes` must be a positive number.
- `Focus:setBreakTime(minutes)` — `minutes` must be a positive number.
- `Focus:setPostponeTime(minutes)` — `minutes` must be a positive number.
- `Focus:setOverlayColor(color)`
- `Focus:setShowTimer(show)`
- `Focus:setPlaySound(play)`
- `Focus:setShowMenuBar(show)`

## Emergency exit

During a break, Focus blocks many keyboard and pointer events to keep the break interruption effective. Emergency exit is available with:

```text
cmd + alt + shift + E
```

## Assets

The Spoon includes menu bar icons:

- `Focus-active.pdf`
- `Focus-inactive.pdf`

They are loaded using `hs.spoons.resourcePath()`.
