local Styles = {}

function Styles.buildTheme(cfg)
  local opacityPercent = math.floor((cfg.popoverBackgroundOpacity or 0.85) * 100 + 0.5)

  return {
    opacityPercent = opacityPercent,
    popoverBgCss = string.format("rgba(24, 24, 24, %.2f)", opacityPercent / 100),
    spacing = {
      container = "10px",
      shellGap = "6px",
      headerGap = "10px",
      headerPaddingBottom = "7px",
      titleWrapGap = "8px",
      headerDetailsGap = "3px",
      headerActionsGap = "6px",
      rowGap = "4px",
      listGap = "3px",
      slotLabelGap = "6px",
      slotNumMarginRight = "8px",
      pillX = "8px",
      pillY = "2px",
      minBadgeX = "5px",
      minBadgeY = "1px",
      buttonX = "11px",
      buttonY = "4px",
      headerButtonX = "12px",
      headerButtonY = "5px",
      configPanelMarginTop = "6px",
      configPanelX = "10px",
      configPanelY = "8px",
      configItemGap = "7px",
      configSliderGap = "4px",
      configSliderMarginTop = "8px",
      configSliderRowGap = "6px",
      configTriggerX = "10px",
      configTriggerY = "5px",
      tooltipX = "6px",
      tooltipY = "3px",
    },
    sizing = {
      slotNumWidth = "18px",
      headerActionWidth = "30px",
      headerActionHeight = "26px",
      headerIconSize = "14px",
      configPanelMinWidth = "180px",
      configPanelMaxWidthInset = "24px",
    },
    radius = {
      panel = "12px",
      button = "4px",
      configPanel = "6px",
      pill = "999px",
      tooltip = "5px",
    },
    typography = {
      body = "13px",
      title = "14px",
      headerPrimary = "11px",
      headerSecondary = "7px",
      slot = "12px",
      slotNum = "11px",
      minBadge = "9px",
      button = "11px",
      tooltip = "10px",
    },
    colors = {
      textBase = "#e0e0e0",
      textPrimary = "#fff",
      textMuted = "#9aa0a6",
      textClose = "#777",
      textCloseHover = "#aaa",
      textConfig = "#d2d2d2",
      textConfigHover = "#f0f0f0",
      textConfigItem = "#c6c6c6",
      textButtonMuted = "#bbb",
      textTooltip = "#f5f7fa",
      textDebugLabel = "#111",
      paired = "#7ec87e",
      pairedMinimized = "#e7c84f",
      unpaired = "#555",
      surfacePanel = string.format("rgba(24, 24, 24, %.2f)", opacityPercent / 100),
      surfacePill = "rgba(0, 0, 0, 0.14)",
      surfacePrimary = "#2d6ee6",
      surfacePrimaryHover = "#4080f0",
      surfaceNeutral = "#444",
      surfaceNeutralHover = "#555",
      surfaceDanger = "#a03020",
      surfaceDangerHover = "#c04030",
      surfaceClose = "#2a2a2a",
      surfaceCloseHover = "#3a3a3a",
      surfaceConfig = "#4b4b4b",
      surfaceConfigHover = "#5a5a5a",
      surfaceTooltip = "rgba(10, 10, 10, 0.94)",
      surfaceConfigPanel = "#171717",
      borderPanel = "rgba(255, 255, 255, 0.06)",
      borderConfigPanel = "#3c3c3c",
      borderMinBadge = "rgba(231, 200, 79, 0.32)",
      bgMinBadge = "rgba(231, 200, 79, 0.16)",
      focusRing = "rgba(120, 168, 255, 0.92)",
    },
    effects = {
      panelShadow = "inset 0 1px 0 rgba(255, 255, 255, 0.04)",
      configPanelShadow = "0 12px 24px rgba(0, 0, 0, 0.45)",
      backdrop = "blur(10px) saturate(115%)",
      pillBackdrop = "blur(1.5px)",
      transitionFast = "opacity 0.12s",
      tooltipTransition = "opacity 0.12s ease",
    },
    zIndex = {
      configPanel = "5",
      tooltip = "6",
      debugLabel = "2",
    },
  }
end

local function rootVars(theme)
  local c = theme.colors
  local opacity = math.max(0.40, (theme.opacityPercent or 85) / 100)

  return [=[
:root {
  --ui-scale: 1;
  --panel-bg: ]=] .. string.format("rgba(20, 20, 20, %.2f)", opacity) .. [=[;
  --panel-overlay: rgba(12, 12, 12, 0.72);
  --line: rgba(255, 255, 255, 0.08);
  --line-strong: rgba(255, 255, 255, 0.16);
  --text: ]=] .. c.textBase .. [=[;
  --text-strong: ]=] .. c.textPrimary .. [=[;
  --text-muted: ]=] .. c.textMuted .. [=[;
  --accent: ]=] .. c.surfacePrimary .. [=[;
  --accent-hover: ]=] .. c.surfacePrimaryHover .. [=[;
  --danger: ]=] .. c.surfaceDanger .. [=[;
  --danger-hover: ]=] .. c.surfaceDangerHover .. [=[;
  --warning: #d7a94b;
  --conflict: #bc5349;
  --focus: rgba(120, 168, 255, 0.92);
  --tooltip-bg: rgba(10, 10, 10, 0.94);
  --resize-ring: 3px;
  --resize-edge-inset: 3px;
  --resize-corner: calc(var(--resize-ring) + var(--resize-edge-inset));
}
]=]
end

function Styles.buildCss(theme)
  return table.concat({
    rootVars(theme),
    [=[
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html, body {
  width: 100%;
  height: 100%;
}

body {
  position: relative;
  /* Outer resize ring on free sides; no top ring so chrome stays flush. */
  padding: 0 var(--resize-ring) var(--resize-ring);
  background: transparent;
  color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  font-size: calc(12px * var(--ui-scale));
  -webkit-user-select: none;
  overflow: hidden;
}

button,
input {
  font: inherit;
}

.container {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: calc(4px * var(--ui-scale));
  height: 100%;
  padding: calc(6px * var(--ui-scale));
  background: var(--panel-bg);
  border: 1px solid var(--line);
  border-radius: 12px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
  -webkit-backdrop-filter: blur(10px) saturate(115%);
  backdrop-filter: blur(10px) saturate(115%);
  overflow: hidden;
}

.header {
  display: flex;
  align-items: flex-start;
  gap: calc(4px * var(--ui-scale));
  padding-bottom: calc(4px * var(--ui-scale));
  border-bottom: 1px solid #333;
  flex: 0 0 auto;
}

.title-wrap {
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
  align-self: stretch;
}

.title-logo {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: calc(20px * var(--ui-scale));
  height: calc(20px * var(--ui-scale));
  padding: 0;
  background: transparent;
  border: none;
  border-radius: calc(6px * var(--ui-scale));
  cursor: pointer;
  transform-origin: center bottom;
  transition: transform 90ms ease;
}

.title-logo.is-pressed {
  transform: translateY(calc(1.5px * var(--ui-scale))) scale(0.97);
}

.title-logo.is-hopping {
  animation: hop-cartoon 700ms cubic-bezier(0.22, 1, 0.36, 1);
}

.title-brand-icon {
  width: 100%;
  height: 100%;
  border-radius: calc(6px * var(--ui-scale));
  flex-shrink: 0;
  pointer-events: none;
}

@keyframes hop-cartoon {
  0% { transform: translateY(0) scaleX(1) scaleY(1); }
  12% { transform: translateY(1px) scaleX(1.15) scaleY(0.84); }
  32% { transform: translateY(calc(-11px * var(--ui-scale))) scaleX(0.88) scaleY(1.18); }
  46% { transform: translateY(calc(-16px * var(--ui-scale))) scaleX(0.96) scaleY(1.06); }
  64% { transform: translateY(0) scaleX(1.1) scaleY(0.88); }
  76% { transform: translateY(calc(-5px * var(--ui-scale))) scaleX(0.97) scaleY(1.04); }
  100% { transform: translateY(0) scaleX(1) scaleY(1); }
}

.header-active-win {
  display: flex;
  align-items: center;
  gap: calc(2px * var(--ui-scale));
  flex: 1 1 auto;
  min-width: 0;
  min-height: calc(20px * var(--ui-scale));
  padding: 0 calc(2px * var(--ui-scale));
  font-size: calc(11px * var(--ui-scale));
  font-weight: 600;
  color: var(--text-strong);
  background: rgba(255, 255, 255, 0.06);
  border-radius: calc(4px * var(--ui-scale));
  overflow: hidden;
}

.header-active-win-title {
  display: block;
  min-width: 0;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.2;
}

.header-active-win-icon {
  width: calc(18px * var(--ui-scale));
  height: calc(18px * var(--ui-scale));
  border-radius: calc(4px * var(--ui-scale));
  flex-shrink: 0;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: calc(4px * var(--ui-scale));
  margin-left: auto;
  flex-shrink: 0;
  border-radius: calc(4px * var(--ui-scale));
}

.profile-switcher {
  display: inline-flex;
  align-items: center;
  gap: calc(2px * var(--ui-scale));
  padding: calc(1px * var(--ui-scale));
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: calc(5px * var(--ui-scale));
}

.profile-btn,
.profile-label {
  border: none;
  border-radius: calc(3px * var(--ui-scale));
  color: var(--text-strong);
}

.profile-btn {
  min-width: calc(16px * var(--ui-scale));
  height: calc(16px * var(--ui-scale));
  padding: 0 calc(3px * var(--ui-scale));
  background: rgba(255, 255, 255, 0.06);
  cursor: pointer;
  line-height: 1;
}

.profile-btn:hover,
.profile-btn.is-pointer-hover {
  background: rgba(255, 255, 255, 0.14);
}

.profile-label {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: calc(24px * var(--ui-scale));
  height: calc(16px * var(--ui-scale));
  padding: 0 calc(4px * var(--ui-scale));
  background: transparent;
  font-size: calc(9px * var(--ui-scale));
  font-weight: 700;
  letter-spacing: 0.02em;
}

.header-btn,
.btn,
.settings-tab {
  border: none;
  border-radius: calc(4px * var(--ui-scale));
  cursor: pointer;
  transition: background 120ms ease, color 120ms ease, opacity 120ms ease, border-color 120ms ease;
}

.header-btn {
  width: calc(24px * var(--ui-scale));
  height: calc(20px * var(--ui-scale));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}

.header-btn:focus-visible,
.profile-btn:focus-visible,
.btn:focus-visible,
.settings-tab:focus-visible,
.hotkey-search:focus-visible {
  outline: none;
  box-shadow: 0 0 0 1px var(--focus);
}

.header-danger {
  background: var(--danger);
  color: var(--text-strong);
}

.header-danger:hover,
.header-danger.is-pointer-hover {
  background: var(--danger-hover);
}

.header-config {
  background: #4b4b4b;
  color: #d2d2d2;
}

.header-config:hover,
.header-config.is-pointer-hover {
  background: #5a5a5a;
  color: #fff;
}

.header-close {
  background: #2a2a2a;
  color: #777;
}

.header-close:hover,
.header-close.is-pointer-hover {
  background: #3a3a3a;
  color: #aaa;
}

.settings-restore-btn {
  background: rgba(255, 255, 255, 0.06);
  color: var(--text-muted);
}

.settings-restore-btn:hover {
  background: rgba(255, 255, 255, 0.12);
  color: var(--text-strong);
}

.header-action-icon {
  width: calc(11px * var(--ui-scale));
  height: calc(11px * var(--ui-scale));
  display: block;
  stroke: currentColor;
  fill: none;
  pointer-events: none;
}

.header-tooltip {
  position: absolute;
  top: 0;
  left: 0;
  padding: calc(3px * var(--ui-scale)) calc(6px * var(--ui-scale));
  border-radius: 5px;
  background: var(--tooltip-bg);
  color: #f5f7fa;
  font-size: calc(10px * var(--ui-scale));
  line-height: 1;
  white-space: nowrap;
  pointer-events: none;
  opacity: 0;
  visibility: hidden;
  transition: opacity 120ms ease;
  z-index: 30;
}

.header-tooltip.is-visible {
  opacity: 1;
  visibility: visible;
}

.body-shell {
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
}

.workspace-list {
  position: relative;
  display: grid;
  grid-template-rows: repeat(9, auto);
  gap: calc(3px * var(--ui-scale));
  align-content: start;
  transition: opacity 90ms ease;
}

.workspace-list.is-dimmed {
  opacity: 0.18;
  pointer-events: none;
}

.row {
  display: flex;
  align-items: center;
  gap: calc(4px * var(--ui-scale));
  border-radius: calc(5px * var(--ui-scale));
  transition: background 90ms ease, box-shadow 90ms ease;
}

.row:has(.slot-icon-btn:hover),
.row:has(.slot-icon-btn.is-pointer-hover),
.row.is-pointer-hover,
.row:has(.slot-icon-btn:focus-visible) {
  background: rgba(255, 255, 255, 0.07);
  box-shadow: inset 0 0 0 1px rgba(120, 215, 255, 0.42);
}

/* Always-on-top utility overlay: ignore native :hover (often sticky/wrong on
   non-key WKWebViews). Pointer hover classes are authoritative. */
body.is-utility-overlay .row:has(.slot-icon-btn:hover) {
  background: transparent;
  box-shadow: none;
}
body.is-utility-overlay .row:has(.slot-icon-btn.is-pointer-hover),
body.is-utility-overlay .row.is-pointer-hover {
  background: rgba(255, 255, 255, 0.07);
  box-shadow: inset 0 0 0 1px rgba(120, 215, 255, 0.42);
}

body.is-utility-overlay .profile-btn:hover {
  background: rgba(255, 255, 255, 0.06);
}
body.is-utility-overlay .profile-btn.is-pointer-hover {
  background: rgba(255, 255, 255, 0.14);
}
body.is-utility-overlay .header-danger:hover {
  background: var(--danger);
  color: var(--text-strong);
}
body.is-utility-overlay .header-danger.is-pointer-hover {
  background: var(--danger-hover);
}
body.is-utility-overlay .header-config:hover {
  background: #4b4b4b;
  color: #d2d2d2;
}
body.is-utility-overlay .header-config.is-pointer-hover {
  background: #5a5a5a;
  color: #fff;
}
body.is-utility-overlay .header-close:hover {
  background: #2a2a2a;
  color: #777;
}
body.is-utility-overlay .header-close.is-pointer-hover {
  background: #3a3a3a;
  color: #aaa;
}
body.is-utility-overlay .btn-primary:hover {
  background: var(--accent);
  color: var(--text-strong);
}
body.is-utility-overlay .btn-primary.is-pointer-hover {
  background: var(--accent-hover);
}
body.is-utility-overlay .btn-unpair:hover {
  background: #444;
  color: #bbb;
}
body.is-utility-overlay .btn-unpair.is-pointer-hover {
  background: #555;
}
body.is-utility-overlay .btn-danger:hover {
  background: rgba(220, 80, 80, 0.22);
  color: #ff9a9a;
}
body.is-utility-overlay .btn-danger.is-pointer-hover {
  background: rgba(220, 80, 80, 0.34);
  color: #ffc0c0;
}

.slot-num {
  display: flex;
  align-items: center;
  justify-content: center;
  width: calc(14px * var(--ui-scale));
  height: calc(14px * var(--ui-scale));
  color: var(--text-strong);
  font-size: calc(11px * var(--ui-scale));
  font-weight: 600;
  flex-shrink: 0;
}

.slot-label {
  display: flex;
  align-items: center;
  gap: calc(4px * var(--ui-scale));
  flex: 1 1 0;
  width: 0;
  min-width: 0;
  overflow: hidden;
  font-size: calc(11px * var(--ui-scale));
}

.slot-text-bg {
  display: inline-flex;
  align-items: center;
  gap: calc(4px * var(--ui-scale));
  max-width: 100%;
  overflow: hidden;
  padding: 0 calc(4px * var(--ui-scale));
  background: rgba(0, 0, 0, 0.14);
  border-radius: calc(4px * var(--ui-scale));
  min-width: 0;
}

.slot-app-icon {
  width: calc(15px * var(--ui-scale));
  height: calc(15px * var(--ui-scale));
  border-radius: calc(4px * var(--ui-scale));
  flex-shrink: 0;
  pointer-events: none;
}

.slot-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin: 0;
  padding: 0;
  border: none;
  background: transparent;
  border-radius: calc(4px * var(--ui-scale));
  cursor: pointer;
  flex-shrink: 0;
  line-height: 0;
}

.slot-icon-btn:focus-visible {
  outline: none;
}

.slot-icon-btn:hover .slot-app-icon:not(.is-muted),
.slot-icon-btn.is-pointer-hover .slot-app-icon:not(.is-muted) {
  filter: brightness(1.12);
}

body.is-utility-overlay .slot-icon-btn:hover .slot-app-icon:not(.is-muted) {
  filter: none;
}
body.is-utility-overlay .slot-icon-btn.is-pointer-hover .slot-app-icon:not(.is-muted) {
  filter: brightness(1.12);
}
body.is-utility-overlay .slot-icon-btn.is-pointer-hover .slot-app-icon.is-muted {
  filter: grayscale(1) saturate(0);
}

.slot-app-icon.is-muted {
  filter: grayscale(1) saturate(0);
  opacity: 0.68;
}

.slot-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.slot-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: calc(1px * var(--ui-scale)) calc(5px * var(--ui-scale));
  border-radius: 999px;
  font-size: calc(9px * var(--ui-scale));
  font-weight: 700;
  flex-shrink: 0;
}

.slot-badge.is-minimized {
  background: rgba(231, 200, 79, 0.16);
  border: 1px solid rgba(231, 200, 79, 0.32);
  color: #e7c84f;
}

.slot-badge.is-fullscreen {
  background: rgba(120, 215, 255, 0.16);
  border: 1px solid rgba(120, 215, 255, 0.32);
  color: #78d7ff;
}

.slot-buttons {
  display: flex;
  gap: calc(4px * var(--ui-scale));
  margin-left: auto;
  flex-shrink: 0;
}

.slot-buttons .btn {
  padding: calc(3px * var(--ui-scale)) calc(6px * var(--ui-scale));
  font-size: calc(8px * var(--ui-scale));
  font-weight: 500;
  white-space: nowrap;
}

.btn {
  padding: calc(4px * var(--ui-scale)) calc(11px * var(--ui-scale));
  font-size: calc(11px * var(--ui-scale));
  font-weight: 500;
  white-space: nowrap;
}

.btn-primary {
  background: var(--accent);
  color: var(--text-strong);
}

.btn-primary:hover,
.btn-primary.is-pointer-hover {
  background: var(--accent-hover);
}

.btn-unpair {
  background: #444;
  color: #bbb;
}

.btn-unpair:hover,
.btn-unpair.is-pointer-hover {
  background: #555;
}

.btn-unpair.off {
  opacity: 0.25;
  pointer-events: none;
}

.btn-danger {
  background: rgba(220, 80, 80, 0.22);
  color: #ff9a9a;
  border: 1px solid rgba(220, 80, 80, 0.35);
}

.btn-danger:hover,
.btn-danger.is-pointer-hover {
  background: rgba(220, 80, 80, 0.34);
  color: #ffc0c0;
}

.confirm-shell[hidden] {
  display: none;
}

.resize-handles {
  position: absolute;
  inset: 0;
  z-index: 20;
  pointer-events: none;
}

.resize-handles.is-disabled {
  visibility: hidden;
}

.resize-handle {
  position: absolute;
  pointer-events: auto;
  background: transparent;
}

/* Edge strips live in the outer ring and bite 3px into the panel. */
.resize-s {
  left: var(--resize-ring);
  right: var(--resize-ring);
  bottom: 0;
  height: calc(var(--resize-ring) + var(--resize-edge-inset));
}

.resize-e,
.resize-w {
  top: 0;
  bottom: var(--resize-ring);
  width: calc(var(--resize-ring) + var(--resize-edge-inset));
}

.resize-e { right: 0; }
.resize-w { left: 0; }

.resize-sw,
.resize-se {
  width: var(--resize-corner);
  height: var(--resize-corner);
  z-index: 21;
}

.resize-sw { left: 0; bottom: 0; }
.resize-se { right: 0; bottom: 0; }

.confirm-shell {
  position: absolute;
  inset: 0;
  z-index: 30;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: calc(8px * var(--ui-scale));
}

.confirm-backdrop {
  position: absolute;
  inset: 0;
  border: none;
  border-radius: inherit;
  background: rgba(0, 0, 0, 0.42);
  cursor: default;
}

.confirm-dialog {
  position: relative;
  z-index: 1;
  width: min(calc(220px * var(--ui-scale)), 100%);
  display: flex;
  flex-direction: column;
  gap: calc(10px * var(--ui-scale));
  padding: calc(10px * var(--ui-scale)) calc(12px * var(--ui-scale));
  border: 1px solid var(--line-strong);
  border-radius: calc(10px * var(--ui-scale));
  background: rgba(22, 22, 22, 0.98);
  box-shadow: 0 12px 28px rgba(0, 0, 0, 0.45);
}

.confirm-title {
  color: var(--text-strong);
  font-size: calc(12px * var(--ui-scale));
  font-weight: 600;
  text-align: center;
  line-height: 1.3;
}

.confirm-actions {
  display: flex;
  align-items: center;
  justify-content: stretch;
  gap: calc(6px * var(--ui-scale));
}

.confirm-actions .btn {
  flex: 1 1 0;
  padding: calc(5px * var(--ui-scale)) calc(8px * var(--ui-scale));
  font-size: calc(11px * var(--ui-scale));
  font-weight: 600;
}

.confirm-cancel {
  background: rgba(255, 255, 255, 0.08);
  color: #bbb;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.confirm-cancel:hover {
  background: rgba(255, 255, 255, 0.14);
  color: #e8e8e8;
}

.confirm-ok {
  background: var(--danger);
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.confirm-ok:hover {
  background: var(--danger-hover);
  color: #fff;
}

.paired { color: #7ec87e; }
.paired-minimized { color: #e7c84f; }
.paired-fullscreen { color: #78d7ff; }
.paired-off-space { color: #f0f0f0; }
.paired-unresolved { color: #ff7a7a; }
.recoverable { color: #555; }
.unpaired { color: #555; font-style: italic; }

.settings-sheet {
  position: absolute;
  inset: 0;
  display: none;
  flex-direction: column;
  gap: calc(6px * var(--ui-scale));
  min-height: 0;
  padding: calc(6px * var(--ui-scale));
  border: 1px solid var(--line-strong);
  border-radius: 9px;
  background: var(--panel-overlay);
}

.settings-sheet.is-open {
  display: flex;
}

.settings-head {
  display: flex;
  align-items: center;
  gap: calc(6px * var(--ui-scale));
  flex: 0 0 auto;
}

.settings-back-btn {
  padding: calc(4px * var(--ui-scale)) calc(7px * var(--ui-scale));
  font-size: calc(10px * var(--ui-scale));
  background: rgba(255, 255, 255, 0.06);
  color: var(--text-muted);
}

.settings-back-btn:hover {
  background: rgba(255, 255, 255, 0.12);
  color: var(--text-strong);
}

.settings-head-main {
  display: flex;
  align-items: center;
  gap: calc(6px * var(--ui-scale));
  flex: 1 1 auto;
  min-width: 0;
}

.settings-tabs {
  display: inline-flex;
  align-items: center;
  gap: calc(4px * var(--ui-scale));
  padding: calc(2px * var(--ui-scale));
  background: rgba(0, 0, 0, 0.24);
  border: 1px solid var(--line);
  border-radius: 999px;
  flex-shrink: 0;
}

.settings-tab {
  background: transparent;
  color: var(--text-muted);
  padding: calc(4px * var(--ui-scale)) calc(10px * var(--ui-scale));
  font-size: calc(10px * var(--ui-scale));
  border-radius: 999px;
}

.settings-tab.is-active {
  background: rgba(255, 255, 255, 0.1);
  color: var(--text-strong);
}

.settings-tools {
  display: flex;
  align-items: center;
  gap: calc(5px * var(--ui-scale));
  margin-left: auto;
  min-width: 0;
}

.hotkey-search {
  width: calc(142px * var(--ui-scale));
  min-width: 0;
  border: 1px solid var(--line);
  border-radius: 7px;
  background: rgba(0, 0, 0, 0.24);
  color: var(--text-strong);
  padding: calc(5px * var(--ui-scale)) calc(8px * var(--ui-scale));
  font-size: calc(10px * var(--ui-scale));
}

.settings-restore-btn {
  width: calc(26px * var(--ui-scale));
  height: calc(24px * var(--ui-scale));
}

body[data-settings-tab="general"] .settings-tools {
  opacity: 0;
  pointer-events: none;
}

.settings-scroll {
  position: relative;
  flex: 1 1 auto;
  min-height: 0;
  overflow: hidden;
}

.settings-panel {
  display: none;
  height: 100%;
  overflow: auto;
  padding-right: calc(2px * var(--ui-scale));
}

body[data-settings-tab="general"] .settings-panel[data-settings-panel="general"],
body[data-settings-tab="hotkeys"] .settings-panel[data-settings-panel="hotkeys"] {
  display: block;
}

.settings-item,
.settings-slider-block {
  display: flex;
  align-items: center;
  gap: calc(8px * var(--ui-scale));
  padding: calc(8px * var(--ui-scale)) calc(9px * var(--ui-scale));
  margin-bottom: calc(6px * var(--ui-scale));
  border: 1px solid var(--line);
  border-radius: 9px;
  background: rgba(255, 255, 255, 0.04);
}

.settings-item {
  cursor: pointer;
}

.settings-item input {
  accent-color: var(--accent);
}

.settings-slider-block {
  align-items: center;
}

.settings-slider-inline {
  gap: calc(10px * var(--ui-scale));
  padding-top: calc(6px * var(--ui-scale));
  padding-bottom: calc(6px * var(--ui-scale));
}

.settings-slider-label {
  flex: 0 0 auto;
  font-size: calc(11px * var(--ui-scale));
  color: var(--text-strong);
  line-height: 1.2;
  white-space: nowrap;
}

.settings-slider-control {
  position: relative;
  flex: 1 1 auto;
  min-width: calc(92px * var(--ui-scale));
  display: flex;
  align-items: center;
  min-height: calc(18px * var(--ui-scale));
}

.settings-slider {
  position: relative;
  z-index: 2;
  display: block;
  width: 100%;
  height: calc(18px * var(--ui-scale));
  margin: 0;
  background: transparent;
  -webkit-appearance: none;
  appearance: none;
}

.settings-slider::-webkit-slider-runnable-track {
  height: calc(4px * var(--ui-scale));
  border: 1px solid var(--line);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.12);
}

.settings-slider::-webkit-slider-thumb {
  width: calc(12px * var(--ui-scale));
  height: calc(12px * var(--ui-scale));
  margin-top: calc(-5px * var(--ui-scale));
  border: 1px solid rgba(255, 255, 255, 0.55);
  border-radius: 999px;
  background: var(--accent);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
  -webkit-appearance: none;
  appearance: none;
}

.settings-slider::-moz-range-track {
  height: calc(4px * var(--ui-scale));
  border: 1px solid var(--line);
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.12);
}

.settings-slider::-moz-range-thumb {
  width: calc(12px * var(--ui-scale));
  height: calc(12px * var(--ui-scale));
  border: 1px solid rgba(255, 255, 255, 0.55);
  border-radius: 999px;
  background: var(--accent);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.35);
}

.settings-slider-ticks {
  position: absolute;
  left: calc(6px * var(--ui-scale));
  right: calc(6px * var(--ui-scale));
  top: 50%;
  display: flex;
  justify-content: space-between;
  pointer-events: none;
  transform: translateY(-50%);
  z-index: 1;
}

.settings-slider-ticks span {
  width: 1px;
  height: calc(10px * var(--ui-scale));
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.28);
}

.hotkeys-helper {
  margin-bottom: calc(6px * var(--ui-scale));
  color: var(--text-muted);
  font-size: calc(9px * var(--ui-scale));
  line-height: 1.3;
}

.hotkeys-error {
  margin-bottom: calc(6px * var(--ui-scale));
  padding: calc(6px * var(--ui-scale)) calc(8px * var(--ui-scale));
  border-radius: 7px;
  border: 1px solid rgba(188, 83, 73, 0.4);
  background: rgba(188, 83, 73, 0.14);
  color: #ffd5d0;
  font-size: calc(9px * var(--ui-scale));
}

.hotkeys-error.is-hidden {
  display: none;
}

.hotkeys-list {
  display: flex;
  flex-direction: column;
  gap: calc(7px * var(--ui-scale));
}

.hotkey-group {
  display: flex;
  flex-direction: column;
  gap: calc(4px * var(--ui-scale));
}

.hotkey-group.is-hidden {
  display: none;
}

.hotkey-group-title {
  padding: 0 calc(2px * var(--ui-scale));
  color: var(--text-muted);
  font-size: calc(9px * var(--ui-scale));
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.hotkey-row {
  display: flex;
  align-items: center;
  gap: calc(8px * var(--ui-scale));
  padding: calc(6px * var(--ui-scale)) calc(8px * var(--ui-scale));
  border: 1px solid var(--line);
  border-left: 2px solid transparent;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.04);
}

.hotkey-row.is-hidden {
  display: none;
}

.hotkey-row.is-modified {
  border-left-color: rgba(255, 255, 255, 0.22);
}

.hotkey-row.has-conflict {
  border-color: rgba(188, 83, 73, 0.55);
  background: rgba(188, 83, 73, 0.12);
}

.hotkey-row.has-live-conflict {
  border-color: rgba(188, 83, 73, 0.55);
  background: rgba(188, 83, 73, 0.12);
}

.hotkey-row.is-unavailable,
.hotkey-row.has-warning {
  border-color: rgba(215, 169, 75, 0.35);
}

.hotkey-main {
  display: flex;
  align-items: center;
  gap: calc(8px * var(--ui-scale));
  flex: 1 1 auto;
  min-width: 0;
}

.hotkey-label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text-strong);
  font-size: calc(10px * var(--ui-scale));
}

.hotkey-combo,
.remap-preview-combo {
  display: inline-flex;
  align-items: center;
  gap: calc(3px * var(--ui-scale));
  flex-wrap: wrap;
  width: fit-content;
  max-width: 100%;
  min-height: calc(24px * var(--ui-scale));
  padding: calc(3px * var(--ui-scale));
  border: 1px solid var(--line);
  border-radius: 7px;
  background: rgba(255, 255, 255, 0.04);
}

.hotkey-combo-empty,
.remap-preview-combo.is-empty {
  display: inline-flex;
  align-items: center;
  padding: 0;
  min-height: 0;
  border: none;
  background: transparent;
}

.hotkey-unset {
  color: var(--text-muted);
  font-size: calc(10px * var(--ui-scale));
  line-height: 1.2;
  font-style: italic;
}

.keycap {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: calc(20px * var(--ui-scale));
  padding: calc(3px * var(--ui-scale)) calc(6px * var(--ui-scale));
  border: 1px solid var(--line);
  border-bottom-color: rgba(255, 255, 255, 0.2);
  border-radius: 6px;
  background: rgba(255, 255, 255, 0.08);
  color: var(--text-strong);
  font-size: calc(9px * var(--ui-scale));
  line-height: 1;
}

.hotkey-actions,
.remap-actions {
  display: inline-flex;
  align-items: center;
  gap: calc(5px * var(--ui-scale));
  flex-shrink: 0;
}

.hotkey-btn {
  background: rgba(255, 255, 255, 0.08);
  color: var(--text-strong);
  padding: calc(3px * var(--ui-scale)) calc(8px * var(--ui-scale));
  font-size: calc(10px * var(--ui-scale));
}

.hotkey-btn:hover {
  background: rgba(255, 255, 255, 0.14);
}

.hotkey-reset-btn {
  color: rgba(255, 255, 255, 0.92);
  font-size: calc(12px * var(--ui-scale));
  padding: calc(1px * var(--ui-scale)) calc(6px * var(--ui-scale));
  font-weight: bold;
}

.hotkey-reset-btn:hover {
  color: #ffffff;
}

.remap-modal-shell[hidden] {
  display: none;
}

.remap-modal-shell {
  position: absolute;
  inset: 0;
  z-index: 20;
}

.remap-modal-backdrop {
  position: absolute;
  inset: 0;
  border: none;
  background: rgba(0, 0, 0, 0.32);
  cursor: default;
}

.remap-modal {
  position: absolute;
  top: 50%;
  left: 50%;
  width: min(calc(320px * var(--ui-scale)), calc(100% - 20px));
  transform: translate(-50%, -50%);
  display: flex;
  flex-direction: column;
  gap: calc(10px * var(--ui-scale));
  padding: calc(12px * var(--ui-scale));
  border: 1px solid var(--line-strong);
  border-radius: 12px;
  background: rgba(18, 18, 18, 0.98);
  box-shadow: 0 18px 36px rgba(0, 0, 0, 0.45);
}

.remap-modal-label {
  color: var(--text-strong);
  font-size: calc(12px * var(--ui-scale));
  font-weight: 600;
}

.remap-preview-row {
  display: flex;
  flex-direction: column;
  gap: calc(6px * var(--ui-scale));
}

.remap-preview-title {
  color: var(--text-muted);
  font-size: calc(10px * var(--ui-scale));
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.remap-save-btn[disabled] {
  opacity: 0.45;
  pointer-events: none;
}
]=],
  })
end

return Styles
