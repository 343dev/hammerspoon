# NetSpeed.spoon

Hammerspoon Spoon that monitors network interface throughput and displays upload/download speed in the macOS menubar.

The Spoon reads byte counters from macOS `netstat` for a configurable network interface and renders a compact two-line menubar icon: upload speed on top, download speed below.

## Requirements

- Hammerspoon
- macOS with `ifconfig` and `netstat` available (standard on macOS)

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/NetSpeed.spoon/
```

Or distribute it as `NetSpeed.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("NetSpeed")
spoon.NetSpeed:start()
```

## Configuration

Configure public properties before calling `start()`:

```lua
hs.loadSpoon("NetSpeed")

spoon.NetSpeed.interface = "en0"          -- primary interface to monitor
spoon.NetSpeed.fallbackInterface = nil     -- optional fallback, e.g. "utun0"
spoon.NetSpeed.updateInterval = 1          -- seconds between updates

spoon.NetSpeed:start()
```

You can also change the primary interface later:

```lua
spoon.NetSpeed:setInterface("utun0")
```

Common interface names on macOS include:

- `en0` — usually Wi-Fi or the primary network adapter
- `en1` — another physical network adapter on some Macs
- `utun0`, `utun1`, ... — VPN/tunnel interfaces

Run `ifconfig -l` in Terminal or `hs.execute("ifconfig -l")` in Hammerspoon Console to list interfaces on your machine.

## Behavior

1. `start()` creates a menubar item and schedules a repeating timer.
2. The Spoon checks whether `interface` exists; if not, it tries `fallbackInterface` when configured.
3. Each update reads byte counters from `netstat`, computes bytes per second since the previous update, and refreshes the menubar icon.
4. If no configured interface is available, the menubar shows `⚠️` and resets counters.
5. `stop()` stops timers and removes the menubar item.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `NetSpeed:start()` — start periodic network speed monitoring.
- `NetSpeed:stop()` — stop timers and remove the menubar item.
- `NetSpeed:setInterface(interface)` — set the primary network interface and reset counters.

Public properties:

- `NetSpeed.interface`
- `NetSpeed.fallbackInterface`
- `NetSpeed.updateInterval`
- `NetSpeed.logger`

## License

MIT — see <https://opensource.org/licenses/MIT>.
