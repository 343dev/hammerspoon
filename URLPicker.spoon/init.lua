--- === URLPicker ===
---
--- Intercept `http`/`https` URL events and choose which browser opens each link.
---
--- URLPicker registers Hammerspoon as the default handler for web links, then
--- displays a compact browser picker near the mouse cursor whenever a URL is
--- opened. Choose with the mouse, arrow keys, Return, or dismiss with Escape.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("URLPicker")
--- spoon.URLPicker:start()
--- ```
---
--- Optional configuration:
--- ```lua
--- spoon.URLPicker.pinnedBrowsers = { "org.mozilla.firefox" }
--- spoon.URLPicker:start({
---   autoSetDefaultHandlers = true,
---   restoreDefaultHandlersOnStop = false,
---   maxCandidates = 24,
--- })
--- ```
---
--- Download: https://github.com/343dev/spoons

-- @class URLPickerState
-- @field popup table|userdata|nil
-- @field clickTap any|nil
-- @field keyTap any|nil
-- @field items table[]|nil
-- @field rowBgIndexByItem table<number, number>|nil
-- @field labelIndexByItem table<number, number>|nil
-- @field selectedIndex integer
-- @field menuScreenFrame table|nil
-- @field running boolean
-- @field previousHTTPCallback function|nil
-- @field previousDefaultHandlerByScheme table<string, string|nil>

-- @class URLPickerConfig
-- @field autoSetDefaultHandlers boolean
-- @field restoreDefaultHandlersOnStop boolean
-- @field maxCandidates integer

local URLPicker = {}
URLPicker.__index = URLPicker

-- Metadata
URLPicker.name = "URLPicker"
URLPicker.version = "2.0.0"
URLPicker.author = "343dev"
URLPicker.license = "MIT - https://opensource.org/licenses/MIT"
URLPicker.homepage = "https://github.com/343dev/spoons"

--- URLPicker.logger
--- Variable
--- Logger object used within the Spoon.
URLPicker.logger = hs.logger.new("URLPicker", "info")

local log = URLPicker.logger
local HS_BUNDLE_ID = "org.hammerspoon.Hammerspoon"

local SUPPORTED_SCHEMES = {
	http = true,
	https = true,
}

local UI = {
	width = 240,
	rowHeight = 24,
	radius = 13,
	paddingY = 5,

	iconSize = 16,

	fontSize = 13.5,
	labelHeight = 16,

	shadowPad = 20,

	rowInsetX = 6,
	rowRadius = 8,

	separatorHeight = 10,
	separatorInsetX = 16,

	iconInsetX = 14,
	iconToLabelGap = 12,
	labelRightInset = 22,
}

local COLORS = {
	menuBg = { white = 0.965, alpha = 0.985 },

	menuOuterStroke = { white = 0.63, alpha = 0.42 },
	menuInnerStroke = { white = 1.0, alpha = 0.30 },

	rowNormal = { white = 1.0, alpha = 0.001 },
	rowSelected = { red = 0.39, green = 0.64, blue = 0.96, alpha = 1.0 },

	textNormal = { white = 0.19, alpha = 1.0 },
	textSelected = { white = 1.0, alpha = 1.0 },

	separator = { white = 0.78, alpha = 1.0 },

	shadowColor = { white = 0.0, alpha = 0.18 },
}

local IGNORE_BUNDLE_IDS = {
	[HS_BUNDLE_ID] = true,
}

--- URLPicker.pinnedBrowsers
--- Variable
--- Browser bundle IDs pinned to the top of the picker, in display order. Only
--- installed handlers for the URL scheme are shown. Default: `{}`.
---
--- Example: `{ "org.mozilla.firefox", "com.google.Chrome" }`.
URLPicker.pinnedBrowsers = {}

--- URLPicker.config
--- Variable
--- Configuration table used by `start()` and `configure()`.
---
--- Fields:
---  * autoSetDefaultHandlers - If true, `start()` sets Hammerspoon as the default
---    handler for `http` and `https` links. Default: true.
---  * restoreDefaultHandlersOnStop - If true, `stop()` restores the previous
---    default handlers captured by `enable()`. Default: false.
---  * maxCandidates - Maximum number of browser candidates shown in the picker.
---    Default: 24.
-- @type URLPickerConfig
URLPicker.config = {
	autoSetDefaultHandlers = true,
	restoreDefaultHandlersOnStop = false,
	maxCandidates = 24,
}

-- @type URLPickerState
URLPicker.state = {
	popup = nil,
	clickTap = nil,
	keyTap = nil,
	items = nil,
	rowBgIndexByItem = nil,
	labelIndexByItem = nil,
	selectedIndex = 1,
	menuScreenFrame = nil,
	running = false,
	previousHTTPCallback = nil,
	previousDefaultHandlerByScheme = {
		http = nil,
		https = nil,
	},
}

local function stopTap(tap)
	if tap then tap:stop() end
	return nil
end

local function pointInRect(point, rect)
	return point.x >= rect.x
			and point.x <= rect.x + rect.w
			and point.y >= rect.y
			and point.y <= rect.y + rect.h
end

local function utf8Length(text)
	if not utf8 or type(utf8.codes) ~= "function" then
		return #text
	end

	local length = 0
	for _ in utf8.codes(text) do
		length = length + 1
	end
	return length
end

local function truncate(text, maxLen)
	if type(text) ~= "string" then return "" end
	if type(maxLen) ~= "number" or maxLen < 1 then return "…" end
	if utf8Length(text) <= maxLen then return text end

	if utf8 and type(utf8.offset) == "function" then
		local bytePos = utf8.offset(text, maxLen)
		if bytePos then
			return text:sub(1, bytePos - 1) .. "…"
		end
	end

	return text:sub(1, maxLen - 1) .. "…"
end

local function extractScheme(url)
	if type(url) ~= "string" then return nil end
	local scheme = url:match("^([%w+.-]+):")
	if not scheme then return nil end
	return string.lower(scheme)
end

local function isSupportedURL(url)
	local scheme = extractScheme(url)
	return scheme ~= nil and SUPPORTED_SCHEMES[scheme] == true
end

local function collectHandlersForScheme(scheme)
	local handlers = hs.urlevent.getAllHandlersForScheme(scheme) or {}
	local seen = {}
	local result = {}

	for _, bundleID in ipairs(handlers) do
		if not IGNORE_BUNDLE_IDS[bundleID] and not seen[bundleID] then
			seen[bundleID] = true
			local name = hs.application.nameForBundleID(bundleID)
			if name then
				table.insert(result, {
					bundleID = bundleID,
					name = name,
					icon = hs.image.imageFromAppBundle(bundleID),
				})
			else
				log.w(string.format("Skipping handler without app name: %s", bundleID))
			end
		end
	end

	table.sort(result, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	return result
end

local function getBrowserCandidatesForURL(url)
	local scheme = extractScheme(url)
	if not scheme then return {} end

	local candidates = collectHandlersForScheme(scheme)

	-- Practical fallback: if https has no handlers (uncommon), try http.
	if #candidates == 0 and scheme == "https" then
		log.w("No HTTPS handlers found, falling back to HTTP handlers")
		candidates = collectHandlersForScheme("http")
	end

	return candidates
end

local function buildMenuItems(candidates, maxCandidates, pinnedBrowsers)
	local pinnedByBundleID = {}
	local pinned = {}
	local rest = {}

	for index, bundleID in ipairs(pinnedBrowsers or {}) do
		pinnedByBundleID[bundleID] = index
	end

	for _, item in ipairs(candidates) do
		if pinnedByBundleID[item.bundleID] then
			table.insert(pinned, item)
		else
			table.insert(rest, item)
		end
	end

	table.sort(pinned, function(a, b)
		return pinnedByBundleID[a.bundleID] < pinnedByBundleID[b.bundleID]
	end)

	local ordered = {}
	for _, item in ipairs(pinned) do
		table.insert(ordered, item)
	end
	for _, item in ipairs(rest) do
		table.insert(ordered, item)
	end

	local clipped = {}
	local limit = math.max(1, maxCandidates or #ordered)
	for i = 1, math.min(#ordered, limit) do
		table.insert(clipped, ordered[i])
	end

	local items = {}
	local pinnedCount = math.min(#pinned, #clipped)

	for i = 1, pinnedCount do
		table.insert(items, {
			kind = "browser",
			data = clipped[i],
		})
	end

	if pinnedCount > 0 and #clipped > pinnedCount then
		table.insert(items, {
			kind = "separator",
		})
	end

	for i = pinnedCount + 1, #clipped do
		table.insert(items, {
			kind = "browser",
			data = clipped[i],
		})
	end

	return items, (#ordered - #clipped)
end

local function getMenuHeight(items)
	local height = UI.paddingY * 2

	for _, item in ipairs(items) do
		if item.kind == "separator" then
			height = height + UI.separatorHeight
		else
			height = height + UI.rowHeight
		end
	end

	return height
end

local function getSelectableRowCenters(items)
	local centers = {}
	local currentY = UI.paddingY

	for idx, item in ipairs(items) do
		if item.kind == "separator" then
			currentY = currentY + UI.separatorHeight
		elseif item.kind == "browser" then
			centers[idx] = currentY + math.floor(UI.rowHeight / 2)
			currentY = currentY + UI.rowHeight
		end
	end

	return centers
end

local function buildPopupFrames(items)
	local mousePos = hs.mouse.absolutePosition()
	local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
	local screenFrame = screen:frame()

	local menuW = UI.width
	local menuH = getMenuHeight(items)

	local canvasW = menuW + (UI.shadowPad * 2)
	local canvasH = menuH + (UI.shadowPad * 2)

	local rowCenters = getSelectableRowCenters(items)

	local firstSelectableCenter
	local lastSelectableCenter

	for i = 1, #items do
		if rowCenters[i] then
			firstSelectableCenter = rowCenters[i]
			break
		end
	end

	for i = #items, 1, -1 do
		if rowCenters[i] then
			lastSelectableCenter = rowCenters[i]
			break
		end
	end

	if not firstSelectableCenter then
		firstSelectableCenter = UI.paddingY + math.floor(UI.rowHeight / 2)
	end

	if not lastSelectableCenter then
		lastSelectableCenter = menuH - UI.paddingY - math.floor(UI.rowHeight / 2)
	end

	local anchorOffsetX = 1
	local openToRight = true
	local openDown = true

	if mousePos.x + anchorOffsetX + menuW > screenFrame.x + screenFrame.w - 4 then
		openToRight = false
	end

	if mousePos.y - firstSelectableCenter + menuH > screenFrame.y + screenFrame.h - 4 then
		openDown = false
	end

	local menuScreenX
	local menuScreenY

	if openToRight then
		menuScreenX = mousePos.x + anchorOffsetX
	else
		menuScreenX = mousePos.x - menuW - anchorOffsetX
	end

	if openDown then
		menuScreenY = mousePos.y - firstSelectableCenter
	else
		menuScreenY = mousePos.y - lastSelectableCenter
	end

	if menuScreenX < screenFrame.x + 4 then
		menuScreenX = screenFrame.x + 4
	end

	if menuScreenY < screenFrame.y + 4 then
		menuScreenY = screenFrame.y + 4
	end

	if menuScreenX + menuW > screenFrame.x + screenFrame.w - 4 then
		menuScreenX = screenFrame.x + screenFrame.w - menuW - 4
	end

	if menuScreenY + menuH > screenFrame.y + screenFrame.h - 4 then
		menuScreenY = screenFrame.y + screenFrame.h - menuH - 4
	end

	local canvasX = menuScreenX - UI.shadowPad
	local canvasY = menuScreenY - UI.shadowPad

	if canvasX < screenFrame.x then
		canvasX = screenFrame.x
	end

	if canvasY < screenFrame.y then
		canvasY = screenFrame.y
	end

	if canvasX + canvasW > screenFrame.x + screenFrame.w then
		canvasX = screenFrame.x + screenFrame.w - canvasW
	end

	if canvasY + canvasH > screenFrame.y + screenFrame.h then
		canvasY = screenFrame.y + screenFrame.h - canvasH
	end

	return {
		canvas = {
			x = canvasX,
			y = canvasY,
			w = canvasW,
			h = canvasH,
		},
		menu = {
			x = menuScreenX - canvasX,
			y = menuScreenY - canvasY,
			w = menuW,
			h = menuH,
		},
		menuScreen = {
			x = menuScreenX,
			y = menuScreenY,
			w = menuW,
			h = menuH,
		},
	}
end

local function cleanupUI()
	URLPicker.state.clickTap = stopTap(URLPicker.state.clickTap)
	URLPicker.state.keyTap = stopTap(URLPicker.state.keyTap)

	URLPicker.state.items = nil
	URLPicker.state.rowBgIndexByItem = nil
	URLPicker.state.labelIndexByItem = nil
	URLPicker.state.selectedIndex = 1
	URLPicker.state.menuScreenFrame = nil

	if URLPicker.state.popup then
		local popup = URLPicker.state.popup -- @type any
		popup:delete()
		URLPicker.state.popup = nil
	end
end

local function isSelectableIndex(idx)
	if not URLPicker.state.items then return false end
	local item = URLPicker.state.items[idx]
	return item and item.kind == "browser"
end

local function findFirstSelectableIndex()
	if not URLPicker.state.items then return nil end

	for i, item in ipairs(URLPicker.state.items) do
		if item.kind == "browser" then
			return i
		end
	end

	return nil
end

local function findNextSelectableIndex(startIndex, step)
	if not URLPicker.state.items then return nil end

	local i = startIndex + step
	while i >= 1 and i <= #URLPicker.state.items do
		if isSelectableIndex(i) then
			return i
		end
		i = i + step
	end

	return nil
end

local function setSelectedIndex(idx)
	if not URLPicker.state.popup or not URLPicker.state.items or #URLPicker.state.items == 0 then
		return
	end

	if not isSelectableIndex(idx) then
		return
	end

	URLPicker.state.selectedIndex = idx

	for i, item in ipairs(URLPicker.state.items) do
		local rowBgIndex = URLPicker.state.rowBgIndexByItem[i]
		local labelIndex = URLPicker.state.labelIndexByItem[i]
		local isSelected = (i == idx)

		if item.kind == "browser" then
			if rowBgIndex then
				URLPicker.state.popup[rowBgIndex].fillColor = isSelected and COLORS.rowSelected or COLORS.rowNormal
			end
			if labelIndex then
				URLPicker.state.popup[labelIndex].textColor = isSelected and COLORS.textSelected or COLORS.textNormal
			end
		end
	end
end

local function openURLInBrowser(url, bundleID)
	cleanupUI()

	if type(url) ~= "string" or url == "" then
		log.e("Cannot open URL: invalid URL")
		hs.alert.show("Invalid URL")
		return
	end

	if type(bundleID) ~= "string" or bundleID == "" then
		log.e("Cannot open URL: invalid browser bundle ID")
		hs.alert.show("Invalid browser")
		return
	end

	local ok = hs.urlevent.openURLWithBundle(url, bundleID)
	if ok then return end

	log.e(string.format("Failed to open URL with bundle '%s'. URL: %s", bundleID, url))
	local fallbackOK = hs.urlevent.openURL(url)
	if fallbackOK then
		log.w("Opened URL with system default browser as fallback")
		hs.alert.show("Failed in selected browser, opened with default")
	else
		log.e("Fallback openURL also failed")
		hs.alert.show("Failed to open URL")
	end
end

local function renderPopup(url, items)
	URLPicker.state.items = items
	URLPicker.state.rowBgIndexByItem = {}
	URLPicker.state.labelIndexByItem = {}

	local frames = buildPopupFrames(items)
	URLPicker.state.menuScreenFrame = frames.menuScreen

	local canvas = hs.canvas.new(frames.canvas)
			:level(hs.canvas.windowLevels.modalPanel)
			:clickActivating(false)

	URLPicker.state.popup = canvas

	canvas[1] = {
		id = "background_fill",
		type = "rectangle",
		action = "fill",
		frame = {
			x = frames.menu.x,
			y = frames.menu.y,
			w = frames.menu.w,
			h = frames.menu.h,
		},
		roundedRectRadii = { xRadius = UI.radius, yRadius = UI.radius },
		fillColor = COLORS.menuBg,
		withShadow = true,
		shadow = {
			blurRadius = 18,
			color = COLORS.shadowColor,
			offset = { h = 0, w = 0 },
		},
	}

	canvas[2] = {
		id = "background_outer_stroke",
		type = "rectangle",
		action = "stroke",
		frame = {
			x = frames.menu.x,
			y = frames.menu.y,
			w = frames.menu.w,
			h = frames.menu.h,
		},
		roundedRectRadii = { xRadius = UI.radius, yRadius = UI.radius },
		strokeColor = COLORS.menuOuterStroke,
		strokeWidth = 1,
	}

	canvas[3] = {
		id = "background_inner_stroke",
		type = "rectangle",
		action = "stroke",
		frame = {
			x = frames.menu.x + 1,
			y = frames.menu.y + 1,
			w = frames.menu.w - 2,
			h = frames.menu.h - 2,
		},
		roundedRectRadii = { xRadius = UI.radius - 1, yRadius = UI.radius - 1 },
		strokeColor = COLORS.menuInnerStroke,
		strokeWidth = 1,
	}

	local elementIndex = 4
	local currentY = frames.menu.y + UI.paddingY

	for idx, item in ipairs(items) do
		if item.kind == "separator" then
			local lineY = currentY + math.floor(UI.separatorHeight / 2)

			canvas[elementIndex] = {
				id = "separator_" .. idx,
				type = "rectangle",
				action = "fill",
				fillColor = COLORS.separator,
				frame = {
					x = frames.menu.x + UI.separatorInsetX,
					y = lineY,
					w = frames.menu.w - (UI.separatorInsetX * 2),
					h = 1,
				},
			}
			elementIndex = elementIndex + 1
			currentY = currentY + UI.separatorHeight
		else
			local browser = item.data
			local rowY = currentY
			local iconY = rowY + math.floor((UI.rowHeight - UI.iconSize) / 2)
			local labelY = rowY + math.floor((UI.rowHeight - UI.labelHeight) / 2)

			URLPicker.state.rowBgIndexByItem[idx] = elementIndex
			canvas[elementIndex] = {
				id = "rowbg_" .. idx,
				type = "rectangle",
				action = "fill",
				fillColor = COLORS.rowNormal,
				frame = {
					x = frames.menu.x + UI.rowInsetX,
					y = rowY,
					w = frames.menu.w - (UI.rowInsetX * 2),
					h = UI.rowHeight,
				},
				roundedRectRadii = { xRadius = UI.rowRadius, yRadius = UI.rowRadius },
				trackMouseEnterExit = true,
				trackMouseDown = true,
				trackMouseByBounds = true,
			}
			elementIndex = elementIndex + 1

			if browser.icon then
				canvas[elementIndex] = {
					id = "icon_" .. idx,
					type = "image",
					image = browser.icon,
					imageAlignment = "center",
					imageScaling = "scaleProportionally",
					frame = {
						x = frames.menu.x + UI.iconInsetX,
						y = iconY,
						w = UI.iconSize,
						h = UI.iconSize,
					},
				}
				elementIndex = elementIndex + 1
			end

			URLPicker.state.labelIndexByItem[idx] = elementIndex
			canvas[elementIndex] = {
				id = "label_" .. idx,
				type = "text",
				text = truncate(browser.name, 34),
				textFont = ".AppleSystemUIFont",
				textSize = UI.fontSize,
				textColor = COLORS.textNormal,
				textAlignment = "left",
				frame = {
					x = frames.menu.x + UI.iconInsetX + UI.iconSize + UI.iconToLabelGap,
					y = labelY,
					w = frames.menu.w - (UI.iconInsetX + UI.iconSize + UI.iconToLabelGap) - UI.labelRightInset,
					h = UI.labelHeight,
				},
			}
			elementIndex = elementIndex + 1

			currentY = currentY + UI.rowHeight
		end
	end

	canvas:mouseCallback(function(_, message, elementID)
		local idx = type(elementID) == "string" and elementID:match("^rowbg_(%d+)$") or nil
		idx = idx and tonumber(idx) or nil

		if message == "mouseEnter" and idx and isSelectableIndex(idx) then
			setSelectedIndex(idx)
			return
		end

		if message == "mouseDown" and idx and isSelectableIndex(idx) then
			local selectedItem = items[idx]
			if selectedItem and selectedItem.kind == "browser" then
				openURLInBrowser(url, selectedItem.data.bundleID)
			end
		end
	end)

	canvas:show()
	canvas:bringToFront(true)

	local firstSelectableIndex = findFirstSelectableIndex()
	if firstSelectableIndex then
		setSelectedIndex(firstSelectableIndex)
	end

	URLPicker.state.clickTap = hs.eventtap.new({
		hs.eventtap.event.types.leftMouseDown,
		hs.eventtap.event.types.rightMouseDown,
		hs.eventtap.event.types.otherMouseDown,
	}, function(_)
		if not URLPicker.state.popup or not URLPicker.state.menuScreenFrame then
			return false
		end

		local point = hs.mouse.absolutePosition()
		if not pointInRect(point, URLPicker.state.menuScreenFrame) then
			cleanupUI()
		end
		return false
	end):start()

	URLPicker.state.keyTap = hs.eventtap.new({
		hs.eventtap.event.types.keyDown,
	}, function(event)
		if not URLPicker.state.popup or not URLPicker.state.items then
			return false
		end

		local keyCode = event:getKeyCode()

		if keyCode == hs.keycodes.map.down then
			local nextIndex = findNextSelectableIndex(URLPicker.state.selectedIndex, 1)
			if nextIndex then setSelectedIndex(nextIndex) end
			return true
		end

		if keyCode == hs.keycodes.map.up then
			local prevIndex = findNextSelectableIndex(URLPicker.state.selectedIndex, -1)
			if prevIndex then setSelectedIndex(prevIndex) end
			return true
		end

		if keyCode == hs.keycodes.map["return"] or keyCode == hs.keycodes.map.padenter then
			local selectedItem = URLPicker.state.items[URLPicker.state.selectedIndex]
			if selectedItem and selectedItem.kind == "browser" then
				openURLInBrowser(url, selectedItem.data.bundleID)
			end
			return true
		end

		if keyCode == hs.keycodes.map.escape then
			cleanupUI()
			return true
		end

		return false
	end):start()
end

--- URLPicker:init()
--- Method
--- Initializes the URLPicker Spoon. Called automatically by `hs.loadSpoon()`.
---
--- This method does not register URL handlers, change default browser settings,
--- start event taps, or show UI. Call `start()` to enable URL interception.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The URLPicker object
function URLPicker:init()
	return self
end

--- URLPicker:configure(config)
--- Method
--- Applies configuration values without starting the Spoon.
---
--- Parameters:
---  * config - A table containing any of the following optional keys:
---    * autoSetDefaultHandlers - A boolean controlling whether `start()` calls
---      `enable()` automatically.
---    * restoreDefaultHandlersOnStop - A boolean controlling whether `stop()`
---      restores default URL handlers captured by `enable()`.
---    * maxCandidates - A number limiting browser candidates shown in the picker.
---    * pinnedBrowsers - An array of browser bundle IDs pinned to the top of the
---      picker, for example `{ "org.mozilla.firefox", "com.google.Chrome" }`.
---
--- Returns:
---  * The URLPicker object
function URLPicker:configure(config)
	if type(config) ~= "table" then
		return self
	end

	for k, v in pairs(config) do
		if k == "maxCandidates" then
			if type(v) == "number" and v >= 1 then
				self.config.maxCandidates = math.floor(v)
			else
				log.w("Invalid maxCandidates value, ignoring")
			end
		elseif k == "autoSetDefaultHandlers" or k == "restoreDefaultHandlersOnStop" then
			if type(v) == "boolean" then
				self.config[k] = v
			else
				log.w(string.format("Invalid %s value, ignoring", k))
			end
		elseif self.config[k] ~= nil then
			self.config[k] = v
		end
	end

	if type(config.pinnedBrowsers) == "table" then
		local cloned = {}
		for _, bundleID in ipairs(config.pinnedBrowsers) do
			if type(bundleID) == "string" and bundleID ~= "" then
				table.insert(cloned, bundleID)
			end
		end
		self.pinnedBrowsers = cloned
	end

	return self
end

--- URLPicker:show(url)
--- Method
--- Shows the browser picker for a URL.
---
--- Parameters:
---  * url - A string containing an `http` or `https` URL.
---
--- Returns:
---  * A boolean, true if the picker was shown, otherwise false
function URLPicker:show(url)
	if type(url) ~= "string" or url == "" then
		log.e("show() called with empty URL")
		hs.alert.show("Invalid URL")
		return false
	end

	if not isSupportedURL(url) then
		log.w(string.format("Unsupported URL scheme: %s", tostring(extractScheme(url))))
		hs.alert.show("Unsupported URL scheme")
		return false
	end

	cleanupUI()

	local candidates = getBrowserCandidatesForURL(url)
	if #candidates == 0 then
		log.w(string.format("No browser handlers found for URL: %s", url))
		hs.alert.show("No browser handlers found")
		return false
	end

	local items, clippedCount = buildMenuItems(candidates, self.config.maxCandidates, self.pinnedBrowsers)
	if clippedCount > 0 then
		log.w(string.format("Candidate list clipped: %d hidden", clippedCount))
		hs.alert.show(string.format("Showing first %d browsers", #items))
	end

	renderPopup(url, items)
	return true
end

local function setDefaultHandlerForScheme(scheme)
	local current = hs.urlevent.getDefaultHandler(scheme)
	if URLPicker.state.previousDefaultHandlerByScheme[scheme] == nil then
		URLPicker.state.previousDefaultHandlerByScheme[scheme] = current
	end

	if current ~= HS_BUNDLE_ID then
		hs.urlevent.setDefaultHandler(scheme)
		log.i(string.format("Requested Hammerspoon as default '%s' handler", scheme))
	end

	return true
end

local function restoreDefaultHandlers()
	for scheme in pairs(SUPPORTED_SCHEMES) do
		local previous = URLPicker.state.previousDefaultHandlerByScheme[scheme]
		if previous and previous ~= HS_BUNDLE_ID then
			hs.urlevent.setDefaultHandler(scheme, previous)
			log.i(string.format("Requested restore of default '%s' handler to '%s'", scheme, previous))
		end
		URLPicker.state.previousDefaultHandlerByScheme[scheme] = nil
	end
end

local function delegateToPreviousCallback(eventName, params, senderPID, fullURL)
	local cb = URLPicker.state.previousHTTPCallback
	if type(cb) ~= "function" then
		return
	end

	local ok, err = pcall(cb, eventName, params, senderPID, fullURL)
	if not ok then
		log.e(string.format("Previous URL callback failed: %s", tostring(err)))
	end
end

local function onHTTPEvent(eventName, params, senderPID, fullURL)
	if not URLPicker.state.running then
		delegateToPreviousCallback(eventName, params, senderPID, fullURL)
		return
	end

	if isSupportedURL(fullURL) then
		URLPicker:show(fullURL)
		return
	end

	-- Do not swallow unrelated URL events.
	delegateToPreviousCallback(eventName, params, senderPID, fullURL)
end

--- URLPicker:enable()
--- Method
--- Sets Hammerspoon as the default handler for `http` and `https` URLs.
---
--- The previous handlers are remembered so they can be restored later by
--- `disable()` or by `stop()` when `restoreDefaultHandlersOnStop` is true.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A boolean, true after both default-handler change requests are submitted
function URLPicker:enable()
	local okHTTP = setDefaultHandlerForScheme("http")
	local okHTTPS = setDefaultHandlerForScheme("https")
	return okHTTP and okHTTPS
end

--- URLPicker:disable()
--- Method
--- Restores the default `http` and `https` URL handlers captured by `enable()`.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A boolean, true after the restore attempt completes
function URLPicker:disable()
	restoreDefaultHandlers()
	return true
end

--- URLPicker:cleanup()
--- Method
--- Closes the browser picker UI and stops temporary event taps.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The URLPicker object
function URLPicker:cleanup()
	cleanupUI()
	return self
end

--- URLPicker:start([config])
--- Method
--- Starts URL interception.
---
--- Parameters:
---  * config - An optional configuration table accepted by `configure()`.
---
--- Returns:
---  * The URLPicker object
function URLPicker:start(config)
	if self.state.running then
		log.i("URLPicker is already running")
		return self
	end

	self:configure(config)

	self.state.previousHTTPCallback = hs.urlevent.httpCallback
	hs.urlevent.httpCallback = onHTTPEvent

	if self.config.autoSetDefaultHandlers then
		self:enable()
	end

	self.state.running = true
	log.i("URLPicker started")
	return self
end

--- URLPicker:stop()
--- Method
--- Stops URL interception and closes any visible picker UI.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The URLPicker object
function URLPicker:stop()
	if not self.state.running then
		cleanupUI()
		return self
	end

	cleanupUI()

	if hs.urlevent.httpCallback == onHTTPEvent then
		hs.urlevent.httpCallback = self.state.previousHTTPCallback
		self.state.previousHTTPCallback = nil
	else
		log.w("httpCallback was changed by another module; keeping previousHTTPCallback for diagnostics")
	end

	if self.config.restoreDefaultHandlersOnStop then
		restoreDefaultHandlers()
	end
	self.state.running = false
	log.i("URLPicker stopped")
	return self
end

return URLPicker
