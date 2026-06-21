# CMDLayoutSwitcher.spoon

Hammerspoon Spoon that selects the macOS keyboard layout by tapping a Command key on its own.

Left Command switches to `leftLayout`; Right Command switches to `rightLayout`. Command combinations such as Cmd+A, Cmd+C, Cmd+Tab, and Cmd+Shift+3 are ignored.

## Requirements

- Hammerspoon
- Hammerspoon Accessibility permission for event taps

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/CMDLayoutSwitcher.spoon/
```

Or distribute it as `CMDLayoutSwitcher.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("CMDLayoutSwitcher")
spoon.CMDLayoutSwitcher:start({
  leftLayout = "ABC",
  rightLayout = "Russian",
})
```

## Configuration

Configure target layouts in `start()` or as public properties before calling `start()`:

```lua
hs.loadSpoon("CMDLayoutSwitcher")

spoon.CMDLayoutSwitcher.leftLayout = "U.S."
spoon.CMDLayoutSwitcher.rightLayout = "Russian - PC"
spoon.CMDLayoutSwitcher:start()
```

Layout names can vary by macOS version (`ABC` vs `U.S.`, `Russian` vs `Russian - PC`). Check yours with `hs.keycodes.layouts()` in the Hammerspoon Console and pass the exact names.

## Behavior

1. `start()` validates the configured layout names and starts an event tap.
2. A tap counts only when Command is pressed and released with no other key in between.
3. Left Command taps switch to `leftLayout`; Right Command taps switch to `rightLayout`.
4. Command-key combinations are passed through unchanged and do not switch layouts.
5. `stop()` stops the event tap and clears internal tap state.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `CMDLayoutSwitcher:init()` — initialize the Spoon without starting the event tap.
- `CMDLayoutSwitcher:start([config])` — configure layouts and start observing Command-key taps.
- `CMDLayoutSwitcher:stop()` — stop observing Command-key taps.

Public properties:

- `CMDLayoutSwitcher.leftLayout`
- `CMDLayoutSwitcher.rightLayout`

## License

MIT — see <https://opensource.org/licenses/MIT>.
