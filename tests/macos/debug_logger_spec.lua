local Assert = require("assert")
local FakeHs = require("fake_hs")
local TempDir = require("temp_dir")
local TestEnv = require("test_env")

local function clearModules()
  for _, name in ipairs({
    "services.debug_logger",
    "persistence.paths",
    "persistence.json_disk",
  }) do
    package.loaded[name] = nil
  end
end

local function makeLogger(dir)
  clearModules()
  TestEnv.reset({
    "services.debug_logger",
    "persistence.paths",
    "persistence.json_disk",
  })
  rawset(_G, "__tapshop_test_data_dir", dir)
  local DebugLogger = require("services.debug_logger")
  return DebugLogger.new(), DebugLogger
end

local function contains(source, needle)
  return tostring(source or ""):find(needle, 1, true) ~= nil
end

return {
  name = "DebugLogger",
  cases = {
    {
      name = "disabled logger does not evaluate payload callbacks",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger = makeLogger(dir)
          local evaluated = false

          Assert.falsy(logger:enabled("focus", "debug", "slot_activation_requested"))
          logger:record("focus", "debug", "slot_activation_requested", "slot activation requested", function()
            evaluated = true
            return {}
          end)

          Assert.falsy(evaluated)
          Assert.falsy(logger:loggingStatus().enabled)
        end)
      end,
    },
    {
      name = "enabled logger writes JSONL and redacts window titles",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger, DebugLogger = makeLogger(dir)

          local status = logger:enableLogging({
            domains = { "focus" },
            level = "debug",
            captureMode = "redacted",
            ttlSeconds = 3600,
          })
          Assert.truthy(status.ok)
          Assert.truthy(status.enabled)
          Assert.truthy(status.path)

          logger:record("focus", "debug", "slot_activation_decision", "using exact live window", function()
            return {
              slot = 1,
              decision = "exact_live_window",
              window = {
                windowId = 64,
                appName = "Safari",
                bundleID = "com.apple.Safari",
                windowTitle = "Safari - GitHub - example/tapshop",
              },
            }
          end, {
            slot = 1,
            windowId = 64,
            decision = "exact_live_window",
          })

          local lines = DebugLogger.readLines(status.path)
          Assert.equal(#lines, 2)
          Assert.truthy(contains(lines[1], "\"event\":\"session_started\""))
          Assert.truthy(contains(lines[2], "\"captureMode\":\"redacted\""))
          Assert.truthy(contains(lines[2], "\"windowTitle\":\"[Safari title:001]\""))
          Assert.falsy(contains(lines[2], "GitHub - example/tapshop"))
        end)
      end,
    },
    {
      name = "structural capture mode omits app identity and titles",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger, DebugLogger = makeLogger(dir)
          local status = logger:enableLogging({
            domains = { "window" },
            captureMode = "structural",
          })

          logger:record("window", "debug", "window_seen", "window seen", {
            window = {
              windowId = 9,
              appName = "Safari",
              bundleID = "com.apple.Safari",
              windowTitle = "Private Title",
              isVisible = true,
            },
          }, {
            windowId = 9,
          })

          local lines = DebugLogger.readLines(status.path)
          Assert.truthy(contains(lines[2], "\"windowId\":9"))
          Assert.truthy(contains(lines[2], "\"isVisible\":true"))
          Assert.falsy(contains(lines[2], "Safari"))
          Assert.falsy(contains(lines[2], "Private Title"))
        end)
      end,
    },
    {
      name = "app filters are applied after lazy payload construction",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger, DebugLogger = makeLogger(dir)
          local status = logger:enableLogging({
            domains = { "window" },
            filters = {
              appName = "Safari",
              bundleID = "com.apple.Safari",
            },
          })
          local evaluated = false

          logger:record("window", "debug", "window_seen", "window seen", function()
            evaluated = true
            return {
              window = {
                windowId = 9,
                appName = "Mail",
                bundleID = "com.apple.mail",
                windowTitle = "Inbox",
              },
            }
          end)

          logger:record("window", "debug", "window_seen", "window seen", {
            window = {
              windowId = 10,
              appName = "Safari",
              bundleID = "com.apple.Safari",
              windowTitle = "Docs",
            },
          })

          local lines = DebugLogger.readLines(status.path)
          Assert.truthy(evaluated)
          Assert.equal(#lines, 2)
          Assert.truthy(contains(lines[1], "\"event\":\"session_started\""))
          Assert.truthy(contains(lines[2], "\"windowId\":10"))
        end)
      end,
    },
    {
      name = "bundleID filter uses the canonical macOS key",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger, DebugLogger = makeLogger(dir)
          local status = logger:enableLogging({
            domains = { "window" },
            filters = {
              bundleID = "com.apple.TextEdit",
            },
          })

          logger:record("window", "debug", "window_seen", "window seen", {
            window = {
              windowId = 9,
              bundleID = "com.apple.mail",
            },
          })
          logger:record("window", "debug", "window_seen", "window seen", {
            window = {
              windowId = 10,
              bundleID = "com.apple.TextEdit",
            },
          })

          local lines = DebugLogger.readLines(status.path)
          Assert.equal(#lines, 2)
          Assert.truthy(contains(lines[2], "\"windowId\":10"))
          Assert.falsy(contains(lines[2], "\"windowId\":9"))
          Assert.equal(logger.active.filters.bundleID, "com.apple.TextEdit")
        end)
      end,
    },
    {
      name = "custom debug directories are used for log output",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local _, DebugLogger = makeLogger(dir)
          local customDir = dir .. "/custom-debug"
          local logger = DebugLogger.new({
            debugDir = customDir,
          })

          local status = logger:enableLogging({
            domains = { "logger" },
          })
          local armed = logger:enableLoggingOnLaunch({
            domains = { "startup" },
          })

          Assert.truthy(status.ok)
          Assert.truthy(contains(status.path, customDir))
          Assert.truthy(armed.ok)
          Assert.truthy(contains(armed.path, customDir))
        end)
      end,
    },
    {
      name = "launch arm is written, consumed once, and starts launch logging",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger = makeLogger(dir)

          local armed = logger:enableLoggingOnLaunch({
            domains = { "startup" },
            level = "debug",
          })
          Assert.truthy(armed.ok)
          Assert.truthy(logger:pendingLaunchArm())

          local consumed = logger:consumeLaunchArm()
          Assert.truthy(consumed.ok)
          Assert.truthy(consumed.consumed)
          Assert.truthy(logger:loggingStatus().enabled)
          Assert.equal(logger:loggingStatus().mode, "launch")
          Assert.equal(logger:pendingLaunchArm(), nil)
        end)
      end,
    },
    {
      name = "launch arm preserves event filters across consume",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger, DebugLogger = makeLogger(dir)

          local armed = logger:enableLoggingOnLaunch({
            domains = { "window" },
            filters = {
              events = {
                windowCreated = true,
              },
            },
          })
          Assert.truthy(armed.ok)

          local consumed = logger:consumeLaunchArm()
          Assert.truthy(consumed.ok)
          Assert.truthy(consumed.consumed)

          logger:record("window", "debug", "windowFocused", "window focused", {
            window = {
              windowId = 9,
            },
          })
          logger:record("window", "debug", "windowCreated", "window created", {
            window = {
              windowId = 10,
            },
          })

          local lines = DebugLogger.readLines(consumed.path)
          Assert.equal(#lines, 2)
          Assert.truthy(contains(lines[2], "\"event\":\"windowCreated\""))
          Assert.truthy(contains(lines[2], "\"windowId\":10"))
          Assert.falsy(contains(lines[2], "windowFocused"))
        end)
      end,
    },
    {
      name = "json encoder emits valid JSON tokens for control and non-finite values",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local _, DebugLogger = makeLogger(dir)
          local encoded = DebugLogger.encodeJson({
            control = "a" .. string.char(1) .. "b",
            nan = 0 / 0,
            positiveInfinity = 1 / 0,
            negativeInfinity = -1 / 0,
          })

          Assert.truthy(contains(encoded, "\"control\":\"a\\u0001b\""))
          Assert.truthy(contains(encoded, "\"nan\":null"))
          Assert.truthy(contains(encoded, "\"positiveInfinity\":null"))
          Assert.truthy(contains(encoded, "\"negativeInfinity\":null"))
          Assert.falsy(contains(encoded, ":nan"))
          Assert.falsy(contains(encoded, ":inf"))
          Assert.falsy(contains(encoded, ":-inf"))
        end)
      end,
    },
    {
      name = "cleanup keeps newest debug logs",
      run = function()
        TempDir.with("debug-logger-spec", function(dir)
          local logger = makeLogger(dir)
          local debugDir = dir .. "/debug"
          os.execute("mkdir -p " .. debugDir)

          for index = 1, 7 do
            local path = string.format("%s/debug-20260705-20120%d-a%d.jsonl", debugDir, index, index)
            local handle = assert(io.open(path, "w"))
            handle:write("{}\n")
            handle:close()
          end

          local cleanup = logger:cleanupLogs({ keepLatest = 5 })
          Assert.truthy(cleanup.ok)
          Assert.equal(#cleanup.removed, 2)
        end)
      end,
    },
  },
}
