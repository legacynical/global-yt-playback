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
  }, YoutubeService)
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

  if not keyStrokeMap[keyPress] and not (type(keyPress) == "string" and #keyPress == 1) then
    return {
      ok = false,
      code = "unsupported_key",
      focusResult = nil,
    }
  end

  -- Primary: focus-preserving direct dispatch when the key window is not
  -- another window of the same browser process (Doc / renamed sibling case).
  if shouldUseDirectDispatch(self.cfg, target, targetApp, frontmost) then
    if sendKeyStrokes(self.cfg, keyPress, targetApp) then
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
  local previousWindow = frontmost
  local previousId = previousWindow and previousWindow:id() or nil
  local targetId = target:id()

  self.windowService.ensureFrontmostAsync(target, self.cfg, function(focusResult, _resolved, token)
    if not focusResult.ok then
      self.toast(Toast.message.status("Focus failed for YT window"))
      return
    end

    local settleDelay = self.cfg.inputDelay or 0
    self.windowService.schedulePendingFrontmost(settleDelay, token, function()
      local focusedTarget = self.windowService.getWindowById(targetId) or target
      local app = (focusedTarget and focusedTarget:application()) or targetApp
      if not sendKeyStrokes(self.cfg, keyPress, app) then
        sendKeyStrokes(self.cfg, keyPress, nil)
      end

      if not (previousId and previousId ~= targetId) then
        return
      end

      self.windowService.schedulePendingFrontmost(settleDelay, token, function()
        local prev = self.windowService.getWindowById(previousId) or previousWindow
        if prev then
          self.windowService.requestFrontmost(prev)
        end
      end)
    end)
  end)

  return {
    ok = true,
    code = "focus_send_requested",
    focusResult = nil,
  }
end

return YoutubeService
