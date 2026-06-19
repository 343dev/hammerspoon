# Gopass.spoon

Keyboard-driven Hammerspoon UI for [`gopass`](https://www.gopass.pw/): search entries, decrypt via pinentry, then type or copy selected fields.

## Requirements

- `gopass`
- `gpg`
- A working pinentry app, typically `pinentry-mac`
- Hammerspoon Accessibility permission if you use typing/paste behavior

`Gopass.spoon` launches commands through `/usr/bin/env` and extends `PATH` with common package-manager locations (`/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`) so GUI-launched Hammerspoon can find `gopass` and `gpg`.

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/Gopass.spoon/
```

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("Gopass")
spoon.Gopass:start()
```

By default, `start()` binds `Ctrl+Alt+Cmd+P` to `spoon.Gopass:show()`.

### Configure at start

Pass a configuration table to `start()`. At minimum, `defaultHotkeys` is supported; `hotkeys` is also accepted as a shorter alias.

```lua
hs.loadSpoon("Gopass")
spoon.Gopass:start({
  defaultHotkeys = {
    show = {{"cmd", "alt"}, "p", message = "Gopass"},
  },
})
```

### Common configuration

```lua
hs.loadSpoon("Gopass")

spoon.Gopass:start({
  hotkeys = {
    show = {{"cmd", "alt"}, "p", message = "Gopass"},
  },
  pasteIntoField = true,          -- type selected fields instead of copying
  clipboardAutoClearSeconds = 30, -- default; only used when pasteIntoField = false
  openConsoleOnError = true,
  extraEnv = {
    -- GOPASS_HOMEDIR = "/Users/you/.local/share/gopass",
  },
})
```

You can still configure public properties directly before calling `start()`, or call `bindHotkeys()` explicitly if you prefer the classic Spoon style.

## Behavior

1. `show()` lists entries via `gopass ls -f`.
2. Selecting an entry runs `gopass show <entry>`.
3. The first line is treated as `password`; subsequent `key: value` lines become selectable fields.
4. Selecting a non-URL field either types it into the previously focused window (`pasteIntoField = true`) or copies it to the clipboard.
5. Selecting `url` or `*.url` opens the normalized HTTP(S) URL.
6. Pressing the hotkey shortly after viewing an entry reopens that entry directly (`reopenCardSeconds`).

Fields named in an `unsafe-keys` value are masked in the chooser preview, as is the password field.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `Gopass:init()` — prepare the Spoon; called automatically by `hs.loadSpoon()`.
- `Gopass:start([config])` — apply optional config, prepare chooser UI, bind default hotkeys if needed, and optionally run health checks.
- `Gopass:stop()` — stop tasks, timers, watchers, and chooser UI.
- `Gopass:show()` — show the entry chooser or reopen the last viewed entry.
- `Gopass:bindHotkeys(mapping)` — bind the `show` action.
