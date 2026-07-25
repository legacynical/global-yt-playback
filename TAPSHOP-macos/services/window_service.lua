local WindowService = {}
local pendingFrontmostTimer = nil
local pendingFrontmostSerial = 0

local function normalizeWindowTitle(title)
  local normalized = tostring(title or ""):lower()
  normalized = normalized:gsub("%s+", " ")
  normalized = normalized:match("^%s*(.-)%s*$") or ""
  return normalized
end

local function focusResult(ok, code, win)
  return {
    ok = ok,
    code = code,
    windowId = win and win:id() or nil,
  }
end

local function isFrontmost(win)
  if not win then
    return false
  end

  local checked, frontmost = pcall(hs.window.frontmostWindow)
  if not checked or not frontmost then
    return false
  end
  local compared, matches = pcall(function()
    return frontmost:id() == win:id()
  end)
  return compared and matches or false
end

local function stopPendingFrontmostTimer()
  if pendingFrontmostTimer then
    pendingFrontmostTimer:stop()
    pendingFrontmostTimer = nil
  end
end

local function invalidatePendingFrontmostRequest()
  pendingFrontmostSerial = pendingFrontmostSerial + 1
  stopPendingFrontmostTimer()
  return pendingFrontmostSerial
end

local function schedulePendingFrontmostRequest(delay, token, callback)
  pendingFrontmostTimer = hs.timer.doAfter(delay, function()
    pendingFrontmostTimer = nil
    if token ~= pendingFrontmostSerial then
      return
    end
    callback()
  end)
end

local function dismissMissionControl()
  if not hs.spaces or type(hs.spaces.closeMissionControl) ~= "function" then
    return false
  end
  return pcall(hs.spaces.closeMissionControl)
end

local function windowIdForTarget(target)
  if type(target) == "number" then
    return target
  end
  if target and type(target.id) == "function" then
    return target:id()
  end
  return nil
end

local function requestFrontmostImpl(win)
  local app = win:application()
  if app and app:isHidden() then
    app:unhide()
  end
  if win:isMinimized() then
    win:unminimize()
  end

  -- hs.window:focus() already makes the app frontmost and the target window main.
  win:focus()
end

local function focusPollIntervalSec(cfg)
  cfg = cfg or {}
  if type(cfg.focusPollInterval) == "number" and cfg.focusPollInterval > 0 then
    return cfg.focusPollInterval
  end
  local micros = cfg.focusPollMicros
  if type(micros) == "number" and micros > 0 then
    return micros / 1e6
  end
  return 0.01
end

function WindowService.getWindowInfo(win)
  win = win or hs.window.frontmostWindow()
  if not win then
    return nil
  end

  local app = win:application()
  return {
    title = win:title() or "",
    id = win:id(),
    appName = app and app:name() or "",
    processName = app and app:name() or "",
    pid = app and app:pid() or nil,
    bundleID = app and app:bundleID() or "",
  }
end

function WindowService.candidateWindows()
  local wins = hs.window.orderedWindows()
  local out = {}
  for _, win in ipairs(wins) do
    if WindowService.isCandidateWindow(win) then
      out[#out + 1] = win
    end
  end
  return out
end

function WindowService.getWindowById(id)
  if not id then
    return nil
  end
  return hs.window.get(id)
end

function WindowService.displayTitle(win)
  if not win then
    return "[empty]"
  end

  local app = win:application()
  local prefix = app and app:name() or "App"
  local title = WindowService.windowTitle(win)

  return "[" .. prefix .. "] " .. title
end

function WindowService.windowTitle(win)
  if not win then
    return "[empty]"
  end

  local title = win:title() or ""
  if title == "" then
    return "[untitled]"
  end

  return title
end

function WindowService.normalizeWindowTitle(title)
  return normalizeWindowTitle(title)
end

function WindowService.pairingMetadata(win)
  if not win then
    return nil
  end

  local app = win:application()
  local title = win:title() or ""
  return {
    bundleID = app and app:bundleID() or "",
    appName = app and app:name() or "",
    titleRaw = title,
    titleNormalized = normalizeWindowTitle(title),
    displayTitle = WindowService.displayTitle(win),
  }
end

function WindowService.isCandidateWindow(win)
  if not win then
    return false
  end

  return win:isVisible() and win:isStandard() and (win:title() or ""):match("%S") ~= nil
end

function WindowService.isRecoveryCandidateWindow(win)
  if not win then
    return false
  end

  return win:isStandard() and (win:title() or ""):match("%S") ~= nil
end

-- Request frontmost status opportunistically for slot-style flows.
-- This path should not block the hotkey/UI loop on verification.
function WindowService.requestFrontmost(win)
  invalidatePendingFrontmostRequest()
  if not win then
    return focusResult(false, "missing_window", nil)
  end

  if isFrontmost(win) then
    return focusResult(true, "already_frontmost", win)
  end

  requestFrontmostImpl(win)
  return focusResult(true, "focus_requested", win)
end

-- Verified focus for callers that must confirm before sending input.
-- Polls with timers so the hotkey/UI thread is never blocked on usleep.
-- onComplete(result, win, token); use schedulePendingFrontmost for follow-up
-- work that must cancel with this pending focus generation.
function WindowService.ensureFrontmostAsync(win, cfg, onComplete)
  cfg = cfg or {}
  local token = invalidatePendingFrontmostRequest()

  local function finish(result, resolved)
    if token ~= pendingFrontmostSerial then
      return
    end
    if onComplete then
      pcall(onComplete, result, resolved, token)
    end
  end

  if not win then
    finish(focusResult(false, "missing_window", nil), nil)
    return { ok = true, code = "ensure_frontmost_async_started", token = token }
  end

  if isFrontmost(win) then
    finish(focusResult(true, "already_frontmost", win), win)
    return { ok = true, code = "ensure_frontmost_async_started", token = token }
  end

  local requested = pcall(requestFrontmostImpl, win)
  if not requested then
    finish(focusResult(false, "focus_request_failed", win), win)
    return { ok = true, code = "ensure_frontmost_async_started", token = token }
  end

  local timeoutSec = cfg.focusWaitTimeout or 0.22
  local pollInterval = focusPollIntervalSec(cfg)
  local deadline = hs.timer.secondsSinceEpoch() + timeoutSec

  local function tick()
    if token ~= pendingFrontmostSerial then
      return
    end
    if not WindowService.windowStillExists(win) then
      finish(focusResult(false, "window_unavailable", win), win)
      return
    end
    if isFrontmost(win) then
      finish(focusResult(true, "focus_verified", win), win)
      return
    end
    if hs.timer.secondsSinceEpoch() >= deadline then
      finish(focusResult(false, "focus_timeout", win), win)
      return
    end
    schedulePendingFrontmostRequest(pollInterval, token, tick)
  end

  schedulePendingFrontmostRequest(pollInterval, token, tick)
  return { ok = true, code = "ensure_frontmost_async_started", token = token }
end

function WindowService.schedulePendingFrontmost(delay, token, callback)
  if token ~= pendingFrontmostSerial then
    return false
  end
  schedulePendingFrontmostRequest(delay or 0, token, callback)
  return true
end

function WindowService.focusedSpaceId()
  local focusedSpaceFn = hs.spaces and hs.spaces.focusedSpace
  if type(focusedSpaceFn) == "function" then
    local ok, focusedSpaceId = pcall(focusedSpaceFn)
    if ok and type(focusedSpaceId) == "number" then
      return focusedSpaceId
    end
  end

  local screen = hs.screen.mainScreen()
  return hs.spaces.activeSpaceOnScreen(screen)
end

function WindowService.currentSpaceId()
  return WindowService.focusedSpaceId()
end

function WindowService.getWindowSpaces(win)
  if not win then
    return {}
  end
  return hs.spaces.windowSpaces(win) or {}
end

function WindowService.getWindowSpacesById(windowId)
  if type(windowId) ~= "number" or windowId < 1 or windowId % 1 ~= 0 then
    return {}
  end

  local ok, spaceIds = pcall(hs.spaces.windowSpaces, windowId)
  if not ok or type(spaceIds) ~= "table" then
    return {}
  end

  return spaceIds
end

function WindowService.getSpaceType(spaceId)
  if not spaceId then
    return nil
  end
  return hs.spaces.spaceType(spaceId)
end

function WindowService.isFullscreenSpace(spaceId)
  return WindowService.getSpaceType(spaceId) == "fullscreen"
end

function WindowService.isWindowFullscreen(win)
  if not win then
    return false
  end

  local ok, isFullscreen = pcall(function()
    return win:isFullScreen()
  end)
  return ok and isFullscreen == true
end

function WindowService.getPrimarySpaceForWindow(win)
  local ok, spaceIdsOrErr = pcall(WindowService.getWindowSpaces, win)
  if not ok then
    return nil
  end

  local spaceIds = spaceIdsOrErr
  if type(spaceIds) ~= "table" or #spaceIds == 0 then
    return nil
  end

  for _, spaceId in ipairs(spaceIds) do
    if WindowService.isFullscreenSpace(spaceId) then
      return spaceId
    end
  end
  return spaceIds[1]
end

function WindowService.windowIsInSpace(win, spaceId)
  if not win or not spaceId then
    return false
  end
  for _, candidate in ipairs(WindowService.getWindowSpaces(win)) do
    if candidate == spaceId then
      return true
    end
  end
  return false
end

function WindowService.windowStillExists(win)
  return win ~= nil and hs.window.get(win:id()) ~= nil
end

function WindowService.frontmostWindowInCurrentSpace()
  local frontmost = hs.window.frontmostWindow()
  if not frontmost then
    return nil
  end
  local activeSpaceId = WindowService.currentSpaceId()
  if not activeSpaceId then
    return nil
  end
  if WindowService.windowIsInSpace(frontmost, activeSpaceId) then
    return frontmost
  end
  return nil
end

function WindowService.bestEffortFrontmostWindowInSpace(spaceId)
  if not spaceId then
    return nil
  end
  if WindowService.currentSpaceId() ~= spaceId then
    return nil
  end

  local frontmost = WindowService.frontmostWindowInCurrentSpace()
  if frontmost and WindowService.isWindowFullscreen(frontmost) then
    return frontmost
  end
  return nil
end

function WindowService.gotoSpace(spaceId, cfg)
  if not spaceId then
    return { ok = false, code = "missing_space_id", spaceId = nil }
  end
  local called, initiated, initiateError = pcall(hs.spaces.gotoSpace, spaceId)
  if not called or initiated == nil or initiated == false then
    dismissMissionControl()
    return {
      ok = false,
      code = "space_switch_not_initiated",
      error = called and initiateError or initiated,
      spaceId = spaceId,
    }
  end
  return { ok = true, code = "space_switch_requested", spaceId = spaceId }
end

-- Space transitions are asynchronous Mission Control operations. Keep one
-- exact target pending until the destination settles and focus is confirmed.
-- Poll with adaptive backoff and dismiss Mission Control on settle (plus one
-- focus-failure retry), not on every resolve/focus tick.
function WindowService.requestFrontmostInSpace(target, spaceId, cfg, onComplete)
  local windowId = windowIdForTarget(target)
  if not windowId then
    return { ok = false, code = "missing_window_id", windowId = nil, spaceId = spaceId }
  end
  if not spaceId then
    return { ok = false, code = "missing_space_id", windowId = windowId, spaceId = nil }
  end

  cfg = cfg or {}
  local token = invalidatePendingFrontmostRequest()
  local switchResult = WindowService.gotoSpace(spaceId, cfg)
  if not switchResult.ok then
    switchResult.windowId = windowId
    return switchResult
  end

  local pollInterval = cfg.spaceSwitchPollInterval or 0.05
  local pollMaxInterval = cfg.spaceSwitchPollMaxInterval or 0.20
  local pollBackoff = cfg.spaceSwitchPollBackoff or 1.5
  local maxSpaceAttempts = cfg.spaceSwitchMaxAttempts or 60
  local focusDelay = cfg.fullscreenSpaceSwitchDelay or 0.20
  local focusVerifyDelay = cfg.spaceSwitchFocusVerifyDelay or 0.05
  local maxResolveAttempts = cfg.spaceSwitchWindowResolveAttempts or 20
  local maxFocusAttempts = cfg.spaceSwitchFocusAttempts or 4
  local spaceAttempts = 0
  local resolveAttempts = 0
  local focusAttempts = 0
  local settleDelay = pollInterval
  local resolveDelay = pollInterval
  local focusFailDismissUsed = false

  local function nextBackoffDelay(current)
    local nextDelay = current * pollBackoff
    if nextDelay > pollMaxInterval then
      return pollMaxInterval
    end
    if nextDelay < pollInterval then
      return pollInterval
    end
    return nextDelay
  end

  local function complete(result, win)
    if token ~= pendingFrontmostSerial then
      return
    end
    stopPendingFrontmostTimer()
    if onComplete then
      pcall(onComplete, result, win)
    end
  end

  local function fail(code)
    dismissMissionControl()
    complete({
      ok = false,
      code = code,
      windowId = windowId,
      spaceId = spaceId,
    })
  end

  local function dismissOnceAfterFocusFailure()
    if focusFailDismissUsed then
      return
    end
    focusFailDismissUsed = true
    dismissMissionControl()
  end

  local focusWhenAvailable
  local verifyFrontmost

  verifyFrontmost = function(win)
    if WindowService.currentSpaceId() ~= spaceId then
      fail("space_switch_interrupted")
      return
    end
    if isFrontmost(win) then
      complete({
        ok = true,
        code = "focus_verified_after_space_switch",
        windowId = windowId,
        spaceId = spaceId,
      }, win)
      return
    end
    if focusAttempts >= maxFocusAttempts then
      fail("focus_timeout_after_space_switch")
      return
    end
    dismissOnceAfterFocusFailure()
    schedulePendingFrontmostRequest(resolveDelay, token, focusWhenAvailable)
    resolveDelay = nextBackoffDelay(resolveDelay)
  end

  focusWhenAvailable = function()
    if WindowService.currentSpaceId() ~= spaceId then
      fail("space_switch_interrupted")
      return
    end

    local win = WindowService.getWindowById(windowId)
    if not win then
      resolveAttempts = resolveAttempts + 1
      if resolveAttempts >= maxResolveAttempts then
        fail("window_unavailable_after_space_switch")
        return
      end
      schedulePendingFrontmostRequest(resolveDelay, token, focusWhenAvailable)
      resolveDelay = nextBackoffDelay(resolveDelay)
      return
    end

    focusAttempts = focusAttempts + 1
    local requested = pcall(requestFrontmostImpl, win)
    if not requested then
      if focusAttempts >= maxFocusAttempts then
        fail("focus_timeout_after_space_switch")
        return
      end
      dismissOnceAfterFocusFailure()
      schedulePendingFrontmostRequest(resolveDelay, token, focusWhenAvailable)
      resolveDelay = nextBackoffDelay(resolveDelay)
      return
    end
    schedulePendingFrontmostRequest(focusVerifyDelay, token, function()
      verifyFrontmost(win)
    end)
  end

  local function waitForSpaceSettlement()
    if WindowService.currentSpaceId() == spaceId then
      dismissMissionControl()
      schedulePendingFrontmostRequest(focusDelay, token, focusWhenAvailable)
      return
    end

    spaceAttempts = spaceAttempts + 1
    if spaceAttempts >= maxSpaceAttempts then
      fail("space_switch_timeout")
      return
    end
    schedulePendingFrontmostRequest(settleDelay, token, waitForSpaceSettlement)
    settleDelay = nextBackoffDelay(settleDelay)
  end

  waitForSpaceSettlement()
  return {
    ok = true,
    code = "space_switch_requested",
    windowId = windowId,
    spaceId = spaceId,
  }
end

function WindowService.cancelPendingFrontmostRequest()
  invalidatePendingFrontmostRequest()
end

return WindowService
