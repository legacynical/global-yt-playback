local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TestEnv = require("test_env")

local function makeConfig(overrides)
  local cfg = {
    minimizeThreshold = 2,
    popoverAutoHideAfterAction = false,
    recoverClosedWindows = true,
    focusWaitTimeout = 0.05,
    focusPollMicros = 1000,
    fullscreenSpaceSwitchDelay = 0.20,
    enableFullscreenSpaceTracking = true,
    fullscreenPostSwitchFocusRetries = { 0.02, 0.06, 0.12 },
  }

  for key, value in pairs(overrides or {}) do
    cfg[key] = value
  end

  return cfg
end

local function makeApp(deps)
  deps = deps or {}
  local configOverrides = deps.configOverrides
  deps.configOverrides = nil
  if deps.settingsStore then
    deps.settings = deps.settings or deps.settingsStore
    deps.appdata = deps.appdata or deps.settingsStore
    deps.settingsStore = nil
  end
  deps.settings = deps.settings or Fakes.createSettingsStore()
  deps.appdata = deps.appdata or Fakes.createSettingsStore()

  TestEnv.reset({
    "app_config",
    "settings",
    "appdata",
    "state.workspace",
    "state.slot_record",
    "state.slot_row",
    "state.app_state",
  })
  local AppState = require("state.app_state")
  return AppState.new(makeConfig(configOverrides), deps)
end

local function flushScheduledTimers(limit)
  local maxPasses = limit or 8
  for _ = 1, maxPasses do
    if #FakeHs.state().doAfterCalls == 0 then
      return
    end
    FakeHs.runScheduledTimers()
  end
end

return {
  name = "AppState",
  cases = {
    {
      name = "creates nine workspaces",
      run = function()
        local toast = function() end
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })

        Assert.equal(#app:getWorkspaces(), 9)
        Assert.equal(app:getWorkspaces()[1].name, "Profile 1 / Window 1")
        Assert.equal(app:getWorkspaces()[9].name, "Profile 1 / Window 9")
      end,
    },
    {
      name = "startup does not persist appdata when restored state is unchanged",
      run = function()
        local appdata = Fakes.createSettingsStore()

        makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        for _, call in ipairs(appdata.calls) do
          Assert.falsy(call.kind == "profilesWindowPairings")
          Assert.falsy(call.kind == "activeProfileId")
        end
      end,
    },
    {
      name = "profile activation persists active profile after the interactive path",
      run = function()
        local appdata = Fakes.createSettingsStore()
        local refreshReason = nil
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        app:attachUi({
          requestRefresh = function(_, reason)
            refreshReason = reason
          end,
        }, nil)

        Assert.truthy(app:activateProfile(2))
        Assert.equal(app:getActiveProfileId(), 2)
        Assert.equal(refreshReason, "profile_switch")
        Assert.equal(appdata:getActiveProfileId(), 1)

        for _, call in ipairs(appdata.calls) do
          Assert.falsy(call.kind == "activeProfileId")
        end

        flushScheduledTimers()

        Assert.equal(appdata:getActiveProfileId(), 2)
      end,
    },
    {
      name = "rapid profile activation coalesces persistence to the final profile",
      run = function()
        local appdata = Fakes.createSettingsStore()
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        Assert.truthy(app:activateProfile(2))
        Assert.truthy(app:activateProfile(3))
        Assert.equal(appdata:getActiveProfileId(), 1)

        flushScheduledTimers()

        Assert.equal(appdata:getActiveProfileId(), 3)
        local activeProfileWrites = 0
        for _, call in ipairs(appdata.calls) do
          if call.kind == "activeProfileId" then
            activeProfileWrites = activeProfileWrites + 1
          end
        end
        Assert.equal(activeProfileWrites, 1)
      end,
    },
    {
      name = "pending profile persistence flushes once before the timer fires",
      run = function()
        local appdata = Fakes.createSettingsStore()
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        Assert.truthy(app:activateProfile(2))
        Assert.truthy(app:flushActiveProfilePersistence())
        Assert.falsy(app:flushActiveProfilePersistence())
        Assert.equal(appdata:getActiveProfileId(), 2)

        flushScheduledTimers()

        local activeProfileWrites = 0
        for _, call in ipairs(appdata.calls) do
          if call.kind == "activeProfileId" then
            activeProfileWrites = activeProfileWrites + 1
          end
        end
        Assert.equal(activeProfileWrites, 1)
      end,
    },
    {
      name = "first activation exact-validates only the newly active profile",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 201,
              baseSpaceId = 1,
              fingerprint = {
                bundleID = "com.apple.mail",
                appName = "Mail",
                titleRaw = "Old Inbox",
                titleNormalized = "old inbox",
              },
            },
          },
        }
        local live = FakeHs.makeWindow({
          id = 201,
          title = "Inbox",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({ live })
        local candidateCalls = 0
        local baseCandidateWindows = windowService.candidateWindows
        windowService.candidateWindows = function()
          candidateCalls = candidateCalls + 1
          return baseCandidateWindows()
        end
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        local refreshReasons = {}
        app:attachUi({
          requestRefresh = function(_, reason)
            refreshReasons[#refreshReasons + 1] = reason
          end,
        }, nil)
        candidateCalls = 0
        windowService.getWindowSpacesCalls = {}
        appdata.calls = {}

        Assert.truthy(app:activateProfile(2))
        Assert.equal(#refreshReasons, 1)
        Assert.equal(refreshReasons[1], "profile_switch")
        Assert.equal(#windowService.getWindowSpacesCalls, 0)
        flushScheduledTimers()

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 201)
        Assert.equal(workspace.binding.baseSpaceId, 2)
        Assert.equal(workspace.binding.fingerprint.titleNormalized, "inbox")
        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(candidateCalls, 0)
        -- Shallow profile-switch paint, then a short republish after exact validation
        -- corrects Space/fullscreen advisory fields.
        Assert.equal(#refreshReasons, 2)
        Assert.equal(refreshReasons[2], "profile_switch")

        Assert.truthy(app:activateProfile(1))
        flushScheduledTimers()
        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()
        Assert.equal(#windowService.getWindowSpacesCalls, 1)
      end,
    },
    {
      name = "first activation demotes usurped recycled ids without adopting foreign fingerprint",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 261,
              baseSpaceId = 1,
              fingerprint = {
                bundleID = "com.apple.mail",
                appName = "Mail",
                titleRaw = "Inbox",
                titleNormalized = "inbox",
              },
            },
          },
        }
        local usurper = FakeHs.makeWindow({
          id = 261,
          title = "Unrelated Tab",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({ usurper })
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        windowService.getWindowSpacesCalls = {}
        windowService.getWindowSpacesByIdCalls = {}

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "recoverable")
        Assert.equal(workspace.binding.baseWindowId, nil)
        Assert.equal(workspace.binding.fingerprint.bundleID, "com.apple.mail")
        Assert.equal(workspace.binding.fingerprint.titleNormalized, "inbox")
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
      end,
    },
    {
      name = "rapid profile switches exact-validate only the final selected profile",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 202,
              fingerprint = {
                bundleID = "com.apple.Safari",
                titleRaw = "Docs",
                titleNormalized = "docs",
              },
            },
          },
          [3] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 303,
              fingerprint = {
                bundleID = "com.apple.mail",
                titleRaw = "Inbox",
                titleNormalized = "inbox",
              },
            },
          },
        }
        local profileTwoWindow = FakeHs.makeWindow({
          id = 202,
          title = "Docs",
          bundleId = "com.apple.Safari",
          spaceIds = { 2 },
        })
        local profileThreeWindow = FakeHs.makeWindow({
          id = 303,
          title = "Inbox",
          bundleId = "com.apple.mail",
          spaceIds = { 3 },
        })
        local windowService = Fakes.createWindowService({ profileTwoWindow, profileThreeWindow })
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        windowService.getWindowSpacesCalls = {}

        Assert.truthy(app:activateProfile(2))
        Assert.truthy(app:activateProfile(3))
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(windowService.getWindowSpacesCalls[1].win:id(), 303)

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()
        Assert.equal(#windowService.getWindowSpacesCalls, 2)
        Assert.equal(windowService.getWindowSpacesCalls[2].win:id(), 202)
      end,
    },
    {
      name = "in-flight exact validation aborts when the active profile changes",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 221,
              baseSpaceId = 1,
              fingerprint = {
                bundleID = "com.apple.Safari",
                titleRaw = "One",
                titleNormalized = "one",
              },
            },
            [2] = {
              version = 2,
              kind = "paired",
              baseWindowId = 222,
              baseSpaceId = 1,
              fingerprint = {
                bundleID = "com.apple.mail",
                titleRaw = "Two",
                titleNormalized = "two",
              },
            },
          },
        }
        local first = FakeHs.makeWindow({
          id = 221,
          title = "One",
          bundleId = "com.apple.Safari",
          spaceIds = { 2 },
        })
        local second = FakeHs.makeWindow({
          id = 222,
          title = "Two",
          bundleId = "com.apple.mail",
          spaceIds = { 3 },
        })
        local windowService = Fakes.createWindowService({ first, second })
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        windowService.getWindowSpacesCalls = {}

        local switchedAway = false
        local baseGetWindowSpaces = windowService.getWindowSpaces
        windowService.getWindowSpaces = function(win)
          local spaceIds = baseGetWindowSpaces(win)
          if not switchedAway then
            switchedAway = true
            -- Simulate a profile hotkey landing while Spaces IPC pumps the runloop.
            app.session.activeProfileId = 1
          end
          return spaceIds
        end

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()

        Assert.equal(app:_getProfile(2).needsExactValidation, true)
        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(windowService.getWindowSpacesCalls[1].win:id(), 221)
        Assert.equal(app:_getWorkspace(1, 2).binding.baseSpaceId, 2)
        Assert.equal(app:_getWorkspace(2, 2).binding.baseSpaceId, 1)
      end,
    },
    {
      name = "first activation preserves exact id space evidence without candidate recovery",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 204,
              baseSpaceId = 1,
              fingerprint = {
                bundleID = "com.apple.Safari",
                titleRaw = "Release Notes",
                titleNormalized = "release notes",
              },
            },
          },
        }
        local offSpace = FakeHs.makeWindow({
          id = 204,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          spaceIds = { 4 },
        })
        local windowService = Fakes.createWindowService({ offSpace })
        local baseGetWindowById = windowService.getWindowById
        windowService.getWindowById = function(id)
          if id == 204 then
            return nil
          end
          return baseGetWindowById(id)
        end
        local candidateCalls = 0
        local baseCandidateWindows = windowService.candidateWindows
        windowService.candidateWindows = function()
          candidateCalls = candidateCalls + 1
          return baseCandidateWindows()
        end
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        candidateCalls = 0
        windowService.getWindowSpacesByIdCalls = {}

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 204)
        Assert.equal(workspace.binding.baseSpaceId, 4)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 1)
        Assert.equal(candidateCalls, 0)
      end,
    },
    {
      name = "first activation leaves missing exact targets paired and unresolved",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 999,
              baseSpaceId = 8,
              fullscreenTarget = {
                windowId = 1000,
                spaceId = 9,
              },
              fingerprint = {
                bundleID = "com.google.Chrome",
                appName = "Google Chrome",
                titleRaw = "Docs",
                titleNormalized = "docs",
              },
            },
          },
        }
        local windowService = Fakes.createWindowService()
        local candidateCalls = 0
        local baseCandidateWindows = windowService.candidateWindows
        windowService.candidateWindows = function()
          candidateCalls = candidateCalls + 1
          return baseCandidateWindows()
        end
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        candidateCalls = 0
        appdata.calls = {}

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 999)
        Assert.equal(workspace.binding.baseSpaceId, nil)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(app:getWorkspaceRowModels()[1].state, "unresolved")
        Assert.equal(candidateCalls, 0)

        local other = FakeHs.makeWindow({
          id = 77,
          title = "Mail",
          bundleId = "com.apple.mail",
        })
        FakeHs.setFrontmostWindow(other)
        app:activateSlot(1)
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 999)
        Assert.equal(candidateCalls, 0)

        local pairingWrites = 0
        for _, call in ipairs(appdata.calls) do
          if call.kind == "profilesWindowPairings" then
            pairingWrites = pairingWrites + 1
          end
        end
        Assert.equal(pairingWrites, 1)
      end,
    },
    {
      name = "first activation preserves exact fullscreen evidence without candidate recovery",
      run = function()
        local appdata = Fakes.createSettingsStore()
        appdata.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 301,
              baseSpaceId = 1,
              fullscreenTarget = {
                windowId = 302,
                spaceId = 2,
              },
              fingerprint = {
                bundleID = "com.apple.Safari",
                titleRaw = "Video",
                titleNormalized = "video",
              },
            },
          },
        }
        local fullscreenTarget = FakeHs.makeWindow({
          id = 302,
          title = "Video",
          bundleId = "com.apple.Safari",
          fullscreen = true,
          spaceIds = { 3 },
        })
        local windowService = Fakes.createWindowService({ fullscreenTarget })
        local candidateCalls = 0
        local baseCandidateWindows = windowService.candidateWindows
        windowService.candidateWindows = function()
          candidateCalls = candidateCalls + 1
          return baseCandidateWindows()
        end
        local app = makeApp({
          settings = Fakes.createSettingsStore(),
          appdata = appdata,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        candidateCalls = 0
        windowService.getWindowSpacesByIdCalls = {}

        Assert.truthy(app:activateProfile(2))
        flushScheduledTimers()

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 302)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 3)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "fullscreen")
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 2)
        Assert.equal(candidateCalls, 0)
      end,
    },
    {
      name = "activating an empty slot pairs the frontmost window",
      run = function()
        local frontmost = FakeHs.makeWindow({
          id = 11,
          title = "Docs - YouTube",
        })

        local windowService = Fakes.createWindowService({
          frontmost,
        })
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setFrontmostWindow(frontmost)

        app:activateSlot(1)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseWindowId, 11)
        Assert.equal(workspace.binding.fingerprint.titleRaw, "Docs - YouTube")
        Assert.equal(workspace.binding.fingerprint.titleNormalized, "docs - youtube")
        Assert.equal(workspace.binding.baseSpaceId, 1)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, nil)
        Assert.equal(app:getWorkspaceRowModels()[1].label, "Docs - YouTube")
        Assert.equal(#toasts, 1)
      end,
    },
    {
      name = "activating a paired slot focuses the paired window from another window",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 21,
          title = "Spotify",
        })
        local other = FakeHs.makeWindow({
          id = 22,
          title = "Mail",
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1]:consumeRepeatPress()
        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.requestFrontmostCalls, 1)
        Assert.equal(#windowService.ensureFrontmostAsyncCalls, 0)
        Assert.equal(windowService.requestFrontmostCalls[1].win:id(), 21)
        Assert.equal(app:getWorkspaces()[1].interaction.repeatBuffer, 2)
      end,
    },
    {
      name = "repeating a paired slot minimizes once the threshold is reached",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 31,
          title = "Browser",
        })

        local windowService = Fakes.createWindowService({
          paired,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFrontmostWindow(paired)

        app:pairSlot(1, paired)
        app:activateSlot(1)
        Assert.falsy(paired.minimized)
        Assert.equal(app:getWorkspaces()[1].interaction.repeatBuffer, 1)

        app:activateSlot(1)
        Assert.truthy(paired.minimized)
        Assert.equal(app:getWorkspaces()[1].interaction.repeatBuffer, 2)
      end,
    },
    {
      name = "destroyed paired windows are cleared and become recoverable",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 41,
          title = "Notes",
          bundleId = "com.apple.Notes",
          appName = "Notes",
        })

        local windowService = Fakes.createWindowService({
          paired,
        })
        local toast, toasts = Fakes.createToast()
        local youtubeService = {
          destroyedIds = {},
          getTargetId = function()
            return nil
          end,
          handleDestroyedWindowId = function(self, id)
            self.destroyedIds[#self.destroyedIds + 1] = id
          end,
          handleWindowCandidate = function() end,
          sendCommand = function() end,
        }
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = youtubeService,
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })

        app:pairSlot(1, paired)
        FakeHs.state().epochSeconds = 12
        app:handleWindowEvent(hs.window.filter.windowDestroyed, paired)

        Assert.falsy(app:getWorkspaces()[1]:isPaired())
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.bundleID, "com.apple.Notes")
        Assert.equal(app:getWorkspaceRowModels()[1].state, "recoverable")
        Assert.equal(app:getWorkspaceRowModels()[1].label, "Notes")
        Assert.equal(app:getWorkspaceRowModels()[1].iconBundleID, "com.apple.Notes")
        Assert.equal(app:getWorkspaceRowModels()[1].iconMuted, true)
        Assert.equal(youtubeService.destroyedIds[1], 41)
        Assert.equal(#toasts, 1)
      end,
    },
    {
      name = "missing paired windows become unresolved instead of being cleared on activation",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 51,
          title = "Notes",
        })
        local other = FakeHs.makeWindow({
          id = 52,
          title = "Mail",
        })

        local settingsStore = Fakes.createSettingsStore()
        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        windowService.getWindowSpacesCalls = {}
        windowService.removeWindow(51)

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 51)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 1)
        local rows = app:getWorkspaceRowModels()
        Assert.equal(rows[1].state, "unresolved")
        Assert.equal(#toasts, 2)
        Assert.equal(toasts[#toasts].message.lines[1].segments[1].text, "Window not found in any spaces")
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(#windowService.getWindowSpacesCalls, 0)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
        Assert.truthy(#settingsStore.calls >= 1)
      end,
    },
    {
      name = "exact-id off-space recovery switches spaces when live window object is unavailable",
      run = function()
        local source = FakeHs.makeWindow({
          id = 98,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local target = FakeHs.makeWindow({
          id = 99,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          source,
          target,
        })
        local baseGetWindowById = windowService.getWindowById
        windowService.getWindowById = function(id)
          if id == 99 and FakeHs.state().focusedSpace ~= 1 then
            return nil
          end
          return baseGetWindowById(id)
        end
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setActiveSpace(2)
        FakeHs.setFrontmostWindow(source)

        app:pairSlot(1, target)
        for key, _ in pairs(toasts) do
          toasts[key] = nil
        end
        windowService.getWindowSpacesCalls = {}
        windowService.getWindowSpacesByIdCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.truthy(#windowService.getWindowSpacesCalls >= 1)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 1)
        Assert.equal(windowService.getWindowSpacesByIdCalls[1].windowId, 99)
        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 1)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 1)
        Assert.equal(windowService.requestFrontmostAfterSpaceSwitchCalls[1].win:id(), 99)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "paired")
        Assert.equal(#toasts, 0)
      end,
    },
    {
      name = "exact-id off-space timeout toasts only after pending activation finally fails",
      run = function()
        local source = FakeHs.makeWindow({
          id = 188,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local target = FakeHs.makeWindow({
          id = 189,
          title = "Mail",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({
          source,
          target,
        })
        local baseGetWindowById = windowService.getWindowById
        windowService.getWindowById = function(id)
          if id == 189 and FakeHs.state().focusedSpace ~= 1 then
            return nil
          end
          return baseGetWindowById(id)
        end
        local pendingCompletion = nil
        windowService.requestFrontmostInSpace = function(windowId, spaceId, cfg, onComplete)
          windowService.requestFrontmostInSpaceCalls[#windowService.requestFrontmostInSpaceCalls + 1] = {
            windowId = windowId,
            spaceId = spaceId,
            cfg = cfg,
          }
          pendingCompletion = onComplete
          return {
            ok = true,
            code = "space_switch_requested",
            windowId = windowId,
            spaceId = spaceId,
          }
        end
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setActiveSpace(2)
        FakeHs.setFrontmostWindow(source)

        app:pairSlot(1, target)
        for key, _ in pairs(toasts) do
          toasts[key] = nil
        end

        app:activateSlot(1)

        Assert.equal(#windowService.requestFrontmostInSpaceCalls, 1)
        Assert.equal(#toasts, 0)
        Assert.truthy(pendingCompletion)

        pendingCompletion({
          ok = false,
          code = "space_switch_timeout",
          windowId = 189,
          spaceId = 1,
        })

        Assert.equal(#toasts, 1)
        -- space_switch_timeout is a Space-switch failure, not a missing-window code.
        Assert.equal(toasts[1].message.lines[1].segments[1].text, "Could not switch to the window's Space")
      end,
    },
    {
      name = "profile switch leaves an in-flight slot Space recall pending",
      run = function()
        local localWin = FakeHs.makeWindow({
          id = 301,
          title = "Local",
          spaceIds = { 1 },
        })
        local remote = FakeHs.makeWindow({
          id = 302,
          title = "Remote",
          spaceIds = { 7 },
        })
        local windowService = Fakes.createWindowService({
          localWin,
          remote,
        })
        local pendingCompletion = nil
        windowService.requestFrontmostInSpace = function(windowId, spaceId, cfg, onComplete)
          windowService.requestFrontmostInSpaceCalls[#windowService.requestFrontmostInSpaceCalls + 1] = {
            windowId = windowId,
            spaceId = spaceId,
            cfg = cfg,
          }
          pendingCompletion = onComplete
          return {
            ok = true,
            code = "space_switch_requested",
            windowId = windowId,
            spaceId = spaceId,
          }
        end
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setActiveSpace(1)
        FakeHs.setFrontmostWindow(localWin)

        app:pairSlot(1, remote)
        app:activateSlot(1)

        Assert.equal(#windowService.requestFrontmostInSpaceCalls, 1)
        Assert.truthy(pendingCompletion)
        local cancelsAfterSlot = windowService.cancelPendingFrontmostCalls
        Assert.truthy(cancelsAfterSlot >= 1, "slot activation cancels prior pending focus")

        -- Product choice: bank switch must not abort the Space jump the user already requested.
        Assert.truthy(app:activateProfile(2))
        Assert.equal(windowService.cancelPendingFrontmostCalls, cancelsAfterSlot)
        Assert.equal(app.session.activeProfileId, 2)

        FakeHs.setActiveSpace(7)
        pendingCompletion({
          ok = true,
          code = "focus_verified_after_space_switch",
          windowId = 302,
          spaceId = 7,
        }, remote)

        Assert.equal(app:_getWorkspace(1, 1).binding.baseSpaceId, 7)
        Assert.equal(app:_getWorkspace(1, 1).binding.baseWindowId, 302)
      end,
    },
    {
      name = "live paired window switches spaces only after exact-id resolution confirms another space",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 91,
          title = "Video",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 2 },
        })
        local other = FakeHs.makeWindow({
          id = 93,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        windowService.getWindowSpacesCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 2)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 1)
        Assert.equal(windowService.requestFrontmostAfterSpaceSwitchCalls[1].win:id(), 91)
        Assert.equal(#windowService.requestFrontmostCalls, 0)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 2)
        Assert.equal(app:getWorkspaces()[1].binding.fullscreenTarget.windowId, nil)
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.titleRaw, "Video")
      end,
    },
      {
        name = "live paired window with stale remembered space does not switch when exact window is already in focused space",
        run = function()
        local paired = FakeHs.makeWindow({
          id = 94,
          title = "Docs",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 95,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1].binding.baseSpaceId = 2
        windowService.getWindowSpacesCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(#windowService.requestFrontmostCalls, 1)
        Assert.equal(windowService.requestFrontmostCalls[1].win:id(), 94)
          Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 1)
        end,
      },
      {
        name = "unpaired window events skip fingerprint metadata work",
        run = function()
          local unrelated = FakeHs.makeWindow({
            id = 97,
            title = "Unrelated",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            spaceIds = { 1 },
          })
          local windowService = Fakes.createWindowService({
            unrelated,
          })
          local pairingMetadata = windowService.pairingMetadata
          local pairingMetadataCalls = 0
          windowService.pairingMetadata = function(win)
            pairingMetadataCalls = pairingMetadataCalls + 1
            return pairingMetadata(win)
          end
          local app = makeApp({
            settingsStore = Fakes.createSettingsStore(),
            windowService = windowService,
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            toast = function() end,
          })
          pairingMetadataCalls = 0

          app:handleWindowEvent(hs.window.filter.windowTitleChanged, unrelated)

          Assert.equal(pairingMetadataCalls, 0)
        end,
      },
      {
        name = "paired windowCreated non-candidates skip fingerprint metadata work",
        run = function()
          local paired = FakeHs.makeWindow({
            id = 96,
            title = "Docs",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            spaceIds = { 1 },
          })
          local untitled = FakeHs.makeWindow({
            id = 97,
            title = "",
            bundleId = "com.electron.helper",
            appName = "Helper",
            spaceIds = { 1 },
          })
          local windowService = Fakes.createWindowService({
            paired,
            untitled,
          })
          local pairingMetadata = windowService.pairingMetadata
          local pairingMetadataCalls = 0
          windowService.pairingMetadata = function(win)
            pairingMetadataCalls = pairingMetadataCalls + 1
            return pairingMetadata(win)
          end
          local app = makeApp({
            settingsStore = Fakes.createSettingsStore(),
            windowService = windowService,
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            toast = function() end,
          })

          app:pairSlot(1, paired)
          pairingMetadataCalls = 0

          app:handleWindowEvent(hs.window.filter.windowCreated, untitled)

          Assert.equal(pairingMetadataCalls, 0)
          Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 96)
          Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        end,
      },
      {
        name = "paired focused-window metadata refresh updates remembered space",
        run = function()
          local paired = FakeHs.makeWindow({
            id = 98,
            title = "Docs",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            spaceIds = { 1 },
          })
          local windowService = Fakes.createWindowService({
            paired,
          })
          local app = makeApp({
            settingsStore = Fakes.createSettingsStore(),
            windowService = windowService,
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            toast = function() end,
          })
          FakeHs.setFocusedSpace(1)

          app:pairSlot(1, paired)
          paired:setSpaceIds({ 2 })

          app:handleWindowEvent(hs.window.filter.windowFocused, paired)

          Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 2)
          Assert.equal(app:getWorkspaceRowModels()[1].state, "off_space")
        end,
      },
      {
        name = "focused fullscreen target does not overwrite base window space metadata",
        run = function()
          local base = FakeHs.makeWindow({
            id = 198,
            title = "Video",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            spaceIds = { 1 },
          })
          local fullscreenTarget = FakeHs.makeWindow({
            id = 199,
            title = "Video",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            fullscreen = true,
            spaceIds = { 7 },
          })
          local windowService = Fakes.createWindowService({
            base,
            fullscreenTarget,
          })
          local app = makeApp({
            settingsStore = Fakes.createSettingsStore(),
            windowService = windowService,
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            toast = function() end,
          })
          FakeHs.setFocusedSpace(7)
          FakeHs.setSpaceType(7, "fullscreen")

          app:pairSlot(1, base)
          local workspace = app:getWorkspaces()[1]
          workspace:setFullscreenState({
            fullscreenWindowId = 199,
            fullscreenSpaceId = 7,
            lastKnownSpaceId = 7,
          })
          workspace:setBaseSpaceId(1)
          windowService.getWindowSpacesCalls = {}

          app:handleWindowEvent(hs.window.filter.windowFocused, fullscreenTarget)

          Assert.equal(workspace.binding.baseSpaceId, 1)
          Assert.equal(workspace.binding.fullscreenTarget.windowId, 199)
          Assert.equal(#windowService.getWindowSpacesCalls, 0)
        end,
      },
      {
        name = "paired title events refresh metadata without space lookup",
        run = function()
          local paired = FakeHs.makeWindow({
            id = 99,
            title = "Docs",
            bundleId = "com.apple.Safari",
            appName = "Safari",
            spaceIds = { 1 },
          })
          local windowService = Fakes.createWindowService({
            paired,
          })
          local app = makeApp({
            settingsStore = Fakes.createSettingsStore(),
            windowService = windowService,
            youtubeService = Fakes.createNoopYoutubeService(),
            spotifyService = Fakes.createNoopSpotifyService(),
            toast = function() end,
          })

        app:pairSlot(1, paired)
        paired:setTitle("Docs Updated")
        windowService.getWindowSpacesCalls = {}

        app:handleWindowEvent(hs.window.filter.windowTitleChanged, paired)

        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.titleRaw, "Docs Updated")
        Assert.equal(#windowService.getWindowSpacesCalls, 0)
      end,
    },
    {
      name = "same-space focus updates the header without a full popover refresh",
      run = function()
        local refreshCalls = {}
        local activeWindowCalls = {}
        local win = FakeHs.makeWindow({
          id = 401,
          title = "Notes",
          bundleId = "com.apple.Notes",
          appName = "Notes",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({ win })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(win)
        app.session.focusedSpaceId = 1
        app:attachUi({
          requestRefresh = function(_, reason, updateWin)
            refreshCalls[#refreshCalls + 1] = {
              reason = reason,
              win = updateWin,
            }
          end,
          requestActiveWindowUpdate = function(_, updateWin)
            activeWindowCalls[#activeWindowCalls + 1] = updateWin
          end,
        }, nil)

        app:handleActiveWindowChange(win)
        app:handleWindowEvent(hs.window.filter.windowFocused, win)

        Assert.equal(#refreshCalls, 0, "focus must not also queue a full rebuild")
        Assert.equal(#activeWindowCalls, 1)
        Assert.equal(activeWindowCalls[1]:id(), 401)
      end,
    },
    {
      name = "focused Space change requests a full popover refresh",
      run = function()
        local refreshCalls = {}
        local activeWindowCalls = {}
        local win = FakeHs.makeWindow({
          id = 402,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({ win })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(2)
        FakeHs.setFrontmostWindow(win)
        app.session.focusedSpaceId = 1
        app:attachUi({
          requestRefresh = function(_, reason, updateWin)
            refreshCalls[#refreshCalls + 1] = {
              reason = reason,
              win = updateWin,
            }
          end,
          requestActiveWindowUpdate = function(_, updateWin)
            activeWindowCalls[#activeWindowCalls + 1] = updateWin
          end,
        }, nil)

        app:handleActiveWindowChange(win)

        Assert.equal(#refreshCalls, 1)
        Assert.equal(refreshCalls[1].reason, "focused_space_change")
        Assert.equal(refreshCalls[1].win:id(), 402)
        Assert.equal(#activeWindowCalls, 0)
      end,
    },
    {
      name = "resyncs popover window behavior when hide-during-fullscreens changes",
      run = function()
        local syncCalls = 0
        local app = makeApp({
          configOverrides = {
            popoverHideOnFullscreenWorkspace = false,
            popoverAlwaysOnTop = true,
          },
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        app:attachUi({
          syncWindowLevel = function()
            syncCalls = syncCalls + 1
          end,
          requestRefresh = function() end,
          requestActiveWindowUpdate = function() end,
        }, nil)
        app.syncUi = function() end

        app:setPopoverHideOnFullscreenWorkspace(true)

        Assert.equal(app.cfg.popoverHideOnFullscreenWorkspace, true)
        Assert.equal(syncCalls, 1)

        app:setPopoverHideOnFullscreenWorkspace(false)
        Assert.equal(app.cfg.popoverHideOnFullscreenWorkspace, false)
        Assert.equal(syncCalls, 2)
      end,
    },
    {
      name = "hides shown popover on fullscreen Space and restores after leaving",
      run = function()
        local ensureCalls = 0
        local hideCalls = 0
        local shown = true
        local app = makeApp({
          configOverrides = {
            popoverHideOnFullscreenWorkspace = true,
            popoverAlwaysOnTop = true,
          },
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(9, "fullscreen")
        FakeHs.setSpaceType(1, "user")
        FakeHs.setFocusedSpace(9)
        app.session.focusedSpaceId = 9
        app:attachUi({
          isShown = function()
            return shown
          end,
          hide = function()
            hideCalls = hideCalls + 1
            shown = false
          end,
          ensureVisible = function()
            ensureCalls = ensureCalls + 1
            shown = true
          end,
          show = function()
            shown = true
          end,
          requestRefresh = function() end,
          requestActiveWindowUpdate = function() end,
        }, nil)

        -- Entering FS while shown hides and pins restore intent.
        app:handleFocusedSpaceChange()
        Assert.equal(hideCalls, 1)
        Assert.equal(shown, false)
        Assert.equal(app.popoverFullscreenVisibility:isRestorePinned(), true)
        Assert.equal(ensureCalls, 0)

        FakeHs.setFocusedSpace(1)
        app:handleFocusedSpaceChange()

        Assert.equal(ensureCalls, 1)
        Assert.equal(shown, true)
        Assert.equal(app.popoverFullscreenVisibility:isRestorePinned(), false)
      end,
    },
    {
      name = "does not force-show popover when leaving fullscreen if it was not open",
      run = function()
        local ensureCalls = 0
        local hideCalls = 0
        local showCalls = 0
        local app = makeApp({
          configOverrides = {
            popoverHideOnFullscreenWorkspace = true,
            popoverAlwaysOnTop = true,
          },
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(9, "fullscreen")
        FakeHs.setSpaceType(1, "user")
        FakeHs.setFocusedSpace(9)
        app.session.focusedSpaceId = 9
        app:attachUi({
          isShown = function()
            return false
          end,
          hide = function()
            hideCalls = hideCalls + 1
          end,
          ensureVisible = function()
            ensureCalls = ensureCalls + 1
          end,
          show = function()
            showCalls = showCalls + 1
          end,
          requestRefresh = function() end,
          requestActiveWindowUpdate = function() end,
        }, nil)

        app:handleFocusedSpaceChange()
        Assert.equal(hideCalls, 0)
        Assert.equal(app.popoverFullscreenVisibility:isRestorePinned(), false)

        FakeHs.setFocusedSpace(1)
        app:handleFocusedSpaceChange()

        Assert.equal(ensureCalls, 0)
        Assert.equal(showCalls, 0)
      end,
    },
    {
      name = "hides popover when activating a slot into a fullscreen Space",
      run = function()
        local hideCalls = 0
        local shown = true
        local paired = FakeHs.makeWindow({
          id = 501,
          title = "Video",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 502,
          title = "Mail",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          configOverrides = {
            popoverHideOnFullscreenWorkspace = true,
            popoverAlwaysOnTop = true,
            popoverAutoHideAfterAction = false,
            recoverClosedWindows = false,
          },
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(9, "fullscreen")
        FakeHs.setSpaceType(1, "user")
        FakeHs.setActiveSpace(1)
        FakeHs.setFrontmostWindow(other)
        app.session.focusedSpaceId = 1

        app:pairSlot(1, paired)
        paired:setFullScreen(true)
        paired:setSpaceIds({ 9 })
        app:handleWindowEvent(hs.window.filter.windowFullscreened, paired)

        app:attachUi({
          isShown = function()
            return shown
          end,
          hide = function()
            hideCalls = hideCalls + 1
            shown = false
          end,
          requestRefresh = function() end,
          requestActiveWindowUpdate = function() end,
        }, nil)
        app.syncUi = function() end
        app._syncWorkspaceUi = function() end

        -- Re-open after fullscreened reconcile may have hidden during the event.
        shown = true
        hideCalls = 0
        app:notePopoverIntentionalDismiss()

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(hideCalls, 1)
        Assert.equal(shown, false)
        Assert.equal(app.popoverFullscreenVisibility:isRestorePinned(), true)
        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 9)
      end,
    },
    {
      name = "unpaired frontmost title changes update the header without a full refresh",
      run = function()
        local refreshCalls = {}
        local activeWindowCalls = {}
        local win = FakeHs.makeWindow({
          id = 403,
          title = "Scratch",
          bundleId = "com.test.scratch",
          appName = "Scratch",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({ win })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFrontmostWindow(win)
        app:attachUi({
          requestRefresh = function(_, reason)
            refreshCalls[#refreshCalls + 1] = reason
          end,
          requestActiveWindowUpdate = function(_, updateWin)
            activeWindowCalls[#activeWindowCalls + 1] = updateWin
          end,
        }, nil)

        win:setTitle("Scratch Updated")
        app:handleWindowEvent(hs.window.filter.windowTitleChanged, win)

        Assert.equal(#refreshCalls, 0)
        Assert.equal(#activeWindowCalls, 1)
        Assert.equal(activeWindowCalls[1]:id(), 403)
      end,
    },
    {
      name = "paired title changes request a full popover refresh",
      run = function()
        local refreshCalls = {}
        local activeWindowCalls = {}
        local paired = FakeHs.makeWindow({
          id = 404,
          title = "Docs",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({ paired })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFrontmostWindow(paired)
        app:attachUi({
          requestRefresh = function(_, reason)
            refreshCalls[#refreshCalls + 1] = reason
          end,
          requestActiveWindowUpdate = function(_, updateWin)
            activeWindowCalls[#activeWindowCalls + 1] = updateWin
          end,
        }, nil)

        app:pairSlot(1, paired)
        refreshCalls = {}
        activeWindowCalls = {}
        paired:setTitle("Docs Updated")
        app:handleWindowEvent(hs.window.filter.windowTitleChanged, paired)

        Assert.equal(#refreshCalls, 1)
        Assert.equal(refreshCalls[1], "window_event")
        Assert.equal(#activeWindowCalls, 0)
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.titleRaw, "Docs Updated")
      end,
    },
    {
      name = "live paired window with unknown space membership does not switch spaces",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 96,
          title = "Docs",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 2 },
        })
        local other = FakeHs.makeWindow({
          id = 97,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local baseGetWindowSpaces = windowService.getWindowSpaces
        windowService.getWindowSpaces = function(win)
          baseGetWindowSpaces(win)
          return {}
        end
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1].binding.baseSpaceId = 2
        windowService.getWindowSpacesCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(#windowService.requestFrontmostCalls, 1)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 2)
      end,
    },
    {
      name = "exact-id unresolved path does not switch when no valid spaces are found",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 100,
          title = "Notes",
          bundleId = "com.apple.Notes",
          appName = "Notes",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 101,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 2 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setFocusedSpace(2)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1].binding.baseSpaceId = 1
        windowService.getWindowSpacesByIdCalls = {}
        windowService.removeWindow(100)

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesByIdCalls, 1)
        Assert.equal(windowService.getWindowSpacesByIdCalls[1].windowId, 100)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(toasts[#toasts].message.lines[1].segments[1].text, "Window not found in any spaces")
      end,
    },
    {
      name = "exact-id unresolved path does not switch when id already claims the focused space",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 102,
          title = "Notes",
          bundleId = "com.apple.Notes",
          appName = "Notes",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 103,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local baseGetWindowById = windowService.getWindowById
        windowService.getWindowById = function(id)
          if id == 102 then
            return nil
          end
          return baseGetWindowById(id)
        end
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1].binding.baseSpaceId = 2
        windowService.getWindowSpacesByIdCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesByIdCalls, 1)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(toasts[#toasts].message.lines[1].segments[1].text, "Window not found in any spaces")
      end,
    },
    {
      name = "main-space source activates fullscreen target by switching spaces",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 121,
          title = "Video",
          spaceIds = { 1 },
        })
        local fullscreenPaired = FakeHs.makeWindow({
          id = 123,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local other = FakeHs.makeWindow({
          id = 122,
          title = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setActiveSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        windowService.removeWindow(121)
        app:getWorkspaces()[1].binding.fullscreenTarget.windowId = 123
        app:getWorkspaces()[1].binding.fullscreenTarget.spaceId = 2
        windowService.addWindow(fullscreenPaired)

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 2)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 1)
        Assert.equal(windowService.requestFrontmostAfterSpaceSwitchCalls[1].win:id(), 123)
      end,
    },
    {
      name = "fullscreen activation preserves base pairing while routing to tracked fullscreen target",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 124,
          title = "Video",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 126,
          title = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setActiveSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, paired)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 1)

        paired:setFullScreen(true)
        paired:setSpaceIds({ 2 })
        app:handleWindowEvent(hs.window.filter.windowFullscreened, paired)

        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 1)
        Assert.truthy(app:getWorkspaces()[1]:hasTrackedFullscreenTarget())
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 124)
        Assert.equal(app:getWorkspaces()[1].binding.fullscreenTarget.windowId, 124)
        Assert.equal(app:getWorkspaces()[1].binding.fullscreenTarget.spaceId, 2)

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 124)
        Assert.equal(app:getWorkspaces()[1].binding.fullscreenTarget.windowId, 124)
        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 2)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 1)
        Assert.equal(windowService.requestFrontmostAfterSpaceSwitchCalls[1].win:id(), 124)
      end,
    },
    {
      name = "fullscreen source activates main-space target via exact-id-confirmed space switch without cleanup",
      run = function()
        local source = FakeHs.makeWindow({
          id = 131,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local target = FakeHs.makeWindow({
          id = 132,
          title = "Mail",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          source,
          target,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setActiveSpace(2)
        FakeHs.setFrontmostWindow(source)

        app:pairSlot(1, target)
        app:getWorkspaces()[1].binding.fullscreenTarget.windowId = 999
        app:getWorkspaces()[1].binding.fullscreenTarget.spaceId = 9
        windowService.getWindowSpacesCalls = {}

        app:activateSlot(1)
        flushScheduledTimers()

        Assert.equal(#windowService.getWindowSpacesCalls, 1)
        Assert.equal(#windowService.gotoSpaceCalls, 1)
        Assert.equal(windowService.gotoSpaceCalls[1].spaceId, 1)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 1)
        Assert.equal(windowService.requestFrontmostAfterSpaceSwitchCalls[1].win:id(), 132)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "paired")
      end,
    },
    {
      name = "rapid same-space recalls request frontmost immediately",
      run = function()
        local slotOne = FakeHs.makeWindow({
          id = 181,
          title = "Docs",
          spaceIds = { 1 },
        })
        local slotTwo = FakeHs.makeWindow({
          id = 182,
          title = "Mail",
          spaceIds = { 1 },
        })
        local other = FakeHs.makeWindow({
          id = 183,
          title = "Terminal",
          spaceIds = { 1 },
        })

        local windowService = Fakes.createWindowService({
          slotOne,
          slotTwo,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setFocusedSpace(1)
        FakeHs.setFrontmostWindow(other)

        app:pairSlot(1, slotOne)
        app:pairSlot(2, slotTwo)

        app:activateSlot(1)
        app:activateSlot(2)
        app:activateSlot(1)
        app:activateSlot(2)

        Assert.equal(#windowService.requestFrontmostCalls, 4)
        Assert.equal(windowService.requestFrontmostCalls[4].win:id(), 182)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 0)
      end,
    },
    {
      name = "same fullscreen target reactivation is a no-op",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 141,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          paired,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setActiveSpace(2)
        FakeHs.setFrontmostWindow(paired)

        app:pairSlot(1, paired)
        app:getWorkspaces()[1].binding.fullscreenTarget.windowId = 141
        app:getWorkspaces()[1].binding.fullscreenTarget.spaceId = 2

        app:activateSlot(1)

        Assert.equal(#windowService.requestFrontmostCalls, 0)
        Assert.equal(#windowService.gotoSpaceCalls, 0)
        Assert.equal(#windowService.requestFrontmostAfterSpaceSwitchCalls, 0)
      end,
    },
    {
      name = "fullscreen target destroy clears fullscreen state but preserves base pairing",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 151,
          title = "Browser",
          spaceIds = { 1 },
        })
        local fullscreenWin = FakeHs.makeWindow({
          id = 152,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          configOverrides = {
            recoverClosedWindows = false,
          },
          windowService = Fakes.createWindowService({
            paired,
            fullscreenWin,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        app:pairSlot(1, paired)
        local workspace = app:getWorkspaces()[1]
        workspace.binding.fullscreenTarget.windowId = 152
        workspace.binding.fullscreenTarget.spaceId = 2

        app:handleWindowEvent(hs.window.filter.windowDestroyed, fullscreenWin)

        Assert.equal(workspace.binding.baseWindowId, 151)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, nil)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(app:getWorkspaceRowModels()[1].state, "paired")
      end,
    },
    {
      name = "pairing an already-fullscreen window tracks overlay without treating fullscreen Space as home",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 161,
          title = "Video",
          fullscreen = true,
          spaceIds = { 7 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService({
            paired,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(7, "fullscreen")
        FakeHs.setActiveSpace(7)
        FakeHs.setFrontmostWindow(paired)

        app:pairSlot(1, paired)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseWindowId, 161)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 161)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 7)
        Assert.equal(workspace.binding.baseSpaceId, nil)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "fullscreen")
      end,
    },
    {
      name = "unfullscreen after pairing fullscreen learns home Space from the landing Space",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 162,
          title = "Video",
          fullscreen = true,
          spaceIds = { 7 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService({
            paired,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(7, "fullscreen")
        FakeHs.setActiveSpace(7)

        app:pairSlot(1, paired)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, nil)

        paired:setFullScreen(false)
        paired:setSpaceIds({ 3 })
        FakeHs.setActiveSpace(3)
        app:handleWindowEvent(hs.window.filter.windowUnfullscreened, paired)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseWindowId, 162)
        Assert.equal(workspace.binding.baseSpaceId, 3)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(workspace.binding.fullscreenTarget.windowId, nil)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "paired")
      end,
    },
    {
      name = "regular pair fullscreen enter preserves desktop home Space",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 163,
          title = "Docs",
          spaceIds = { 1 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService({
            paired,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(8, "fullscreen")
        FakeHs.setActiveSpace(1)

        app:pairSlot(1, paired)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 1)

        paired:setFullScreen(true)
        paired:setSpaceIds({ 8 })
        app:handleWindowEvent(hs.window.filter.windowFullscreened, paired)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseSpaceId, 1)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 163)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 8)

        paired:setFullScreen(false)
        paired:setSpaceIds({ 4 })
        app:handleWindowEvent(hs.window.filter.windowUnfullscreened, paired)

        Assert.equal(workspace.binding.baseSpaceId, 4)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
      end,
    },
    {
      name = "tracked fullscreen destroy clears fullscreen state and preserves base pairing",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 153,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService({
            paired,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")

        app:pairSlot(1, paired)
        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 153)
        Assert.equal(workspace.binding.baseSpaceId, nil)

        app:handleWindowEvent(hs.window.filter.windowDestroyed, paired)

        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 153)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, nil)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
      end,
    },
    {
      name = "unfullscreen updates the remembered space and clears fullscreen state",
      run = function()
        local paired = FakeHs.makeWindow({
          id = 154,
          title = "Video",
          fullscreen = true,
          spaceIds = { 2 },
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService({
            paired,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        FakeHs.setSpaceType(2, "fullscreen")

        app:pairSlot(1, paired)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, nil)
        Assert.equal(app:getWorkspaces()[1].binding.fullscreenTarget.windowId, 154)

        paired:setFullScreen(false)
        paired:setSpaceIds({ 1 })

        app:handleWindowEvent(hs.window.filter.windowUnfullscreened, paired)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseSpaceId, 1)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(workspace.binding.fullscreenTarget.windowId, nil)
      end,
    },
    {
      name = "restore of live fullscreen base without persisted target sets overlay and keeps home unset",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "paired",
            baseWindowId = 171,
            fingerprint = {
              bundleID = "com.apple.Safari",
              appName = "Safari",
              titleRaw = "Video",
              titleNormalized = "video",
            },
          },
        }

        local liveFullscreen = FakeHs.makeWindow({
          id = 171,
          title = "Video",
          fullscreen = true,
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 9 },
        })
        local windowService = Fakes.createWindowService({
          liveFullscreen,
        })
        FakeHs.setSpaceType(9, "fullscreen")
        FakeHs.setFocusedSpace(1)
        FakeHs.setActiveSpace(1)

        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.baseWindowId, 171)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 171)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 9)
        Assert.equal(workspace.binding.baseSpaceId, nil)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "fullscreen")
      end,
    },
    {
      name = "matching replacement window restores the recoverable slot",
      run = function()
        local original = FakeHs.makeWindow({
          id = 61,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 62,
          title = "  release   notes ",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })

        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(61)
        FakeHs.state().epochSeconds = 20
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        FakeHs.state().epochSeconds = 23
        app:handleWindowEvent(hs.window.filter.windowCreated, restored)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 62)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        Assert.equal(#toasts, 2)
      end,
    },
    {
      name = "debug logger records window and recovery decisions",
      run = function()
        local original = FakeHs.makeWindow({
          id = 63,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 64,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          visible = false,
          minimized = true,
        })
        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local debugLogger = {
          records = {},
          enabled = function()
            return true
          end,
          record = function(self, domain, level, event, message, payloadOrFn)
            local data = type(payloadOrFn) == "function" and payloadOrFn() or payloadOrFn
            self.records[#self.records + 1] = {
              domain = domain,
              level = level,
              event = event,
              message = message,
              data = data,
            }
            return true
          end,
        }
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          debugLogger = debugLogger,
          toast = function() end,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(63)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        debugLogger.records = {}

        app:handleWindowEvent(hs.window.filter.windowCreated, restored)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 64)

        local sawWindow = false
        local sawMatch = false
        local sawRestore = false
        for _, record in ipairs(debugLogger.records) do
          if record.domain == "window" and record.event == hs.window.filter.windowCreated then
            sawWindow = true
            Assert.equal(record.data.window.isVisible, false)
            Assert.equal(record.data.window.isMinimized, true)
          elseif record.domain == "recovery" and record.event == "slot_match_result" then
            sawMatch = true
            Assert.equal(record.data.decision, "matched")
            Assert.equal(record.data.matchedSlots[1].index, 1)
          elseif record.domain == "recovery" and record.event == "restore_result" then
            sawRestore = true
            Assert.equal(record.data.decision, "restored")
            Assert.equal(record.data.restoredSlots[1].index, 1)
          end
        end
        Assert.truthy(sawWindow)
        Assert.truthy(sawMatch)
        Assert.truthy(sawRestore)
      end,
    },
    {
      name = "same app with different title does not restore",
      run = function()
        local original = FakeHs.makeWindow({
          id = 71,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local other = FakeHs.makeWindow({
          id = 72,
          title = "Settings",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })

        local windowService = Fakes.createWindowService({
          original,
          other,
        })
        local toast, toasts = Fakes.createToast()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = toast,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(71)
        FakeHs.state().epochSeconds = 30
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        FakeHs.state().epochSeconds = 31
        app:handleWindowEvent(hs.window.filter.windowCreated, other)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.titleNormalized, "release notes")
        Assert.equal(#toasts, 1)
      end,
    },
    {
      name = "matching title from different app does not restore",
      run = function()
        local original = FakeHs.makeWindow({
          id = 81,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local other = FakeHs.makeWindow({
          id = 82,
          title = "Release Notes",
          bundleId = "com.apple.TextEdit",
          appName = "TextEdit",
        })

        local windowService = Fakes.createWindowService({
          original,
          other,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(81)
        FakeHs.state().epochSeconds = 40
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        FakeHs.state().epochSeconds = 41
        app:handleWindowEvent(hs.window.filter.windowCreated, other)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.bundleID, "com.apple.Safari")
      end,
    },
    {
      name = "recovery fingerprint index relinks all matching recoverable slots",
      run = function()
        local originalA = FakeHs.makeWindow({
          id = 83,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local originalB = FakeHs.makeWindow({
          id = 84,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 85,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local unrelated = FakeHs.makeWindow({
          id = 86,
          title = "Inbox",
          bundleId = "com.apple.mail",
          appName = "Mail",
        })

        local windowService = Fakes.createWindowService({
          originalA,
          originalB,
          restored,
          unrelated,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local pairCalls = 0
        local pairWorkspace = app._pairWorkspace
        app._pairWorkspace = function(self, workspace, windowId, win)
          pairCalls = pairCalls + 1
          return pairWorkspace(self, workspace, windowId, win)
        end

        app:pairSlot(1, originalA)
        app:pairSlot(2, originalB)
        pairCalls = 0

        windowService.removeWindow(83)
        windowService.removeWindow(84)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, originalA)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, originalB)

        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[2].binding.kind, "recoverable")
        Assert.equal(app.session.recoveryMatchIndexDirty, true)

        app:_ensureRecoveryMatchIndex()
        Assert.equal(app.session.recoveryMatchIndexDirty, false)
        Assert.equal(app.session.recoverableSlotCount, 2)
        local indexed = app.session.recoveryMatchIndex["com.apple.Safari"]
          and app.session.recoveryMatchIndex["com.apple.Safari"]["release notes"]
        Assert.equal(#indexed, 2)

        pairCalls = 0
        app:handleWindowEvent(hs.window.filter.windowCreated, unrelated)
        Assert.equal(pairCalls, 0)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[2].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)
        Assert.equal(app:getWorkspaces()[2].binding.baseWindowId, nil)

        app:handleWindowEvent(hs.window.filter.windowCreated, restored)
        Assert.equal(pairCalls, 2)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        Assert.equal(app:getWorkspaces()[2].binding.kind, "paired")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 85)
        Assert.equal(app:getWorkspaces()[2].binding.baseWindowId, 85)
        Assert.equal(app.session.recoveryMatchIndexDirty, true)

        app:_ensureRecoveryMatchIndex()
        Assert.equal(app.session.recoverableSlotCount, 0)
        Assert.equal(
          app.session.recoveryMatchIndex["com.apple.Safari"]
            and app.session.recoveryMatchIndex["com.apple.Safari"]["release notes"],
          nil
        )
      end,
    },
    {
      name = "recovery fingerprint index matches recoverable slots on inactive profiles",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.profiles"] = {
          [2] = {
            [1] = {
              version = 2,
              kind = "recoverable",
              fingerprint = {
                bundleID = "com.apple.Safari",
                appName = "Safari",
                titleRaw = "Release Notes",
                titleNormalized = "release notes",
              },
            },
          },
        }

        local restored = FakeHs.makeWindow({
          id = 114,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local windowService = Fakes.createWindowService({})
        TestEnv.reset({
          "app_config",
          "settings",
          "appdata",
          "state.workspace",
          "state.slot_record",
          "state.slot_row",
          "state.app_state",
        })
        local AppState = require("state.app_state")
        local app = AppState.new(makeConfig(), {
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local inactive = app:_getWorkspace(1, 2)
        Assert.equal(inactive.binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")

        windowService.addWindow(restored)
        app:handleWindowEvent(hs.window.filter.windowCreated, restored)

        Assert.equal(inactive.binding.kind, "paired")
        Assert.equal(inactive.binding.baseWindowId, 114)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
      end,
    },
    {
      name = "persisted recoverable without live window stays recoverable until matching candidate",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "recoverable",
            fingerprint = {
              bundleID = "com.apple.Safari",
              appName = "Safari",
              titleRaw = "Release Notes",
              titleNormalized = "release notes",
            },
          },
        }

        local unrelated = FakeHs.makeWindow({
          id = 112,
          title = "Inbox",
          bundleId = "com.apple.mail",
          appName = "Mail",
        })
        local restored = FakeHs.makeWindow({
          id = 113,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local windowService = Fakes.createWindowService({
          unrelated,
        })
        TestEnv.reset({
          "app_config",
          "settings",
          "appdata",
          "state.workspace",
          "state.slot_record",
          "state.slot_row",
          "state.app_state",
        })
        local AppState = require("state.app_state")
        local app = AppState.new(makeConfig(), {
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)

        local pairCalls = 0
        local pairWorkspace = app._pairWorkspace
        app._pairWorkspace = function(self, workspace, windowId, win)
          pairCalls = pairCalls + 1
          return pairWorkspace(self, workspace, windowId, win)
        end

        app:handleWindowEvent(hs.window.filter.windowTitleChanged, unrelated)
        Assert.equal(pairCalls, 0)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")

        windowService.addWindow(restored)
        app:handleWindowEvent(hs.window.filter.windowCreated, restored)
        Assert.equal(pairCalls, 1)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 113)
      end,
    },
    {
      name = "unpairAll clears recovery index so matching candidates do not restore",
      run = function()
        local original = FakeHs.makeWindow({
          id = 115,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 116,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(115)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "recoverable")

        app:unpairAll()
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
        Assert.equal(app.session.recoveryMatchIndexDirty, true)

        app:_ensureRecoveryMatchIndex()
        Assert.equal(app.session.recoverableSlotCount, 0)

        app:handleWindowEvent(hs.window.filter.windowCreated, restored)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)
      end,
    },
    {
      name = "recoverable slots do not expire before a matching replacement appears",
      run = function()
        local original = FakeHs.makeWindow({
          id = 91,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 92,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })

        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        app:pairSlot(1, original)
        windowService.removeWindow(91)
        FakeHs.state().epochSeconds = 50
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        FakeHs.state().epochSeconds = 59
        app:handleWindowEvent(hs.window.filter.windowCreated, restored)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 92)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
      end,
    },
    {
      name = "explicit unpair does not trigger restore path",
      run = function()
        local original = FakeHs.makeWindow({
          id = 101,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local restored = FakeHs.makeWindow({
          id = 102,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })

        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        app:pairSlot(1, original)
        app:unpairSlot(1)
        FakeHs.state().epochSeconds = 61
        app:handleWindowEvent(hs.window.filter.windowCreated, restored)

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, nil)
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.bundleID, nil)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
      end,
    },
      {
        name = "persisted recoverable records survive startup and restore by fingerprint",
        run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "recoverable",
            fingerprint = {
              bundleID = "com.apple.Safari",
              appName = "Safari",
              titleRaw = "Release Notes",
              titleNormalized = "release notes",
            },
          },
        }

        local restored = FakeHs.makeWindow({
          id = 111,
          title = "Release Notes",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local windowService = Fakes.createWindowService({
          restored,
        })
        TestEnv.reset({
          "app_config",
          "settings",
          "appdata",
          "state.workspace",
          "state.slot_record",
          "state.slot_row",
          "state.app_state",
        })
        FakeHs.state().epochSeconds = 10
        local AppState = require("state.app_state")
        local app = AppState.new(makeConfig(), {
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.bundleID, "com.apple.Safari")

        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 111)
          Assert.equal(app:getWorkspaces()[1].binding.kind, "paired")
        end,
      },
      {
        name = "persisted paired records restore as off-space when exact-id space lookup still resolves",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "paired",
            baseWindowId = 201,
            baseSpaceId = 2,
            fingerprint = {
              bundleID = "com.apple.mail",
              appName = "Mail",
              titleRaw = "Inbox",
              titleNormalized = "inbox",
            },
          },
        }

        local offSpace = FakeHs.makeWindow({
          id = 201,
          title = "Inbox",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          offSpace,
        })
        local baseGetWindowById = windowService.getWindowById
        windowService.getWindowById = function(id)
          if id == 201 then
            return nil
          end
          return baseGetWindowById(id)
        end
        FakeHs.setFocusedSpace(1)
        FakeHs.setActiveSpace(1)

        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 201)
        Assert.equal(workspace.binding.baseSpaceId, 2)
        Assert.equal(app:getWorkspaceRowModels()[1].state, "off_space")
      end,
    },
    {
      name = "persisted fullscreen target survives startup when its exact id still resolves",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "paired",
            baseWindowId = 301,
            baseSpaceId = 1,
            fullscreenTarget = {
              windowId = 302,
              spaceId = 2,
            },
            fingerprint = {
              bundleID = "com.apple.Safari",
              appName = "Safari",
              titleRaw = "Video",
              titleNormalized = "video",
            },
          },
        }

        local fullscreenWin = FakeHs.makeWindow({
          id = 302,
          title = "Video",
          fullscreen = true,
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          fullscreenWin,
        })
        FakeHs.setSpaceType(2, "fullscreen")
        FakeHs.setFocusedSpace(1)
        FakeHs.setActiveSpace(1)

        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 301)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 302)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 2)
        Assert.truthy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(app:getWorkspaceRowModels()[1].state, "fullscreen")
      end,
    },
    {
      name = "stale legacy metadata-only records are discarded on startup",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            bundleID = "com.apple.Safari",
            appName = "Safari",
            titleRaw = "Release Notes",
            titleNormalized = "release notes",
          },
        }

        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
        Assert.equal(app:getWorkspaces()[1].binding.fingerprint.bundleID, nil)
      end,
    },
    {
      name = "returns youtube command result",
      run = function()
        local youtubeService = {
          getTargetId = function()
            return nil
          end,
          handleDestroyedWindowId = function() end,
          handleWindowCandidate = function() end,
          sendCommand = function(_, keyPress)
            return {
              ok = keyPress == "k",
              code = "focused_and_sent",
              focusResult = "focus_verified",
            }
          end,
        }
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = youtubeService,
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local result = app:sendYoutubeCommand("k")

        Assert.truthy(result.ok)
        Assert.equal(result.code, "focused_and_sent")
        Assert.equal(result.focusResult, "focus_verified")
      end,
    },
    {
      name = "pairing actions auto-hide while hotkey slot activation does not",
      run = function()
        FakeHs.install()
        local paired = FakeHs.makeWindow({
          id = 201,
          title = "Docs",
        })
        local other = FakeHs.makeWindow({
          id = 202,
          title = "Mail",
        })
        local windowService = Fakes.createWindowService({
          paired,
          other,
        })
        local app = makeApp({
          configOverrides = {
            popoverAutoHideAfterAction = true,
          },
          settingsStore = Fakes.createSettingsStore(),
          windowService = windowService,
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        local popover = {
          hideCalls = 0,
          isShown = function()
            return true
          end,
          hide = function(self)
            self.hideCalls = self.hideCalls + 1
          end,
        }
        app:attachUi(popover, nil)

        app:pairSlot(1, paired)
        Assert.equal(popover.hideCalls, 1)

        app:unpairSlot(1)
        Assert.equal(popover.hideCalls, 2)

        app:pairSlot(1, paired)
        Assert.equal(popover.hideCalls, 3)

        FakeHs.setFrontmostWindow(other)
        app:activateSlot(1)
        Assert.equal(popover.hideCalls, 3)
        Assert.truthy(#windowService.requestFrontmostCalls == 1)

        FakeHs.setFrontmostWindow(paired)
        app:activateSlot(1)
        Assert.equal(popover.hideCalls, 3)
      end,
    },
    {
      name = "hotkey binding mutations do not force a broad syncUi refresh",
      run = function()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        local syncCalls = 0
        app.syncUi = function()
          syncCalls = syncCalls + 1
        end
        app.hotkeyManager = {
          getUiState = function()
            return {
              rows = {},
              conflictsById = {},
              overrides = {},
              recordingSupported = true,
            }
          end,
          warmUiState = function() end,
          warmHtml = function(_, rendererFn)
            if rendererFn then
              rendererFn({})
            end
          end,
          updateBinding = function()
            return { ok = true }
          end,
          resetBinding = function()
            return { ok = true }
          end,
          resetAll = function()
            return { ok = true }
          end,
        }

        app:updateHotkeyBinding("youtube.playPause.k", { mods = { "cmd" }, key = "k" })
        app:resetHotkeyBinding("youtube.playPause.k")
        app:resetAllHotkeys()
        Assert.equal(syncCalls, 0)
      end,
    },
    {
      name = "settings window toggle shows when hidden and hides when shown",
      run = function()
        local app = makeApp({
          settingsStore = Fakes.createSettingsStore(),
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })
        local settingsWindow = {
          shown = false,
          showCalls = 0,
          hideCalls = 0,
          isShown = function(self)
            return self.shown
          end,
          show = function(self)
            self.shown = true
            self.showCalls = self.showCalls + 1
          end,
          hide = function(self)
            self.shown = false
            self.hideCalls = self.hideCalls + 1
          end,
        }
        app:attachUi({
          requestRefresh = function() end,
        }, settingsWindow)

        app:toggleSettingsWindow()
        Assert.equal(settingsWindow.showCalls, 1)
        Assert.equal(settingsWindow.hideCalls, 0)
        app:toggleSettingsWindow()
        Assert.equal(settingsWindow.hideCalls, 1)
      end,
    },
    {
      name = "startup rewrites unresolved paired records as recoverable when recovery is enabled",
      run = function()
        local settingsStore = Fakes.createSettingsStore()
        settingsStore.values["tapshop.workspace.pairings"] = {
          [1] = {
            version = 2,
            kind = "paired",
            baseWindowId = 999,
            fingerprint = {
              bundleID = "com.apple.Safari",
              appName = "Safari",
              titleRaw = "Release Notes",
              titleNormalized = "release notes",
            },
          },
        }
        local app = makeApp({
          settings = settingsStore,
          appdata = settingsStore,
          windowService = Fakes.createWindowService(),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          toast = function() end,
        })

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "recoverable")
        Assert.equal(workspace.binding.fingerprint.bundleID, "com.apple.Safari")
        Assert.equal(settingsStore.values["tapshop.workspace.pairings"][1].kind, "recoverable")
      end,
    },
    {
      name = "profile pairings stay isolated across switches, unpairAll, and restart",
      run = function()
        FakeHs.install()
        local safari = FakeHs.makeWindow({
          id = 101,
          title = "Docs",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local mail = FakeHs.makeWindow({
          id = 202,
          title = "Inbox",
          bundleId = "com.apple.mail",
          appName = "Mail",
        })
        local store = Fakes.createSettingsStore()
        local app = makeApp({
          settings = store,
          appdata = store,
          windowService = Fakes.createWindowService({
            safari,
            mail,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          systemAudioService = {},
          toast = function() end,
        })

        Assert.equal(app:getProfileCount(), 12)
        Assert.equal(app:getActiveProfileId(), 1)
        Assert.equal(app:getWorkspaces()[1].name, "Profile 1 / Window 1")

        app:pairSlot(1, safari)
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 101)
        Assert.equal(store.values["tapshop.workspace.profiles"][1][1].baseWindowId, 101)

        Assert.truthy(app:activateProfile(2))
        Assert.equal(app:getActiveProfileId(), 2)
        Assert.falsy(app:getWorkspaces()[1]:isPaired())
        FakeHs.runScheduledTimers()
        Assert.equal(store.values["tapshop.workspace.activeProfileId"], 2)

        app:pairSlot(1, mail)
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 202)
        Assert.equal(store.values["tapshop.workspace.profiles"][2][1].baseWindowId, 202)

        Assert.truthy(app:activateProfile(1))
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 101)

        app:unpairAll()
        Assert.falsy(app:getWorkspaces()[1]:isPaired())
        Assert.truthy(store.values["tapshop.workspace.profiles"][2][1] ~= nil)

        Assert.truthy(app:activateProfile(2))
        Assert.equal(app:getWorkspaces()[1].binding.baseWindowId, 202)

        local restartStore = Fakes.createSettingsStore()
        restartStore.values["tapshop.workspace.activeProfileId"] = 2
        restartStore.values["tapshop.workspace.profiles"] = {
          [1] = {
            [1] = {
              version = 2,
              kind = "paired",
              baseWindowId = 101,
              fingerprint = {
                bundleID = "com.apple.Safari",
                appName = "Safari",
                titleRaw = "Docs",
                titleNormalized = "docs",
              },
            },
          },
          [2] = {
            [2] = {
              version = 2,
              kind = "paired",
              baseWindowId = 202,
              fingerprint = {
                bundleID = "com.apple.mail",
                appName = "Mail",
                titleRaw = "Inbox",
                titleNormalized = "inbox",
              },
            },
          },
        }
        local restartedApp = makeApp({
          settings = restartStore,
          appdata = restartStore,
          windowService = Fakes.createWindowService({
            safari,
            mail,
          }),
          youtubeService = Fakes.createNoopYoutubeService(),
          spotifyService = Fakes.createNoopSpotifyService(),
          systemAudioService = {},
          toast = function() end,
        })

        Assert.equal(restartedApp:getActiveProfileId(), 2)
        Assert.equal(restartedApp:getWorkspaces()[2].binding.baseWindowId, 202)
        Assert.truthy(restartedApp:activateProfile(1))
        Assert.equal(restartedApp:getWorkspaces()[1].binding.baseWindowId, 101)
      end,
    },
  },
}
