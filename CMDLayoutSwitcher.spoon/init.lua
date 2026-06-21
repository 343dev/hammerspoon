--- === CMDLayoutSwitcher ===
---
--- Select the keyboard layout based on a lone tap of a Command key.
---
--- Left Command tap  (press & release without any other key) -> leftLayout
--- Right Command tap (press & release without any other key) -> rightLayout
---
--- Command-key combinations such as CMD+A, CMD+C, CMD+Tab, CMD+Shift+3, etc.
--- do not switch the layout — the tap only counts when Command is pressed and
--- released on its own.
---
--- Switching is purely event-driven (no timers / intervals) and every event is
--- observed read-only and passed through unchanged, so all normal Command usage
--- keeps working.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("CMDLayoutSwitcher")
--- spoon.CMDLayoutSwitcher:start({
---   leftLayout = "ABC",
---   rightLayout = "Russian",
--- })
--- ```
---
--- Download: https://github.com/343dev/spoons

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CMDLayoutSwitcher"
obj.version = "1.1"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/spoons"

-- Internal state
obj._tap = nil
obj._armed = nil -- layout to apply if the current Command tap turns out lone

--- CMDLayoutSwitcher.leftLayout
--- Variable
--- The keyboard layout name to switch to when the left Command key is tapped
--- on its own. Set directly or pass as leftLayout to start().
--- See hs.keycodes.layouts().
obj.leftLayout = nil

--- CMDLayoutSwitcher.rightLayout
--- Variable
--- The keyboard layout name to switch to when the right Command key is tapped
--- on its own. Set directly or pass as rightLayout to start().
--- See hs.keycodes.layouts().
obj.rightLayout = nil

-- macOS keycodes for the Command modifier keys (received on flagsChanged events).
local LEFT_COMMAND = 55
local RIGHT_COMMAND = 54

local function isValidLayout(name)
	for _, layout in ipairs(hs.keycodes.layouts()) do
		if layout == name then return true end
	end
	return false
end

local function applyConfig(self, config)
	local leftLayout = self.leftLayout
	local rightLayout = self.rightLayout

	if config ~= nil then
		assert(type(config) == "table", "CMDLayoutSwitcher:start(config) expects a table")
		if config.leftLayout ~= nil then leftLayout = config.leftLayout end
		if config.rightLayout ~= nil then rightLayout = config.rightLayout end
	end

	assert(type(leftLayout) == "string" and leftLayout ~= "",
		"CMDLayoutSwitcher.leftLayout must be a non-empty string")
	assert(isValidLayout(leftLayout),
		string.format("CMDLayoutSwitcher.leftLayout '%s' is not a known layout", leftLayout))
	assert(type(rightLayout) == "string" and rightLayout ~= "",
		"CMDLayoutSwitcher.rightLayout must be a non-empty string")
	assert(isValidLayout(rightLayout),
		string.format("CMDLayoutSwitcher.rightLayout '%s' is not a known layout", rightLayout))

	self.leftLayout = leftLayout
	self.rightLayout = rightLayout
end

--- CMDLayoutSwitcher:init()
--- Method
--- Prepares the Spoon. Called automatically by hs.loadSpoon().
---
--- Does not start any watchers (per Spoon conventions); use start() to begin.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CMDLayoutSwitcher object
function obj:init()
	return self
end

--- CMDLayoutSwitcher:start([config])
--- Method
--- Configures the target layouts, starts observing Command keys, and switches
--- layout on a lone Command tap.
---
--- A tap counts as "lone" only when Command is pressed and released with no other
--- key in between. Command+key combinations (CMD+A, …) are ignored. Safe to call
--- multiple times; only one observer is ever active. If called again while
--- running, a valid config updates the layouts immediately without restarting
--- the observer.
---
--- Parameters:
---  * config - An optional table with leftLayout and/or rightLayout string
---    values. These override CMDLayoutSwitcher.leftLayout and
---    CMDLayoutSwitcher.rightLayout for this and future starts.
---
--- Returns:
---  * The CMDLayoutSwitcher object
function obj:start(config)
	applyConfig(self, config)
	if self._tap then
		-- Already running: applyConfig has just updated the layouts, which take
		-- effect immediately on the next lone Command tap.
		return self
	end

	self._armed = nil

	local types = hs.eventtap.event.types

	self._tap = hs.eventtap.new({ types.flagsChanged, types.keyDown }, function(event)
		local kc = event:getKeyCode()

		if kc == LEFT_COMMAND or kc == RIGHT_COMMAND then
			-- Read press/release straight from the event's modifier flags rather than
			-- toggling a boolean. A reload while Command is held, or a missed
			-- flagsChanged event, can therefore never desync our state.
			--
			-- Note: cmd is the combined left+right Command flag — it is true while
			-- any Command key is held, and becomes false only once the last one is
			-- released. The left/right distinction comes from kc; the (rare) case of
			-- holding both Command keys at once is acceptable to leave ambiguous.
			local cmdDown = event:getFlags().cmd

			if cmdDown then
				-- A Command key went down. Arm only if we are not already tracking a tap.
				if self._armed == nil then
					self._armed = (kc == LEFT_COMMAND) and "left" or "right"
				end
			else
				-- The last held Command key was released. If no ordinary key was typed
				-- in between this was a lone tap -> switch layout. Always clear the arm
				-- so the state can never get stuck.
				if self._armed == "left" then
					hs.keycodes.setLayout(self.leftLayout)
				elseif self._armed == "right" then
					hs.keycodes.setLayout(self.rightLayout)
				end
				self._armed = nil
			end
		else
			-- An ordinary key (or a non-Command modifier) ends any potential lone tap,
			-- so Command+key combinations never trigger a switch.
			self._armed = nil
		end

		-- Never consume events: Command keeps working as a normal modifier.
		return false
	end)

	assert(self._tap,
		"CMDLayoutSwitcher: failed to create eventtap (check Accessibility permissions for Hammerspoon)")

	self._tap:start()
	return self
end

--- CMDLayoutSwitcher:stop()
--- Method
--- Stops observing Command keys.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CMDLayoutSwitcher object
function obj:stop()
	if self._tap then
		self._tap:stop()
		self._tap = nil
	end
	self._armed = nil
	return self
end

return obj
