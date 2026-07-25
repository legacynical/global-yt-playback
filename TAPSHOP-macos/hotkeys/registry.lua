-- Hotkey registry: default binding table (id, mods, key, AppState action, args).
-- Overrides live in appdata; HotkeyManager merges them at resolve time.

local Registry = {}
local Layout = require("state.layout")

local function buildBindings()
  local bindings = {}

  for i = 1, Layout.MAX_PROFILES do
    bindings[#bindings + 1] = {
      id = "profiles.activate." .. tostring(i),
      group = "Profiles",
      label = "Switch to Profile " .. tostring(i),
      mods = {},
      key = false,
      action = "activateProfile",
      args = { i },
      guarded = true,
      enabled = true,
    }
  end

  bindings[#bindings + 1] = {
    id = "profiles.previousNonEmpty",
    group = "Profiles",
    label = "Previous Non-Empty Profile",
    mods = { "cmd", "alt" },
    key = "up",
    action = "activatePreviousNonEmptyProfile",
    args = {},
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "profiles.nextNonEmpty",
    group = "Profiles",
    label = "Next Non-Empty Profile",
    mods = { "cmd", "alt" },
    key = "down",
    action = "activateNextNonEmptyProfile",
    args = {},
    guarded = true,
    enabled = true,
  }

  for i = 1, Layout.SLOTS_PER_PROFILE do
    bindings[#bindings + 1] = {
      id = "slots.activate." .. tostring(i),
      group = "Window Slots",
      label = "Pair/Toggle Slot " .. tostring(i),
      mods = { "cmd", "alt" },
      key = tostring(i),
      action = "activateSlot",
      args = { i },
      guarded = false,
      enabled = true,
    }
  end

  for i = 1, Layout.SLOTS_PER_PROFILE do
    bindings[#bindings + 1] = {
      id = "slots.unpair." .. tostring(i),
      group = "Window Slots",
      label = "Unpair Slot " .. tostring(i),
      mods = { "cmd", "alt", "shift" },
      key = tostring(i),
      action = "unpairSlot",
      args = { i },
      guarded = false,
      enabled = true,
    }
  end

  bindings[#bindings + 1] = {
    id = "slots.unpairAll",
    group = "Window Slots",
    label = "Unpair All Slots",
    mods = { "cmd", "alt", "shift" },
    key = "0",
    action = "unpairAll",
    args = {},
    guarded = false,
    enabled = true,
  }

  bindings[#bindings + 1] = {
    id = "popover.toggle",
    group = "UI",
    label = "Toggle Popover",
    mods = { "cmd", "alt" },
    key = "`",
    action = "togglePopover",
    args = {},
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekBack.arrow",
    group = "YouTube",
    label = "Seek Back 5s",
    mods = { "cmd", "alt" },
    key = "left",
    action = "sendYoutubeCommand",
    args = { "{Left}" },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekForward.arrow",
    group = "YouTube",
    label = "Seek Forward 5s",
    mods = { "cmd", "alt" },
    key = "right",
    action = "sendYoutubeCommand",
    args = { "{Right}" },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekBack.j",
    group = "YouTube",
    label = "Seek Back 10s",
    mods = { "cmd", "alt" },
    key = "j",
    action = "sendYoutubeCommand",
    args = { "j" },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekForward.l",
    group = "YouTube",
    label = "Seek Forward 10s",
    mods = { "cmd", "alt" },
    key = "l",
    action = "sendYoutubeCommand",
    args = { "l" },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.playPause.k",
    group = "YouTube",
    label = "Play or Pause",
    mods = { "cmd", "alt" },
    key = "k",
    action = "sendYoutubeCommand",
    args = { "k" },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekBack.f19",
    group = "YouTube",
    label = "Seek Back 5s (F19)",
    mods = {},
    key = "F19",
    action = "sendYoutubeCommand",
    args = { "{Left}" },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekBack.ctrlF19",
    group = "YouTube",
    label = "Seek Back 10s (Ctrl+F19)",
    mods = { "ctrl" },
    key = "F19",
    action = "sendYoutubeCommand",
    args = { "j" },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekForward.f21",
    group = "YouTube",
    label = "Seek Forward 5s (F21)",
    mods = {},
    key = "F21",
    action = "sendYoutubeCommand",
    args = { "{Right}" },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.seekForward.ctrlF21",
    group = "YouTube",
    label = "Seek Forward 10s (Ctrl+F21)",
    mods = { "ctrl" },
    key = "F21",
    action = "sendYoutubeCommand",
    args = { "l" },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "youtube.playPause.f20",
    group = "YouTube",
    label = "Play or Pause (F20)",
    mods = {},
    key = "F20",
    action = "sendYoutubeCommand",
    args = { "k" },
    guarded = true,
    enabled = true,
  }

  bindings[#bindings + 1] = {
    id = "spotify.previous",
    group = "Spotify",
    label = "Previous Track",
    mods = {},
    key = "F7",
    action = "spotifyPrevious",
    args = {},
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.playPause",
    group = "Spotify",
    label = "Play or Pause",
    mods = {},
    key = "F8",
    action = "spotifyPlayPause",
    args = {},
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.next",
    group = "Spotify",
    label = "Next Track",
    mods = {},
    key = "F9",
    action = "spotifyNext",
    args = {},
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.seekBack",
    group = "Spotify",
    label = "Seek Back 5s",
    mods = { "ctrl" },
    key = "F7",
    action = "spotifySeekBack",
    args = { 5 },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.seekForward",
    group = "Spotify",
    label = "Seek Forward 5s",
    mods = { "ctrl" },
    key = "F9",
    action = "spotifySeekForward",
    args = { 5 },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.like",
    group = "Spotify",
    label = "Toggle Like",
    mods = {},
    key = "F22",
    action = "spotifyToggleLike",
    args = {},
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.volumeDown",
    group = "Spotify",
    label = "Spotify Volume Down",
    mods = {},
    key = "F23",
    action = "spotifyVolumeDown",
    args = { 6 },
    guarded = true,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "spotify.volumeUp",
    group = "Spotify",
    label = "Spotify Volume Up",
    mods = {},
    key = "F24",
    action = "spotifyVolumeUp",
    args = { 6 },
    guarded = true,
    enabled = true,
  }

  bindings[#bindings + 1] = {
    id = "system.volumeDown",
    group = "System Volume",
    label = "Volume Down",
    mods = { "cmd", "alt", "ctrl" },
    key = ",",
    action = "adjustSystemVolume",
    args = { -5 },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "system.volumeUp",
    group = "System Volume",
    label = "Volume Up",
    mods = { "cmd", "alt", "ctrl" },
    key = ".",
    action = "adjustSystemVolume",
    args = { 5 },
    guarded = false,
    enabled = true,
  }
  bindings[#bindings + 1] = {
    id = "system.mute",
    group = "System Volume",
    label = "Toggle Mute",
    mods = { "cmd", "alt", "ctrl" },
    key = "m",
    action = "toggleSystemMute",
    args = {},
    guarded = false,
    enabled = true,
  }

  return bindings
end

local cachedBindings = buildBindings()

function Registry.bindings()
  return cachedBindings
end

return Registry
