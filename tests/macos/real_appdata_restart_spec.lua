local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TempDir = require("temp_dir")

local function clearModules()
  for _, name in ipairs({
    "persistence.settings_store",
    "persistence.appdata_store",
    "persistence.paths",
    "persistence.json_disk",
    "persistence.normalize",
    "state.layout",
    "state.workspace",
    "state.slot_record",
    "state.slot_row",
    "state.app_state",
  }) do
    package.loaded[name] = nil
  end
end

local function makeConfig()
  return {
    minimizeThreshold = 2,
    popoverAutoHideAfterAction = false,
    focusWaitTimeout = 0.05,
    focusPollMicros = 1000,
    recoverClosedWindows = true,
  }
end

return {
  name = "RealAppdataRestart",
  cases = {
    {
      name = "restores an already-open matching window after restart without restore toasts",
      run = function()
        TempDir.with("real-appdata-restart", function(dir)
          rawset(_G, "__tapshop_test_data_dir", dir)

          FakeHs.install()
          _G.hs.printf = function() end
          clearModules()

          local Settings = require("persistence.settings_store")
          local AppData = require("persistence.appdata_store")
          local AppState = require("state.app_state")

          local startupToasts = 0
          local originalWindow = FakeHs.makeWindow({
            id = 101,
            title = "Docs",
            bundleId = "com.apple.Safari",
            appName = "Safari",
          })

          Settings.bootstrap()
          AppData.bootstrap()

          local app = AppState.new(makeConfig(), {
            settings = Settings,
            appdata = AppData,
            windowService = Fakes.createWindowService({ originalWindow }),
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            systemAudioService = {},
            toast = function() end,
          })

          app:pairSlot(1, originalWindow)
          Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 101)

          FakeHs.install()
          _G.hs.printf = function() end
          clearModules()

          local reopenedWindow = FakeHs.makeWindow({
            id = 202,
            title = "Docs",
            bundleId = "com.apple.Safari",
            appName = "Safari",
          })

          local SettingsAfterRestart = require("persistence.settings_store")
          local AppDataAfterRestart = require("persistence.appdata_store")
          local AppStateAfterRestart = require("state.app_state")

          SettingsAfterRestart.bootstrap()
          AppDataAfterRestart.bootstrap()

          local restartedApp = AppStateAfterRestart.new(makeConfig(), {
            settings = SettingsAfterRestart,
            appdata = AppDataAfterRestart,
            windowService = Fakes.createWindowService({ reopenedWindow }),
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            systemAudioService = {},
            toast = function()
              startupToasts = startupToasts + 1
            end,
          })

          Assert.equal(restartedApp:getWorkspaces()[1].binding.kind, "paired")
          Assert.equal(restartedApp:getWorkspaces()[1].binding.baseWindowId, 202)
          Assert.equal(startupToasts, 0)
        end)
      end,
    },
  },
}
