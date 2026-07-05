local Workspace = require("state.workspace")
local SlotRecord = require("state.slot_record")
local SlotRow = require("state.slot_row")
local Layout = require("state.layout")
local Toast = require("ui.toast")

local AppState = {}
AppState.__index = AppState
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
    toast = deps.toast,
    profiles = {},
    session = {
      focusedSpaceId = nil,
      activeProfileId = initialProfileId,
    },
    hotkeyManager = nil,
    popover = nil,
    settingsWindow = nil,
  }, AppState)

  for profileId = 1, Layout.MAX_PROFILES do
    local profile = {
      id = profileId,
      name = "Profile " .. tostring(profileId),
      workspaces = {},
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

  self:_refreshFocusedSpaceId()
  self:_restoreStartupWorkspaceState()
  return self
end

function AppState:attachUi(popover, settingsWindow)
  self.popover = popover
  self.settingsWindow = settingsWindow
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

function AppState:getWorkspaceRowModels()
  self:_refreshFocusedSpaceId()
  return SlotRow.buildRows(self:getWorkspaces(), self.session, {
    windowService = self.windowService,
  })
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

function AppState:_syncWorkspaceUi()
  if self.popover and self.popover.requestRefresh then
    self.popover:requestRefresh("workspace_state")
  elseif self.popover and self.popover.refreshIfShown then
    self.popover:refreshIfShown()
  end
end

function AppState:_runPairingAction(actionFn)
  if self.windowService and self.windowService.cancelPendingFrontmostRequest then
    self.windowService.cancelPendingFrontmostRequest()
  end
  actionFn()
  self:_persistWorkspacePairings()
  self:_syncWorkspaceUi()
  if self.cfg.popoverAutoHideAfterAction and self.popover and self.popover.hide then
    self.popover:hide()
  end
  return true
end

function AppState:_runWorkspaceAction(actionFn)
  if self.windowService and self.windowService.cancelPendingFrontmostRequest then
    self.windowService.cancelPendingFrontmostRequest()
  end
  actionFn()
  self:_syncWorkspaceUi()
end

function AppState:_hidePopoverForFullscreenWorkspaceActivation()
  if not self.cfg.popoverHideOnFullscreenWorkspace then
    return
  end
  if self.popover and self.popover.hide then
    self.popover:hide()
  end
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

function AppState:_findFullscreenCompanion(workspace, sourceWin, fullscreenSpaceId)
  if not workspace or not sourceWin or not fullscreenSpaceId then
    return nil
  end
  if not self.windowService.candidateWindows then
    return nil
  end

  local sourceId = sourceWin:id()
  for _, candidate in ipairs(self.windowService:candidateWindows()) do
    if candidate and candidate:id() ~= sourceId
      and self.windowService.isWindowFullscreen(candidate)
      and self.windowService.windowIsInSpace(candidate, fullscreenSpaceId)
      and self:_windowTitleMatchesWorkspace(workspace, candidate) then
      return candidate
    end
  end

  return nil
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

function AppState:_restorePairedWorkspaceFromRecord(workspace, persisted)
  if not workspace or type(persisted) ~= "table" then
    return false
  end

  local baseWindowId = persisted.baseWindowId
  if not baseWindowId then
    workspace:clear()
    return false
  end

  local baseWin = self.windowService.getWindowById(baseWindowId)
  if baseWin then
    workspace:pair(baseWindowId, persisted.fingerprint)
    self:_refreshWorkspaceRuntimeApplicationIdentity(workspace, baseWin)
    if persisted.baseSpaceId then
      workspace:setBaseSpaceId(persisted.baseSpaceId)
    end
    self:_updateWorkspaceBindingSpaceState(workspace, baseWin)

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
      local baseSpaceId = workspace:getBaseSpaceId()
      local fullscreenTarget = self:_findFullscreenCompanion(workspace, baseWin, baseSpaceId) or baseWin
      workspace:setFullscreenState({
        fullscreenWindowId = fullscreenTarget:id(),
        fullscreenSpaceId = baseSpaceId,
        lastKnownSpaceId = workspace:getBaseSpaceId(),
      })
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

function AppState:_restoreWorkspaceFromPersistedRecord(workspace, persisted)
  if not workspace or type(persisted) ~= "table" then
    return false
  end

  if persisted.kind == "paired" then
    return self:_restorePairedWorkspaceFromRecord(workspace, persisted)
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
    local pairings = self:_workspacePairingSnapshot(profile)
    if next(pairings) ~= nil then
      profiles[profile.id] = pairings
    end
  end
  return profiles
end

function AppState:_persistWorkspacePairings()
  if self.appdata.setProfilesWindowPairings then
    self.appdata.setProfilesWindowPairings(self:_profilePairingSnapshot())
    return
  end

  self.appdata.setWindowPairings(self:_workspacePairingSnapshot(self:_getActiveProfile()))
end

function AppState:_restoreWorkspacePairings()
  local pairings = loadPersistedWorkspacePairings(self.appdata)
  local restoredCount = 0
  for profileId, profilePairings in pairs(pairings) do
    local profile = self:_getProfile(profileId)
    if profile then
      for index, persisted in pairs(profilePairings or {}) do
        local workspace = self:_getWorkspace(index, profile.id)
        if self:_restoreWorkspaceFromPersistedRecord(workspace, persisted) then
          restoredCount = restoredCount + 1
        end
      end
    end
  end
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
    self:_refreshWorkspaceRuntimeApplicationIdentity(workspace, target)
  end
end

function AppState:_refreshWorkspaceRuntimeApplicationIdentity(workspace, win)
  if not workspace or not self.windowService.runtimeApplicationIdentity then
    return
  end
  workspace:setRuntimeApplicationIdentity(self.windowService.runtimeApplicationIdentity(win))
end

function AppState:_refreshPairedWorkspaceMetadataForWindow(win, opts)
  if not win then
    return false
  end

  local id = win:id()
  if not id then
    return false
  end

  local meta = self.windowService.pairingMetadata(win)
  local matchedWorkspace = false
  self:_forEachWorkspace(function(workspace)
    local isBaseWindow = workspace:getBaseWindowId() == id
    if isBaseWindow or workspace:getFullscreenTargetWindowId() == id then
      matchedWorkspace = true
      workspace:setFingerprint(meta)
      self:_refreshWorkspaceRuntimeApplicationIdentity(workspace, win)
      if isBaseWindow and type(opts) == "table" and opts.updateSpace == true then
        self:_updateWorkspaceBindingSpaceState(workspace, win)
      end
    end
  end)

  return matchedWorkspace
end

function AppState:_pairWorkspace(workspace, windowId, win)
  workspace:pair(windowId, self.windowService.pairingMetadata(win))
  self:_refreshWorkspaceRuntimeApplicationIdentity(workspace, win)
  local spaceId = self:_updateWorkspaceBindingSpaceState(
    workspace,
    win
  )
  if self.windowService.isWindowFullscreen(win) then
    local fullscreenTarget = self:_findFullscreenCompanion(workspace, win, spaceId) or win
    workspace:setFullscreenState({
      fullscreenWindowId = fullscreenTarget:id(),
      fullscreenSpaceId = spaceId,
      lastKnownSpaceId = spaceId,
    })
  end
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

function AppState:_activateResolvedPairedWindow(workspace, paired, focusedSpaceId)
  if not workspace or not paired then
    return nil
  end

  local shouldInspectSpaces = workspace:getBaseSpaceId() ~= nil
    and focusedSpaceId ~= nil
    and workspace:getBaseSpaceId() ~= focusedSpaceId

  if shouldInspectSpaces then
    local targetSpaceId, inFocusedSpace, resolvedSpaceId = self:_resolvedTargetSpaceForWindow(paired, focusedSpaceId)
    if inFocusedSpace then
      if resolvedSpaceId then
        workspace:setBaseSpaceId(resolvedSpaceId)
      end
      self:_refreshWorkspaceFingerprint(workspace, paired)
      self.windowService.requestFrontmost(paired)
      return "base-window"
    end

    if targetSpaceId then
      local switchResult = self.windowService.gotoSpace(targetSpaceId, self.cfg)
      if switchResult.ok then
        workspace:setBaseSpaceId(targetSpaceId)
        self:_refreshWorkspaceFingerprint(workspace, paired)
        self.windowService.requestFrontmostAfterSpaceSwitch(paired, self.cfg)
        return "base-window-space-switch"
      end

      return nil
    end
  end

  self:_refreshWorkspaceFingerprint(workspace, paired)
  self.windowService.requestFrontmost(paired)
  return "base-window"
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

  local switchResult = self.windowService.gotoSpace(targetSpaceId, self.cfg)
  if not switchResult.ok then
    return nil
  end

  local resolved = self:_resolvePairedWindow(workspace)
  if not resolved then
    return nil
  end

  self:_updateWorkspaceBindingSpaceState(
    workspace,
    resolved
  )
  workspace:setBaseSpaceId(targetSpaceId)
  self:_refreshWorkspaceFingerprint(workspace, resolved)
  self.windowService.requestFrontmostAfterSpaceSwitch(resolved, self.cfg)
  return "base-window-id-space-switch"
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

function AppState:_restoreRecoverableWorkspacesForCandidate(win)
  if not self.cfg.recoverClosedWindows then
    return {}
  end

  local isCandidate = self.windowService.isRecoveryCandidateWindow or self.windowService.isCandidateWindow
  if not isCandidate or not isCandidate(win) then
    return {}
  end

  local candidateMeta = self.windowService.pairingMetadata(win)
  local candidateId = win:id()
  if not candidateMeta or not candidateId or self:_isWindowAlreadyPaired(candidateId) then
    return {}
  end

  local restoredWorkspaces = {}
  self:_forEachWorkspace(function(workspace)
    if not workspace:matchesRecoveryCandidate(candidateMeta) then
      return
    end

    if workspace:canRecover() then
      self:_pairWorkspace(workspace, candidateId, win)
      restoredWorkspaces[#restoredWorkspaces + 1] = workspace
    end
  end)

  return restoredWorkspaces
end

function AppState:_restoreWorkspaceFromCandidate(win, opts)
  local restoredWorkspaces = self:_restoreRecoverableWorkspacesForCandidate(win, opts)
  if #restoredWorkspaces > 0 then
    if not (type(opts) == "table" and opts.persist == false) then
      self:_persistWorkspacePairings()
    end
    if not (type(opts) == "table" and opts.notify == false) then
      self.toast(self:_formatRestoreToast(restoredWorkspaces, win))
    end
    return true
  end
  return false
end

function AppState:_restoreRecoverableWorkspacesFromExistingCandidates()
  if not self.cfg.recoverClosedWindows then
    return false
  end

  local hasRecoverableWorkspace = false
  self:_forEachWorkspace(function(workspace)
    if workspace:canRecover() then
      hasRecoverableWorkspace = true
    end
  end)
  if not hasRecoverableWorkspace then
    return false
  end

  if not self.windowService.candidateWindows then
    return false
  end

  local candidates = self.windowService:candidateWindows() or {}
  local restored = false
  for _, win in ipairs(candidates) do
    local restoredWorkspaces = self:_restoreRecoverableWorkspacesForCandidate(win)
    if #restoredWorkspaces > 0 then
      restored = true
    end
  end

  return restored
end

local function workspaceMatchesTerminatedApp(workspace, terminatedIdentity)
  local fingerprint = workspace and workspace:getFingerprint() or nil
  if type(fingerprint) ~= "table" then
    return false
  end

  if type(terminatedIdentity) ~= "table" then
    return false
  end

  if type(terminatedIdentity.pid) == "number" then
    local runtimePid = workspace.getRuntimeApplicationPid and workspace:getRuntimeApplicationPid() or nil
    if runtimePid == terminatedIdentity.pid then
      return true
    end
  end

  if type(terminatedIdentity.bundleID) == "string" and terminatedIdentity.bundleID ~= "" then
    return fingerprint.bundleID == terminatedIdentity.bundleID
  end

  if type(terminatedIdentity.appName) == "string" and terminatedIdentity.appName ~= "" then
    return fingerprint.appName == terminatedIdentity.appName
  end

  return false
end

function AppState:handleApplicationTerminated(appName, appObject)
  if not self.cfg.recoverClosedWindows then
    return false
  end

  local terminatedIdentity = self.windowService.applicationIdentity
    and self.windowService.applicationIdentity(appName, appObject)
    or nil
  if not terminatedIdentity then
    return false
  end

  local changed = false
  local function visitProfile(profile)
    if not profile then
      return
    end

    for _, workspace in ipairs(profile.workspaces or {}) do
      if workspace:isPaired()
        and workspaceMatchesTerminatedApp(workspace, terminatedIdentity) then
        local baseWindowId = workspace:getBaseWindowId()
        local fullscreenTargetWindowId = workspace:getFullscreenTargetWindowId()
        if baseWindowId then
          self.youtubeService:handleDestroyedWindowId(baseWindowId)
        end
        if fullscreenTargetWindowId and fullscreenTargetWindowId ~= baseWindowId then
          self.youtubeService:handleDestroyedWindowId(fullscreenTargetWindowId)
        end

        workspace:markClosedForRecovery()
        changed = true
      end
    end
  end

  local activeProfile = self:_getActiveProfile()
  visitProfile(activeProfile)
  for _, profile in ipairs(self.profiles or {}) do
    if profile ~= activeProfile then
      visitProfile(profile)
    end
  end

  if changed then
    self:_persistWorkspacePairings()
    self:syncUi()
  end

  return changed
end

function AppState:_restoreStartupWorkspaceState()
  self:_restoreWorkspacePairings()
  self:_restoreRecoverableWorkspacesFromExistingCandidates()
  self:_persistWorkspacePairings()
  if self.appdata.setActiveProfileId then
    self.appdata.setActiveProfileId(self.session.activeProfileId)
  end
end

function AppState:_formatPairToast(workspace, win)
  local app = win and win:application() or nil
  local label = self.windowService.windowTitle and self.windowService.windowTitle(win) or self.windowService.displayTitle(win)
  return Toast.message.windowAction({
    prefixText = string.format("Pairing %s: ", workspace:getName()),
    titleText = label,
    bundleID = app and app:bundleID() or nil,
    appName = app and app:name() or nil,
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
    prefixText = string.format("Unpairing %s: ", workspace:getName()),
    titleText = label,
    bundleID = app and app:bundleID() or fingerprint.bundleID or nil,
    appName = app and app:name() or fingerprint.appName or nil,
    prefixColor = TOAST_WHITE,
    titleColor = UNPAIR_TOAST_COLOR,
  })
end

function AppState:_formatClosedWindowUnpairToast(workspace)
  local fingerprint = workspace and workspace:getFingerprint() or {}
  return Toast.message.windowAction({
    prefixText = "[Unpaired Closed Window: ",
    titleText = workspace and workspace:getStoredWindowTitle() or "[empty]",
    bundleID = fingerprint.bundleID or nil,
    appName = fingerprint.appName or nil,
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
    names[#names + 1] = ws:getName()
  end
  return Toast.message.windowAction({
    prefixText = "Restored " .. table.concat(names, ", ") .. ": ",
    titleText = label,
    bundleID = app and app:bundleID() or nil,
    appName = app and app:name() or nil,
    prefixColor = TOAST_WHITE,
    titleColor = PAIR_TOAST_COLOR,
    duration = 2.0,
  })
end

function AppState:_clearRecoverableWorkspaces()
  local changed = false
  self:_forEachWorkspace(function(workspace)
    if workspace:isRecoverable() then
      workspace:clear()
      changed = true
    end
  end)
  return changed
end

function AppState:_clearWorkspaceAndPersist(workspace)
  if not workspace then
    return
  end
  workspace:clear()
  self:_persistWorkspacePairings()
end

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

function AppState:activateSlot(index)
  local workspace = self:_getWorkspace(index)
  if not workspace then
    return
  end

  local bindingChanged = false
  self:_runWorkspaceAction(function()
    local win = hs.window.frontmostWindow()
    if not win then
      self.toast(Toast.message.plain("No active window found!"))
      return
    end

    local currentId = win:id()
    local focusedSpaceId = self.windowService.focusedSpaceId and self.windowService.focusedSpaceId() or nil
    if not workspace:isPaired() then
      self:_pairWorkspace(workspace, currentId, win)
      bindingChanged = true
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
          end

          if focusedSpaceId == resolvedFullscreenSpaceId then
            local fullscreenWin = self.windowService.getWindowById(workspace:getFullscreenTargetWindowId())
            if fullscreenWin then
              self:_hidePopoverForFullscreenWorkspaceActivation()
              workspace:setFullscreenState({
                fullscreenWindowId = fullscreenWin:id(),
                fullscreenSpaceId = resolvedFullscreenSpaceId,
                lastKnownSpaceId = workspace:getBaseSpaceId(),
              })
              self.windowService.requestFrontmost(fullscreenWin)
              self:_refreshWorkspaceFingerprint(workspace, fullscreenWin)
              return
            end
          else
            local switchResult = self.windowService.gotoSpace(resolvedFullscreenSpaceId, self.cfg)
            if switchResult.ok then
              local fullscreenWin = self.windowService.getWindowById(workspace:getFullscreenTargetWindowId())
              if fullscreenWin then
                self:_hidePopoverForFullscreenWorkspaceActivation()
                workspace:setFullscreenState({
                  fullscreenWindowId = fullscreenWin:id(),
                  fullscreenSpaceId = resolvedFullscreenSpaceId,
                  lastKnownSpaceId = workspace:getBaseSpaceId(),
                })
                self.windowService.requestFrontmostAfterSpaceSwitch(fullscreenWin, self.cfg)
                self:_refreshWorkspaceFingerprint(workspace, fullscreenWin)
                return
              end
            end
          end
        else
          workspace:clearFullscreenState()
          bindingChanged = true
        end
      end

      local paired = self:_resolvePairedWindow(workspace)
      if paired then
        workspace:resetInputBuffer()
        self:_activateResolvedPairedWindow(workspace, paired, focusedSpaceId)
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
      return
    end
  end)

  if bindingChanged then
    self:_persistWorkspacePairings()
  end
end

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
      self.toast(toastPayload)
    else
      self.toast(Toast.message.plain(workspace:getName() .. " is already unpaired!"))
    end
  end)
end

function AppState:unpairAll()
  return self:_runPairingAction(function()
    local cleared = false
    for _, workspace in ipairs(self:getWorkspaces()) do
      if workspace:isPaired() or workspace:isRecoverable() then
        workspace:clear()
        cleared = true
      end
    end
    self.toast(Toast.message.plain(cleared and "[Unpaired All Windows]" or "[No Paired Windows]"))
  end)
end

function AppState:activateProfile(profileId)
  local profile = self:_getProfile(profileId)
  if not profile or profile.id == self.session.activeProfileId then
    return false
  end

  self.session.activeProfileId = profile.id
  if self.appdata.setActiveProfileId then
    self.appdata.setActiveProfileId(profile.id)
  end
  self:_syncWorkspaceUi()
  self.toast(Toast.message.plain(string.format("[Active Profile: %d]", profile.id)))
  return true
end

function AppState:activatePreviousProfile()
  local profileId = self.session.activeProfileId - 1
  if profileId < 1 then
    profileId = self:getProfileCount()
  end
  return self:activateProfile(profileId)
end

function AppState:activateNextProfile()
  local profileId = self.session.activeProfileId + 1
  if profileId > self:getProfileCount() then
    profileId = 1
  end
  return self:activateProfile(profileId)
end

function AppState:togglePopover()
  if self.popover and self.popover.toggleOrFocus then
    self.popover:toggleOrFocus()
    return
  end

  if self.popover and self.popover.toggle then
    self.popover:toggle()
  end
end

function AppState:showPopover()
  if self.popover and self.popover.show then
    self.popover:show()
  end
end

function AppState:toggleSettingsWindow()
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
  self:syncUi()
end

function AppState:setRecoverClosedWindows(enabled)
  self.cfg.recoverClosedWindows = enabled == true
  self.settings.setRecoverClosedWindows(self.cfg.recoverClosedWindows)
  if not self.cfg.recoverClosedWindows and self:_clearRecoverableWorkspaces() then
    self:_persistWorkspacePairings()
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

function AppState:handleWindowEvent(event, win)
  if event == hs.window.filter.windowDestroyed then
    if not win then
      return
    end

    local deadId = win:id()
    self.youtubeService:handleDestroyedWindowId(deadId)

    local basePairingChanged = false
    local fullscreenStateChanged = false
    local closedWindowToast = nil
    self:_forEachWorkspace(function(workspace)
      if workspace:getFullscreenTargetWindowId() == deadId and workspace:getBaseWindowId() ~= deadId then
        workspace:clearFullscreenState()
        fullscreenStateChanged = true
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
          return
        end
        if self.cfg.recoverClosedWindows then
          workspace:markClosedForRecovery()
        else
          closedWindowToast = self:_formatClosedWindowUnpairToast(workspace)
          workspace:clear()
        end
        basePairingChanged = true
      end
    end)

    if basePairingChanged then
      self:_persistWorkspacePairings()
      if closedWindowToast then
        self.toast(closedWindowToast)
      end
      self:syncUi()
    elseif fullscreenStateChanged then
      self:_persistWorkspacePairings()
      self:syncUi()
    end
    return
  end

  if event == hs.window.filter.windowFullscreened then
    if not win then
      return
    end
    self:_refreshFocusedSpaceId()
    local winId = win:id()
    self:_forEachWorkspace(function(workspace)
      if workspace:getBaseWindowId() == winId then
        local spaceId = self:_updateWorkspaceBindingSpaceState(workspace, win)
        local fullscreenTarget = self:_findFullscreenCompanion(workspace, win, spaceId) or win
        workspace:setFullscreenState({
          fullscreenWindowId = fullscreenTarget:id(),
          fullscreenSpaceId = spaceId,
          lastKnownSpaceId = spaceId,
        })
      end
    end)
    self:_persistWorkspacePairings()
    self:syncUi()
    return
  end

  if event == hs.window.filter.windowUnfullscreened then
    if not win then
      return
    end
    self:_refreshFocusedSpaceId()
    local winId = win:id()
    self:_forEachWorkspace(function(workspace)
      if workspace:getFullscreenTargetWindowId() == winId then
        local spaceId = self:_updateWorkspaceBindingSpaceState(workspace, win)
        workspace:clearFullscreenState()
        if spaceId ~= nil then
          workspace:setBaseSpaceId(spaceId)
        end
      elseif workspace:getBaseWindowId() == winId then
        local spaceId = self:_updateWorkspaceBindingSpaceState(workspace, win)
        workspace:clearFullscreenState()
        if spaceId ~= nil then
          workspace:setBaseSpaceId(spaceId)
        end
      end
    end)
    self:_persistWorkspacePairings()
    self:syncUi()
    return
  end

  local restored = false
  if event == hs.window.filter.windowCreated and win then
    restored = self:_restoreWorkspaceFromCandidate(win)
  end

  local pairedWorkspaceTouched = self:_refreshPairedWorkspaceMetadataForWindow(win, {
    updateSpace = event == hs.window.filter.windowFocused,
  })
  self.youtubeService:handleWindowCandidate(win)

  local shouldRefreshPopover = event == hs.window.filter.windowFocused or pairedWorkspaceTouched or restored
  if win then
    local frontmost = hs.window.frontmostWindow()
    if frontmost and frontmost:id() == win:id() then
      shouldRefreshPopover = true
    end
  end

  if shouldRefreshPopover and self.popover and self.popover.requestRefresh then
    self.popover:requestRefresh("window_event")
  end

end

function AppState:handleActiveWindowChange(win)
  self:_refreshFocusedSpaceId()
  if self.popover and self.popover.requestActiveWindowUpdate then
    self.popover:requestActiveWindowUpdate(win)
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

POPOVER_ACTIONS["unpairAll"] = function(self)
  self:unpairAll()
end

POPOVER_ACTIONS["toggleSettingsWindow"] = function(self)
  self:toggleSettingsWindow()
end

POPOVER_ACTIONS["activateProfile"] = function(self, body)
  local profileId = tonumber(body.profile)
  if profileId then
    self:activateProfile(profileId)
  end
end

POPOVER_ACTIONS["activatePreviousProfile"] = function(self)
  self:activatePreviousProfile()
end

POPOVER_ACTIONS["activateNextProfile"] = function(self)
  self:activateNextProfile()
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
