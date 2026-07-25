local Fakes = {}
local FakeHs = require("fake_hs")

local function cloneTable(source)
  local out = {}
  for key, value in pairs(source or {}) do
    if type(value) == "table" then
      out[key] = cloneTable(value)
    else
      out[key] = value
    end
  end
  return out
end

function Fakes.createToast()
  local calls = {}

  local function toast(message, duration)
    calls[#calls + 1] = {
      message = message,
      duration = duration,
    }
  end

  return toast, calls
end

function Fakes.createSettingsStore()
  local HOTKEY_OVERRIDES_KEY = "tapshop.hotkeys.overrides"
  local POPOVER_AUTO_HIDE_KEY = "tapshop.popover.autoHideAfterAction"
  local POPOVER_ALWAYS_ON_TOP_KEY = "tapshop.popover.alwaysOnTop"
  local POPOVER_HIDE_ON_FULLSCREEN_KEY = "tapshop.popover.hideOnFullscreenWorkspace"
  local POPOVER_HIDE_PAIR_BUTTONS_KEY = "tapshop.popover.hidePairButtons"
  local RECOVER_CLOSED_WINDOWS_KEY = "tapshop.workspace.recoverClosedWindows"
  local POPOVER_BACKGROUND_OPACITY_KEY = "tapshop.popover.backgroundOpacity"
  local WORKSPACE_PAIRINGS_KEY = "tapshop.workspace.pairings"
  local WORKSPACE_PROFILES_KEY = "tapshop.workspace.profiles"
  local ACTIVE_PROFILE_ID_KEY = "tapshop.workspace.activeProfileId"
  local POPOVER_TOP_LEFT_KEY = "tapshop.popover.topLeft"
  local POPOVER_SIZE_KEY = "tapshop.popover.mainSize"
  local SETTINGS_TOP_LEFT_KEY = "tapshop.settings.topLeft"
  local SETTINGS_SIZE_KEY = "tapshop.settings.size"

  local store = {
    values = {},
    calls = {},
  }

  function store.setBoolean(key, value)
    store.values[key] = value
    store.calls[#store.calls + 1] = {
      kind = "boolean",
      key = key,
      value = value,
    }
  end

  function store.setOpacity(key, value)
    store.values[key] = value
    store.calls[#store.calls + 1] = {
      kind = "opacity",
      key = key,
      value = value,
    }
    return value
  end

  function store.getWindowPairings(key)
    if key ~= nil then
      return cloneTable(store.values[key] or {})
    end

    local profileId = store.getActiveProfileId()
    local profiles = store.getProfilesWindowPairings()
    if profiles[profileId] ~= nil then
      return cloneTable(profiles[profileId])
    end
    return cloneTable(store.values[WORKSPACE_PAIRINGS_KEY] or {})
  end

  function store.setWindowPairings(key, pairings)
    if pairings == nil then
      pairings = key
      key = nil
    end

    if key ~= nil then
      store.values[key] = cloneTable(pairings)
      store.calls[#store.calls + 1] = {
        kind = "windowPairings",
        key = key,
        value = cloneTable(pairings),
      }
      return
    end

    local profileId = store.getActiveProfileId()
    local profiles = store.getProfilesWindowPairings()
    profiles[profileId] = cloneTable(pairings)
    store.values[WORKSPACE_PROFILES_KEY] = profiles
    if profileId == 1 then
      store.values[WORKSPACE_PAIRINGS_KEY] = cloneTable(pairings)
    end
    store.calls[#store.calls + 1] = {
      kind = "windowPairings",
      key = WORKSPACE_PROFILES_KEY,
      value = cloneTable(pairings),
    }
  end

  function store.getActiveProfileId()
    local value = tonumber(store.values[ACTIVE_PROFILE_ID_KEY])
    if not value or value < 1 then
      return 1
    end
    return math.floor(value)
  end

  function store.setActiveProfileId(profileId)
    local normalized = tonumber(profileId)
    if not normalized or normalized < 1 then
      normalized = 1
    end
    normalized = math.floor(normalized)
    store.values[ACTIVE_PROFILE_ID_KEY] = normalized
    store.calls[#store.calls + 1] = {
      kind = "activeProfileId",
      value = normalized,
    }
    return normalized
  end

  function store.getProfilesWindowPairings()
    local profiles = store.values[WORKSPACE_PROFILES_KEY]
    if type(profiles) == "table" then
      return cloneTable(profiles)
    end

    local legacy = store.values[WORKSPACE_PAIRINGS_KEY]
    if type(legacy) == "table" and next(legacy) ~= nil then
      return {
        [1] = cloneTable(legacy),
      }
    end
    return {}
  end

  function store.setProfilesWindowPairings(profiles)
    store.values[WORKSPACE_PROFILES_KEY] = cloneTable(profiles)
    local profileOne = type(profiles) == "table" and profiles[1] or nil
    store.values[WORKSPACE_PAIRINGS_KEY] = cloneTable(profileOne or {})
    store.calls[#store.calls + 1] = {
      kind = "profilesWindowPairings",
      value = cloneTable(profiles),
    }
    return store.getProfilesWindowPairings()
  end

  function store.getProfileWindowPairings(profileId)
    local profiles = store.getProfilesWindowPairings()
    return cloneTable(profiles[tonumber(profileId)] or {})
  end

  function store.setProfileWindowPairings(profileId, pairings)
    local normalized = tonumber(profileId)
    if not normalized or normalized < 1 then
      normalized = 1
    end
    normalized = math.floor(normalized)
    local profiles = store.getProfilesWindowPairings()
    profiles[normalized] = cloneTable(pairings)
    return store.setProfilesWindowPairings(profiles)
  end

  function store.getHotkeyOverrides()
    return cloneTable(store.values[HOTKEY_OVERRIDES_KEY] or {})
  end

  function store.setHotkeyOverrides(overrides)
    store.values[HOTKEY_OVERRIDES_KEY] = cloneTable(overrides)
    store.calls[#store.calls + 1] = {
      kind = "hotkeyOverrides",
      value = cloneTable(overrides),
    }
  end

  function store.resetHotkeyOverrides()
    store.values[HOTKEY_OVERRIDES_KEY] = {}
    store.calls[#store.calls + 1] = {
      kind = "resetHotkeyOverrides",
    }
  end

  function store.setPopoverAutoHideAfterAction(value)
    return store.setBoolean(POPOVER_AUTO_HIDE_KEY, value == true)
  end

  function store.setPopoverAlwaysOnTop(value)
    return store.setBoolean(POPOVER_ALWAYS_ON_TOP_KEY, value == true)
  end

  function store.setPopoverHideOnFullscreenWorkspace(value)
    return store.setBoolean(POPOVER_HIDE_ON_FULLSCREEN_KEY, value == true)
  end

  function store.getPopoverHideOnFullscreenWorkspace()
    return store.values[POPOVER_HIDE_ON_FULLSCREEN_KEY] == true
  end

  function store.setPopoverHidePairButtons(value)
    return store.setBoolean(POPOVER_HIDE_PAIR_BUTTONS_KEY, value == true)
  end

  function store.setRecoverClosedWindows(value)
    return store.setBoolean(RECOVER_CLOSED_WINDOWS_KEY, value == true)
  end

  function store.setPopoverBackgroundOpacity(value)
    return store.setOpacity(POPOVER_BACKGROUND_OPACITY_KEY, value)
  end

  function store.getPopoverTopLeft()
    return cloneTable(store.values[POPOVER_TOP_LEFT_KEY])
  end

  function store.setPopoverTopLeft(value)
    store.values[POPOVER_TOP_LEFT_KEY] = cloneTable(value)
  end

  function store.getPopoverSize()
    return cloneTable(store.values[POPOVER_SIZE_KEY])
  end

  function store.setPopoverSize(value)
    store.values[POPOVER_SIZE_KEY] = cloneTable(value)
  end

  function store.getSettingsWindowTopLeft()
    return cloneTable(store.values[SETTINGS_TOP_LEFT_KEY])
  end

  function store.setSettingsWindowTopLeft(value)
    store.values[SETTINGS_TOP_LEFT_KEY] = cloneTable(value)
  end

  function store.getSettingsWindowSize()
    return cloneTable(store.values[SETTINGS_SIZE_KEY])
  end

  function store.setSettingsWindowSize(value)
    store.values[SETTINGS_SIZE_KEY] = cloneTable(value)
  end

  return store
end

function Fakes.createWindowService(initialWindows)
  local service = {
    windows = {},
    ensureFrontmostAsyncCalls = {},
    ensureFrontmostCalls = {}, -- legacy alias; prefer ensureFrontmostAsyncCalls
    requestFrontmostCalls = {},
    requestFrontmostAfterSpaceSwitchCalls = {},
    requestFrontmostInSpaceCalls = {},
    schedulePendingFrontmostCalls = {},
    cancelPendingFrontmostCalls = 0,
    gotoSpaceCalls = {},
    getWindowSpacesCalls = {},
    getWindowSpacesByIdCalls = {},
    _pendingFrontmostSerial = 0,
    ensureFrontmostAsyncResult = { ok = true, code = "focus_verified", windowId = nil },
    -- Legacy alias kept for older specs; prefer ensureFrontmostAsyncResult.
    ensureFrontmostResult = nil,
    requestFrontmostResult = { ok = true, code = "focus_requested", windowId = nil },
    requestFrontmostAfterSpaceSwitchResult = { ok = true, code = "focus_requested_after_space_switch", windowId = nil },
    requestFrontmostInSpaceResult = { ok = true, code = "space_switch_requested", windowId = nil, spaceId = nil },
    gotoSpaceResult = { ok = true, code = "space_switch_requested", spaceId = nil },
  }

  function service.addWindow(win)
    service.windows[win:id()] = win
  end

  function service.removeWindow(id)
    service.windows[id] = nil
  end

  function service.getWindowById(id)
    return service.windows[id]
  end

  function service.findWindowById(id)
    return service.getWindowById(id)
  end

  function service.frontmostWindow()
    return FakeHs.state().frontmostWindow
  end

  function service.frontmostWindowInCurrentSpace()
    return FakeHs.state().frontmostWindow
  end

  function service.currentSpaceId()
    return FakeHs.state().focusedSpace
  end

  function service.focusedSpaceId()
    return FakeHs.state().focusedSpace
  end

  function service.waitForSpace(spaceId)
    return FakeHs.state().activeSpace == spaceId
  end

  function service.displayTitle(win)
    if not win then
      return "[empty]"
    end

    local app = win:application()
    local prefix = app and app:name() or "App"
    local title = win:title() or ""
    if title == "" then
      title = "[untitled]"
    end
    return string.format("[%s] %s", prefix, title)
  end

  function service.windowTitle(win)
    if not win then
      return "[empty]"
    end

    local title = win:title() or ""
    if title == "" then
      return "[untitled]"
    end
    return title
  end

  function service.normalizeWindowTitle(title)
    local normalized = tostring(title or ""):lower()
    normalized = normalized:gsub("%s+", " ")
    normalized = normalized:match("^%s*(.-)%s*$") or ""
    return normalized
  end

  function service.pairingMetadata(win)
    if not win then
      return nil
    end

    local app = win:application()
    local title = win:title() or ""
    return {
      bundleID = app and app:bundleID() or "",
      appName = app and app:name() or "",
      titleRaw = title,
      titleNormalized = service.normalizeWindowTitle(title),
      displayTitle = service.displayTitle(win),
    }
  end

  function service.runtimeApplicationIdentity(win)
    if not win then
      return nil
    end

    local app = win:application()
    if not app then
      return nil
    end

    local bundleID = app.bundleID and app:bundleID() or nil
    local appName = app.name and app:name() or nil
    local identity = {
      pid = app.pid and app:pid() or nil,
      bundleID = type(bundleID) == "string" and bundleID:match("%S") and bundleID or nil,
      appName = type(appName) == "string" and appName:match("%S") and appName or nil,
    }
    if not identity.pid and not identity.bundleID and not identity.appName then
      return nil
    end
    return identity
  end

  function service.applicationIdentity(appName, appObject)
    local fallbackAppName = type(appName) == "string" and appName:match("%S") and appName or nil
    if not appObject then
      if fallbackAppName then
        return {
          pid = nil,
          bundleID = nil,
          appName = fallbackAppName,
        }
      end
      return nil
    end

    local bundleID = appObject.bundleID and appObject:bundleID() or nil
    local resolvedAppName = appObject.name and appObject:name() or nil
    local identity = {
      pid = appObject.pid and appObject:pid() or nil,
      bundleID = type(bundleID) == "string" and bundleID:match("%S") and bundleID or nil,
      appName = type(resolvedAppName) == "string" and resolvedAppName:match("%S") and resolvedAppName or fallbackAppName,
    }
    if not identity.pid and not identity.bundleID and not identity.appName then
      return nil
    end
    return identity
  end

  function service.isCandidateWindow(win)
    return win ~= nil and win:isVisible() and win:isStandard() and (win:title() or ""):match("%S") ~= nil
  end

  function service.isRecoveryCandidateWindow(win)
    return win ~= nil and win:isStandard() and (win:title() or ""):match("%S") ~= nil
  end

  local function nextPendingFrontmostToken()
    service._pendingFrontmostSerial = service._pendingFrontmostSerial + 1
    return service._pendingFrontmostSerial
  end

  local function resolveEnsureFrontmostResult(win)
    local result = service.ensureFrontmostAsyncResult or service.ensureFrontmostResult
    if not result then
      result = { ok = true, code = "focus_verified", windowId = win and win:id() or nil }
    end
    if result.windowId == nil and win then
      result.windowId = win:id()
    end
    return result
  end

  -- Production path: timer-based verified focus. Fake completes immediately with
  -- the configured result so unit tests stay deterministic without wall clocks.
  function service.ensureFrontmostAsync(win, cfg, onComplete)
    local token = nextPendingFrontmostToken()
    local call = {
      win = win,
      cfg = cfg,
      token = token,
    }
    service.ensureFrontmostAsyncCalls[#service.ensureFrontmostAsyncCalls + 1] = call
    service.ensureFrontmostCalls[#service.ensureFrontmostCalls + 1] = call

    local result = resolveEnsureFrontmostResult(win)
    if onComplete then
      onComplete(result, win, token)
    end
    return { ok = true, code = "ensure_frontmost_async_started", token = token }
  end

  function service.schedulePendingFrontmost(delay, token, callback)
    service.schedulePendingFrontmostCalls[#service.schedulePendingFrontmostCalls + 1] = {
      delay = delay,
      token = token,
    }
    if token ~= service._pendingFrontmostSerial then
      return false
    end
    if type(callback) ~= "function" then
      return false
    end
    hs.timer.doAfter(delay or 0, callback)
    return true
  end

  function service.cancelPendingFrontmostRequest()
    service.cancelPendingFrontmostCalls = service.cancelPendingFrontmostCalls + 1
    nextPendingFrontmostToken()
  end

  function service.requestFrontmost(win, cfg)
    service.requestFrontmostCalls[#service.requestFrontmostCalls + 1] = {
      win = win,
      cfg = cfg,
    }
    if service.requestFrontmostResult and service.requestFrontmostResult.windowId == nil and win then
      service.requestFrontmostResult.windowId = win:id()
    end
    return service.requestFrontmostResult
  end

  function service.requestFrontmostAfterSpaceSwitch(win, cfg)
    service.requestFrontmostAfterSpaceSwitchCalls[#service.requestFrontmostAfterSpaceSwitchCalls + 1] = {
      win = win,
      cfg = cfg,
    }
    if service.requestFrontmostAfterSpaceSwitchResult
      and service.requestFrontmostAfterSpaceSwitchResult.windowId == nil
      and win then
      service.requestFrontmostAfterSpaceSwitchResult.windowId = win:id()
    end
    return service.requestFrontmostAfterSpaceSwitchResult
  end

  function service.requestFrontmostInSpace(target, spaceId, cfg, onComplete)
    local windowId = type(target) == "number" and target or target and target:id() or nil
    service.requestFrontmostInSpaceCalls[#service.requestFrontmostInSpaceCalls + 1] = {
      windowId = windowId,
      spaceId = spaceId,
      cfg = cfg,
    }
    service.gotoSpaceCalls[#service.gotoSpaceCalls + 1] = {
      spaceId = spaceId,
      cfg = cfg,
    }

    local result = service.requestFrontmostInSpaceResult
      or { ok = true, code = "space_switch_requested", windowId = windowId, spaceId = spaceId }
    result.windowId = windowId
    result.spaceId = spaceId
    if result.ok ~= false then
      FakeHs.setActiveSpace(spaceId)
      local win = service.getWindowById(windowId)
      if win then
        service.requestFrontmostAfterSpaceSwitchCalls[#service.requestFrontmostAfterSpaceSwitchCalls + 1] = {
          win = win,
          cfg = cfg,
        }
        if onComplete then
          onComplete({
            ok = true,
            code = "focus_verified_after_space_switch",
            windowId = windowId,
            spaceId = spaceId,
          }, win)
        end
      end
    end
    return result
  end

  function service.gotoSpace(spaceId, cfg)
    service.gotoSpaceCalls[#service.gotoSpaceCalls + 1] = {
      spaceId = spaceId,
      cfg = cfg,
    }
    local result = service.gotoSpaceResult or { ok = true, code = "space_switch_verified", spaceId = spaceId }
    if result.spaceId == nil then
      result.spaceId = spaceId
    end
    if result.ok ~= false then
      FakeHs.setActiveSpace(spaceId)
      if result.code == nil or result.code == "space_switch_requested" then
        result.code = "space_switch_verified"
      end
    end
    service.gotoSpaceResult = result
    return result
  end

  function service.getWindowSpaces(win)
    service.getWindowSpacesCalls[#service.getWindowSpacesCalls + 1] = {
      win = win,
    }
    return win and win:spaceIds() or {}
  end

  function service.getWindowSpacesById(windowId)
    service.getWindowSpacesByIdCalls[#service.getWindowSpacesByIdCalls + 1] = {
      windowId = windowId,
    }
    local win = service.windows[windowId]
    return win and win:spaceIds() or {}
  end

  function service.getPrimarySpaceForWindow(win)
    local spaceIds = service.getWindowSpaces(win)
    for _, spaceId in ipairs(spaceIds) do
      if service.isFullscreenSpace(spaceId) then
        return spaceId
      end
    end
    return spaceIds[1]
  end

  function service.getSpaceType(spaceId)
    return FakeHs.state().spaceTypes[spaceId] or "user"
  end

  function service.isFullscreenSpace(spaceId)
    return service.getSpaceType(spaceId) == "fullscreen"
  end

  function service.isWindowFullscreen(win)
    return win ~= nil and win:isFullScreen()
  end

  function service.windowIsInSpace(win, spaceId)
    if not win or not spaceId then
      return false
    end
    for _, candidate in ipairs(service.getWindowSpaces(win)) do
      if candidate == spaceId then
        return true
      end
    end
    return false
  end

  function service.bestEffortFrontmostWindowInSpace(spaceId)
    local frontmost = FakeHs.state().frontmostWindow
    if service.windowIsInSpace(frontmost, spaceId) then
      return frontmost
    end
    return nil
  end

  function service.windowStillExists(win)
    return win ~= nil and service.windows[win:id()] ~= nil
  end

  function service.getWindowInfo(win)
    return {
      id = win and win:id() or nil,
      title = win and win:title() or nil,
      appName = win and win:application() and win:application():name() or nil,
      bundleID = win and win:application() and win:application():bundleID() or nil,
    }
  end

  function service.candidateWindows()
    local windows = {}
    for _, win in pairs(service.windows) do
      if service.isCandidateWindow(win) then
        windows[#windows + 1] = win
      end
    end
    table.sort(windows, function(left, right)
      return left:id() < right:id()
    end)
    return windows
  end

  for _, win in ipairs(initialWindows or {}) do
    service.addWindow(win)
  end

  return service
end

function Fakes.createNoopSpotifyService()
  return {
    previous = function() end,
    next = function() end,
    playPause = function() end,
    seekBack = function() end,
    seekForward = function() end,
    volumeDown = function() end,
    volumeUp = function() end,
    toggleLike = function() end,
    toggleSystemMute = function() end,
  }
end

function Fakes.createNoopYoutubeService()
  return {
    getTargetId = function()
      return nil
    end,
    handleDestroyedWindowId = function() end,
    handleWindowCandidate = function() end,
    sendCommand = function()
      return {
        ok = true,
        code = "noop",
        focusResult = nil,
      }
    end,
  }
end

return Fakes
