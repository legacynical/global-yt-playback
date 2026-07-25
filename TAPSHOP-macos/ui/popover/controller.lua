local clientScript = require("ui.popover.client_script")
local icons = require("ui.icons")
local panelLayout = require("ui.panel_layout")
local popoverRender = require("ui.popover.render")
local popoverStyles = require("ui.popover.styles")
local webviewPanel = require("ui.webview_panel")

local Popover = {}
local REFRESH_DEBOUNCE_SECONDS = 0.18
local INTERACTIVE_REFRESH_DELAY_SECONDS = 0.03
local AUTO_HIDE_ACTIONS = {
  pair = true,
  unpair = true,
  unpairAll = true,
}
local popoverLayout = panelLayout.create({
  defaultSize = { w = 500, h = 273 },
  minWidth = 150,
  targetMinHeight = 125,
  loadSavedSize = function(appdata)
    return appdata.getPopoverSize()
  end,
})

function Popover.new(app, cfg, deps)
  local windowService = deps.windowService
  local appdata = deps.appdata

  local panel = nil
  local callerWin = nil
  local activeWin = nil
  local pendingActiveWin = nil
  local pendingRefresh = false
  local refreshTimer = nil
  local isDragging = false
  local isResizing = false
  local isFocused = false
  local cachedThemeCss = nil
  local savedTopLeft = appdata.getPopoverTopLeft()
  local savedSize = popoverLayout.loadSavedSize(appdata)
  local runtimeBounds = popoverLayout.initialRuntimeBounds()

  local function pickScreen()
    return hs.mouse.getCurrentScreen()
      or (activeWin and activeWin:screen())
      or (callerWin and callerWin:screen())
      or hs.screen.mainScreen()
  end

  local function screenFrame(screen)
    if not screen then
      return nil
    end
    local frame = screen:frame()
    return {
      x = math.floor(frame.x),
      y = math.floor(frame.y),
      w = math.floor(frame.w),
      h = math.floor(frame.h),
    }
  end

  local function frameTable(frame)
    return {
      x = math.floor(frame.x),
      y = math.floor(frame.y),
      w = math.floor(frame.w),
      h = math.floor(frame.h),
    }
  end

  local function geometryRect(frame)
    return hs.geometry.rect(frame.x, frame.y, frame.w, frame.h)
  end

  local function centeredRect(screen)
    return geometryRect(popoverLayout.centeredFrame(
      screenFrame(screen or pickScreen()),
      savedSize,
      runtimeBounds
    ))
  end

  local function frameForSavedTopLeft(screen)
    return popoverLayout.frameForTopLeft(
      savedTopLeft,
      screenFrame(screen or pickScreen()),
      savedSize,
      runtimeBounds
    )
  end

  local function currentPopoverLevel()
    if cfg.popoverAlwaysOnTop then
      return hs.drawing.windowLevels.popUpMenu
    end
    return hs.drawing.windowLevels.normal
  end

  local function currentPopoverBehavior()
    local behavior = {
      "canJoinAllSpaces",
      "fullScreenAuxiliary",
    }

    if cfg.popoverAlwaysOnTop then
      behavior[#behavior + 1] = "transient"
    else
      behavior[#behavior + 1] = "managed"
    end

    return behavior
  end

  local function focusPanelWindow(panelRef)
    if cfg.popoverAlwaysOnTop then
      return
    end

    local view = panelRef and panelRef.getWebview and panelRef:getWebview() or nil
    if not view then
      return
    end

    if hs.focus then
      hs.focus()
    end

    if view.bringToFront then
      view:bringToFront(false)
    end

    if view.hswindow then
      local win = view:hswindow()
      if win and win.focus then
        win:focus()
      end
    end
  end

  local function saveTopLeftFromFrame(panelRef)
    local frame = panelRef:getWebview():frame()
    savedTopLeft = {
      x = math.floor(frame.x),
      y = math.floor(frame.y),
    }
    appdata.setPopoverTopLeft(savedTopLeft)
  end

  local function saveSize(size, screen)
    local clamped = popoverLayout.clampSize(
      size,
      screenFrame(screen or pickScreen()),
      runtimeBounds
    )
    savedSize = clamped
    appdata.setPopoverSize(clamped)
    return clamped
  end

  local function saveSizeFromFrame(panelRef)
    local frame = panelRef:getWebview():frame()
    return saveSize({
      w = math.floor(frame.w),
      h = math.floor(frame.h),
    })
  end

  local function requestBoundsRecompute(panelRef)
    if panelRef and panelRef:isShown() then
      panelRef:evaluateJavaScript("window.tapshopRecomputeBounds && window.tapshopRecomputeBounds()")
    end
  end

  local function currentHeaderLines()
    local info = windowService.getWindowInfo(activeWin)
      or windowService.getWindowInfo(callerWin)
      or windowService.getWindowInfo()
    local primaryLine = "No active window found"
    local bundleID = nil
    local appName = nil

    if info then
      local rawTitle = info.title or ""
      local title = rawTitle:match("%S") and rawTitle or "[untitled]"
      appName = info.appName or ""
      bundleID = info.bundleID or nil
      primaryLine = title
    end

    return primaryLine, bundleID, appName
  end

  local function buildRenderContext()
    local theme = popoverStyles.buildTheme(cfg)
    local primaryLine, headerBundleID, headerAppName = currentHeaderLines()
    if not cachedThemeCss then
      cachedThemeCss = popoverStyles.buildCss(theme)
    end

    return {
      css = cachedThemeCss,
      script = clientScript.script,
      layoutPolicy = popoverLayout.clientPolicy(),
      theme = theme,
      primaryLine = primaryLine,
      headerBundleID = headerBundleID,
      headerAppName = headerAppName,
      config = {
        hidePairButtons = cfg.popoverHidePairButtons == true,
      },
      activeProfileId = app.getActiveProfileId and app:getActiveProfileId() or 1,
      profileCount = app.getProfileCount and app:getProfileCount() or 1,
      rows = app:getWorkspaceRowModels(),
    }
  end

  local function stopRefreshTimer()
    if refreshTimer then
      refreshTimer:stop()
      refreshTimer = nil
    end
  end

  local function applyPendingActiveWin()
    if pendingActiveWin ~= nil then
      activeWin = pendingActiveWin
      pendingActiveWin = nil
    end
  end

  local function flushQueuedRefresh()
    pendingRefresh = false
    stopRefreshTimer()
    applyPendingActiveWin()

    if panel:isShown() then
      panel:refresh()
      return
    end

    panel:markDirty()
  end

  local function queueRefresh(delay)
    pendingRefresh = true
    stopRefreshTimer()
    refreshTimer = hs.timer.doAfter(delay or REFRESH_DEBOUNCE_SECONDS, flushQueuedRefresh)
  end

  local function pushActiveWindowHeaderUpdate()
    if not panel:isShown() or not panel:hasContent() then
      return false
    end

    local primaryLine, headerBundleID, headerAppName = currentHeaderLines()
    local encoded = hs.json.encode({
      title = primaryLine,
      iconUrl = icons.appIconUrl(headerBundleID, 16),
      appName = headerAppName or "",
    }) or "{}"
    -- Queue the lightweight header update; markDirty on callback failure so a
    -- stale header is rebuilt the next time the popover is shown.
    panel:evaluateJavaScript(
      "(function(){ return !!(window.tapshopUpdateActiveWindow && window.tapshopUpdateActiveWindow("
        .. encoded
        .. ")); })()",
      function(result, err)
        if err or not result then
          panel:markDirty()
        end
      end
    )
    return true
  end

  panel = webviewPanel.new({
    messageHandler = "tapshop",
    initialRect = function()
      local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
      return centeredRect(screen)
    end,
    windowStyle = hs.webview.windowMasks.borderless,
    transparent = true,
    level = currentPopoverLevel,
    behavior = currentPopoverBehavior,
    allowTextEntry = true,
    buildHtml = function()
      return popoverRender.buildHtml(buildRenderContext())
    end,
    handleAction = function(panelRef, msg)
      local body = msg.body or {}
      local action = body.action

      if action == "dragStart" then
        isDragging = true
        return
      end
      if action == "dragMove" then
        if not isDragging then
          return
        end
        local dx = tonumber(body.dx) or 0
        local dy = tonumber(body.dy) or 0
        if dx == 0 and dy == 0 then
          return
        end
        local frame = panelRef:getWebview():frame()
        panelRef:getWebview():topLeft({
          x = frame.x + dx,
          y = frame.y + dy,
        })
        return
      end
      if action == "dragEnd" then
        isDragging = false
        saveTopLeftFromFrame(panelRef)
        return
      end
      if action == "resizeStart" then
        isResizing = true
        return
      end
      if action == "resizeMove" then
        if not isResizing then
          return
        end
        local dw = tonumber(body.dw) or 0
        local dh = tonumber(body.dh) or 0
        local direction = tostring(body.direction or "")
        if dw == 0 and dh == 0 then
          return
        end
        local frame = panelRef:getWebview():frame()
        local nextX = frame.x
        local nextY = frame.y
        local nextW = frame.w
        local nextH = frame.h
        local minWidth = popoverLayout.minWidth()
        local currentScreenFrame = screenFrame(pickScreen())

        if direction:find("w", 1, true) then
          nextW = math.max(minWidth, frame.w - dw)
          nextX = frame.x + (frame.w - nextW)
        elseif direction:find("e", 1, true) then
          nextW = math.max(minWidth, frame.w + dw)
        end

        if direction:find("n", 1, true) then
          nextH = popoverLayout.clampSize({
            w = nextW,
            h = frame.h - dh,
          }, currentScreenFrame, runtimeBounds).h
          nextY = frame.y + (frame.h - nextH)
        elseif direction:find("s", 1, true) then
          nextH = popoverLayout.clampSize({
            w = nextW,
            h = frame.h + dh,
          }, currentScreenFrame, runtimeBounds).h
        end

        panelRef:getWebview():frame(hs.geometry.rect(nextX, nextY, nextW, nextH))
        return
      end
      if action == "updatePopoverBounds" then
        local targetMinHeight = tonumber(body.targetMinHeight)
        local derivedMinHeight = tonumber(body.derivedMinHeight)
        local derivedMaxHeight = tonumber(body.derivedMaxHeight)
        local derivedMinUiScale = tonumber(body.derivedMinUiScale)
        local maxUiScale = tonumber(body.maxUiScale)
        local measuredMinHeight = tonumber(body.measuredMinHeight)
        local currentHeight = tonumber(body.currentHeight)
        local currentUiScale = tonumber(body.currentUiScale)
        local bodyShellHeight = tonumber(body.bodyShellHeight)
        local workspaceListHeight = tonumber(body.workspaceListHeight)
        if not derivedMinHeight or not derivedMaxHeight then
          return
        end

        local normalizedMinHeight = math.max(popoverLayout.targetMinHeight(), math.floor(derivedMinHeight + 0.5))
        local normalizedMaxHeight = math.max(normalizedMinHeight, math.floor(derivedMaxHeight + 0.5))
        runtimeBounds = {
          minHeight = normalizedMinHeight,
          maxHeight = normalizedMaxHeight,
          minUiScale = derivedMinUiScale,
          maxUiScale = maxUiScale,
          targetMinHeight = targetMinHeight,
          measuredMinHeight = measuredMinHeight,
          currentHeight = currentHeight,
          currentUiScale = currentUiScale,
          bodyShellHeight = bodyShellHeight,
          workspaceListHeight = workspaceListHeight,
        }

        if not isResizing then
          local currentFrame = frameTable(panelRef:getWebview():frame())
          local nextFrame = popoverLayout.clampFrame(
            currentFrame,
            screenFrame(pickScreen()),
            runtimeBounds
          )
          if nextFrame.x ~= currentFrame.x
            or nextFrame.y ~= currentFrame.y
            or nextFrame.w ~= currentFrame.w
            or nextFrame.h ~= currentFrame.h then
            panelRef:getWebview():frame(geometryRect(nextFrame))
            saveTopLeftFromFrame(panelRef)
            saveSize({
              w = nextFrame.w,
              h = nextFrame.h,
            })
          else
            local clampedSavedSize = popoverLayout.clampSize(savedSize, screenFrame(pickScreen()), runtimeBounds)
            if savedSize.w ~= clampedSavedSize.w or savedSize.h ~= clampedSavedSize.h then
              saveSize(clampedSavedSize)
            end
          end
        end
        return
      end
      if action == "resizeEnd" then
        isResizing = false
        saveTopLeftFromFrame(panelRef)
        saveSizeFromFrame(panelRef)
        return
      end
      if action == "close" then
        panelRef:hide()
        return
      end

      if action == "pair" then
        body.sourceWindow = activeWin or callerWin
      end
      local result = app:handlePopoverAction(body)
      if action == "setAlwaysOnTop" then
        panelRef:setLevel(currentPopoverLevel())
      end
      if result ~= false and cfg.popoverAutoHideAfterAction and AUTO_HIDE_ACTIONS[action] then
        panelRef:hide()
      end
      return result
    end,
    windowCallback = function(panelRef, act, _, focusState)
      if act == "focusChange" then
        isFocused = focusState == true
        if focusState == false and panelRef:isShown() and not cfg.popoverAlwaysOnTop then
          panelRef:hide()
        end
      end
    end,
    beforeShow = function(_, view)
      callerWin = hs.window.frontmostWindow()
      activeWin = callerWin
      local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
      if savedTopLeft then
        local frame = frameForSavedTopLeft(screen)
        view:frame(geometryRect(frame))
        if frame.x ~= savedTopLeft.x or frame.y ~= savedTopLeft.y then
          savedTopLeft = { x = frame.x, y = frame.y }
          appdata.setPopoverTopLeft(savedTopLeft)
        end
      else
        view:frame(centeredRect(screen))
      end
      view:level(currentPopoverLevel())
    end,
    afterShow = function(panelRef)
      focusPanelWindow(panelRef)
      requestBoundsRecompute(panelRef)
      panelRef:evaluateJavaScript("window.tapshopFocusKeyboardSurface && window.tapshopFocusKeyboardSurface()")
    end,
    beforeHide = function()
      isDragging = false
      isResizing = false
      isFocused = false
    end,
  })

  local instance = {}

  function instance:show()
    panel:show()
  end

  function instance:hide()
    panel:hide()
  end

  function instance:toggle()
    panel:toggle()
  end

  function instance:toggleOrFocus()
    if cfg.popoverAlwaysOnTop then
      if panel:isShown() then
        panel:hide()
      else
        panel:show()
      end
      return
    end

    if panel:isShown() and isFocused then
      panel:hide()
      return
    end

    panel:show()
  end

  function instance:refreshIfShown()
    if panel:isShown() then
      panel:refresh()
      return
    end
    panel:markDirty()
  end

  function instance:refreshCache()
    panel:markDirty()
    cachedThemeCss = nil
    panel:setLevel(currentPopoverLevel())
    panel:syncBehavior()
    if panel:isShown() then
      panel:refresh()
      requestBoundsRecompute(panel)
    end
  end

  function instance:warmStaticCaches()
    local theme = popoverStyles.buildTheme(cfg)
    cachedThemeCss = popoverStyles.buildCss(theme)
  end

  function instance:requestRefresh(reason, win)
    if win ~= nil then
      pendingActiveWin = win
    end
    if reason == "profile_switch" then
      queueRefresh(INTERACTIVE_REFRESH_DELAY_SECONDS)
      return
    end
    queueRefresh()
  end

  function instance:requestActiveWindowUpdate(win)
    pendingActiveWin = win or hs.window.frontmostWindow() or activeWin
    applyPendingActiveWin()

    if pushActiveWindowHeaderUpdate() then
      return
    end

    panel:markDirty()
  end

  function instance:updateActiveWindow(win)
    self:requestActiveWindowUpdate(win)
  end

  function instance:syncWindowLevel()
    panel:setLevel(currentPopoverLevel())
    panel:syncBehavior()
  end

  function instance:pushOpacityUpdate(percent)
    if not panel:isShown() or not panel:hasContent() then
      return
    end
    local p = tonumber(percent) or 85
    panel:evaluateJavaScript("window.tapshopUpdateOpacity && window.tapshopUpdateOpacity(" .. tostring(p) .. ")")
  end

  return instance
end

return Popover
