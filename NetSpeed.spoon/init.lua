--- === NetSpeed ===
---
--- Monitor network interface throughput and display upload/download speed in the menubar.
---
--- NetSpeed reads byte counters from macOS `netstat` for a configurable network
--- interface and renders a compact two-line menubar icon.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("NetSpeed")
--- spoon.NetSpeed:start()
--- ```
---
--- Configure the interface before starting if needed:
--- ```lua
--- spoon.NetSpeed.interface = "en0"
--- spoon.NetSpeed.fallbackInterface = "utun0"
--- spoon.NetSpeed.updateInterval = 1
--- spoon.NetSpeed:start()
--- ```
---
--- Download: https://github.com/343dev/spoons

local canvas = require("hs.canvas")
local logger = require("hs.logger")
local menubar = require("hs.menubar")
local timer = require("hs.timer")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "NetSpeed"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/spoons"

--- NetSpeed.interface
--- Variable
--- Primary network interface to monitor. Default: "en0".
obj.interface = "en0"

--- NetSpeed.fallbackInterface
--- Variable
--- Optional fallback network interface used when `interface` is unavailable. Set to
--- `nil` to disable fallback. Default: nil.
obj.fallbackInterface = nil

--- NetSpeed.updateInterval
--- Variable
--- Interval, in seconds, between menubar updates while the Spoon is running.
obj.updateInterval = 1

--- NetSpeed.logger
--- Variable
--- Logger object used within the Spoon.
obj.logger = logger.new("NetSpeed")

-- Internal state
obj.menubar = nil
obj.timer = nil
obj.updateTimer = nil
obj.lastIBytes = 0
obj.lastOBytes = 0
obj.lastTime = 0
obj.activeInterface = nil

local function interfaceExists(ifaceName)
	if type(ifaceName) ~= "string" or ifaceName == "" then
		return false
	end

	local output = hs.execute("ifconfig -l 2>/dev/null")
	if type(output) ~= "string" or output == "" then
		return false
	end

	for name in output:gmatch("%S+") do
		if name == ifaceName then
			return true
		end
	end

	return false
end

local function getActiveInterface(self)
	if interfaceExists(self.interface) then
		if self.activeInterface ~= self.interface then
			self.logger.i("Using primary interface: " .. self.interface)
			self.activeInterface = self.interface
		end
		return self.activeInterface
	elseif interfaceExists(self.fallbackInterface) then
		if self.activeInterface ~= self.fallbackInterface then
			self.logger.i("Primary interface unavailable, using fallback: " .. self.fallbackInterface)
			self.activeInterface = self.fallbackInterface
		end
		return self.activeInterface
	end
	return nil
end

local function resetCounters(self)
	self.lastIBytes = 0
	self.lastOBytes = 0
	self.lastTime = 0
end

local function getCurrentBytes(self)
	local activeInterface = getActiveInterface(self)

	if not activeInterface then
		return nil, nil
	end

	if not activeInterface:match("^[a-zA-Z0-9]+$") then
		self.logger.w("Invalid interface name: " .. activeInterface)
		return nil, nil
	end

	local output = hs.execute(string.format("netstat -ib -I %s 2>/dev/null | tail -1", activeInterface))

	if not output or output == "" then
		self.logger.w("Failed to get stats for interface: " .. activeInterface)
		return nil, nil
	end

	local parts = {}
	for part in output:gmatch("%S+") do
		table.insert(parts, part)
	end

	if #parts < 10 then
		self.logger.w("Unexpected netstat output format")
		return nil, nil
	end

	local ibytes = tonumber(parts[7])
	local obytes = tonumber(parts[10])

	if not ibytes or not obytes then
		self.logger.w("Failed to parse byte counters from netstat output")
		return nil, nil
	end

	return ibytes, obytes
end

local function formatSpeed(bytesPerSec)
	if not bytesPerSec or bytesPerSec < 0 then
		return "0 B/s"
	end

	local units = { "B/s", "KB/s", "MB/s", "GB/s" }
	local speed = bytesPerSec
	local unitIndex = 1

	while speed >= 1024 and unitIndex < #units do
		speed = speed / 1024
		unitIndex = unitIndex + 1
	end

	return string.format("%.1f %s", speed, units[unitIndex])
end

local function getSpeed(self)
	local currentTime = timer.secondsSinceEpoch()
	local ibytes, obytes = getCurrentBytes(self)

	if not ibytes or not obytes then
		return nil, nil
	end

	if self.lastTime == 0 then
		self.lastIBytes = ibytes
		self.lastOBytes = obytes
		self.lastTime = currentTime
		return 0, 0
	end

	local timeDiff = currentTime - self.lastTime
	if timeDiff == 0 then
		return 0, 0
	end

	local downloadSpeed = (ibytes - self.lastIBytes) / timeDiff
	local uploadSpeed = (obytes - self.lastOBytes) / timeDiff

	self.lastIBytes = ibytes
	self.lastOBytes = obytes
	self.lastTime = currentTime

	return downloadSpeed, uploadSpeed
end

local function createMenubarImage(downloadStr, uploadStr)
	local imageCanvas = canvas.new({ x = 0, y = 0, w = 60, h = 20 })

	local shadowColor = { red = 0, green = 0, blue = 0, alpha = 0.5 }

	imageCanvas[1] = {
		type = "rectangle",
		action = "fill",
		fillColor = { alpha = 0.0 },
		frame = { x = 0, y = 0, w = 60, h = 20 },
	}

	imageCanvas[2] = {
		type = "text",
		text = uploadStr .. " ↑",
		textSize = 9,
		textColor = shadowColor,
		textAlignment = "right",
		frame = { x = 0.5, y = 0.5, w = 60, h = 10 },
	}

	imageCanvas[3] = {
		type = "text",
		text = uploadStr .. " ↑",
		textSize = 9,
		textColor = { red = 1.0, green = 0.4, blue = 0.4, alpha = 1.0 },
		textAlignment = "right",
		frame = { x = 0, y = 0, w = 60, h = 10 },
	}

	imageCanvas[4] = {
		type = "text",
		text = downloadStr .. " ↓",
		textSize = 9,
		textColor = shadowColor,
		textAlignment = "right",
		frame = { x = 0.5, y = 10.5, w = 60, h = 10 },
	}

	imageCanvas[5] = {
		type = "text",
		text = downloadStr .. " ↓",
		textSize = 9,
		textColor = { red = 0.4, green = 0.7, blue = 1.0, alpha = 1.0 },
		textAlignment = "right",
		frame = { x = 0, y = 10, w = 60, h = 10 },
	}

	local image = imageCanvas:imageFromCanvas()
	imageCanvas:delete()
	return image
end

local function updateMenubar(self)
	local prevInterface = self.activeInterface
	local activeInterface = getActiveInterface(self)

	if not activeInterface then
		self.menubar:setIcon(nil, false)
		self.menubar:setTitle("⚠️")
		self.menubar:setTooltip("No network interface available")
		resetCounters(self)
		return
	end

	if prevInterface ~= activeInterface then
		self.logger.i("Interface changed, resetting counters")
		resetCounters(self)
	end

	local download, upload = getSpeed(self)

	if not download or not upload then
		self.menubar:setTitle("⚠️")
		self.menubar:setTooltip(string.format("No data for %s", activeInterface))
		return
	end

	local image = createMenubarImage(formatSpeed(download), formatSpeed(upload))
	self.menubar:setIcon(image, false)
	self.menubar:setTitle("")

	local tooltip = string.format("Network speed on %s", activeInterface)
	if activeInterface ~= self.interface then
		tooltip = tooltip .. " (fallback)"
	end
	self.menubar:setTooltip(tooltip)
end

--- NetSpeed:start()
--- Method
--- Start monitoring network speed
---
--- Parameters:
---  * None
---
--- Returns:
---  * The NetSpeed object
function obj:start()
	if not self.menubar then
		self.menubar = menubar.new()
		if not self.menubar then
			self.logger.ef("Failed to create menubar item")
			return self
		end
	end

	self.menubar:setTitle("...")
	self.menubar:setTooltip("Loading...")

	resetCounters(self)
	self.activeInterface = nil

	if self.timer then
		self.timer:stop()
	end

	self.timer = timer.new(self.updateInterval, function()
		updateMenubar(self)
	end)
	self.timer:start()

	if self.updateTimer then
		self.updateTimer:stop()
	end

	self.updateTimer = timer.doAfter(0.1, function()
		updateMenubar(self)
		self.updateTimer = nil
	end)

	self.logger.i("Started monitoring")
	return self
end

--- NetSpeed:stop()
--- Method
--- Stop monitoring network speed
---
--- Parameters:
---  * None
---
--- Returns:
---  * The NetSpeed object
function obj:stop()
	if self.updateTimer then
		self.updateTimer:stop()
		self.updateTimer = nil
	end

	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	if self.menubar then
		self.menubar:delete()
		self.menubar = nil
	end

	self.logger.i("Stopped")
	return self
end

--- NetSpeed:setInterface(interface)
--- Method
--- Set the primary network interface to monitor
---
--- Parameters:
---  * interface - Network interface name (e.g., "en0", "utun7")
---
--- Returns:
---  * The NetSpeed object
function obj:setInterface(interface)
	if type(interface) ~= "string" or interface == "" or not interface:match("^[a-zA-Z0-9]+$") then
		self.logger.w("Invalid interface name: " .. tostring(interface))
		return self
	end

	self.interface = interface
	resetCounters(self)
	self.activeInterface = nil
	self.logger.i("Interface set to: " .. interface)
	return self
end

return obj
