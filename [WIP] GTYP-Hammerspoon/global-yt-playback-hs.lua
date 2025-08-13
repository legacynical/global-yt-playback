-- Port of AHK v2 script to Hammerspoon (macOS)
-- Hotkeys use "Hyper" = ctrl+alt+cmd by default

local hyper = { "ctrl", "alt", "cmd" }
local hyperShift = { "ctrl", "alt", "cmd", "shift" }

-- You can tweak these to your preference:
local keys = {
  -- YouTube controls (when a YouTube window/tab is open in a supported browser)
  yt = {
    rewind5 = { mods = hyper, key = "left" },
    rewind10 = { mods = hyperShift, key = "left" }, -- or change to "j"
    forward5 = { mods = hyper, key = "right" },
    forward10 = { mods = hyperShift, key = "right" }, -- or change to "l"
    playPause = { mods = hyper, key = "k" }, -- 'k' is YouTube's toggle
  },

  -- Spotify controls (via hs.spotify, no focus needed)
  sp = {
    prev = { mods = hyper, key = "," },
    playPause = { mods = hyper, key = "space" },
    next = { mods = hyper, key = "." },
    volDown = { mods = hyper, key = "down" }, -- Spotify volume (0..100)
    volUp = { mods = hyper, key = "up" },
    -- like/unlike is not officially in Spotify AppleScript; see note below
    -- like = { mods = hyper, key = "b" }, -- optional UI-scripting idea
  },

  -- System volume fallback (alt controls) - optional
  vol = {
    mute = { mods = hyperShift, key = "m" },
    down = { mods = hyperShift, key = "[" },
    up = { mods = hyperShift, key = "]" },
  },

  -- Workspaces (1..9): pair/toggle/minimize current window
  -- Unpair: add shift
  ws = {
    pairToggle = hyper,
    unpair = hyperShift,
    unpairAll = { mods = hyperShift, key = "0" },
  },

  -- Info popup for the active window
  info = { mods = hyper, key = "`" },

  -- Optional: open a chooser to assign any visible window to a workspace
  chooser = { mods = hyperShift, key = "g" },
}

-- ================ Utilities ================

local app = {
  workspaces = {},
  maxInputBuffer = 2,
  ytCacheWinId = nil,
  debug = false,
}

for i = 1, 9 do
  app.workspaces[i] = {
    id = nil,
    label = "Window " .. i,
    isPaired = false,
    pressBuffer = app.maxInputBuffer,
  }
end

local function log(...)
  if app.debug then
    print("[HS]", ...)
  end
end

local function frontmostWindow()
  return hs.window.frontmostWindow()
end

local function getWindowById(id)
  if not id then
    return nil
  end
  return hs.window.get(id)
end

local function isValidWindow(w)
  return w and w:isStandard() and w:isVisible()
end

local function appName(w)
  local a = w and w:application()
  return a and a:name() or "[Unknown]"
end

-- ================ Active window info ================

local function showActiveWindowInfo()
  local w = frontmostWindow()
  if not isValidWindow(w) then
    hs.alert.show("No active window")
    return
  end
  local title = w:title() or ""
  local id = w:id() or 0
  local bundleID = (w:application() and w:application():bundleID())
    or "[Unknown]"
  local appNameStr = appName(w)

  hs.alert.show(
    "Active window:\n"
      .. "Title: "
      .. title
      .. "\n"
      .. "App: "
      .. appNameStr
      .. "\n"
      .. "Bundle ID: "
      .. bundleID
      .. "\n"
      .. "Window ID: "
      .. tostring(id)
  )
end

-- ================ YouTube control ================

local youtubeApps = {
  ["Google Chrome"] = true,
  ["Google Chrome Canary"] = true,
  ["Chromium"] = true,
  ["Brave Browser"] = true,
  ["Microsoft Edge"] = true,
  ["Vivaldi"] = true,
  ["Opera"] = true,
  ["Opera GX"] = true,
  ["Firefox"] = true,
  ["Waterfox"] = true,
  ["Safari"] = true,
  ["Safari Technology Preview"] = true,
  ["Arc"] = true,
}

local function findYouTubeWindow()
  -- Reuse cached window if still valid
  if app.ytCacheWinId then
    local cached = getWindowById(app.ytCacheWinId)
    if isValidWindow(cached) then
      local t = cached:title() or ""
      local name = appName(cached)
      if t:find("YouTube") and youtubeApps[name] then
        return cached
      end
    end
  end

  -- Search for a visible window with "YouTube" in title from supported apps
  local wins = hs.window.allWindows()
  for _, w in ipairs(wins) do
    if isValidWindow(w) then
      local t = w:title() or ""
      if t:find("YouTube") and youtubeApps[appName(w)] then
        app.ytCacheWinId = w:id()
        return w
      end
    end
  end

  return nil
end

local function doWithWindowActivated(targetWin, fn)
  local lastWin = frontmostWindow()
  local lastApp = lastWin and lastWin:application()

  if targetWin then
    local a = targetWin:application()
    if a then
      a:activate(true)
    end
    targetWin:raise()
    targetWin:focus()
  end

  hs.timer.doAfter(0.02, function()
    pcall(fn)
    hs.timer.doAfter(0.02, function()
      if lastApp then
        lastApp:activate(true)
      end
      if lastWin and lastWin:isVisible() then
        lastWin:raise()
        lastWin:focus()
      end
    end)
  end)
end

local function ytSendKey(mods, key)
  local w = findYouTubeWindow()
  if not w then
    hs.alert.show("No YouTube window found")
    return
  end
  doWithWindowActivated(w, function()
    -- If key is a single character like 'k', send keystrokes; otherwise keyStroke
    if #key == 1 and not (key == "left" or key == "right" or key == "up" or key
      == "down")
    then
      hs.eventtap.keyStrokes(key)
    else
      hs.eventtap.keyStroke(mods or {}, key, 0)
    end
  end)
end

-- ================ Spotify control ================

local function spPlayPause()
  hs.spotify.playpause()
end

local function spNext()
  hs.spotify.next()
end

local function spPrev()
  hs.spotify.previous()
end

local function spVol(delta)
  local v = hs.spotify.getVolume() or 50
  local nv = math.max(0, math.min(100, v + delta))
  hs.spotify.setVolume(nv)
  hs.alert.show("Spotify volume: " .. nv)
end

-- NOTE: Like/Unlike is not exposed in Spotify's AppleScript API.
-- If you really want it, you can UI-script the heart button when Spotify
-- is frontmost. That approach is brittle and depends on UI structure.

-- ================ System volume (optional) ================

local function sysMuteToggle()
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    local newMuted = not dev:muted()
    dev:setMuted(newMuted)
    hs.alert.show(newMuted and "Muted" or "Unmuted")
  end
end

local function sysVol(delta)
  local dev = hs.audiodevice.defaultOutputDevice()
  if not dev then
    return
  end
  local vol = dev:volume() or 50
  local nv = math.max(0, math.min(100, vol + delta))
  dev:setVolume(nv)
  hs.alert.show("Volume: " .. math.floor(nv))
end

-- ================ Workspaces (pair/toggle/minimize) ================

local function getWorkspace(i)
  return app.workspaces[i]
end

local function currentWindowInfo()
  local w = frontmostWindow()
  if not isValidWindow(w) then
    return nil
  end
  return {
    id = w:id(),
    title = w:title() or "",
    app = appName(w),
    ref = w,
  }
end

local function activateWindowById(id)
  local w = getWindowById(id)
  if not isValidWindow(w) then
    return false
  end
  local a = w:application()
  if a then
    a:activate(true)
  end
  w:raise()
  w:focus()
  return true
end

local function pairOrToggleWorkspace(i)
  local ws = getWorkspace(i)
  local winInfo = currentWindowInfo()
  if not winInfo then
    hs.alert.show("No active window to pair")
    return
  end

  local currentID = winInfo.id

  if not ws.id then
    -- Pair current window
    ws.id = currentID
    ws.isPaired = true
    ws.pressBuffer = app.maxInputBuffer
    hs.alert.show(
      ("[Paired %s]\n[%s] %s"):format(ws.label, winInfo.app, winInfo.title)
    )
    return
  end

  if ws.id ~= currentID then
    -- Switch to paired window
    if activateWindowById(ws.id) then
      ws.pressBuffer = app.maxInputBuffer
    else
      -- Paired window no longer exists, clear it
      ws.id = nil
      ws.isPaired = false
      hs.alert.show("[Cleared stale pairing: " .. ws.label .. "]")
    end
    return
  end

  -- Already in the paired window: decrement buffer and minimize when <= 0
  ws.pressBuffer = ws.pressBuffer - 1
  if ws.pressBuffer <= 0 then
    ws.pressBuffer = app.maxInputBuffer
    local w = getWindowById(ws.id)
    if isValidWindow(w) then
      w:minimize()
    end
  end
end

local function unpairWorkspace(i)
  local ws = getWorkspace(i)
  if ws.id then
    ws.id = nil
    ws.isPaired = false
    ws.pressBuffer = app.maxInputBuffer
    hs.alert.show("[Unpaired " .. ws.label .. "]")
  else
    hs.alert.show(ws.label .. " is already unpaired")
  end
end

local function unpairAllWorkspaces()
  hs.dialog.blockAlert(
    "Unpair All",
    "Are you sure you want to unpair all windows?",
    "Yes",
    "No",
    "NSCriticalAlertStyle"
  )
  for i = 1, 9 do
    local ws = getWorkspace(i)
    ws.id = nil
    ws.isPaired = false
    ws.pressBuffer = app.maxInputBuffer
  end
  hs.alert.show("[Unpaired All Windows]")
end

-- Optional: chooser to assign any visible window to a workspace
local function visibleWindowsList()
  local wins = hs.window.allWindows()
  local items = {}
  for _, w in ipairs(wins) do
    if isValidWindow(w) then
      table.insert(items, {
        text = string.format("[%s] %s", appName(w), w:title() or ""),
        subText = "ID: " .. tostring(w:id()),
        winId = w:id(),
      })
    end
  end
  return items
end

local function assignWorkspaceViaChooser(wsIndex)
  local chooser = hs.chooser.new(function(choice)
    if not choice then
      return
    end
    local ws = getWorkspace(wsIndex)
    ws.id = choice.winId
    ws.isPaired = true
    ws.pressBuffer = app.maxInputBuffer
    hs.alert.show(
      ("[Paired %s]\n%s"):format(ws.label, choice.text or "Unknown")
    )
  end)

  chooser:placeholderText("Select a window for " .. getWorkspace(wsIndex).label)
  chooser:choices(visibleWindowsList())
  chooser:show()
end

-- ================ Key bindings ================

local function bind(mods, key, fn)
  hs.hotkey.bind(mods, key, fn)
end

-- YouTube bindings
bind(keys.yt.rewind5.mods, keys.yt.rewind5.key, function()
  ytSendKey({}, "left")
end)

bind(keys.yt.rewind10.mods, keys.yt.rewind10.key, function()
  -- YouTube 10s rewind is 'j'
  ytSendKey({}, "j")
end)

bind(keys.yt.forward5.mods, keys.yt.forward5.key, function()
  ytSendKey({}, "right")
end)

bind(keys.yt.forward10.mods, keys.yt.forward10.key, function()
  -- YouTube 10s forward is 'l'
  ytSendKey({}, "l")
end)

bind(keys.yt.playPause.mods, keys.yt.playPause.key, function()
  ytSendKey({}, "k")
end)

-- Spotify bindings
bind(keys.sp.prev.mods, keys.sp.prev.key, spPrev)
bind(keys.sp.playPause.mods, keys.sp.playPause.key, spPlayPause)
bind(keys.sp.next.mods, keys.sp.next.key, spNext)
bind(keys.sp.volDown.mods, keys.sp.volDown.key, function()
  spVol(-5)
end)
bind(keys.sp.volUp.mods, keys.sp.volUp.key, function()
  spVol(5)
end)

-- System volume (optional)
bind(keys.vol.mute.mods, keys.vol.mute.key, sysMuteToggle)
bind(keys.vol.down.mods, keys.vol.down.key, function()
  sysVol(-5)
end)
bind(keys.vol.up.mods, keys.vol.up.key, function()
  sysVol(5)
end)

-- Workspaces: pair/toggle/minimize
for i = 1, 9 do
  bind(keys.ws.pairToggle, tostring(i), function()
    pairOrToggleWorkspace(i)
  end)
  bind(keys.ws.unpair, tostring(i), function()
    unpairWorkspace(i)
  end)
  -- Optional: assign via chooser with Hyper+Shift+G then number?
  -- Or bind Hyper+Shift+[1..9] to chooser:
  hs.hotkey.bind(hyperShift, tostring(i), function()
    assignWorkspaceViaChooser(i)
  end)
end

-- Unpair all
bind(keys.ws.unpairAll.mods, keys.ws.unpairAll.key, unpairAllWorkspaces)

-- Active window info
bind(keys.info.mods, keys.info.key, showActiveWindowInfo)

-- Optional unified chooser (Hyper+Shift+G) to pick which workspace to assign
bind(keys.chooser.mods, keys.chooser.key, function()
  local choices = {}
  for i = 1, 9 do
    table.insert(choices, {
      text = "Assign " .. getWorkspace(i).label,
      subText = "Open window chooser for this slot",
      wsIndex = i,
    })
  end
  local c = hs.chooser.new(function(choice)
    if not choice then
      return
    end
    assignWorkspaceViaChooser(choice.wsIndex)
  end)
  c:placeholderText("Pick a workspace slot to assign")
  c:choices(choices)
  c:show()
end)

hs.alert.show("Hammerspoon config loaded")