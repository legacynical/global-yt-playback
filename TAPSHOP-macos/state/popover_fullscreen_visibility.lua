-- PopoverFullscreenVisibility: hide/restore the main popover around fullscreen
-- Spaces for "Hide during fullscreens". Callers emit events; this module owns
-- the restore pin, reconcile, and settle timer.
--
-- Collection behavior (omit/include fullScreenAuxiliary) stays on the popover
-- controller. Active hide is still required because canJoinAllSpaces panels
-- can appear on fullscreen Spaces even without fullScreenAuxiliary.

local PopoverFullscreenVisibility = {}
PopoverFullscreenVisibility.__index = PopoverFullscreenVisibility

-- focusedSpace()/spaceType can lag past a single tick; a short ladder covers
-- leave-FS restore without waiting for another user gesture.
local SETTLE_DELAYS_SECONDS = { 0.08, 0.16, 0.32 }

local function popoverShown(popover)
  return popover
    and type(popover.isShown) == "function"
    and popover:isShown() == true
end

function PopoverFullscreenVisibility.new(deps)
  deps = deps or {}
  local self = setmetatable({
    _isEnabled = deps.isEnabled,
    _isSpaceFullscreen = deps.isSpaceFullscreen,
    _getFocusedSpaceId = deps.getFocusedSpaceId,
    _refreshFocusedSpaceId = deps.refreshFocusedSpaceId,
    _getPopover = deps.getPopover or function()
      return deps.popover
    end,
    _schedule = deps.schedule or (hs.timer and hs.timer.doAfter),
    _restorePinned = false,
    _settleGeneration = 0,
  }, PopoverFullscreenVisibility)
  return self
end

function PopoverFullscreenVisibility:_enabled()
  return type(self._isEnabled) == "function" and self._isEnabled() == true
end

function PopoverFullscreenVisibility:_focusedIsFullscreen()
  if type(self._isSpaceFullscreen) ~= "function" or type(self._getFocusedSpaceId) ~= "function" then
    return false
  end
  return self._isSpaceFullscreen(self._getFocusedSpaceId()) == true
end

function PopoverFullscreenVisibility:_spaceIsFullscreen(spaceId)
  return spaceId ~= nil
    and type(self._isSpaceFullscreen) == "function"
    and self._isSpaceFullscreen(spaceId) == true
end

function PopoverFullscreenVisibility:_hideIfShown()
  if not self:_enabled() then
    return false
  end
  local popover = self._getPopover and self._getPopover() or nil
  if not popoverShown(popover) then
    return false
  end
  self._restorePinned = true
  if type(popover.hide) == "function" then
    popover:hide()
  end
  return true
end

function PopoverFullscreenVisibility:_reconcile()
  if not self:_enabled() then
    return
  end

  if self:_focusedIsFullscreen() then
    self:_hideIfShown()
    return
  end

  if not self._restorePinned then
    return
  end

  local popover = self._getPopover and self._getPopover() or nil
  if not popover then
    self._restorePinned = false
    return
  end

  if type(popover.ensureVisible) == "function" then
    popover:ensureVisible()
  elseif type(popover.show) == "function" then
    popover:show()
  end

  -- Keep the pin if show did not stick so later settle passes can retry.
  if popoverShown(popover) then
    self._restorePinned = false
  end
end

function PopoverFullscreenVisibility:_scheduleSettle()
  if not self:_enabled() or type(self._schedule) ~= "function" then
    return
  end

  self._settleGeneration = self._settleGeneration + 1
  local gen = self._settleGeneration
  for _, delay in ipairs(SETTLE_DELAYS_SECONDS) do
    self._schedule(delay, function()
      if gen ~= self._settleGeneration then
        return
      end
      local before = type(self._getFocusedSpaceId) == "function" and self._getFocusedSpaceId() or nil
      if type(self._refreshFocusedSpaceId) == "function" then
        self._refreshFocusedSpaceId()
      end
      local after = type(self._getFocusedSpaceId) == "function" and self._getFocusedSpaceId() or nil
      if before ~= after or self:_focusedIsFullscreen() or self._restorePinned then
        self:_reconcile()
      end
    end)
  end
end

function PopoverFullscreenVisibility:onFocusedSpaceChanged()
  self:_reconcile()
  self:_scheduleSettle()
end

function PopoverFullscreenVisibility:onWindowFullscreened()
  self:_reconcile()
  self:_scheduleSettle()
end

function PopoverFullscreenVisibility:onWindowUnfullscreened()
  self:_reconcile()
  self:_scheduleSettle()
end

-- Preemptive hide before gotoSpace / same-Space FS focus so canJoinAllSpaces
-- cannot keep the panel visible across the transition.
function PopoverFullscreenVisibility:beforeEnteringSpace(spaceId)
  if self:_spaceIsFullscreen(spaceId) then
    self:_hideIfShown()
  end
end

function PopoverFullscreenVisibility:onSettingChanged(enabled)
  local popover = self._getPopover and self._getPopover() or nil
  if popover and type(popover.syncWindowLevel) == "function" then
    popover:syncWindowLevel()
  end
  if enabled == true then
    if type(self._refreshFocusedSpaceId) == "function" then
      self._refreshFocusedSpaceId()
    end
    self:_reconcile()
  elseif enabled == false then
    -- Setting off: do not restore from a stale pin; user turned the policy off.
    self._restorePinned = false
  end
end

function PopoverFullscreenVisibility:noteIntentionalDismiss()
  self._restorePinned = false
end

function PopoverFullscreenVisibility:isRestorePinned()
  return self._restorePinned == true
end

function PopoverFullscreenVisibility:dispose()
  self._settleGeneration = self._settleGeneration + 1
  self._restorePinned = false
end

return PopoverFullscreenVisibility
