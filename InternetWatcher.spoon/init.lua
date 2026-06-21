--- === InternetWatcher ===
---
--- Monitor internet connectivity and display status in the menubar.
---
--- The Spoon checks a list of connectivity endpoints on a timer. When the
--- connection is considered offline, it shows a warning in the menubar, sends a
--- notification, and plays `offline.wav`. When connectivity is restored, it hides
--- the menubar item, sends a notification, and plays `online.wav`.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("InternetWatcher")
--- spoon.InternetWatcher:start()
--- ```
---
--- Download: https://github.com/343dev/hammerspoon

local http = require("hs.http")
local logger = require("hs.logger")
local menubar = require("hs.menubar")
local notify = require("hs.notify")
local sound = require("hs.sound")
local spoons = require("hs.spoons")
local styledtext = require("hs.styledtext")
local timer = require("hs.timer")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "InternetWatcher"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/hammerspoon"

obj.logger = logger.new("InternetWatcher")

--- InternetWatcher.checkUrls
--- Variable
--- URLs used to check internet connectivity. Requests are made in parallel and
--- the first HTTP 200 or 204 response is treated as success.
obj.checkUrls = {
	"http://cp.cloudflare.com/generate_204",
	"http://connect.rom.miui.com/generate_204",
	"http://google.com/generate_204",
}

--- InternetWatcher.timeout
--- Variable
--- Maximum time, in seconds, to wait for connectivity checks before treating the
--- attempt as failed.
obj.timeout = 1

--- InternetWatcher.checkInterval
--- Variable
--- Interval, in seconds, between connectivity checks while the Spoon is running.
obj.checkInterval = 10

--- InternetWatcher.failureThreshold
--- Variable
--- Number of consecutive failed checks required before the connection is treated
--- as offline.
obj.failureThreshold = 3

--- InternetWatcher.suppressSoundsInFocus
--- Variable
--- Whether status sounds should be suppressed while macOS Focus mode appears active.
obj.suppressSoundsInFocus = true

-- Internal state
obj.status = "unknown"
obj.failureCount = 0
obj.menubar = nil
obj.timer = nil
obj.timeoutTimer = nil
obj.lastCheckedAt = nil
obj.lastCheckResult = "never"
obj.lastCheckStatusCode = nil
obj.lastCheckUrl = nil
obj._currentSound = nil
obj._checkToken = 0

-- Check if Focus mode is active to avoid playing extra sounds.
-- For macOS 12+ (Monterey and later), active Focus assertions are stored in
-- Assertions.json under the storeAssertionRecords key.
local function isFocusActive()
	local assertionsFile = os.getenv("HOME") .. "/Library/DoNotDisturb/DB/Assertions.json"
	local file = io.open(assertionsFile, "r")
	if not file then
		return false
	end

	local content = file:read("*all")
	file:close()

	return content:match('"storeAssertionRecords"%s*:%s*%{%s*"') ~= nil
			or content:match('"storeAssertionRecords"%s*:%s*%[%s*%{') ~= nil
end

local function notifyStatus(title, subtitle, informativeText)
	notify.show(title, subtitle, informativeText or "")
end

local function playSound(self, filename)
	if self.suppressSoundsInFocus and isFocusActive() then
		self.logger.i("Sound suppressed by Focus mode: " .. filename)
		return
	end

	local path = spoons.resourcePath(filename)
	local snd = sound.getByFile(path)
	if snd then
		self._currentSound = snd
		snd:play()
	else
		self.logger.w("Sound not found: " .. filename)
	end
end

local function setTitle(self, title, tooltip)
	self.menubar:setTitle(styledtext.new(title, { font = { size = 10 } }))
	self.menubar:setTooltip(tooltip or "")
end

local function updateStatus(self, isOnline)
	if isOnline then
		self.failureCount = 0
		if self.status ~= "online" then
			self.status = "online"
			self.logger.i("Status changed to online")
			if self.menubar then
				self.menubar:removeFromMenuBar()
			end
			notifyStatus("Online", "Internet connection restored", "")
			playSound(self, "online.wav")
		end
	else
		self.failureCount = self.failureCount + 1
		if self.failureCount >= self.failureThreshold and self.status ~= "offline" then
			self.status = "offline"
			self.logger.i("Status changed to offline")
			if self.menubar then
				self.menubar:returnToMenuBar()
				setTitle(self, "⚠️ No internet", "No internet connection")
			end
			notifyStatus("Offline", "Internet connection lost", "")
			playSound(self, "offline.wav")
		end
	end
end

--- InternetWatcher:check()
--- Method
--- Run one internet connectivity check immediately.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The InternetWatcher object
function obj:check()
	if self.timeoutTimer then
		self.timeoutTimer:stop()
		self.timeoutTimer = nil
	end

	self._checkToken = (self._checkToken or 0) + 1
	local checkToken = self._checkToken

	local urls = self.checkUrls or {}
	local totalAttempts = #urls
	if totalAttempts == 0 then
		self.lastCheckedAt = timer.secondsSinceEpoch()
		self.lastCheckResult = "failed: no check URLs configured"
		self.lastCheckStatusCode = nil
		self.lastCheckUrl = nil
		updateStatus(self, false)
		return self
	end

	local completed = false
	local failedAttempts = 0

	for _, url in ipairs(urls) do
		http.asyncGet(url, { ["User-Agent"] = "Mozilla/5.0" }, function(status)
			if completed or checkToken ~= self._checkToken then
				return
			end

			if status == 200 or status == 204 then
				completed = true
				self.lastCheckedAt = timer.secondsSinceEpoch()
				self.lastCheckResult = "online"
				self.lastCheckStatusCode = status
				self.lastCheckUrl = url
				if self.timeoutTimer then
					self.timeoutTimer:stop()
					self.timeoutTimer = nil
				end
				updateStatus(self, true)
				return
			end

			failedAttempts = failedAttempts + 1
			if failedAttempts >= totalAttempts then
				completed = true
				self.lastCheckedAt = timer.secondsSinceEpoch()
				self.lastCheckResult = "failed"
				self.lastCheckStatusCode = status
				self.lastCheckUrl = url
				if self.timeoutTimer then
					self.timeoutTimer:stop()
					self.timeoutTimer = nil
				end
				updateStatus(self, false)
			end
		end)
	end

	self.timeoutTimer = timer.doAfter(self.timeout, function()
		if not completed and checkToken == self._checkToken then
			completed = true
			self.timeoutTimer = nil
			self.lastCheckedAt = timer.secondsSinceEpoch()
			self.lastCheckResult = "timeout"
			self.lastCheckStatusCode = nil
			self.lastCheckUrl = nil
			updateStatus(self, false)
		end
	end)

	-- hs.http.asyncGet does not provide a cancellation API. _checkToken keeps
	-- stale callbacks from changing state, but requests remain open until they
	-- finish or fail internally.
	return self
end

--- InternetWatcher:showStatus()
--- Method
--- Show current InternetWatcher state in Hammerspoon Console and the Hammerspoon log.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The InternetWatcher object
function obj:showStatus()
	local running = self.timer ~= nil
	local focusActive = isFocusActive()
	local lastChecked = self.lastCheckedAt and string.format("%.0f", self.lastCheckedAt) or "never"
	local statusCode = self.lastCheckStatusCode and tostring(self.lastCheckStatusCode) or "n/a"
	local url = self.lastCheckUrl or "n/a"
	local message = string.format(
		"InternetWatcher: %s\nRunning: %s\nFailures: %d/%d\nLast check: %s\nLast result: %s\nHTTP status: %s\nURL: %s\nFocus active: %s",
		self.status,
		tostring(running),
		self.failureCount,
		self.failureThreshold,
		lastChecked,
		self.lastCheckResult,
		statusCode,
		url,
		tostring(focusActive)
	)

	print(message)
	self.logger.i(message:gsub("\n", "; "))
	return self
end

--- InternetWatcher:start()
--- Method
--- Start monitoring internet connectivity.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The InternetWatcher object
function obj:start()
	if self.timer or self.timeoutTimer or self.menubar then
		self:stop()
	end

	self.status = "unknown"
	self.failureCount = 0
	self.menubar = menubar.new(false)
	self.logger.i("Started")
	self:check()
	self.timer = timer.new(self.checkInterval, function()
		self:check()
	end):start()

	return self
end

--- InternetWatcher:stop()
--- Method
--- Stop monitoring internet connectivity and clean up resources.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The InternetWatcher object
function obj:stop()
	self._checkToken = (self._checkToken or 0) + 1

	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	if self.timeoutTimer then
		self.timeoutTimer:stop()
		self.timeoutTimer = nil
	end

	if self.menubar then
		self.menubar:delete()
		self.menubar = nil
	end

	if self._currentSound then
		self._currentSound:stop()
		self._currentSound = nil
	end

	self.logger.i("Stopped")
	return self
end

return obj
