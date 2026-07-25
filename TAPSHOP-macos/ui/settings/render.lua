local icons = require("ui.icons")
local hs = hs

local Render = {}

local KEY_LABELS = {
  left = "Left",
  right = "Right",
  up = "Up",
  down = "Down",
  ["return"] = "Return",
  delete = "Delete",
  forwarddelete = "Forward Delete",
  escape = "Esc",
  space = "Space",
  tab = "Tab",
  ["`"] = "`",
  [","] = ",",
  ["."] = ".",
  BRIGHTNESS_UP = "Brightness Up",
  BRIGHTNESS_DOWN = "Brightness Down",
  SOUND_UP = "Volume Up",
  SOUND_DOWN = "Volume Down",
  PLAY = "Play/Pause",
  LAUNCH_PANEL = "Launchpad",
}

local MOD_LABELS = {
  cmd = "⌘",
  alt = "⌥",
  ctrl = "⌃",
  shift = "⇧",
}

local MOD_TITLES = {
  cmd = "Command",
  alt = "Option",
  ctrl = "Control",
  shift = "Shift",
}

local function escapeHtml(text)
  local value = tostring(text or "")
  return (value:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function titleCaseWords(value)
  local lowered = string.lower(value or "")
  local parts = {}
  for part in lowered:gmatch("[^_]+") do
    parts[#parts + 1] = part:gsub("^%l", string.upper)
  end
  return table.concat(parts, " ")
end

local function displayKey(key)
  local raw = tostring(key or "")
  local systemMeta = icons.systemKeyDisplay(raw)
  if systemMeta then
    return systemMeta.label
  end
  if KEY_LABELS[raw] then
    return KEY_LABELS[raw]
  end
  local systemCode = raw:match("^SYSTEM_(%d+)$")
  if systemCode then
    return "SYSTEM_" .. systemCode
  end
  if raw:match("^[A-Z0-9_]+$") and raw:find("_", 1, true) then
    return titleCaseWords(raw)
  end
  return string.upper(raw)
end

local function keycapHtml(content, title, className)
  local classes = "keycap"
  if className and className ~= "" then
    classes = classes .. " " .. className
  end
  return '<span class="' .. classes .. '" title="' .. escapeHtml(title or "") .. '">' .. content .. "</span>"
end

local function comboHtml(mods, key)
  if key == false or key == nil or key == "" then
    return ""
  end

  local parts = {}
  for _, mod in ipairs(mods or {}) do
    parts[#parts + 1] = keycapHtml(
      escapeHtml(MOD_LABELS[mod] or mod),
      MOD_TITLES[mod] or tostring(mod),
      nil
    )
  end

  local rawKey = tostring(key or "")
  local systemMeta = icons.systemKeyDisplay(rawKey)
  if systemMeta then
    parts[#parts + 1] = keycapHtml(systemMeta.svg, systemMeta.label, "keycap-system")
  else
    local label = displayKey(rawKey)
    parts[#parts + 1] = keycapHtml(escapeHtml(label), label, nil)
  end

  return table.concat(parts)
end

function Render.buildHotkeyListHtml(rows)
  local parts = {}
  local currentGroup = nil
  for index, row in ipairs(rows or {}) do
    if row.group ~= currentGroup then
      currentGroup = row.group
      parts[#parts + 1] = "                <section class=\"hotkey-group\" data-hotkey-group=\""
      parts[#parts + 1] = escapeHtml(string.lower(row.group))
      parts[#parts + 1] = "\">\n"
      parts[#parts + 1] = "                  <div class=\"hotkey-group-title\">"
      parts[#parts + 1] = escapeHtml(row.group)
      parts[#parts + 1] = "</div>\n"
    end

    local classes = { "hotkey-row" }
    if row.isModified then
      classes[#classes + 1] = "is-modified"
    end
    if row.isUnavailable then
      classes[#classes + 1] = "is-unavailable"
    end
    if row.warning then
      classes[#classes + 1] = "has-warning"
    end
    if #(row.conflictIds or {}) > 0 then
      classes[#classes + 1] = "has-conflict"
    end

    local comboTitle = row.isAssigned and "Current shortcut" or "No shortcut assigned"
    local comboClass = row.isAssigned and "hotkey-combo" or "hotkey-combo hotkey-combo-empty"
    local comboInner = row.isAssigned and comboHtml(row.mods, row.key) or '<span class="hotkey-unset">(unset)</span>'
    local rawKey = row.isAssigned and tostring(row.key) or ""
    local comboSearch = row.isAssigned and string.lower(table.concat(row.mods or {}, " ") .. " " .. rawKey) or ""
    local resetHtml = ""
    if row.isModified then
      resetHtml = '<button type="button" class="btn hotkey-btn hotkey-reset-btn" title="Reset to default" data-hotkey-action="reset" data-hotkey-id="'
        .. escapeHtml(row.id)
        .. '">↺</button>'
    end

    parts[#parts + 1] = "              <div class=\""
    parts[#parts + 1] = table.concat(classes, " ")
    parts[#parts + 1] = "\" data-hotkey-row data-id=\""
    parts[#parts + 1] = escapeHtml(row.id)
    parts[#parts + 1] = "\" data-label=\""
    parts[#parts + 1] = escapeHtml(string.lower(row.label))
    parts[#parts + 1] = "\" data-group=\""
    parts[#parts + 1] = escapeHtml(string.lower(row.group))
    parts[#parts + 1] = "\" data-key=\""
    parts[#parts + 1] = escapeHtml(rawKey)
    parts[#parts + 1] = "\" data-mods=\""
    parts[#parts + 1] = escapeHtml(table.concat(row.mods or {}, " "))
    parts[#parts + 1] = "\" data-assigned=\""
    parts[#parts + 1] = row.isAssigned and "1" or "0"
    parts[#parts + 1] = "\" data-modified=\""
    parts[#parts + 1] = row.isModified and "1" or "0"
    parts[#parts + 1] = "\" data-combo=\""
    parts[#parts + 1] = escapeHtml(comboSearch)
    parts[#parts + 1] = "\">\n"
    parts[#parts + 1] = "                <div class=\"hotkey-main\">\n"
    parts[#parts + 1] = "                  <span class=\"hotkey-label\">"
    parts[#parts + 1] = escapeHtml(row.label)
    parts[#parts + 1] = "</span>\n"
    parts[#parts + 1] = "                  <div class=\""
    parts[#parts + 1] = comboClass
    parts[#parts + 1] = "\" title=\""
    parts[#parts + 1] = escapeHtml(comboTitle)
    parts[#parts + 1] = "\">"
    parts[#parts + 1] = comboInner
    parts[#parts + 1] = "</div>\n"
    parts[#parts + 1] = "                </div>\n"
    parts[#parts + 1] = "                <div class=\"hotkey-actions\">\n"
    parts[#parts + 1] = "                  "
    parts[#parts + 1] = resetHtml
    parts[#parts + 1] = "\n"
    parts[#parts + 1] = "                  <button type=\"button\" class=\"btn hotkey-btn hotkey-remap-btn\" title=\"Record shortcut\" data-hotkey-action=\"remap\" data-hotkey-id=\""
    parts[#parts + 1] = escapeHtml(row.id)
    parts[#parts + 1] = "\">Remap</button>\n"
    parts[#parts + 1] = "                </div>\n"
    parts[#parts + 1] = "              </div>\n"

    local nextRow = rows[index + 1]
    if not nextRow or nextRow.group ~= currentGroup then
      parts[#parts + 1] = "                </section>\n"
    end
  end

  return table.concat(parts)
end

local function checkedAttr(value)
  if value then
    return "checked"
  end
  return ""
end

local function headerGlyphButtonHtml(opts)
  return '<button type="button" class="header-btn icon-only '
    .. escapeHtml(opts.className or "")
    .. '" aria-label="'
    .. escapeHtml(opts.ariaLabel or opts.tooltip or "")
    .. '" data-tooltip="'
    .. escapeHtml(opts.tooltip or "")
    .. '" onclick="'
    .. escapeHtml(opts.onclick or "")
    .. '"><span class="header-action-glyph" aria-hidden="true">'
    .. escapeHtml(opts.glyph or "")
    .. "</span></button>"
end

local function generalTabHtml(config)
  return "          <div class=\"settings-panel\" data-settings-panel=\"general\">\n"
    .. "            <label class=\"settings-item\">\n"
    .. "              <input type=\"checkbox\" "
    .. checkedAttr(config.autoHideAfterAction)
    .. " data-settings-config=\"autoHideAfterAction\""
    .. " onchange=\"sendAction('setAutoHideAfterAction', { slot: this.checked ? 1 : 0 })\">\n"
    .. "              <span>Auto-hide after pair/unpair</span>\n"
    .. "            </label>\n"
    .. "            <label class=\"settings-item\">\n"
    .. "              <input type=\"checkbox\" "
    .. checkedAttr(config.alwaysOnTop)
    .. " data-settings-config=\"alwaysOnTop\""
    .. " onchange=\"sendAction('setAlwaysOnTop', { slot: this.checked ? 1 : 0 })\">\n"
    .. "              <span>Always on top</span>\n"
    .. "            </label>\n"
    .. "            <label class=\"settings-item\">\n"
    .. "              <input type=\"checkbox\" "
    .. checkedAttr(config.hideOnFullscreenWorkspace)
    .. " data-settings-config=\"hideOnFullscreenWorkspace\""
    .. " onchange=\"sendAction('setHideOnFullscreenWorkspace', { slot: this.checked ? 1 : 0 })\">\n"
    .. "              <span>Hide during fullscreens</span>\n"
    .. "            </label>\n"
    .. "            <label class=\"settings-item\">\n"
    .. "              <input type=\"checkbox\" "
    .. checkedAttr(config.hidePairButtons)
    .. " data-settings-config=\"hidePairButtons\""
    .. " onchange=\"sendAction('setHidePairButtons', { slot: this.checked ? 1 : 0 })\">\n"
    .. "              <span>Hide pair/unpair buttons</span>\n"
    .. "            </label>\n"
    .. "            <label class=\"settings-item\">\n"
    .. "              <input type=\"checkbox\" "
    .. checkedAttr(config.recoverClosedWindows)
    .. " data-settings-config=\"recoverClosedWindows\""
    .. " onchange=\"sendAction('setRecoverClosedWindows', { slot: this.checked ? 1 : 0 })\">\n"
    .. "              <span>Recover closed windows</span>\n"
    .. "            </label>\n"
    .. "            <div class=\"settings-slider-block settings-slider-inline\">\n"
    .. "              <label class=\"settings-slider-label\" for=\"settings-opacity-slider\">Background opacity</label>\n"
    .. "              <div class=\"settings-slider-control\">\n"
    .. "                <input id=\"settings-opacity-slider\" class=\"settings-slider\" data-settings-config=\"opacityPercent\" type=\"range\" min=\"40\" max=\"100\" step=\"10\" list=\"opacity-ticks\" value=\""
    .. tostring(config.opacityPercent)
    .. "\" oninput=\"updateOpacityPreview(this.value)\" onchange=\"sendAction('setPopoverOpacity', { slot: this.value })\">\n"
    .. "                <div class=\"settings-slider-ticks\" aria-hidden=\"true\">\n"
    .. "                  <span></span><span></span><span></span><span></span><span></span><span></span><span></span>\n"
    .. "                </div>\n"
    .. "              </div>\n"
    .. "              <datalist id=\"opacity-ticks\">\n"
    .. "                <option value=\"40\"></option>\n"
    .. "                <option value=\"50\"></option>\n"
    .. "                <option value=\"60\"></option>\n"
    .. "                <option value=\"70\"></option>\n"
    .. "                <option value=\"80\"></option>\n"
    .. "                <option value=\"90\"></option>\n"
    .. "                <option value=\"100\"></option>\n"
    .. "              </datalist>\n"
    .. "            </div>\n"
    .. "          </div>\n"
end

local function hotkeysTabHtml(ctx)
  local parts = {
    "          <div class=\"settings-panel\" data-settings-panel=\"hotkeys\">\n",
    "            <div class=\"hotkeys-helper\">Click Remap to open the recorder. Press a new shortcut, media key, or system key, then save it or unbind the action.</div>\n",
  }

  if ctx.validation and ctx.validation.message then
    parts[#parts + 1] = "            <div class=\"hotkeys-error\" data-hotkey-validation>"
    parts[#parts + 1] = escapeHtml(ctx.validation.message)
    parts[#parts + 1] = "</div>\n"
  else
    parts[#parts + 1] = "            <div class=\"hotkeys-error is-hidden\" data-hotkey-validation></div>\n"
  end

  parts[#parts + 1] = "            <div class=\"hotkeys-list\" data-hotkeys-list>\n"
  parts[#parts + 1] = ctx.hotkeysHtml or Render.buildHotkeyListHtml(ctx.hotkeys or {})
  parts[#parts + 1] = "            </div>\n"
  parts[#parts + 1] = "          </div>\n"
  return table.concat(parts)
end

local function remapModalHtml()
  return [[
      <div class="remap-modal-shell" data-remap-shell hidden>
        <button type="button" class="remap-modal-backdrop" aria-label="Close remap recorder" data-remap-action="cancel"></button>
        <div class="remap-modal" role="dialog" aria-modal="true" aria-labelledby="remap-modal-title">
          <div class="remap-modal-label" id="remap-modal-title" data-remap-label></div>
          <div class="remap-comparison">
            <div class="remap-binding-pane">
              <div class="remap-preview-title">Current</div>
              <div class="remap-preview-combo remap-binding-combo" data-remap-current></div>
            </div>
            <div class="remap-binding-arrow" aria-hidden="true">→</div>
            <div class="remap-binding-pane">
              <div class="remap-preview-title">New</div>
              <div class="remap-preview-combo remap-binding-combo" data-remap-draft></div>
            </div>
          </div>
          <div class="remap-mods" role="group" aria-label="Modifier keys">
            <button type="button" class="btn hotkey-btn remap-mod-btn" data-remap-mod="cmd"><span class="remap-mod-text">Cmd</span><span class="remap-mod-symbol">⌘</span></button>
            <button type="button" class="btn hotkey-btn remap-mod-btn" data-remap-mod="alt"><span class="remap-mod-text">Option</span><span class="remap-mod-symbol">⌥</span></button>
            <button type="button" class="btn hotkey-btn remap-mod-btn" data-remap-mod="ctrl"><span class="remap-mod-text">Ctrl</span><span class="remap-mod-symbol">⌃</span></button>
            <button type="button" class="btn hotkey-btn remap-mod-btn" data-remap-mod="shift"><span class="remap-mod-text">Shift</span><span class="remap-mod-symbol">⇧</span></button>
          </div>
          <div class="remap-capture" data-remap-capture tabindex="0" role="button" aria-label="Record new hotkey">
            <div class="remap-capture-topline">
              <span class="remap-capture-status" data-remap-status>Listening</span>
              <span class="remap-capture-hint" data-remap-hint>Press any shortcut, media key, or system key</span>
            </div>
          </div>
          <div class="hotkeys-error is-hidden" data-remap-error></div>
          <div class="remap-actions">
            <button type="button" class="btn hotkey-btn hotkey-reset-btn remap-reset-btn" data-remap-reset data-remap-action="reset">Reset</button>
            <button type="button" class="btn hotkey-btn remap-unbind-btn" data-remap-action="unbind">Unbind</button>
            <button type="button" class="btn hotkey-btn" data-remap-action="cancel">Cancel</button>
            <button type="button" class="btn hotkey-btn btn-primary remap-save-btn" data-remap-save data-remap-action="save">Save</button>
          </div>
        </div>
      </div>
]]
end

function Render.buildHtml(ctx)
  local generalActive = ctx.settingsTab ~= "hotkeys" and " is-active" or ""
  local hotkeysActive = ctx.settingsTab == "hotkeys" and " is-active" or ""
  local brandIcon = icons.tapshopBrandIconHtml("settings-brand-icon", 18)
  local parts = {
    "<!DOCTYPE html>\n<html>\n<head>\n  <meta charset=\"utf-8\">\n  <style>\n",
    ctx.css,
    "\n  </style>\n</head>\n<body data-settings-tab=\"",
    escapeHtml(ctx.settingsTab or "general"),
    "\" data-settings-scroll-top=\"",
    escapeHtml(tostring(ctx.scrollTop or 0)),
    "\">\n  <div class=\"container\">\n    <div class=\"header\">\n      <div class=\"header-titleblock\">\n        <div class=\"settings-window-title-row\">\n          ",
    brandIcon,
    "\n          <div class=\"settings-window-title\">TAPSHOP Settings</div>\n        </div>\n        <div class=\"settings-window-subtitle\">General preferences and hotkey overrides</div>\n      </div>\n      <div class=\"header-actions\">\n        ",
    icons.headerIconButton({
      className = "header-close",
      icon = "hide",
      tooltip = "Hide settings",
      onclick = "sendAction('close')",
    }),
    "\n      </div>\n    </div>\n    <div class=\"settings-window-shell\">\n      <div class=\"settings-head\">\n        <div class=\"settings-tabs\">\n          <button type=\"button\" data-settings-tab-button=\"general\" class=\"settings-tab",
    generalActive,
    "\" onclick=\"switchSettingsTab('general')\">General</button>\n          <button type=\"button\" data-settings-tab-button=\"hotkeys\" class=\"settings-tab",
    hotkeysActive,
    "\" onclick=\"switchSettingsTab('hotkeys')\">Hotkeys</button>\n        </div>\n        <div class=\"settings-tools\">\n          <input class=\"hotkey-search\" type=\"text\" value=\"",
    escapeHtml(ctx.search or ""),
    "\" placeholder=\"Search hotkeys\" oninput=\"handleSearchInput(this.value)\">\n          ",
    headerGlyphButtonHtml({
      className = "settings-restore-btn",
      glyph = "↺",
      tooltip = "Reset All",
      onclick = "resetAllHotkeys()",
    }),
    "\n        </div>\n      </div>\n      <div class=\"header-tooltip\" aria-hidden=\"true\"></div>\n      <div class=\"settings-scroll\">\n",
    generalTabHtml(ctx.config),
    hotkeysTabHtml(ctx),
    "      </div>\n",
    remapModalHtml(),
    "    </div>\n  </div>\n<script>\nwindow.tapshopSettingsLayoutPolicy = ",
    hs.json.encode(ctx.layoutPolicy or {}) or "{}",
    ";\nwindow.tapshopSystemKeyDisplay = ",
    hs.json.encode(icons.systemKeyDisplayJsData()) or "{}",
    ";\n",
    ctx.script,
    "\n</script>\n</body>\n</html>",
  }

  return table.concat(parts)
end

return Render
