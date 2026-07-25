local Assert = require("assert")
local FakeHs = require("fake_hs")
local TestEnv = require("test_env")

local function makeConfig(overrides)
  local cfg = {
    popoverAlwaysOnTop = true,
    popoverAutoHideAfterAction = false,
    popoverHidePairButtons = false,
    popoverBackgroundOpacity = 0.85,
  }

  for key, value in pairs(overrides or {}) do
    cfg[key] = value
  end

  return cfg
end

local function makeAppData()
  local points = {}
  local sizes = {}

  return {
    getSettingsWindowTopLeft = function()
      return points.settings
    end,
    setSettingsWindowTopLeft = function(value)
      points.settings = {
        x = value.x,
        y = value.y,
      }
    end,
    getSettingsWindowSize = function()
      return sizes.settings
    end,
    setSettingsWindowSize = function(value)
      sizes.settings = {
        w = value.w,
        h = value.h,
      }
    end,
  }
end

local function makeApp(options)
  options = options or {}
  local app = {
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
      local frame = { x = 120, y = 80, w = 560, h = 420 }
      local level = nil
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
        level = function(_, nextLevel)
          if nextLevel ~= nil then
            level = nextLevel
            return webview
          end
          return level
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
        if opts.beforeShow then
          opts.beforeShow(panel, webview)
        end
        stub.calls.show = stub.calls.show + 1
        shown = true
        panel:refresh()
        if opts.afterShow then
          opts.afterShow(panel, webview)
        end
      end

      function panel:hide()
        if not shown then
          return
        end
        if opts.beforeHide then
          opts.beforeHide(panel, webview)
        end
        stub.calls.hide = stub.calls.hide + 1
        shown = false
      end

      function panel:setLevel(nextLevel)
        level = nextLevel
        return panel
      end

      function panel:evaluateJavaScript(script)
        stub.calls.evaluateJavaScript = stub.calls.evaluateJavaScript + 1
        stub.lastJavaScript = script
        stub.javaScriptCalls[#stub.javaScriptCalls + 1] = script
      end

      stub.panel = panel
      stub.opts = opts
      stub.webview = webview
      return panel
    end,
  }

  return stub
end

local function makeSettingsWindow(options)
  TestEnv.reset({
    "app_config",
    "appdata",
    "ui.settings.controller",
    "ui.webview_panel",
  })

  local hs = FakeHs.install()
  hs.webview = {
    windowMasks = {
      borderless = 1,
    },
  }

  local panelStub = installPanelStub(options and options.shown)
  local SettingsWindow = require("ui.settings.controller")

  local settingsWindow = SettingsWindow.new(
    makeApp(options),
    makeConfig(options and options.cfg),
    {
      appdata = makeAppData(),
    }
  )

  return settingsWindow, panelStub
end

return {
  name = "SettingsWindow",
  cases = {
    {
      name = "warming static caches does not create or show the webview",
      run = function()
        local hotkeyStateCalls = 0
        local settingsWindow, panelStub = makeSettingsWindow({
          shown = false,
          getHotkeyUiState = function()
            hotkeyStateCalls = hotkeyStateCalls + 1
            return {
              rows = {},
              conflictsById = {},
              overrides = {},
            }
          end,
        })

        Assert.truthy(panelStub.panel ~= nil, "panel wrapper should exist after settings-window construction")
        Assert.equal(panelStub.calls.show, 0)
        Assert.equal(panelStub.calls.refresh, 0)
        settingsWindow:warmStaticCaches()
        Assert.equal(panelStub.calls.refresh, 0)
        Assert.equal(panelStub.calls.show, 0)
        Assert.truthy(hotkeyStateCalls >= 1, "warming caches should prepare hotkey state in the background")
      end,
    },
    {
      name = "renders the TAPSHOP brand icon in the settings header",
      run = function()
        local _, panelStub = makeSettingsWindow({
          shown = true,
        })

        panelStub.panel:show()

        Assert.truthy(string.find(panelStub.lastHtml or "", 'class="settings-brand-icon"', 1, true) ~= nil)
      end,
    },
    {
      name = "switching to the hotkeys tab recomputes layout without refreshing the webview",
      run = function()
        local hotkeyStateCalls = 0
        local _, panelStub = makeSettingsWindow({
          shown = true,
          getHotkeyUiState = function()
            hotkeyStateCalls = hotkeyStateCalls + 1
            return {
              rows = {
                {
                  id = "youtube.playPause.k",
                  group = "YouTube",
                  label = "Play or Pause",
                  mods = { "cmd", "alt" },
                  key = "k",
                  isAssigned = true,
                  guarded = false,
                  isModified = false,
                  isUnavailable = false,
                  conflictIds = {},
                },
              },
              conflictsById = {},
              overrides = {},
            }
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "setSettingsTab",
            settingsTab = "hotkeys",
          },
        })

        Assert.equal(hotkeyStateCalls, 0)
        Assert.equal(panelStub.calls.refresh, 0)
        local sawLayoutRecompute = false
        for _, script in ipairs(panelStub.javaScriptCalls) do
          if string.find(script or "", "tapshopRecomputeBounds", 1, true) ~= nil then
            sawLayoutRecompute = true
            break
          end
        end
        Assert.truthy(sawLayoutRecompute)
      end,
    },
    {
      name = "failed hotkey updates push validation without refreshing the webview",
      run = function()
        local _, panelStub = makeSettingsWindow({
          shown = true,
          handlePopoverAction = function(body)
            if body.action == "updateHotkeyBinding" then
              return {
                ok = false,
                code = "conflict",
                ids = {
                  ["youtube.playPause.k"] = { "youtube.seekBack.j" },
                },
                message = "Shortcut conflicts with another TAPSHOP binding.",
              }
            end
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "setSettingsTab",
            settingsTab = "hotkeys",
          },
        })
        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "updateHotkeyBinding",
            id = "youtube.playPause.k",
            mods = { "cmd", "alt" },
            key = "j",
            settingsTab = "hotkeys",
            search = "play",
            scrollTop = 84,
          },
        })

        Assert.equal(panelStub.calls.refresh, 0)
        Assert.truthy(panelStub.calls.evaluateJavaScript >= 1)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "tapshopApplyValidation", 1, true) ~= nil)
      end,
    },
    {
      name = "successful hotkey updates notify commit without refreshing the webview",
      run = function()
        local _, panelStub = makeSettingsWindow({
          shown = true,
          hotkeyState = {
            rows = {
              {
                id = "youtube.playPause.k",
                group = "YouTube",
                label = "Play or Pause",
                mods = { "cmd", "alt" },
                key = "k",
                isAssigned = true,
                guarded = false,
                isModified = false,
                isUnavailable = false,
                conflictIds = {},
              },
            },
            conflictsById = {},
            overrides = {},
          },
          handlePopoverAction = function(body)
            if body.action == "updateHotkeyBinding" then
              return {
                ok = true,
              }
            end
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "setSettingsTab",
            settingsTab = "hotkeys",
          },
        })
        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "updateHotkeyBinding",
            id = "youtube.playPause.k",
            mods = { "cmd", "alt" },
            key = "p",
            settingsTab = "hotkeys",
            search = "play",
            scrollTop = 126,
          },
        })

        Assert.equal(panelStub.calls.refresh, 0)
        Assert.truthy(panelStub.calls.evaluateJavaScript >= 1)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "tapshopDidCommitHotkeyAction", 1, true) ~= nil)
        Assert.truthy(string.find(panelStub.lastJavaScript or "", "updateHotkeyBinding", 1, true) ~= nil)
      end,
    },
    {
      name = "closing settings clears search scroll and validation state before the next refresh",
      run = function()
        local settingsWindow, panelStub = makeSettingsWindow({
          shown = true,
          hotkeyState = {
            rows = {},
            conflictsById = {},
            overrides = {},
          },
          handlePopoverAction = function(body)
            if body.action == "updateHotkeyBinding" then
              return {
                ok = false,
                code = "conflict",
                ids = {},
                message = "Shortcut conflicts with another TAPSHOP binding.",
              }
            end
          end,
        })

        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "setSettingsTab",
            settingsTab = "hotkeys",
          },
        })
        panelStub.opts.handleAction(panelStub.panel, {
          body = {
            action = "updateHotkeyBinding",
            id = "youtube.playPause.k",
            settingsTab = "hotkeys",
            search = "play",
            scrollTop = 101,
          },
        })

        settingsWindow:hide()
        panelStub.panel:refresh()

        Assert.truthy(string.find(panelStub.lastHtml or "", 'data-settings-scroll-top="0"', 1, true) ~= nil)
        Assert.falsy(string.find(panelStub.lastHtml or "", 'value="play"', 1, true) ~= nil)
        Assert.falsy(string.find(panelStub.lastHtml or "", "Shortcut conflicts with another TAPSHOP binding.", 1, true) ~= nil)
      end,
    },
    {
      name = "toggleOrFocus hides only when the settings window is already focused",
      run = function()
        local settingsWindow, panelStub = makeSettingsWindow({
          shown = true,
        })

        panelStub.opts.windowCallback(panelStub.panel, "focusChange", nil, false)
        settingsWindow:toggleOrFocus()
        Assert.equal(panelStub.calls.hide, 0)
        Assert.equal(panelStub.calls.show, 1)

        panelStub.opts.windowCallback(panelStub.panel, "focusChange", nil, true)
        settingsWindow:toggleOrFocus()
        Assert.equal(panelStub.calls.hide, 1)
      end,
    },
  },
}
