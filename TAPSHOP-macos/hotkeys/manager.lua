-- HotkeyManager: bind/resolve/override TAPSHOP hotkeys from registry + appdata.
-- Dispatches to AppState methods by binding.action; guards system-shortcut
-- collisions; maintains settings UI row/HTML caches.

local Registry = require("hotkeys.registry")
local Normalize = require("persistence.normalize")

local HotkeyManager = {}
HotkeyManager.__index = HotkeyManager

local SYSTEM_SHORTCUTS = {
  ["cmd+h"] = "Hide Application",
  ["cmd+q"] = "Quit Application",
  ["cmd+space"] = "Spotlight",
  ["cmd+tab"] = "App Switcher",
  ["cmd+shift+q"] = "Log Out",
  ["cmd+alt+esc"] = "Force Quit",
  ["ctrl+up"] = "Mission Control",
  ["ctrl+down"] = "App Expose",
  ["ctrl+left"] = "Switch Space Left",
  ["ctrl+right"] = "Switch Space Right",
}

local FALLBACK_BINDING_ID = "popover.toggle"
local FALLBACK_MODS = { "cmd", "alt" }
local FALLBACK_KEY = "`"
local FALLBACK_WINDOW_SECONDS = 0.8
local ASSIGNABLE_MODS = {
  cmd = true,
  alt = true,
  ctrl = true,
  shift = true,
}
local MOD_ORDER = {
  cmd = 1,
  alt = 2,
  ctrl = 3,
  shift = 4,
}

local function cloneArray(values)
  local out = {}
  for _, value in ipairs(values or {}) do
    out[#out + 1] = value
  end
  return out
end

local function cloneBinding(binding)
  return {
    id = binding.id,
    group = binding.group,
    label = binding.label,
    mods = cloneArray(binding.mods),
    key = binding.key,
    action = binding.action,
    args = cloneArray(binding.args),
    guarded = binding.guarded == true,
    enabled = binding.enabled ~= false,
  }
end

local function normalizeConflictKey(key)
  return Normalize.normalizeKey(key) or ""
end

local function normalizeConflictMods(mods)
  local normalized = {}
  for _, mod in ipairs(mods or {}) do
    local value = tostring(mod)
    if MOD_ORDER[value] then
      normalized[#normalized + 1] = value
    end
  end
  table.sort(normalized, function(a, b)
    return MOD_ORDER[a] < MOD_ORDER[b]
  end)

  local deduped = {}
  local last = nil
  for _, mod in ipairs(normalized) do
    if mod ~= last then
      deduped[#deduped + 1] = mod
    end
    last = mod
  end
  return deduped
end

local function normalizeConflictCombo(mods, key)
  local parts = normalizeConflictMods(mods)
  parts[#parts + 1] = normalizeConflictKey(key)
  return table.concat(parts, "+")
end

local function detectConflicts(bindingsById)
  local comboMap = {}
  for id, binding in pairs(bindingsById or {}) do
    if binding.enabled and binding.key ~= false and binding.key ~= nil and binding.key ~= "" then
      local combo = normalizeConflictCombo(binding.mods, binding.key)
      comboMap[combo] = comboMap[combo] or {}
      comboMap[combo][#comboMap[combo] + 1] = id
    end
  end

  local conflictsById = {}
  for _, ids in pairs(comboMap) do
    if #ids > 1 then
      for _, id in ipairs(ids) do
        conflictsById[id] = {}
        for _, otherId in ipairs(ids) do
          if otherId ~= id then
            conflictsById[id][#conflictsById[id] + 1] = otherId
          end
        end
      end
    end
  end
  return conflictsById
end

local function bindingUsesDefaultPopoverShortcut(binding)
  if not binding then
    return false
  end
  return normalizeConflictCombo(binding.mods, binding.key) == normalizeConflictCombo(FALLBACK_MODS, FALLBACK_KEY)
end

local function isSystemKey(key)
  return Normalize.isSystemKey(key)
end

local function toBindableKey(key)
  if key == false or key == nil or key == "" then
    return nil
  end
  if isSystemKey(key) then
    return tostring(Normalize.normalizeKey(key) or "")
  end
  return string.lower(tostring(key or ""))
end

local function toAssignableMods(mods)
  local normalized = {}
  for _, mod in ipairs(mods or {}) do
    local value = tostring(mod or "")
    if not ASSIGNABLE_MODS[value] then
      return nil, value
    end
    normalized[#normalized + 1] = value
  end
  return normalized, nil
end

local function keyIsAvailable(key)
  if isSystemKey(key) then
    return true
  end
  local bindableKey = toBindableKey(key)
  if not bindableKey then
    return false
  end
  return hs.keycodes.map[bindableKey] ~= nil
end

local function modsFromFlags(flags)
  local mods = {}
  if flags and flags.cmd then
    mods[#mods + 1] = "cmd"
  end
  if flags and flags.alt then
    mods[#mods + 1] = "alt"
  end
  if flags and flags.ctrl then
    mods[#mods + 1] = "ctrl"
  end
  if flags and flags.shift then
    mods[#mods + 1] = "shift"
  end
  return normalizeConflictMods(mods)
end

local function eventFlags(event)
  local merged = {}

  if event and event.getFlags then
    local ok, flags = pcall(event.getFlags, event)
    if ok and type(flags) == "table" then
      for key, value in pairs(flags) do
        if value then
          merged[key] = true
        end
      end
    end
  end

  if event
    and event.getType
    and event:getType() == hs.eventtap.event.types.systemDefined
    and hs.eventtap
    and type(hs.eventtap.checkKeyboardModifiers) == "function" then
    local ok, liveFlags = pcall(hs.eventtap.checkKeyboardModifiers)
    if ok and type(liveFlags) == "table" then
      for key, value in pairs(liveFlags) do
        if value then
          merged[key] = true
        end
      end
    end
  end

  return merged
end

local function comboIsAssignable(mods, key)
  if not keyIsAvailable(key) then
    return false, "missing_key"
  end

  if isSystemKey(key) then
    return true, nil
  end

  local assignableMods, unsupportedMod = toAssignableMods(mods)
  if unsupportedMod then
    return false, unsupportedMod
  end

  local bindableKey = toBindableKey(key)
  if not hs.hotkey or type(hs.hotkey.assignable) ~= "function" then
    return true, nil
  end

  local ok, assignable = pcall(hs.hotkey.assignable, assignableMods, bindableKey)
  if not ok then
    hs.printf("[tapshop-hotkeys] failed to check assignable %s: %s", tostring(bindableKey), tostring(assignable))
    return true, nil
  end
  return assignable == true, assignable == true and nil or "system_reserved"
end

local function getSystemAssignedInfo(mods, key)
  if not hs.hotkey or type(hs.hotkey.systemAssigned) ~= "function" then
    return false
  end

  local assignableMods, unsupportedMod = toAssignableMods(mods)
  if unsupportedMod then
    return false
  end

  local bindableKey = toBindableKey(key)
  if not bindableKey then
    return false
  end

  local ok, result = pcall(hs.hotkey.systemAssigned, assignableMods, bindableKey)
  if not ok then
    hs.printf("[tapshop-hotkeys] failed to check systemAssigned %s: %s", tostring(bindableKey), tostring(result))
    return false
  end
  return result
end

local function assignabilityWarning(mods, key, reason)
  if reason == "missing_key" then
    return "Key is unavailable in the current keyboard layout."
  end
  if reason == "system_reserved" then
    local info = getSystemAssignedInfo(mods, key)
    if info then
      return "Shortcut is reserved by macOS and cannot be assigned."
    end
    return "Shortcut cannot be assigned by Hammerspoon."
  end
  return "Shortcut cannot be assigned."
end

local function bindHotkeySafe(mods, key, fn)
  local assignableMods, unsupportedMod = toAssignableMods(mods)
  if unsupportedMod then
    hs.printf("[tapshop-hotkeys] failed to bind %s: unsupported modifier %s", tostring(key), tostring(unsupportedMod))
    return nil
  end

  local bindableKey = toBindableKey(key)
  local ok, bindingOrErr = pcall(hs.hotkey.bind, assignableMods, bindableKey, fn)
  if ok then
    return bindingOrErr
  end
  hs.printf("[tapshop-hotkeys] failed to bind %s: %s", tostring(bindableKey), tostring(bindingOrErr))
  return nil
end

local function isBindingAssigned(binding)
  return binding
    and binding.enabled ~= false
    and binding.key ~= false
    and binding.key ~= nil
    and binding.key ~= ""
end

function HotkeyManager.new(app, settings)
  local defaults = Registry.bindings()

  local defaultsById = {}
  for _, binding in ipairs(defaults) do
    defaultsById[binding.id] = cloneBinding(binding)
  end

  local self = setmetatable({
    app = app,
    settings = settings,
    defaults = defaults,
    defaultsById = defaultsById,
    liveHotkeys = {},
    liveSystemBindingsByCombo = {},
    liveRawSystemBindingsByCombo = {},
    systemEventTap = nil,
    rawSystemEventTap = nil,
    resolvedById = {},
    conflictsById = {},
    fallbackHotkey = nil,
    fallbackPresses = {},
    uiStateCache = nil,
    uiStateDirty = true,
    htmlCache = nil,
    htmlCacheDirty = true,
  }, HotkeyManager)

  self:resolve()
  return self
end

function HotkeyManager:_sanitizeOverrides(overrides)
  local source = type(overrides) == "table" and overrides or {}
  local sanitized = {}
  local changed = false

  for id, rawOverride in pairs(source) do
    local defaultBinding = self.defaultsById[id]
    if not defaultBinding then
      changed = true
    else
      local merged = cloneBinding(defaultBinding)

      if type(rawOverride) == "table" then
        if rawOverride.mods ~= nil then
          merged.mods = normalizeConflictMods(rawOverride.mods)
        end
        if rawOverride.key ~= nil then
          local normalizedKey = Normalize.normalizeKey(rawOverride.key)
          if normalizedKey ~= nil then
            merged.key = normalizedKey
          end
        end
        if rawOverride.enabled ~= nil then
          merged.enabled = rawOverride.enabled == true
          if rawOverride.enabled == false then
            merged.mods = {}
            merged.key = false
          end
        end
      else
        changed = true
      end

      local override = self:_buildOverride(merged)
      if override then
        sanitized[id] = override
      end
      if not Normalize.deepEqual(rawOverride, override) then
        changed = true
      end
    end
  end

  return sanitized, changed
end

function HotkeyManager:_loadOverrides()
  local overrides = self.settings.getHotkeyOverrides()
  local sanitized, changed = self:_sanitizeOverrides(overrides)
  if changed then
    self.settings.setHotkeyOverrides(sanitized)
  end
  return sanitized
end

function HotkeyManager:_saveOverrides(overrides)
  local sanitized = self:_sanitizeOverrides(overrides)
  self.settings.setHotkeyOverrides(sanitized)
end

function HotkeyManager:invalidateUiCache()
  self.uiStateCache = nil
  self.uiStateDirty = true
  self.htmlCache = nil
  self.htmlCacheDirty = true
end

function HotkeyManager:resolve()
  local overrides = self:_loadOverrides()
  self._lastOverrides = overrides
  local resolvedById = {}
  for _, defaultBinding in ipairs(self.defaults) do
    local merged = cloneBinding(defaultBinding)
    local override = overrides[defaultBinding.id]
    if override then
      if override.mods ~= nil then
        merged.mods = normalizeConflictMods(override.mods)
      end
      if override.key ~= nil then
        merged.key = override.key
      end
      if override.enabled ~= nil then
        merged.enabled = override.enabled == true
        if override.enabled == false then
          merged.mods = {}
          merged.key = false
        end
      end
    end
    resolvedById[merged.id] = merged
  end
  self.resolvedById = resolvedById
  self.conflictsById = detectConflicts(resolvedById)

  local popoverBinding = resolvedById[FALLBACK_BINDING_ID]
  if popoverBinding and not bindingUsesDefaultPopoverShortcut(popoverBinding) then
    local reservedCombo = normalizeConflictCombo(FALLBACK_MODS, FALLBACK_KEY)
    for id, binding in pairs(resolvedById) do
      if id ~= FALLBACK_BINDING_ID and isBindingAssigned(binding) and normalizeConflictCombo(binding.mods, binding.key) == reservedCombo then
        self.conflictsById[id] = self.conflictsById[id] or {}
        self.conflictsById[id][#self.conflictsById[id] + 1] = FALLBACK_BINDING_ID
        self.conflictsById[FALLBACK_BINDING_ID] = self.conflictsById[FALLBACK_BINDING_ID] or {}
        self.conflictsById[FALLBACK_BINDING_ID][#self.conflictsById[FALLBACK_BINDING_ID] + 1] = id
      end
    end
  end
end

function HotkeyManager:_dispatch(binding)
  if self.app and self.app._recordDebug then
    self.app:_recordDebug("hotkey", "info", "hotkey_dispatched", "hotkey dispatched", function()
      return {
        id = binding.id,
        action = binding.action,
        group = binding.group,
        label = binding.label,
      }
    end)
  end

  local method = self.app[binding.action]
  if type(method) ~= "function" then
    if self.app and self.app._recordDebug then
      self.app:_recordDebug("hotkey", "warn", "hotkey_dispatch_failed", "hotkey dispatch failed", function()
        return {
          id = binding.id,
          action = binding.action,
          reason = "unknown_action",
        }
      end, {
        decision = "unknown_action",
      })
    end
    hs.printf("[tapshop-hotkeys] unknown action %s for %s", tostring(binding.action), tostring(binding.id))
    return
  end
  method(self.app, table.unpack(binding.args or {}))
end

function HotkeyManager:_deleteBinding(id)
  local hotkey = self.liveHotkeys[id]
  if hotkey and hotkey.delete then
    hotkey:delete()
  end
  self.liveHotkeys[id] = nil
end

function HotkeyManager:_stopSystemBindings()
  if self.systemEventTap then
    self.systemEventTap:stop()
    self.systemEventTap = nil
  end
  if self.rawSystemEventTap then
    self.rawSystemEventTap:stop()
    self.rawSystemEventTap = nil
  end
  self.liveSystemBindingsByCombo = {}
  self.liveRawSystemBindingsByCombo = {}
end

function HotkeyManager:_startSystemBindingsIfNeeded()
  if next(self.liveSystemBindingsByCombo or {}) == nil and next(self.liveRawSystemBindingsByCombo or {}) == nil then
    self:_stopSystemBindings()
    return
  end

  if next(self.liveSystemBindingsByCombo or {}) ~= nil and not self.systemEventTap then
    self.systemEventTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(event)
      if not event or type(event.systemKey) ~= "function" then
        return false
      end

      local info = event:systemKey() or {}
      if not Normalize.isSystemKeyPress(info) then
        return false
      end
      local normalizedKey = Normalize.normalizeSystemKeyInfo(info)
      if not normalizedKey then
        return false
      end

      local combo = normalizeConflictCombo(modsFromFlags(eventFlags(event)), normalizedKey)
      local binding = self.liveSystemBindingsByCombo[combo]
      if not binding then
        return false
      end

      self:_dispatch(binding)
      return true
    end)
    self.systemEventTap:start()
  end

  if next(self.liveRawSystemBindingsByCombo or {}) ~= nil and not self.rawSystemEventTap then
    self.rawSystemEventTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
      if not event or type(event.getKeyCode) ~= "function" then
        return false
      end

      local keyCode = event:getKeyCode()
      if type(keyCode) ~= "number" or keyCode < 128 then
        return false
      end

      local normalizedKey = Normalize.normalizeRawKeyCode(keyCode)
      if not normalizedKey then
        return false
      end

      local combo = normalizeConflictCombo(modsFromFlags(eventFlags(event)), normalizedKey)
      local binding = self.liveRawSystemBindingsByCombo[combo]
      if not binding then
        return false
      end

      self:_dispatch(binding)
      return true
    end)
    self.rawSystemEventTap:start()
  end
end

function HotkeyManager:_deleteFallback()
  if self.fallbackHotkey and self.fallbackHotkey.delete then
    self.fallbackHotkey:delete()
  end
  self.fallbackHotkey = nil
  self.fallbackPresses = {}
end

function HotkeyManager:_bindFallbackIfNeeded()
  self:_deleteFallback()
  local binding = self.resolvedById[FALLBACK_BINDING_ID]
  if bindingUsesDefaultPopoverShortcut(binding) then
    return
  end

  local windowSeconds = FALLBACK_WINDOW_SECONDS
  self.fallbackHotkey = bindHotkeySafe(FALLBACK_MODS, FALLBACK_KEY, function()
    local now = hs.timer.secondsSinceEpoch()
    local presses = {}
    for _, ts in ipairs(self.fallbackPresses) do
      if (now - ts) <= windowSeconds then
        presses[#presses + 1] = ts
      end
    end
    presses[#presses + 1] = now
    self.fallbackPresses = presses
    if #presses >= 3 then
      self.fallbackPresses = {}
      if self.app and self.app.showPopover then
        self.app:showPopover()
      end
    end
  end)
end

-- (Re)bind all non-conflicting, assigned hotkeys from the resolved table.
function HotkeyManager:bindAll()
  self:unbindAll()
  self:resolve()

  for _, binding in ipairs(self.defaults) do
    local resolved = self.resolvedById[binding.id]
    if resolved and isBindingAssigned(resolved) and not self.conflictsById[resolved.id] then
      if isSystemKey(resolved.key) then
        local combo = normalizeConflictCombo(resolved.mods, resolved.key)
        if tostring(resolved.key):match("^SYSTEM_%d+$") then
          self.liveRawSystemBindingsByCombo[combo] = resolved
        else
          self.liveSystemBindingsByCombo[combo] = resolved
        end
        goto continue
      end
      if not keyIsAvailable(resolved.key) then
        goto continue
      end
      self.liveHotkeys[resolved.id] = bindHotkeySafe(resolved.mods, resolved.key, function()
        self:_dispatch(resolved)
      end)
    end
    ::continue::
  end

  self:_startSystemBindingsIfNeeded()
  self:_bindFallbackIfNeeded()
end

function HotkeyManager:unbindAll()
  for id, hotkey in pairs(self.liveHotkeys) do
    if hotkey and hotkey.delete then
      hotkey:delete()
    end
    self.liveHotkeys[id] = nil
  end
  self:_stopSystemBindings()
  self:_deleteFallback()
end

function HotkeyManager:_warningFor(binding)
  if not isBindingAssigned(binding) then
    return nil
  end
  local combo = normalizeConflictCombo(binding.mods, binding.key)
  if SYSTEM_SHORTCUTS[combo] then
    return "Likely reserved by macOS: " .. SYSTEM_SHORTCUTS[combo]
  end
  if not keyIsAvailable(binding.key) then
    return "Key is unavailable in the current keyboard layout."
  end
  return nil
end

function HotkeyManager:_buildUiRows()
  local overrides = self._lastOverrides or self:_loadOverrides()
  local rows = {}
  for _, defaultBinding in ipairs(self.defaults) do
    local binding = self.resolvedById[defaultBinding.id]
    local warning = self:_warningFor(binding)
    rows[#rows + 1] = {
      id = binding.id,
      group = binding.group,
      label = binding.label,
      mods = cloneArray(binding.mods),
      key = binding.key,
      isAssigned = isBindingAssigned(binding),
      enabled = binding.enabled == true,
      guarded = binding.guarded == true,
      isModified = overrides[binding.id] ~= nil,
      isUnavailable = isBindingAssigned(binding) and not keyIsAvailable(binding.key),
      conflictIds = cloneArray(self.conflictsById[binding.id]),
      warning = warning,
    }
  end
  return rows
end

function HotkeyManager:_buildUiState()
  self:resolve()
  local rows = self:_buildUiRows()
  return {
    rows = rows,
    conflictsById = self.conflictsById,
    overrides = self._lastOverrides or {},
    recordingSupported = true,
  }
end

function HotkeyManager:warmUiState()
  self:getUiState()
end

function HotkeyManager:getUiState()
  if self.uiStateDirty or not self.uiStateCache then
    self.uiStateCache = self:_buildUiState()
    self.uiStateDirty = false
  end
  return self.uiStateCache
end

function HotkeyManager:getHotkeyHtmlCached(rendererFn)
  if type(rendererFn) ~= "function" then
    return self.htmlCache
  end
  if self.htmlCacheDirty or not self.htmlCache then
    self.htmlCache = rendererFn(self:getUiState().rows or {})
    self.htmlCacheDirty = false
  end
  return self.htmlCache
end

function HotkeyManager:warmHtml(rendererFn)
  if type(rendererFn) == "function" then
    self:getHotkeyHtmlCached(rendererFn)
  else
    self:warmUiState()
  end
end

function HotkeyManager:_buildOverride(binding)
  local defaultBinding = self.defaultsById[binding.id]
  local override = {}
  local defaultCombo = normalizeConflictCombo(defaultBinding.mods, defaultBinding.key)
  local bindingCombo = normalizeConflictCombo(binding.mods, binding.key)

  if bindingCombo ~= defaultCombo then
    override.mods = binding.key == false and {} or cloneArray(binding.mods)
    override.key = binding.key
  end
  if binding.enabled ~= defaultBinding.enabled then
    override.enabled = binding.enabled == true
  end
  if next(override) == nil then
    return nil
  end
  return override
end

function HotkeyManager:_applyCandidate(candidateById)
  local popoverBinding = candidateById[FALLBACK_BINDING_ID]
  if not popoverBinding then
    return false, {
      code = "popover_required",
      ids = {
        [FALLBACK_BINDING_ID] = {},
      },
      message = "The popover shortcut is missing.",
    }
  end

  if not bindingUsesDefaultPopoverShortcut(popoverBinding) then
    local reservedCombo = normalizeConflictCombo(FALLBACK_MODS, FALLBACK_KEY)
    for id, binding in pairs(candidateById) do
      if id ~= FALLBACK_BINDING_ID and isBindingAssigned(binding) and normalizeConflictCombo(binding.mods, binding.key) == reservedCombo then
        return false, {
          code = "popover_fallback_reserved",
          ids = {
            [id] = { FALLBACK_BINDING_ID },
            [FALLBACK_BINDING_ID] = { id },
          },
          message = "Cmd+Option+` is reserved for the hidden popover recovery shortcut.",
        }
      end
    end
  end

  return true, nil
end

function HotkeyManager:updateBinding(id, payload)
  local current = self.resolvedById[id]
  local defaultBinding = self.defaultsById[id]
  if not current or not defaultBinding then
    return {
      ok = false,
      code = "missing_binding",
      ids = {
        [id] = {},
      },
      message = "Unknown hotkey binding.",
    }
  end

  local candidateById = {}
  for _, binding in ipairs(self.defaults) do
    candidateById[binding.id] = cloneBinding(self.resolvedById[binding.id])
  end

  local candidate = candidateById[id]
  if payload.mods ~= nil then
    candidate.mods = normalizeConflictMods(payload.mods)
  end
  if payload.key ~= nil then
    local normalizedKey = Normalize.normalizeKey(payload.key)
    if normalizedKey == nil then
      return {
        ok = false,
        code = "invalid_key",
        ids = {
          [id] = {},
        },
        message = "Shortcut key is invalid.",
      }
    end
    if normalizedKey ~= false and not keyIsAvailable(normalizedKey) then
      return {
        ok = false,
        code = "unavailable_key",
        ids = {
          [id] = {},
        },
        message = "Shortcut key is unavailable in the current keyboard layout.",
      }
    end
    candidate.key = normalizedKey
    if normalizedKey == false then
      candidate.mods = {}
      candidate.enabled = true
    end
  end
  if payload.enabled ~= nil then
    candidate.enabled = payload.enabled == true
  end

  if isBindingAssigned(candidate) then
    if not keyIsAvailable(candidate.key) then
      return {
        ok = false,
        code = "unavailable_key",
        ids = {
          [id] = {},
        },
        message = "Shortcut key is unavailable in the current keyboard layout.",
      }
    end

    local isAssignable, reason = comboIsAssignable(candidate.mods, candidate.key)
    if not isAssignable then
      return {
        ok = false,
        code = "unassignable_shortcut",
        ids = {
          [id] = {},
        },
        message = assignabilityWarning(candidate.mods, candidate.key, reason),
      }
    end
  end

  local ok, err = self:_applyCandidate(candidateById)
  if not ok then
    return {
      ok = false,
      code = err.code,
      ids = err.ids,
      message = err.message,
    }
  end

  local overrides = self:_loadOverrides()
  local override = self:_buildOverride(candidate)
  if override then
    overrides[id] = override
  else
    overrides[id] = nil
  end
  self:_saveOverrides(overrides)
  self:invalidateUiCache()
  self:bindAll()

  local conflictIds = cloneArray(self.conflictsById[id])
  local conflictMessage = nil
  if #conflictIds > 0 then
    conflictMessage = "Shortcut saved. Conflicting TAPSHOP hotkeys were disabled until resolved."
  end

  return {
    ok = true,
    warning = self:_warningFor(self.resolvedById[id]),
    conflictIds = conflictIds,
    message = conflictMessage,
  }
end

function HotkeyManager:resetBinding(id)
  if not self.defaultsById[id] then
    return {
      ok = false,
      code = "missing_binding",
      ids = {
        [tostring(id or "")] = {},
      },
      message = "Unknown hotkey binding.",
    }
  end

  local overrides = self:_loadOverrides()
  overrides[id] = nil
  self:_saveOverrides(overrides)
  self:invalidateUiCache()
  self:bindAll()
  return {
    ok = true,
  }
end

function HotkeyManager:resetAll()
  self.settings.resetHotkeyOverrides()
  self:invalidateUiCache()
  self:bindAll()
  return {
    ok = true,
  }
end

HotkeyManager._conflicts = {
  normalizeMods = normalizeConflictMods,
  normalizeCombo = normalizeConflictCombo,
  detect = detectConflicts,
}

return HotkeyManager
