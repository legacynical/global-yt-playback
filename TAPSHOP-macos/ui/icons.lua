local hs = hs

local Icons = {}
local APP_ICON_URL_CACHE = {}
local cachedModuleDir = nil

local function escapeHtml(text)
  local value = tostring(text or "")
  return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local HEADER_ICON_SVGS = {
  hide = [=[
<path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49" />
<path d="M14.084 14.158a3 3 0 0 1-4.242-4.242" />
<path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143" />
<path d="m2 2 20 20" />
]=],
  config = [=[
<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915" />
<circle cx="12" cy="12" r="3" />
]=],
  clearAll = [=[
<path d="M10 11v6" />
<path d="M14 11v6" />
<path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
<path d="M3 6h18" />
<path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
]=],
  profile = [=[
<circle cx="12" cy="8" r="4" />
<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
]=],
  restore = [=[
<path d="M3 2v6h6" />
<path d="M3 8a9 9 0 1 0 3-6.7L3 4" />
]=],
}

local function moduleDir()
  if cachedModuleDir then
    return cachedModuleDir
  end

  local source = debug.getinfo(1, "S").source
  local scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
  cachedModuleDir = scriptPath:match("^(.*)/[^/]+$")
  return cachedModuleDir
end

local function systemKeySvg(inner)
  return '<svg class="keycap-system-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'
    .. inner
    .. "</svg>"
end

local SYSTEM_KEY_DISPLAY = {
  BRIGHTNESS_UP = {
    label = "Brightness Up",
    svg = systemKeySvg([[
<path d="M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0" />
<path d="M12 5l0 -2" />
<path d="M17 7l1.4 -1.4" />
<path d="M19 12l2 0" />
<path d="M17 17l1.4 1.4" />
<path d="M12 19l0 2" />
<path d="M7 17l-1.4 1.4" />
<path d="M5 12l-2 0" />
<path d="M7 7l-1.4 -1.4" />
]]),
  },
  BRIGHTNESS_DOWN = {
    label = "Brightness Down",
    svg = systemKeySvg([[
<path d="M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0" />
<path d="M12 5l0 .01" />
<path d="M17 7l0 .01" />
<path d="M19 12l0 .01" />
<path d="M17 17l0 .01" />
<path d="M12 19l0 .01" />
<path d="M7 17l0 .01" />
<path d="M5 12l0 .01" />
<path d="M7 7l0 .01" />
]]),
  },
  SOUND_UP = {
    label = "Volume Up",
    svg = systemKeySvg([[
<path d="M5 14h3l4 4V6L8 10H5z" />
<path d="M16 9.5a4.5 4.5 0 0 1 0 5" />
<path d="M18.5 7a8 8 0 0 1 0 10" />
]]),
  },
  SOUND_DOWN = {
    label = "Volume Down",
    svg = systemKeySvg([[
<path d="M5 14h3l4 4V6L8 10H5z" />
<path d="M16 9.5a4.5 4.5 0 0 1 0 5" />
]]),
  },
  MUTE = {
    label = "Mute",
    svg = systemKeySvg([[
<path d="M5 14h3l4 4V6L8 10H5z" />
<path d="M16 9l4 6" />
<path d="M20 9l-4 6" />
]]),
  },
  PLAY = {
    label = "Play/Pause",
    svg = systemKeySvg([[
<path stroke-linecap="round" stroke-linejoin="round" d="M21 7.5V18M15 7.5V18M3 16.811V8.69c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061A1.125 1.125 0 0 1 3 16.811Z" />
]]),
  },
  FAST = {
    label = "Fast Forward",
    svg = systemKeySvg([[
<path stroke-linecap="round" stroke-linejoin="round" d="M3 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061A1.125 1.125 0 0 1 3 16.811V8.69ZM12.75 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061a1.125 1.125 0 0 1-1.683-.977V8.69Z" />
]]),
  },
  REWIND = {
    label = "Rewind",
    svg = systemKeySvg([[
<path stroke-linecap="round" stroke-linejoin="round" d="M21 16.811c0 .864-.933 1.406-1.683.977l-7.108-4.061a1.125 1.125 0 0 1 0-1.954l7.108-4.061A1.125 1.125 0 0 1 21 8.689v8.122ZM11.25 16.811c0 .864-.933 1.406-1.683.977l-7.108-4.061a1.125 1.125 0 0 1 0-1.954l7.108-4.061a1.125 1.125 0 0 1 1.683.977v8.122Z" />
]]),
  },
  NEXT = {
    label = "Next",
    svg = systemKeySvg([[
<path d="M5 6l6 6-6 6z" />
<path d="M11 6l6 6-6 6z" />
<path d="M19 6v12" />
]]),
  },
  PREVIOUS = {
    label = "Previous",
    svg = systemKeySvg([[
<path d="M19 6l-6 6 6 6z" />
<path d="M13 6l-6 6 6 6z" />
<path d="M5 6v12" />
]]),
  },
  LAUNCH_PANEL = {
    label = "Launchpad",
    svg = systemKeySvg([[
<rect x="5" y="5" width="4" height="4" rx="0.8" />
<rect x="10" y="5" width="4" height="4" rx="0.8" />
<rect x="15" y="5" width="4" height="4" rx="0.8" />
<rect x="5" y="10" width="4" height="4" rx="0.8" />
<rect x="10" y="10" width="4" height="4" rx="0.8" />
<rect x="15" y="10" width="4" height="4" rx="0.8" />
<rect x="5" y="15" width="4" height="4" rx="0.8" />
<rect x="10" y="15" width="4" height="4" rx="0.8" />
<rect x="15" y="15" width="4" height="4" rx="0.8" />
]]),
  },
  EJECT = {
    label = "Eject",
    svg = systemKeySvg([[
<path d="M12 5l6 8H6z" />
<path d="M7 20h10" />
]]),
  },
}

function Icons.headerIconSvg(name)
  local icon = HEADER_ICON_SVGS[name] or ""
  return '<svg class="header-action-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">'
    .. icon
    .. "</svg>"
end

function Icons.headerIconButton(opts)
  local tooltip = escapeHtml(opts.tooltip)
  local ariaLabel = escapeHtml(opts.ariaLabel or opts.tooltip)
  return '<button type="button" class="header-btn icon-only '
    .. opts.className
    .. '" aria-label="'
    .. ariaLabel
    .. '" data-tooltip="'
    .. tooltip
    .. '" onclick="'
    .. opts.onclick
    .. '">'
    .. Icons.headerIconSvg(opts.icon)
    .. "</button>"
end

function Icons.systemKeyDisplay(key)
  return SYSTEM_KEY_DISPLAY[tostring(key or "")]
end

function Icons.systemKeyDisplayJsData()
  local out = {}
  for key, meta in pairs(SYSTEM_KEY_DISPLAY) do
    out[key] = {
      label = meta.label,
      svg = meta.svg,
    }
  end
  return out
end

function Icons.appIconUrl(bundleID, size)
  if type(bundleID) ~= "string" or bundleID == "" then
    return nil
  end

  local cacheKey = table.concat({ bundleID, tostring(size or 18) }, "::")
  local cached = APP_ICON_URL_CACHE[cacheKey]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end

  local image = hs.image.imageFromAppBundle(bundleID)
  if not image then
    APP_ICON_URL_CACHE[cacheKey] = false
    return nil
  end

  local ok, encoded = pcall(function()
    return image:setSize({ h = size or 18, w = size or 18 }):encodeAsURLString()
  end)
  APP_ICON_URL_CACHE[cacheKey] = ok and encoded or false
  return ok and encoded or nil
end

function Icons.imageUrlFromPath(imagePath, size)
  if type(imagePath) ~= "string" or imagePath == "" or not hs.image or not hs.image.imageFromPath then
    return nil
  end

  local cacheKey = table.concat({ "path", imagePath, tostring(size or 18) }, "::")
  local cached = APP_ICON_URL_CACHE[cacheKey]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end

  local image = hs.image.imageFromPath(imagePath)
  if not image then
    APP_ICON_URL_CACHE[cacheKey] = false
    return nil
  end

  local ok, encoded = pcall(function()
    return image:setSize({ h = size or 18, w = size or 18 }):encodeAsURLString()
  end)
  APP_ICON_URL_CACHE[cacheKey] = ok and encoded or false
  return ok and encoded or nil
end

function Icons.appIconHtml(bundleID, appName, className, size)
  local iconUrl = Icons.appIconUrl(bundleID, size or 18)
  if not iconUrl then
    return ""
  end

  return '<img class="'
    .. escapeHtml(className or "slot-app-icon")
    .. '" src="'
    .. escapeHtml(iconUrl)
    .. '" alt="" aria-hidden="true" title="'
    .. escapeHtml(appName or "")
    .. '">'
end

function Icons.imagePathHtml(imagePath, className, size, title)
  local iconUrl = Icons.imageUrlFromPath(imagePath, size or 18)
  if not iconUrl then
    return ""
  end

  return '<img class="'
    .. escapeHtml(className or "slot-app-icon")
    .. '" src="'
    .. escapeHtml(iconUrl)
    .. '" alt="" aria-hidden="true" title="'
    .. escapeHtml(title or "")
    .. '">'
end

function Icons.tapshopIconPath()
  local dir = moduleDir()
  if not dir then
    return nil
  end
  return dir .. "/tapshop.png"
end

function Icons.youtubeIconPath()
  local dir = moduleDir()
  if not dir then
    return nil
  end
  return dir .. "/youtube.png"
end

function Icons.tapshopBrandIconHtml(className, size)
  return Icons.imagePathHtml(Icons.tapshopIconPath(), className or "title-brand-icon", size or 16, "TAPSHOP")
end

function Icons.youtubeSlotIconHtml(className, size)
  return Icons.imagePathHtml(Icons.youtubeIconPath(), className or "slot-app-icon", size or 18, "YouTube")
end

function Icons.slotAppIconHtml(bundleID, appName, className)
  return Icons.appIconHtml(bundleID, appName, className or "slot-app-icon", 18)
end

return Icons
