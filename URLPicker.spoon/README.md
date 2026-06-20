# URLPicker.spoon

Hammerspoon Spoon that intercepts `http` and `https` URL events and lets you choose which browser opens each link.

When a web link is opened, URLPicker shows a compact picker near the mouse cursor with installed browser handlers. Select a browser with the mouse, arrow keys and Return, or dismiss the picker with Escape.

## Requirements

- Hammerspoon
- macOS URL handler permissions for Hammerspoon
- One or more installed applications registered as handlers for `http`/`https` URLs

## Install

Copy or symlink this folder to:

```text
~/.hammerspoon/Spoons/URLPicker.spoon/
```

Or distribute it as `URLPicker.spoon.zip`; after unzipping, double-click the `.spoon` bundle to install it with Hammerspoon.

## Use

In your Hammerspoon `init.lua`:

```lua
hs.loadSpoon("URLPicker")
spoon.URLPicker:start()
```

By default, `start()` sets Hammerspoon as the system handler for `http` and `https` links so URLPicker can receive link-open events.

## Configuration

Configure public properties before calling `start()` or pass a table to `start()`:

```lua
hs.loadSpoon("URLPicker")

spoon.URLPicker.pinnedBrowsers = {
  "org.mozilla.firefox",
  "com.google.Chrome",
}

spoon.URLPicker:start({
  autoSetDefaultHandlers = true,
  restoreDefaultHandlersOnStop = false,
  maxCandidates = 24,
})
```

You can also configure without starting:

```lua
spoon.URLPicker:configure({
  pinnedBrowsers = { "org.mozilla.firefox" },
  maxCandidates = 12,
})
```

### Browser bundle IDs

Pinned browsers are configured with macOS bundle IDs. Useful examples include:

- Firefox: `org.mozilla.firefox`
- Google Chrome: `com.google.Chrome`
- Chromium: `org.chromium.Chromium`
- Safari: `com.apple.Safari`
- Microsoft Edge: `com.microsoft.edgemac`
- Brave Browser: `com.brave.Browser`

Only installed apps that are registered handlers for the URL scheme are shown.

## Behavior

1. `start()` installs an `hs.urlevent.httpCallback` and optionally sets Hammerspoon as the default `http`/`https` handler.
2. When a supported URL arrives, the Spoon lists installed URL handlers for that scheme.
3. Pinned browsers are shown first, followed by the remaining handlers alphabetically.
4. Selecting a browser opens the URL with `hs.urlevent.openURLWithBundle()`.
5. `stop()` closes the picker and restores the previous `hs.urlevent.httpCallback`. It restores previous system URL handlers only when `restoreDefaultHandlersOnStop` is true.

## API

Public API is documented in Hammerspoon docstring format in `init.lua` and collected in `docs.json`.

Main methods:

- `URLPicker:start([config])` — start URL interception.
- `URLPicker:stop()` — stop URL interception.
- `URLPicker:configure(config)` — apply configuration without starting.
- `URLPicker:show(url)` — show the picker manually for an `http`/`https` URL.
- `URLPicker:enable()` — set Hammerspoon as default `http`/`https` handler.
- `URLPicker:disable()` — restore previously captured default handlers.
- `URLPicker:cleanup()` — close the picker UI and stop temporary event taps.

Public properties:

- `URLPicker.config`
- `URLPicker.pinnedBrowsers`
- `URLPicker.logger`

## License

MIT — see <https://opensource.org/licenses/MIT>.
