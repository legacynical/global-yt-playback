local icons = require("ui.icons")
local hs = hs

local Render = {}

local function escapeHtml(text)
  local value = tostring(text or "")
  return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function escapeAttr(text)
  return escapeHtml(text)
end

local PENCIL_SVG =
  '<svg class="profile-edit-icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false" fill="currentColor">'
  .. '<path d="M12.146 2.146a.5.5 0 0 1 .708 0l1 1a.5.5 0 0 1 0 .708l-1.5 1.5-1.708-1.708 1.5-1.5zm-2.207 2.207L2.5 11.792V13.5h1.708l7.439-7.439-1.708-1.708zM1.5 12.5v2h2l.5-.5H2v-1.5l-.5.5z"/>'
  .. "</svg>"

local function rowHtml(row, config)
  config = config or {}
  local hidePairButtons = config.hidePairButtons == true
  local unpairClass = row.canUnpair and "btn btn-unpair" or "btn btn-unpair off"
  local appIconClass = row.iconMuted and "slot-app-icon is-muted" or "slot-app-icon"
  local appIcon = ""
  if row.useYouTubeIcon then
    appIcon = icons.youtubeSlotIconHtml(appIconClass)
  end
  if appIcon == "" then
    appIcon = icons.slotAppIconHtml(row.iconBundleID, row.iconAppName, appIconClass)
  end
  local badgeHtml = ""
  local buttonsHtml = ""

  if row.canActivate and appIcon ~= "" then
    appIcon = '<button type="button" class="slot-icon-btn" aria-label="Activate slot '
      .. tostring(row.index)
      .. '" onclick="sendAction(\'activateSlot\', { slot: '
      .. tostring(row.index)
      .. ' })">'
      .. appIcon
      .. "</button>"
  end

  if row.badgeText and row.badgeText ~= "" then
    local badgeClass = "slot-badge"
    if row.state == "minimized" then
      badgeClass = badgeClass .. " is-minimized"
    elseif row.state == "fullscreen" then
      badgeClass = badgeClass .. " is-fullscreen"
    end
    badgeHtml = '<span class="' .. badgeClass .. '">' .. escapeHtml(row.badgeText) .. "</span>"
  end

  if not hidePairButtons then
    buttonsHtml = "        <div class=\"slot-buttons\">\n"
      .. "          <button class=\"btn btn-primary\" type=\"button\" onclick=\"sendAction('pair', { slot: "
      .. tostring(row.index)
      .. " })\">Pair</button>\n"
      .. "          <button class=\""
      .. unpairClass
      .. "\" type=\"button\" onclick=\"sendAction('unpair', { slot: "
      .. tostring(row.index)
      .. " })\">Unpair</button>\n"
      .. "        </div>\n"
  end

  return "      <div class=\"row is-slots-row\">\n"
    .. "        <span class=\"slot-num\">" .. tostring(row.index) .. "</span>\n"
    .. "        <span class=\"slot-label " .. row.className .. "\"><span class=\"slot-text-bg\">"
    .. appIcon
    .. "<span class=\"slot-text\">"
    .. escapeHtml(row.label)
    .. "</span>"
    .. "</span>"
    .. badgeHtml
    .. "</span>\n"
    .. buttonsHtml
    .. "      </div>\n"
end

function Render.slotsListInnerHtml(rows, config)
  local parts = {
    '<div class="profile-rail" id="profile-rail" aria-hidden="true"></div>\n',
  }
  for _, row in ipairs(rows or {}) do
    parts[#parts + 1] = rowHtml(row, config)
  end
  return table.concat(parts)
end

local function profileColorStyle(color)
  if not color or color == "" then
    return ""
  end
  return ' style="background: ' .. escapeAttr(color) .. ';"'
end

local function profileRowHtml(profile)
  local color = profile.color
  local hasColor = type(color) == "string" and color ~= ""
  local pairedCount = tonumber(profile.pairedCount) or 0
  local statusClass = pairedCount > 0 and "is-paired" or "is-empty"
  local activeClass = profile.isActive and " is-active-profile" or ""
  local emptyClass = pairedCount > 0 and "" or " is-empty"
  local squareClass = "profile-color-btn" .. (hasColor and "" or " is-none")
  local squareStyle = profileColorStyle(hasColor and color or nil)
  local id = tostring(profile.id)

  local colorAttr = ""
  if hasColor then
    colorAttr = ' data-color="' .. escapeAttr(color) .. '"'
  end

  return table.concat({
    '<div class="row is-profile-row',
    activeClass,
    emptyClass,
    '" data-profile-id="',
    id,
    '">\n',
    '        <span class="slot-num">',
    id,
    "</span>\n",
    '        <span class="profile-label">',
    '<span class="profile-label-pill">',
    '<button type="button" class="',
    squareClass,
    '" data-profile-id="',
    id,
    '"',
    colorAttr,
    ' aria-label="Activate ',
    escapeAttr(profile.name),
    '"',
    squareStyle,
    "></button>",
    '<span class="profile-label-text">',
    escapeHtml(profile.name),
    "</span>",
    "</span>",
    "</span>\n",
    '        <div class="profile-edit-actions">\n',
    '          <button type="button" class="profile-icon-btn profile-edit-btn" data-profile-id="',
    id,
    '" aria-label="Edit name and color" data-tooltip="Edit name &amp; color">',
    PENCIL_SVG,
    "</button>\n",
    "        </div>\n",
    '        <span class="profile-status ',
    statusClass,
    '">',
    tostring(pairedCount),
    "/9</span>\n",
    "      </div>\n",
  })
end

function Render.profilesListInnerHtml(profiles)
  local parts = {}
  for _, profile in ipairs(profiles or {}) do
    parts[#parts + 1] = profileRowHtml(profile)
  end
  return table.concat(parts)
end

local function profileSwitcherHtml(ctx)
  local active = ctx.activeProfile or {}
  local color = active.color
  local hasColor = type(color) == "string" and color ~= ""
  local style = ""
  if hasColor then
    style = ' style="--profile-tint: ' .. escapeAttr(color) .. ';"'
  end
  local tintClass = hasColor and " has-profile-tint" or ""
  if ctx.profileListMode == "profiles" then
    tintClass = tintClass .. " is-profiles-mode"
  end

  return table.concat({
    '<button type="button" class="header-btn header-profile',
    tintClass,
    '" id="profile-mode-toggle" aria-label="Toggle profiles mode" data-tooltip="Profiles"',
    style,
    ' onclick="tapshopToggleProfileMode()">',
    icons.headerIconSvg("profile"),
    "</button>",
  })
end

local function colorPaletteJson(ctx)
  local colors = ctx.profilePaletteColors or {}
  return hs.json.encode(colors) or "[]"
end

function Render.buildHtml(ctx)
  local headerAppIcon = icons.appIconHtml(ctx.headerBundleID, ctx.headerAppName, "header-active-win-icon", 16)
  local brandIcon = icons.tapshopBrandIconHtml("title-brand-icon", 16)
  local bodyClass = ""
  if ctx.config and ctx.config.utilityOverlay then
    bodyClass = ' class="is-utility-overlay"'
  end

  local active = ctx.activeProfile or {}
  local activeColor = active.color
  local hasActiveColor = type(activeColor) == "string" and activeColor ~= ""
  local shellStyle = ""
  local listMode = ctx.profileListMode == "profiles" and "profiles" or "slots"
  local shellClass = "body-shell is-" .. listMode .. "-mode"
  if hasActiveColor then
    shellClass = shellClass .. " has-active-color"
    shellStyle = ' style="--active-profile-color: ' .. escapeAttr(activeColor) .. ';"'
  end
  local slotsHidden = listMode == "profiles" and " hidden" or ""
  local profilesHidden = listMode ~= "profiles" and " hidden" or ""

  local parts = {
    "<!DOCTYPE html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <style>\n",
    ctx.css,
    "\n  </style>\n</head>\n<body tabindex=\"0\"",
    bodyClass,
    ">\n  <div class=\"container\">\n    <div class=\"header\">\n      <div class=\"title-wrap\">\n        <button class=\"title-logo\" type=\"button\" aria-label=\"Tapshop\">",
    brandIcon,
    "</button>\n      </div>\n      <div class=\"header-active-win\">",
    headerAppIcon,
    "<span class=\"header-active-win-title\">",
    escapeHtml(ctx.primaryLine),
    "</span>\n      </div>\n      <div class=\"header-actions\">\n        ",
    profileSwitcherHtml(ctx),
    "\n        ",
    icons.headerIconButton({
      className = "header-danger",
      icon = "clearAll",
      tooltip = "Unpair ALL",
      onclick = "showUnpairAllConfirm()",
    }),
    "\n        ",
    icons.headerIconButton({
      className = "header-config",
      icon = "config",
      tooltip = "Settings",
      onclick = "sendAction('toggleSettingsWindow')",
    }),
    "\n        ",
    icons.headerIconButton({
      className = "header-close",
      icon = "hide",
      tooltip = "Hide",
      onclick = "sendAction('close')",
    }),
    "\n      </div>\n    </div>\n    <div class=\"header-tooltip\" aria-hidden=\"true\"></div>\n    <div class=\"",
    shellClass,
    "\" id=\"body-shell\"",
    shellStyle,
    ">\n      <div class=\"workspace-list is-slots-list\" id=\"slots-list\"",
    slotsHidden,
    ">\n",
    Render.slotsListInnerHtml(ctx.rows, ctx.config),
    "      </div>\n      <div class=\"workspace-list is-profiles-list\" id=\"profiles-list\"",
    profilesHidden,
    ">\n",
    Render.profilesListInnerHtml(ctx.profileRows),
    "      </div>\n    </div>\n",
    '    <div class="color-picker" id="profile-color-picker" hidden aria-label="Profile color palette">\n',
    '      <div class="color-picker-grid" id="profile-color-picker-grid"></div>\n',
    "    </div>\n",
    '    <div class="confirm-shell" id="unpair-all-confirm" hidden>\n',
    '      <button type="button" class="confirm-backdrop" aria-label="Cancel" onclick="hideUnpairAllConfirm()"></button>\n',
    '      <div class="confirm-dialog" role="dialog" aria-modal="true" aria-labelledby="unpair-all-confirm-title">\n',
    '        <div class="confirm-title" id="unpair-all-confirm-title">Unpair All?</div>\n',
    '        <div class="confirm-actions">\n',
    '          <button type="button" class="btn confirm-ok" onclick="confirmUnpairAll()">Confirm</button>\n',
    '          <button type="button" class="btn confirm-cancel" onclick="hideUnpairAllConfirm()">Cancel</button>\n',
    "        </div>\n",
    "      </div>\n",
    "    </div>\n",
    "  </div>\n",
    '  <div class="resize-handles" aria-hidden="true">\n',
    '    <div class="resize-handle resize-s" data-resize="s"></div>\n',
    '    <div class="resize-handle resize-e" data-resize="e"></div>\n',
    '    <div class="resize-handle resize-w" data-resize="w"></div>\n',
    '    <div class="resize-handle resize-se" data-resize="se"></div>\n',
    '    <div class="resize-handle resize-sw" data-resize="sw"></div>\n',
    "  </div>\n<script>\nwindow.tapshopLayoutPolicy = ",
    hs.json.encode(ctx.layoutPolicy or {}) or "{}",
    ";\nwindow.tapshopProfilePalette = ",
    colorPaletteJson(ctx),
    ";\nwindow.tapshopActiveProfile = ",
    hs.json.encode(active) or "{}",
    ";\n",
    ctx.script,
    "\n</script>\n</body>\n</html>",
  }

  return table.concat(parts)
end

return Render
