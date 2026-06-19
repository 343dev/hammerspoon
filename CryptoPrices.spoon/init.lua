--- === CryptoPrices ===
---
--- Display current BTC and ETH prices in USD in the menubar.
---
--- The Spoon fetches prices from the CoinGecko public API on a timer and
--- displays Bitcoin and Ethereum prices as a compact two-line menubar icon.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("CryptoPrices")
--- spoon.CryptoPrices:start()
--- ```
---
--- Download: https://github.com/343dev/spoons

local canvas = require("hs.canvas")
local caffeinate = require("hs.caffeinate")
local drawing = require("hs.drawing")
local http = require("hs.http")
local json = require("hs.json")
local logger = require("hs.logger")
local menubar = require("hs.menubar")
local timer = require("hs.timer")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "CryptoPrices"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/spoons"

obj.logger = logger.new("CryptoPrices")

--- CryptoPrices.updateInterval
--- Variable
--- Interval, in seconds, between price refreshes while the Spoon is running.
obj.updateInterval = 60

-- Internal state
obj.menubar = nil
obj.timer = nil
obj.caffeinateWatcher = nil
obj.btcPrice = nil
obj.ethPrice = nil
obj.btcChange = nil
obj.ethChange = nil
obj.lastUpdated = nil
obj.errorCount = 0
obj.updating = false
obj.requestToken = 0

local fontSize = 9
local lineHeight = 10
local priceUrl =
"https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true&precision=0&include_last_updated_at=true"

local function formatPrice(price)
	if price == nil then return "N/A" end

	local formatted = tostring(price)
	local sign, integer, fraction = formatted:match("^([+-]?)(%d+)(%.?.*)$")
	if not integer then return formatted end

	local groups = {}
	while #integer > 3 do
		table.insert(groups, 1, integer:sub(-3))
		integer = integer:sub(1, -4)
	end
	table.insert(groups, 1, integer)

	return sign .. table.concat(groups, " ") .. fraction
end

local function getColorForChange(change)
	if change == nil then return drawing.color.hammerspoon.osx_yellow end
	return change >= 0 and drawing.color.hammerspoon.osx_green or drawing.color.hammerspoon.osx_red
end

local function createMenubarImage(btcStr, ethStr, btcColor, ethColor)
	local btcWidth = drawing.getTextDrawingSize(btcStr .. " ₿", { size = fontSize }).w
	local ethWidth = drawing.getTextDrawingSize(ethStr .. " Ξ", { size = fontSize }).w
	local width = math.max(btcWidth, ethWidth)
	local height = lineHeight * 2

	local imgCanvas = canvas.new({ x = 0, y = 0, w = width, h = height })
	local shadowColor = { red = 0, green = 0, blue = 0, alpha = 0.5 }

	imgCanvas[1] = {
		type = "rectangle",
		action = "fill",
		fillColor = { alpha = 0.0 },
		frame = { x = 0, y = 0, w = width, h = height },
	}

	imgCanvas[2] = {
		type = "text",
		text = btcStr .. " ₿",
		textSize = fontSize,
		textColor = shadowColor,
		textAlignment = "right",
		frame = { x = 0.5, y = 0.5, w = width, h = lineHeight },
	}

	imgCanvas[3] = {
		type = "text",
		text = btcStr .. " ₿",
		textSize = fontSize,
		textColor = btcColor,
		textAlignment = "right",
		frame = { x = 0, y = 0, w = width, h = lineHeight },
	}

	imgCanvas[4] = {
		type = "text",
		text = ethStr .. " Ξ",
		textSize = fontSize,
		textColor = shadowColor,
		textAlignment = "right",
		frame = { x = 0.5, y = lineHeight + 0.5, w = width, h = lineHeight },
	}

	imgCanvas[5] = {
		type = "text",
		text = ethStr .. " Ξ",
		textSize = fontSize,
		textColor = ethColor,
		textAlignment = "right",
		frame = { x = 0, y = lineHeight, w = width, h = lineHeight },
	}

	return imgCanvas:imageFromCanvas()
end

local function updateDisplay(self, btcStr, ethStr, btcColor, ethColor, tooltip)
	local image = createMenubarImage(btcStr, ethStr, btcColor, ethColor)
	self.menubar:setIcon(image, false)
	self.menubar:setTitle("")
	self.menubar:setTooltip(tooltip)
end

local function handleUpdateFailure(self, reason)
	self.logger.w(reason)
	self.errorCount = self.errorCount + 1

	if self.errorCount >= 10 or (not self.btcPrice and not self.ethPrice) then
		updateDisplay(self, "?", "?", drawing.color.hammerspoon.osx_yellow, drawing.color.hammerspoon.osx_yellow, reason)
	else
		updateDisplay(self, formatPrice(self.btcPrice), formatPrice(self.ethPrice), getColorForChange(self.btcChange),
			getColorForChange(self.ethChange), "Using cached prices - " .. reason)
	end
end

local function decodeResponse(body)
	if type(body) ~= "string" or body == "" then return nil, "Empty response body" end

	local ok, data = pcall(json.decode, body)
	if not ok or type(data) ~= "table" then return nil, "Failed to parse JSON" end

	return data, nil
end

local function updateMenubar(self)
	if self.updating then return end
	if not self.menubar then return end

	self.updating = true
	self.requestToken = self.requestToken + 1
	local requestToken = self.requestToken

	http.asyncGet(priceUrl, nil, function(status, body)
		if requestToken ~= self.requestToken then return end

		if not self.menubar then
			self.updating = false
			return
		end

		local data, parseError = decodeResponse(body)
		local btc = data and data.bitcoin
		local eth = data and data.ethereum

		if status ~= 200 or parseError or not btc or not eth then
			local reason = parseError or "Failed to fetch prices"
			if status ~= 200 then reason = "HTTP " .. tostring(status) end
			if data and (not btc or not eth) then reason = "Missing price data" end

			handleUpdateFailure(self, reason)
			self.updating = false
			return
		end

		self.errorCount = 0
		self.btcPrice = btc.usd
		self.ethPrice = eth.usd
		self.btcChange = btc.usd_24h_change
		self.ethChange = eth.usd_24h_change
		self.lastUpdated = btc.last_updated_at

		local tooltip = self.lastUpdated and ("Last updated: " .. os.date("%d %b, %H:%M", self.lastUpdated))
				or "Crypto Prices"
		updateDisplay(self, formatPrice(self.btcPrice), formatPrice(self.ethPrice), getColorForChange(self.btcChange),
			getColorForChange(self.ethChange), tooltip)

		self.updating = false
	end)
end

--- CryptoPrices:init()
--- Method
--- Initializes the CryptoPrices Spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CryptoPrices object
function obj:init()
	return self
end

--- CryptoPrices:start()
--- Method
--- Start monitoring crypto prices.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CryptoPrices object
function obj:start()
	if not self.menubar then
		self.menubar = menubar.new()
	end

	self.menubar:setTitle("...")
	self.menubar:setTooltip("Loading crypto prices...")

	updateMenubar(self)

	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	self.timer = timer.new(self.updateInterval, function()
		updateMenubar(self)
	end)
	self.timer:start()

	if self.caffeinateWatcher then
		self.caffeinateWatcher:stop()
		self.caffeinateWatcher = nil
	end

	self.caffeinateWatcher = caffeinate.watcher.new(function(event)
		if event == caffeinate.watcher.systemWillSleep or event == caffeinate.watcher.screensDidSleep then
			if self.timer then self.timer:stop() end
			self.requestToken = self.requestToken + 1
			self.updating = false
		elseif event == caffeinate.watcher.systemDidWake or event == caffeinate.watcher.screensDidWake then
			updateMenubar(self)
			if self.timer then self.timer:start() end
		end
	end):start()

	self.logger.i("Started monitoring crypto prices")
	return self
end

--- CryptoPrices:stop()
--- Method
--- Stop monitoring crypto prices.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The CryptoPrices object
function obj:stop()
	if self.timer then
		self.timer:stop()
		self.timer = nil
	end

	if self.caffeinateWatcher then
		self.caffeinateWatcher:stop()
		self.caffeinateWatcher = nil
	end

	if self.menubar then
		self.menubar:delete()
		self.menubar = nil
	end

	self.requestToken = self.requestToken + 1
	self.updating = false

	self.logger.i("Stopped")
	return self
end

return obj
