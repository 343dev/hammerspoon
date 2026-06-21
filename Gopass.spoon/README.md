# Gopass.spoon

Hammerspoon Spoon that provides a keyboard-driven UI for [`gopass`](https://www.gopass.pw/): search password-store entries, decrypt via pinentry, then type or copy selected fields.

The Spoon launches commands through `/usr/bin/env` and extends `PATH` with common package-manager locations so GUI-launched Hammerspoon can find `gopass` and `gpg`.

## Requirements

- Hammerspoon
- `gopass`
- `gpg`
- A working pinentry app, typically `pinentry-mac`
- Hammerspoon Accessibility permission if you use typing/paste behavior

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/Gopass.spoon/
```

Or distribute it as `Gopass.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("Gopass")
spoon.Gopass:start()
```

By default, `start()` binds Ctrl+Alt+Cmd+P to `spoon.Gopass:show()`.

## Configuration

Configure public properties before calling `start()` or pass a table to `start()`:

```lua
hs.loadSpoon("Gopass")

spoon.Gopass:start({
  hotkeys = {
    show = {{"cmd", "alt"}, "p", message = "Gopass"},
  },
  pasteIntoField = true,          -- type selected fields instead of copying
  clipboardAutoClearSeconds = 30, -- used when pasteIntoField = false
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
7. Fields named in an `unsafe-keys` value are masked in the chooser preview, as is the password field.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `Gopass:init()` — prepare the Spoon; called automatically by `hs.loadSpoon()`.
- `Gopass:start([config])` — apply optional config, prepare chooser UI, bind default hotkeys if needed, and optionally run health checks.
- `Gopass:stop()` — stop tasks, timers, watchers, and chooser UI.
- `Gopass:show()` — show the entry chooser or reopen the last viewed entry.
- `Gopass:bindHotkeys(mapping)` — bind the `show` action.

Public properties:

- `Gopass.defaultHotkeys`
- `Gopass.gopassBin`
- `Gopass.listArgs`
- `Gopass.showArgsPrefix`
- `Gopass.listTimeoutSeconds`
- `Gopass.showTimeoutSeconds`
- `Gopass.gopassRetryOnTimeout`
- `Gopass.extraPathEntries`
- `Gopass.extraEnv`
- `Gopass.pinentryAppName`
- `Gopass.pinentryFocusAssistSeconds`
- `Gopass.pinentryFocusAssistInterval`
- `Gopass.maxEntryRows`
- `Gopass.cacheEntriesSeconds`
- `Gopass.openConsoleOnError`
- `Gopass.healthCheckOnStart`
- `Gopass.healthCheckTimeoutSeconds`
- `Gopass.clipboardAutoClearSeconds`
- `Gopass.pasteIntoField`
- `Gopass.pasteDelaySeconds`
- `Gopass.reopenCardSeconds`
- `Gopass.logger`

## License

MIT — see <https://opensource.org/licenses/MIT>.
