-- TAPSHOP (Hammerspoon port of your AHK script)
-- Requires: Accessibility permissions enabled for Hammerspoon

local Config = {
  inputDelay = 0.05, -- seconds; AHK had 50 ms
  minimizeThreshold = 2,
  isGuiDebugMode = false,
  isHotkeyDebugMode = false,
  cursorMsgBottomMargin = 100, -- lift above bottom of visible screen area
  browserBundleIDs = {
    ["com.apple.Safari"] = true,
    ["com.google.Chrome"] = true,
    ["org.chromium.Chromium"] = true,
    ["com.brave.Browser"] = true,
    ["com.operasoftware.Opera"] = true,
    ["com.vivaldi.Vivaldi"] = true,
    ["org.mozilla.firefox"] = true,
    ["com.microsoft.edgemac"] = true,
    ["ru.yandex.desktop.yandex-browser"] = true,
    ["org.waterfoxproject.waterfox"] = true,
    ["org.torproject.torbrowser"] = true,
  },
}

-- --------- Safe hotkey bind (skips missing keys like F21/F22/F23/F24) ---------
local function bindIfAvailable(mods, key, fn)
  local map = hs.keycodes.map
  local kLower = string.lower(key)
  if map[key] or map[kLower] then
    hs.hotkey.bind(mods, key, fn)
  else
    hs.printf(
      "Skipping hotkey: %s + %s (key not in keymap)",
      table.concat(mods, "+"),
      key
    )
  end
end

-- ------------- CursorMsg: stacked transient alert near bottom center -------------
-- Places alert at bottom-center of the screen under the mouse, lifted above Dock/menubar
CursorMsg = (function()
  local lines = {}
  local timer = nil
  local maxLines = 25
  local alertId = nil

  local function bottomMargin()
    return (Config and Config.cursorMsgBottomMargin) or 100
  end

  local function pickScreen()
    return hs.mouse.getCurrentScreen()
      or (hs.window.frontmostWindow() and hs.window.frontmostWindow():screen())
      or hs.screen.mainScreen()
  end

  local function alertPos()
    local scr = pickScreen()
    local vf = scr:frame() -- visible frame
    local x = vf.x + vf.w / 2
    local y = vf.y + vf.h - bottomMargin()
    return { x = x, y = y }
  end

  local function show(secs)
    local buf = {}
    for i = 1, #lines do
      local prefix = (i == #lines) and "> " or "  "
      buf[#buf + 1] = prefix .. tostring(lines[i])
    end
    local text = table.concat(buf, "\n")
    if text == "" then
      text = " "
    end

    if alertId then
      hs.alert.closeSpecific(alertId)
      alertId = nil
    end

    local style = { textSize = 14, radius = 6 }
    local ok, id = pcall(hs.alert.show, text, style, alertPos(), secs)
    if ok and id then
      alertId = id
      return
    end
    hs.alert.show(text, style, secs)
  end

  return function(msg, secs)
    secs = secs or 2.0
    lines[#lines + 1] = tostring(msg)
    if #lines > maxLines then
      table.remove(lines, 1)
    end
    show(secs)

    if timer then
      timer:stop()
      timer = nil
    end
    timer = hs.timer.doAfter(secs, function()
      lines = {}
      if alertId then
        hs.alert.closeSpecific(alertId)
        alertId = nil
      end
    end)
  end
end)()

-- ------------- Helpers -------------
local function sleepSeconds(sec)
  if sec and sec > 0 then
    hs.timer.usleep(math.floor(sec * 1000000))
  end
end

local function appNameOrBundle(win)
  local app = win and win:application()
  if not app then
    return "[UnknownApp]"
  end
  return app:bundleID() or app:name() or "[Unknown]"
end

local function GetWinInfo(win)
  win = win or hs.window.frontmostWindow()
  if not win then
    return nil
  end
  return {
    title = win:title() or "",
    id = win:id(),
    app = appNameOrBundle(win),
    appName = win:application() and win:application():name() or "",
    bundleID = win:application() and win:application():bundleID() or "",
  }
end

local function allWindowsVisible()
  -- filters out hidden or minimized windows
  local wins = hs.window.filter.default:getWindows()
  local out = {}
  for _, w in ipairs(wins) do
    if w:isVisible() then
      table.insert(out, w)
    end
  end
  return out
end

-- ------------- Workspace model -------------
local function Workspace(label)
  return {
    label = label,
    id = nil,
    isPaired = false,
    inputBuffer = Config.minimizeThreshold, -- per-workspace buffer
  }
end

local TAPSHOP = {
  cfg = Config,
  workspaces = {},
  ytTargetId = nil,
}

for i = 1, 9 do
  table.insert(TAPSHOP.workspaces, Workspace("Window " .. tostring(i)))
end

-- ------------- YouTube window tracking -------------
local function isYouTubeWindow(win)
  if not win or not win:isVisible() then
    return false
  end
  local app = win:application()
  if not app then
    return false
  end
  local bid = app:bundleID() or ""
  if not TAPSHOP.cfg.browserBundleIDs[bid] then
    return false
  end
  local title = win:title() or ""
  if title == "" then
    return false
  end
  if string.find(title, "Subscriptions - YouTube", 1, true) then
    return false
  end
  return string.find(title, "- YouTube", 1, true) ~= nil
end

local function setYTTargetIfApplicable(win)
  if win and isYouTubeWindow(win) then
    local id = win:id()
    if TAPSHOP.ytTargetId ~= id then
      TAPSHOP.ytTargetId = id
      CursorMsg("YT Target Updated: " .. (win:title() or "[untitled]"))
    end
  end
end

local wf = hs.window.filter.new(nil)
wf:subscribe({
  hs.window.filter.windowFocused,
  hs.window.filter.windowTitleChanged,
}, function(win, appName, event)
  pcall(function()
    setYTTargetIfApplicable(win)
  end)
end)

local function getYTTargetWindow()
  if TAPSHOP.ytTargetId then
    local w = hs.window.get(TAPSHOP.ytTargetId)
    if w and w:isVisible() and isYouTubeWindow(w) then
      return w
    end
  end
  -- scan any YouTube window
  for _, w in ipairs(allWindowsVisible()) do
    if isYouTubeWindow(w) then
      TAPSHOP.ytTargetId = w:id()
      return w
    end
  end
  return nil
end

-- ------------- Spotify helpers -------------
local function spotifyIsRunning()
  local app = hs.application.get("Spotify")
  return app ~= nil
end

local function spotifyAdjustPosition(delta)
  -- adjust Spotify playback position by delta seconds
  local script = string.format(
    [[
      tell application "Spotify"
        if it is running then
          try
            set p to player position
            set player position to (p + %f)
          end try
        end if
      end tell
    ]],
    delta
  )
  hs.osascript.applescript(script)
end

local function spotifyToggleLike()
  -- Try 'liked' property; fallback to 'starred' if older builds.
  local script = [[
    tell application "Spotify"
      if it is running then
        try
          set t to current track
          try
            set liked of t to not (liked of t)
          on error
            set starred of t to not (starred of t)
          end try
        end try
      end if
    end tell
  ]]
  hs.osascript.applescript(script)
end

--------------- Window pairing / switching -------------
local function focusOrRestore(win)
  if not win then
    return false
  end
  local app = win:application()
  if app and app:isHidden() then
    app:unhide()
  end
  if win:isMinimized() then
    win:unminimize()
  end
  if app then
    app:activate(true)
  end
  hs.timer.doAfter(TAPSHOP.cfg.inputDelay, function()
    if win then
      win:focus()
    end
  end)
  return true
end

local function pairWindow(workspace)
  local win = hs.window.frontmostWindow()
  if not win then
    CursorMsg("No active window found!")
    return
  end
  local currentId = win:id()

  if not workspace.isPaired or not workspace.id then
    workspace.id = currentId
    workspace.isPaired = true
    workspace.inputBuffer = TAPSHOP.cfg.minimizeThreshold
    local info = GetWinInfo(win)
    CursorMsg(
      string.format(
        "[Pairing %s]\n%s\nid:%s\napp:%s",
        workspace.label,
        info.title,
        tostring(info.id),
        info.appName
      ),
      2.0
    )
    return
  end

  if currentId ~= workspace.id then
    -- Activate paired window (restore if minimized/hidden)
    local paired = hs.window.get(workspace.id)
    if paired then
      workspace.inputBuffer = TAPSHOP.cfg.minimizeThreshold
      focusOrRestore(paired)
    else
      -- Window truly gone: clear
      workspace.id = nil
      workspace.isPaired = false
      CursorMsg("[Paired window missing; cleared]")
    end
  else
    -- same window pressed repeatedly: decrement buffer then minimize
    workspace.inputBuffer = workspace.inputBuffer - 1
    local paired = hs.window.get(workspace.id)
    if paired and workspace.inputBuffer <= 0 then
      workspace.inputBuffer = TAPSHOP.cfg.minimizeThreshold
      paired:minimize()
    end
  end
end

local function focusWorkspace(workspace)
  if workspace.isPaired and workspace.id then
    local paired = hs.window.get(workspace.id)
    if paired then
      focusOrRestore(paired)
    else
      workspace.id = nil
      workspace.isPaired = false
      CursorMsg("[Paired window missing; cleared]")
    end
  else
    CursorMsg(workspace.label .. " not paired")
  end
end

local function unpairWindow(workspace)
  if workspace.isPaired then
    workspace.id = nil
    workspace.isPaired = false
    workspace.inputBuffer = TAPSHOP.cfg.minimizeThreshold
    CursorMsg("[Unpaired " .. workspace.label .. "]")
  else
    CursorMsg(workspace.label .. " is already unpaired!")
  end
end

local function unpairAll()
  for _, ws in ipairs(TAPSHOP.workspaces) do
    ws.id = nil
    ws.isPaired = false
    ws.inputBuffer = TAPSHOP.cfg.minimizeThreshold
  end
  CursorMsg("[Unpaired All Windows]")
end

--------------- YouTube control -------------
local function sendKeyStrokes(keys)
  -- keys: a small subset parser for "{Left}", "{Right}" or "k"/"j"/"l"
  local special = {
    ["{Left}"] = { {}, "left" },
    ["{Right}"] = { {}, "right" },
  }
  if special[keys] then
    hs.eventtap.keyStroke(special[keys][1], special[keys][2], 0)
    return
  end
  if #keys == 1 then
    hs.eventtap.keyStroke({}, keys, 0)
    return
  end
end

local function YoutubeControl(keyPress)
  local target = getYTTargetWindow()
  if not target then
    CursorMsg("YouTube window not found.")
    return
  end
  local prevApp = hs.application.frontmostApplication()
  target:focus()
  if target == hs.window.frontmostWindow() then
    sleepSeconds(TAPSHOP.cfg.inputDelay)
    sendKeyStrokes(keyPress)
  else
    CursorMsg("Focus failed for YT window")
  end
  if prevApp then
    prevApp:activate()
  end
end

-- ------------- Spotify control -------------
local function SpotifyControl(keyPress)
  -- Focus Spotify window and send keystrokes. Fallback method.
  local app = hs.application.get("Spotify")
  if not app then
    CursorMsg("Spotify not running.")
    return
  end
  local prevApp = hs.application.frontmostApplication()
  app:activate(true)
  sleepSeconds(TAPSHOP.cfg.inputDelay)

  local function parseAndSend(s)
    -- Minimal translator for the few you used in AHK:
    if s == "!+b" then
      -- Option+Shift+b in AHK; here we toggle Like via AppleScript
      spotifyToggleLike()
      return
    elseif s == "^{Down}" then
      hs.spotify.setVolume(math.max(0, (hs.spotify.getVolume() or 50) - 6))
      return
    elseif s == "^{Up}" then
      hs.spotify.setVolume(math.min(100, (hs.spotify.getVolume() or 50) + 6))
      return
    end
  end

  parseAndSend(keyPress)
  if prevApp then
    prevApp:activate()
  end
end

local function SpotifyControlV2(appCommand)
  -- Native control; doesn't need window focus
  if appCommand == "APPCOMMAND_MEDIA_PREVIOUSTRACK" then
    hs.spotify.previous()
  elseif appCommand == "APPCOMMAND_MEDIA_NEXTTRACK" then
    hs.spotify.next()
  elseif appCommand == "APPCOMMAND_MEDIA_PLAY_PAUSE" then
    hs.spotify.playpause()
  elseif appCommand == "APPCOMMAND_MEDIA_REWIND" then
    spotifyAdjustPosition(-5)
  elseif appCommand == "APPCOMMAND_MEDIA_FAST_FORWARD" then
    spotifyAdjustPosition(5)
  elseif appCommand == "APPCOMMAND_VOLUME_DOWN" then
    hs.spotify.setVolume(math.max(0, (hs.spotify.getVolume() or 50) - 6))
  elseif appCommand == "APPCOMMAND_VOLUME_UP" then
    hs.spotify.setVolume(math.min(100, (hs.spotify.getVolume() or 50) + 6))
  elseif appCommand == "APPCOMMAND_VOLUME_MUTE" then
    -- System mute instead of Spotify mute (Spotify has no dedicated mute)
    local dev = hs.audiodevice.defaultOutputDevice()
    if dev then
      dev:setMuted(not dev:muted())
    end
  end
end

-- ------------- Active window info -------------
local function DisplayActiveWindowStats()
  local info = GetWinInfo()
  if info then
    hs.dialog.blockAlert(
      "Active Window",
      string.format(
        "Title: %s\nID: %s\nApp: %s\nBundleID: %s",
        info.title,
        tostring(info.id),
        info.appName,
        info.bundleID
      ),
      "OK",
      "",
      "informational"
    )
  end
end

--------------- Menubar helper -------------
local menuBar = hs.menubar.new(true)
local function rebuildMenu()
  local function winTitleById(id)
    local w = id and hs.window.get(id)
    if w then
      local app = w:application()
      local prefix = app and app:name() or "App"
      local title = (w:title() or "")
      if w:isMinimized() then
        title = title .. " (minimized)"
      end
      return "[" .. prefix .. "] " .. title
    end
    return "[Unpaired]"
  end

  local items = {}
  table.insert(items, { title = "Active Window Details…", fn = DisplayActiveWindowStats })
  table.insert(items, { title = "-" })

  for i, ws in ipairs(TAPSHOP.workspaces) do
    table.insert(items, {
      title = string.format("%d) %s -> %s", i, ws.label, winTitleById(ws.id)),
      disabled = true,
    })
    table.insert(items, {
      title = "  Pair with current window",
      fn = function()
        pairWindow(ws)
        rebuildMenu()
      end,
    })
    table.insert(items, {
      title = "  Unpair",
      fn = function()
        unpairWindow(ws)
        rebuildMenu()
      end,
    })
    table.insert(items, { title = "-" })
  end

  table.insert(items, {
    title = "Unpair ALL",
    fn = function()
      unpairAll()
      rebuildMenu()
    end,
  })
  menuBar:setMenu(items)
end

menuBar:setTitle("TAPSHOP")
rebuildMenu()

--------------- Hotkeys (Cmd+Option for context-aware pairing) -------------
local pairMods = { "cmd", "alt" }
local unpairMods = { "cmd", "alt", "shift" }
local toggleMenuBar = { "cmd", "alt", "shift" }

-- Cmd+Option+1..9: context-aware pair/focus/minimize
for i = 1, 9 do
  hs.hotkey.bind(pairMods, tostring(i), function()
    pairWindow(TAPSHOP.workspaces[i])
    rebuildMenu()
  end)
end

-- Cmd+Option+Shift+1..9: unpair slots; Cmd+Option+Shift+0: unpair all
for i = 1, 9 do
  hs.hotkey.bind(unpairMods, tostring(i), function()
    unpairWindow(TAPSHOP.workspaces[i])
    rebuildMenu()
  end)
end
hs.hotkey.bind(unpairMods, "0", function()
  unpairAll()
  rebuildMenu()
end)

-- Toggle info window (Cmd+Option+`)
hs.hotkey.bind(pairMods, "`", function()
  DisplayActiveWindowStats()
end)

-- Toggle menubar (Cmd+Option+Shift+`)
hs.hotkey.bind(toggleMenuBar, "`", function()
  print(menuBar)
  if menuBar then
    local pt = hs.mouse.getAbsolutePosition()
    pt.y = 22
    menuBar:popupMenu(pt)
  else
    CursorMsg("TAPSHOP menu not available")
  end
end)

-- YouTube controls on Cmd+Option layer
hs.hotkey.bind(pairMods, "left", function()
  YoutubeControl("{Left}")
end)
hs.hotkey.bind(pairMods, "right", function()
  YoutubeControl("{Right}")
end)
hs.hotkey.bind(pairMods, "j", function()
  YoutubeControl("j")
end)
hs.hotkey.bind(pairMods, "l", function()
  YoutubeControl("l")
end)
hs.hotkey.bind(pairMods, "k", function()
  YoutubeControl("k")
end)

-- Optional legacy F19/F20/F21 binds (kept but not required)
bindIfAvailable({}, "F19", function()
  YoutubeControl("{Left}")
end)
bindIfAvailable({ "ctrl" }, "F19", function()
  YoutubeControl("j")
end)
bindIfAvailable({}, "F21", function()
  YoutubeControl("{Right}")
end)
bindIfAvailable({ "ctrl" }, "F21", function()
  YoutubeControl("l")
end)
bindIfAvailable({}, "F20", function()
  YoutubeControl("k")
end)

-- Spotify media keys (native V2)
hs.hotkey.bind({}, "F7", function()
  SpotifyControlV2("APPCOMMAND_MEDIA_PREVIOUSTRACK")
end)
hs.hotkey.bind({}, "F8", function()
  SpotifyControlV2("APPCOMMAND_MEDIA_PLAY_PAUSE")
end)
hs.hotkey.bind({}, "F9", function()
  SpotifyControlV2("APPCOMMAND_MEDIA_NEXTTRACK")
end)

-- Seek with Ctrl+F7/F9 (rewind/fast-forward)
hs.hotkey.bind({ "ctrl" }, "F7", function()
  SpotifyControlV2("APPCOMMAND_MEDIA_REWIND")
end)
hs.hotkey.bind({ "ctrl" }, "F9", function()
  SpotifyControlV2("APPCOMMAND_MEDIA_FAST_FORWARD")
end)

-- Volume and like (guarded F-keys)
bindIfAvailable({}, "F23", function()
  SpotifyControlV2("APPCOMMAND_VOLUME_DOWN")
end)
bindIfAvailable({}, "F24", function()
  SpotifyControlV2("APPCOMMAND_VOLUME_UP")
end)
bindIfAvailable({}, "F22", function()
  spotifyToggleLike()
end)

-- Alternate volume controls for keyboards without knobs (Hyper retained)
local hyper = { "cmd", "alt", "ctrl" }
hs.hotkey.bind(hyper, ",", function()
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    local v = math.max(0, (dev:volume() or 25) - 5)
    dev:setVolume(v)
  end
end)
hs.hotkey.bind(hyper, ".", function()
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    local v = math.min(100, (dev:volume() or 25) + 5)
    dev:setVolume(v)
  end
end)
hs.hotkey.bind(hyper, "M", function()
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    dev:setMuted(not dev:muted())
  end
end)

--------------- Init message -------------
CursorMsg("TAPSHOP ready (Hammerspoon)")