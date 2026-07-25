local Assert = require("assert")
local TempDir = require("temp_dir")
local TestEnv = require("test_env")

local function clearModules()
  for _, name in ipairs({
    "persistence.appdata_store",
    "persistence.settings_store",
    "persistence.paths",
    "persistence.json_disk",
    "persistence.normalize",
    "state.slot_record",
    "utils",
  }) do
    package.loaded[name] = nil
  end
end

local function makeAppData()
  clearModules()
  return require("persistence.appdata_store")
end

local function makeSettings()
  clearModules()
  return require("persistence.settings_store")
end

local function assertDeepEq(actual, expected, message)
  if type(actual) ~= type(expected) then
    error(message or "expected values to share the same type")
  end
  if type(actual) ~= "table" then
    Assert.equal(actual, expected, message)
    return
  end

  for key, value in pairs(expected) do
    assertDeepEq(actual[key], value, message)
  end
  for key, value in pairs(actual) do
    assertDeepEq(value, expected[key], message)
  end
end

local function installHs(logs)
  _G.hs = {
    printf = function(fmt, ...)
      logs[#logs + 1] = string.format(fmt, ...)
    end,
  }
end

local function readFile(path)
  local handle = assert(io.open(path, "r"))
  local contents = handle:read("*a")
  handle:close()
  return contents
end

local function findFiles(dir, pattern)
  local pipe = assert(io.popen("find '" .. dir:gsub("'", "'\\''") .. "' -maxdepth 1 -name '" .. pattern:gsub("'", "'\\''") .. "' -print"))
  local results = {}
  for line in pipe:lines() do
    results[#results + 1] = line
  end
  pipe:close()
  return results
end

return {
  name = "SettingsStore",
  cases = {
    {
      name = "bootstraps settings and appdata on disk, sanitizes overrides, and recovers corruption",
      run = function()
        TempDir.with("settings-store-disk", function(dir)
          local logs = {}
          rawset(_G, "__tapshop_test_data_dir", dir)
          clearModules()
          installHs(logs)

          local Settings = require("persistence.settings_store")
          local AppData = require("persistence.appdata_store")
          local Paths = require("persistence.paths")
          local JsonDisk = require("persistence.json_disk")

          Settings.bootstrap()
          AppData.bootstrap()

          Assert.equal(Settings.getPopoverAutoHideAfterAction(), false)
          Assert.equal(Settings.getPopoverAlwaysOnTop(), true)
          Assert.equal(Settings.getPopoverHidePairButtons(), false)
          Assert.equal(Settings.getRecoverClosedWindows(), true)
          Assert.equal(Settings.getPopoverBackgroundOpacity(), 0.9)

          local settingsDoc = assert(JsonDisk.read(Paths.settings()))
          Assert.equal(settingsDoc.schemaVersion, 1)
          Assert.equal(settingsDoc.workspace.recoverClosedWindows, true)
          Assert.equal(next(settingsDoc.hotkeys.overrides), nil)

          local appdataDoc = assert(JsonDisk.read(Paths.appdata()))
          Assert.equal(appdataDoc.schemaVersion, 2)
          Assert.equal(appdataDoc.workspace.activeProfileId, 1)
          Assert.equal(next(appdataDoc.workspace.profiles), nil)
          Assert.equal(appdataDoc.windows.popover.topLeft, nil)
          Assert.equal(appdataDoc.windows.settings.size, nil)

          Settings.setHotkeyOverrides({
            ["youtube.playPause.k"] = {
              mods = { "shift", "cmd", "cmd", "invalid", "alt" },
              key = "K",
              enabled = false,
            },
            ["youtube.seekForward.l"] = {
              mods = {},
              key = false,
            },
            bad = {
              mods = "nope",
              key = "",
            },
          })

          local overrides = Settings.getHotkeyOverrides()
          Assert.equal(table.concat(overrides["youtube.playPause.k"].mods, ","), "cmd,alt,shift")
          Assert.equal(overrides["youtube.playPause.k"].key, "k")
          Assert.equal(overrides["youtube.playPause.k"].enabled, false)
          Assert.equal(overrides["youtube.seekForward.l"].key, false)
          Assert.equal(overrides.bad, nil)

          AppData.setActiveProfileId(2)
          AppData.setWindowPairings({
            [2] = {
              version = 2,
              kind = "recoverable",
              fingerprint = {
                bundleID = "com.apple.Notes",
                appName = "Notes",
                titleRaw = "Notes",
                titleNormalized = "notes",
              },
            },
          })
          AppData.setProfileWindowPairings(1, {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 101,
              baseSpaceId = 4,
              fingerprint = {
                bundleID = "com.apple.Safari",
                appName = "Safari",
                titleRaw = "Docs",
                titleNormalized = "docs",
              },
            },
          })
          AppData.setPopoverTopLeft({ x = 110.8, y = 220.2 })
          AppData.setPopoverSize({ w = 640.9, h = 360.1 })
          AppData.setSettingsWindowTopLeft({ x = 330, y = 440 })
          AppData.setSettingsWindowSize({ w = 600, h = 420 })
          Settings.setPopoverBackgroundOpacity(0.93)

          local updatedSettings = assert(JsonDisk.read(Paths.settings()))
          Assert.equal(updatedSettings.popover.backgroundOpacity, 0.9)

          local updatedAppdata = assert(JsonDisk.read(Paths.appdata()))
          Assert.equal(updatedAppdata.workspace.activeProfileId, 2)
          Assert.equal(updatedAppdata.workspace.profiles["1"].pairings["1"].baseWindowId, 101)
          Assert.equal(updatedAppdata.workspace.profiles["2"].pairings["2"].kind, "recoverable")
          assertDeepEq(updatedAppdata.windows.popover.topLeft, { x = 110, y = 220 })
          assertDeepEq(updatedAppdata.windows.popover.size, { w = 640, h = 360 })

          Assert.equal(AppData.getActiveProfileId(), 2)
          Assert.equal(AppData.getWindowPairings()[2].kind, "recoverable")
          Assert.equal(AppData.getProfileWindowPairings(1)[1].baseWindowId, 101)

          Settings.resetHotkeyOverrides()
          Assert.equal(next(Settings.getHotkeyOverrides()), nil)

          clearModules()
          installHs(logs)
          assert(JsonDisk.write(Paths.appdata(), {
            schemaVersion = 1,
            windows = {
              popover = {
                size = {
                  w = 512,
                  h = 288,
                },
              },
            },
            workspace = {
              pairings = {
                ["1"] = {
                  version = 2,
                  kind = "paired",
                  baseWindowId = 303,
                  fingerprint = {
                    bundleID = "com.apple.Terminal",
                    titleNormalized = "shell",
                  },
                },
              },
            },
          }))
          assert(JsonDisk.write(Paths.settings(), {
            schemaVersion = 1,
            popover = {
              autoHideAfterAction = true,
            },
          }))

          local SettingsAgain = require("persistence.settings_store")
          local AppDataAgain = require("persistence.appdata_store")
          Assert.equal(SettingsAgain.getPopoverAlwaysOnTop(), true)
          Assert.equal(AppDataAgain.getActiveProfileId(), 1)
          local rewrittenSettings = assert(JsonDisk.read(Paths.settings()))
          Assert.equal(rewrittenSettings.workspace.recoverClosedWindows, true)
          local rewrittenAppdata = assert(JsonDisk.read(Paths.appdata()))
          assertDeepEq(rewrittenAppdata.windows.popover.size, { w = 512, h = 288 })
          Assert.equal(rewrittenAppdata.workspace.activeProfileId, 1)
          Assert.equal(rewrittenAppdata.workspace.profiles["1"].pairings["1"].baseWindowId, 303)
          Assert.equal(AppDataAgain.getProfileWindowPairings(1)[1].baseWindowId, 303)

          clearModules()
          installHs(logs)
          local brokenHandle = assert(io.open(Paths.settings(), "w"))
          brokenHandle:write("{ broken json")
          brokenHandle:close()

          local SettingsAfterCorruption = require("persistence.settings_store")
          Assert.equal(SettingsAfterCorruption.getPopoverAutoHideAfterAction(), false)
          local recoveredSettings = readFile(Paths.settings())
          Assert.truthy(string.find(recoveredSettings, "\"schemaVersion\": 1", 1, true) ~= nil)
          local backups = findFiles(dir, "settings.corrupt-*.json")
          Assert.truthy(#backups >= 1)
          Assert.truthy(#logs >= 1)
        end)
      end,
    },
    {
      name = "ignores malformed persisted window pairings from appdata json",
      run = function()
        TempDir.with("settings-store-spec", function(dir)
          TestEnv.reset({
            "persistence.appdata_store",
            "persistence.paths",
            "persistence.json_disk",
            "persistence.normalize",
            "state.slot_record",
            "utils",
          })
          rawset(_G, "__tapshop_test_data_dir", dir)

          local JsonDisk = require("persistence.json_disk")
          local AppDataStore = require("persistence.appdata_store")
          local appdata = makeAppData()

          JsonDisk.write(AppDataStore.path(), {
            schemaVersion = 1,
            workspace = {
              pairings = {
                ["1"] = {
                  version = 2,
                  kind = "paired",
                  baseWindowId = 101,
                  baseSpaceId = 3,
                  fullscreenTarget = {
                    windowId = 202,
                    spaceId = 9,
                  },
                  fingerprint = {
                    bundleID = "com.apple.Safari",
                    titleNormalized = "docs - youtube",
                  },
                },
                ["2"] = {
                  version = 2,
                  kind = "paired",
                  baseWindowId = 0,
                },
                ["3"] = {
                  version = 2,
                  kind = "recoverable",
                  fingerprint = {
                    bundleID = "com.apple.Notes",
                  },
                },
                ["4"] = "404",
                ["10"] = {
                  version = 2,
                  kind = "paired",
                  baseWindowId = 1000,
                },
                bad = {
                  version = 2,
                  kind = "paired",
                  baseWindowId = 505,
                },
              },
            },
          })

          local result = appdata.getWindowPairings()

          Assert.equal(result[1].kind, "paired")
          Assert.equal(result[1].baseWindowId, 101)
          Assert.equal(result[1].baseSpaceId, 3)
          Assert.equal(result[1].fullscreenTarget.windowId, 202)
          Assert.equal(result[1].fingerprint.bundleID, "com.apple.Safari")
          Assert.equal(result[2], nil)
          Assert.equal(result[3], nil)
          Assert.equal(result[4], nil)
          Assert.equal(result[10], nil)
        end)
      end,
    },
    {
      name = "serializes valid v2 pairing records into appdata json with string slot keys",
      run = function()
        TempDir.with("settings-store-spec", function(dir)
          TestEnv.reset({
            "persistence.appdata_store",
            "persistence.paths",
            "persistence.json_disk",
            "persistence.normalize",
            "state.slot_record",
            "utils",
          })
          rawset(_G, "__tapshop_test_data_dir", dir)

          local JsonDisk = require("persistence.json_disk")
          local AppDataStore = require("persistence.appdata_store")
          local appdata = makeAppData()

          appdata.setWindowPairings({
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 111,
              baseSpaceId = 1,
              fullscreenTarget = {
                windowId = 222,
                spaceId = 8,
              },
              fingerprint = {
                bundleID = "com.apple.Safari",
                appName = "Safari",
                titleRaw = "Docs",
                titleNormalized = "docs",
              },
            },
            [3] = {
              version = 2,
              kind = "recoverable",
              fingerprint = {
                bundleID = "com.apple.Notes",
                appName = "Notes",
                titleRaw = "Notes",
                titleNormalized = "notes",
              },
            },
            [10] = {
              version = 2,
              kind = "paired",
              baseWindowId = 1010,
            },
            bad = {
              version = 2,
              kind = "paired",
              baseWindowId = 444,
            },
          })

          local persisted = assert(JsonDisk.read(AppDataStore.path()))
          local pairings = persisted.workspace.profiles["1"].pairings

          Assert.equal(pairings["1"].version, 2)
          Assert.equal(pairings["1"].kind, "paired")
          Assert.equal(pairings["1"].baseWindowId, 111)
          Assert.equal(pairings["1"].baseSpaceId, 1)
          Assert.equal(pairings["1"].fullscreenTarget.windowId, 222)
          Assert.equal(pairings["1"].fingerprint.bundleID, "com.apple.Safari")
          Assert.equal(pairings["3"].version, 2)
          Assert.equal(pairings["3"].kind, "recoverable")
          Assert.equal(pairings["3"].fingerprint.bundleID, "com.apple.Notes")
          Assert.equal(pairings["10"], nil)
        end)
      end,
    },
  },
}
