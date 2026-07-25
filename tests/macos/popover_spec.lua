local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TestEnv = require("test_env")

local function makeConfig(overrides)
  local cfg = {
    popoverAlwaysOnTop = true,
    popoverAutoHideAfterAction = false,
    popoverBackgroundOpacity = 0.85,
  }

  for key, value in pairs(overrides or {}) do
    cfg[key] = value
  end

  return cfg
end

local function makeAppData()
  return {
    getPopoverTopLeft = function()
      return nil
    end,
    getPopoverSize = function()
      return nil
    end,
    setPopoverTopLeft = function() end,
    setPopoverSize = function() end,
  }
end

local function makeWindow(id, title, appName)
  local app = FakeHs.makeApplication("com.test." .. tostring(id), appName or "App " .. tostring(id))
  return FakeHs.makeWindow({
    id = id,
    title = title,
    app = app,
  })
end

local function makeWindowService()
  return {
    getWindowInfo = function(win)
      local app = win and win:application() or nil
      return {
        id = win and win:id() or nil,
        title = win and win:title() or "",
        appName = app and app:name() or "",
        bundleID = app and app:bundleID() or nil,
      }
    end,
    getWindowById = function()
      return nil
    end,
    currentSpaceId = function()
      return 1
    end,
  }
end

local function makeApp(options)
  options = options or {}
  local app = {
    getWorkspaces = function()
      return options.workspaces or {}
    end,
    getWorkspaceRowModels = function()
      if options.getWorkspaceRowModels then
        return options.getWorkspaceRowModels()
      end
      local rows = {}
      for index, workspace in ipairs(options.workspaces or {}) do
        rows[#rows + 1] = {
          index = index,
          label = workspace.label or "[empty]",
          state = workspace.state or "empty",
          className = workspace.className or "unpaired",
          canPair = workspace.canPair ~= false,
          canUnpair = workspace.canUnpair == true,
          iconBundleID = workspace.iconBundleID,
          iconAppName = workspace.iconAppName,
          badgeText = workspace.badgeText,
        }
      end
      return rows
    end,
    getHotkeyUiState = function()
      if options.getHotkeyUiState then
        return options.getHotkeyUiState()
      end
      return options.hotkeyState or {
        rows = {},
        conflictsById = {},
        overrides = {},
      }
    end,
    handlePopoverAction = function(_, body)
      if options.handlePopoverAction then
        return options.handlePopoverAction(body)
      end
      return nil
    end,
    warmHotkeyUiCache = function(self, rendererFn)
      local state = self:getHotkeyUiState()
      if rendererFn then
        rendererFn(state.rows or {})
      end
    end,
  }
  app.hotkeyManager = options.hotkeyManager
  return app
end

local function installPanelStub(initiallyShown)
  local stub = {
    panel = nil,
    calls = {
      refresh = 0,
      markDirty = 0,
      show = 0,
      hide = 0,
      evaluateJavaScript = 0,
    },
    lastHtml = nil,
    lastJavaScript = nil,
    javaScriptCalls = {},
  }

  package.loaded["ui.webview_panel"] = {
    new = function(opts)
      local shown = initiallyShown == true
      local frame = { x = 0, y = 0, w = 500, h = 272 }
      local webview = {
        frame = function(_, nextFrame)
          if nextFrame then
            frame = nextFrame
            return webview
          end
          return frame
        end,
        topLeft = function(_, point)
          frame = {
            x = point.x,
            y = point.y,
            w = frame.w,
            h = frame.h,
          }
          return webview
        end,
        level = function()
          return webview
        end,
      }

      local panel = {}

      function panel:getWebview()
        return webview
      end

      function panel:isShown()
        return shown
      end

      function panel:hasContent()
        return stub.lastHtml ~= nil
      end

      function panel:markDirty()
        stub.calls.markDirty = stub.calls.markDirty + 1
      end

      function panel:refresh()
        stub.calls.refresh = stub.calls.refresh + 1
        stub.lastHtml = opts.buildHtml(panel)
      end

      function panel:show()
        shown = true
        stub.calls.show = stub.calls.show + 1
      end

      function panel:hide()
        shown = false
        stub.calls.hide = stub.calls.hide + 1
      end

      function panel:setLevel()
        return panel
      end

      function panel:evaluateJavaScript(script)
        stub.calls.evaluateJavaScript = stub.calls.evaluateJavaScript + 1
        stub.lastJavaScript = script
        stub.javaScriptCalls[#stub.javaScriptCalls + 1] = script
      end

      stub.panel = panel
      stub.opts = opts
      return panel
    end,
  }

  return stub
end

local function makePopover(options)
  TestEnv.reset({
    "app_config",
    "appdata",
    "ui.popover.controller",
    "ui.webview_panel",
  })

  local hs = FakeHs.install()
  hs.webview = {
    windowMasks = {
      borderless = 1,
    },
  }
  -- Preserve fake_hs eventtap.new; only ensure needed event type ids exist.
  hs.eventtap.event = hs.eventtap.event or {}
  hs.eventtap.event.types = hs.eventtap.event.types or {}
  hs.eventtap.event.types.keyDown = hs.eventtap.event.types.keyDown or 10
  hs.eventtap.event.types.mouseMoved = hs.eventtap.event.types.mouseMoved or 5
  hs.keycodes = {
    map = {
      escape = 53,
    },
  }

  local panelStub = installPanelStub(options and options.shown)
  local app = nil
  local appdata = nil
  local windowService = nil
  if options and options.appFactory then
    app, appdata, windowService = options.appFactory()
  else
    app = makeApp(options)
    appdata = makeAppData()
    windowService = makeWindowService()
  end
  local Popover = require("ui.popover.controller")

  local popover = Popover.new(
    app,
    makeConfig(options and options.cfg),
    {
      appdata = appdata,
      windowService = windowService,
    }
  )

  if app.attachUi then
    app:attachUi(popover, nil)
  end

  return popover, panelStub, app
end

return {
  name = "Popover",
  cases = {
    {
      name = "warming static caches does not create or show the webview",
      run = function()
        local popover, panelStub = makePopover({
          shown = false,
        })

        Assert.truthy(panelStub.panel ~= nil, "panel wrapper should exist after popover construction")
        Assert.equal(panelStub.calls.show, 0, "warming should not show the panel before warm runs")
        Assert.equal(panelStub.calls.refresh, 0, "warming should not refresh the panel before warm runs")
        popover:warmStaticCaches()
        Assert.equal(panelStub.calls.refresh, 0, "warming caches should not refresh the panel")
        Assert.equal(panelStub.calls.show, 0, "warming caches should not show the panel")
      end,
    },
    {
      name = "queues visible refreshes and flushes them on the next timer tick",
      run = function()
        local popover, panelStub = makePopover({
          shown = true,
        })

        popover:requestRefresh("window_event")

        Assert.equal(panelStub.calls.refresh, 0, "expected no inline refresh")

        FakeHs.runScheduledTimers()

        Assert.equal(panelStub.calls.refresh, 1, "expected queued refresh to hit the visible panel")
        Assert.equal(panelStub.calls.markDirty, 0, "expected visible panel refresh instead of markDirty")
      end,
    },
    {
      name = "active window updates use evaluateJavaScript instead of full HTML refresh",
      run = function()
        local win = FakeHs.makeWindow({
          id = 71,
          title = "Editor",
          bundleId = "com.test.editor",
          appName = "EditorApp",
        })
        local popover, panelStub = makePopover({
          shown = true,
        })
        panelStub.panel:refresh()
        local refreshBefore = panelStub.calls.refresh

        popover:requestActiveWindowUpdate(win)

        Assert.equal(panelStub.calls.refresh, refreshBefore, "header update must not rebuild HTML")
        Assert.equal(panelStub.calls.markDirty, 0)
        Assert.equal(panelStub.calls.evaluateJavaScript, 1)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "tapshopUpdateActiveWindow", 1, true))
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "Editor", 1, true))
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "com.test.editor", 1, true))
      end,
    },
    {
      name = "active window updates mark dirty when the panel is hidden",
      run = function()
        local win = FakeHs.makeWindow({
          id = 72,
          title = "Background",
          bundleId = "com.test.bg",
          appName = "BackgroundApp",
        })
        local popover, panelStub = makePopover({
          shown = false,
        })

        popover:requestActiveWindowUpdate(win)

        Assert.equal(panelStub.calls.refresh, 0)
        Assert.equal(panelStub.calls.evaluateJavaScript, 0)
        Assert.equal(panelStub.calls.markDirty, 1)
      end,
    },
    {
      name = "full refresh can carry the active window into the queued rebuild",
      run = function()
        local win = FakeHs.makeWindow({
          id = 73,
          title = "Space Shift",
          bundleId = "com.test.space",
          appName = "SpaceApp",
        })
        local popover, panelStub = makePopover({
          shown = true,
        })

        popover:requestRefresh("focused_space_change", win)
        FakeHs.runScheduledTimers()

        Assert.equal(panelStub.calls.refresh, 1)
        Assert.truthy(string.find(panelStub.lastHtml or "", "Space Shift", 1, true))
      end,
    },
    {
      name = "profile switch refreshes use the short interactive queue",
      run = function()
        local popover = makePopover({
          shown = true,
        })

        popover:requestRefresh("profile_switch")

        Assert.equal(#FakeHs.state().doAfterCalls, 1)
        Assert.equal(FakeHs.state().doAfterCalls[1].delay, 0.03)
      end,
    },
    {
      name = "profile exact validation republishes after the shallow interactive paint",
      run = function()
        local appdata = nil
        local windowService = nil
        local candidateCalls = 0
        local popover, panelStub, app = makePopover({
          shown = true,
          appFactory = function()
            appdata = Fakes.createSettingsStore()
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
            windowService = Fakes.createWindowService({ live })
            local baseCandidateWindows = windowService.candidateWindows
            windowService.candidateWindows = function()
              candidateCalls = candidateCalls + 1
              return baseCandidateWindows()
            end

            local AppState = TestEnv.freshRequire("state.app_state")
            local integratedApp = AppState.new({
              minimizeThreshold = 2,
              recoverClosedWindows = true,
              popoverAutoHideAfterAction = false,
              popoverHideOnFullscreenWorkspace = true,
            }, {
              settings = Fakes.createSettingsStore(),
              appdata = appdata,
              windowService = windowService,
              youtubeService = Fakes.createNoopYoutubeService(),
              spotifyService = Fakes.createNoopSpotifyService(),
              toast = function() end,
            })
            candidateCalls = 0
            windowService.getWindowSpacesCalls = {}
            appdata.calls = {}
            return integratedApp, appdata, windowService
          end,
        })

        Assert.truthy(popover ~= nil)
        Assert.truthy(app:activateProfile(2))
        Assert.equal(#FakeHs.state().doAfterCalls, 3)
        local validationTimerIndex = nil
        local refreshTimerIndex = nil
        local persistenceTimerFound = false
        for index, timer in ipairs(FakeHs.state().doAfterCalls) do
          if timer.delay == 0.20 then
            validationTimerIndex = index
          elseif timer.delay == 0.03 then
            refreshTimerIndex = index
          elseif timer.delay == 0.05 then
            persistenceTimerFound = true
          end
        end
        Assert.truthy(validationTimerIndex ~= nil)
        Assert.truthy(refreshTimerIndex ~= nil)
        Assert.truthy(persistenceTimerFound)

        FakeHs.runScheduledTimers()

        Assert.equal(panelStub.calls.refresh, 1)
        local hasIdlePersist = false
        local hasRepublish = false
        for _, timer in ipairs(FakeHs.state().doAfterCalls) do
          if timer.delay == 5.0 then
            hasIdlePersist = true
          elseif timer.delay == 0.03 then
            hasRepublish = true
          end
        end
        Assert.truthy(hasIdlePersist)
        Assert.truthy(hasRepublish)

        FakeHs.runScheduledTimers()
        Assert.equal(panelStub.calls.refresh, 2)
        Assert.equal(app:getWorkspaces()[1].binding.baseSpaceId, 2)
        Assert.truthy(string.find(panelStub.lastHtml or "", "paired-off-space", 1, true) ~= nil)
        Assert.truthy(string.find(panelStub.lastHtml or "", "P2", 1, true) ~= nil)
        Assert.equal(candidateCalls, 0)
      end,
    },
    {
      name = "marks hidden popovers dirty instead of refreshing them",
      run = function()
        local popover, panelStub = makePopover({
          shown = false,
        })

        popover:requestRefresh("window_event")
        FakeHs.runScheduledTimers()

        Assert.equal(panelStub.calls.refresh, 0)
        Assert.equal(panelStub.calls.markDirty, 1)
      end,
    },
    {
      name = "coalesces multiple refresh requests into one visible refresh",
      run = function()
        local popover, panelStub = makePopover({
          shown = true,
        })

        popover:requestRefresh("window_event")
        popover:requestRefresh("window_event")

        Assert.equal(#FakeHs.state().doAfterCalls, 2, "expected a cancelled timer plus the latest scheduled refresh")
        Assert.truthy(FakeHs.state().doAfterCalls[1].stopped, "expected the older refresh timer to be stopped")
        Assert.falsy(FakeHs.state().doAfterCalls[2].stopped, "expected the latest refresh timer to remain active")

        FakeHs.runScheduledTimers()

        Assert.equal(panelStub.calls.refresh, 1)
      end,
    },
    {
      name = "uses the latest active window when applying successive active-window updates",
      run = function()
        local winA = FakeHs.makeWindow({
          id = 101,
          title = "Alpha",
          bundleId = "com.test.alpha",
          appName = "Browser A",
        })
        local winB = FakeHs.makeWindow({
          id = 202,
          title = "Beta",
          bundleId = "com.test.beta",
          appName = "Browser B",
        })

        local popover, panelStub = makePopover({
          shown = true,
        })
        panelStub.panel:refresh()
        local refreshBefore = panelStub.calls.refresh

        popover:requestActiveWindowUpdate(winA)
        popover:requestActiveWindowUpdate(winB)

        Assert.equal(panelStub.calls.refresh, refreshBefore, "successive focus updates must stay header-only")
        Assert.equal(panelStub.calls.evaluateJavaScript, 2)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "Beta", 1, true) ~= nil)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "com.test.beta", 1, true) ~= nil)
      end,
    },
    {
      name = "renders the TAPSHOP brand icon in the header",
      run = function()
        local _, panelStub = makePopover({
          shown = true,
        })

        panelStub.panel:refresh()

        Assert.truthy(string.find(panelStub.lastHtml or "", 'class="title-brand-icon"', 1, true) ~= nil)
      end,
    },
    {
      name = "renders rows from derived workspace row models",
      run = function()
        local _, panelStub = makePopover({
          shown = true,
          getWorkspaceRowModels = function()
            return {
              {
                index = 1,
                label = "Video",
                state = "fullscreen",
                className = "paired-fullscreen",
                canUnpair = true,
                iconBundleID = nil,
                iconAppName = nil,
                badgeText = "FULL",
              },
            }
          end,
        })

        panelStub.panel:refresh()

        Assert.truthy(string.find(panelStub.lastHtml or "", "Video", 1, true) ~= nil)
        Assert.truthy(string.find(panelStub.lastHtml or "", "paired-fullscreen", 1, true) ~= nil)
        Assert.truthy(string.find(panelStub.lastHtml or "", "FULL", 1, true) ~= nil)
      end,
    },
    {
      name = "does not render slot icons for empty rows",
      run = function()
        local _, panelStub = makePopover({
          shown = true,
          getWorkspaceRowModels = function()
            return {
              {
                index = 1,
                label = "[empty]",
                state = "empty",
                className = "unpaired",
                canUnpair = false,
                iconBundleID = nil,
                iconAppName = nil,
                badgeText = nil,
              },
            }
          end,
        })

        panelStub.panel:refresh()

        Assert.truthy(string.find(panelStub.lastHtml or "", "[empty]", 1, true) ~= nil)
        Assert.falsy(string.find(panelStub.lastHtml or "", "<img class=\"slot-app-icon\"", 1, true) ~= nil)
      end,
    },
    {
      name = "forwards the settings-window toggle action to app state",
      run = function()
        local receivedAction = nil
        local _, panelStub = makePopover({
          shown = true,
          handlePopoverAction = function(body)
            receivedAction = body.action
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "toggleSettingsWindow",
          },
        })

        Assert.equal(receivedAction, "toggleSettingsWindow")
        Assert.equal(panelStub.calls.refresh, 0)
      end,
    },
    {
      name = "always-on-top toggleOrFocus shows when hidden and hides when shown",
      run = function()
        local popover, panelStub = makePopover({
          shown = false,
          cfg = {
            popoverAlwaysOnTop = true,
          },
        })

        popover:toggleOrFocus()
        Assert.equal(panelStub.calls.show, 1)
        Assert.equal(panelStub.calls.hide, 0)
        Assert.truthy(panelStub.panel:isShown())

        popover:toggleOrFocus()
        Assert.equal(panelStub.calls.hide, 1)
        Assert.equal(panelStub.calls.show, 1)
        Assert.falsy(panelStub.panel:isShown())
      end,
    },
    {
      name = "auto-hides successful pair and unpair actions when enabled",
      run = function()
        local received = nil
        local _, panelStub = makePopover({
          shown = true,
          cfg = {
            popoverAutoHideAfterAction = true,
          },
          handlePopoverAction = function(body)
            received = body
            return true
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "pair",
            slot = 1,
          },
        })
        Assert.equal(panelStub.calls.hide, 1)
        Assert.equal(received.action, "pair")
        Assert.equal(received.sourceWindow, nil)

        panelStub.panel:show()
        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "unpair",
            slot = 1,
          },
        })
        Assert.equal(panelStub.calls.hide, 2)

        panelStub.panel:show()
        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "unpairAll",
          },
        })
        Assert.equal(panelStub.calls.hide, 3)
      end,
    },
    {
      name = "does not auto-hide failed actions or when auto-hide is disabled",
      run = function()
        local _, panelStub = makePopover({
          shown = true,
          cfg = {
            popoverAutoHideAfterAction = true,
          },
          handlePopoverAction = function()
            return false
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "pair",
            slot = 1,
          },
        })
        Assert.equal(panelStub.calls.hide, 0)

        local _, disabledStub = makePopover({
          shown = true,
          cfg = {
            popoverAutoHideAfterAction = false,
          },
          handlePopoverAction = function()
            return true
          end,
        })
        disabledStub.opts.handleAction(disabledStub.panel, {
          body = {
            action = "pair",
            slot = 1,
          },
        })
        Assert.equal(disabledStub.calls.hide, 0)
      end,
    },
  },
}
