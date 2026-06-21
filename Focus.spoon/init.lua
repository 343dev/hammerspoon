--- === Focus ===
---
--- Timer with customizable focus and break intervals.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("Focus")
--- spoon.Focus:start({
---   focusTime = 55,
---   breakTime = 5,
---   postponeTime = 5,
---   playSound = true,
---   showTimer = true,
---   hotkeys = {
---     toggleFlow = {{"cmd", "alt", "ctrl"}, "f"},
---     takeBreak = {{"cmd", "alt", "ctrl"}, "b"},
---   },
--- })
--- ```
---
--- Download: https://github.com/343dev/hammerspoon

local caffeinate = require("hs.caffeinate")
local canvas = require("hs.canvas")
local eventtap = require("hs.eventtap")
local fnutils = require("hs.fnutils")
local logger = require("hs.logger")
local menubar = require("hs.menubar")
local screen = require("hs.screen")
local sound = require("hs.sound")
local spoons = require("hs.spoons")
local timer = require("hs.timer")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Focus"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/hammerspoon"

-- Default settings
obj.focusTime = 55 * 60
obj.breakTime = 5 * 60
obj.overlayColor = { red = 0, green = 0, blue = 0, alpha = 0.85 }
obj.showTimer = true
obj.playSound = true
obj.showMenuBar = true
obj.postponeTime = 5 * 60

-- Internal variables
obj.overlay = nil
obj.timerDisplay = nil
obj.currentPhase = "focus"
obj.timeLeft = 0
obj.displayTimer = nil
obj.wakeTimer = nil
obj.eventTap = nil
obj.menuBar = nil
obj.flowMode = false
obj.caffeineWatcher = nil
obj.screenWatcher = nil
obj.wasActiveBeforeSleep = false
obj.wasInFlowBeforeBreak = false
obj.currentBreakTip = ""
obj.caffeineActive = false

-- Break tips array
obj.breakTips = {
	"Look at a point 20 feet away 👀",
	"Stand up and stretch 🤸",
	"Drink a glass of water 🥛",
	"Take 5 deep breaths 🧘",
	"Do some light exercises 💪",
	"Rest your eyes and blink slowly 👁️",
	"Walk around for a minute 🚶",
	"Roll your shoulders and neck 🔄",
	"Look out the window 🪟",
	"Do some quick stretches 🤸‍♂️",
	"Hydrate yourself 💧",
	"Give your mind a break 🧠",
}

-- Logger for debugging
local log = logger.new("Focus")

local function isPositiveNumber(value)
	return type(value) == "number" and value > 0
end

--- Focus:init()
--- Method
--- Initializes the Focus Spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Focus object
function obj:init()
	log.d("Initializing Focus")
	return self
end

-- Setup system state watchers
function obj:setupSystemWatchers()
	if self.caffeineWatcher or self.screenWatcher then
		return self
	end

	local sleepEvents = {
		[caffeinate.watcher.systemWillSleep] = true,
		[caffeinate.watcher.systemWillPowerOff] = true,
		[caffeinate.watcher.sessionDidResignActive] = true,
	}

	self.caffeineWatcher = caffeinate.watcher.new(function(eventType)
		if sleepEvents[eventType] then
			log.d("System sleep/power off - saving state")
			self:handleSystemSleep()
		elseif eventType == caffeinate.watcher.systemDidWake then
			log.d("System did wake - restoring state")
			self:handleSystemWake()
		end
	end)

	self.screenWatcher = caffeinate.watcher.new(function(eventType)
		if eventType == caffeinate.watcher.screensDidLock then
			log.d("Screen locked - saving state")
			self:handleSystemSleep()
		elseif eventType == caffeinate.watcher.screensDidUnlock then
			log.d("Screen unlocked - restoring state")
			self:handleSystemWake()
		end
	end)

	self.caffeineWatcher:start()
	self.screenWatcher:start()
	log.d("System watchers started")
	return self
end

-- Enable caffeinate to prevent sleep and screensaver
function obj:enableCaffeinate()
	if not self.caffeineActive then
		caffeinate.set("system", true)
		caffeinate.set("displayIdle", true)
		self.caffeineActive = true
		log.d("Caffeinate enabled")
	end
end

-- Disable caffeinate
function obj:disableCaffeinate()
	if self.caffeineActive then
		caffeinate.set("system", false)
		caffeinate.set("displayIdle", false)
		self.caffeineActive = false
		log.d("Caffeinate disabled")
	end
end

-- Handle system sleep/lock events
function obj:handleSystemSleep()
	local wasInFlow = self.wasInFlowBeforeBreak or self.flowMode
	self.wasInFlowBeforeBreak = wasInFlow
	self.wasActiveBeforeSleep = not wasInFlow
	self:stopTimer()
end

-- Handle system wake/unlock events
function obj:handleSystemWake()
	if self.wakeTimer then
		self.wakeTimer:stop()
	end

	self.wakeTimer = timer.doAfter(1, function()
		if self.wasInFlowBeforeBreak then
			log.d("Restoring flow mode")
			self.flowMode = true
			self.wasInFlowBeforeBreak = false
			self:updateMenuBar()
		elseif self.wasActiveBeforeSleep and not self.flowMode then
			log.d("Restoring timer")
			self:startTimer()
		end
		self.wakeTimer = nil
	end)
end

-- Create menu bar element
function obj:createMenuBar()
	if self.menuBar then
		self.menuBar:delete()
	end

	self.menuBar = menubar.new()
	self.menuBar:setTooltip("Focus")
	self:updateMenuBar()
	log.d("MenuBar created")
end

-- Update menu bar
function obj:updateMenuBar()
	if not self.menuBar then
		return
	end

	local iconName = self.flowMode and "Focus-inactive.pdf" or "Focus-active.pdf"
	local iconPath = hs.spoons.resourcePath(iconName)

	self.menuBar:setIcon(iconPath, true)
	self.menuBar:setTitle(nil)

	self.menuBar:setMenu({
		{ title = "Flow",         checked = self.flowMode,             fn = function() self:toggleFlow() end },
		{ title = "Take a Break", fn = function() self:takeBreak() end },
	})

	return self
end

--- Focus:toggleFlow()
--- Method
--- Toggles flow mode. In flow mode, the focus timer is paused until flow mode is disabled.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Focus object
function obj:toggleFlow()
	self.flowMode = not self.flowMode

	if self.flowMode then
		log.d("Flow mode enabled")
		self:stopTimer()
	else
		log.d("Flow mode disabled")
		self:startTimer()
	end

	self:updateMenuBar()
	return self
end

--- Focus:takeBreak()
--- Method
--- Starts a break immediately.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Focus object
function obj:takeBreak()
	log.d("Take a break requested")

	if self.flowMode then
		self.wasInFlowBeforeBreak = true
		self.flowMode = false
		log.d("Manual break from flow mode")
	else
		self.wasInFlowBeforeBreak = false
	end

	self:updateMenuBar()

	if self.displayTimer then
		self.displayTimer:stop()
		self.displayTimer = nil
	end

	self:startBreakTimer()
	return self
end

-- Get random break tip
function obj:getRandomBreakTip()
	return self.breakTips[math.random(1, #self.breakTips)]
end

-- Calculate timer position
function obj:getTimerPosition(phase)
	local frame = screen.mainScreen():frame()
	local timerWidth = phase == "focus" and 220 or 120
	local timerHeight = 35

	return {
		x = frame.x + (frame.w - timerWidth) / 2,
		y = frame.y + frame.h * 2 / 3 + (frame.h / 3 - timerHeight) / 2,
		w = timerWidth,
		h = timerHeight,
	}
end

-- Timer display element templates
local function getFocusTimerElements(text)
	return {
		{
			type = "rectangle",
			action = "fill",
			fillColor = { red = 0.1, green = 0.1, blue = 0.1, alpha = 0.8 },
			roundedRectRadii = { xRadius = 18, yRadius = 18 },
			frame = { x = 0, y = 0, w = 220, h = 35 },
		},
		{
			type = "text",
			text = text,
			textColor = { red = 1, green = 1, blue = 1, alpha = 1 },
			textSize = 28,
			textFont = "SF Mono",
			textAlignment = "center",
			frame = { x = 0, y = 0, w = 120, h = 35 },
		},
		{
			id = "postponeButtonBg",
			type = "rectangle",
			action = "fill",
			fillColor = { red = 1, green = 1, blue = 1, alpha = 0.95 },
			roundedRectRadii = { xRadius = 14, yRadius = 14 },
			trackMouseDown = true,
			frame = { x = 125, y = 4, w = 90, h = 27 },
		},
		{
			id = "postponeButtonLabel",
			type = "text",
			text = "+5 min",
			textColor = { red = 0.1, green = 0.1, blue = 0.1, alpha = 0.8 },
			textSize = 16,
			textFont = ".AppleSystemUIFont",
			textAlignment = "center",
			trackMouseDown = true,
			frame = { x = 125, y = 8, w = 90, h = 21 },
		},
	}
end

local function getBreakTimerElements(text)
	return {
		{
			type = "text",
			text = text,
			textColor = { red = 1, green = 1, blue = 1, alpha = 1 },
			textSize = 28,
			textFont = "SF Mono",
			textAlignment = "center",
			frame = { x = 0, y = 0, w = 120, h = 35 },
		},
	}
end

-- Cleanup resources
function obj:cleanup()
	if self.displayTimer then
		self.displayTimer:stop()
		self.displayTimer = nil
	end

	if self.wakeTimer then
		self.wakeTimer:stop()
		self.wakeTimer = nil
	end

	if self.eventTap then
		self.eventTap:stop()
		self.eventTap = nil
	end

	if self.overlay then
		self.overlay:hide()
		self.overlay = nil
	end

	if self.timerDisplay then
		self.timerDisplay:hide()
		self.timerDisplay = nil
	end

	self:disableCaffeinate()
end

-- Emergency exit combination
local emergencyExitKeyCode = 14

-- Check if key combination is emergency exit
function obj:isEmergencyExit(event)
	if event:getType() == eventtap.event.types.keyDown then
		local flags = event:getFlags()
		local keyCode = event:getKeyCode()

		if flags.cmd and flags.alt and flags.shift and keyCode == emergencyExitKeyCode then
			if self.currentPhase == "break" then
				log.d("Emergency exit")
				self:cleanup()
				self:restoreAfterBreak()
			end
			return true
		end
	end
	return false
end

-- Blocked system hotkeys
local blockedHotkeys = {
	{ cmd = true,  key = 48 }, -- Cmd+Tab
	{ cmd = true,  key = 49 }, -- Cmd+Space
	{ cmd = true,  key = 4 },  -- Cmd+H (Hide)
	{ cmd = true,  key = 46 }, -- Cmd+W (Close)
	{ cmd = true,  key = 13 }, -- Cmd+P (Print)
	{ key = 99 },              -- F5
	{ key = 118 },             -- F7
	{ key = 103 },             -- F8
	{ key = 111 },             -- F9
	{ ctrl = true, key = 126 }, -- Ctrl+Up (Mission Control)
	{ ctrl = true, key = 125 }, -- Ctrl+Down (App Exposé)
	{ ctrl = true, key = 123 }, -- Ctrl+Left (Spaces)
	{ ctrl = true, key = 124 }, -- Ctrl+Right (Spaces)
	{ cmd = true,  key = 50 }, -- Cmd+` (Cycle windows)
}

-- Check if event is blocked
function obj:isBlockedSystemEvent(event)
	local eventType = event:getType()

	if eventType == eventtap.event.types.keyDown then
		local flags = event:getFlags()
		local keyCode = event:getKeyCode()

		if flags.cmd and keyCode == 12 and not (flags.alt and flags.shift) then
			return true
		end

		for _, hotkey in ipairs(blockedHotkeys) do
			if (not hotkey.cmd or flags.cmd)
					and (not hotkey.ctrl or flags.ctrl)
					and hotkey.key == keyCode then
				return true
			end
		end
	end

	return false
end

-- Create overlay
function obj:createOverlay()
	if self.overlay then
		self.overlay:delete()
	end

	local frame = screen.mainScreen():fullFrame()

	self.overlay = canvas.new(frame)
	self.overlay:level(canvas.windowLevels.screenSaver)
	self.overlay:clickActivating(false)

	local overlayElements = {
		{
			type = "rectangle",
			action = "fill",
			fillColor = self.overlayColor,
			frame = { x = 0, y = 0, w = frame.w, h = frame.h },
		},
	}

	if self.showTimer then
		table.insert(overlayElements, {
			type = "text",
			text = self.currentBreakTip,
			textColor = { red = 1, green = 1, blue = 1, alpha = 1 },
			textSize = 48,
			textAlignment = "center",
			frame = { x = 0, y = frame.h / 2 - 50, w = frame.w, h = 100 },
		})
	end

	self.overlay:appendElements(overlayElements)

	local eventTypes = {
		eventtap.event.types.leftMouseDown,
		eventtap.event.types.rightMouseDown,
		eventtap.event.types.middleMouseDown,
		eventtap.event.types.leftMouseUp,
		eventtap.event.types.rightMouseUp,
		eventtap.event.types.middleMouseUp,
		eventtap.event.types.mouseMoved,
		eventtap.event.types.leftMouseDragged,
		eventtap.event.types.rightMouseDragged,
		eventtap.event.types.middleMouseDragged,
		eventtap.event.types.scrollWheel,
		eventtap.event.types.keyDown,
		eventtap.event.types.keyUp,
		eventtap.event.types.flagsChanged,
		eventtap.event.types.gesture,
		eventtap.event.types.magnify,
		eventtap.event.types.rotate,
		eventtap.event.types.swipe,
		eventtap.event.types.tabletPointer,
		eventtap.event.types.tabletProximity,
		eventtap.event.types.otherMouseDown,
		eventtap.event.types.otherMouseUp,
		eventtap.event.types.otherMouseDragged,
	}

	local gestureTypes = {
		[eventtap.event.types.gesture] = true,
		[eventtap.event.types.magnify] = true,
		[eventtap.event.types.rotate] = true,
		[eventtap.event.types.swipe] = true,
	}

	self.eventTap = eventtap.new(eventTypes, function(event)
		if self:isEmergencyExit(event) then
			return false
		end

		if self:isBlockedSystemEvent(event) then
			log.d("Blocked system event: " .. event:getType())
			return true
		end

		if gestureTypes[event:getType()] then
			log.d("Blocked gesture: " .. event:getType())
			return true
		end

		return true
	end)

	log.d("Overlay created")
end

-- Create timer display
function obj:createTimerDisplay(phase)
	if self.timerDisplay then
		self.timerDisplay:delete()
	end

	local displayFrame = self:getTimerPosition(phase)
	self.timerDisplay = canvas.new(displayFrame)

	if phase == "focus" then
		self.timerDisplay:level(canvas.windowLevels.floating)
		self.timerDisplay:appendElements(table.unpack(getFocusTimerElements(self:formatTime(self.timeLeft))))
		self.timerDisplay:mouseCallback(function(_, message, elementID)
			if message == "mouseDown"
					and (elementID == "postponeButtonBg" or elementID == "postponeButtonLabel") then
				self:postponeBreak()
			end
		end)
	else
		self.timerDisplay:level(canvas.windowLevels.screenSaver + 1)
		self.timerDisplay:appendElements(table.unpack(getBreakTimerElements(self:formatTime(self.timeLeft))))
	end

	self.timerDisplay:show()
end

-- Update timer display
function obj:updateTimerDisplay()
	if not self.timerDisplay then
		return
	end

	if self.currentPhase == "focus" then
		self.timerDisplay:replaceElements(table.unpack(getFocusTimerElements(self:formatTime(self.timeLeft))))
	else
		self.timerDisplay:replaceElements(table.unpack(getBreakTimerElements(self:formatTime(self.timeLeft))))
	end
end

-- Update overlay
function obj:updateOverlay()
	if not self.overlay then
		return
	end

	local frame = screen.mainScreen():fullFrame()
	local elements = {
		{
			type = "rectangle",
			action = "fill",
			fillColor = self.overlayColor,
			frame = { x = 0, y = 0, w = frame.w, h = frame.h },
		},
	}

	if self.showTimer then
		table.insert(elements, {
			type = "text",
			text = self.currentBreakTip,
			textColor = { red = 1, green = 1, blue = 1, alpha = 1 },
			textSize = 48,
			textAlignment = "center",
			frame = { x = 0, y = frame.h / 2 - 50, w = frame.w, h = 100 },
		})
	end

	self.overlay:replaceElements(table.unpack(elements))
end

-- Format time as mm:ss
function obj:formatTime(seconds)
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Postpone break start
function obj:postponeBreak()
	if self.currentPhase ~= "focus" then
		return
	end

	self.timeLeft = self.timeLeft + self.postponeTime
	log.d("Postponed break by " .. math.floor(self.postponeTime / 60) .. " minutes")

	if self.timerDisplay and self.timeLeft > 10 then
		self.timerDisplay:hide()
		self.timerDisplay = nil
	end
end

-- Play notification sound
function obj:playNotificationSound()
	if self.playSound then
		local notificationSound = sound.getByName("Glass")
		if notificationSound then
			notificationSound:play()
		else
			log.w("Notification sound not found: Glass")
		end
	end
end

-- Start focus timer
function obj:startFocusTimer()
	if self.flowMode then
		return
	end

	log.d("Starting focus timer")
	self.currentPhase = "focus"
	self.timeLeft = self.focusTime
	self:updateMenuBar()

	self.displayTimer = timer.doEvery(1, function()
		self.timeLeft = self.timeLeft - 1

		if self.showTimer and self.timeLeft <= 10 then
			if not self.timerDisplay then
				self:createTimerDisplay("focus")
			else
				self:updateTimerDisplay()
			end
		elseif self.timerDisplay and self.timeLeft > 10 then
			self.timerDisplay:hide()
			self.timerDisplay = nil
		end

		if self.timeLeft <= 0 then
			self.displayTimer:stop()
			self:startBreakTimer()
		end
	end)
end

-- Start break timer
function obj:startBreakTimer()
	log.d("Starting break timer")
	self.currentPhase = "break"
	self.timeLeft = self.breakTime
	self.currentBreakTip = self:getRandomBreakTip()
	self:updateMenuBar()

	if self.timerDisplay then
		self.timerDisplay:hide()
		self.timerDisplay = nil
	end

	self:enableCaffeinate()
	self:createOverlay()
	self.overlay:show()

	if self.showTimer then
		self:createTimerDisplay("break")
	end

	if self.eventTap then
		self.eventTap:start()
	end

	self:playNotificationSound()

	self.displayTimer = timer.doEvery(1, function()
		self.timeLeft = self.timeLeft - 1
		self:updateOverlay()

		if self.showTimer then
			self:updateTimerDisplay()
		end

		if self.timeLeft <= 0 then
			self.displayTimer:stop()
			self:endBreakTimer()
		end
	end)
end

-- End break timer
function obj:endBreakTimer()
	log.d("Ending break timer")
	self:cleanup()
	self:playNotificationSound()

	if self.wasInFlowBeforeBreak then
		log.d("Restoring flow mode")
		self.flowMode = true
		self.wasInFlowBeforeBreak = false
	elseif not self.flowMode then
		self:startFocusTimer()
	end

	self:updateMenuBar()
end

-- Restore after break
function obj:restoreAfterBreak()
	if self.wasInFlowBeforeBreak then
		log.d("Restoring flow mode")
		self.flowMode = true
		self.wasInFlowBeforeBreak = false
	elseif not self.flowMode then
		self:startFocusTimer()
	end
	self:updateMenuBar()
end

--- Focus:start([config])
--- Method
--- Configures and starts Focus, including background watchers, the menu bar item, and the focus timer.
---
--- Parameters:
---  * config - An optional table containing startup configuration:
---    * focusTime - Focus interval length in minutes
---    * breakTime - Break interval length in minutes
---    * postponeTime - Postpone duration in minutes
---    * playSound - A boolean, true to play sounds, false to disable sounds
---    * showTimer - A boolean, true to show the countdown timer, false to hide it
---    * hotkeys - A table passed to Focus:bindHotkeys()
---
--- Returns:
---  * The Focus object
function obj:start(config)
	self:configure(config)

	if self.showMenuBar and not self.menuBar then
		self:createMenuBar()
	end

	self:setupSystemWatchers()
	return self:startTimer()
end

-- Internal start timer
function obj:startTimer()
	if self.flowMode then
		log.d("Cannot start timer - in flow mode")
		return self
	end

	log.d("Starting Focus")
	self:stopTimer()
	self:startFocusTimer()

	return self
end

--- Focus:stop()
--- Method
--- Stops Focus and removes all timers, watchers, event taps, overlays, and menu bar items.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Focus object
function obj:stop()
	return self:cleanupFull()
end

-- Internal stop timer
function obj:stopTimer()
	log.d("Stopping Focus")
	self:cleanup()
	self:updateMenuBar()
	return self
end

-- Cleanup function
function obj:cleanupFull()
	log.d("Cleaning up Focus")
	self:cleanup()

	if self.caffeineWatcher then
		self.caffeineWatcher:stop()
		self.caffeineWatcher = nil
	end

	if self.screenWatcher then
		self.screenWatcher:stop()
		self.screenWatcher = nil
	end

	if self.menuBar then
		self.menuBar:delete()
		self.menuBar = nil
	end

	return self
end

--- Focus:configure([config])
--- Method
--- Applies Focus configuration without starting the timer.
---
--- Parameters:
---  * config - An optional table containing configuration values:
---    * focusTime - Focus interval length in minutes
---    * breakTime - Break interval length in minutes
---    * postponeTime - Postpone duration in minutes
---    * playSound - A boolean, true to play sounds, false to disable sounds
---    * showTimer - A boolean, true to show the countdown timer, false to hide it
---    * hotkeys - A table passed to Focus:bindHotkeys()
---
--- Returns:
---  * The Focus object
function obj:configure(config)
	if not config then
		return self
	end

	if config.focusTime ~= nil then
		self:setFocusTime(config.focusTime)
	end

	if config.breakTime ~= nil then
		self:setBreakTime(config.breakTime)
	end

	if config.postponeTime ~= nil then
		self:setPostponeTime(config.postponeTime)
	end

	if config.playSound ~= nil then
		self:setPlaySound(config.playSound)
	end

	if config.showTimer ~= nil then
		self:setShowTimer(config.showTimer)
	end

	if config.hotkeys ~= nil then
		self:bindHotkeys(config.hotkeys)
	end

	return self
end

--- Focus:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for Focus actions.
---
--- Parameters:
---  * mapping - A table containing hotkey definitions for actions. Supported actions are:
---    * toggleFlow - Toggle flow mode
---    * takeBreak - Start a break immediately
---    * start - Start Focus
---    * stop - Stop Focus
---
--- Returns:
---  * The Focus object
function obj:bindHotkeys(mapping)
	local spec = {
		toggleFlow = fnutils.partial(self.toggleFlow, self),
		takeBreak = fnutils.partial(self.takeBreak, self),
		start = fnutils.partial(self.start, self),
		stop = fnutils.partial(self.stop, self),
	}

	spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

--- Focus:getStatus()
--- Method
--- Gets the current Focus state.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table containing the current phase, remaining time, configured durations, flow mode state, and related runtime flags
function obj:getStatus()
	return {
		phase = self.currentPhase,
		timeLeft = self.timeLeft,
		focusTime = self.focusTime,
		breakTime = self.breakTime,
		flowMode = self.flowMode,
		wasActiveBeforeSleep = self.wasActiveBeforeSleep,
		wasInFlowBeforeBreak = self.wasInFlowBeforeBreak,
		currentBreakTip = self.currentBreakTip,
		caffeineActive = self.caffeineActive,
		postponeTime = self.postponeTime,
		playSound = self.playSound,
		showTimer = self.showTimer,
	}
end

--- Focus:setFocusTime(minutes)
--- Method
--- Sets the focus interval length.
---
--- Parameters:
---  * minutes - A positive number containing the focus interval length in minutes
---
--- Returns:
---  * The Focus object
function obj:setFocusTime(minutes)
	if not isPositiveNumber(minutes) then
		log.w("Invalid focus time: " .. tostring(minutes))
		return self
	end

	log.d("Setting focus time to " .. minutes .. " minutes")
	self.focusTime = minutes * 60

	if not self.flowMode and self.displayTimer then
		local currentPhase = self.currentPhase
		self:stopTimer()
		if currentPhase == "focus" then
			self:startFocusTimer()
		elseif currentPhase == "break" then
			self:startBreakTimer()
		end
	end

	return self
end

--- Focus:setBreakTime(minutes)
--- Method
--- Sets the break interval length.
---
--- Parameters:
---  * minutes - A positive number containing the break interval length in minutes
---
--- Returns:
---  * The Focus object
function obj:setBreakTime(minutes)
	if not isPositiveNumber(minutes) then
		log.w("Invalid break time: " .. tostring(minutes))
		return self
	end

	log.d("Setting break time to " .. minutes .. " minutes")
	self.breakTime = minutes * 60

	if not self.flowMode and self.displayTimer then
		local currentPhase = self.currentPhase
		self:stopTimer()
		if currentPhase == "focus" then
			self:startFocusTimer()
		elseif currentPhase == "break" then
			self:startBreakTimer()
		end
	end

	return self
end

--- Focus:setPostponeTime(minutes)
--- Method
--- Sets the postpone duration.
---
--- Parameters:
---  * minutes - A positive number containing the postpone duration in minutes
---
--- Returns:
---  * The Focus object
function obj:setPostponeTime(minutes)
	if not isPositiveNumber(minutes) then
		log.w("Invalid postpone time: " .. tostring(minutes))
		return self
	end

	log.d("Setting postpone time to " .. minutes .. " minutes")
	self.postponeTime = minutes * 60
	return self
end

--- Focus:setOverlayColor(color)
--- Method
--- Sets the break overlay color.
---
--- Parameters:
---  * color - A color table suitable for hs.canvas fillColor
---
--- Returns:
---  * The Focus object
function obj:setOverlayColor(color)
	self.overlayColor = color
	return self
end

--- Focus:setShowTimer(show)
--- Method
--- Enables or disables the on-screen countdown timer.
---
--- Parameters:
---  * show - A boolean, true to show the countdown timer, false to hide it
---
--- Returns:
---  * The Focus object
function obj:setShowTimer(show)
	self.showTimer = show
	return self
end

--- Focus:setPlaySound(play)
--- Method
--- Enables or disables notification sounds.
---
--- Parameters:
---  * play - A boolean, true to play sounds, false to disable sounds
---
--- Returns:
---  * The Focus object
function obj:setPlaySound(play)
	self.playSound = play
	return self
end

--- Focus:setShowMenuBar(show)
--- Method
--- Enables or disables the menu bar item.
---
--- Parameters:
---  * show - A boolean, true to show the menu bar item, false to remove it
---
--- Returns:
---  * The Focus object
function obj:setShowMenuBar(show)
	self.showMenuBar = show

	if show then
		self:createMenuBar()
	elseif self.menuBar then
		self.menuBar:delete()
		self.menuBar = nil
	end

	return self
end

return obj
