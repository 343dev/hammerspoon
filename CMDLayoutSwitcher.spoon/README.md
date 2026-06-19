# CMDLayoutSwitcher.spoon

Select the macOS keyboard layout by **tapping a Command key on its own**.

| Tap (press & release, no other key) | Layout        |
| ----------------------------------- | ------------- |
| **Left  ⌘**                          | `leftLayout`  |
| **Right ⌘**                          | `rightLayout` |

**Command combinations are ignored.** CMD+A, CMD+C, CMD+Tab, CMD+Shift+3, … do
**not** switch the layout — only a lone Command tap does. The switch happens on
key *release*, purely via events (no timers), and every event is passed through
unchanged, so all normal Command shortcuts keep working.

## Install

Copy (or symlink) this folder to:

```
~/.hammerspoon/Spoons/CMDLayoutSwitcher.spoon/
```

## Use

In your `init.lua`:

```lua
hs.loadSpoon("CMDLayoutSwitcher")

spoon.CMDLayoutSwitcher:start({
  leftLayout = "ABC",
  rightLayout = "Russian",
})
```

### Layout names

Layout names can vary by macOS version ("ABC" vs "U.S.", "Russian" vs
"Russian - PC"). Check yours with `hs.keycodes.layouts()` in the Hammerspoon
console, then pass the exact names to `:start()`:

```lua
spoon.CMDLayoutSwitcher:start({
  leftLayout = "U.S.",
  rightLayout = "Russian - PC",
})
```

You can also configure layouts as properties before starting:

```lua
spoon.CMDLayoutSwitcher.leftLayout = "U.S."
spoon.CMDLayoutSwitcher.rightLayout = "Russian - PC"
spoon.CMDLayoutSwitcher:start()
```

Toggle at runtime: `spoon.CMDLayoutSwitcher:stop()` / `spoon.CMDLayoutSwitcher:start()`.

> Hammerspoon needs **Accessibility** permission for event taps — grant it if
> prompted.
