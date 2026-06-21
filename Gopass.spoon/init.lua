--- === Gopass ===
---
--- Keyboard-driven UI for gopass: search password-store entries, decrypt via
--- pinentry, then type or copy selected fields.
---
--- Usage:
--- ```lua
--- hs.loadSpoon("Gopass")
--- spoon.Gopass:start()
--- -- or configure at start:
--- spoon.Gopass:start({ defaultHotkeys = { show = {{"cmd", "alt"}, "p"} } })
--- ```
---
--- Download: https://github.com/343dev/hammerspoon

local alert = require("hs.alert")
local application = require("hs.application")
local appfinder = require("hs.appfinder")
local chooser = require("hs.chooser")
local eventtap = require("hs.eventtap")
local fnutils = require("hs.fnutils")
local logger = require("hs.logger")
local pasteboard = require("hs.pasteboard")
local spoons = require("hs.spoons")
local task = require("hs.task")
local timer = require("hs.timer")
local urlevent = require("hs.urlevent")
local window = require("hs.window")

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Gopass"
obj.version = "1.0"
obj.author = "343dev"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/343dev/hammerspoon"

obj.logger = logger.new("Gopass")

--- Gopass.defaultHotkeys
--- Variable
--- Default hotkey mapping used by start() when bindHotkeys() has not been called.
--- Maps the show action to Ctrl+Alt+Cmd+P.
obj.defaultHotkeys = {
	show = { { "cmd", "alt", "ctrl" }, "P" },
}

--- Gopass.gopassBin
--- Variable
--- Executable name or path for gopass. The command is launched via /usr/bin/env.
obj.gopassBin = "gopass"

--- Gopass.listArgs
--- Variable
--- Argument list used to fetch password-store entry names.
obj.listArgs = { "ls", "-f" }

--- Gopass.showArgsPrefix
--- Variable
--- Argument prefix used before the selected entry name when decrypting an entry.
obj.showArgsPrefix = { "show" }

--- Gopass.listTimeoutSeconds
--- Variable
--- Timeout, in seconds, for listing entries. Set to 0 or nil to disable.
obj.listTimeoutSeconds = 10

--- Gopass.showTimeoutSeconds
--- Variable
--- Timeout, in seconds, for decrypting an entry. Set to 0 or nil to disable.
obj.showTimeoutSeconds = 30

--- Gopass.gopassRetryOnTimeout
--- Variable
--- Number of times to retry gopass commands that time out.
obj.gopassRetryOnTimeout = 1

--- Gopass.extraPathEntries
--- Variable
--- Additional PATH entries passed to gopass and gpg subprocesses. Useful because
--- GUI-launched Hammerspoon can inherit a minimal launchd PATH.
obj.extraPathEntries = {
	"/opt/homebrew/bin",
	"/usr/local/bin",
	"/opt/local/bin",
}

--- Gopass.extraEnv
--- Variable
--- Extra environment variables passed to gopass and gpg subprocesses.
--- Example: `{ GOPASS_HOMEDIR = "/Users/you/.local/share/gopass" }`.
obj.extraEnv = {}

--- Gopass.pinentryAppName
--- Variable
--- Application name to focus while gopass waits for passphrase entry.
obj.pinentryAppName = "pinentry-mac"

--- Gopass.pinentryFocusAssistSeconds
--- Variable
--- Number of seconds to keep looking for pinentryAppName after decryption starts.
obj.pinentryFocusAssistSeconds = 8

--- Gopass.pinentryFocusAssistInterval
--- Variable
--- Polling interval, in seconds, used while focusing pinentryAppName.
obj.pinentryFocusAssistInterval = 0.2

--- Gopass.maxEntryRows
--- Variable
--- Maximum number of rows shown in the entry chooser.
obj.maxEntryRows = 8

--- Gopass.cacheEntriesSeconds
--- Variable
--- Number of seconds to cache the entry list. Set to 0 or nil to always refresh.
obj.cacheEntriesSeconds = 60

--- Gopass.openConsoleOnError
--- Variable
--- Whether to open the Hammerspoon console when a gopass/gpg command fails.
obj.openConsoleOnError = false

--- Gopass.healthCheckOnStart
--- Variable
--- Whether start() should run lightweight gopass and gpg availability checks.
obj.healthCheckOnStart = true

--- Gopass.healthCheckTimeoutSeconds
--- Variable
--- Timeout, in seconds, for each startup health-check command.
obj.healthCheckTimeoutSeconds = 5

--- Gopass.clipboardAutoClearSeconds
--- Variable
--- Seconds before clearing the clipboard if it still contains the copied secret.
--- Set to nil to disable automatic clearing.
obj.clipboardAutoClearSeconds = 30

--- Gopass.pasteIntoField
--- Variable
--- When true, selected non-URL fields are typed into the previously focused
--- window. When false, selected fields are copied to the clipboard. URL fields
--- always open as URLs.
obj.pasteIntoField = true

--- Gopass.pasteDelaySeconds
--- Variable
--- Delay, in seconds, between refocusing the target window and typing a value.
obj.pasteDelaySeconds = 0.15

--- Gopass.reopenCardSeconds
--- Variable
--- Time window, in seconds, during which show() reopens the last viewed entry
--- card instead of showing the full entry list.
obj.reopenCardSeconds = 90

-- Internal state
obj.entryChooser = nil
obj.fieldChooser = nil
obj.entries = nil
obj.entriesFetchedAt = nil
obj.currentTask = nil
obj.currentTaskTimeoutTimer = nil
obj._envCommandTimeoutTimers = {}
obj.pinentryFocusTimer = nil
obj.clipboardClearTimer = nil
obj._entryReturnTimer = nil
obj._fieldReturnTimer = nil
obj._typeFieldTimer = nil
obj.lastFrontApp = nil
obj.lastFocusedWindow = nil
obj.lastEntryId = nil
obj.lastCardShownAt = nil
obj._escTimestamp = nil

local function nowSeconds()
	return timer.secondsSinceEpoch()
end

local function buildTaskPath(extraEntries, envPath)
	local seen = {}
	local parts = {}

	local function addPathPart(p)
		if type(p) == "string" and p ~= "" and not seen[p] then
			seen[p] = true
			table.insert(parts, p)
		end
	end

	local function addPathString(pathValue)
		if type(pathValue) ~= "string" then
			return
		end
		for p in pathValue:gmatch("[^:]+") do
			addPathPart(p)
		end
	end

	addPathString(os.getenv("PATH") or "")

	for _, p in ipairs(extraEntries or {}) do
		addPathPart(p)
	end

	addPathString(envPath)

	-- Ensure core system paths exist.
	addPathPart("/usr/bin")
	addPathPart("/bin")
	addPathPart("/usr/sbin")
	addPathPart("/sbin")

	return table.concat(parts, ":")
end

local function buildEnvArgs(extraPathEntries, extraEnv)
	local env = extraEnv or {}
	local args = {
		"PATH=" .. buildTaskPath(extraPathEntries, env.PATH or env.Path or env.path),
	}

	for key, value in pairs(env) do
		if type(key) == "string" and key ~= "" and value ~= nil and key:upper() ~= "PATH" then
			table.insert(args, key .. "=" .. tostring(value))
		end
	end

	return args
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function splitLines(s)
	local lines = {}
	if type(s) ~= "string" then
		return lines
	end
	for line in s:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	return lines
end

local function truncate(s, maxLen)
	if type(s) ~= "string" then
		return ""
	end
	if #s <= maxLen then
		return s
	end
	if maxLen <= 3 then
		return s:sub(1, maxLen)
	end
	return s:sub(1, maxLen - 3) .. "..."
end

local function getAppByName(name)
	if not name or name == "" then
		return nil
	end

	local app = application.get(name)
	if app then
		return app
	end

	app = appfinder.appFromName(name)
	if app then
		return app
	end

	-- Common capitalization variants
	app = application.get(name:gsub("^%l", string.upper))
	if app then
		return app
	end

	return appfinder.appFromName(name:gsub("^%l", string.upper))
end

local function normalizeURL(url)
	if type(url) ~= "string" then
		return nil
	end

	local cleaned = trim(url)
	if cleaned == "" then
		return nil
	end

	if cleaned:match("^www%.") then
		cleaned = "https://" .. cleaned
	end

	if not cleaned:match("^https?://") then
		return nil
	end

	return cleaned
end

local configurableProperties = {
	cacheEntriesSeconds = true,
	clipboardAutoClearSeconds = true,
	defaultHotkeys = true,
	extraEnv = true,
	extraPathEntries = true,
	gopassBin = true,
	gopassRetryOnTimeout = true,
	healthCheckOnStart = true,
	healthCheckTimeoutSeconds = true,
	listArgs = true,
	listTimeoutSeconds = true,
	maxEntryRows = true,
	openConsoleOnError = true,
	pasteDelaySeconds = true,
	pasteIntoField = true,
	pinentryAppName = true,
	pinentryFocusAssistInterval = true,
	pinentryFocusAssistSeconds = true,
	reopenCardSeconds = true,
	showArgsPrefix = true,
	showTimeoutSeconds = true,
}

local function applyConfig(self, config)
	if config == nil then
		return
	end

	assert(type(config) == "table", "Gopass:start(config) expects a table")

	for key, value in pairs(config) do
		if key ~= "hotkeys" then
			if configurableProperties[key] then
				self[key] = value
			else
				error("Unknown Gopass config key: " .. tostring(key), 2)
			end
		end
	end

	if config.hotkeys ~= nil then
		self.defaultHotkeys = config.hotkeys
	end
end

function obj:_stopTimer(field)
	if self[field] then
		if self[field].stop then
			self[field]:stop()
		end
		self[field] = nil
	end
end

function obj:_maybeOpenConsoleOnError()
	if self.openConsoleOnError then
		pcall(function()
			hs.openConsole()
		end)
	end
end

function obj:_alertConsoleError()
	alert.show("Gopass error. See Hammerspoon console.", 2)
end

function obj:_cancelCurrentTask()
	self:_stopTimer("currentTaskTimeoutTimer")
	if self.currentTask then
		pcall(function()
			self.currentTask:terminate()
		end)
		self.currentTask = nil
	end
end

function obj:_runGopass(args, opts, cb)
	if type(opts) == "function" and cb == nil then
		cb = opts
		opts = {}
	end
	opts = opts or {}

	self:_cancelCurrentTask()

	local fullArgs = buildEnvArgs(self.extraPathEntries, self.extraEnv)

	table.insert(fullArgs, self.gopassBin)
	for _, a in ipairs(args or {}) do
		table.insert(fullArgs, a)
	end

	local state = {
		timedOut = false,
		timeoutSeconds = tonumber(opts.timeoutSeconds) or 0,
	}

	local t, err = task.new("/usr/bin/env", function(exitCode, stdOut, stdErr)
		self:_stopTimer("currentTaskTimeoutTimer")
		self.currentTask = nil

		local out = stdOut or ""
		local stderr = stdErr or ""
		local meta = { timedOut = state.timedOut }
		if state.timedOut and trim(stderr) == "" then
			stderr = "Command timed out after " .. tostring(state.timeoutSeconds) .. "s"
		end

		cb(exitCode or 1, out, stderr, meta)
	end, fullArgs)

	if not t then
		return nil, err or "Failed to create task"
	end

	self.currentTask = t
	local started = t:start()
	if started == false then
		self.currentTask = nil
		return nil, "Failed to start task"
	end

	if state.timeoutSeconds > 0 then
		self.currentTaskTimeoutTimer = timer.doAfter(state.timeoutSeconds, function()
			if self.currentTask == t then
				state.timedOut = true
				pcall(function()
					t:terminate()
				end)
			end
			self.currentTaskTimeoutTimer = nil
		end)
	end

	return t, nil
end

function obj:_runEnvCommand(bin, args, timeoutSeconds, cb)
	local fullArgs = buildEnvArgs(self.extraPathEntries, self.extraEnv)

	table.insert(fullArgs, bin)
	for _, a in ipairs(args or {}) do
		table.insert(fullArgs, a)
	end

	local timedOut = false
	local timeoutTimer = nil

	local t, err = task.new("/usr/bin/env", function(exitCode, stdOut, stdErr)
		if timeoutTimer then
			if self._envCommandTimeoutTimers then
				self._envCommandTimeoutTimers[timeoutTimer] = nil
			end
			timeoutTimer:stop()
			timeoutTimer = nil
		end

		cb(exitCode or 1, stdOut or "", stdErr or "", { timedOut = timedOut })
	end, fullArgs)

	if not t then
		return nil, err or "Failed to create task"
	end

	local started = t:start()
	if started == false then
		return nil, "Failed to start task"
	end

	local timeout = tonumber(timeoutSeconds) or 0
	if timeout > 0 then
		timeoutTimer = timer.doAfter(timeout, function()
			if self._envCommandTimeoutTimers then
				self._envCommandTimeoutTimers[timeoutTimer] = nil
			end
			timedOut = true
			pcall(function()
				t:terminate()
			end)
			timeoutTimer = nil
		end)
		self._envCommandTimeoutTimers = self._envCommandTimeoutTimers or {}
		self._envCommandTimeoutTimers[timeoutTimer] = true
	end

	return t, nil
end

function obj:_runHealthCheck()
	if not self.healthCheckOnStart then
		return
	end

	self:_runEnvCommand(self.gopassBin, { "--version" }, self.healthCheckTimeoutSeconds, function(code, out, err)
		if code ~= 0 then
			self:_logGopassFailure("healthcheck gopass --version", code, err, out)
			self:_maybeOpenConsoleOnError()
			self:_alertConsoleError()
			return
		end

		self:_runEnvCommand("gpg", { "--version" }, self.healthCheckTimeoutSeconds, function(gpgCode, gpgOut, gpgErr)
			if gpgCode ~= 0 then
				self.logger.e("healthcheck gpg --version failed (exit " ..
					tostring(gpgCode) .. "): " .. truncate(self:_gopassErrorText(gpgErr, gpgOut), 2000))
				self:_maybeOpenConsoleOnError()
				self:_alertConsoleError()
			end
		end)
	end)
end

function obj:_runGopassWithRetry(context, args, opts, cb)
	local attempts = 1
	local retries = tonumber((opts or {}).retryOnTimeout) or 0

	local function runOnce()
		local _, startErr = self:_runGopass(args, opts, function(code, out, err, meta)
			if meta and meta.timedOut and attempts <= retries then
				self.logger.w(context .. " timed out, retrying (" .. tostring(attempts) .. "/" .. tostring(retries) .. ")")
				attempts = attempts + 1
				runOnce()
				return
			end

			cb(code, out, err, meta)
		end)

		if startErr then
			cb(1, "", startErr, { timedOut = false, startError = true })
			return nil, startErr
		end

		return true, nil
	end

	return runOnce()
end

function obj:_gopassErrorText(stdErr, stdOut)
	local err = trim(stdErr or "")
	local out = trim(stdOut or "")
	if err ~= "" then
		return err
	end
	return out
end

function obj:_isCanceled(stdErr, stdOut)
	local msg = (stdErr or "") .. "\n" .. (stdOut or "")
	msg = msg:lower()
	return msg:match("cancel") ~= nil
end

function obj:_logGopassFailure(context, exitCode, stdErr, stdOut)
	local msg = self:_gopassErrorText(stdErr, stdOut)
	if msg == "" then
		msg = "(no output)"
	end

	self.logger.e(context .. " failed (exit " .. tostring(exitCode) .. "): " .. truncate(msg, 2000))
end

function obj:_parseEntryList(out)
	local entries = {}
	for _, line in ipairs(splitLines(out)) do
		line = trim(line)
		if line ~= "" and not line:match("/$") then
			table.insert(entries, line)
		end
	end
	table.sort(entries, function(a, b)
		return a:lower() < b:lower()
	end)
	return entries
end

function obj:_fetchEntries(cb)
	local ageOk = false
	if self.entries and self.entriesFetchedAt and self.cacheEntriesSeconds then
		ageOk = (nowSeconds() - self.entriesFetchedAt) <= self.cacheEntriesSeconds
	end

	if ageOk then
		cb(self.entries, nil)
		return
	end

	self:_runGopassWithRetry("gopass ls", self.listArgs, {
		timeoutSeconds = self.listTimeoutSeconds,
		retryOnTimeout = self.gopassRetryOnTimeout,
	}, function(code, out, err)
		if code ~= 0 then
			self:_logGopassFailure("gopass ls", code, err, out)
			cb(nil, "gopass")
			return
		end

		local entries = self:_parseEntryList(out)
		self.entries = entries
		self.entriesFetchedAt = nowSeconds()
		cb(entries, nil)
	end)
end

function obj:_startPinentryFocusAssist()
	self:_stopTimer("pinentryFocusTimer")

	local deadline = nowSeconds() + (self.pinentryFocusAssistSeconds or 0)
	self.pinentryFocusTimer = timer.doEvery(self.pinentryFocusAssistInterval or 0.2, function()
		if nowSeconds() >= deadline then
			self:_stopTimer("pinentryFocusTimer")
			return
		end

		local app = getAppByName(self.pinentryAppName)
		if app then
			app:activate(true)
			self:_stopTimer("pinentryFocusTimer")
		end
	end)
end

function obj:_parsePassStyle(out)
	local lines = splitLines(out)
	local i = 1
	while i <= #lines and trim(lines[i]) == "" do
		i = i + 1
	end
	if i > #lines then
		return nil, "Empty secret"
	end

	local fields = {}
	table.insert(fields, { key = "password", value = lines[i] })
	local unsafeSet = {}
	local containers = {}

	local function indentWidth(ws)
		local expanded = (ws or ""):gsub("\t", "  ")
		return #expanded
	end

	local function parseUnsafeKeys(value)
		for item in value:gmatch("[^,]+") do
			local keyName = trim(item):lower()
			if keyName ~= "" then
				unsafeSet[keyName] = true
			end
		end
	end

	local notes = {}
	for j = i + 1, #lines do
		local line = lines[j]
		if trim(line) == "---" then
			goto continue
		end
		if trim(line) ~= "" then
			local leading, k, v = line:match("^(%s*)([^:]+)%s*:%s*(.*)%s*$")
			if k then
				k = trim(k)
				local indent = indentWidth(leading)

				while #containers > 0 and indent <= containers[#containers].indent do
					table.remove(containers)
				end

				local fullKey = k
				if #containers > 0 then
					fullKey = containers[#containers].path .. "." .. k
				end

				if v == "" then
					table.insert(containers, { indent = indent, path = fullKey })
				else
					table.insert(fields, { key = fullKey, value = v })
					if k:lower() == "unsafe-keys" then
						parseUnsafeKeys(v)
					end
				end
			else
				table.insert(notes, line)
			end
		end
		::continue::
	end

	if #notes > 0 then
		table.insert(fields, { key = "notes", value = table.concat(notes, "\n") })
	end

	return fields, unsafeSet, nil
end

function obj:_isUnsafeKeyPath(key, unsafeSet)
	if not key then
		return false
	end

	local lower = key:lower()
	if (unsafeSet or {})[lower] then
		return true
	end

	local prefix = ""
	for part in lower:gmatch("[^%.]+") do
		if prefix == "" then
			prefix = part
		else
			prefix = prefix .. "." .. part
		end

		if (unsafeSet or {})[prefix] then
			return true
		end
	end

	return false
end

function obj:_buildEntryChooser()
	if self.entryChooser then
		return
	end

	self.entryChooser = chooser.new(function(choice)
		if not choice then
			return
		end
		self:_onEntrySelected(choice.entryId)
	end)

	self.entryChooser:placeholderText("Search gopass...")
	self.entryChooser:searchSubText(false)
	self.entryChooser:rows(self.maxEntryRows or 12)
end

function obj:_buildFieldChooser()
	if self.fieldChooser then
		return
	end

	self._fieldEscWatcher = eventtap.new({ eventtap.event.types.keyDown }, function(e)
		if e:getKeyCode() == 53 then -- ESC
			self._escTimestamp = timer.secondsSinceEpoch()
		end
		return false
	end)

	self.fieldChooser = chooser.new(function(choice)
		-- Stop ESC watcher whenever chooser closes
		if self._fieldEscWatcher then
			self._fieldEscWatcher:stop()
		end

		if not choice then
			-- Distinguish ESC (go back to list) from click-outside (just close)
			local wasEsc = self._escTimestamp
					and (timer.secondsSinceEpoch() - self._escTimestamp) < 0.2
			self._escTimestamp = nil
			if wasEsc then
				self:_stopTimer("_fieldReturnTimer")
				self._fieldReturnTimer = timer.doAfter(0.15, function()
					self._fieldReturnTimer = nil
					if self.entryChooser then
						self:_showEntryChooser()
					end
				end)
			end
			return
		end
		self._escTimestamp = nil
		self:_copyField(choice.value, choice.label)
	end)

	self.fieldChooser:placeholderText("Select field to copy...")
	self.fieldChooser:searchSubText(true)
	self.fieldChooser:rows(10)
end

function obj:_showEntryChooser()
	self:_buildEntryChooser()
	self.lastFrontApp = application.frontmostApplication()
	self.lastFocusedWindow = window.focusedWindow()

	self:_fetchEntries(function(entries, err)
		if err then
			-- gopass errors are logged to console.
			self:_maybeOpenConsoleOnError()
			self:_alertConsoleError()
			return
		end
		if not entries or #entries == 0 then
			alert.show("No gopass entries found", 2)
			return
		end

		local choices = {}
		for _, id in ipairs(entries) do
			table.insert(choices, {
				text = id,
				entryId = id,
			})
		end

		pcall(function()
			self.entryChooser:query("")
		end)
		self.entryChooser:rows(self.maxEntryRows or 12)
		self.entryChooser:choices(choices)
		self.entryChooser:show()
	end)
end

function obj:_showFieldChooser(entryId, fields, unsafeSet)
	self:_buildFieldChooser()

	if self.pasteIntoField then
		self.fieldChooser:placeholderText("Select field to type...")
	else
		self.fieldChooser:placeholderText("Select field to copy...")
	end

	-- Remember for quick reopen (content is fetched fresh via gopass show)
	self.lastEntryId = entryId
	self.lastCardShownAt = nowSeconds()

	-- Start ESC detection
	self._escTimestamp = nil
	if self._fieldEscWatcher then
		self._fieldEscWatcher:start()
	end

	local choices = {}
	for _, f in ipairs(fields or {}) do
		local label = tostring(f.key or "")
		local value = tostring(f.value or "")
		local preview = value
		local keyLower = label:lower()
		local isMasked = (keyLower == "password") or self:_isUnsafeKeyPath(label, unsafeSet)
		if isMasked then
			preview = "******"
		else
			preview = truncate(preview:gsub("\n", " "), 80)
		end

		table.insert(choices, {
			text = label,
			subText = preview,
			value = value,
			label = label,
			entryId = entryId,
		})
	end

	pcall(function()
		self.fieldChooser:query("")
	end)
	self.fieldChooser:choices(choices)
	self.fieldChooser:show()
end

function obj:_armClipboardClear(copiedValue)
	if not self.clipboardAutoClearSeconds then
		return
	end

	self:_stopTimer("clipboardClearTimer")
	self.clipboardClearTimer = timer.doAfter(self.clipboardAutoClearSeconds, function()
		local current = pasteboard.getContents()
		if current == copiedValue then
			local ok = pcall(function()
				pasteboard.clearContents()
			end)
			if not ok then
				pasteboard.setContents("")
			end
		end
		self.clipboardClearTimer = nil
	end)
end

function obj:_copyField(value, label)
	local labelLower = tostring(label or ""):lower()
	local isURLField = (labelLower == "url") or (labelLower:match("^.+%.url$") ~= nil)
	if isURLField then
		local normalized = normalizeURL(value)
		if normalized then
			local ok = urlevent.openURL(normalized)
			if ok ~= false then
				alert.show("Opened URL", 0.8)
				if self.lastFrontApp then
					pcall(function()
						self.lastFrontApp:activate(true)
					end)
				end
				return
			end
		end
		alert.show("Invalid URL", 1.2)
		return
	end

	if self.pasteIntoField then
		self:_typeField(value, label)
		return
	end

	pasteboard.setContents(value)
	alert.show("Copied " .. tostring(label), 0.8)
	self:_armClipboardClear(value)

	if self.lastFrontApp then
		pcall(function()
			self.lastFrontApp:activate(true)
		end)
	end
end

function obj:_typeField(value, label)
	-- Restore focus to the text field that was active when the chooser opened.
	local focused = false
	if self.lastFocusedWindow then
		focused = pcall(function()
			self.lastFocusedWindow:focus()
		end)
	end
	if not focused and self.lastFrontApp then
		pcall(function()
			self.lastFrontApp:activate(true)
		end)
	end

	-- Give the target window a moment to receive keyboard focus, then type the
	-- value directly via keyboard events (clipboard is not involved).
	self:_stopTimer("_typeFieldTimer")
	self._typeFieldTimer = timer.doAfter(self.pasteDelaySeconds or 0.15, function()
		self._typeFieldTimer = nil
		eventtap.keyStrokes(value)
	end)

	alert.show("Typed " .. tostring(label), 0.8)
end

function obj:_onEntrySelected(entryId)
	if self.entryChooser then
		self.entryChooser:hide()
	end

	self:_startPinentryFocusAssist()

	local args = {}
	for _, a in ipairs(self.showArgsPrefix or {}) do
		table.insert(args, a)
	end
	table.insert(args, entryId)

	local _, startErr = self:_runGopassWithRetry("gopass show " .. tostring(entryId), args, {
		timeoutSeconds = self.showTimeoutSeconds,
		retryOnTimeout = self.gopassRetryOnTimeout,
	}, function(code, out, err)
		self:_stopTimer("pinentryFocusTimer")

		if code ~= 0 then
			if self:_isCanceled(err, out) then
				alert.show("Canceled", 1.2)
			else
				self:_logGopassFailure("gopass show " .. tostring(entryId), code, err, out)
				self:_maybeOpenConsoleOnError()
				self:_alertConsoleError()
			end
			-- Best-effort UX: go back to entry chooser after a cancellation/error.
			self:_stopTimer("_entryReturnTimer")
			self._entryReturnTimer = timer.doAfter(0.2, function()
				self._entryReturnTimer = nil
				if self.entryChooser then
					self:_showEntryChooser()
				end
			end)
			return
		end

		local fields, unsafeSet, parseErr = self:_parsePassStyle(out)
		if parseErr then
			alert.show(parseErr, 2)
			return
		end

		self:_showFieldChooser(entryId, fields, unsafeSet)
	end)

	if startErr then
		self:_stopTimer("pinentryFocusTimer")
		self.logger.e("Failed to start gopass task: " .. tostring(startErr))
		self:_maybeOpenConsoleOnError()
		self:_alertConsoleError()
	end
end

--- Gopass:init()
--- Method
--- Prepares the Spoon. Called automatically by hs.loadSpoon().
---
--- This method does not start tasks, timers, watchers, or bind hotkeys; call
--- start() to activate the Spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Gopass object
function obj:init()
	return self
end

--- Gopass:show()
--- Method
--- Shows the gopass entry chooser, or reopens the last viewed card if it was
--- shown within reopenCardSeconds.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj:show()
	if self.lastEntryId
			and self.lastCardShownAt
			and self.reopenCardSeconds
			and (nowSeconds() - self.lastCardShownAt) < self.reopenCardSeconds
	then
		self.lastFrontApp = application.frontmostApplication()
		self.lastFocusedWindow = window.focusedWindow()
		self:_onEntrySelected(self.lastEntryId)
	else
		self:_showEntryChooser()
	end
end

--- Gopass:bindHotkeys(mapping)
--- Method
--- Binds hotkeys to Spoon actions.
---
--- Supported mapping keys:
---  * show - Show the entry chooser, or reopen the last viewed card.
---
--- Parameters:
---  * mapping - A table mapping action names to hotkey definitions, e.g.
---    `{ show = {{"cmd", "alt"}, "p", message = "Gopass"} }`.
---
--- Returns:
---  * The Gopass object
function obj:bindHotkeys(mapping)
	local spec = {
		show = fnutils.partial(self.show, self),
	}
	spoons.bindHotkeysToSpec(spec, mapping)
	self._hotkeysBound = true
	return self
end

--- Gopass:start([config])
--- Method
--- Applies optional configuration, prepares chooser UI, and runs the optional
--- health check. If bindHotkeys() has not been called, defaultHotkeys are bound.
---
--- Parameters:
---  * config - An optional table of Gopass settings to apply before starting.
---    Supported keys are the documented public variables, plus `hotkeys` as an
---    alias for `defaultHotkeys`.
---
--- Returns:
---  * The Gopass object
function obj:start(config)
	applyConfig(self, config)
	self:_buildEntryChooser()
	self:_buildFieldChooser()
	if not self._hotkeysBound and self.defaultHotkeys then
		self:bindHotkeys(self.defaultHotkeys)
	end
	self:_runHealthCheck()
	self.logger.i("Started")
	return self
end

--- Gopass:stop()
--- Method
--- Stops active tasks, timers, watchers, and chooser UI owned by the Spoon.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The Gopass object
function obj:stop()
	self:_cancelCurrentTask()
	for timeoutTimer in pairs(self._envCommandTimeoutTimers or {}) do
		pcall(function()
			timeoutTimer:stop()
		end)
	end
	self._envCommandTimeoutTimers = {}
	self:_stopTimer("pinentryFocusTimer")
	self:_stopTimer("clipboardClearTimer")
	self:_stopTimer("_entryReturnTimer")
	self:_stopTimer("_fieldReturnTimer")
	self:_stopTimer("_typeFieldTimer")

	if self.entryChooser then
		self.entryChooser:delete()
		self.entryChooser = nil
	end

	if self._fieldEscWatcher then
		self._fieldEscWatcher:stop()
		self._fieldEscWatcher = nil
	end

	if self.fieldChooser then
		self.fieldChooser:delete()
		self.fieldChooser = nil
	end

	self.lastEntryId = nil
	self.lastCardShownAt = nil

	self.logger.i("Stopped")
	return self
end

return obj
