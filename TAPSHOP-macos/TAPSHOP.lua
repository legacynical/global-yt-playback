-- TAPSHOP (Hammerspoon port)
-- Requires: Accessibility permissions enabled for Hammerspoon

local function ensureModulePath()
  local source = debug.getinfo(1, "S").source
  local scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
  local scriptDir = scriptPath:match("^(.*)/[^/]+$")
  if not scriptDir then
    return
  end

  local modulePath = scriptDir .. "/?.lua;" .. scriptDir .. "/?/init.lua;"
  if not package.path:find(scriptDir, 1, true) then
    package.path = modulePath .. package.path
  end
end

ensureModulePath()

local Normalize = require("persistence.normalize")
local Settings = require("persistence.settings_store")
local AppData = require("persistence.appdata_store")
local AppState = require("state.app_state")
local HotkeyManager = require("hotkeys.manager")
local windowService = require("services.window_service")
local YoutubeService = require("services.youtube_service")
local SpotifyService = require("services.spotify_service")
local SystemAudioService = require("services.system_audio_service")
local DebugLogger = require("services.debug_logger")
local Toast = require("ui.toast")
local Icons = require("ui.icons")
local Popover = require("ui.popover.controller")
local SettingsWindow = require("ui.settings.controller")

local DEFAULT_CONFIG = {
  inputDelay = 0.05,
  minimizeThreshold = 2,
  focusWaitTimeout = 0.22,
  focusPollMicros = 10000,
  youtubeDirectDispatch = true,
  popoverAutoHideAfterAction = false,
  popoverAlwaysOnTop = true,
  popoverHideOnFullscreenWorkspace = true,
  popoverHidePairButtons = false,
  recoverClosedWindows = true,
  popoverBackgroundOpacity = 0.85,
  tapshopMsgBottomMargin = 100,
  tapshopMsgWidth = 760,
  tapshopMsgTextSize = 14,
  tapshopMsgMaxLines = 25,
  browserBundleIDs = {
    ["com.apple.Safari"] = true,
    ["com.google.Chrome"] = true,
    ["org.chromium.Chromium"] = true,
    ["com.brave.Browser"] = true,
    ["com.operasoftware.Opera"] = true,
    ["com.operasoftware.OperaGX"] = true,
    ["com.vivaldi.Vivaldi"] = true,
    ["org.mozilla.firefox"] = true,
    ["com.microsoft.edgemac"] = true,
    ["ru.yandex.desktop.yandex-browser"] = true,
    ["org.waterfoxproject.waterfox"] = true,
    ["org.torproject.torbrowser"] = true,
    ["com.maxthon.browser"] = true,
    ["com.maxthon.Maxthon"] = true,
    ["org.mozilla.seamonkey"] = true,
    ["com.hiddenreflex.epic"] = true,
    ["com.hiddenreflex.epicbrowser"] = true,
    ["com.flashpeak.Slimjet"] = true,
    ["com.comodo.dragon"] = true,
    ["com.avast.browser"] = true,
    ["com.srware.iron"] = true,
    ["org.kde.falkon"] = true,
    ["company.thebrowser.Browser"] = true,
    ["company.thebrowser.dia"] = true,
    ["ai.perplexity.comet"] = true,
    ["io.gitlab.librewolf-community.librewolf"] = true,
    ["one.ablaze.floorp"] = true,
  },
}

local function loadConfig()
  local cfg = Normalize.deepCopy(DEFAULT_CONFIG)
  cfg.popoverAutoHideAfterAction = Settings.getPopoverAutoHideAfterAction()
  cfg.popoverAlwaysOnTop = Settings.getPopoverAlwaysOnTop()
  cfg.popoverHideOnFullscreenWorkspace = Settings.getPopoverHideOnFullscreenWorkspace()
  cfg.popoverHidePairButtons = Settings.getPopoverHidePairButtons()
  cfg.recoverClosedWindows = Settings.getRecoverClosedWindows()
  cfg.popoverBackgroundOpacity = Settings.getPopoverBackgroundOpacity()
  return cfg
end

Settings.bootstrap()
AppData.bootstrap()

local debugLogger = DebugLogger.new()
_G.tapshop = _G.tapshop or {}
_G.tapshop.debug = debugLogger:commands()
debugLogger:consumeLaunchArm()
debugLogger:record("startup", "info", "bootstrap_started", "TAPSHOP bootstrap started", function()
  return {
    phase = "after_persistence_bootstrap",
  }
end)

local cfg = loadConfig()
local toast = Toast.new(cfg)
local youtubeService = YoutubeService.new(cfg, windowService, toast)
local spotifyService = SpotifyService.new()
local systemAudioService = SystemAudioService.new()

local app = AppState.new(cfg, {
  settings = Settings,
  appdata = AppData,
  windowService = windowService,
  youtubeService = youtubeService,
  spotifyService = spotifyService,
  systemAudioService = systemAudioService,
  debugLogger = debugLogger,
  toast = toast,
})

local previousShutdownCallback = hs.shutdownCallback
hs.shutdownCallback = function()
  local flushed, flushErr = pcall(function()
    app:flushActiveProfilePersistence()
  end)
  if not flushed and hs and type(hs.printf) == "function" then
    hs.printf("[tapshop-persistence] active profile shutdown flush failed: %s", tostring(flushErr))
  end

  if type(previousShutdownCallback) == "function" then
    local chained, chainedErr = pcall(previousShutdownCallback)
    if not chained and hs and type(hs.printf) == "function" then
      hs.printf("[tapshop] chained shutdown callback failed: %s", tostring(chainedErr))
    end
  end
end

local hotkeyManager = HotkeyManager.new(app, Settings)
app:attachHotkeyManager(hotkeyManager)

local popover = Popover.new(app, cfg, {
  appdata = AppData,
  windowService = windowService,
})
local settingsWindow = SettingsWindow.new(app, cfg, {
  appdata = AppData,
})

app:attachUi(popover, settingsWindow)

local function startWindowFilter()
  if app.windowFilter then
    return
  end

  local subscribedEvents = {
    hs.window.filter.windowFocused,
    hs.window.filter.windowTitleChanged,
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
    hs.window.filter.windowVisible,
    hs.window.filter.windowMinimized,
    hs.window.filter.windowUnminimized,
    hs.window.filter.windowFullscreened,
    hs.window.filter.windowUnfullscreened,
  }
  local windowFilter = hs.window.filter.new()
  windowFilter:subscribe(subscribedEvents, function(win, _, event)
    if event == hs.window.filter.windowFocused then
      app:handleActiveWindowChange(win)
    end
    app:handleWindowEvent(event, win)
  end)

  app.windowFilter = windowFilter
  debugLogger:record("startup", "debug", "window_filter_subscribed", "window filter subscribed", function()
    return {
      events = subscribedEvents,
    }
  end)
end

hotkeyManager:bindAll()
debugLogger:record("startup", "info", "hotkeys_bound", "hotkeys bound")

toast(Toast.message.status("TAPSHOP ready (Hammerspoon)", {
  imagePath = Icons.tapshopIconPath(),
}))
debugLogger:record("startup", "info", "app_ready", "TAPSHOP ready")

hs.timer.doAfter(0.05, startWindowFilter)

hs.timer.doAfter(0.25, function()
  if popover.warmStaticCaches then
    popover:warmStaticCaches()
  end
end)

hs.timer.doAfter(0.75, function()
  if settingsWindow.warmStaticCaches then
    settingsWindow:warmStaticCaches()
  end
end)

return app
