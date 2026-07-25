-- YoutubeService: global YouTube playback targeting for TAPSHOP macos hotkeys.
--
-- Target selection:
--   Eligible windows are supported browsers whose title contains " - YouTube"
--   (Subscriptions feed excluded). Focusing / discovering an eligible window
--   updates ytTargetId; same-window tab switches refresh ytTargetTitle + toast.
--
-- Dispatch (sendCommand):
--   1) Direct app keyStroke when focus-preserving is safe (other app focused,
--      or already on the target window).
--   2) Same browser process + different frontmost window → async focus fallback
--      (focus target, send, delayed restore). App-targeted keystrokes only reach
--      that process's key window, so blind direct dispatch would misdeliver.
--   Unsupported keyPress values are rejected before any focus work.
--
-- Overlapping commands:
--   Restore is owned here (pendingRestoreId + local timer), not the shared
--   WindowService pending token, so a later hotkey cannot treat the focused YT
--   target as "previous" and skip restoration.
--   Focus-fallback sends are queued while focusSendInFlight; a second hotkey
--   appends instead of restarting ensureFrontmostAsync (which would invalidate
--   the in-flight token and drop the earlier key). If pairing/workspace work
--   cancels the shared focus token without a callback, the next hotkey detects
--   the stale token and restarts focus for the queued keys.

local YoutubeService = {}
YoutubeService.__index = YoutubeService
local Toast = require("ui.toast")

local keyStrokeMap = {
  ["{Left}"] = "left",
  ["{Right}"] = "right",
}

local function sendKeyStrokes(cfg, keys, app)
  local mapped = keyStrokeMap[keys]
  if mapped then
    hs.eventtap.keyStroke({}, mapped, 0, app)
    return true
  end

  if type(keys) == "string" and #keys == 1 then
    hs.eventtap.keyStroke({}, string.lower(keys), 0, app)
    return true
  end

  return false
end

-- hs.eventtap.keyStroke(..., app) posts to the app (CGEventPostToPSN), which
-- macOS delivers to that process's key window — not a chosen hs.window id.
-- Same browser process + different window => direct dispatch misdelivers.
local function isSameBrowserAppDifferentWindow(frontmost, target)
  if not frontmost or not target then
    return false
  end

  local okSame, sameWindow = pcall(function()
    return frontmost:id() == target:id()
  end)
  if okSame and sameWindow then
    return false
  end

  local frontApp = frontmost:application()
  local targetApp = target:application()
  if not frontApp or not targetApp then
    return false
  end

  local okPid, samePid = pcall(function()
    return frontApp:pid() == targetApp:pid()
  end)
  return okPid and samePid == true
end

local function shouldUseDirectDispatch(cfg, target, targetApp, frontmost)
  if not cfg.youtubeDirectDispatch or not targetApp then
    return false
  end
  if isSameBrowserAppDifferentWindow(frontmost, target) then
    return false
  end
  return true
end

function YoutubeService.new(cfg, windowService, toast)
  return setmetatable({
    cfg = cfg,
    windowService = windowService,
    toast = toast,
    ytTargetId = nil,
    ytTargetTitle = nil,
    -- Focus-fallback restore across overlapping sendCommand calls.
    pendingRestoreId = nil,
    pendingRestoreWindow = nil,
    restoreSerial = 0,
    restoreTimer = nil,
    -- Queued keyPress values while one focus-fallback cycle is in flight.
    pendingCommands = {},
    focusSendInFlight = false,
    focusGeneration = 0,
    focusToken = nil,
    sendSerial = 0,
    sendTimer = nil,
  }, YoutubeService)
end

local function stopRestoreTimer(self)
  if self.restoreTimer then
    self.restoreTimer:stop()
    self.restoreTimer = nil
  end
end

local function stopSendTimer(self)
  if self.sendTimer then
    self.sendTimer:stop()
    self.sendTimer = nil
  end
end

local function clearPendingRestore(self)
  stopRestoreTimer(self)
  self.restoreSerial = (self.restoreSerial or 0) + 1
  self.pendingRestoreId = nil
  self.pendingRestoreWindow = nil
end

local function clearFocusSendQueue(self)
  stopSendTimer(self)
  self.sendSerial = (self.sendSerial or 0) + 1
  self.focusGeneration = (self.focusGeneration or 0) + 1
  self.pendingCommands = {}
  self.focusSendInFlight = false
  self.focusToken = nil
end

-- Remember the pre-YT window and (re)arm a delayed restore. Safe to call again
-- for overlapping commands: bumps restoreSerial so only the latest timer fires.
local function armRestore(self, delay, restoreId, restoreWindow, targetId)
  stopRestoreTimer(self)
  if not (restoreId and restoreId ~= targetId) then
    self.restoreSerial = (self.restoreSerial or 0) + 1
    self.pendingRestoreId = nil
    self.pendingRestoreWindow = nil
    return
  end

  self.pendingRestoreId = restoreId
  self.pendingRestoreWindow = restoreWindow
  self.restoreSerial = (self.restoreSerial or 0) + 1
  local serial = self.restoreSerial
  self.restoreTimer = hs.timer.doAfter(delay or 0, function()
    self.restoreTimer = nil
    if serial ~= self.restoreSerial then
      return
    end
    local prevId = self.pendingRestoreId
    local prevWin = self.pendingRestoreWindow
    self.pendingRestoreId = nil
    self.pendingRestoreWindow = nil
    local prev = self.windowService.getWindowById(prevId) or prevWin
    if prev then
      self.windowService.requestFrontmost(prev)
    end
  end)
end

local function flushPendingCommands(self, targetId, targetApp, target)
  local keys = self.pendingCommands
  self.pendingCommands = {}
  self.focusSendInFlight = false
  self.focusToken = nil
  stopSendTimer(self)

  local focusedTarget = self.windowService.getWindowById(targetId) or target
  local app = (focusedTarget and focusedTarget:application()) or targetApp
  for _, keyPress in ipairs(keys) do
    if not sendKeyStrokes(self.cfg, keyPress, app) then
      sendKeyStrokes(self.cfg, keyPress, nil)
    end
  end

  armRestore(self, self.cfg.inputDelay or 0, self.pendingRestoreId, self.pendingRestoreWindow, targetId)
end

-- Start (or restart) async focus + queued key flush for the YT target.
local function startFocusFallback(self, target, targetApp, targetId)
  self.focusSendInFlight = true
  self.focusGeneration = (self.focusGeneration or 0) + 1
  local focusGeneration = self.focusGeneration
  stopSendTimer(self)

  local started = self.windowService.ensureFrontmostAsync(target, self.cfg, function(focusResult, _resolved, _token)
    if focusGeneration ~= self.focusGeneration then
      return
    end
    if not focusResult.ok then
      clearFocusSendQueue(self)
      clearPendingRestore(self)
      self.toast(Toast.message.status("Focus failed for YT window"))
      return
    end

    local settleDelay = self.cfg.inputDelay or 0
    -- Own the settle timer so WindowService token churn cannot drop queued keys.
    stopSendTimer(self)
    self.sendSerial = (self.sendSerial or 0) + 1
    local sendSerial = self.sendSerial
    self.focusToken = nil
    self.sendTimer = hs.timer.doAfter(settleDelay, function()
      self.sendTimer = nil
      if sendSerial ~= self.sendSerial or focusGeneration ~= self.focusGeneration then
        return
      end
      flushPendingCommands(self, targetId, targetApp, target)
    end)
  end)

  self.focusToken = started and started.token or nil
end

-- Prefer an in-flight restore target over current frontmost (which may already
-- be the YT window after a prior focus fallback that has not restored yet).
local function resolveRestoreTarget(self, frontmost, targetId)
  local restoreId = self.pendingRestoreId
  local restoreWindow = self.pendingRestoreWindow
  if restoreId == targetId then
    restoreId = nil
    restoreWindow = nil
  end
  if restoreId then
    local resolved = self.windowService.getWindowById(restoreId)
    if resolved then
      restoreWindow = resolved
    end
    return restoreId, restoreWindow
  end

  local frontmostId = frontmost and frontmost:id() or nil
  if frontmostId and frontmostId ~= targetId then
    return frontmostId, frontmost
  end
  return nil, nil
end

-- True when bundleId is in cfg.browserBundleIDs (Chrome, Safari, etc.).
function YoutubeService:isSupportedBrowser(bundleId)
  return self.cfg.browserBundleIDs[bundleId or ""] == true
end

-- Title-based YT page detection for a visible supported-browser window.
function YoutubeService:isYouTubeWindow(win)
  if not win or not win:isVisible() then
    return false
  end

  local app = win:application()
  if not app then
    return false
  end

  local bundleId = app:bundleID() or ""
  if not self:isSupportedBrowser(bundleId) then
    return false
  end

  local title = win:title() or ""
  if title == "" then
    return false
  end
  if title:find("Subscriptions - YouTube", 1, true) then
    return false
  end

  return title:find(" - YouTube", 1, true) ~= nil
end

local function announceTarget(self, win, title)
  local app = win:application()
  self.toast(Toast.message.windowAction({
    prefixText = "YT Target Updated: ",
    titleText = title or "[untitled]",
    bundleID = app and app:bundleID() or nil,
    appName = app and app:name() or nil,
  }))
end

-- Window-filter hook: adopt eligible windows as the YT target.
-- Same id + new title (tab switch) keeps the id and re-toasts the video title.
function YoutubeService:handleWindowCandidate(win)
  if not (win and self:isYouTubeWindow(win)) then
    return
  end

  local id = win:id()
  local title = win:title() or ""

  -- Same window, new video/tab title: keep the target id but refresh the
  -- announced title so tab switches inside the YT target are visible.
  if self.ytTargetId == id then
    if self.ytTargetTitle ~= title then
      self.ytTargetTitle = title
      announceTarget(self, win, title)
    end
    return
  end

  self.ytTargetId = id
  self.ytTargetTitle = title
  announceTarget(self, win, title)
end

function YoutubeService:handleDestroyedWindowId(id)
  if self.ytTargetId == id then
    self.ytTargetId = nil
    self.ytTargetTitle = nil
  end
  if self.pendingRestoreId == id then
    clearPendingRestore(self)
  end
end

function YoutubeService:getTargetId()
  return self.ytTargetId
end

-- Prefer sticky ytTargetId while it remains an eligible YT window; else scan
-- candidates and adopt the first match. Does not change focus.
function YoutubeService:getTargetWindow()
  if self.ytTargetId then
    local win = self.windowService.getWindowById(self.ytTargetId)
    if win and win:isVisible() and self:isYouTubeWindow(win) then
      self.ytTargetTitle = win:title() or self.ytTargetTitle
      return win
    end
  end

  for _, win in ipairs(self.windowService.candidateWindows()) do
    if self:isYouTubeWindow(win) then
      self.ytTargetId = win:id()
      self.ytTargetTitle = win:title() or ""
      return win
    end
  end

  return nil
end

-- Hotkey entry: deliver keyPress to the YT target (see module dispatch rules).
-- Returns immediately; async fallback reports focus failure via toast.
function YoutubeService:sendCommand(keyPress)
  local target = self:getTargetWindow()
  if not target then
    self.toast(Toast.message.status("YouTube window not found."))
    return {
      ok = false,
      code = "target_missing",
      focusResult = nil,
    }
  end

  local targetApp = target:application()
  local frontmost = hs.window.frontmostWindow()
  local targetId = target:id()
  local frontmostId = frontmost and frontmost:id() or nil
  local restoreId, restoreWindow = resolveRestoreTarget(self, frontmost, targetId)

  if not keyStrokeMap[keyPress] and not (type(keyPress) == "string" and #keyPress == 1) then
    return {
      ok = false,
      code = "unsupported_key",
      focusResult = nil,
    }
  end

  -- Overlapping focus-fallback: queue the key instead of restarting
  -- ensureFrontmostAsync (which would cancel the in-flight token/send).
  if self.focusSendInFlight then
    self.pendingCommands[#self.pendingCommands + 1] = keyPress
    if restoreId and restoreId ~= targetId then
      self.pendingRestoreId = restoreId
      self.pendingRestoreWindow = restoreWindow
    end
    -- Focus already landed (settle pending, or token cancelled externally):
    -- flush now so queued keys are not stuck behind a dead callback.
    if frontmostId == targetId then
      self.windowService.cancelPendingFrontmostRequest()
      self.focusGeneration = (self.focusGeneration or 0) + 1
      self.sendSerial = (self.sendSerial or 0) + 1
      flushPendingCommands(self, targetId, targetApp, target)
      return {
        ok = true,
        code = "focus_send_flushed",
        focusResult = nil,
      }
    end
    -- Pairing/workspace focus cancelled our token without a callback: restart
    -- so queued playback commands are not stranded forever.
    if not self.windowService.isCurrentFrontmostToken(self.focusToken) then
      startFocusFallback(self, target, targetApp, targetId)
      return {
        ok = true,
        code = "focus_send_restarted",
        focusResult = nil,
      }
    end
    return {
      ok = true,
      code = "focus_send_queued",
      focusResult = nil,
    }
  end

  -- A new command supersedes any armed restore timer; restore target is kept
  -- via pendingRestoreId / restoreId so we can re-arm after this send.
  stopRestoreTimer(self)

  -- Primary: focus-preserving direct dispatch when the key window is not
  -- another window of the same browser process (Doc / renamed sibling case).
  if shouldUseDirectDispatch(self.cfg, target, targetApp, frontmost) then
    if sendKeyStrokes(self.cfg, keyPress, targetApp) then
      -- If a prior focus fallback left us on the YT target (or we still owe a
      -- restore), re-arm restore. Pure other-app direct dispatch needs none.
      local owesRestore = restoreId and restoreId ~= targetId
        and (self.pendingRestoreId ~= nil or frontmostId == targetId)
      if owesRestore then
        armRestore(self, self.cfg.inputDelay or 0, restoreId, restoreWindow, targetId)
      else
        clearPendingRestore(self)
      end
      return {
        ok = true,
        code = "direct_dispatch",
        focusResult = nil,
      }
    end
  end

  -- Fallback: briefly focus YT target, send, then restore previous window.
  -- Required when origin and destination share a browser app — app-targeted
  -- keystrokes cannot address a background window of that process.
  if restoreId and restoreId ~= targetId then
    self.pendingRestoreId = restoreId
    self.pendingRestoreWindow = restoreWindow
  else
    clearPendingRestore(self)
  end

  self.pendingCommands = { keyPress }
  startFocusFallback(self, target, targetApp, targetId)

  return {
    ok = true,
    code = "focus_send_requested",
    focusResult = nil,
  }
end

return YoutubeService
