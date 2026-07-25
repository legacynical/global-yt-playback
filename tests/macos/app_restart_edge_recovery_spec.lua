local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TestEnv = require("test_env")

local function makeConfig()
  return {
    minimizeThreshold = 2,
    popoverAutoHideAfterAction = false,
    recoverClosedWindows = true,
    focusWaitTimeout = 0.05,
    focusPollMicros = 1000,
  }
end

local function makeApp(windowService, overrides)
  overrides = overrides or {}
  TestEnv.reset({
    "state.workspace",
    "state.slot_record",
    "state.slot_row",
    "state.app_state",
  })
  local AppState = require("state.app_state")
  return AppState.new(makeConfig(), {
    settings = overrides.settings or Fakes.createSettingsStore(),
    appdata = overrides.appdata or Fakes.createSettingsStore(),
    windowService = windowService,
    youtubeService = overrides.youtubeService or Fakes.createNoopYoutubeService(),
    spotifyService = Fakes.createNoopSpotifyService(),
    toast = function() end,
  })
end

local function makeWindow(opts)
  return FakeHs.makeWindow(opts)
end

return {
  name = "App Restart Edge Recovery",
  cases = {
    {
      name = "restores a minimized child window after app restart",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 401,
          title = "Cursor Notes",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local restoredMinimized = makeWindow({
          id = 402,
          title = "Cursor Notes",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          minimized = true,
          visible = false,
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(401)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        windowService.addWindow(restoredMinimized)

        app:handleWindowEvent(hs.window.filter.windowCreated, restoredMinimized)

        local workspace = app:getWorkspaces()[1]
        local row = app:getWorkspaceRowModels()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 402)
        Assert.equal(row.state, "minimized")
        Assert.equal(row.label, "Cursor Notes")
      end,
    },
    {
      name = "restores an off-space child window after app restart",
      run = function()
        FakeHs.install()
        FakeHs.setFocusedSpace(1)
        local original = makeWindow({
          id = 421,
          title = "Cursor Detached",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          spaceIds = { 1 },
        })
        local restoredOffSpace = makeWindow({
          id = 422,
          title = "Cursor Detached",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(421)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        windowService.addWindow(restoredOffSpace)

        app:handleWindowEvent(hs.window.filter.windowCreated, restoredOffSpace)

        local workspace = app:getWorkspaces()[1]
        local row = app:getWorkspaceRowModels()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 422)
        Assert.equal(workspace.binding.baseSpaceId, 2)
        Assert.equal(row.state, "off_space")
        Assert.equal(row.label, "Cursor Detached")
      end,
    },
    {
      name = "windowCreated does not relink a still-valid paired slot",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 441,
          title = "Cursor Still Paired",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local duplicate = makeWindow({
          id = 442,
          title = "Cursor Still Paired",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          minimized = true,
          visible = false,
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.addWindow(duplicate)
        windowService.getWindowSpacesByIdCalls = {}

        app:handleWindowEvent(hs.window.filter.windowCreated, duplicate)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 441)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
      end,
    },
    {
      name = "windowCreated promotes a matching stale paired slot after exact validation fails",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 461,
          title = "Cursor Stale Paired",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local replacement = makeWindow({
          id = 462,
          title = "Cursor Stale Paired",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(461)
        windowService.addWindow(replacement)

        app:handleWindowEvent(hs.window.filter.windowCreated, replacement)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 462)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 1)
        Assert.equal(windowService.getWindowSpacesByIdCalls[1].windowId, 461)
      end,
    },
    {
      name = "windowCreated promotes when a recycled id belongs to a different app without Spaces",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 471,
          title = "Cursor Recycled Id",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local usurper = makeWindow({
          id = 471,
          title = "Unrelated",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local replacement = makeWindow({
          id = 472,
          title = "Cursor Recycled Id",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(471)
        windowService.addWindow(usurper)
        windowService.addWindow(replacement)
        windowService.getWindowSpacesByIdCalls = {}

        app:handleWindowEvent(hs.window.filter.windowCreated, replacement)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 472)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
      end,
    },
    {
      name = "windowCreated demotes inactive stale paired slots without Spaces or promote",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 481,
          title = "Cursor Inactive Stale",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local replacement = makeWindow({
          id = 482,
          title = "Cursor Inactive Stale",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)

        Assert.truthy(app:activateProfile(2))
        app:pairSlot(1, original)
        Assert.truthy(app:activateProfile(1))

        windowService.removeWindow(481)
        windowService.addWindow(replacement)
        windowService.getWindowSpacesByIdCalls = {}

        app:handleWindowEvent(hs.window.filter.windowCreated, replacement)

        local inactive = app:_getWorkspace(1, 2)
        Assert.equal(inactive.binding.kind, "recoverable")
        Assert.equal(inactive.binding.baseWindowId, nil)
        Assert.equal(inactive.binding.fingerprint.titleNormalized, "cursor inactive stale")
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
        Assert.equal(app:getWorkspaces()[1].binding.kind, "empty")
      end,
    },
    {
      name = "non-created concrete window events can relink recoverable slots",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 443,
          title = "Cursor Recoverable",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local restored = makeWindow({
          id = 444,
          title = "Cursor Recoverable",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local windowService = Fakes.createWindowService({
          original,
          restored,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(443)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)

        app:handleWindowEvent(hs.window.filter.windowTitleChanged, restored)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 444)
      end,
    },
    {
      name = "unrelated window events do not probe missing paired ids",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 451,
          title = "Cursor Missing",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local unrelated = makeWindow({
          id = 452,
          title = "Other Window",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })
        local windowService = Fakes.createWindowService({
          original,
          unrelated,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(451)
        windowService.getWindowSpacesByIdCalls = {}

        app:handleWindowEvent(hs.window.filter.windowTitleChanged, unrelated)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 451)
        Assert.equal(#windowService.getWindowSpacesByIdCalls, 0)
      end,
    },
    {
      name = "restores a fullscreen child window after app restart",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 411,
          title = "Cursor Fullscreen",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
        })
        local restoredFullscreen = makeWindow({
          id = 412,
          title = "Cursor Fullscreen",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          fullscreen = true,
          spaceIds = { 7 },
        })
        local windowService = Fakes.createWindowService({
          original,
        })
        local app = makeApp(windowService)
        FakeHs.setSpaceType(7, "fullscreen")

        app:pairSlot(1, original)
        windowService.removeWindow(411)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        windowService.addWindow(restoredFullscreen)

        app:handleWindowEvent(hs.window.filter.windowCreated, restoredFullscreen)

        local workspace = app:getWorkspaces()[1]
        local row = app:getWorkspaceRowModels()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 412)
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 412)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 7)
        Assert.equal(row.state, "fullscreen")
        Assert.equal(row.badgeText, "FULL")
      end,
    },
    {
      name = "recoverable slot activation can re-pair the frontmost window",
      run = function()
        FakeHs.install()
        local original = makeWindow({
          id = 420,
          title = "Cursor Recoverable Activation",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          pid = 8300,
        })
        local frontmost = makeWindow({
          id = 422,
          title = "Cursor Settings - tapshop",
          bundleId = "com.todesktop.230313mzl4w4u92",
          appName = "Cursor",
          pid = 8301,
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({
          original,
          frontmost,
        })
        local app = makeApp(windowService)

        app:pairSlot(1, original)
        windowService.removeWindow(420)
        app:handleWindowEvent(hs.window.filter.windowDestroyed, original)
        FakeHs.setFrontmostWindow(frontmost)

        app:activateSlot(1)

        local workspace = app:getWorkspaces()[1]
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 422)
        Assert.equal(workspace.binding.fingerprint.titleRaw, "Cursor Settings - tapshop")
      end,
    },
  },
}
