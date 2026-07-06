local Paths = {}

local function homeDir()
  return os.getenv("HOME") or "~"
end

local function testOverride()
  return rawget(_G, "__tapshop_test_data_dir")
end

function Paths.baseDir()
  return testOverride() or (homeDir() .. "/.hammerspoon/tapshop")
end

function Paths.settings()
  return Paths.baseDir() .. "/settings.json"
end

function Paths.appdata()
  return Paths.baseDir() .. "/appdata.json"
end

function Paths.debugDir()
  return Paths.baseDir() .. "/debug"
end

function Paths.debugLaunchArm()
  return Paths.debugDir() .. "/launch-arm.json"
end

function Paths.debugLog(sessionId)
  return Paths.debugDir() .. "/debug-" .. tostring(sessionId or "session") .. ".jsonl"
end

return Paths
