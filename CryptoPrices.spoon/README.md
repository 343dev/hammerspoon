# CryptoPrices.spoon

Hammerspoon Spoon that displays current Bitcoin and Ethereum prices in USD in the menubar.

## Requirements

- Hammerspoon
- Internet access

Prices are fetched from the CoinGecko public API. The Spoon displays a compact two-line menubar icon with BTC and ETH prices, colored by 24-hour price change.

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/CryptoPrices.spoon/
```

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("CryptoPrices")
spoon.CryptoPrices:start()
```

## Configuration

Configure public properties before calling `start()`:

```lua
hs.loadSpoon("CryptoPrices")

spoon.CryptoPrices.updateInterval = 300 -- seconds between price refreshes

spoon.CryptoPrices:start()
```

## Behavior

1. `start()` creates a menubar item and fetches prices immediately.
2. Prices refresh every `updateInterval` seconds.
3. BTC and ETH prices are shown in USD with no decimal places.
4. Green text means the 24-hour change is non-negative; red text means it is negative.
5. On temporary API/network failures, the Spoon keeps showing cached prices when available.
6. After repeated failures, or when no cached prices exist, the menubar displays `?` values.
7. The refresh timer pauses while the system or screens sleep and refreshes again on wake.

Price data comes from CoinGecko and may be delayed or unavailable. This Spoon is for convenience only and is not financial advice.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `CryptoPrices:init()` — initialize the Spoon.
- `CryptoPrices:start()` — start periodic crypto price monitoring.
- `CryptoPrices:stop()` — stop timers/watchers and remove the menubar item.

Public properties:

- `CryptoPrices.updateInterval`

## License

MIT — see <https://opensource.org/licenses/MIT>.
