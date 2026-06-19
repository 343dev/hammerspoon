# InternetWatcher.spoon

Hammerspoon Spoon that monitors internet connectivity, shows an offline warning in the menubar, and plays status sounds when connectivity changes.

## Requirements

- Hammerspoon
- macOS 12 Monterey or later if you want Focus mode detection to suppress notifications and sounds

The Spoon checks multiple HTTP connectivity endpoints in parallel. The first HTTP `200` or `204` response is treated as success. After several consecutive failed checks, the Spoon shows `⚠️ No internet` in the menubar until connectivity is restored.

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/InternetWatcher.spoon/
```

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("InternetWatcher")
spoon.InternetWatcher:start()
```

## Configuration

Configure public properties before calling `start()`:

```lua
hs.loadSpoon("InternetWatcher")

spoon.InternetWatcher.checkInterval = 10    -- seconds between checks
spoon.InternetWatcher.timeout = 1           -- seconds before a check times out
spoon.InternetWatcher.failureThreshold = 3  -- failed checks before offline state
spoon.InternetWatcher.suppressSoundsInFocus = true
spoon.InternetWatcher.checkUrls = {
  "http://cp.cloudflare.com/generate_204",
  "http://connect.rom.miui.com/generate_204",
  "http://google.com/generate_204",
}

spoon.InternetWatcher:start()
```

## Behavior

1. `start()` creates a hidden menubar item and runs an immediate connectivity check.
2. Checks repeat every `checkInterval` seconds.
3. Each check requests all `checkUrls` in parallel.
4. A `200` or `204` response marks the connection as online.
5. If `failureThreshold` consecutive checks fail or time out, the Spoon marks the connection offline, shows the menubar warning, sends a notification, and plays `offline.wav`.
6. When connectivity returns, the Spoon hides the menubar warning, sends a notification, and plays `online.wav`.

Notifications are always sent through `hs.notify`; macOS decides how to handle them during Focus. The Spoon suppresses its extra status sounds during Focus by default. It also logs status transitions and can show its state via `showStatus()`.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `InternetWatcher:start()` — start periodic internet connectivity monitoring.
- `InternetWatcher:stop()` — stop timers and remove the menubar item.
- `InternetWatcher:check()` — run one connectivity check immediately.
- `InternetWatcher:showStatus()` — print current state to Hammerspoon Console and write it to the Hammerspoon log.

To verify that the Spoon is running while Focus affects notifications or sounds:

```lua
spoon.InternetWatcher:showStatus()
```

For temporary debugging, you can disable Focus sound suppression:

```lua
spoon.InternetWatcher.suppressSoundsInFocus = false
```

Public properties:

- `InternetWatcher.checkUrls`
- `InternetWatcher.timeout`
- `InternetWatcher.checkInterval`
- `InternetWatcher.failureThreshold`
- `InternetWatcher.suppressSoundsInFocus`

## License

MIT — see <https://opensource.org/licenses/MIT>.
