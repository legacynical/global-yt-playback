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

  local frontmost = hs.window.frontmostWindow()
  return frontmost and frontmost:id() == win:id() or false
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

local function ensureFrontmostImpl(win, cfg)
  if not win then
    return focusResult(false, "missing_window", nil)
  end

  if isFrontmost(win) then
    return focusResult(true, "already_frontmost", win)
  end

  requestFrontmostImpl(win)
  local focused = WindowService.waitForFrontmost(win, cfg)
  return focusResult(focused, focused and "focus_verified" or "focus_timeout", win)
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

  local ok, isStandard = pcall(function()
    return win:isStandard()
  end)
  if not ok or isStandard ~= true then
    return false
  end

  local gotTitle, title = pcall(function()
    return win:title()
  end)
  return gotTitle and type(title) == "string" and title:match("%S") ~= nil
end

function WindowService.waitForFrontmost(win, cfg)
  local timeoutSec = cfg.focusWaitTimeout
  local start = hs.timer.secondsSinceEpoch()
  while (hs.timer.secondsSinceEpoch() - start) < timeoutSec do
    if isFrontmost(win) then
      return true
    end
    hs.timer.usleep(cfg.focusPollMicros)
  end
  return false
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

-- Use verified focus only when subsequent input depends on confirmation.
function WindowService.ensureFrontmost(win, cfg)
  invalidatePendingFrontmostRequest()
  return ensureFrontmostImpl(win, cfg)
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

function WindowService.waitForSpace(spaceId, cfg)
  if not spaceId then
    return false
  end
  local timeoutSec = (cfg and cfg.spaceSwitchWaitTimeout) or 0.35
  local pollMicros = (cfg and cfg.spaceSwitchPollMicros) or 10000
  local start = hs.timer.secondsSinceEpoch()
  while (hs.timer.secondsSinceEpoch() - start) < timeoutSec do
    if WindowService.currentSpaceId() == spaceId then
      return true
    end
    hs.timer.usleep(pollMicros)
  end
  return WindowService.currentSpaceId() == spaceId
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

  local ok, fullscreen = pcall(function()
    return win:isFullScreen()
  end)
  return ok and fullscreen == true
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
  hs.spaces.gotoSpace(spaceId)
  if not WindowService.waitForSpace(spaceId, cfg) then
    return { ok = false, code = "space_switch_timeout", spaceId = spaceId }
  end
  if hs.spaces and type(hs.spaces.closeMissionControl) == "function" then
    pcall(hs.spaces.closeMissionControl)
  end
  return { ok = true, code = "space_switch_verified", spaceId = spaceId }
end

-- After a Space switch, request focus on the next loop turn once the desktop settles.
function WindowService.requestFrontmostAfterSpaceSwitch(win, cfg)
  if not win then
    return focusResult(false, "missing_window", nil)
  end

  local initialDelay = cfg.fullscreenSpaceSwitchDelay or 0.20
  local token = invalidatePendingFrontmostRequest()

  pendingFrontmostTimer = hs.timer.doAfter(initialDelay, function()
    pendingFrontmostTimer = nil
    pcall(function()
      if token ~= pendingFrontmostSerial then
        return
      end
      requestFrontmostImpl(win)
    end)
  end)

  return focusResult(true, "focus_requested_after_space_switch", win)
end

function WindowService.cancelPendingFrontmostRequest()
  invalidatePendingFrontmostRequest()
end

return WindowService
