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

function YoutubeService.new(cfg, windowService, toast)
  return setmetatable({
    cfg = cfg,
    windowService = windowService,
    toast = toast,
    ytTargetId = nil,
  }, YoutubeService)
end

function YoutubeService:isSupportedBrowser(bundleId)
  return self.cfg.browserBundleIDs[bundleId or ""] == true
end

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

function YoutubeService:handleWindowCandidate(win)
  if win and self:isYouTubeWindow(win) then
    local id = win:id()
    if self.ytTargetId ~= id then
      self.ytTargetId = id
      local app = win:application()
      self.toast(Toast.message.windowAction({
        prefixText = "YT Target Updated: ",
        titleText = win:title() or "[untitled]",
        bundleID = app and app:bundleID() or nil,
        appName = app and app:name() or nil,
      }))
    end
  end
end

function YoutubeService:handleDestroyedWindowId(id)
  if self.ytTargetId == id then
    self.ytTargetId = nil
  end
end

function YoutubeService:getTargetId()
  return self.ytTargetId
end

function YoutubeService:getTargetWindow()
  if self.ytTargetId then
    local win = self.windowService.getWindowById(self.ytTargetId)
    if win and win:isVisible() and self:isYouTubeWindow(win) then
      return win
    end
  end

  for _, win in ipairs(self.windowService.candidateWindows()) do
    if self:isYouTubeWindow(win) then
      self.ytTargetId = win:id()
      return win
    end
  end

  return nil
end

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

  -- Primary: focus-preserving direct dispatch. Do not steal focus from the
  -- current window (including same-app siblings / Docs).
  if self.cfg.youtubeDirectDispatch and targetApp and sendKeyStrokes(self.cfg, keyPress, targetApp) then
    return {
      ok = true,
      code = "direct_dispatch",
      focusResult = nil,
    }
  end

  -- Fallback only: focus target, send so target is key, then restore.
  -- Restore is delayed so key delivery is not raced within the same app.
  local previousWindow = hs.window.frontmostWindow()
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
