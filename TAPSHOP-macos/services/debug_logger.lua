local JsonDisk = require("persistence.json_disk")
local Paths = require("persistence.paths")

local DebugLogger = {}
DebugLogger.__index = DebugLogger

local SCHEMA_VERSION = 1
local DEFAULT_LEVEL = "debug"
local DEFAULT_CAPTURE_MODE = "redacted"
local DEFAULT_TTL_SECONDS = 3600
local DEFAULT_MAX_RECORDS = 25000
local DEFAULT_MAX_BYTES = 5 * 1024 * 1024
local DEFAULT_KEEP_LATEST_LOGS = 5
local STOP_RECORD_RESERVE_BYTES = 1024

local LEVELS = {
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
  trace = 5,
}

local VALID_DOMAINS = {
  logger = true,
  startup = true,
  window = true,
  focus = true,
  popover = true,
  hotkey = true,
  persistence = true,
  recovery = true,
}

local VALID_CAPTURE_MODES = {
  structural = true,
  redacted = true,
  unredacted = true,
}

local STRUCTURAL_STRING_KEYS = {
  code = true,
  decision = true,
  domain = true,
  event = true,
  kind = true,
  level = true,
  mode = true,
  operation = true,
  phase = true,
  reason = true,
  result = true,
  source = true,
  status = true,
  stopReason = true,
  type = true,
}

local FORBIDDEN_KEYS = {
  clipboard = true,
  clipboardText = true,
  image = true,
  object = true,
  raw = true,
  screenshot = true,
  selectedText = true,
  userdata = true,
}

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function ensureDir(path)
  os.execute("mkdir -p " .. shellQuote(path))
end

local function readAll(path)
  local handle = io.open(path, "r")
  if not handle then
    return nil
  end
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function fileExists(path)
  local handle = io.open(path, "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

local function trim(value)
  if type(value) ~= "string" then
    return nil
  end
  local trimmed = value:match("^%s*(.-)%s*$")
  if trimmed == "" then
    return nil
  end
  return trimmed
end

local function sortedKeys(value)
  local keys = {}
  for key, _ in pairs(value or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys, function(left, right)
    if type(left) == type(right) then
      return tostring(left) < tostring(right)
    end
    return type(left) < type(right)
  end)
  return keys
end

local function isArray(value)
  local maxIndex = 0
  local count = 0
  for key, _ in pairs(value or {}) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    if key > maxIndex then
      maxIndex = key
    end
    count = count + 1
  end
  return maxIndex == count
end

local function encodeString(value)
  local escaped = tostring(value)
  escaped = escaped:gsub("\\", "\\\\")
  escaped = escaped:gsub("\"", "\\\"")
  escaped = escaped:gsub("\b", "\\b")
  escaped = escaped:gsub("\f", "\\f")
  escaped = escaped:gsub("\n", "\\n")
  escaped = escaped:gsub("\r", "\\r")
  escaped = escaped:gsub("\t", "\\t")
  return "\"" .. escaped .. "\""
end

local function encodeJson(value)
  local valueType = type(value)
  if valueType == "nil" then
    return "null"
  end
  if valueType == "boolean" or valueType == "number" then
    return tostring(value)
  end
  if valueType == "string" then
    return encodeString(value)
  end
  if valueType ~= "table" then
    return nil
  end

  local parts = {}
  if isArray(value) then
    for index = 1, #value do
      parts[#parts + 1] = encodeJson(value[index]) or "null"
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  for _, key in ipairs(sortedKeys(value)) do
    local encoded = encodeJson(value[key])
    if encoded ~= nil then
      parts[#parts + 1] = encodeString(tostring(key)) .. ":" .. encoded
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function cloneArray(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    out[#out + 1] = value
  end
  return out
end

local function tableSet(values)
  if values == "all" then
    return "all"
  end
  local set = {}
  if type(values) == "table" then
    for _, value in ipairs(values) do
      if type(value) == "string" and value ~= "" then
        set[value] = true
      end
    end
  end
  return set
end

local function normalizeDomains(values)
  if values == nil or values == "all" then
    return "all"
  end
  local out = {}
  if type(values) == "table" then
    for _, value in ipairs(values) do
      if type(value) == "string" and value ~= "" and VALID_DOMAINS[value] then
        out[#out + 1] = value
      end
    end
  end
  if #out == 0 then
    return "all"
  end
  return out
end

local function normalizeExcludeDomains(values)
  if values == nil then
    return {}
  end
  if values == "all" then
    return "all"
  end
  local out = {}
  if type(values) == "table" then
    for _, value in ipairs(values) do
      if type(value) == "string" and value ~= "" and VALID_DOMAINS[value] then
        out[#out + 1] = value
      end
    end
  end
  return out
end

local function normalizeLevel(value)
  return LEVELS[value] and value or DEFAULT_LEVEL
end

local function normalizeCaptureMode(value)
  return VALID_CAPTURE_MODES[value] and value or DEFAULT_CAPTURE_MODE
end

local function normalizePositiveInteger(value, defaultValue)
  local number = tonumber(value)
  if not number or number <= 0 then
    return defaultValue
  end
  return math.floor(number)
end

local function normalizeTtlSeconds(value)
  if value == nil then
    return DEFAULT_TTL_SECONDS
  end
  local number = tonumber(value)
  if not number or number <= 0 then
    return nil, "ttlSeconds must be greater than 0"
  end
  return math.floor(number)
end

local function normalizeFilters(filters)
  local source = type(filters) == "table" and filters or {}
  local normalized = {}
  if type(source.events) == "table" then
    normalized.events = tableSet(source.events)
  elseif type(source.event) == "string" then
    normalized.events = {
      [source.event] = true,
    }
  end
  for _, key in ipairs({ "slot", "windowId", "appName", "bundleId", "bundleID", "profileId", "decision", "result" }) do
    if source[key] ~= nil then
      normalized[key] = source[key]
    end
  end
  return normalized
end

local function normalizeOptions(opts, mode)
  local source = type(opts) == "table" and opts or {}
  local ttlSeconds, ttlErr = normalizeTtlSeconds(source.ttlSeconds)
  if ttlErr then
    return nil, ttlErr
  end

  return {
    mode = mode or source.mode or "current_process",
    domains = normalizeDomains(source.domains),
    excludeDomains = normalizeExcludeDomains(source.excludeDomains),
    level = normalizeLevel(source.level),
    captureMode = normalizeCaptureMode(source.captureMode),
    ttlSeconds = ttlSeconds,
    maxRecords = normalizePositiveInteger(source.maxRecords, DEFAULT_MAX_RECORDS),
    maxBytes = normalizePositiveInteger(source.maxBytes, DEFAULT_MAX_BYTES),
    keepLatestLogs = normalizePositiveInteger(source.keepLatestLogs or source.keepLatest, DEFAULT_KEEP_LATEST_LOGS),
    filters = normalizeFilters(source.filters),
  }
end

local function epochSeconds()
  if hs and hs.timer and type(hs.timer.secondsSinceEpoch) == "function" then
    local ok, seconds = pcall(hs.timer.secondsSinceEpoch)
    if ok and type(seconds) == "number" then
      return seconds
    end
  end
  return os.time()
end

local function isoTime(seconds)
  return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(seconds or epochSeconds()))
end

local function monotonicTime()
  if hs and hs.timer and type(hs.timer.absoluteTime) == "function" then
    local ok, nanos = pcall(hs.timer.absoluteTime)
    if ok and type(nanos) == "number" then
      return nanos / 1000000000
    end
  end
  return nil
end

local function sessionTimestamp(seconds)
  return os.date("!%Y%m%d-%H%M%S", math.floor(seconds or epochSeconds()))
end

local function randomSuffix()
  local value = math.random(0, 0xffff)
  return string.format("%04x", value)
end

local function normalizePathKey(key)
  return tostring(key or ""):lower()
end

local function isForbiddenKey(key)
  local normalized = normalizePathKey(key)
  if FORBIDDEN_KEYS[normalized] then
    return true
  end
  return normalized:find("screenshot", 1, true)
    or normalized:find("clipboard", 1, true)
    or normalized:find("selectedtext", 1, true)
    or normalized:find("userdata", 1, true)
end

local function isTitleKey(key)
  return normalizePathKey(key):find("title", 1, true) ~= nil
end

local function isPathOrUrlKey(key)
  local normalized = normalizePathKey(key)
  return normalized:find("path", 1, true) ~= nil
    or normalized:find("url", 1, true) ~= nil
    or normalized == "uri"
end

local function isAppIdentityKey(key)
  local normalized = normalizePathKey(key)
  return normalized == "appname" or normalized == "bundleid" or normalized == "bundleid"
end

local function isStructuralNumberKey(key)
  local normalized = normalizePathKey(key)
  return normalized:find("id$", 1) ~= nil
    or normalized:find("ids$", 1) ~= nil
    or normalized:find("count$", 1) ~= nil
    or normalized:find("time$", 1) ~= nil
    or normalized == "maxrecords"
    or normalized == "maxbytes"
    or normalized == "ttlseconds"
    or normalized == "byteswritten"
    or normalized == "recordswritten"
    or normalized == "slot"
    or normalized == "slotindex"
    or normalized == "profile"
    or normalized == "index"
    or normalized == "seq"
end

local function isStructuralKey(key, value)
  local valueType = type(value)
  if valueType == "boolean" then
    return true
  end
  if valueType == "number" then
    return isStructuralNumberKey(key)
  end
  if valueType == "string" then
    return STRUCTURAL_STRING_KEYS[key] == true
  end
  return valueType == "table"
end

function DebugLogger.new(opts)
  local debugDir = (opts and opts.debugDir) or Paths.debugDir()
  local self = setmetatable({
    debugDir = debugDir,
    launchArmPath = (opts and opts.launchArmPath) or (debugDir .. "/launch-arm.json"),
    active = nil,
    stopReason = nil,
    lastError = nil,
    titlePlaceholders = {},
    titlePlaceholderCountByApp = {},
  }, DebugLogger)
  return self
end

function DebugLogger:_titlePlaceholder(appName, bundleId, title)
  local rawTitle = trim(title)
  if not rawTitle then
    return nil
  end

  local appLabel = trim(appName) or trim(bundleId) or "App"
  local key = tostring(trim(bundleId) or appLabel) .. "\0" .. rawTitle
  local existing = self.titlePlaceholders[key]
  if existing then
    return existing
  end

  self.titlePlaceholderCountByApp[appLabel] = (self.titlePlaceholderCountByApp[appLabel] or 0) + 1
  local placeholder = string.format("[%s title:%03d]", appLabel, self.titlePlaceholderCountByApp[appLabel])
  self.titlePlaceholders[key] = placeholder
  return placeholder
end

function DebugLogger:_sanitizeValue(value, captureMode, context, key, depth)
  if isForbiddenKey(key) then
    return nil
  end
  if depth > 6 then
    return nil
  end

  local valueType = type(value)
  if valueType == "nil" then
    return nil
  end
  if valueType == "boolean" or valueType == "number" then
    if captureMode == "structural" and not isStructuralKey(key, value) then
      return nil
    end
    return value
  end
  if valueType == "string" then
    if captureMode == "structural" then
      if isStructuralKey(key, value) then
        return value
      end
      return nil
    end
    if isTitleKey(key) then
      if captureMode == "unredacted" then
        return value
      end
      return self:_titlePlaceholder(context.appName, context.bundleId, value)
    end
    if isPathOrUrlKey(key) then
      if captureMode == "unredacted" then
        return value
      end
      return "[redacted]"
    end
    return value
  end
  if valueType ~= "table" then
    return nil
  end

  local childContext = {
    appName = context.appName,
    bundleId = context.bundleId,
  }
  if type(value.appName) == "string" then
    childContext.appName = value.appName
  end
  if type(value.bundleId) == "string" then
    childContext.bundleId = value.bundleId
  elseif type(value.bundleID) == "string" then
    childContext.bundleId = value.bundleID
  end

  local out = {}
  local count = 0
  if isArray(value) then
    for index = 1, math.min(#value, 50) do
      local sanitized = self:_sanitizeValue(value[index], captureMode, childContext, key, depth + 1)
      if sanitized ~= nil then
        out[#out + 1] = sanitized
      end
    end
    return out
  end

  for _, childKey in ipairs(sortedKeys(value)) do
    local childValue = value[childKey]
    if not (captureMode == "structural" and isAppIdentityKey(childKey)) then
      local sanitized = self:_sanitizeValue(childValue, captureMode, childContext, childKey, depth + 1)
      if sanitized ~= nil then
        out[childKey] = sanitized
        count = count + 1
        if count >= 80 then
          break
        end
      end
    end
  end
  if count == 0 and not isArray(value) then
    return nil
  end
  return out
end

function DebugLogger:_sanitizeData(data)
  if not self.active then
    return {}
  end
  local sanitized = self:_sanitizeValue(data or {}, self.active.captureMode, {}, "data", 0)
  return type(sanitized) == "table" and sanitized or {}
end

local function domainIsEnabled(active, domain)
  if not active then
    return false
  end
  if active.excludeDomainSet and active.excludeDomainSet[domain] then
    return false
  end
  if active.domainSet == "all" then
    return true
  end
  return active.domainSet and active.domainSet[domain] == true
end

local function fieldValue(fields, key)
  if type(fields) ~= "table" then
    return nil
  end
  if fields[key] ~= nil then
    return fields[key]
  end
  if key == "bundleId" and fields.bundleID ~= nil then
    return fields.bundleID
  end
  if key == "windowId" then
    if type(fields.window) == "table" and fields.window.windowId ~= nil then
      return fields.window.windowId
    end
    return fields.candidateWindowId
  end
  if key == "appName" and type(fields.window) == "table" then
    return fields.window.appName
  end
  if key == "bundleId" and type(fields.window) == "table" then
    return fields.window.bundleId or fields.window.bundleID
  end
  return nil
end

local function filterMatchesValue(expected, actual, allowMissing)
  if expected == nil then
    return true
  end
  if actual == nil then
    return allowMissing == true
  end
  if type(expected) == "table" then
    for _, value in ipairs(expected) do
      if tostring(value) == tostring(actual) then
        return true
      end
    end
    for key, value in pairs(expected) do
      if value == true and tostring(key) == tostring(actual) then
        return true
      end
      if type(key) ~= "number" and tostring(value) == tostring(actual) then
        return true
      end
    end
    return false
  end
  return tostring(expected) == tostring(actual)
end

function DebugLogger:_filtersMatch(event, fields, opts)
  local filters = self.active and self.active.filters or {}
  if filters.events and event and not filters.events[event] then
    return false
  end
  local allowMissing = type(opts) == "table" and opts.allowMissing == true
  for _, key in ipairs({ "slot", "windowId", "appName", "bundleId", "profileId", "decision", "result" }) do
    if filters[key] ~= nil and not filterMatchesValue(filters[key], fieldValue(fields, key), allowMissing) then
      return false
    end
  end
  return true
end

function DebugLogger:enabled(domain, level, event, fields)
  local active = self.active
  if not active then
    return false
  end
  if active.expiresAtEpoch and epochSeconds() >= active.expiresAtEpoch then
    self:stop("ttl_expired")
    return false
  end
  if not domainIsEnabled(active, domain) then
    return false
  end
  if (LEVELS[level] or LEVELS.info) > active.levelValue then
    return false
  end
  return self:_filtersMatch(event, fields, { allowMissing = true })
end

function DebugLogger:_recordObject(domain, level, event, message, data)
  local active = self.active
  local now = epochSeconds()
  active.seq = active.seq + 1
  return {
    sessionId = active.sessionId,
    seq = active.seq,
    time = isoTime(now),
    monotonicTime = monotonicTime(),
    level = level,
    domain = domain,
    event = event,
    message = message,
    captureMode = active.captureMode,
    data = self:_sanitizeData(data),
  }
end

function DebugLogger:_appendEncoded(encoded)
  local active = self.active
  if not active then
    return false, "not_enabled"
  end

  local line = tostring(encoded or "") .. "\n"
  local handle, err = io.open(active.path, "a")
  if not handle then
    return false, err or "open_failed"
  end
  handle:write(line)
  handle:close()
  active.recordsWritten = active.recordsWritten + 1
  active.bytesWritten = active.bytesWritten + #line
  return true
end

function DebugLogger:_writeRecord(record, allowReserve)
  local active = self.active
  if not active then
    return false, "not_enabled"
  end

  if active.recordsWritten >= active.maxRecords then
    self:stop("max_records")
    return false, "max_records"
  end

  local encoded = encodeJson(record)
  if not encoded then
    return false, "encode_failed"
  end
  local reserve = allowReserve and 0 or STOP_RECORD_RESERVE_BYTES
  if active.bytesWritten + #encoded + 1 + reserve > active.maxBytes then
    self:stop("max_bytes")
    return false, "max_bytes"
  end

  local ok, err = self:_appendEncoded(encoded)
  if not ok then
    self.lastError = err
    self:stop("write_failed")
  end
  return ok, err
end

function DebugLogger:record(domain, level, event, message, payloadOrFn, filterFields)
  if type(message) ~= "string" then
    filterFields = payloadOrFn
    payloadOrFn = message
    message = event
  end
  if not self:enabled(domain, level, event, filterFields) then
    return false
  end

  local data = payloadOrFn
  if type(payloadOrFn) == "function" then
    local ok, result = pcall(payloadOrFn)
    if not ok then
      data = {
        error = "payload_failed",
        reason = tostring(result),
      }
    else
      data = result
    end
  end
  if type(data) ~= "table" then
    data = {}
  end
  if not self:_filtersMatch(event, data) then
    return false
  end
  return self:_writeRecord(self:_recordObject(domain, level, event, message, data))
end

function DebugLogger:cleanupLogs(opts)
  local keepLatest = normalizePositiveInteger(type(opts) == "table" and opts.keepLatest or nil, DEFAULT_KEEP_LATEST_LOGS)
  local removed = {}
  ensureDir(self.debugDir)

  local files = {}
  local command = "ls -1 " .. shellQuote(self.debugDir) .. " 2>/dev/null"
  local pipe = io.popen(command, "r")
  if pipe then
    for name in pipe:lines() do
      if name:match("^debug%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-.+%.jsonl$") then
        files[#files + 1] = name
      end
    end
    pipe:close()
  end
  table.sort(files, function(left, right)
    return left > right
  end)
  for index = keepLatest + 1, #files do
    local path = self.debugDir .. "/" .. files[index]
    if os.remove(path) then
      removed[#removed + 1] = path
    end
  end

  os.remove(self.launchArmPath .. ".tmp")
  local arm = self:pendingLaunchArm()
  if arm and (arm.invalid or arm.expired) then
    if os.remove(self.launchArmPath) then
      removed[#removed + 1] = self.launchArmPath
    end
  end

  return {
    ok = true,
    removed = removed,
    keepLatest = keepLatest,
  }
end

function DebugLogger:_sessionStatus(extra)
  local active = self.active
  local status = {
    ok = true,
    enabled = active ~= nil,
    stopReason = self.stopReason,
    lastError = self.lastError,
    pendingLaunchArm = self:pendingLaunchArm(),
  }
  if active then
    status.mode = active.mode
    status.sessionId = active.sessionId
    status.path = active.path
    status.domains = active.domains
    status.excludeDomains = active.excludeDomains
    status.level = active.level
    status.captureMode = active.captureMode
    status.recordsWritten = active.recordsWritten
    status.bytesWritten = active.bytesWritten
    status.maxRecords = active.maxRecords
    status.maxBytes = active.maxBytes
    status.ttlSeconds = active.ttlSeconds
  end
  for key, value in pairs(extra or {}) do
    status[key] = value
  end
  return status
end

function DebugLogger:loggingStatus()
  if self.active and self.active.expiresAtEpoch and epochSeconds() >= self.active.expiresAtEpoch then
    self:stop("ttl_expired")
  end
  return self:_sessionStatus()
end

function DebugLogger:stop(reason)
  local active = self.active
  if not active then
    self.stopReason = reason or self.stopReason
    return self:_sessionStatus({ ok = true })
  end

  if active.ttlTimer and active.ttlTimer.stop then
    active.ttlTimer:stop()
  end

  local stopRecord = self:_recordObject("logger", "info", "logger_stopped", "debug logging stopped", {
    reason = reason or "disabled",
  })
  local encoded = encodeJson(stopRecord)
  if encoded and active.bytesWritten + #encoded + 1 <= active.maxBytes then
    self:_appendEncoded(encoded)
  end

  self.stopReason = reason or "disabled"
  self.active = nil
  return self:_sessionStatus({ ok = true, stopReason = self.stopReason })
end

function DebugLogger:disableLogging()
  return self:stop("disabled")
end

function DebugLogger:_startTtlTimer()
  local active = self.active
  if not active or not active.ttlSeconds then
    return
  end
  if hs and hs.timer and type(hs.timer.doAfter) == "function" then
    active.ttlTimer = hs.timer.doAfter(active.ttlSeconds, function()
      if self.active == active then
        self:stop("ttl_expired")
      end
    end)
  end
end

function DebugLogger:enableLogging(opts)
  local source = type(opts) == "table" and opts or {}
  local options, err = normalizeOptions(source, source.mode or "current_process")
  if not options then
    return {
      ok = false,
      error = err,
    }
  end

  if self.active then
    if source.replace == true then
      self:stop("replaced")
    else
      return self:_sessionStatus({
        ok = false,
        error = "already_enabled",
      })
    end
  end

  self:cleanupLogs({ keepLatest = options.keepLatestLogs })
  ensureDir(self.debugDir)

  local now = epochSeconds()
  local sessionId = sessionTimestamp(now) .. "-" .. randomSuffix()
  local path = self.debugDir .. "/debug-" .. tostring(sessionId) .. ".jsonl"
  local handle, openErr = io.open(path, "a")
  if not handle then
    self.lastError = openErr
    return {
      ok = false,
      error = "open_failed",
      detail = openErr,
      path = path,
    }
  end
  handle:close()

  self.titlePlaceholders = {}
  self.titlePlaceholderCountByApp = {}
  self.stopReason = nil
  self.lastError = nil
  self.active = {
    mode = options.mode,
    sessionId = sessionId,
    path = path,
    domains = options.domains,
    domainSet = tableSet(options.domains),
    excludeDomains = options.excludeDomains == "all" and {} or options.excludeDomains,
    excludeDomainSet = tableSet(options.excludeDomains == "all" and {} or options.excludeDomains),
    level = options.level,
    levelValue = LEVELS[options.level],
    captureMode = options.captureMode,
    ttlSeconds = options.ttlSeconds,
    expiresAtEpoch = now + options.ttlSeconds,
    maxRecords = options.maxRecords,
    maxBytes = options.maxBytes,
    keepLatestLogs = options.keepLatestLogs,
    filters = options.filters,
    seq = 0,
    recordsWritten = 0,
    bytesWritten = 0,
  }
  self:_startTtlTimer()

  self:_writeRecord(self:_recordObject("logger", "info", "session_started", "debug logging started", {
    schemaVersion = SCHEMA_VERSION,
    mode = options.mode,
    domains = options.domains,
    excludeDomains = self.active.excludeDomains,
    level = options.level,
    captureMode = options.captureMode,
    ttlSeconds = options.ttlSeconds,
    maxRecords = options.maxRecords,
    maxBytes = options.maxBytes,
  }), true)

  return self:_sessionStatus({ ok = true })
end

function DebugLogger:enableLoggingOnLaunch(opts)
  local options, err = normalizeOptions(opts, "launch")
  if not options then
    return {
      ok = false,
      error = err,
    }
  end
  ensureDir(self.debugDir)
  self:cleanupLogs({ keepLatest = options.keepLatestLogs })

  local now = epochSeconds()
  local payload = {
    schemaVersion = SCHEMA_VERSION,
    mode = "launch",
    createdAt = isoTime(now),
    expiresAt = isoTime(now + options.ttlSeconds),
    expiresAtEpoch = now + options.ttlSeconds,
    domains = options.domains,
    excludeDomains = options.excludeDomains == "all" and {} or options.excludeDomains,
    level = options.level,
    captureMode = options.captureMode,
    ttlSeconds = options.ttlSeconds,
    maxRecords = options.maxRecords,
    maxBytes = options.maxBytes,
    keepLatestLogs = options.keepLatestLogs,
    filters = options.filters,
  }
  local ok, writeErr = JsonDisk.write(self.launchArmPath, payload)
  if not ok then
    return {
      ok = false,
      error = "write_failed",
      detail = writeErr,
      path = self.launchArmPath,
    }
  end
  return {
    ok = true,
    path = self.launchArmPath,
    pendingLaunchArm = payload,
  }
end

function DebugLogger:cancelLoggingOnLaunch()
  os.remove(self.launchArmPath .. ".tmp")
  local removed = os.remove(self.launchArmPath) == true
  return {
    ok = true,
    removed = removed,
    path = self.launchArmPath,
  }
end

function DebugLogger:pendingLaunchArm()
  if not fileExists(self.launchArmPath) then
    return nil
  end
  local payload, meta = JsonDisk.read(self.launchArmPath)
  if not payload or (meta and meta.invalid) then
    return {
      path = self.launchArmPath,
      invalid = true,
    }
  end
  local expiresAtEpoch = tonumber(payload.expiresAtEpoch)
  if expiresAtEpoch and epochSeconds() >= expiresAtEpoch then
    return {
      path = self.launchArmPath,
      expired = true,
      expiresAt = payload.expiresAt,
    }
  end
  payload.path = self.launchArmPath
  return payload
end

function DebugLogger:consumeLaunchArm()
  local pending = self:pendingLaunchArm()
  if not pending then
    return {
      ok = true,
      consumed = false,
    }
  end
  os.remove(self.launchArmPath)
  if pending.invalid then
    return {
      ok = false,
      consumed = false,
      error = "launch_arm_invalid",
    }
  end
  if pending.expired then
    return {
      ok = false,
      consumed = false,
      error = "launch_arm_expired",
    }
  end
  pending.mode = "launch"
  local status = self:enableLogging(pending)
  status.consumed = status.ok == true
  return status
end

function DebugLogger:commands()
  return {
    enableLogging = function(opts)
      return self:enableLogging(opts)
    end,
    enableLoggingOnLaunch = function(opts)
      return self:enableLoggingOnLaunch(opts)
    end,
    disableLogging = function()
      return self:disableLogging()
    end,
    loggingStatus = function()
      return self:loggingStatus()
    end,
    cleanupLogs = function(opts)
      return self:cleanupLogs(opts)
    end,
    cancelLoggingOnLaunch = function()
      return self:cancelLoggingOnLaunch()
    end,
  }
end

function DebugLogger.encodeJson(value)
  return encodeJson(value)
end

function DebugLogger.readLines(path)
  local contents = readAll(path)
  if not contents then
    return {}
  end
  local lines = {}
  for line in contents:gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  return lines
end

return DebugLogger
