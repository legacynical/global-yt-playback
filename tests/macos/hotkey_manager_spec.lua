local Assert = require("assert")
local TestEnv = require("test_env")

local settingsState = {}
local boundHotkeys = {}
local deletedHotkeys = {}
local createdEventTaps = {}
local liveModifierState = {}
local secondsNow = 100
local assignableCalls = 0

local function installHsStubs()
  _G.hs = {
    keycodes = {
      map = {
        ["`"] = 50,
        left = 123,
        right = 124,
        j = 38,
        l = 37,
        k = 40,
        ["0"] = 29,
        ["1"] = 18,
        ["2"] = 19,
        ["3"] = 20,
        ["4"] = 21,
        ["5"] = 23,
        ["6"] = 22,
        ["7"] = 26,
        ["8"] = 28,
        ["9"] = 25,
        [","] = 43,
        ["."] = 47,
        m = 46,
        space = 49,
        F7 = 98,
        F8 = 100,
        F9 = 101,
        p = 35,
      },
    },
    hotkey = {
      assignable = function()
        assignableCalls = assignableCalls + 1
        return true
      end,
      bind = function(mods, key, fn)
        local binding = {
          mods = mods,
          key = key,
          fn = fn,
        }
        function binding:delete()
          deletedHotkeys[#deletedHotkeys + 1] = self.key
        end
        boundHotkeys[#boundHotkeys + 1] = binding
        return binding
      end,
    },
    eventtap = {
      event = {
        types = {
          keyDown = "keyDown",
          systemDefined = "systemDefined",
        },
      },
      new = function(types, fn)
        local tap = {
          types = types,
          fn = fn,
          started = false,
        }
        function tap:start()
          self.started = true
          return self
        end
        function tap:stop()
          self.started = false
          return self
        end
        createdEventTaps[#createdEventTaps + 1] = tap
        return tap
      end,
      checkKeyboardModifiers = function()
        local copy = {}
        for key, value in pairs(liveModifierState) do
          copy[key] = value
        end
        return copy
      end,
    },
    timer = {
      secondsSinceEpoch = function()
        return secondsNow
      end,
    },
    printf = function() end,
  }
end

local unpack = table.unpack or unpack

local settings = {
  getHotkeyOverrides = function()
    return settingsState.overrides or {}
  end,
  setHotkeyOverrides = function(overrides)
    local copy = {}
    for id, value in pairs(overrides) do
      copy[id] = {
        mods = value.mods and { unpack(value.mods) } or nil,
        key = value.key,
        enabled = value.enabled,
      }
    end
    settingsState.overrides = copy
  end,
  resetHotkeyOverrides = function()
    settingsState.overrides = nil
  end,
}

local appCalls = {}
local app = {
  togglePopover = function(self)
    appCalls[#appCalls + 1] = "togglePopover"
  end,
  showPopover = function(self)
    appCalls[#appCalls + 1] = "showPopover"
  end,
  sendYoutubeCommand = function(self, arg)
    appCalls[#appCalls + 1] = "youtube:" .. tostring(arg)
  end,
  activateSlot = function(self, slot)
    appCalls[#appCalls + 1] = "activate:" .. tostring(slot)
  end,
  activateProfile = function(self, profile)
    appCalls[#appCalls + 1] = "profile:" .. tostring(profile)
  end,
  unpairSlot = function(self, slot)
    appCalls[#appCalls + 1] = "unpair:" .. tostring(slot)
  end,
  unpairAll = function(self)
    appCalls[#appCalls + 1] = "unpairAll"
  end,
  spotifyPrevious = function() end,
  spotifyPlayPause = function() end,
  spotifyNext = function() end,
  spotifySeekBack = function() end,
  spotifySeekForward = function() end,
  spotifyToggleLike = function() end,
  spotifyVolumeDown = function() end,
  spotifyVolumeUp = function() end,
  adjustSystemVolume = function() end,
  toggleSystemMute = function() end,
}

local function assertEq(actual, expected, message)
  Assert.equal(actual, expected, message)
end

local function assertTrue(value, message)
  Assert.truthy(value, message)
end

local function assertFalse(value, message)
  Assert.falsy(value, message)
end

local function resetState()
  settingsState = {}
  boundHotkeys = {}
  deletedHotkeys = {}
  createdEventTaps = {}
  liveModifierState = {}
  appCalls = {}
  secondsNow = 100
  assignableCalls = 0
  installHsStubs()
end

local function makeSystemEvent(key, flags)
  return {
    getType = function()
      return hs.eventtap.event.types.systemDefined
    end,
    getFlags = function()
      return flags or {}
    end,
    systemKey = function()
      return {
        key = key,
        down = true,
      }
    end,
  }
end


return {
  name = "HotkeyManager",
  cases = {
    {
      name = "binds, remaps, fallbacks, and sanitizes overrides",
      run = function()
        resetState()
        TestEnv.reset({
          "hotkeys.manager",
          "hotkeys.registry",
        })
        -- TestEnv.reset reinstalls FakeHs; restore HotkeyManager stubs.
        installHsStubs()
        local HotkeyManager = require("hotkeys.manager")

        local manager = HotkeyManager.new(app, settings)
        manager:bindAll()
        assertEq(assignableCalls, 0, "startup binding should not run assignability preflight")

        local warmedUi = manager:getUiState()
        local cachedUi = manager:getUiState()
        assertTrue(warmedUi == cachedUi, "hotkey UI state should be cached between reads")
        local warmedHtml = manager:getHotkeyHtmlCached(function(rows)
            return "rows:" .. tostring(#rows)
        end)
        local cachedHtml = manager:getHotkeyHtmlCached(function()
            return "should-not-run"
        end)
        assertEq(warmedHtml, "rows:" .. tostring(#warmedUi.rows), "html warm should render from cached ui rows")
        assertEq(cachedHtml, warmedHtml, "hotkey html fragment should be cached")

        assertTrue(manager.fallbackHotkey == nil, "fallback should not bind while default popover shortcut is active")

        local ui = manager:getUiState()
        assertTrue(#ui.rows > 0, "ui rows should be present")
        local unavailable = false
        for _, row in ipairs(ui.rows) do
            if row.id == "youtube.seekBack.f19" then
              unavailable = row.isUnavailable
            end
        end
        assertTrue(unavailable, "missing guarded function key should surface unavailable state")

        local conflictResult = manager:updateBinding("youtube.playPause.k", {
            mods = { "cmd", "alt" },
            key = "j",
        })
        assertEq(conflictResult.ok, true, "conflicting remap should persist and mark the conflict")
        assertTrue(#(conflictResult.conflictIds or {}) > 0, "conflicting remap should report affected bindings")

        local invalidResult = manager:updateBinding("youtube.playPause.k", {
            key = "",
        })
        assertEq(invalidResult.ok, false, "invalid key should be rejected")
        assertEq(invalidResult.code, "invalid_key", "invalid key should return dedicated code")

        local unavailableResult = manager:updateBinding("youtube.playPause.k", {
            key = "º",
        })
        assertEq(unavailableResult.ok, false, "layout-unavailable key should be rejected")
        assertEq(unavailableResult.code, "unavailable_key", "unavailable key should return dedicated code")

        local remapToSpotlight = manager:updateBinding("youtube.playPause.k", {
            mods = { "cmd" },
            key = "space",
        })
        assertEq(remapToSpotlight.ok, true, "reserved macOS combos should warn but remain configurable")
        assertTrue(
            string.find(remapToSpotlight.warning or "", "Spotlight", 1, true) ~= nil,
            "reserved combo warning should mention the system shortcut"
        )

        local remapPlayable = manager:updateBinding("youtube.playPause.k", {
            mods = { "cmd", "alt" },
            key = "p",
        })
        assertEq(remapPlayable.ok, true, "valid remap should succeed")
        local postRemapUi = manager:getUiState()
        assertFalse(postRemapUi == warmedUi, "hotkey ui cache should invalidate after remap")
        local newBinding = nil
        for _, binding in ipairs(boundHotkeys) do
            if binding.key == "p" then
              newBinding = binding
            end
        end
        assertTrue(newBinding ~= nil, "new hotkey binding should be registered")
        newBinding.fn()
        assertEq(appCalls[#appCalls], "youtube:k", "newly bound hotkey should dispatch the mapped action")
        assertTrue(#deletedHotkeys > 0, "rebinding should delete previously bound hotkeys")

        local resetOne = manager:resetBinding("youtube.playPause.k")
        assertEq(resetOne.ok, true, "single reset should succeed")
        local resetRow = nil
        for _, row in ipairs(manager:getUiState().rows) do
            if row.id == "youtube.playPause.k" then
              resetRow = row
            end
        end
        assertTrue(resetRow ~= nil, "reset row should still exist")
        assertEq(resetRow.key, "k", "single reset should restore the default key")
        assertFalse(resetRow.isModified, "single reset should clear the override marker")

        local clearYoutube = manager:updateBinding("youtube.playPause.k", {
            mods = {},
            key = false,
        })
        assertEq(clearYoutube.ok, true, "non-popover binding should be clearable")
        local clearedRow = nil
        for _, row in ipairs(manager:getUiState().rows) do
            if row.id == "youtube.playPause.k" then
              clearedRow = row
            end
        end
        assertTrue(clearedRow ~= nil, "cleared row should still be present")
        assertEq(clearedRow.isAssigned, false, "cleared row should be unassigned")

        local remapPopover = manager:updateBinding("popover.toggle", {
            mods = { "cmd", "alt" },
            key = "p",
        })
        assertEq(remapPopover.ok, true, "popover remap should succeed")
        assertTrue(settingsState.overrides["popover.toggle"] ~= nil, "override should persist")

        local reserveDefault = manager:updateBinding("youtube.playPause.k", {
            mods = { "cmd", "alt" },
            key = "`",
        })
        assertEq(reserveDefault.ok, false, "default popover combo should be reserved after remap")
        assertEq(reserveDefault.code, "popover_fallback_reserved", "fallback reservation should be enforced")

        local clearPopover = manager:updateBinding("popover.toggle", {
            mods = {},
            key = false,
        })
        assertEq(clearPopover.ok, true, "popover binding may be blank because fallback remains")
        assertTrue(manager.fallbackHotkey ~= nil, "fallback should remain active when popover row is blank")

        manager.fallbackHotkey.fn()
        secondsNow = secondsNow + 1.2
        manager.fallbackHotkey.fn()
        secondsNow = secondsNow + 0.2
        manager.fallbackHotkey.fn()
        assertFalse(appCalls[#appCalls] == "showPopover", "stale fallback presses should expire outside the time window")

        secondsNow = secondsNow + 0.2
        manager.fallbackHotkey.fn()
        secondsNow = secondsNow + 0.2
        manager.fallbackHotkey.fn()
        assertEq(appCalls[#appCalls], "showPopover", "fallback triple-press should show popover")

        local resetResult = manager:resetAll()
        assertEq(resetResult.ok, true, "reset all should succeed")
        assertTrue(settingsState.overrides == nil, "reset all should clear overrides")

        local profileRemap = manager:updateBinding("profiles.activate.1", {
            mods = { "cmd", "alt" },
            key = "BRIGHTNESS_DOWN",
        })
        assertEq(profileRemap.ok, true, "default-unbound profile bindings should be assignable")
        assertTrue(settingsState.overrides["profiles.activate.1"] ~= nil, "profile remap should persist as an override")
        assertEq(settingsState.overrides["profiles.activate.1"].key, "BRIGHTNESS_DOWN", "profile override should store the new system key")
        assertTrue(manager.systemEventTap ~= nil, "system-defined bindings should start an event tap")

        liveModifierState = { cmd = true, alt = true }
        local handledSystemEvent = manager.systemEventTap.fn(makeSystemEvent("BRIGHTNESS_DOWN", {}))
        assertEq(handledSystemEvent, true, "system-key dispatch should use live modifier state when event flags are empty")
        assertEq(appCalls[#appCalls], "profile:1", "system-key dispatch should trigger the remapped profile action")

        local resetProfile = manager:resetBinding("profiles.activate.1")
        assertEq(resetProfile.ok, true, "resetting a profile binding should succeed")
        assertTrue(settingsState.overrides["profiles.activate.1"] == nil, "reset should clear the profile override")
        local profileRow = nil
        for _, row in ipairs(manager:getUiState().rows) do
            if row.id == "profiles.activate.1" then
              profileRow = row
              break
            end
        end
        assertTrue(profileRow ~= nil, "profile row should still exist after reset")
        assertFalse(profileRow.isModified, "reset should clear the modified state for default-unbound profiles")
        assertFalse(profileRow.isAssigned, "default-unbound profile should render as unassigned after reset")

        resetState()
        settingsState.overrides = {
            ["youtube.playPause.k"] = {
              enabled = false,
            },
            ["popover.toggle"] = {
              mods = { "cmd", "alt" },
              key = "º",
            },
        }
        local legacyManager = HotkeyManager.new(app, settings)
        local legacyRow = nil
        local brokenPopoverRow = nil
        for _, row in ipairs(legacyManager:getUiState().rows) do
            if row.id == "youtube.playPause.k" then
              legacyRow = row
            elseif row.id == "popover.toggle" then
              brokenPopoverRow = row
            end
        end
        assertTrue(legacyRow ~= nil, "legacy override row should still resolve")
        assertFalse(legacyRow.isAssigned, "legacy enabled=false overrides should load as unassigned")
        assertTrue(brokenPopoverRow ~= nil, "persisted invalid-layout row should still resolve")
        assertTrue(brokenPopoverRow.isUnavailable, "persisted invalid-layout row should be surfaced as unavailable")
        legacyManager:bindAll()
        assertTrue(legacyManager.fallbackHotkey ~= nil, "fallback should still bind when persisted popover shortcut is unavailable")

        resetState()
        settingsState.overrides = {
            ["profiles.activate.1"] = {
              mods = {},
              key = false,
            },
            ["missing.binding"] = {
              mods = { "cmd", "alt" },
              key = "p",
            },
        }
        local sanitizedManager = HotkeyManager.new(app, settings)
        local sanitizedOverrides = settingsState.overrides or {}
        assertTrue(next(sanitizedOverrides) == nil, "default-equivalent and unknown overrides should be stripped during load")

        local sanitizedProfileRow = nil
        for _, row in ipairs(sanitizedManager:getUiState().rows) do
            if row.id == "profiles.activate.1" then
              sanitizedProfileRow = row
              break
            end
        end
        assertTrue(sanitizedProfileRow ~= nil, "sanitized profile row should still resolve")
        assertFalse(sanitizedProfileRow.isModified, "sanitized default-unbound profiles should not appear modified")
        assertFalse(sanitizedProfileRow.isAssigned, "sanitized default-unbound profiles should remain unassigned")
      end,
    },
  },
}
