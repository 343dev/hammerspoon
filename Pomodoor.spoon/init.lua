--- === Pomodoor ===
---
--- Pomodoro timer with work/break cycles.
---
--- Pomodoor shows the remaining work or break time in the menubar, plays bundled
--- sounds when sessions change, and keeps a daily pomodoro count in
--- `hs.settings`.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("Pomodoor")
--- spoon.Pomodoor:start()
--- ```
---
--- Optional hotkeys:
--- ```lua
--- spoon.Pomodoor:bindHotkeys({
---   start = {{"cmd", "alt", "ctrl"}, "9"},
---   pause = {{"cmd", "alt", "ctrl"}, "0"},
--- })
--- ```
---
--- Download: https://github.com/343dev/hammerspoon

local alert = require("hs.alert")
local application = require("hs.application")
local caffeinate = require("hs.caffeinate")
local dialog = require("hs.dialog")
local menubar = require("hs.menubar")
local screen = require("hs.screen")
local settings = require("hs.settings")
local sound = require("hs.sound")
local spoons = require("hs.spoons")
local styledtext = require("hs.styledtext")
local timer = require("hs.timer")
local urlevent = require("hs.urlevent")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Pomodoor"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/hammerspoon"

--- Pomodoor.workingTime
--- Variable
--- Work session duration, in seconds. Default: 1500 (25 minutes).
obj.workingTime = 25 * 60

--- Pomodoor.breakTime
--- Variable
--- Short break duration, in seconds. Default: 300 (5 minutes).
obj.breakTime = 5 * 60

--- Pomodoor.longBreakTime
--- Variable
--- Long break duration, in seconds. Default: 1800 (30 minutes).
obj.longBreakTime = 30 * 60

--- Pomodoor.longBreakEach
--- Variable
--- Number of completed work sessions between long breaks. Default: 6.
obj.longBreakEach = 6

--- Pomodoor.breakSound
--- Variable
--- Bundled sound file played when a break starts.
obj.breakSound = "break.mp3"

--- Pomodoor.workSound
--- Variable
--- Bundled sound file played when work should resume.
obj.workSound = "work.mp3"

--- Pomodoor.showRaycastConfetti
--- Variable
--- Whether to open Raycast confetti when a work session completes. Default: true.
obj.showRaycastConfetti = true

--- Pomodoor.defaultHotkeys
--- Variable
--- Default hotkey mapping. Used only if explicitly passed to bindHotkeys().
obj.defaultHotkeys = {
	start = { { "cmd", "alt", "ctrl" }, "9" },
	pause = { { "cmd", "alt", "ctrl" }, "0" },
}

-- Internal state
obj.currentStatus = "stopped"
obj.pomodoros = 0
obj.timeLeft = 25 * 60
obj.hasDialogOpened = false
obj.menubar = nil
obj.timer = nil
obj.caffeinateWatcher = nil
obj.dialogTimeout = nil
obj.wasActiveBeforeSleep = false
obj.sleepTimestamp = nil

-- Local helpers
local function getSetting(self, label, default)
	return settings.get(self.name .. "." .. label) or default
end

local function setSetting(self, label, value)
	settings.set(self.name .. "." .. label, value)
	return value
end

local function resetDailyPomodoros(self)
	local today = os.date("%Y-%m-%d")
	if getSetting(self, "date", nil) ~= today then
		setSetting(self, "date", today)
		self.pomodoros = setSetting(self, "pomodoros", 0)
	end
end

local function closeDialog(self)
	self.hasDialogOpened = false
	if self.dialogTimeout then
		self.dialogTimeout:stop()
		self.dialogTimeout = nil
	end
end

local function centerBreakDialog(screenFrame, attempts)
	attempts = attempts or 1
	timer.doAfter(0.1, function()
		local app = application.get("Hammerspoon")
		if not app then
			return
		end

		local dialogWindow = nil
		for _, win in ipairs(app:allWindows()) do
			if win:title() == "Pomodoor" then
				dialogWindow = win
				break
			end
		end

		if not dialogWindow then
			if attempts < 5 then
				centerBreakDialog(screenFrame, attempts + 1)
			end
			return
		end

		local frame = dialogWindow:frame()
		dialogWindow:setFrame({
			x = screenFrame.x + ((screenFrame.w - frame.w) / 2),
			y = screenFrame.y + ((screenFrame.h - frame.h) / 2),
			w = frame.w,
			h = frame.h,
		})
	end)
end

local function startCaffeinateWatcher(self)
	if self.caffeinateWatcher then
		return
	end

	self.caffeinateWatcher = caffeinate.watcher.new(function(event)
		if event == caffeinate.watcher.systemWillSleep or event == caffeinate.watcher.screensDidSleep then
			self.wasActiveBeforeSleep = self.timer and self.timer:running()
			self.sleepTimestamp = self.wasActiveBeforeSleep and os.time() or nil
			if self.timer then
				self.timer:stop()
			end
		elseif event == caffeinate.watcher.systemDidWake or event == caffeinate.watcher.screensDidWake then
			if self.wasActiveBeforeSleep then
				if self.sleepTimestamp then
					self.timeLeft = math.max(0, self.timeLeft - (os.time() - self.sleepTimestamp))
				end
				self.sleepTimestamp = nil
				self.wasActiveBeforeSleep = false
				if self.timeLeft > 0 then
					self:startTimer()
				else
					self.timeLeft = 1
					self:startTimer()
				end
			end
		end
	end):start()
end

local function stopCaffeinateWatcher(self)
	if self.caffeinateWatcher then
		self.caffeinateWatcher:stop()
		self.caffeinateWatcher = nil
	end
end

--- Pomodoor:playSound(filepath)
--- Method
--- Play a sound file from Spoon resources.
---
--- Parameters:
---  * filepath - The bundled sound filename to play.
---
--- Returns:
---  * The Pomodoor object
function obj:playSound(filepath)
	local path = spoons.resourcePath(filepath)
	local snd = sound.getByFile(path)
	if snd then
		snd:play()
	end
	return self
end

--- Pomodoor:showAlert(message)
--- Method
--- Show an alert on screen.
---
--- Parameters:
---  * message - The message to display.
---
--- Returns:
---  * The Pomodoor object
function obj:showAlert(message)
	alert.show("🍅 " .. message, 2)
	return self
end

--- Pomodoor:showConfetti()
--- Method
--- Show confetti via Raycast.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:showConfetti()
	if self.showRaycastConfetti then
		urlevent.openURL("raycast://confetti")
	end
	return self
end

--- Pomodoor:updateMenu()
--- Method
--- Update the menubar title and tooltip.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:updateMenu()
	if not self.menubar then
		self.menubar = menubar.new()
	end

	local min = math.floor(self.timeLeft / 60)
	local sec = self.timeLeft % 60
	local icon = self.currentStatus == "breaking" and "❤︎ " or ""
	local text = icon .. string.format("%02d:%02d", min, sec)

	self.menubar:setTitle(styledtext.new(text):setStyle({
		font = styledtext._defaultFonts()["userFixedPitch"],
	}))
	self.menubar:setTooltip("Pomodoros: " .. self.pomodoros .. "\nStatus: " .. self.currentStatus)
	return self
end

--- Pomodoor:startTimer()
--- Method
--- Start the countdown timer.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:startTimer()
	if self.timer then
		self.timer:stop()
	end
	startCaffeinateWatcher(self)
	self.timer = timer.new(1, function() self:timerTick() end):start():fire()
	return self
end

--- Pomodoor:stopTimer()
--- Method
--- Stop the countdown timer.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:stopTimer()
	if self.timer and self.timer:running() then
		self.timer:stop()
	end
	stopCaffeinateWatcher(self)
	return self
end

--- Pomodoor:timerTick()
--- Method
--- Timer callback called every second.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:timerTick()
	if not self.timer or not self.timer:running() then
		return
	end

	self.timeLeft = self.timeLeft - 1
	self:updateMenu()

	if self.timeLeft > 0 then
		return
	end

	if self.currentStatus == "working" then
		self.pomodoros = setSetting(self, "pomodoros", self.pomodoros + 1)
		self.timeLeft = self.pomodoros % self.longBreakEach == 0 and self.longBreakTime or self.breakTime
		self.currentStatus = "breaking"
		self:updateMenu()
		self:playSound(self.breakSound)
		self:showConfetti()
		return
	end

	self.currentStatus = "stopped"
	self:stopTimer()
	self.timeLeft = self.workingTime
	self:updateMenu()
	self:playSound(self.workSound)

	local mainScreen = screen.mainScreen()
	local screenFrame = mainScreen and mainScreen:frame()
	if not screenFrame or not screenFrame.w or not screenFrame.h then
		self.hasDialogOpened = false
		return
	end

	self.hasDialogOpened = true
	self.dialogTimeout = timer.doAfter(300, function()
		closeDialog(self)
	end)
	dialog.alert(screenFrame.x + (screenFrame.w / 2), screenFrame.y + (screenFrame.h / 2), function(result)
		closeDialog(self)
		if result == "Okay" then
			self.currentStatus = "working"
			self:startTimer()
			self:updateMenu()
		end
	end, "Pomodoor", "Break is over, get back to work!", "Okay", "No, thanks")

	hs.focus()
	centerBreakDialog(screenFrame)
end

--- Pomodoor:start()
--- Method
--- Start or resume the timer
---
--- Returns:
---  * The Pomodoor object
function obj:start()
	if self.timer and self.timer:running() then
		return self
	end
	if self.hasDialogOpened then
		return self
	end

	resetDailyPomodoros(self)

	if self.currentStatus ~= "breaking" then
		self.currentStatus = "working"
	end

	self:startTimer()
	self:updateMenu()
	self:showAlert("Started")

	return self
end

--- Pomodoor:pause()
--- Method
--- Pause the active timer without resetting the remaining time. When the current
--- work or break session is already paused, reset it.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:pause()
	if self.currentStatus == "paused" or (self.currentStatus == "breaking" and (not self.timer or not self.timer:running())) then
		return self:stop()
	end

	if not self.timer or not self.timer:running() then
		return self
	end

	self:stopTimer()
	self:showAlert("Paused")
	if self.currentStatus ~= "breaking" then
		self.currentStatus = "paused"
	end

	self:updateMenu()
	return self
end

--- Pomodoor:stop()
--- Method
--- Stop the Spoon, reset the current session, and remove background activity.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:stop()
	self:stopTimer()
	self.timeLeft = self.workingTime
	self.currentStatus = "stopped"
	self.wasActiveBeforeSleep = false
	self.sleepTimestamp = nil

	closeDialog(self)

	if self.menubar then
		self.menubar:delete()
		self.menubar = nil
	end

	return self
end

--- Pomodoor:init()
--- Method
--- Initialize the Spoon. Called automatically by hs.loadSpoon().
---
--- Does not start timers/watchers or bind hotkeys; call start() and
--- bindHotkeys() explicitly.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:init()
	resetDailyPomodoros(self)
	self.pomodoros = getSetting(self, "pomodoros", 0)
	self.timeLeft = self.workingTime

	return self
end

--- Pomodoor:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for Pomodoor actions.
---
--- Supported actions are `start`, `pause`, and `stop`.
---
--- Parameters:
---  * mapping - A table containing hotkey specs, for example:
---    `{ start={{"cmd", "alt", "ctrl"}, "9"}, pause={{"cmd", "alt", "ctrl"}, "0"} }`
---
--- Returns:
---  * The Pomodoor object
function obj:bindHotkeys(mapping)
	local spec = {
		start = function() self:start() end,
		pause = function() self:pause() end,
		stop = function() self:stop() end,
	}
	spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

--- Pomodoor:cleanup()
--- Method
--- Cleanup resources. Alias for stop().
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Pomodoor object
function obj:cleanup()
	return self:stop()
end

return obj
