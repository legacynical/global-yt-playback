-- AppState: TAPSHOP macos session orchestrator (profiles, slots, window events,
-- hotkey actions, popover/settings wiring). Hotkeys call public methods here;
-- WindowService / YoutubeService / SpotifyService own lower-level mechanics.
--
-- Persistence: pairing and active-profile writes are coalesced (idle / short
-- delay), not flushed on every focus event. Space validation for a newly
-- activated profile is deferred off the switch edge.

local Workspace = require("state.workspace")
local SlotRecord = require("state.slot_record")
local SlotRow = require("state.slot_row")
local Layout = require("state.layout")
local ProfilePalette = require("state.profile_palette")
local PopoverFullscreenVisibility = require("state.popover_fullscreen_visibility")
local Toast = require("ui.toast")

local AppState = {}
AppState.__index = AppState
local ACTIVE_PROFILE_PERSIST_DELAY_SECONDS = 0.05
-- First shallow→active bank entry: defer Spaces reconcile off the switch edge.
local ACTIVE_PROFILE_VALIDATION_DELAY_SECONDS = 0.20
-- Lifecycle pairing checkpoints: idle coalesce, not near-realtime durability.
local WORKSPACE_PAIRING_PERSIST_IDLE_SECONDS = 5.0
local PAIR_TOAST_COLOR = { red = 0x7e / 255, green = 0xc8 / 255, blue = 0x7e / 255, alpha = 1 }
local UNPAIR_TOAST_COLOR = { red = 0xc0 / 255, green = 0x40 / 255, blue = 0x30 / 255, alpha = 1 }
local HOTKEY_WARNING_TOAST_COLOR = { red = 0xf2 / 255, green = 0xc1 / 255, blue = 0x4e / 255, alpha = 1 }
local TOAST_WHITE = { white = 1, alpha = 1 }

local function loadPersistedWorkspacePairings(appdata)
  if appdata.getProfilesWindowPairings then
    return appdata.getProfilesWindowPairings()
  end
  return {
    [1] = appdata.getWindowPairings(),
  }
end

local function deepEqual(left, right)
  if type(left) ~= type(right) then
    return false
  end
  if type(left) ~= "table" then
    return left == right
  end

  for key, value in pairs(left) do
    if not deepEqual(value, right[key]) then
      return false
    end
  end

  for key, value in pairs(right) do
    if not deepEqual(value, left[key]) then
      return false
    end
  end

  return true
end

function AppState.new(cfg, deps)
  local initialProfileId = deps.appdata.getActiveProfileId and deps.appdata.getActiveProfileId() or 1
  local self = setmetatable({
    cfg = cfg,
    settings = deps.settings,
    appdata = deps.appdata,
    windowService = deps.windowService,
    youtubeService = deps.youtubeService,
    spotifyService = deps.spotifyService,
    systemAudioService = deps.systemAudioService,
    debugLogger = deps.debugLogger,
    toast = deps.toast,
    profiles = {},
    session = {
      focusedSpaceId = nil,
      activeProfileId = initialProfileId,
      recoveryMatchIndex = nil,
      recoveryMatchIndexDirty = true,
      recoverableSlotCount = 0,
    },
    hotkeyManager = nil,
    popover = nil,
    settingsWindow = nil,
    activeProfilePersistTimer = nil,
    activeProfileValidationTimer = nil,
    pendingActiveProfileId = nil,
    workspacePairingPersistTimer = nil,
    workspacePairingPersistDirty = false,
  }, AppState)

  for profileId = 1, Layout.MAX_PROFILES do
    local profile = {
      id = profileId,
      name = ProfilePalette.defaultName(profileId),
      color = ProfilePalette.defaultColor(profileId),
      workspaces = {},
      needsExactValidation = profileId ~= initialProfileId,
    }
    for slotIndex = 1, Layout.SLOTS_PER_PROFILE do
      profile.workspaces[#profile.workspaces + 1] = Workspace.new(
        slotIndex,
        string.format("Profile %d / Window %d", profileId, slotIndex),
        cfg.minimizeThreshold
      )
    end
    self.profiles[#self.profiles + 1] = profile
  end

  self:_restoreProfileMetadata()
  self:_refreshFocusedSpaceId()
  self:_restoreStartupWorkspaceState()
  self:_initPopoverFullscreenVisibility()
  return self
end

function AppState:_initPopoverFullscreenVisibility()
  self.popoverFullscreenVisibility = PopoverFullscreenVisibility.new({
    isEnabled = function()
      return self.cfg.popoverHideOnFullscreenWorkspace == true
    end,
    isSpaceFullscreen = function(spaceId)
      return self:_spaceIsFullscreen(spaceId)
    end,
    getFocusedSpaceId = function()
      return self.session.focusedSpaceId
    end,
    refreshFocusedSpaceId = function()
      return self:_refreshFocusedSpaceId()
    end,
    getPopover = function()
      return self.popover
    end,
  })
end

function AppState:_popoverFullscreenPolicy()
  if not self.popoverFullscreenVisibility then
    self:_initPopoverFullscreenVisibility()
  end
  return self.popoverFullscreenVisibility
end

function AppState:attachUi(popover, settingsWindow)
  self.popover = popover
  self.settingsWindow = settingsWindow
end

function AppState:notePopoverIntentionalDismiss()
  local policy = self:_popoverFullscreenPolicy()
  if policy then
    policy:noteIntentionalDismiss()
  end
end

function AppState:attachHotkeyManager(hotkeyManager)
  self.hotkeyManager = hotkeyManager
end

function AppState:getWorkspaces()
  local profile = self:_getActiveProfile()
  return profile and profile.workspaces or {}
end

function AppState:getConfig()
  return self.cfg
end

function AppState:_getProfile(profileId)
  local normalized = tonumber(profileId)
  if not normalized then
    return nil
  end
  normalized = math.floor(normalized)
  if normalized < 1 or normalized > #self.profiles then
    return nil
  end
  return self.profiles[normalized]
end

function AppState:_getActiveProfile()
  return self:_getProfile(self.session.activeProfileId)
end

function AppState:_forEachWorkspace(visitor)
  if type(visitor) ~= "function" then
    return
  end

  for _, profile in ipairs(self.profiles) do
    for _, workspace in ipairs(profile.workspaces or {}) do
      visitor(workspace, profile)
    end
  end
end

function AppState:_refreshFocusedSpaceId()
  if self.windowService and self.windowService.focusedSpaceId then
    self.session.focusedSpaceId = self.windowService.focusedSpaceId()
  end
  return self.session.focusedSpaceId
end

local function safeValue(fn)
  local ok, value = pcall(fn)
  if ok then
    return value
  end
  return nil
end

function AppState:_debugEnabled(domain, level, event, fields)
  if not self.debugLogger or not self.debugLogger.enabled then
    return false
  end
  return self.debugLogger:enabled(domain, level, event, fields)
end

function AppState:_recordDebug(domain, level, event, message, payloadFn, fields)
  if not self.debugLogger or not self.debugLogger.record then
    return false
  end
  return self.debugLogger:record(domain, level, event, message, payloadFn, fields)
end

function AppState:_windowDebugSnapshot(win)
  if not win then
    return nil
  end

  local app = safeValue(function()
    return win:application()
  end)
  local spaces = nil
  if self.windowService and self.windowService.getWindowSpaces then
    spaces = safeValue(function()
      return self.windowService.getWindowSpaces(win)
    end)
  end

  return {
    windowId = safeValue(function()
      return win:id()
    end),
    windowTitle = safeValue(function()
      return win:title()
    end),
    isVisible = safeValue(function()
      return win:isVisible()
    end),
    isStandard = safeValue(function()
      return win:isStandard()
    end),
    isMinimized = safeValue(function()
      return win:isMinimized()
    end),
    isFullscreen = safeValue(function()
      return win:isFullScreen()
    end),
    spaceIds = spaces,
    bundleID = app and safeValue(function()
      return app:bundleID()
    end) or nil,
    appName = app and safeValue(function()
      return app:name()
    end) or nil,
  }
end

function AppState:getWorkspaceRowModels()
  self:_refreshFocusedSpaceId()
  return SlotRow.buildRows(self:getWorkspaces(), self.session, {
    windowService = self.windowService,
    youtubeService = self.youtubeService,
  })
end

-- Build slot rows for any profile bank without changing the active profile.
-- Used to warm neighbor caches after a settle-gated switch.
function AppState:getWorkspaceRowModelsForProfile(profileId)
  local profile = self:_getProfile(profileId)
  if not profile then
    return {}
  end
  self:_refreshFocusedSpaceId()
  return SlotRow.buildRows(profile.workspaces or {}, self.session, {
    windowService = self.windowService,
    youtubeService = self.youtubeService,
  })
end

-- Previous/next non-empty profile ids for cycle prefetch (wraps; may be empty).
function AppState:getAdjacentNonEmptyProfileIds(profileId)
  local count = self:getProfileCount()
  if count < 1 then
    return nil, nil
  end
  local current = tonumber(profileId) or self.session.activeProfileId
  local prevId, nextId = nil, nil
  for offset = 1, count do
    local candidate = current - offset
    if candidate < 1 then
      candidate = candidate + count
    end
    if candidate ~= current and self:_profileIsNonEmpty(candidate) then
      prevId = candidate
      break
    end
  end
  for offset = 1, count do
    local candidate = current + offset
    if candidate > count then
      candidate = candidate - count
    end
    if candidate ~= current and self:_profileIsNonEmpty(candidate) then
      nextId = candidate
      break
    end
  end
  return prevId, nextId
end

function AppState:getProfilePairedCount(profileId)
  local profile = self:_getProfile(profileId)
  if not profile then
    return 0
  end
  local count = 0
  for _, workspace in ipairs(profile.workspaces or {}) do
    if workspace and (workspace:isPaired() or workspace:isRecoverable()) then
      count = count + 1
    end
  end
  return count
end

function AppState:getProfileDisplayName(profileId)
  local profile = self:_getProfile(profileId)
  if not profile then
    return ProfilePalette.defaultName(profileId)
  end
  return ProfilePalette.normalizeName(profile.name, profile.id)
end

function AppState:getProfileColor(profileId)
  local profile = self:_getProfile(profileId)
  if not profile then
    return ProfilePalette.defaultColor(profileId)
  end
  return ProfilePalette.normalizeColor(profile.color)
end

function AppState:getProfileRowModels()
  local rows = {}
  local activeId = self.session.activeProfileId
  for _, profile in ipairs(self.profiles) do
    local pairedCount = self:getProfilePairedCount(profile.id)
    rows[#rows + 1] = {
      id = profile.id,
      name = self:getProfileDisplayName(profile.id),
      color = self:getProfileColor(profile.id),
      pairedCount = pairedCount,
      isActive = profile.id == activeId,
      isEmpty = pairedCount <= 0,
    }
  end
  return rows
end

function AppState:getActiveProfilePresentation()
  local id = self.session.activeProfileId
  return {
    id = id,
    name = self:getProfileDisplayName(id),
    color = self:getProfileColor(id),
  }
end

function AppState:getProfileCount()
  return #self.profiles
end

function AppState:getActiveProfileId()
  return self.session.activeProfileId
end

function AppState:getWindowInfo(win)
  return self.windowService.getWindowInfo(win)
end

function AppState:getYouTubeTargetId()
  return self.youtubeService:getTargetId()
end

function AppState:syncUi(opacityPercent)
  if opacityPercent then
    if self.popover and self.popover.pushOpacityUpdate then
      self.popover:pushOpacityUpdate(opacityPercent)
    end
    if self.settingsWindow and self.settingsWindow.pushOpacityUpdate then
      self.settingsWindow:pushOpacityUpdate(opacityPercent)
    end
  end

  local components = {
    self.popover,
    self.settingsWindow,
  }

  for _, component in ipairs(components) do
    if component and component.refreshCache then
      component:refreshCache()
    elseif component and component.refreshIfShown then
      component:refreshIfShown()
    end
  end
end

function AppState:_syncWorkspaceUi(reason, opts)
  if self.popover and self.popover.requestRefresh then
    self.popover:requestRefresh(reason or "workspace_state", nil, opts)
  elseif self.popover and self.popover.refreshIfShown then
    self.popover:refreshIfShown()
  end
end

-- Drop cached slots HTML for a profile after pairing/recovery mutations so
-- begin-paint cannot flash pre-mutation banks during rapid switches.
function AppState:_invalidateProfileSlotsCache(profileId)
  if profileId == nil or not self.popover or not self.popover.invalidateSlotsCache then
    return false
  end
  self.popover:invalidateSlotsCache({
    profileId = profileId,
    pairing = true,
  })
  return true
end

function AppState:_profileIdForWorkspace(workspace)
  if not workspace then
    return nil
  end
  for _, profile in ipairs(self.profiles or {}) do
    for _, candidate in ipairs(profile.workspaces or {}) do
      if candidate == workspace then
        return profile.id
      end
    end
  end
  return nil
end

function AppState:_invalidateWorkspaceSlotsCache(workspace, profileId)
  local id = profileId or self:_profileIdForWorkspace(workspace) or self.session.activeProfileId
  return self:_invalidateProfileSlotsCache(id)
end

function AppState:_runPairingAction(actionFn)
  if self.windowService and self.windowService.cancelPendingFrontmostRequest then
    self.windowService.cancelPendingFrontmostRequest()
  end
  actionFn()
  self:_persistWorkspacePairingsNow()
  self:_invalidateProfileSlotsCache(self.session.activeProfileId)
  self:_syncWorkspaceUi()
  if self.cfg.popoverAutoHideAfterAction and self.popover and self.popover.hide then
    local wasShown = self.popover.isShown and self.popover:isShown()
    self.popover:hide()
    -- Only clear the FS restore pin when this action actually dismissed a
    -- shown panel. If policy already hid for a fullscreen Space, keep the pin.
    if wasShown then
      self:notePopoverIntentionalDismiss()
    end
  end
  return true
end

-- Slot hotkeys: cancel in-flight focus, run the action, optionally paint.
-- Pure focus hops should pass syncUi=false; pair / badge / Space corrections
-- opt in so mashable ⌘⌥N does not rebuild popover JS every press.
function AppState:_runWorkspaceAction(actionFn, opts)
  if self.windowService and self.windowService.cancelPendingFrontmostRequest then
    self.windowService.cancelPendingFrontmostRequest()
  end
  actionFn()
  opts = opts or {}
  if opts.syncUi == false then
    return
  end
  self:_syncWorkspaceUi(opts.reason)
end

function AppState:_spaceIsFullscreen(spaceId)
  return spaceId ~= nil
    and type(self.windowService.isFullscreenSpace) == "function"
    and self.windowService.isFullscreenSpace(spaceId) == true
end

function AppState:_getWorkspace(index, profileId)
  local profile = self:_getProfile(profileId or self.session.activeProfileId)
  if not profile then
    return nil
  end
  return profile.workspaces[index]
end

function AppState:_resolvePairedWindow(workspace)
  if not workspace or not workspace:getBaseWindowId() then
    return nil
  end
  return self.windowService.getWindowById(workspace:getBaseWindowId())
end

function AppState:_windowTitleMatchesWorkspace(workspace, win)
  if not workspace or not win then
    return false
  end

  local meta = self.windowService.pairingMetadata and self.windowService.pairingMetadata(win)
  if not meta then
    return false
  end

  local fingerprint = workspace:getFingerprint()
  if fingerprint.bundleID and meta.bundleID and fingerprint.bundleID ~= meta.bundleID then
    return false
  end

  if fingerprint.titleNormalized
    and meta.titleNormalized
    and fingerprint.titleNormalized ~= meta.titleNormalized then
    return false
  end

  return true
end

function AppState:_resolveFullscreenTargetForActivation(workspace)
  if not workspace or not workspace:hasTrackedFullscreenTarget() then
    return nil, nil
  end

  return self:_resolveLiveWindowTargetById(workspace:getFullscreenTargetWindowId())
end

function AppState:_resolveTrackedSpaceByWindowId(windowId)
  if not windowId then
    return nil
  end

  if not self.windowService.getWindowSpacesById then
    return nil
  end

  local spaceIds = self.windowService.getWindowSpacesById(windowId)
  local _, _, resolvedSpaceId = self:_resolvedTargetSpaceFromSpaceIds(spaceIds, nil)
  return resolvedSpaceId
end

function AppState:_resolveLiveWindowTargetById(windowId)
  local resolvedSpaceId = self:_resolveTrackedSpaceByWindowId(windowId)
  if not resolvedSpaceId then
    return nil, nil
  end
  return self.windowService.getWindowById(windowId), resolvedSpaceId
end

function AppState:_restorePairedWorkspaceFromRecord(workspace, persisted, opts)
  if not workspace or type(persisted) ~= "table" then
    return false
  end

  local baseWindowId = persisted.baseWindowId
  if not baseWindowId then
    workspace:clear()
    return false
  end

  if type(opts) == "table" and opts.shallow == true then
    workspace:pair(baseWindowId, persisted.fingerprint)
    if persisted.baseSpaceId then
      workspace:setBaseSpaceId(persisted.baseSpaceId)
    end
    local fullscreenTarget = persisted.fullscreenTarget
    if type(fullscreenTarget) == "table" and fullscreenTarget.windowId and fullscreenTarget.spaceId then
      workspace:setFullscreenState({
        fullscreenWindowId = fullscreenTarget.windowId,
        fullscreenSpaceId = fullscreenTarget.spaceId,
        lastKnownSpaceId = persisted.baseSpaceId,
      })
    end
    return true
  end

  local baseWin = self.windowService.getWindowById(baseWindowId)
  if baseWin then
    workspace:pair(baseWindowId, persisted.fingerprint)
    if persisted.baseSpaceId then
      workspace:setBaseSpaceId(persisted.baseSpaceId)
    end

    local fullscreenTargetWindowId = persisted.fullscreenTarget and persisted.fullscreenTarget.windowId or nil
    local fullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId)
    if fullscreenTargetWindowId and fullscreenSpaceId then
      local fullscreenWin = self.windowService.getWindowById(fullscreenTargetWindowId)
      workspace:setFullscreenState({
        fullscreenWindowId = fullscreenTargetWindowId,
        fullscreenSpaceId = fullscreenSpaceId,
        lastKnownSpaceId = workspace:getBaseSpaceId(),
      })
      if fullscreenWin then
        self:_refreshWorkspaceFingerprint(workspace, fullscreenWin)
      end
    elseif self.windowService.isWindowFullscreen(baseWin) then
      local fullscreenSpaceId = self.windowService.getPrimarySpaceForWindow(baseWin)
      workspace:setFullscreenState({
        fullscreenWindowId = baseWin:id(),
        fullscreenSpaceId = fullscreenSpaceId,
      })
      -- Home Space is unknown while already fullscreen unless persisted above.
      if not persisted.baseSpaceId then
        workspace:setBaseSpaceId(nil)
      end
    elseif not workspace:getBaseSpaceId() then
      self:_updateWorkspaceBindingSpaceState(workspace, baseWin)
    end

    if not workspace:hasTrackedFullscreenTarget() then
      self:_refreshWorkspaceFingerprint(workspace, baseWin)
    end
    return true
  end

  local fullscreenTargetWindowId = persisted.fullscreenTarget and persisted.fullscreenTarget.windowId or nil
  local fullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId)
  if fullscreenTargetWindowId and fullscreenSpaceId then
    workspace:pair(baseWindowId, persisted.fingerprint)
    if persisted.baseSpaceId then
      workspace:setBaseSpaceId(persisted.baseSpaceId)
    end
    workspace:setFullscreenState({
      fullscreenWindowId = fullscreenTargetWindowId,
      fullscreenSpaceId = fullscreenSpaceId,
      lastKnownSpaceId = workspace:getBaseSpaceId(),
    })
    local fullscreenWin = self.windowService.getWindowById(fullscreenTargetWindowId)
    if fullscreenWin then
      self:_refreshWorkspaceFingerprint(workspace, fullscreenWin)
    end
    return true
  end

  local resolvedBaseSpaceId = self:_resolveTrackedSpaceByWindowId(baseWindowId)
  if resolvedBaseSpaceId then
    workspace:pair(baseWindowId, persisted.fingerprint)
    workspace:setBaseSpaceId(resolvedBaseSpaceId)
    return true
  end

  if self.cfg.recoverClosedWindows and type(persisted.fingerprint) == "table" then
    local fingerprint = persisted.fingerprint
    if fingerprint.bundleID and fingerprint.titleNormalized then
      workspace:setRecoverable(fingerprint)
      return false
    end
  end

  workspace:clear()
  return false
end

function AppState:_restoreWorkspaceFromPersistedRecord(workspace, persisted, opts)
  if not workspace or type(persisted) ~= "table" then
    return false
  end

  if persisted.kind == "paired" then
    return self:_restorePairedWorkspaceFromRecord(workspace, persisted, opts)
  end

  if persisted.kind == "recoverable" then
    if self.cfg.recoverClosedWindows then
      workspace:setRecoverable(persisted.fingerprint)
    else
      workspace:clear()
    end
    return false
  end

  workspace:clear()
  return false
end

-- Factory defaults are already applied; overlay persisted name/color when present.
function AppState:_restoreProfileMetadata()
  if not self.appdata or not self.appdata.getProfileRecords then
    return
  end

  local records = self.appdata.getProfileRecords()
  for profileId, record in pairs(records or {}) do
    local profile = self:_getProfile(profileId)
    if profile and type(record) == "table" then
      if record.name ~= nil then
        profile.name = ProfilePalette.normalizeName(record.name, profile.id)
      end
      if record.colorPresent then
        profile.color = ProfilePalette.normalizeColor(record.color)
      end
    end
  end
end

function AppState:_workspacePairingSnapshot(profile)
  local pairings = {}
  for index, workspace in ipairs((profile and profile.workspaces) or {}) do
    if workspace then
      local record = SlotRecord.encode(workspace.binding)
      if record then
        pairings[index] = record
      end
    end
  end
  return pairings
end

function AppState:_profilePairingSnapshot()
  local profiles = {}
  for _, profile in ipairs(self.profiles) do
    profiles[profile.id] = {
      pairings = self:_workspacePairingSnapshot(profile),
      name = ProfilePalette.normalizeName(profile.name, profile.id),
      color = ProfilePalette.normalizeColor(profile.color),
      colorPresent = true,
    }
  end
  return profiles
end

function AppState:_writeWorkspacePairingsToDisk()
  local activeProfileId = self.session.activeProfileId
  local profileSnapshot = self:_profilePairingSnapshot()
  local activeProfileSnapshot = self:_workspacePairingSnapshot(self:_getActiveProfile())
  local profileCount = 0
  for _, _ in pairs(profileSnapshot) do
    profileCount = profileCount + 1
  end
  local scope = "active_profile"

  if self.appdata.setProfilesWindowPairings then
    self.appdata.setProfilesWindowPairings(profileSnapshot)
    scope = "profiles"
  else
    self.appdata.setWindowPairings(activeProfileSnapshot)
  end

  self.workspacePairingPersistDirty = false

  self:_recordDebug("persistence", "debug", "workspace_pairings_persisted", "workspace pairings persisted", function()
    return {
      operation = "write",
      result = "ok",
      scope = scope,
      profileCount = profileCount,
      activeProfileId = activeProfileId,
    }
  end, {
    profileId = activeProfileId,
  })
end

function AppState:_scheduleWorkspacePairingPersist()
  self.workspacePairingPersistDirty = true

  if self.workspacePairingPersistTimer then
    self.workspacePairingPersistTimer:stop()
    self.workspacePairingPersistTimer = nil
  end

  self.workspacePairingPersistTimer = hs.timer.doAfter(WORKSPACE_PAIRING_PERSIST_IDLE_SECONDS, function()
    self.workspacePairingPersistTimer = nil
    self:flushWorkspacePairingPersistence()
  end)
end

function AppState:flushWorkspacePairingPersistence()
  if self.workspacePairingPersistTimer then
    self.workspacePairingPersistTimer:stop()
    self.workspacePairingPersistTimer = nil
  end

  if not self.workspacePairingPersistDirty then
    return false
  end

  self:_writeWorkspacePairingsToDisk()
  return true
end

function AppState:_persistWorkspacePairingsNow()
  self.workspacePairingPersistDirty = true
  return self:flushWorkspacePairingPersistence()
end

function AppState:_restoreWorkspacePairings(pairings, opts)
  self:_recordDebug("persistence", "debug", "workspace_pairings_restore_started", "workspace pairings restore started", function()
    return {
      operation = "read",
      activeProfileId = self.session.activeProfileId,
    }
  end, {
    profileId = self.session.activeProfileId,
  })

  pairings = pairings or loadPersistedWorkspacePairings(self.appdata)
  local restoredCount = 0
  for profileId, profilePairings in pairs(pairings) do
    local profile = self:_getProfile(profileId)
    if profile then
      local restoreOpts = opts
      if type(opts) == "table" and opts.shallowInactiveProfiles == true then
        restoreOpts = {
          shallow = profile.id ~= self.session.activeProfileId,
        }
      end
      for index, persisted in pairs(profilePairings or {}) do
        local workspace = self:_getWorkspace(index, profile.id)
        if self:_restoreWorkspaceFromPersistedRecord(workspace, persisted, restoreOpts) then
          restoredCount = restoredCount + 1
        end
      end
    end
  end
  self:_markRecoveryMatchIndexDirty()
  self:_recordDebug("persistence", "debug", "workspace_pairings_restore_result", "workspace pairings restore result", function()
    return {
      operation = "read",
      result = "restored",
      restoredCount = restoredCount,
      activeProfileId = self.session.activeProfileId,
    }
  end, {
    profileId = self.session.activeProfileId,
    result = "restored",
  })
  return restoredCount
end

function AppState:_refreshWorkspaceFingerprint(workspace, win)
  if not workspace then
    return
  end
  if not workspace:getBaseWindowId() then
    return
  end

  local target = win
  if not target or target:id() ~= workspace:getBaseWindowId() then
    target = self.windowService.getWindowById(workspace:getBaseWindowId())
  end

  if not target then
    target = win
  end

  if target then
    workspace:setFingerprint(self.windowService.pairingMetadata(target))
  end
end

-- Fingerprint AX work is advisory; keep it off the slot hotkey edge so rapid
-- ⌘⌥N focus hops are not blocked behind pairingMetadata.
function AppState:_queueWorkspaceFingerprintRefresh(workspace)
  if not workspace or not workspace:getBaseWindowId() then
    return
  end
  local slotIndex = workspace.getIndex and workspace:getIndex() or nil
  local profileId = self.session.activeProfileId
  local expectedId = workspace:getBaseWindowId()
  hs.timer.doAfter(0, function()
    local ws = (slotIndex and self:_getWorkspace(slotIndex, profileId)) or workspace
    if not ws or ws:getBaseWindowId() ~= expectedId then
      return
    end
    self:_refreshWorkspaceFingerprint(ws, nil)
  end)
end

function AppState:_refreshPairedWorkspaceMetadataForWindow(win, opts)
  if not win then
    return false, false
  end

  local id = win:id()
  if not id then
    return false, false
  end

  local refreshBaseSpace = type(opts) == "table" and opts.refreshBaseSpace == true
  local matchedWorkspace = false
  local rowStateChanged = false
  local meta = nil
  self:_forEachWorkspace(function(workspace)
    if workspace:getBaseWindowId() == id or workspace:getFullscreenTargetWindowId() == id then
      matchedWorkspace = true
      if not meta then
        meta = self.windowService.pairingMetadata(win)
      end
      local previousFingerprint = workspace:getFingerprint() or {}
      local previousSpaceId = workspace:getBaseSpaceId()
      workspace:setFingerprint(meta)
      if refreshBaseSpace and workspace:getBaseWindowId() == id then
        self:_updateWorkspaceBindingSpaceState(workspace, win)
      end
      local nextFingerprint = workspace:getFingerprint() or {}
      if (previousFingerprint.titleRaw or "") ~= (nextFingerprint.titleRaw or "")
        or (previousFingerprint.bundleID or "") ~= (nextFingerprint.bundleID or "")
        or (previousFingerprint.appName or "") ~= (nextFingerprint.appName or "")
        or previousSpaceId ~= workspace:getBaseSpaceId() then
        rowStateChanged = true
      end
    end
  end)

  return matchedWorkspace, rowStateChanged
end

function AppState:_markRecoveryMatchIndexDirty()
  self.session.recoveryMatchIndexDirty = true
end

function AppState:_rebuildRecoveryMatchIndex()
  local index = {}
  local recoverableCount = 0
  self:_forEachWorkspace(function(workspace)
    if not workspace:canRecover() then
      return
    end
    recoverableCount = recoverableCount + 1
    local fingerprint = workspace:getFingerprint()
    local bundleID = fingerprint and fingerprint.bundleID
    local titleNormalized = fingerprint and fingerprint.titleNormalized
    if type(bundleID) ~= "string" or bundleID == ""
      or type(titleNormalized) ~= "string" or titleNormalized == "" then
      return
    end
    local byTitle = index[bundleID]
    if not byTitle then
      byTitle = {}
      index[bundleID] = byTitle
    end
    local bucket = byTitle[titleNormalized]
    if not bucket then
      bucket = {}
      byTitle[titleNormalized] = bucket
    end
    bucket[#bucket + 1] = workspace
  end)
  self.session.recoveryMatchIndex = index
  self.session.recoverableSlotCount = recoverableCount
  self.session.recoveryMatchIndexDirty = false
end

function AppState:_ensureRecoveryMatchIndex()
  if self.session.recoveryMatchIndexDirty or self.session.recoveryMatchIndex == nil then
    self:_rebuildRecoveryMatchIndex()
  end
  return self.session.recoveryMatchIndex
end

function AppState:_pairWorkspace(workspace, windowId, win, profileId)
  workspace:pair(windowId, self.windowService.pairingMetadata(win))
  self:_markRecoveryMatchIndexDirty()
  if self.windowService.isWindowFullscreen(win) then
    local fullscreenSpaceId = self.windowService.getPrimarySpaceForWindow(win)
    workspace:setFullscreenState({
      fullscreenWindowId = win:id(),
      fullscreenSpaceId = fullscreenSpaceId,
    })
    -- Home Space is learned on unfullscreen; do not store the fullscreen Space as home.
    workspace:setBaseSpaceId(nil)
  else
    self:_updateWorkspaceBindingSpaceState(workspace, win)
  end
  self:_invalidateWorkspaceSlotsCache(workspace, profileId)
end

function AppState:_updateWorkspaceBindingSpaceState(workspace, win)
  if not workspace or not win then
    return nil
  end

  local spaceId = self.windowService.getPrimarySpaceForWindow(win)
  if spaceId ~= nil then
    workspace:setBaseSpaceId(spaceId)
  end
  return spaceId
end

function AppState:_resolvedTargetSpaceForWindow(win, focusedSpaceId)
  if not win or not self.windowService.getWindowSpaces then
    return nil
  end

  local spaceIds = self.windowService.getWindowSpaces(win)
  return self:_resolvedTargetSpaceFromSpaceIds(spaceIds, focusedSpaceId)
end

function AppState:_resolvedTargetSpaceFromSpaceIds(spaceIds, focusedSpaceId)
  if type(spaceIds) ~= "table" or #spaceIds == 0 then
    return nil, false, nil
  end

  local primarySpaceId = nil
  for _, spaceId in ipairs(spaceIds) do
    if not primarySpaceId then
      primarySpaceId = spaceId
    end
    if self.windowService.isFullscreenSpace
      and self.windowService.isFullscreenSpace(spaceId) then
      primarySpaceId = spaceId
      break
    end
  end

  if focusedSpaceId ~= nil then
    for _, spaceId in ipairs(spaceIds) do
      if spaceId == focusedSpaceId then
        return nil, true, primarySpaceId or focusedSpaceId
      end
    end
  end

  return primarySpaceId, false, primarySpaceId
end

function AppState:_requestWindowInSpace(workspace, windowId, spaceId, activationPath, onSuccess)
  self:_popoverFullscreenPolicy():beforeEnteringSpace(spaceId)

  local slot = workspace and workspace:getIndex() or nil
  local profileId = self.session.activeProfileId
  local function recordResult(result)
    self:_recordDebug("focus", result.ok and "info" or "warn", "slot_space_switch_result", "slot Space switch completed", function()
      return {
        slot = slot,
        profileId = profileId,
        windowId = windowId,
        spaceId = spaceId,
        result = result.code,
      }
    end, {
      slot = slot,
      profileId = profileId,
      windowId = windowId,
      spaceId = spaceId,
      result = result.code,
    })
  end

  local function spaceSwitchFailureToast(code)
    local message = "Could not switch to the window's Space"
    if code == "window_unavailable_after_space_switch" or code == "missing_window_id" then
      message = "Window not found in any spaces"
    end
    self.toast(Toast.message.plain(message))
  end

  local result = self.windowService.requestFrontmostInSpace(windowId, spaceId, self.cfg, function(outcome, resolved)
    recordResult(outcome)
    if outcome.ok then
      if onSuccess then
        onSuccess(resolved)
      end
    else
      spaceSwitchFailureToast(outcome.code)
      self:_refreshFocusedSpaceId()
      self:_popoverFullscreenPolicy():onFocusedSpaceChanged()
    end
    self:_syncWorkspaceUi("slot_space_switch_result")
  end)

  if not result.ok then
    recordResult(result)
    spaceSwitchFailureToast(result.code)
    self:_refreshFocusedSpaceId()
    self:_popoverFullscreenPolicy():onFocusedSpaceChanged()
    return "space-switch-failed"
  end

  self:_recordDebug("focus", "info", "slot_space_switch_requested", "slot Space switch requested", function()
    return {
      slot = slot,
      profileId = profileId,
      windowId = windowId,
      spaceId = spaceId,
      result = result.code,
    }
  end, {
    slot = slot,
    profileId = profileId,
    windowId = windowId,
    spaceId = spaceId,
    result = result.code,
  })
  return activationPath
end

-- Focus a live paired window. Returns resultCode, spaceCorrected.
-- Spaces IPC only when cached baseSpaceId disagrees with the focused Space;
-- fingerprint refresh is queued off the hotkey edge for same-Space focus.
function AppState:_activateResolvedPairedWindow(workspace, paired, focusedSpaceId)
  if not workspace or not paired then
    return nil, false
  end

  local shouldInspectSpaces = workspace:getBaseSpaceId() ~= nil
    and focusedSpaceId ~= nil
    and workspace:getBaseSpaceId() ~= focusedSpaceId

  if shouldInspectSpaces then
    local targetSpaceId, inFocusedSpace, resolvedSpaceId = self:_resolvedTargetSpaceForWindow(paired, focusedSpaceId)
    if inFocusedSpace then
      local spaceCorrected = false
      if resolvedSpaceId and resolvedSpaceId ~= workspace:getBaseSpaceId() then
        workspace:setBaseSpaceId(resolvedSpaceId)
        spaceCorrected = true
      end
      self:_queueWorkspaceFingerprintRefresh(workspace)
      self.windowService.requestFrontmost(paired)
      return "base-window", spaceCorrected
    end

    if targetSpaceId then
      return self:_requestWindowInSpace(
        workspace,
        paired:id(),
        targetSpaceId,
        "base-window-space-switch",
        function(resolved)
          workspace:setBaseSpaceId(targetSpaceId)
          self:_refreshWorkspaceFingerprint(workspace, resolved)
        end
      ), false
    end
  end

  self:_queueWorkspaceFingerprintRefresh(workspace)
  self.windowService.requestFrontmost(paired)
  return "base-window", false
end

function AppState:_activateExactWindowIdAcrossSpaces(workspace, focusedSpaceId)
  if not workspace or not workspace:getBaseWindowId() then
    return nil
  end

  if workspace:getBaseSpaceId() == nil or workspace:getBaseSpaceId() == focusedSpaceId then
    return nil
  end

  if not self.windowService.getWindowSpacesById then
    return nil
  end

  local spaceIds = self.windowService.getWindowSpacesById(workspace:getBaseWindowId())
  local targetSpaceId, inFocusedSpace = self:_resolvedTargetSpaceFromSpaceIds(spaceIds, focusedSpaceId)
  if inFocusedSpace or not targetSpaceId then
    return nil
  end

  return self:_requestWindowInSpace(
    workspace,
    workspace:getBaseWindowId(),
    targetSpaceId,
    "base-window-id-space-switch",
    function(resolved)
      self:_updateWorkspaceBindingSpaceState(
        workspace,
        resolved
      )
      workspace:setBaseSpaceId(targetSpaceId)
      self:_refreshWorkspaceFingerprint(workspace, resolved)
    end
  )
end

function AppState:_isWindowAlreadyPaired(windowId)
  local paired = false
  self:_forEachWorkspace(function(workspace)
    if workspace:getBaseWindowId() == windowId or workspace:getFullscreenTargetWindowId() == windowId then
      paired = true
    end
  end)
  return paired
end

function AppState:_liveWindowCorroboratesWorkspaceIdentity(workspace, win)
  if not workspace or not win then
    return false
  end

  local fingerprint = workspace:getFingerprint()
  local expectedBundleID = fingerprint and fingerprint.bundleID or nil
  if type(expectedBundleID) ~= "string" or expectedBundleID == "" then
    -- No durable app identity to corroborate against; treat a live id as
    -- exact-target evidence (same as a plain getWindowById hit).
    return true
  end

  local meta = self.windowService.pairingMetadata and self.windowService.pairingMetadata(win)
  local liveBundleID = meta and meta.bundleID or nil
  if type(liveBundleID) ~= "string" or liveBundleID == "" then
    local app = safeValue(function()
      return win:application()
    end)
    liveBundleID = app and safeValue(function()
      return app:bundleID()
    end) or nil
  end

  return liveBundleID == expectedBundleID
end

-- Stale-pair exact-target evidence (not activation routing):
-- Grade A: live window id + same-app corroboration (cheap; rejects recycled ids
-- belonging to a different app). Title drift alone must not invalidate.
-- Grade B: Spaces probe only when local id evidence is missing and caller opts in
-- (active-profile stale repair). Never Spaces-probe after a positive id that fails
-- corroboration — that id is usurped, not "off-space".
function AppState:_pairedWorkspaceHasExactTargetEvidence(workspace, opts)
  if not workspace or not workspace:getBaseWindowId() then
    return false
  end

  local allowSpacesProbe = type(opts) == "table" and opts.allowSpacesProbe == true
  local baseWindowId = workspace:getBaseWindowId()
  local baseWin = self:_resolvePairedWindow(workspace)
  if baseWin then
    return self:_liveWindowCorroboratesWorkspaceIdentity(workspace, baseWin)
  end

  if workspace:hasTrackedFullscreenTarget() then
    local fullscreenTargetWindowId = workspace:getFullscreenTargetWindowId()
    local fullscreenWin = self.windowService.getWindowById(fullscreenTargetWindowId)
    if fullscreenWin then
      return self:_liveWindowCorroboratesWorkspaceIdentity(workspace, fullscreenWin)
    end

    if allowSpacesProbe and self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId) then
      return true
    end
  end

  if not allowSpacesProbe then
    return false
  end

  return self:_resolveTrackedSpaceByWindowId(baseWindowId) ~= nil
end

function AppState:_restoreRecoverableWorkspacesForCandidate(win, opts)
  if not self.cfg.recoverClosedWindows then
    return {}
  end

  local eventName = opts and opts.event or nil
  local candidateWindowId = safeValue(function()
    return win and win:id()
  end)
  local recoveryFields = {
    event = eventName,
    windowId = candidateWindowId,
  }
  self:_recordDebug("recovery", "debug", "candidate_considered", "recovery candidate considered", function()
    return {
      event = eventName,
      window = self:_windowDebugSnapshot(win),
    }
  end, recoveryFields)

  local isRecoveryCandidateWindow = self.windowService.isRecoveryCandidateWindow
    or self.windowService.isCandidateWindow
  local isCandidate = isRecoveryCandidateWindow and isRecoveryCandidateWindow(win) or false
  if not isCandidate then
    self:_recordDebug("recovery", "debug", "candidate_rejected", "recovery candidate rejected", function()
      return {
        event = opts and opts.event or nil,
        decision = "rejected",
        reason = "candidate_filter",
        window = self:_windowDebugSnapshot(win),
      }
    end, {
      event = eventName,
      windowId = candidateWindowId,
      decision = "rejected",
    })
    return {}
  end

  local candidateMeta = self.windowService.pairingMetadata(win)
  local candidateId = win:id()
  local alreadyPaired = candidateId and self:_isWindowAlreadyPaired(candidateId) or false
  if not candidateMeta or not candidateId or alreadyPaired then
    self:_recordDebug("recovery", "debug", "candidate_rejected", "recovery candidate rejected", function()
      return {
        event = opts and opts.event or nil,
        decision = "rejected",
        reason = alreadyPaired and "already_paired" or "missing_metadata",
        window = self:_windowDebugSnapshot(win),
        candidateMeta = candidateMeta,
      }
    end, {
      event = eventName,
      windowId = candidateWindowId,
      decision = "rejected",
    })
    return {}
  end

  self:_recordDebug("recovery", "debug", "candidate_accepted", "recovery candidate accepted", function()
    return {
      event = eventName,
      decision = "accepted",
      window = self:_windowDebugSnapshot(win),
      candidateMeta = candidateMeta,
    }
  end, {
    event = eventName,
    windowId = candidateWindowId,
    decision = "accepted",
  })

  local restoredWorkspaces = {}
  local restoredLookup = {}
  local recoverableCount = 0
  local stalePairedCandidateCount = 0
  local matchedSlots = {}
  local stalePairedPromotedSlots = {}
  local stalePairedRejectedSlots = {}
  self:_recordDebug("recovery", "debug", "slot_match_attempted", "recovery slot match attempted", function()
    return {
      event = eventName,
      window = self:_windowDebugSnapshot(win),
      candidateMeta = candidateMeta,
    }
  end, {
    event = eventName,
    windowId = candidateWindowId,
  })

  -- Derived fingerprint index: lookup matching recoverables instead of
  -- scanning every profile/slot on each candidate event.
  self:_ensureRecoveryMatchIndex()
  recoverableCount = self.session.recoverableSlotCount or 0
  local byTitle = self.session.recoveryMatchIndex
    and candidateMeta.bundleID
    and self.session.recoveryMatchIndex[candidateMeta.bundleID]
  local indexedMatches = byTitle and candidateMeta.titleNormalized and byTitle[candidateMeta.titleNormalized] or nil
  if type(indexedMatches) == "table" then
    local snapshot = {}
    for index, workspace in ipairs(indexedMatches) do
      snapshot[index] = workspace
    end
    for _, workspace in ipairs(snapshot) do
      if workspace:canRecover() and workspace:matchesRecoveryCandidate(candidateMeta) then
        matchedSlots[#matchedSlots + 1] = {
          index = workspace:getIndex(),
          name = workspace:getName(),
          storedTitle = workspace:getStoredWindowTitle(),
        }
        self:_pairWorkspace(workspace, candidateId, win)
        restoredWorkspaces[#restoredWorkspaces + 1] = workspace
        restoredLookup[workspace] = true
      end
    end
  end

  if eventName == hs.window.filter.windowCreated then
    local inactiveDemoted = false
    self:_forEachWorkspace(function(workspace, profile)
      if restoredLookup[workspace] then
        return
      end
      if not workspace:isPaired() or not workspace:matchesRecoveryCandidate(candidateMeta) then
        return
      end

      stalePairedCandidateCount = stalePairedCandidateCount + 1
      local isActiveProfile = profile and profile.id == self.session.activeProfileId
      local exactTargetStillValid = self:_pairedWorkspaceHasExactTargetEvidence(workspace, {
        allowSpacesProbe = isActiveProfile == true,
      })
      if exactTargetStillValid then
        stalePairedRejectedSlots[#stalePairedRejectedSlots + 1] = {
          index = workspace:getIndex(),
          name = workspace:getName(),
          storedTitle = workspace:getStoredWindowTitle(),
          reason = "exact_target_still_valid",
        }
        return
      end

      -- Promote only on the active profile. Inactive mismatches demote to
      -- recoverable (no Spaces probe, no candidate claim) so recycled ids
      -- cannot freeze wrong bindings until profile switch.
      if not isActiveProfile then
        if self.cfg.recoverClosedWindows then
          workspace:markClosedForRecovery()
          inactiveDemoted = true
          self:_invalidateProfileSlotsCache(profile.id)
          stalePairedRejectedSlots[#stalePairedRejectedSlots + 1] = {
            index = workspace:getIndex(),
            name = workspace:getName(),
            storedTitle = workspace:getStoredWindowTitle(),
            reason = "inactive_exact_target_demoted",
          }
        end
        return
      end

      local promotedSlot = {
        index = workspace:getIndex(),
        name = workspace:getName(),
        storedTitle = workspace:getStoredWindowTitle(),
        reason = "exact_target_unresolved",
      }
      matchedSlots[#matchedSlots + 1] = promotedSlot
      stalePairedPromotedSlots[#stalePairedPromotedSlots + 1] = promotedSlot
      self:_pairWorkspace(workspace, candidateId, win, profile.id)
      restoredWorkspaces[#restoredWorkspaces + 1] = workspace
      restoredLookup[workspace] = true
    end)
    if inactiveDemoted then
      self:_markRecoveryMatchIndexDirty()
      self:_scheduleWorkspacePairingPersist()
    end
  end

  self:_recordDebug("recovery", "debug", "slot_match_result", "recovery slot match result", function()
    return {
      event = opts and opts.event or nil,
      decision = #restoredWorkspaces > 0 and "matched" or "no_match",
      window = self:_windowDebugSnapshot(win),
      candidateMeta = candidateMeta,
      recoverableCount = recoverableCount,
      stalePairedCandidateCount = stalePairedCandidateCount,
      matchedSlots = matchedSlots,
      stalePairedPromotedSlots = stalePairedPromotedSlots,
      stalePairedRejectedSlots = stalePairedRejectedSlots,
    }
  end, {
    event = eventName,
    windowId = candidateWindowId,
    decision = #restoredWorkspaces > 0 and "matched" or "no_match",
  })

  return restoredWorkspaces
end

function AppState:_restoreWorkspaceFromCandidate(win, opts)
  local eventName = type(opts) == "table" and opts.event or nil
  local candidateWindowId = safeValue(function()
    return win and win:id()
  end)
  self:_recordDebug("recovery", "debug", "restore_attempted", "recovery restore attempted", function()
    return {
      event = eventName,
      window = self:_windowDebugSnapshot(win),
    }
  end, {
    event = eventName,
    windowId = candidateWindowId,
  })

  local restoredWorkspaces = self:_restoreRecoverableWorkspacesForCandidate(win, opts)
  self:_recordDebug("recovery", "debug", "restore_result", "recovery restore result", function()
    local restoredSlots = {}
    for _, workspace in ipairs(restoredWorkspaces) do
      restoredSlots[#restoredSlots + 1] = {
        index = workspace:getIndex(),
        name = workspace:getName(),
      }
    end
    return {
      event = eventName,
      decision = #restoredWorkspaces > 0 and "restored" or "no_match",
      window = self:_windowDebugSnapshot(win),
      restoredCount = #restoredWorkspaces,
      restoredSlots = restoredSlots,
    }
  end, {
    event = eventName,
    windowId = candidateWindowId,
    decision = #restoredWorkspaces > 0 and "restored" or "no_match",
  })

  if #restoredWorkspaces > 0 then
    if not (type(opts) == "table" and opts.persist == false) then
      self:_scheduleWorkspacePairingPersist()
    end
    if not (type(opts) == "table" and opts.notify == false) then
      self.toast(self:_formatRestoreToast(restoredWorkspaces, win))
    end
    return true
  end
  return false
end

function AppState:_shouldAttemptRecoverableRestoreForWindowEvent(event)
  return event == hs.window.filter.windowCreated
    or event == hs.window.filter.windowTitleChanged
    or event == hs.window.filter.windowFocused
    or event == hs.window.filter.windowVisible
    or event == hs.window.filter.windowMinimized
    or event == hs.window.filter.windowUnminimized
end

function AppState:_hasWorkspaceEligibleForRecoveryEvent(event)
  local eligible = false
  local allowsStalePairedRepair = event == hs.window.filter.windowCreated
  self:_forEachWorkspace(function(workspace)
    if workspace:canRecover() or (allowsStalePairedRepair and workspace:isPaired()) then
      eligible = true
    end
  end)
  return eligible
end

function AppState:_recoverFromWindowEvent(event, win)
  if not win then
    return false
  end

  if not self:_shouldAttemptRecoverableRestoreForWindowEvent(event) then
    return false
  end

  if not self:_hasWorkspaceEligibleForRecoveryEvent(event) then
    return false
  end

  -- Reject non-candidates before pairingMetadata / slot scans / Spaces
  -- probes. Eligibility alone is not enough: any paired slot makes every
  -- windowCreated eligible for stale-pair consideration.
  local isRecoveryCandidateWindow = self.windowService.isRecoveryCandidateWindow
    or self.windowService.isCandidateWindow
  if not (isRecoveryCandidateWindow and isRecoveryCandidateWindow(win)) then
    return false
  end

  -- Recoverable-slot relink can use concrete window events. Stale-pair
  -- repair is candidate-local and windowCreated-only inside the matcher.
  return self:_restoreWorkspaceFromCandidate(win, {
    event = event,
  })
end

function AppState:_refreshUiStateFromWindowEvent(event, win)
  local pairedWorkspaceTouched, rowStateChanged = self:_refreshPairedWorkspaceMetadataForWindow(win, {
    refreshBaseSpace = event == hs.window.filter.windowFocused,
  })
  self.youtubeService:handleWindowCandidate(win)

  -- Minimize/visible can change row appearance without fingerprint/space churn.
  if rowStateChanged
    or (pairedWorkspaceTouched and (
      event == hs.window.filter.windowMinimized
      or event == hs.window.filter.windowUnminimized
      or event == hs.window.filter.windowVisible
    )) then
    return "rows"
  end

  -- Focus UI is owned by handleActiveWindowChange (header JS, or full refresh on Space change).
  if event == hs.window.filter.windowFocused then
    return nil
  end

  if win then
    local frontmost = hs.window.frontmostWindow()
    if frontmost and frontmost:id() == win:id() then
      return "header"
    end
  end

  return nil
end

function AppState:_restoreRecoverableWorkspacesFromExistingCandidates()
  if not self.cfg.recoverClosedWindows then
    return false
  end

  if not self.windowService.candidateWindows then
    return false
  end

  local candidates = self.windowService:candidateWindows() or {}
  local restored = false
  for _, win in ipairs(candidates) do
    local restoredWorkspaces = self:_restoreRecoverableWorkspacesForCandidate(win, {
      event = "startup_existing_candidate",
    })
    if #restoredWorkspaces > 0 then
      restored = true
    end
  end

  return restored
end

function AppState:_restoreStartupWorkspaceState()
  local persistedPairings = loadPersistedWorkspacePairings(self.appdata)
  self:_restoreWorkspacePairings(persistedPairings, {
    shallowInactiveProfiles = true,
  })
  self:_restoreRecoverableWorkspacesFromExistingCandidates()

  -- Persisted load shape is pairings-only; full metadata snapshots always differ.
  local restoredPairings = {}
  for profileId, record in pairs(self:_profilePairingSnapshot()) do
    local pairings = type(record) == "table" and record.pairings or record
    if type(pairings) == "table" and next(pairings) ~= nil then
      restoredPairings[profileId] = pairings
    end
  end
  if not deepEqual(restoredPairings, persistedPairings) then
    self:_persistWorkspacePairingsNow()
  end
end

function AppState:_validateWorkspaceExactState(workspace)
  if not workspace or not workspace:isPaired() then
    return false
  end

  local baseWindowId = workspace:getBaseWindowId()
  if not baseWindowId then
    return false
  end

  local before = SlotRecord.encode(workspace.binding)
  local baseWin = self.windowService.getWindowById(baseWindowId)
  if baseWin then
    if not self:_liveWindowCorroboratesWorkspaceIdentity(workspace, baseWin) then
      -- Recycled / usurped id: do not refresh fingerprint from the wrong window.
      if self.cfg.recoverClosedWindows then
        workspace:markClosedForRecovery()
      else
        workspace:clear()
      end
      return not deepEqual(before, SlotRecord.encode(workspace.binding))
    end

    local priorHomeSpaceId = workspace:getBaseSpaceId()
    local primarySpaceId = self.windowService.getPrimarySpaceForWindow(baseWin)
    local baseIsFullscreen = self.windowService.isWindowFullscreen(baseWin)
    self:_refreshWorkspaceFingerprint(workspace, baseWin)

    local homeSpaceId = nil
    if baseIsFullscreen then
      -- Never treat the fullscreen Space as advisory home.
      if priorHomeSpaceId
        and not (self.windowService.isFullscreenSpace
          and self.windowService.isFullscreenSpace(priorHomeSpaceId)) then
        homeSpaceId = priorHomeSpaceId
      end
      workspace:setBaseSpaceId(homeSpaceId)
    else
      homeSpaceId = primarySpaceId
      if homeSpaceId ~= nil then
        workspace:setBaseSpaceId(homeSpaceId)
      else
        workspace:setBaseSpaceId(nil)
      end
    end

    if workspace:hasTrackedFullscreenTarget() then
      local fullscreenTargetWindowId = workspace:getFullscreenTargetWindowId()
      local fullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId)
      if fullscreenSpaceId then
        workspace:setFullscreenState({
          fullscreenWindowId = fullscreenTargetWindowId,
          fullscreenSpaceId = fullscreenSpaceId,
          lastKnownSpaceId = homeSpaceId,
        })
      elseif baseIsFullscreen and primarySpaceId then
        workspace:setFullscreenState({
          fullscreenWindowId = baseWindowId,
          fullscreenSpaceId = primarySpaceId,
        })
      else
        workspace:clearFullscreenState()
      end
    elseif baseIsFullscreen and primarySpaceId then
      workspace:setFullscreenState({
        fullscreenWindowId = baseWindowId,
        fullscreenSpaceId = primarySpaceId,
      })
    end
  else
    local baseSpaceId = self:_resolveTrackedSpaceByWindowId(baseWindowId)
    if baseSpaceId then
      workspace:setBaseSpaceId(baseSpaceId)
      if workspace:hasTrackedFullscreenTarget() then
        local fullscreenTargetWindowId = workspace:getFullscreenTargetWindowId()
        local fullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId)
        if fullscreenSpaceId then
          workspace:setFullscreenState({
            fullscreenWindowId = fullscreenTargetWindowId,
            fullscreenSpaceId = fullscreenSpaceId,
            lastKnownSpaceId = baseSpaceId,
          })
        else
          workspace:clearFullscreenState()
        end
      end
    elseif workspace:hasTrackedFullscreenTarget() then
      local fullscreenTargetWindowId = workspace:getFullscreenTargetWindowId()
      local fullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(fullscreenTargetWindowId)
      if fullscreenSpaceId then
        workspace:setFullscreenState({
          fullscreenWindowId = fullscreenTargetWindowId,
          fullscreenSpaceId = fullscreenSpaceId,
          lastKnownSpaceId = workspace:getBaseSpaceId(),
        })
      else
        workspace:setBaseSpaceId(nil)
        workspace:clearFullscreenState()
      end
    else
      workspace:setBaseSpaceId(nil)
    end
  end

  return not deepEqual(before, SlotRecord.encode(workspace.binding))
end

function AppState:_validateProfileExactState(profile)
  if not profile then
    return false
  end

  local profileId = profile.id
  local changed = false
  local pairedCount = 0
  local aborted = false

  for _, workspace in ipairs(profile.workspaces or {}) do
    -- Rapid profile cycling can pump the runloop during Spaces IPC; stop paying
    -- for a bank the user already left, and keep the dirty flag for a later settle.
    if self.session.activeProfileId ~= profileId then
      aborted = true
      break
    end

    if workspace:isPaired() then
      pairedCount = pairedCount + 1
      if self:_validateWorkspaceExactState(workspace) then
        changed = true
      end
    end
  end

  if aborted then
    self:_recordDebug("persistence", "debug", "profile_exact_validation_aborted", "profile exact validation aborted after profile switch", function()
      return {
        profileId = profileId,
        pairedCount = pairedCount,
        changed = changed,
        activeProfileId = self.session.activeProfileId,
      }
    end, {
      profileId = profileId,
      result = "aborted",
    })
    if changed then
      self:_markRecoveryMatchIndexDirty()
      self:_scheduleWorkspacePairingPersist()
    end
    return changed
  end

  profile.needsExactValidation = false
  self:_recordDebug("persistence", "debug", "profile_exact_validation_result", "profile exact validation completed", function()
    return {
      profileId = profile.id,
      pairedCount = pairedCount,
      changed = changed,
    }
  end, {
    profileId = profile.id,
    result = changed and "changed" or "unchanged",
  })

  if changed then
    self:_markRecoveryMatchIndexDirty()
    self:_scheduleWorkspacePairingPersist()
    -- Publish badge-relevant Space/fullscreen corrections; the profile-switch
    -- paint may have already flushed from shallow cache.
    if self.session.activeProfileId == profileId then
      self:_syncWorkspaceUi("profile_validation")
    end
  end
  return changed
end

function AppState:_queueActiveProfileValidation(profile)
  if self.activeProfileValidationTimer then
    self.activeProfileValidationTimer:stop()
    self.activeProfileValidationTimer = nil
  end

  if not profile or profile.needsExactValidation ~= true then
    return
  end

  local profileId = profile.id
  self.activeProfileValidationTimer = hs.timer.doAfter(ACTIVE_PROFILE_VALIDATION_DELAY_SECONDS, function()
    self.activeProfileValidationTimer = nil
    if self.session.activeProfileId ~= profileId then
      return
    end

    local activeProfile = self:_getProfile(profileId)
    if activeProfile and activeProfile.needsExactValidation == true then
      self:_validateProfileExactState(activeProfile)
    end
  end)
end

function AppState:_workspaceActionLabel(workspace)
  local slotIndex = workspace and workspace.getIndex and workspace:getIndex() or nil
  local profileName = self:getProfileDisplayName(self.session.activeProfileId)
  if slotIndex then
    return string.format("%s [%d]", profileName, slotIndex)
  end
  return profileName
end

function AppState:_activeProfileToastColor()
  return self:getProfileColor(self.session.activeProfileId)
end

function AppState:_formatPairToast(workspace, win)
  local app = win and win:application() or nil
  local label = self.windowService.windowTitle and self.windowService.windowTitle(win) or self.windowService.displayTitle(win)
  return Toast.message.windowAction({
    prefixText = "Pairing ",
    labelText = self:_workspaceActionLabel(workspace) .. ": ",
    titleText = label,
    bundleID = app and app:bundleID() or nil,
    appName = app and app:name() or nil,
    imageColor = self:_activeProfileToastColor(),
    prefixColor = TOAST_WHITE,
    titleColor = PAIR_TOAST_COLOR,
    duration = 2.0,
  })
end

function AppState:_formatUnpairToast(workspace, win)
  local app = win and win:application() or nil
  local fingerprint = workspace and workspace:getFingerprint() or {}
  local label = self.windowService.windowTitle and self.windowService.windowTitle(win) or self.windowService.displayTitle(win)
  if label == "[empty]" then
    label = workspace:getStoredWindowTitle()
  end
  return Toast.message.windowAction({
    prefixText = "Unpairing ",
    labelText = self:_workspaceActionLabel(workspace) .. ": ",
    titleText = label,
    bundleID = app and app:bundleID() or fingerprint.bundleID or nil,
    appName = app and app:name() or fingerprint.appName or nil,
    imageColor = self:_activeProfileToastColor(),
    prefixColor = TOAST_WHITE,
    titleColor = UNPAIR_TOAST_COLOR,
  })
end

function AppState:_formatClosedWindowUnpairToast(workspace)
  local fingerprint = workspace and workspace:getFingerprint() or {}
  return Toast.message.windowAction({
    prefixText = "[Unpaired Closed Window · ",
    labelText = self:_workspaceActionLabel(workspace) .. ": ",
    titleText = workspace and workspace:getStoredWindowTitle() or "[empty]",
    bundleID = fingerprint.bundleID or nil,
    appName = fingerprint.appName or nil,
    imageColor = self:_activeProfileToastColor(),
    prefixColor = TOAST_WHITE,
    titleColor = UNPAIR_TOAST_COLOR,
    suffixText = "]",
    suffixColor = TOAST_WHITE,
  })
end

function AppState:_formatRestoreToast(workspaces, win)
  local app = win and win:application() or nil
  local label = self.windowService.windowTitle and self.windowService.windowTitle(win) or self.windowService.displayTitle(win)
  local names = {}
  for _, ws in ipairs(workspaces) do
    names[#names + 1] = self:_workspaceActionLabel(ws)
  end
  return Toast.message.windowAction({
    prefixText = "Restored ",
    labelText = table.concat(names, ", ") .. ": ",
    titleText = label,
    bundleID = app and app:bundleID() or nil,
    appName = app and app:name() or nil,
    imageColor = self:_activeProfileToastColor(),
    prefixColor = TOAST_WHITE,
    titleColor = PAIR_TOAST_COLOR,
    duration = 2.0,
  })
end

function AppState:_clearRecoverableWorkspaces()
  local changed = false
  self:_forEachWorkspace(function(workspace, profile)
    if workspace:isRecoverable() then
      workspace:clear()
      changed = true
      if profile then
        self:_invalidateProfileSlotsCache(profile.id)
      end
    end
  end)
  if changed then
    self:_markRecoveryMatchIndexDirty()
  end
  return changed
end

function AppState:_clearWorkspaceAndPersist(workspace)
  if not workspace then
    return
  end
  workspace:clear()
  self:_invalidateWorkspaceSlotsCache(workspace)
  self:_markRecoveryMatchIndexDirty()
  self:_persistWorkspacePairingsNow()
end

-- Pair frontmost/source window to slot index on the active profile.
function AppState:pairSlot(index, sourceWindow)
  local workspace = self:_getWorkspace(index)
  if not workspace then
    return false
  end

  local win = sourceWindow
  if not win then
    self.toast(Toast.message.plain("No window to pair!"))
    return false
  end

  return self:_runPairingAction(function()
    self:_pairWorkspace(workspace, win:id(), win)
    self.toast(self:_formatPairToast(workspace, win))
  end)
end

-- Hotkey: pair if empty, else focus/minimize the paired window (incl. cross-Space).
-- Cheap edge work only: toast on pair/error, kick focus/minimize/Space switch.
-- Popover rebuild is skipped for pure focus; fingerprint AX is deferred.
function AppState:activateSlot(index)
  local workspace = self:_getWorkspace(index)
  if not workspace then
    return
  end

  self:_recordDebug("focus", "info", "slot_activation_requested", "slot activation requested", function()
    return {
      slot = index,
      profileId = self.session.activeProfileId,
      isPaired = workspace:isPaired(),
      isRecoverable = workspace:isRecoverable(),
    }
  end, {
    slot = index,
    profileId = self.session.activeProfileId,
  })

  local bindingChanged = false
  local needsUiSync = false
  self:_runWorkspaceAction(function()
    local win = hs.window.frontmostWindow()
    if not win then
      self:_recordDebug("focus", "warn", "slot_activation_result", "slot activation failed", function()
        return {
          slot = index,
          result = "no_frontmost_window",
        }
      end, {
        slot = index,
        profileId = self.session.activeProfileId,
        result = "no_frontmost_window",
      })
      self.toast(Toast.message.plain("No active window found!"))
      return
    end

    local currentId = win:id()
    local focusedSpaceId = self.windowService.focusedSpaceId and self.windowService.focusedSpaceId() or nil
    if not workspace:isPaired() then
      self:_pairWorkspace(workspace, currentId, win)
      bindingChanged = true
      needsUiSync = true
      self:_recordDebug("focus", "info", "slot_activation_result", "slot activation paired frontmost window", function()
        return {
          slot = index,
          result = "paired_frontmost_window",
          window = self:_windowDebugSnapshot(win),
        }
      end, {
        slot = index,
        profileId = self.session.activeProfileId,
        windowId = currentId,
        result = "paired_frontmost_window",
      })
      self.toast(self:_formatPairToast(workspace, win))
      return
    end

    if workspace:hasTrackedFullscreenTarget()
      and currentId == workspace:getFullscreenTargetWindowId()
      and focusedSpaceId == workspace:getFullscreenTargetSpaceId()
      and self.windowService.isWindowFullscreen(win) then
      return
    end

    if currentId ~= workspace:getBaseWindowId() then
      if workspace:hasTrackedFullscreenTarget() then
        local resolvedFullscreenSpaceId = self:_resolveTrackedSpaceByWindowId(workspace:getFullscreenTargetWindowId())
        if resolvedFullscreenSpaceId then
          if resolvedFullscreenSpaceId ~= workspace:getFullscreenTargetSpaceId() then
            workspace:setFullscreenState({
              fullscreenWindowId = workspace:getFullscreenTargetWindowId(),
              fullscreenSpaceId = resolvedFullscreenSpaceId,
              lastKnownSpaceId = workspace:getBaseSpaceId(),
            })
            bindingChanged = true
            needsUiSync = true
          end

          if focusedSpaceId == resolvedFullscreenSpaceId then
            local fullscreenWin = self.windowService.getWindowById(workspace:getFullscreenTargetWindowId())
            if fullscreenWin then
              self:_popoverFullscreenPolicy():beforeEnteringSpace(resolvedFullscreenSpaceId)
              workspace:setFullscreenState({
                fullscreenWindowId = fullscreenWin:id(),
                fullscreenSpaceId = resolvedFullscreenSpaceId,
                lastKnownSpaceId = workspace:getBaseSpaceId(),
              })
              self.windowService.requestFrontmost(fullscreenWin)
              self:_queueWorkspaceFingerprintRefresh(workspace)
              return
            end
          else
            -- _requestWindowInSpace hides when the target Space is fullscreen.
            -- Completion callback refreshes UI via slot_space_switch_result.
            self:_requestWindowInSpace(
              workspace,
              workspace:getFullscreenTargetWindowId(),
              resolvedFullscreenSpaceId,
              "fullscreen-space-switch",
              function(fullscreenWin)
                workspace:setFullscreenState({
                  fullscreenWindowId = fullscreenWin:id(),
                  fullscreenSpaceId = resolvedFullscreenSpaceId,
                  lastKnownSpaceId = workspace:getBaseSpaceId(),
                })
                self:_refreshWorkspaceFingerprint(workspace, fullscreenWin)
              end
            )
            return
          end
        else
          workspace:clearFullscreenState()
          bindingChanged = true
          needsUiSync = true
        end
      end

      local paired = self:_resolvePairedWindow(workspace)
      if paired then
        workspace:resetInputBuffer()
        local _, spaceCorrected = self:_activateResolvedPairedWindow(workspace, paired, focusedSpaceId)
        if spaceCorrected then
          bindingChanged = true
          needsUiSync = true
        end
      elseif not self:_activateExactWindowIdAcrossSpaces(workspace, focusedSpaceId) then
        self.toast(Toast.message.plain("Window not found in any spaces"))
      end
      return
    end

    if workspace:hasTrackedFullscreenTarget() and currentId == workspace:getFullscreenTargetWindowId()
      and self.windowService.isWindowFullscreen(win) then
      return
    end

    local paired = self:_resolvePairedWindow(workspace) or win
    workspace:consumeRepeatPress()
    if paired and workspace:shouldMinimize() then
      workspace:resetInputBuffer()
      paired:minimize()
      -- Minimize badge is visible in the popover when shown.
      needsUiSync = true
      return
    end
  end, { syncUi = false })

  if bindingChanged then
    self:_scheduleWorkspacePairingPersist()
  end
  if needsUiSync then
    self:_syncWorkspaceUi("workspace_state")
  end
end

-- Hotkey: clear one slot pairing (and recoverable state) on the active profile.
function AppState:unpairSlot(index)
  local workspace = self:_getWorkspace(index)
  if not workspace then
    return false
  end

  return self:_runPairingAction(function()
    if workspace:isPaired() or workspace:isRecoverable() then
      local win = self:_resolvePairedWindow(workspace)
      local toastPayload = self:_formatUnpairToast(workspace, win)
      workspace:clear()
      self:_markRecoveryMatchIndexDirty()
      self.toast(toastPayload)
    else
      self.toast(Toast.message.status(self:_workspaceActionLabel(workspace) .. " is already unpaired!", {
        imageColor = self:_activeProfileToastColor(),
      }))
    end
  end)
end

-- Hotkey: clear all slot pairings on the active profile.
function AppState:unpairAll()
  return self:_runPairingAction(function()
    local cleared = false
    for _, workspace in ipairs(self:getWorkspaces()) do
      if workspace:isPaired() or workspace:isRecoverable() then
        workspace:clear()
        cleared = true
      end
    end
    if cleared then
      self:_markRecoveryMatchIndexDirty()
    end
    self.toast(Toast.message.plain(cleared and "[Unpaired All Windows]" or "[No Paired Windows]"))
  end)
end

function AppState:_queueActiveProfilePersistence()
  if not self.appdata.setActiveProfileId then
    return
  end

  self.pendingActiveProfileId = self.session.activeProfileId

  if self.activeProfilePersistTimer then
    self.activeProfilePersistTimer:stop()
    self.activeProfilePersistTimer = nil
  end

  self.activeProfilePersistTimer = hs.timer.doAfter(ACTIVE_PROFILE_PERSIST_DELAY_SECONDS, function()
    self.activeProfilePersistTimer = nil
    self:flushActiveProfilePersistence()
  end)
end

function AppState:flushActiveProfilePersistence()
  if self.activeProfilePersistTimer then
    self.activeProfilePersistTimer:stop()
    self.activeProfilePersistTimer = nil
  end

  local profileId = self.pendingActiveProfileId
  if not profileId or not self.appdata.setActiveProfileId then
    return false
  end

  self.appdata.setActiveProfileId(profileId)
  if self.pendingActiveProfileId == profileId then
    self.pendingActiveProfileId = nil
  end
  return true
end

-- Switch active profile bank; defers Spaces validation off the hotkey edge.
function AppState:activateProfile(profileId, opts)
  local profile = self:_getProfile(profileId)
  if not profile then
    return false
  end

  opts = opts or {}
  if profile.id == self.session.activeProfileId then
    -- Already active: return to slots without settle probes / row rebuilds.
    if opts.returnToSlots == true and self.popover and self.popover.requestRefresh then
      self.popover:requestRefresh("profile_switch", nil, {
        returnToSlots = true,
        clientEpoch = opts.clientEpoch,
        modeOnly = true,
      })
    end
    return false
  end

  self.session.activeProfileId = profile.id
  self:_queueActiveProfilePersistence()
  self:_queueActiveProfileValidation(profile)
  self:_syncWorkspaceUi("profile_switch", {
    returnToSlots = opts.returnToSlots == true,
    clientEpoch = opts.clientEpoch,
  })
  -- One toast line per hop (matches UI cycling). Capture name/color now so a
  -- deferred render cannot rewrite earlier stack lines to the final bank.
  local toastName = self:getProfileDisplayName(profile.id)
  local toastColor = self:getProfileColor(profile.id)
  hs.timer.doAfter(0, function()
    self.toast(Toast.message.profile(toastName, toastColor, { duration = 2.0 }))
  end)
  return true
end

function AppState:_profileIsNonEmpty(profileId)
  return self:getProfilePairedCount(profileId) > 0
end

function AppState:activatePreviousNonEmptyProfile()
  local count = self:getProfileCount()
  if count < 1 then
    return false
  end
  local current = self.session.activeProfileId
  for offset = 1, count do
    local candidate = current - offset
    if candidate < 1 then
      candidate = candidate + count
    end
    if self:_profileIsNonEmpty(candidate) then
      return self:activateProfile(candidate, { returnToSlots = true })
    end
  end
  return false
end

function AppState:activateNextNonEmptyProfile()
  local count = self:getProfileCount()
  if count < 1 then
    return false
  end
  local current = self.session.activeProfileId
  for offset = 1, count do
    local candidate = current + offset
    if candidate > count then
      candidate = candidate - count
    end
    if self:_profileIsNonEmpty(candidate) then
      return self:activateProfile(candidate, { returnToSlots = true })
    end
  end
  return false
end

function AppState:activatePreviousProfile()
  local profileId = self.session.activeProfileId - 1
  if profileId < 1 then
    profileId = self:getProfileCount()
  end
  return self:activateProfile(profileId, { returnToSlots = true })
end

function AppState:activateNextProfile()
  local profileId = self.session.activeProfileId + 1
  if profileId > self:getProfileCount() then
    profileId = 1
  end
  return self:activateProfile(profileId, { returnToSlots = true })
end

function AppState:_colorOwnedByOtherProfile(color, exceptProfileId)
  local normalized = ProfilePalette.normalizeColor(color)
  if not normalized then
    return false
  end
  for _, profile in ipairs(self.profiles) do
    if profile.id ~= exceptProfileId and ProfilePalette.normalizeColor(profile.color) == normalized then
      return true
    end
  end
  return false
end

function AppState:updateProfileMetadata(profileId, opts)
  local profile = self:_getProfile(profileId)
  if not profile or type(opts) ~= "table" then
    return false
  end

  local changed = false
  if opts.name ~= nil then
    local nextName = ProfilePalette.normalizeName(opts.name, profile.id)
    if nextName ~= profile.name then
      profile.name = nextName
      changed = true
    end
  end

  if opts.color ~= nil or opts.clearColor == true then
    local nextColor = nil
    if opts.clearColor == true then
      nextColor = nil
    else
      nextColor = ProfilePalette.normalizeColor(opts.color)
      if opts.color ~= false and opts.color ~= "" and opts.color ~= "none" and nextColor == nil then
        return false
      end
      if nextColor and self:_colorOwnedByOtherProfile(nextColor, profile.id) then
        return false
      end
    end
    if nextColor ~= ProfilePalette.normalizeColor(profile.color) then
      profile.color = nextColor
      changed = true
    end
  end

  if not changed then
    return true
  end

  self:_persistWorkspacePairingsNow()
  self:_syncWorkspaceUi("profile_metadata")
  return true
end

function AppState:togglePopover()
  self:_recordDebug("popover", "info", "popover_toggle_requested", "popover toggle requested")
  if self.popover and self.popover.toggleOrFocus then
    self.popover:toggleOrFocus()
    return
  end

  if self.popover and self.popover.toggle then
    self.popover:toggle()
  end
end

function AppState:showPopover()
  self:_recordDebug("popover", "info", "popover_show_requested", "popover show requested")
  if self.popover and self.popover.show then
    self.popover:show()
  end
end

function AppState:toggleSettingsWindow()
  self:_recordDebug("popover", "info", "settings_toggle_requested", "settings window toggle requested")
  if not self.settingsWindow then
    return
  end

  if self.settingsWindow.isShown and self.settingsWindow:isShown() then
    if self.settingsWindow.hide then
      self.settingsWindow:hide()
    end
    return
  end

  if self.settingsWindow.show then
    self.settingsWindow:show()
  end
end

function AppState:setPopoverAutoHide(enabled)
  self.cfg.popoverAutoHideAfterAction = enabled == true
  self.settings.setPopoverAutoHideAfterAction(self.cfg.popoverAutoHideAfterAction)
  self:syncUi()
end

function AppState:setPopoverAlwaysOnTop(enabled)
  self.cfg.popoverAlwaysOnTop = enabled == true
  self.settings.setPopoverAlwaysOnTop(self.cfg.popoverAlwaysOnTop)
  if self.popover and self.popover.syncWindowLevel then
    self.popover:syncWindowLevel()
  end
  if self.settingsWindow and self.settingsWindow.syncWindowLevel then
    self.settingsWindow:syncWindowLevel()
  end
  self:syncUi()
end

function AppState:setPopoverHidePairButtons(enabled)
  self.cfg.popoverHidePairButtons = enabled == true
  self.settings.setPopoverHidePairButtons(self.cfg.popoverHidePairButtons)
  self:syncUi()
end

function AppState:setPopoverHideOnFullscreenWorkspace(enabled)
  self.cfg.popoverHideOnFullscreenWorkspace = enabled == true
  self.settings.setPopoverHideOnFullscreenWorkspace(self.cfg.popoverHideOnFullscreenWorkspace)
  self:_popoverFullscreenPolicy():onSettingChanged(self.cfg.popoverHideOnFullscreenWorkspace)
  self:syncUi()
end

function AppState:setRecoverClosedWindows(enabled)
  self.cfg.recoverClosedWindows = enabled == true
  self.settings.setRecoverClosedWindows(self.cfg.recoverClosedWindows)
  if not self.cfg.recoverClosedWindows and self:_clearRecoverableWorkspaces() then
    self:_persistWorkspacePairingsNow()
  end
  self:syncUi()
end

function AppState:setPopoverOpacity(opacity)
  local normalized = opacity > 1 and (opacity / 100) or opacity
  local percent = math.floor(normalized * 100 + 0.5)
  self.cfg.popoverBackgroundOpacity = self.settings.setPopoverBackgroundOpacity(normalized)
  self:syncUi(percent)
end

function AppState:getHotkeyUiState()
  if not self.hotkeyManager or not self.hotkeyManager.getUiState then
    return {
      rows = {},
      conflictsById = {},
      overrides = {},
      recordingSupported = false,
    }
  end
  return self.hotkeyManager:getUiState()
end

function AppState:warmHotkeyUiCache(rendererFn)
  if not self.hotkeyManager then
    return
  end
  if self.hotkeyManager.warmUiState then
    self.hotkeyManager:warmUiState()
  end
  if rendererFn and self.hotkeyManager.warmHtml then
    self.hotkeyManager:warmHtml(rendererFn)
  end
end

function AppState:updateHotkeyBinding(id, payload)
  if not self.hotkeyManager or not self.hotkeyManager.updateBinding then
    return {
      ok = false,
      code = "missing_manager",
      ids = {
        [tostring(id or "")] = {},
      },
      message = "Hotkey manager unavailable.",
    }
  end

  local result = self.hotkeyManager:updateBinding(id, payload or {})
  if result and result.ok and type(self.toast) == "function" and type(result.conflictIds) == "table" and #result.conflictIds > 0 then
    self.toast(Toast.message.plain(
      result.message or "Shortcut saved. Conflicting TAPSHOP hotkeys were disabled until resolved.",
      { color = HOTKEY_WARNING_TOAST_COLOR }
    ))
  end
  return result
end

function AppState:resetHotkeyBinding(id)
  if not self.hotkeyManager or not self.hotkeyManager.resetBinding then
    return {
      ok = false,
      code = "missing_manager",
      ids = {
        [tostring(id or "")] = {},
      },
      message = "Hotkey manager unavailable.",
    }
  end

  local result = self.hotkeyManager:resetBinding(id)
  return result
end

function AppState:resetAllHotkeys()
  if not self.hotkeyManager or not self.hotkeyManager.resetAll then
    return {
      ok = false,
      code = "missing_manager",
      message = "Hotkey manager unavailable.",
    }
  end

  local result = self.hotkeyManager:resetAll()
  return result
end

-- hs.window.filter sink: destruction, fullscreen, recovery, YT target, popover UI.
function AppState:handleWindowEvent(event, win)
  local windowId = safeValue(function()
    return win and win:id()
  end)
  self:_recordDebug("window", "debug", event or "window_event", "window event observed", function()
    return {
      event = event,
      window = self:_windowDebugSnapshot(win),
    }
  end, {
    event = event,
    windowId = windowId,
  })

  if event == hs.window.filter.windowDestroyed then
    if not win then
      return
    end

    local deadId = win:id()
    self.youtubeService:handleDestroyedWindowId(deadId)

    local basePairingChanged = false
    local fullscreenStateChanged = false
    local closedWindowToast = nil
    self:_forEachWorkspace(function(workspace, profile)
      if workspace:getFullscreenTargetWindowId() == deadId and workspace:getBaseWindowId() ~= deadId then
        workspace:clearFullscreenState()
        fullscreenStateChanged = true
        if profile then
          self:_invalidateProfileSlotsCache(profile.id)
        end
      end
      if workspace:getBaseWindowId() == deadId then
        if workspace:hasTrackedFullscreenTarget()
          and workspace:getFullscreenTargetWindowId() ~= deadId then
          return
        end
        if workspace:hasTrackedFullscreenTarget()
          and workspace:getFullscreenTargetWindowId() == deadId
          and self.windowService.isWindowFullscreen(win) then
          workspace:clearFullscreenState()
          fullscreenStateChanged = true
          if profile then
            self:_invalidateProfileSlotsCache(profile.id)
          end
          return
        end
        if self.cfg.recoverClosedWindows then
          workspace:markClosedForRecovery()
        else
          closedWindowToast = self:_formatClosedWindowUnpairToast(workspace)
          workspace:clear()
        end
        basePairingChanged = true
        if profile then
          self:_invalidateProfileSlotsCache(profile.id)
        end
      end
    end)

    if basePairingChanged then
      self:_markRecoveryMatchIndexDirty()
      self:_scheduleWorkspacePairingPersist()
      if closedWindowToast then
        self.toast(closedWindowToast)
      end
      self:_syncWorkspaceUi("window_destroyed")
    elseif fullscreenStateChanged then
      self:_scheduleWorkspacePairingPersist()
      self:_syncWorkspaceUi("fullscreen_change")
    end
    return
  end

  if event == hs.window.filter.windowFullscreened then
    if not win then
      return
    end
    self:_refreshFocusedSpaceId()
    local winId = win:id()
    self:_forEachWorkspace(function(workspace, profile)
      if workspace:getBaseWindowId() == winId then
        local fullscreenSpaceId = self.windowService.getPrimarySpaceForWindow(win)
        -- Preserve existing advisory home; do not store the fullscreen Space as baseSpaceId.
        workspace:setFullscreenState({
          fullscreenWindowId = win:id(),
          fullscreenSpaceId = fullscreenSpaceId,
        })
        if profile then
          self:_invalidateProfileSlotsCache(profile.id)
        end
      end
    end)
    self:_scheduleWorkspacePairingPersist()
    self:_syncWorkspaceUi("fullscreen_change")
    self:_popoverFullscreenPolicy():onWindowFullscreened()
    return
  end

  if event == hs.window.filter.windowUnfullscreened then
    if not win then
      return
    end
    self:_refreshFocusedSpaceId()
    local winId = win:id()
    self:_forEachWorkspace(function(workspace, profile)
      if workspace:getFullscreenTargetWindowId() == winId then
        local spaceId = self:_updateWorkspaceBindingSpaceState(workspace, win)
        workspace:clearFullscreenState()
        if spaceId ~= nil then
          workspace:setBaseSpaceId(spaceId)
        end
        if profile then
          self:_invalidateProfileSlotsCache(profile.id)
        end
      elseif workspace:getBaseWindowId() == winId then
        local spaceId = self:_updateWorkspaceBindingSpaceState(workspace, win)
        workspace:clearFullscreenState()
        if spaceId ~= nil then
          workspace:setBaseSpaceId(spaceId)
        end
        if profile then
          self:_invalidateProfileSlotsCache(profile.id)
        end
      end
    end)
    self:_scheduleWorkspacePairingPersist()
    self:_syncWorkspaceUi("fullscreen_change")
    self:_popoverFullscreenPolicy():onWindowUnfullscreened()
    return
  end

  local restored = self:_recoverFromWindowEvent(event, win)
  local refreshKind = self:_refreshUiStateFromWindowEvent(event, win)
  if restored then
    refreshKind = "rows"
  end

  if refreshKind == "rows" and self.popover and self.popover.requestRefresh then
    self.popover:requestRefresh("window_event")
  elseif refreshKind == "header" and self.popover and self.popover.requestActiveWindowUpdate then
    self.popover:requestActiveWindowUpdate(win)
  end

end

-- Frontmost-window watcher: Space change may full-refresh popover; else header JS.
function AppState:handleActiveWindowChange(win)
  local previousSpaceId = self.session.focusedSpaceId
  self:_refreshFocusedSpaceId()
  local spaceChanged = previousSpaceId ~= self.session.focusedSpaceId
  local windowId = safeValue(function()
    return win and win:id()
  end)
  self:_recordDebug("focus", "debug", "active_window_changed", "active window changed", function()
    return {
      focusedSpaceId = self.session.focusedSpaceId,
      focusedSpaceChanged = spaceChanged,
      window = self:_windowDebugSnapshot(win),
    }
  end, {
    windowId = windowId,
  })
  if spaceChanged then
    self:_popoverFullscreenPolicy():onFocusedSpaceChanged()
    if self.popover and self.popover.requestRefresh then
      self.popover:requestRefresh("focused_space_change", win)
    end
  elseif self.popover and self.popover.requestActiveWindowUpdate then
    self.popover:requestActiveWindowUpdate(win)
  end
end

-- Primary Space-switch signal (Mission Control / trackpad). windowFocused often
-- does not fire on a plain swipe, so restore cannot rely on handleActiveWindowChange.
function AppState:handleFocusedSpaceChange()
  local previousSpaceId = self.session.focusedSpaceId
  self:_refreshFocusedSpaceId()
  local spaceChanged = previousSpaceId ~= self.session.focusedSpaceId
  local policy = self:_popoverFullscreenPolicy()
  self:_recordDebug("focus", "debug", "focused_space_changed", "focused Space changed", function()
    return {
      previousSpaceId = previousSpaceId,
      focusedSpaceId = self.session.focusedSpaceId,
      focusedIsFullscreen = self:_spaceIsFullscreen(self.session.focusedSpaceId),
      restorePinned = policy and policy:isRestorePinned() or false,
    }
  end)
  policy:onFocusedSpaceChanged()
  if spaceChanged and self.popover and self.popover.requestRefresh then
    local win = hs.window.frontmostWindow()
    self.popover:requestRefresh("focused_space_change", win)
  end
end

local POPOVER_ACTIONS = {}

local function slotAction(self, body, method)
  local slot = tonumber(body.slot) or 0
  if slot >= 1 and slot <= Layout.SLOTS_PER_PROFILE then
    method(self, slot, body.sourceWindow)
  end
end

POPOVER_ACTIONS["pair"] = function(self, body)
  slotAction(self, body, self.pairSlot)
end

POPOVER_ACTIONS["unpair"] = function(self, body)
  slotAction(self, body, self.unpairSlot)
end

POPOVER_ACTIONS["activateSlot"] = function(self, body)
  slotAction(self, body, self.activateSlot)
end

POPOVER_ACTIONS["unpairAll"] = function(self)
  self:unpairAll()
end

POPOVER_ACTIONS["toggleSettingsWindow"] = function(self)
  self:toggleSettingsWindow()
end

POPOVER_ACTIONS["activateProfile"] = function(self, body)
  local profileId = tonumber(body.profile)
  if profileId then
    self:activateProfile(profileId, {
      returnToSlots = body.returnToSlots == true or body.returnToSlots == 1,
      clientEpoch = tonumber(body.epoch),
    })
  end
end

POPOVER_ACTIONS["activatePreviousProfile"] = function(self)
  self:activatePreviousProfile()
end

POPOVER_ACTIONS["activateNextProfile"] = function(self)
  self:activateNextProfile()
end

POPOVER_ACTIONS["activatePreviousNonEmptyProfile"] = function(self)
  self:activatePreviousNonEmptyProfile()
end

POPOVER_ACTIONS["activateNextNonEmptyProfile"] = function(self)
  self:activateNextNonEmptyProfile()
end

POPOVER_ACTIONS["updateProfileMetadata"] = function(self, body)
  local profileId = tonumber(body.profile)
  if not profileId then
    return
  end
  local opts = {}
  if body.name ~= nil then
    opts.name = body.name
  end
  if body.clearColor == true or body.clearColor == 1 or body.color == "none" then
    opts.clearColor = true
  elseif body.color ~= nil then
    opts.color = body.color
  end
  self:updateProfileMetadata(profileId, opts)
end

POPOVER_ACTIONS["setAutoHideAfterAction"] = function(self, body)
  self:setPopoverAutoHide(tonumber(body.slot) == 1)
end

POPOVER_ACTIONS["setAlwaysOnTop"] = function(self, body)
  self:setPopoverAlwaysOnTop(tonumber(body.slot) == 1)
end

POPOVER_ACTIONS["setHidePairButtons"] = function(self, body)
  self:setPopoverHidePairButtons(tonumber(body.slot) == 1)
end

POPOVER_ACTIONS["setHideOnFullscreenWorkspace"] = function(self, body)
  self:setPopoverHideOnFullscreenWorkspace(tonumber(body.slot) == 1)
end

POPOVER_ACTIONS["setRecoverClosedWindows"] = function(self, body)
  self:setRecoverClosedWindows(tonumber(body.slot) == 1)
end

POPOVER_ACTIONS["setPopoverOpacity"] = function(self, body)
  local rawPercent = tonumber(body.slot)
  if rawPercent then
    self:setPopoverOpacity(rawPercent)
  end
end

POPOVER_ACTIONS["updateHotkeyBinding"] = function(self, body)
  return self:updateHotkeyBinding(body.id, {
    mods = body.mods,
    key = body.key,
    enabled = body.enabled,
  })
end

POPOVER_ACTIONS["resetHotkeyBinding"] = function(self, body)
  return self:resetHotkeyBinding(body.id)
end

POPOVER_ACTIONS["resetAllHotkeys"] = function(self)
  return self:resetAllHotkeys()
end

function AppState:handlePopoverAction(body)
  local handler = POPOVER_ACTIONS[body.action]
  if handler then
    return handler(self, body)
  end
end

-- Hotkey → YoutubeService:sendCommand (direct dispatch or same-browser fallback).
function AppState:sendYoutubeCommand(keyPress)
  return self.youtubeService:sendCommand(keyPress)
end

function AppState:spotifyPrevious()
  self.spotifyService:previous()
end

function AppState:spotifyNext()
  self.spotifyService:next()
end

function AppState:spotifyPlayPause()
  self.spotifyService:playPause()
end

function AppState:spotifySeekBack(seconds)
  self.spotifyService:seekBack(seconds)
end

function AppState:spotifySeekForward(seconds)
  self.spotifyService:seekForward(seconds)
end

function AppState:spotifyVolumeDown(step)
  self.spotifyService:volumeDown(step)
end

function AppState:spotifyVolumeUp(step)
  self.spotifyService:volumeUp(step)
end

function AppState:spotifyToggleLike()
  self.spotifyService:toggleLike()
end

function AppState:toggleSystemMute()
  self.systemAudioService:toggleMute()
end

function AppState:adjustSystemVolume(delta)
  self.systemAudioService:adjustVolume(delta)
end

return AppState
