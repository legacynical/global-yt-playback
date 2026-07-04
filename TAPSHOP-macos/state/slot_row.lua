local SlotRow = {}

local APPEARANCE = {
  empty = {
    className = "unpaired",
    badgeText = nil,
    showIcon = false,
    muteIcon = false,
  },
  paired = {
    className = "paired",
    badgeText = nil,
    showIcon = true,
    muteIcon = false,
  },
  minimized = {
    className = "paired-minimized",
    badgeText = "MIN",
    showIcon = true,
    muteIcon = false,
  },
  fullscreen = {
    className = "paired-fullscreen",
    badgeText = "FULL",
    showIcon = true,
    muteIcon = false,
  },
  off_space = {
    className = "paired-off-space",
    badgeText = nil,
    showIcon = true,
    muteIcon = false,
  },
  unresolved = {
    className = "paired-unresolved",
    badgeText = nil,
    showIcon = true,
    muteIcon = false,
  },
  recoverable = {
    className = "recoverable",
    badgeText = nil,
    showIcon = true,
    muteIcon = true,
  },
}

local function rowLabelForWindow(windowService, win)
  if windowService.windowTitle then
    return windowService.windowTitle(win)
  end
  return windowService.displayTitle(win)
end

local function iconFieldsForWindow(win, fallbackBundleID, fallbackAppName)
  local app = win and win:application() or nil
  return app and app:bundleID() or fallbackBundleID, app and app:name() or fallbackAppName
end

local function isOffSpace(slot, session)
  local focusedSpaceId = session and session.focusedSpaceId or nil
  local baseSpaceId = slot.getBaseSpaceId and slot:getBaseSpaceId() or nil

  return baseSpaceId ~= nil
    and focusedSpaceId ~= nil
    and baseSpaceId ~= focusedSpaceId
end

function SlotRow.build(slot, session, deps)
  local windowService = deps.windowService
  local fingerprint = slot:getFingerprint() or {}
  local bindingKind = slot:getBindingKind()
  local windowId = slot:getBaseWindowId()
  local state = "empty"
  local label = "[empty]"
  local iconBundleID = nil
  local iconAppName = nil
  local baseWin = nil

  if bindingKind == "paired" and windowId ~= nil then
    baseWin = windowService.getWindowById(windowId)
    if slot:hasTrackedFullscreenTarget() then
      local fullscreenWin = windowService.getWindowById(slot:getFullscreenTargetWindowId())
      state = "fullscreen"
      if fullscreenWin then
        label = rowLabelForWindow(windowService, fullscreenWin)
        iconBundleID, iconAppName = iconFieldsForWindow(fullscreenWin, fingerprint.bundleID, fingerprint.appName)
      else
        label = slot:getStoredWindowTitle()
        iconBundleID = fingerprint.bundleID
        iconAppName = fingerprint.appName
      end
    end

    if state ~= "fullscreen" then
      if isOffSpace(slot, session) then
        state = "off_space"
        if baseWin then
          label = rowLabelForWindow(windowService, baseWin)
          iconBundleID, iconAppName = iconFieldsForWindow(baseWin, fingerprint.bundleID, fingerprint.appName)
        else
          label = slot:getStoredWindowTitle()
          iconBundleID = fingerprint.bundleID
          iconAppName = fingerprint.appName
        end
      elseif baseWin then
        state = baseWin:isMinimized() and "minimized" or "paired"
        label = rowLabelForWindow(windowService, baseWin)
        iconBundleID, iconAppName = iconFieldsForWindow(baseWin, fingerprint.bundleID, fingerprint.appName)
      else
        state = "unresolved"
        label = slot:getStoredWindowTitle()
        iconBundleID = fingerprint.bundleID
        iconAppName = fingerprint.appName
      end
    end
  elseif bindingKind == "recoverable" then
    state = "recoverable"
    label = slot:getStoredWindowTitle()
    iconBundleID = fingerprint.bundleID
    iconAppName = fingerprint.appName
  end

  local appearance = APPEARANCE[state] or APPEARANCE.empty
  if not appearance.showIcon then
    iconBundleID = nil
    iconAppName = nil
  end

  return {
    index = slot:getIndex(),
    label = label,
    state = state,
    canPair = true,
    canUnpair = bindingKind == "paired" or bindingKind == "recoverable",
    iconBundleID = iconBundleID,
    iconAppName = iconAppName,
    iconMuted = appearance.muteIcon == true,
    badgeText = appearance.badgeText,
    className = appearance.className,
  }
end

function SlotRow.buildRows(slots, session, deps)
  local rows = {}
  for _, slot in ipairs(slots or {}) do
    rows[#rows + 1] = SlotRow.build(slot, session, deps)
  end
  return rows
end

return SlotRow
