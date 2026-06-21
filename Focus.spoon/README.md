# Focus.spoon

Hammerspoon Spoon for focus/break cycles with a configurable timer, blocking break overlay, optional sounds, menubar controls, and optional hotkeys.

Focus supports flow mode for pausing scheduled breaks while staying in deep work, and handles sleep/lock events so timer state is restored safely.

## Requirements

- Hammerspoon

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/Focus.spoon/
```

Or distribute it as `Focus.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("Focus")
spoon.Focus:start()
```

By default, Focus uses a 55-minute focus interval, a 5-minute break interval, a 5-minute postpone interval, notification sounds, countdown display, and a menubar item.

## Configuration

Configure Focus by passing a table to `start()` or by using setter methods:

```lua
hs.loadSpoon("Focus")

spoon.Focus:start({
  focusTime = 55,
  breakTime = 5,
  postponeTime = 5,
  playSound = true,
  showTimer = true,
  showMenuBar = true,
  hotkeys = {
    toggleFlow = {{"cmd", "alt", "ctrl"}, "f"},
    takeBreak = {{"cmd", "alt", "ctrl"}, "b"},
    start = {{"cmd", "alt", "ctrl"}, "s"},
    stop = {{"cmd", "alt", "ctrl"}, "x"},
  },
})
```

Time values in `start()` are specified in minutes and must be positive numbers.

## Hotkeys

Hotkeys are optional:

```lua
spoon.Focus:bindHotkeys({
  toggleFlow = {{"cmd", "alt", "ctrl"}, "f"},
  takeBreak = {{"cmd", "alt", "ctrl"}, "b"},
})

spoon.Focus:start()
```

Supported hotkey actions:

- `toggleFlow` — toggle flow mode. In flow mode, the focus timer is paused.
- `takeBreak` — start a break immediately.
- `start` — start Focus.
- `stop` — stop Focus and clean up timers, watchers, overlays, and the menubar item.

## Behavior

1. `start()` applies configuration, starts system watchers, creates the menubar item when enabled, and starts the focus timer.
2. Focus alternates focus and break phases using configurable durations.
3. Breaks show a full-screen overlay with a short wellness tip and optional countdown.
4. Flow mode pauses focus/break cycles while keeping quick menubar control available.
5. Sleep and lock events stop active timers and restore the appropriate state on wake/unlock.
6. During a break, emergency exit is available with Cmd+Alt+Shift+E.
7. `stop()` removes timers, watchers, event taps, overlays, and menubar items.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `Focus:init()` — initialize the Spoon.
- `Focus:start([config])` — configure and start Focus.
- `Focus:stop()` — stop Focus and clean up runtime state.
- `Focus:configure([config])` — apply configuration without starting the timer.
- `Focus:bindHotkeys(mapping)` — bind hotkeys for supported Focus actions.
- `Focus:toggleFlow()` — toggle flow mode.
- `Focus:takeBreak()` — start a break immediately.
- `Focus:getStatus()` — return current runtime state.

Configuration setters:

- `Focus:setFocusTime(minutes)`
- `Focus:setBreakTime(minutes)`
- `Focus:setPostponeTime(minutes)`
- `Focus:setOverlayColor(color)`
- `Focus:setShowTimer(show)`
- `Focus:setPlaySound(play)`
- `Focus:setShowMenuBar(show)`

Public properties:

- `Focus.focusTime`
- `Focus.breakTime`
- `Focus.overlayColor`
- `Focus.showTimer`
- `Focus.playSound`
- `Focus.showMenuBar`
- `Focus.postponeTime`
- `Focus.breakTips`

## Assets

The Spoon includes menu bar icons loaded with `hs.spoons.resourcePath()`:

- `Focus-active.pdf`
- `Focus-inactive.pdf`

## License

MIT — see <https://opensource.org/licenses/MIT>.
