local Workspace = {}
Workspace.__index = Workspace

local function cloneFingerprint(recoveryMeta)
  if type(recoveryMeta) ~= "table" then
    return {
      bundleID = nil,
      appName = nil,
      titleRaw = nil,
      titleNormalized = nil,
    }
  end

  local function normalizeString(value)
    if type(value) ~= "string" or value == "" then
      return nil
    end
    return value
  end

  return {
    bundleID = normalizeString(recoveryMeta.bundleID),
    appName = normalizeString(recoveryMeta.appName),
    titleRaw = type(recoveryMeta.titleRaw) == "string" and recoveryMeta.titleRaw or nil,
    titleNormalized = normalizeString(recoveryMeta.titleNormalized),
  }
end

function Workspace.new(indexOrName, nameOrThreshold, maybeThreshold)
  local index = nil
  local name = nil
  local minimizeThreshold = nil

  if type(indexOrName) == "number" then
    index = indexOrName
    name = tostring(nameOrThreshold or ("Window " .. tostring(index)))
    minimizeThreshold = maybeThreshold
  else
    name = tostring(indexOrName or "Window")
    minimizeThreshold = nameOrThreshold
  end

  return setmetatable({
    index = index,
    name = name,
    interaction = {
      repeatBuffer = minimizeThreshold,
    },
    binding = {
      kind = "empty",
      baseWindowId = nil,
      baseSpaceId = nil,
      fullscreenTarget = {
        windowId = nil,
        spaceId = nil,
      },
      fingerprint = cloneFingerprint(nil),
    },
    runtime = {
      application = nil,
    },
    _minimizeThreshold = minimizeThreshold,
  }, Workspace)
end

function Workspace:getName()
  return self.name
end

function Workspace:getIndex()
  return self.index
end

function Workspace:getBaseWindowId()
  return self.binding.baseWindowId
end

function Workspace:getBindingKind()
  return self.binding.kind
end

function Workspace:getFingerprint()
  return self.binding.fingerprint
end

function Workspace:getBaseSpaceId()
  return self.binding.baseSpaceId
end

function Workspace:getFullscreenTargetWindowId()
  return self.binding.fullscreenTarget.windowId
end

function Workspace:getFullscreenTargetSpaceId()
  return self.binding.fullscreenTarget.spaceId
end

function Workspace:isPaired()
  return self.binding.kind == "paired" and self.binding.baseWindowId ~= nil
end

function Workspace:isRecoverable()
  return self.binding.kind == "recoverable"
end

function Workspace:pair(baseWindowId, recoveryMeta)
  self.binding.kind = "paired"
  self.binding.baseWindowId = baseWindowId
  self.binding.baseSpaceId = nil
  self:setFingerprint(recoveryMeta)
  self:clearRuntimeApplicationIdentity()
  self:clearFullscreenState()
  self:resetInputBuffer()
end

function Workspace:setFingerprint(recoveryMeta)
  self.binding.fingerprint = cloneFingerprint(recoveryMeta)
end

function Workspace:setRecoverable(recoveryMeta)
  self.binding.kind = "recoverable"
  self.binding.baseWindowId = nil
  self.binding.baseSpaceId = nil
  self:setFingerprint(recoveryMeta)
  self:clearRuntimeApplicationIdentity()
  self:resetInputBuffer()
  self:clearFullscreenState()
end

function Workspace:clear()
  self.binding.kind = "empty"
  self.binding.baseWindowId = nil
  self.binding.baseSpaceId = nil
  self.binding.fingerprint = cloneFingerprint(nil)
  self:clearRuntimeApplicationIdentity()
  self:resetInputBuffer()
  self:clearFullscreenState()
end

function Workspace:markClosedForRecovery()
  self:setRecoverable(self.binding.fingerprint)
end

function Workspace:canRecover()
  local fingerprint = self.binding.fingerprint

  if self.binding.kind ~= "recoverable" then
    return false
  end
  return fingerprint.bundleID ~= nil and fingerprint.titleNormalized ~= nil
end

function Workspace:matchesRecoveryCandidate(candidateMeta)
  local fingerprint = self.binding.fingerprint

  if type(candidateMeta) ~= "table" then
    return false
  end
  if not fingerprint.bundleID or not fingerprint.titleNormalized then
    return false
  end
  return fingerprint.bundleID == candidateMeta.bundleID
    and fingerprint.titleNormalized == candidateMeta.titleNormalized
end

function Workspace:setRuntimeApplicationIdentity(identity)
  if type(identity) ~= "table" then
    self:clearRuntimeApplicationIdentity()
    return
  end

  local pid = type(identity.pid) == "number" and identity.pid or nil
  local bundleID = type(identity.bundleID) == "string" and identity.bundleID ~= "" and identity.bundleID or nil
  local appName = type(identity.appName) == "string" and identity.appName ~= "" and identity.appName or nil
  if not pid and not bundleID and not appName then
    self:clearRuntimeApplicationIdentity()
    return
  end

  self.runtime.application = {
    pid = pid,
    bundleID = bundleID,
    appName = appName,
  }
end

function Workspace:clearRuntimeApplicationIdentity()
  self.runtime.application = nil
end

function Workspace:getRuntimeApplicationIdentity()
  return self.runtime.application
end

function Workspace:getRuntimeApplicationPid()
  local identity = self.runtime.application
  return identity and identity.pid or nil
end

function Workspace:resetInputBuffer()
  self.interaction.repeatBuffer = self._minimizeThreshold
end

function Workspace:consumeRepeatPress()
  self.interaction.repeatBuffer = self.interaction.repeatBuffer - 1
  return self.interaction.repeatBuffer
end

function Workspace:shouldMinimize()
  return self.interaction.repeatBuffer <= 0
end

function Workspace:setBaseSpaceId(spaceId)
  self.binding.baseSpaceId = spaceId
end

function Workspace:getStoredWindowTitle()
  local titleRaw = self.binding.fingerprint.titleRaw
  if type(titleRaw) == "string" and titleRaw:match("%S") then
    return titleRaw
  end
  return "[empty]"
end

function Workspace:setFullscreenState(opts)
  if type(opts) ~= "table" then
    return
  end

  self.binding.fullscreenTarget.windowId = opts.fullscreenWindowId
  self.binding.fullscreenTarget.spaceId = opts.fullscreenSpaceId

  if opts.lastKnownSpaceId ~= nil then
    self.binding.baseSpaceId = opts.lastKnownSpaceId
  end
end

function Workspace:clearFullscreenState()
  self.binding.fullscreenTarget.windowId = nil
  self.binding.fullscreenTarget.spaceId = nil
end

function Workspace:hasTrackedFullscreenTarget()
  return self.binding.fullscreenTarget.windowId ~= nil
end

return Workspace
