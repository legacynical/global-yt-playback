local clientScript = require("ui.popover.client_script")
local icons = require("ui.icons")
local panelLayout = require("ui.panel_layout")
local popoverRender = require("ui.popover.render")
local popoverStyles = require("ui.popover.styles")
local webviewPanel = require("ui.webview_panel")
local ProfilePalette = require("state.profile_palette")

local Popover = {}
local REFRESH_DEBOUNCE_SECONDS = 0.18
local INTERACTIVE_REFRESH_DELAY_SECONDS = 0.03
-- Coalesce Accessibility/Spaces row rebuilds until the active bank stops changing.
local PROFILE_SWITCH_SETTLE_SECONDS = 0.10
local AUTO_HIDE_ACTIONS = {
  pair = true,
  unpair = true,
  unpairAll = true,
  activateSlot = true,
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
  local resizeDirection = ""
  local isFocused = false
  local cachedThemeCss = nil
  local profileTextEntryActive = false
  -- Mirrored from client so full HTML rebuilds can restore profiles mode.
  local profileListMode = "slots"
  local deferredRefreshWhileEditing = false
  local savedTopLeft = appdata.getPopoverTopLeft()
  local savedSize = popoverLayout.loadSavedSize(appdata)
  local runtimeBounds = popoverLayout.initialRuntimeBounds()
  local pointerHoverTap = nil
  local confirmEscapeTap = nil
  local lastPointerHoverX = nil
  local lastPointerHoverY = nil
  local pointerInsidePopover = false
  local pointerHoverFlushTimer = nil
  local pendingPointerHoverX = nil
  local pendingPointerHoverY = nil
  local POINTER_HOVER_INTERVAL = 0.03
  local focusHandbackGeneration = 0
  local escapeKeyCode = (hs.keycodes and hs.keycodes.map and hs.keycodes.map.escape) or 53

  local function isPointInFrame(pt, frame)
    return pt
      and frame
      and pt.x >= frame.x
      and pt.x <= frame.x + frame.w
      and pt.y >= frame.y
      and pt.y <= frame.y + frame.h
  end

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
    -- Live toggle (not a launch-only flag): when "Hide during fullscreens" is
    -- on, omit fullScreenAuxiliary. Active hide/restore lives in
    -- state/popover_fullscreen_visibility (canJoinAllSpaces can still show an
    -- AOT panel during FS visits). Turning the setting off restores
    -- fullScreenAuxiliary via syncWindowLevel.
    local behavior = {
      "canJoinAllSpaces",
    }
    if not cfg.popoverHideOnFullscreenWorkspace then
      behavior[#behavior + 1] = "fullScreenAuxiliary"
    end

    if cfg.popoverAlwaysOnTop then
      behavior[#behavior + 1] = "transient"
    else
      behavior[#behavior + 1] = "managed"
    end

    return behavior
  end

  -- A+B focus model when Always on Top (popover is a utility overlay, not a
  -- workspace you focus into for work; header active-window stays the user's
  -- real window underneath):
  --   A) mouse hits the popover (click/drag/resize) via nonactivating panel
  --   B) keyboard stays on the user's frontmost window
  -- Hammerspoon detail: allowTextEntry gates canBecomeKeyWindow. If true, a
  -- click makes the webview key and steals keyboard — keep it false in AOT.
  -- When Always on Top is off, take normal key/app focus on show.
  local function focusPanelWindow(panelRef)
    if cfg.popoverAlwaysOnTop and not profileTextEntryActive then
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

  local function abandonFocusHandback()
    focusHandbackGeneration = focusHandbackGeneration + 1
  end

  local function scheduleFocusHandback()
    -- Only undo accidental self-focus. Never yank focus after pair/activate
    -- already moved it to a real target window.
    focusHandbackGeneration = focusHandbackGeneration + 1
    local gen = focusHandbackGeneration
    local target = activeWin or callerWin
    hs.timer.doAfter(0.05, function()
      if gen ~= focusHandbackGeneration or not cfg.popoverAlwaysOnTop or not target then
        return
      end
      local view = panel and panel.getWebview and panel:getWebview() or nil
      local selfWin = nil
      if view and view.hswindow then
        local ok, win = pcall(function()
          return view:hswindow()
        end)
        if ok then
          selfWin = win
        end
      end
      local front = hs.window.frontmostWindow()
      local frontId = front and front.id and front:id() or nil
      local selfId = selfWin and selfWin.id and selfWin:id() or nil
      if not frontId or not selfId or frontId ~= selfId then
        return
      end
      pcall(function()
        target:focus()
      end)
    end)
  end

  local function currentWindowStyle()
    local style = hs.webview.windowMasks.borderless
    -- nonactivating only for Always on Top; normal show/hide should be a real key window.
    -- While renaming a profile, temporarily allow key focus for the text field.
    if cfg.popoverAlwaysOnTop and not profileTextEntryActive then
      style = style | hs.webview.windowMasks.nonactivating
    end
    return style
  end

  local function clearPointerHover(panelRef)
    pendingPointerHoverX = nil
    pendingPointerHoverY = nil
    if pointerHoverFlushTimer then
      pointerHoverFlushTimer:stop()
      pointerHoverFlushTimer = nil
    end
    lastPointerHoverX = nil
    lastPointerHoverY = nil
    pointerInsidePopover = false
    if panelRef then
      panelRef:evaluateJavaScript(
        "window.tapshopClearPointerHover && window.tapshopClearPointerHover()"
      )
    end
  end

  local function flushPointerHover(panelRef)
    pointerHoverFlushTimer = nil
    local x = pendingPointerHoverX
    local y = pendingPointerHoverY
    pendingPointerHoverX = nil
    pendingPointerHoverY = nil
    if x == nil or y == nil or not panelRef then
      return
    end
    local rx = math.floor(x + 0.5)
    local ry = math.floor(y + 0.5)
    if rx == lastPointerHoverX and ry == lastPointerHoverY then
      return
    end
    lastPointerHoverX = rx
    lastPointerHoverY = ry
    panelRef:evaluateJavaScript(
      "window.tapshopPointerHoverAt && window.tapshopPointerHoverAt("
        .. string.format("%.2f", x)
        .. ","
        .. string.format("%.2f", y)
        .. ")"
    )
  end

  -- Non-key webviews often skip CSS :hover; drive control hover from live
  -- mouse vs webview:frame(). HS webview frames are Y-flipped (top-left origin,
  -- same as DOM) — same space used by topLeft persistence and drag/resize.
  local function updatePointerHover(panelRef)
    local view = panelRef and panelRef.getWebview and panelRef:getWebview() or nil
    if not view then
      return
    end

    local mouseApi = hs.mouse
    if not mouseApi or type(mouseApi.absolutePosition) ~= "function" then
      return
    end
    local ok, pt = pcall(mouseApi.absolutePosition)
    if not ok or type(pt) ~= "table" then
      return
    end
    local frame = view:frame()
    if not isPointInFrame(pt, frame) then
      if pointerInsidePopover or lastPointerHoverX ~= nil or pendingPointerHoverX ~= nil then
        clearPointerHover(panelRef)
      end
      return
    end

    pointerInsidePopover = true
    pendingPointerHoverX = pt.x - frame.x
    pendingPointerHoverY = pt.y - frame.y
    if pointerHoverFlushTimer then
      return
    end
    pointerHoverFlushTimer = hs.timer.doAfter(POINTER_HOVER_INTERVAL, function()
      flushPointerHover(panelRef)
    end)
  end

  local function stopPointerHoverTap()
    if pointerHoverTap then
      pointerHoverTap:stop()
      pointerHoverTap = nil
    end
  end

  local function stopConfirmEscapeTap()
    if confirmEscapeTap then
      confirmEscapeTap:stop()
      confirmEscapeTap = nil
    end
  end

  -- Force a fresh hit-test even when client coords are unchanged (layout may
  -- have moved under a still cursor after drag/resize/bounds clamp).
  local function refreshPointerHover(panelRef)
    lastPointerHoverX = nil
    lastPointerHoverY = nil
    pendingPointerHoverX = nil
    pendingPointerHoverY = nil
    if pointerHoverFlushTimer then
      pointerHoverFlushTimer:stop()
      pointerHoverFlushTimer = nil
    end
    updatePointerHover(panelRef)
  end

  local function startPointerHoverTap()
    if pointerHoverTap or not cfg.popoverAlwaysOnTop then
      return
    end
    -- Only while shown: syncWindowLevel/refreshCache can run while hidden and
    -- would otherwise leave a process-lifetime mouseMoved tap running.
    if not (panel and panel:isShown()) then
      return
    end
    pointerHoverTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
      if not panel or not panel:isShown() or not cfg.popoverAlwaysOnTop then
        return false
      end
      updatePointerHover(panel)
      return false
    end)
    pointerHoverTap:start()
  end

  -- Non-key AOT panel never receives document keydown; Escape dismisses
  -- confirm / color picker / edit / profiles mode (do not steal Escape for close).
  local function startConfirmEscapeTap()
    stopConfirmEscapeTap()
    if not cfg.popoverAlwaysOnTop then
      return
    end
    if profileTextEntryActive then
      -- Webview is temporarily key for rename; document keydown owns Escape.
      return
    end
    confirmEscapeTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
      if not panel or not panel:isShown() or not cfg.popoverAlwaysOnTop then
        stopConfirmEscapeTap()
        return false
      end
      if profileTextEntryActive then
        return false
      end
      if event:getKeyCode() ~= escapeKeyCode then
        return false
      end
      panel:evaluateJavaScript(
        "(function(){ return !!(window.tapshopHandleEscape && window.tapshopHandleEscape()); })()"
      )
      return true
    end)
    confirmEscapeTap:start()
  end

  local function syncAlwaysOnTopFocusPolicy(panelRef)
    local view = panelRef and panelRef.getWebview and panelRef:getWebview() or nil
    if view and view.windowStyle then
      view:windowStyle(currentWindowStyle())
    end
    if panelRef and panelRef.syncAllowTextEntry then
      panelRef:syncAllowTextEntry()
    end
    if panelRef then
      panelRef:evaluateJavaScript(
        "document.body && document.body.classList.toggle('is-utility-overlay', "
          .. (cfg.popoverAlwaysOnTop and "true" or "false")
          .. ")"
      )
    end
    if cfg.popoverAlwaysOnTop then
      startPointerHoverTap()
      refreshPointerHover(panelRef or panel)
      if profileTextEntryActive then
        stopConfirmEscapeTap()
      end
    else
      stopPointerHoverTap()
      stopConfirmEscapeTap()
      clearPointerHover(panelRef or panel)
    end
  end

  local function setProfileTextEntryActive(active, panelRef)
    local next = active == true
    if profileTextEntryActive == next then
      if next then
        abandonFocusHandback()
        focusPanelWindow(panelRef or panel)
      end
      return
    end
    profileTextEntryActive = next
    if next then
      abandonFocusHandback()
    end
    syncAlwaysOnTopFocusPolicy(panelRef or panel)
    if next then
      focusPanelWindow(panelRef or panel)
    elseif cfg.popoverAlwaysOnTop then
      scheduleFocusHandback()
    end
  end

  local function clearProfileTextEntryState(panelRef)
    if not profileTextEntryActive then
      return
    end
    profileTextEntryActive = false
    syncAlwaysOnTopFocusPolicy(panelRef or panel)
    if cfg.popoverAlwaysOnTop then
      scheduleFocusHandback()
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

    local activeProfile = app.getActiveProfilePresentation and app:getActiveProfilePresentation() or {
      id = app.getActiveProfileId and app:getActiveProfileId() or 1,
      name = "Profile",
      color = nil,
    }

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
        utilityOverlay = cfg.popoverAlwaysOnTop == true,
      },
      activeProfileId = activeProfile.id,
      activeProfile = activeProfile,
      profileCount = app.getProfileCount and app:getProfileCount() or 1,
      profileRows = app.getProfileRowModels and app:getProfileRowModels() or {},
      profilePaletteColors = ProfilePalette.COLORS,
      profileListMode = profileListMode,
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

  local profileUiEpoch = 0
  local lastSlotsProfileId = nil
  local lastSlotsSignature = nil
  -- Last-known slots HTML per profile so rapid cycles can paint immediately.
  local slotsHtmlCache = {}
  local spaceGeneration = 0
  local pairingGeneration = 0
  local settleTimer = nil
  local settleSerial = 0

  local function slotsListConfig()
    return {
      hidePairButtons = cfg.popoverHidePairButtons == true,
      utilityOverlay = cfg.popoverAlwaysOnTop == true,
    }
  end

  local function slotsRenderSignature(rows)
    local parts = {}
    for i, row in ipairs(rows or {}) do
      parts[i] = table.concat({
        tostring(row.index or ""),
        tostring(row.state or ""),
        tostring(row.label or ""),
        tostring(row.className or ""),
        tostring(row.badgeText or ""),
        tostring(row.iconBundleID or ""),
        row.useYouTubeIcon and "1" or "0",
        row.iconMuted and "1" or "0",
        row.canPair and "1" or "0",
        row.canUnpair and "1" or "0",
      }, "\31")
    end
    return table.concat(parts, "\30")
  end

  local function storeSlotsCache(profileId, signature, html)
    if profileId == nil or type(html) ~= "string" then
      return
    end
    slotsHtmlCache[profileId] = {
      signature = signature,
      html = html,
      spaceGeneration = spaceGeneration,
      pairingGeneration = pairingGeneration,
    }
  end

  local function warmSlotsCacheForProfile(profileId)
    if profileId == nil or not app.getWorkspaceRowModelsForProfile then
      return false
    end
    local rows = app:getWorkspaceRowModelsForProfile(profileId)
    local signature = slotsRenderSignature(rows)
    local html = popoverRender.slotsListInnerHtml(rows, slotsListConfig())
    storeSlotsCache(profileId, signature, html)
    return true
  end

  local function prefetchNeighborCaches(profileId)
    if not app.getAdjacentNonEmptyProfileIds then
      return
    end
    local prevId, nextId = app:getAdjacentNonEmptyProfileIds(profileId)
    hs.timer.doAfter(0, function()
      if app.getActiveProfileId and app:getActiveProfileId() ~= profileId then
        return
      end
      local warmed = {}
      for _, neighborId in ipairs({ prevId, nextId }) do
        if neighborId and neighborId ~= profileId and not warmed[neighborId] then
          warmed[neighborId] = true
          local cached = slotsHtmlCache[neighborId]
          local current = cached
            and cached.spaceGeneration == spaceGeneration
            and cached.pairingGeneration == pairingGeneration
          if not current then
            warmSlotsCacheForProfile(neighborId)
          end
        end
      end
    end)
  end

  local function applySlotsPayload(payload, epoch, onApplied)
    local encoded = hs.json.encode(payload) or "{}"
    panel:evaluateJavaScript(
      "(function(){ return !!(window.tapshopApplyProfileUi && window.tapshopApplyProfileUi("
        .. encoded
        .. ")); })()",
      function(result, err)
        if epoch ~= profileUiEpoch then
          return
        end
        if err or not result then
          panel:markDirty()
          if panel:isShown() then
            queueRefresh(INTERACTIVE_REFRESH_DELAY_SECONDS)
          end
          return
        end
        if type(onApplied) == "function" then
          onApplied()
        end
        if cfg.popoverAlwaysOnTop then
          refreshPointerHover(panel)
        end
      end
    )
  end

  local function settleRebuildSlots(profileId, epoch, opts)
    opts = opts or {}
    if not panel:isShown() or not panel:hasContent() then
      return
    end
    if epoch ~= profileUiEpoch then
      return
    end
    if app.getActiveProfileId and app:getActiveProfileId() ~= profileId then
      return
    end

    local rows = app.getWorkspaceRowModelsForProfile
        and app:getWorkspaceRowModelsForProfile(profileId)
      or app:getWorkspaceRowModels()
    local signature = slotsRenderSignature(rows)

    -- Only skip the JS apply when *this controller* already committed this
    -- exact view. Do not treat "cache matches" as painted — begin is async and
    -- may not have landed, which would leave the previous bank on screen.
    if profileId == lastSlotsProfileId and signature == lastSlotsSignature then
      prefetchNeighborCaches(profileId)
      return
    end

    local cached = slotsHtmlCache[profileId]
    local slotsHtml
    if cached
      and cached.signature == signature
      and cached.spaceGeneration == spaceGeneration
      and cached.pairingGeneration == pairingGeneration
      and type(cached.html) == "string"
    then
      slotsHtml = cached.html
    else
      slotsHtml = popoverRender.slotsListInnerHtml(rows, slotsListConfig())
      storeSlotsCache(profileId, signature, slotsHtml)
    end

    local activeProfile = app.getActiveProfilePresentation and app:getActiveProfilePresentation() or {
      id = profileId,
      name = "Profile",
      color = nil,
    }
    applySlotsPayload({
      activeProfile = activeProfile,
      returnToSlots = opts.returnToSlots == true,
      epoch = epoch,
      slotsHtml = slotsHtml,
    }, epoch, function()
      lastSlotsProfileId = profileId
      lastSlotsSignature = signature
    end)
    prefetchNeighborCaches(profileId)
  end

  local function scheduleSettleRebuild(profileId, epoch, opts)
    settleSerial = settleSerial + 1
    local serial = settleSerial
    if settleTimer then
      settleTimer:stop()
      settleTimer = nil
    end
    settleTimer = hs.timer.doAfter(PROFILE_SWITCH_SETTLE_SECONDS, function()
      settleTimer = nil
      if serial ~= settleSerial then
        return
      end
      settleRebuildSlots(profileId, epoch, opts)
    end)
  end

  local function flushQueuedRefresh()
    pendingRefresh = false
    stopRefreshTimer()
    applyPendingActiveWin()

    -- Do not tear down an in-progress rename; apply when edit ends.
    if profileTextEntryActive then
      deferredRefreshWhileEditing = true
      panel:markDirty()
      return
    end

    lastSlotsProfileId = nil
    lastSlotsSignature = nil
    -- Generations are bumped by the requestRefresh reason (or surgical invalidate).
    -- Do not nuke neighbor caches here on every full rebuild.

    if panel:isShown() then
      clearProfileTextEntryState(panel)
      stopConfirmEscapeTap()
      panel:refresh()
      -- Full HTML rebuild drops DOM hover classes and body flags; re-apply policy.
      syncAlwaysOnTopFocusPolicy(panel)
      requestBoundsRecompute(panel)
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

  local function pushProfileUiUpdate(opts)
    if not panel:isShown() or not panel:hasContent() then
      return false
    end

    opts = opts or {}
    profileUiEpoch = profileUiEpoch + 1
    local epoch = profileUiEpoch
    if opts.clientEpoch ~= nil then
      local clientEpoch = math.floor(tonumber(opts.clientEpoch) or 0)
      if clientEpoch > epoch then
        profileUiEpoch = clientEpoch
        epoch = clientEpoch
      end
    end

    local activeProfile = app.getActiveProfilePresentation and app:getActiveProfilePresentation() or {
      id = app.getActiveProfileId and app:getActiveProfileId() or 1,
      name = "Profile",
      color = nil,
    }
    local returnToSlots = opts.returnToSlots == true
    local profileId = activeProfile.id
    local cached = slotsHtmlCache[profileId]
    local payload = {
      activeProfile = activeProfile,
      returnToSlots = returnToSlots,
      epoch = epoch,
    }

    -- Paint chrome immediately; include cached slots when warm so rapid cycles
    -- never sit blank waiting for Accessibility probes.
    if opts.beginSwitch == true then
      -- Click path already ran an optimistic client begin for this epoch.
      -- Lua owns begin only for hotkeys / non-client switches.
      local clientOwnedBegin = opts.clientEpoch ~= nil
      if not clientOwnedBegin then
        -- Begin is async and may omit slotsHtml on cache miss. When settle will
        -- follow, invalidate the "already committed" marker so settle cannot no-op
        -- and leave the wrong bank on screen.
        if opts.settleSlots == true then
          lastSlotsProfileId = nil
          lastSlotsSignature = nil
        end

        local beginPayload = {
          epoch = epoch,
          activeProfile = activeProfile,
          returnToSlots = returnToSlots,
        }
        -- Only paint generation-current cache; stale Space/pairing HTML is worse
        -- than keeping the previous bank until settle.
        if cached
          and type(cached.html) == "string"
          and cached.spaceGeneration == spaceGeneration
          and cached.pairingGeneration == pairingGeneration
        then
          beginPayload.slotsHtml = cached.html
        end
        local beginEncoded = hs.json.encode(beginPayload) or "{}"
        panel:evaluateJavaScript(
          "(function(){ return !!(window.tapshopBeginProfileSwitch && window.tapshopBeginProfileSwitch("
            .. beginEncoded
            .. ")); })()"
        )
      elseif opts.settleSlots == true then
        -- Client begin already painted; still force settle to apply truth.
        lastSlotsProfileId = nil
        lastSlotsSignature = nil
      end
    end

    if opts.includeProfiles == true then
      local profileRows = app.getProfileRowModels and app:getProfileRowModels() or {}
      payload.profilesHtml = popoverRender.profilesListInnerHtml(profileRows)
    end

    -- Happy-path switches: coalesce row truth until the bank settles.
    if opts.settleSlots == true then
      scheduleSettleRebuild(profileId, epoch, {
        returnToSlots = returnToSlots,
        skipUnchangedSlots = true,
      })
      if payload.profilesHtml then
        applySlotsPayload(payload, epoch)
      end
      return true
    end

    if opts.includeSlots ~= false then
      local rows = app:getWorkspaceRowModels()
      local signature = slotsRenderSignature(rows)
      local unchanged = opts.skipUnchangedSlots == true
        and profileId == lastSlotsProfileId
        and signature == lastSlotsSignature
      if unchanged then
        if not payload.profilesHtml then
          return true
        end
      else
        local slotsHtml = popoverRender.slotsListInnerHtml(rows, slotsListConfig())
        payload.slotsHtml = slotsHtml
        storeSlotsCache(profileId, signature, slotsHtml)
        applySlotsPayload(payload, epoch, function()
          lastSlotsProfileId = profileId
          lastSlotsSignature = signature
        end)
        return true
      end
    end

    applySlotsPayload(payload, epoch)
    return true
  end

  panel = webviewPanel.new({
    messageHandler = "tapshop",
    initialRect = function()
      local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
      return centeredRect(screen)
    end,
    -- Always on Top: borderless|nonactivating + allowTextEntry false so the
    -- panel accepts mouse without becoming key (A+B). Do not hs.focus() it.
    windowStyle = currentWindowStyle,
    transparent = true,
    level = currentPopoverLevel,
    behavior = currentPopoverBehavior,
    -- false while Always on Top: HS uses this for canBecomeKeyWindow.
    -- Profile rename temporarily opts into text entry even under AOT.
    allowTextEntry = function()
      return (not cfg.popoverAlwaysOnTop) or profileTextEntryActive
    end,
    buildHtml = function()
      return popoverRender.buildHtml(buildRenderContext())
    end,
    handleAction = function(panelRef, msg)
      local body = msg.body or {}
      local action = body.action

      if action == "dragStart" then
        isDragging = true
        clearPointerHover(panelRef)
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
        if cfg.popoverAlwaysOnTop then
          refreshPointerHover(panelRef)
        end
        return
      end
      if action == "unpairAllConfirmOpen" then
        startConfirmEscapeTap()
        if cfg.popoverAlwaysOnTop then
          refreshPointerHover(panelRef)
        end
        return
      end
      if action == "unpairAllConfirmClose" then
        if cfg.popoverAlwaysOnTop then
          panelRef:evaluateJavaScript(
            "(function(){ return !!(window.tapshopNeedsEscapeArm && window.tapshopNeedsEscapeArm()); })()",
            function(needsArm)
              if needsArm then
                startConfirmEscapeTap()
              else
                stopConfirmEscapeTap()
              end
            end
          )
          refreshPointerHover(panelRef)
        else
          stopConfirmEscapeTap()
        end
        return
      end
      if action == "profileUiArmEscape" then
        startConfirmEscapeTap()
        return
      end
      if action == "profileUiDisarmEscape" then
        stopConfirmEscapeTap()
        return
      end
      if action == "profileEditBegin" then
        setProfileTextEntryActive(true, panelRef)
        return
      end
      if action == "profileEditEnd" then
        setProfileTextEntryActive(false, panelRef)
        if deferredRefreshWhileEditing then
          deferredRefreshWhileEditing = false
          queueRefresh(INTERACTIVE_REFRESH_DELAY_SECONDS)
        end
        if cfg.popoverAlwaysOnTop then
          panelRef:evaluateJavaScript(
            "(function(){ return !!(window.tapshopNeedsEscapeArm && window.tapshopNeedsEscapeArm()); })()",
            function(needsArm)
              if needsArm then
                startConfirmEscapeTap()
              else
                stopConfirmEscapeTap()
              end
            end
          )
        end
        return
      end
      if action == "profileModeChanged" then
        local mode = tostring(body.mode or "")
        profileListMode = mode == "profiles" and "profiles" or "slots"
        return
      end
      if action == "resizeStart" then
        isResizing = true
        resizeDirection = tostring(body.direction or "")
        clearPointerHover(panelRef)
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
          if cfg.popoverAlwaysOnTop then
            refreshPointerHover(panelRef)
          end
        end
        return
      end
      if action == "resizeEnd" then
        isResizing = false
        resizeDirection = ""
        saveTopLeftFromFrame(panelRef)
        saveSizeFromFrame(panelRef)
        if cfg.popoverAlwaysOnTop then
          refreshPointerHover(panelRef)
        end
        return
      end
      if action == "close" then
        panelRef:hide()
        if app.notePopoverIntentionalDismiss then
          app:notePopoverIntentionalDismiss()
        end
        return
      end

      if action == "pair" then
        body.sourceWindow = activeWin or callerWin
      end
      local result = app:handlePopoverAction(body)
      -- Slot activate / pair intentionally change frontmost; abandon any
      -- accidental-focus handback so we do not undo that navigation.
      if action == "activateSlot" or action == "pair" then
        abandonFocusHandback()
      end
      if action == "setAlwaysOnTop" then
        panelRef:setLevel(currentPopoverLevel())
        syncAlwaysOnTopFocusPolicy(panelRef)
        -- Leaving utility-overlay mode: take normal key focus again.
        if not cfg.popoverAlwaysOnTop and panelRef:isShown() then
          focusPanelWindow(panelRef)
          panelRef:evaluateJavaScript(
            "window.tapshopFocusKeyboardSurface && window.tapshopFocusKeyboardSurface()"
          )
        end
      end
      if result ~= false and cfg.popoverAutoHideAfterAction and AUTO_HIDE_ACTIONS[action] then
        abandonFocusHandback()
        panelRef:hide()
        if app.notePopoverIntentionalDismiss then
          app:notePopoverIntentionalDismiss()
        end
      end
      return result
    end,
    windowCallback = function(panelRef, act, _, focusState)
      if act == "focusChange" then
        isFocused = focusState == true
        if focusState == true and cfg.popoverAlwaysOnTop and not profileTextEntryActive then
          scheduleFocusHandback()
        elseif focusState == false and panelRef:isShown() and not cfg.popoverAlwaysOnTop then
          panelRef:hide()
          if app.notePopoverIntentionalDismiss then
            app:notePopoverIntentionalDismiss()
          end
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
      syncAlwaysOnTopFocusPolicy(panelRef)
      -- Keyboard surface only when this panel is allowed to become key.
      if not cfg.popoverAlwaysOnTop then
        panelRef:evaluateJavaScript("window.tapshopFocusKeyboardSurface && window.tapshopFocusKeyboardSurface()")
      end
    end,
    beforeHide = function()
      isDragging = false
      isResizing = false
      resizeDirection = ""
      isFocused = false
      clearProfileTextEntryState(panel)
      stopPointerHoverTap()
      stopConfirmEscapeTap()
      clearPointerHover(panel)
      panel:evaluateJavaScript(
        "window.tapshopResetInteractionGestures && window.tapshopResetInteractionGestures()"
      )
    end,
  })

  local instance = {}

  function instance:show()
    panel:show()
  end

  function instance:hide()
    panel:hide()
  end

  function instance:isShown()
    return panel:isShown()
  end

  -- Re-assert visibility after Space changes. isShown can stay true while AppKit
  -- has ordered the webview out during a fullscreen Space visit.
  function instance:ensureVisible()
    if panel:isShown() then
      local view = panel.getWebview and panel:getWebview() or nil
      if view and view.show then
        view:show()
      end
      panel:setLevel(currentPopoverLevel())
      panel:syncBehavior()
      return
    end
    panel:show()
  end

  function instance:toggle()
    local wasShown = panel:isShown()
    panel:toggle()
    if wasShown and not panel:isShown() and app.notePopoverIntentionalDismiss then
      app:notePopoverIntentionalDismiss()
    end
  end

  function instance:toggleOrFocus()
    if cfg.popoverAlwaysOnTop then
      if panel:isShown() then
        panel:hide()
        if app.notePopoverIntentionalDismiss then
          app:notePopoverIntentionalDismiss()
        end
      else
        panel:show()
      end
      return
    end

    if panel:isShown() and isFocused then
      panel:hide()
      if app.notePopoverIntentionalDismiss then
        app:notePopoverIntentionalDismiss()
      end
      return
    end

    panel:show()
  end

  function instance:refreshIfShown()
    if panel:isShown() then
      clearProfileTextEntryState(panel)
      stopConfirmEscapeTap()
      panel:refresh()
      syncAlwaysOnTopFocusPolicy(panel)
      requestBoundsRecompute(panel)
      return
    end
    panel:markDirty()
  end

  function instance:syncWindowLevel()
    panel:setLevel(currentPopoverLevel())
    panel:syncBehavior()
    syncAlwaysOnTopFocusPolicy(panel)
  end

  function instance:refreshCache()
    panel:markDirty()
    cachedThemeCss = nil
    lastSlotsProfileId = nil
    lastSlotsSignature = nil
    slotsHtmlCache = {}
    spaceGeneration = spaceGeneration + 1
    pairingGeneration = pairingGeneration + 1
    panel:setLevel(currentPopoverLevel())
    panel:syncBehavior()
    syncAlwaysOnTopFocusPolicy(panel)
    if panel:isShown() then
      clearProfileTextEntryState(panel)
      stopConfirmEscapeTap()
      if panel.hasContent and panel:hasContent() then
        panel:evaluateJavaScript("window.tapshopSlotsHtmlByProfile={};true")
      end
      panel:refresh()
      requestBoundsRecompute(panel)
    end
  end

  function instance:warmStaticCaches()
    local theme = popoverStyles.buildTheme(cfg)
    cachedThemeCss = popoverStyles.buildCss(theme)
  end

  function instance:requestRefresh(reason, win, opts)
    if win ~= nil then
      pendingActiveWin = win
    end
    opts = opts or {}

    if reason == "profile_switch" or reason == "profile_metadata" or reason == "profile_validation" then
      local modeOnly = opts.modeOnly == true
      if pushProfileUiUpdate({
        returnToSlots = reason == "profile_switch" and opts.returnToSlots == true,
        includeSlots = reason ~= "profile_metadata" and not modeOnly,
        includeProfiles = reason == "profile_metadata",
        skipUnchangedSlots = reason == "profile_validation",
        beginSwitch = reason == "profile_switch",
        settleSlots = reason == "profile_switch" and not modeOnly,
        clientEpoch = opts.clientEpoch,
      }) then
        return
      end
      queueRefresh(INTERACTIVE_REFRESH_DELAY_SECONDS)
      return
    end

    -- Lifecycle / workspace truth: prefer surgical slots apply so neighbor caches survive.
    if reason == "window_destroyed"
      or reason == "fullscreen_change"
      or reason == "workspace_state"
      or reason == "window_event"
      or reason == "slot_space_switch_result"
    then
      -- While renaming, skip profilesHtml so tapshopApplyProfileUi cannot
      -- rehydrate beginProfileEdit from server name/color and wipe the draft.
      if pushProfileUiUpdate({
        includeSlots = true,
        includeProfiles = profileListMode == "profiles" and not profileTextEntryActive,
        skipUnchangedSlots = false,
      }) then
        return
      end
      queueRefresh(INTERACTIVE_REFRESH_DELAY_SECONDS)
      return
    end

    if reason == "focused_space_change" then
      spaceGeneration = spaceGeneration + 1
    end

    queueRefresh()
  end

  function instance:invalidateSlotsCache(opts)
    opts = opts or {}
    if opts.space == true then
      spaceGeneration = spaceGeneration + 1
    end
    if opts.pairing == true then
      pairingGeneration = pairingGeneration + 1
    end
    local clearedIds = {}
    if opts.profileId ~= nil then
      slotsHtmlCache[opts.profileId] = nil
      clearedIds[#clearedIds + 1] = opts.profileId
    elseif opts.all == true then
      slotsHtmlCache = {}
      clearedIds = nil
    end
    -- Drop the client HTML mirror so click-begin cannot paint pre-mutation banks.
    if panel and panel.hasContent and panel:hasContent() then
      local js
      if clearedIds == nil then
        js = "window.tapshopSlotsHtmlByProfile={};true"
      elseif #clearedIds > 0 then
        local parts = {}
        for i, id in ipairs(clearedIds) do
          parts[i] = "delete window.tapshopSlotsHtmlByProfile[" .. tostring(id) .. "]"
        end
        js = "if(window.tapshopSlotsHtmlByProfile){" .. table.concat(parts, ";") .. "};true"
      end
      if js then
        panel:evaluateJavaScript(js)
      end
    end
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
