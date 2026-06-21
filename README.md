# Hammerspoon Spoons

A collection of custom [Hammerspoon](https://www.hammerspoon.org/) Spoon plugins for macOS automation and menubar utilities.

Each tracked Spoon lives in its own `*.spoon` bundle and includes its own `README.md`, `init.lua`, and `docs.json` with more detailed usage and API documentation.

## Included Spoons

- [`CMDLayoutSwitcher.spoon`](CMDLayoutSwitcher.spoon/) — switches the macOS keyboard layout by tapping the left or right Command key on its own.
- [`CryptoPrices.spoon`](CryptoPrices.spoon/) — shows current BTC and ETH prices in USD in the macOS menubar using the public CoinGecko API.
- [`Focus.spoon`](Focus.spoon/) — provides configurable focus/break cycles with a blocking break overlay, optional sounds, menubar controls, and flow mode.
- [`Gopass.spoon`](Gopass.spoon/) — provides a keyboard-driven UI for `gopass`: search password-store entries, decrypt them, then type or copy selected fields.
- [`InternetWatcher.spoon`](InternetWatcher.spoon/) — monitors internet connectivity, shows an offline warning in the menubar, and plays status sounds when connectivity changes.
- [`NetSpeed.spoon`](NetSpeed.spoon/) — displays upload and download throughput for a configurable network interface in the macOS menubar.
- [`Pomodoor.spoon`](Pomodoor.spoon/) — implements a Pomodoro timer with work/break cycles, a menubar countdown, notification sounds, and a daily count.
- [`TimeMachine.spoon`](TimeMachine.spoon/) — shows active Time Machine backup progress and estimated remaining time in the macOS menubar.
- [`URLPicker.spoon`](URLPicker.spoon/) — intercepts `http` and `https` URL events and lets you choose which browser should open each link.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/)
- Accessibility permissions for Spoons that use event taps or type/paste into other applications

Some Spoons have additional requirements:

- `Gopass.spoon`: `gopass`, `gpg`, and a working pinentry app such as `pinentry-mac`
- `CryptoPrices.spoon`: internet access for CoinGecko requests
- `InternetWatcher.spoon`: internet access for connectivity probes; macOS 12+ is recommended for Focus-mode sound suppression
- `TimeMachine.spoon`: macOS Time Machine and `/usr/bin/tmutil`
- `NetSpeed.spoon`: standard macOS networking tools such as `ifconfig` and `netstat`

See each Spoon's own `README.md` for complete requirements and configuration details.

## Installation

Copy or symlink the Spoon bundle you want to use into Hammerspoon's Spoons directory:

```text
~/.hammerspoon/Spoons/<Name>.spoon/
```

For example:

```sh
ln -s /path/to/this/repo/NetSpeed.spoon ~/.hammerspoon/Spoons/NetSpeed.spoon
```

Then load and start it from your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("NetSpeed")
spoon.NetSpeed:start()
```

Repeat this for each Spoon you want to enable.

## Example configuration

```lua
hs.loadSpoon("CMDLayoutSwitcher")
spoon.CMDLayoutSwitcher:start({
  leftLayout = "ABC",
  rightLayout = "Russian",
})

hs.loadSpoon("NetSpeed")
spoon.NetSpeed.interface = "en0"
spoon.NetSpeed:start()

hs.loadSpoon("InternetWatcher")
spoon.InternetWatcher:start()
```

## Documentation

- Open the individual `README.md` inside a Spoon directory for usage examples and configuration options.
- Public APIs are documented in Hammerspoon docstring format in each `init.lua`.
- Generated API metadata is stored in each Spoon's `docs.json`.

## License

MIT — see <https://opensource.org/licenses/MIT>.
