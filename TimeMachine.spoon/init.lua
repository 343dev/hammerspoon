--- === TimeMachine ===
---
--- Display active Time Machine backup progress in the menubar.
---
--- TimeMachine polls macOS `tmutil status` and shows a compact two-line menubar
--- item only while a Time Machine backup is running. The menubar item displays
--- backup progress and estimated remaining time when available.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("TimeMachine")
--- spoon.TimeMachine:start()
--- ```
---
--- Optional hotkeys:
--- ```lua
--- spoon.TimeMachine:bindHotkeys({
---   check = {{"cmd", "alt", "ctrl"}, "t"},
---   openPreferences = {{"cmd", "alt", "ctrl"}, "b"},
--- })
--- ```
---
--- Download: https://github.com/343dev/hammerspoon

local canvas = require("hs.canvas")
local drawing = require("hs.drawing")
local fnutils = require("hs.fnutils")
local logger = require("hs.logger")
local menubar = require("hs.menubar")
local spoons = require("hs.spoons")
local task = require("hs.task")
local timer = require("hs.timer")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "TimeMachine"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/hammerspoon"

--- TimeMachine.checkInterval
--- Variable
--- Update interval, in seconds, when no backup is running. Default: 60.
obj.checkInterval = 60

--- TimeMachine.fastInterval
--- Variable
--- Update interval, in seconds, while a backup is running. Default: 1.
obj.fastInterval = 1

--- TimeMachine.logger
--- Variable
--- Logger object used within the Spoon.
obj.logger = logger.new("TimeMachine")

-- Internal state
obj.menubar = nil
obj.timer = nil
obj.task = nil
obj.currentInterval = nil
obj.taskGeneration = 0
obj.isRunning = false

local fontSize = 9
local lineHeight = 10
local textColor = { white = 1, alpha = 0.6 }
local shadowColor = { red = 0, green = 0, blue = 0, alpha = 0.5 }

local function trim(value)
	local trimmed = (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return trimmed
end

local function unquote(value)
	local unquoted = trim(value):gsub("^\"", ""):gsub("\"$", "")
	return unquoted
end

local function parseBoolean(value)
	return unquote(value) == "1" or unquote(value) == "true"
end

local function parseNumber(value)
	return tonumber(unquote(value))
end

local function parseTmutilStatus(output)
	local result = { Running = false, BackupPhase = "", Progress = {} }

	if type(output) ~= "string" or output == "" then
		return result
	end

	local inProgress = false
	local progressDepth = 0

	for line in output:gmatch("[^\r\n]+") do
		local key, value = line:match("^%s*\"?([%w_]+)\"?%s*=%s*(.-)%s*;?%s*$")

		if key and value then
			if key == "Progress" and value:find("{", 1, true) then
				inProgress = true
				progressDepth = 1
			elseif key == "Running" then
				result.Running = parseBoolean(value)
			elseif key == "BackupPhase" then
				result.BackupPhase = unquote(value)
			elseif key == "FractionOfProgressBar" then
				result.Progress.Percent = result.Progress.Percent or parseNumber(value)
			elseif key == "Percent" then
				result.Progress.Percent = parseNumber(value) or 0
			elseif key == "TimeRemaining" then
				result.Progress.TimeRemaining = parseNumber(value)
			end
		end

		if inProgress and not (key == "Progress") then
			local openBraces = select(2, line:gsub("{", ""))
			local closeBraces = select(2, line:gsub("}", ""))
			progressDepth = progressDepth + openBraces - closeBraces

			if progressDepth <= 0 then
				inProgress = false
			end
		end
	end

	return result
end

local function normalizeInterval(value, default)
	local interval = tonumber(value) or default
	if interval < 1 then
		return 1
	end
	return interval
end

local function formatTime(seconds)
	if not seconds or seconds <= 0 then
		return nil
	end

	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

local function createMenubarImage(line1, line2)
	local line1Width = drawing.getTextDrawingSize(line1, { size = fontSize }).w
	local line2Width = drawing.getTextDrawingSize(line2, { size = fontSize }).w
	local width = math.ceil(math.max(line1Width, line2Width))
	local height = lineHeight * 2

	local imgCanvas = canvas.new({ x = 0, y = 0, w = width, h = height })

	imgCanvas[1] = {
		type = "rectangle",
		action = "fill",
		fillColor = { alpha = 0.0 },
		frame = { x = 0, y = 0, w = width, h = height },
	}

	imgCanvas[2] = {
		type = "text",
		text = line1,
		textSize = fontSize,
		textColor = shadowColor,
		textAlignment = "left",
		frame = { x = 0.5, y = 0.5, w = width, h = lineHeight },
	}

	imgCanvas[3] = {
		type = "text",
		text = line1,
		textSize = fontSize,
		textColor = textColor,
		textAlignment = "left",
		frame = { x = 0, y = 0, w = width, h = lineHeight },
	}

	imgCanvas[4] = {
		type = "text",
		text = line2,
		textSize = fontSize,
		textColor = shadowColor,
		textAlignment = "left",
		frame = { x = 0.5, y = lineHeight + 0.5, w = width, h = lineHeight },
	}

	imgCanvas[5] = {
		type = "text",
		text = line2,
		textSize = fontSize,
		textColor = textColor,
		textAlignment = "left",
		frame = { x = 0, y = lineHeight, w = width, h = lineHeight },
	}

	local image = imgCanvas:imageFromCanvas()
	imgCanvas:delete()

	return image
end

local function ensureMenubar(self)
	if self.menubar then
		return true
	end

	self.menubar = menubar.new()
	if not self.menubar then
		self.logger.e("Unable to create menubar item")
		return false
	end

	self.menubar:setClickCallback(function()
		self:openPreferences()
	end)

	return true
end

local function updateDisplay(self, status)
	if not status.Running then
		if self.menubar then
			self.menubar:removeFromMenuBar()
		end
		return
	end

	if not ensureMenubar(self) then
		return
	end

	local phase = status.BackupPhase ~= "" and status.BackupPhase or "Time Machine backup"
	local progress = status.Progress or {}
	local percentValue = progress.Percent
	local percent = percentValue and percentValue > 0 and string.format("%.1f%%", percentValue * 100) or nil
	local timeLeft = formatTime(progress.TimeRemaining)
	local details = {}

	if percent then
		table.insert(details, percent)
	end
	if timeLeft then
		table.insert(details, timeLeft)
	end

	local line2Text = #details > 0 and table.concat(details, " ") or "Calculating..."
	local tooltipText = phase
	if percent then
		tooltipText = tooltipText .. " - " .. percent
	end
	if timeLeft then
		tooltipText = tooltipText .. " - " .. timeLeft .. " left"
	end

	self.menubar:returnToMenuBar()
	self.menubar:setIcon(createMenubarImage("Time Machine", line2Text), false)
	self.menubar:setTitle("")
	self.menubar:setTooltip(tooltipText)
end

local function scheduleNextCheck(self, interval)
	if not self.isRunning then
		return
	end

	interval = normalizeInterval(interval, self.checkInterval)
	self.currentInterval = interval

	if self.timer then
		self.timer:stop()
	end

	self.timer = timer.doAfter(interval, function()
		self.timer = nil
		self:check()
	end)
end

--- TimeMachine:check()
--- Method
--- Run one Time Machine status check immediately.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The TimeMachine object
function obj:check()
	if self.task then
		self.task:terminate()
		self.task = nil
	end

	self.taskGeneration = self.taskGeneration + 1
	local generation = self.taskGeneration

	local statusTask = task.new("/usr/bin/tmutil", function(exitCode, stdout, stderr)
		if generation ~= self.taskGeneration then
			return false
		end

		self.task = nil

		if exitCode ~= 0 then
			self.logger.w("tmutil status failed: " .. (stderr or ("exit " .. tostring(exitCode))))
			scheduleNextCheck(self, self.checkInterval)
			return false
		end

		local status = parseTmutilStatus(stdout)
		updateDisplay(self, status)
		scheduleNextCheck(self, status.Running and self.fastInterval or self.checkInterval)

		return true
	end, { "status" })

	if not statusTask then
		self.logger.e("Unable to create tmutil task")
		scheduleNextCheck(self, self.checkInterval)
		return self
	end

	self.task = statusTask
	statusTask:start()
	return self
end

--- TimeMachine:openPreferences()
--- Method
--- Open the Time Machine pane in macOS System Settings.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The TimeMachine object
function obj:openPreferences()
	hs.execute("open 'x-apple.systempreferences:com.apple.Time-Machine-Settings.extension'")
	return self
end

--- TimeMachine:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for TimeMachine actions.
---
--- Parameters:
---  * mapping - A table containing hotkey details for one or more actions:
---    * check - Run one Time Machine status check immediately
---    * openPreferences - Open Time Machine settings
---
--- Returns:
---  * The TimeMachine object
function obj:bindHotkeys(mapping)
	local spec = {
		check = fnutils.partial(self.check, self),
		openPreferences = fnutils.partial(self.openPreferences, self),
	}

	spoons.bindHotkeysToSpec(spec, mapping)
	return self
end

--- TimeMachine:start()
--- Method
--- Start monitoring Time Machine status.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The TimeMachine object
function obj:start()
	if self.isRunning then
		return self
	end

	self.isRunning = true
	self:check()

	return self
end

--- TimeMachine:stop()
--- Method
--- Stop monitoring Time Machine status and clean up resources.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The TimeMachine object
function obj:stop()
	self.isRunning = false
	self.taskGeneration = self.taskGeneration + 1

	if self.task then
		self.task:terminate()
		self.task = nil
	end

	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	if self.menubar then
		self.menubar:delete()
		self.menubar = nil
	end

	self.currentInterval = nil
	return self
end

return obj
