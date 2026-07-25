local ClientScript = {}

ClientScript.script = [=[
var HARD_MIN_UI_SCALE_FLOOR = 0.6;
var MAX_UI_SCALE = 1.75;
var TITLE_TAP_WINDOW_MS = 650;
var lastReportedBounds = null;

function layoutPolicy() {
  return window.tapshopLayoutPolicy || {};
}

function sendAction(action, extra) {
  var payload = extra || {};
  payload.action = action;
  if (payload.slot == null) payload.slot = 0;
  if (payload.dx == null) payload.dx = 0;
  if (payload.dy == null) payload.dy = 0;
  if (payload.dw == null) payload.dw = 0;
  if (payload.dh == null) payload.dh = 0;
  if (payload.direction == null) payload.direction = "";
  window.webkit.messageHandlers.tapshop.postMessage(payload);
}

function focusKeyboardSurface() {
  if (document.body && document.body.classList.contains("is-utility-overlay")) return;
  if (!document.body || typeof document.body.focus !== "function") return;
  try {
    document.body.focus({ preventScroll: true });
  } catch (_) {
    document.body.focus();
  }
}

function setUiScale(scale) {
  document.documentElement.style.setProperty("--ui-scale", scale.toFixed(3));
}

function readPx(value) {
  return parseFloat(value || "0") || 0;
}

function resizeRingVerticalPx() {
  var bodyStyle = window.getComputedStyle(document.body);
  return readPx(bodyStyle.paddingTop) + readPx(bodyStyle.paddingBottom);
}

function measureContainerChromeHeight(scale) {
  var container = document.querySelector(".container");
  var header = document.querySelector(".header");
  if (!container || !header) return 0;

  setUiScale(scale);
  void container.offsetHeight;

  var containerStyle = window.getComputedStyle(container);
  var containerGap = readPx(containerStyle.rowGap || containerStyle.gap);
  return readPx(containerStyle.paddingTop)
    + readPx(containerStyle.paddingBottom)
    + readPx(containerStyle.borderTopWidth)
    + readPx(containerStyle.borderBottomWidth)
    + header.getBoundingClientRect().height
    + containerGap
    + resizeRingVerticalPx();
}

function measureWorkspaceHeightAtScale(scale) {
  var workspaceList = document.querySelector(".workspace-list:not([hidden])")
    || document.querySelector(".body-shell.is-profiles-mode .is-profiles-list")
    || document.querySelector(".body-shell.is-slots-mode .is-slots-list")
    || document.querySelector(".workspace-list");
  var total = measureContainerChromeHeight(scale);
  if (!total) return 0;
  if (!workspaceList) return total;
  return total + workspaceList.getBoundingClientRect().height;
}

function readLiveLayoutMetrics() {
  var bodyShell = document.querySelector(".body-shell");
  var workspaceList = document.querySelector(".workspace-list:not([hidden])")
    || document.querySelector(".body-shell.is-profiles-mode .is-profiles-list")
    || document.querySelector(".body-shell.is-slots-mode .is-slots-list")
    || document.querySelector(".workspace-list");
  return {
    bodyShellHeight: bodyShell ? bodyShell.getBoundingClientRect().height : 0,
    workspaceListHeight: workspaceList ? workspaceList.getBoundingClientRect().height : 0
  };
}

function solveScaleForHeight(targetHeight, minScale, maxScale, measureFn) {
  var lowScale = Math.min(minScale, maxScale);
  var highScale = Math.max(minScale, maxScale);
  var lowHeight = measureFn(lowScale);
  var highHeight = measureFn(highScale);

  if (!lowHeight || !highHeight) {
    return {
      scale: lowScale,
      height: lowHeight || 0,
      clamped: true
    };
  }

  if (targetHeight <= lowHeight) {
    return {
      scale: lowScale,
      height: lowHeight,
      clamped: true
    };
  }

  if (targetHeight >= highHeight) {
    return {
      scale: highScale,
      height: highHeight,
      clamped: true
    };
  }

  var bestScale = lowScale;
  var bestHeight = lowHeight;
  var bestDiff = Math.abs(targetHeight - lowHeight);

  for (var i = 0; i < 18; i += 1) {
    var midScale = (lowScale + highScale) / 2;
    var midHeight = measureFn(midScale);
    var midDiff = Math.abs(targetHeight - midHeight);

    if (midDiff < bestDiff) {
      bestScale = midScale;
      bestHeight = midHeight;
      bestDiff = midDiff;
    }

    if (midHeight < targetHeight) {
      lowScale = midScale;
    } else {
      highScale = midScale;
    }
  }

  return {
    scale: bestScale,
    height: bestHeight,
    clamped: false
  };
}

function targetMinHeight() {
  var policy = layoutPolicy();
  if (typeof policy.targetMinHeight === "number") {
    return policy.targetMinHeight;
  }
  return 150;
}

function computeVerticalSizingModel() {
  var measureFn = measureWorkspaceHeightAtScale;
  var minHeight = targetMinHeight();
  var floorHeight = measureFn(HARD_MIN_UI_SCALE_FLOOR);
  var maxHeightAtScale = measureFn(MAX_UI_SCALE);
  if (!floorHeight || !maxHeightAtScale) {
    return null;
  }

  if (MAX_UI_SCALE <= HARD_MIN_UI_SCALE_FLOOR || maxHeightAtScale <= floorHeight) {
    return {
      targetMinHeight: minHeight,
      derivedMinHeight: floorHeight,
      derivedMaxHeight: floorHeight,
      derivedMinUiScale: HARD_MIN_UI_SCALE_FLOOR,
      maxUiScale: HARD_MIN_UI_SCALE_FLOOR,
      measuredMinHeight: floorHeight
    };
  }

  var minSolution = solveScaleForHeight(minHeight, HARD_MIN_UI_SCALE_FLOOR, MAX_UI_SCALE, measureFn);
  var derivedMinHeight = minSolution.clamped ? minSolution.height : minHeight;

  return {
    targetMinHeight: minHeight,
    derivedMinHeight: derivedMinHeight,
    derivedMaxHeight: maxHeightAtScale,
    derivedMinUiScale: minSolution.scale,
    maxUiScale: MAX_UI_SCALE,
    measuredMinHeight: minSolution.height
  };
}

function reportPopoverBounds(bounds) {
  var layout = readLiveLayoutMetrics();
  var next = {
    targetMinHeight: Math.ceil(bounds.targetMinHeight),
    derivedMinHeight: Math.ceil(bounds.derivedMinHeight),
    derivedMaxHeight: Math.ceil(bounds.derivedMaxHeight),
    derivedMinUiScale: Number(bounds.derivedMinUiScale.toFixed(3)),
    maxUiScale: Number(bounds.maxUiScale.toFixed(3)),
    measuredMinHeight: Number(bounds.measuredMinHeight.toFixed(3)),
    currentHeight: Math.ceil(bounds.currentHeight),
    currentUiScale: Number(bounds.currentUiScale.toFixed(3)),
    bodyShellHeight: Number(layout.bodyShellHeight.toFixed(3)),
    workspaceListHeight: Number(layout.workspaceListHeight.toFixed(3))
  };
  if (
    lastReportedBounds
    && lastReportedBounds.targetMinHeight === next.targetMinHeight
    && lastReportedBounds.derivedMinHeight === next.derivedMinHeight
    && lastReportedBounds.derivedMaxHeight === next.derivedMaxHeight
    && lastReportedBounds.derivedMinUiScale === next.derivedMinUiScale
    && lastReportedBounds.maxUiScale === next.maxUiScale
    && lastReportedBounds.measuredMinHeight === next.measuredMinHeight
    && lastReportedBounds.currentHeight === next.currentHeight
    && lastReportedBounds.currentUiScale === next.currentUiScale
    && lastReportedBounds.bodyShellHeight === next.bodyShellHeight
    && lastReportedBounds.workspaceListHeight === next.workspaceListHeight
  ) {
    return;
  }
  lastReportedBounds = next;
  sendAction("updatePopoverBounds", next);
}

function updateUiScale() {
  var model = computeVerticalSizingModel();
  var minHeight = targetMinHeight();
  if (!model) {
    setUiScale(1);
    reportPopoverBounds({
      targetMinHeight: minHeight,
      derivedMinHeight: minHeight,
      derivedMaxHeight: Math.max(minHeight, Math.ceil(window.innerHeight)),
      derivedMinUiScale: 1,
      maxUiScale: 1,
      measuredMinHeight: minHeight,
      currentHeight: window.innerHeight,
      currentUiScale: 1
    });
    return;
  }

  var currentSolution = solveScaleForHeight(window.innerHeight, model.derivedMinUiScale, model.maxUiScale, measureWorkspaceHeightAtScale);
  setUiScale(currentSolution.scale);
  model.currentHeight = window.innerHeight;
  model.currentUiScale = currentSolution.scale;
  reportPopoverBounds(model);
}

window.tapshopRecomputeBounds = function () {
  lastReportedBounds = null;
  updateUiScale();
};

window.tapshopFocusKeyboardSurface = focusKeyboardSurface;

window.tapshopClearPointerHover = function () {
  document.querySelectorAll(".is-pointer-hover").forEach(function (el) {
    el.classList.remove("is-pointer-hover");
  });
  window.__tapshopPointerHoverEl = null;
};

function pointInRect(x, y, rect) {
  return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
}

function hitTestSelectorList(x, y, selectors) {
  for (var s = 0; s < selectors.length; s++) {
    var nodes = document.querySelectorAll(selectors[s]);
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (!node || node.disabled || node.getAttribute("aria-disabled") === "true") continue;
      if (node.classList.contains("off") || node.hasAttribute("hidden")) continue;
      if (node.closest && node.closest("[hidden]")) continue;
      var style = window.getComputedStyle(node);
      if (style.pointerEvents === "none" || style.visibility === "hidden" || style.display === "none") {
        continue;
      }
      if (pointInRect(x, y, node.getBoundingClientRect())) {
        return node;
      }
    }
  }
  return null;
}

function findPointerHoverTarget(x, y) {
  // Prefer explicit rect hit-tests over elementFromPoint: inactive/non-key
  // WKWebViews are unreliable for the latter, and --ui-scale + resize change
  // layout without changing the top-left client mapping from Lua.
  // While confirm is open, only dialog actions — otherwise covered slots/buttons
  // still have live rects and would steal hover under the overlay.
  if (isUnpairAllConfirmOpen()) {
    return hitTestSelectorList(x, y, [".confirm-ok", ".confirm-cancel"]);
  }
  if (isColorPickerOpen()) {
    return hitTestSelectorList(x, y, [".color-pick", ".profile-color-btn.is-wiggle", ".profile-icon-btn", ".header-btn"]);
  }
  return hitTestSelectorList(x, y, [
    ".slot-icon-btn",
    ".profile-color-btn",
    ".profile-icon-btn",
    ".btn",
    ".header-btn"
  ]);
}

window.tapshopPointerHoverAt = function (x, y) {
  var next = null;
  if (x != null && y != null && !isNaN(x) && !isNaN(y)) {
    next = findPointerHoverTarget(x, y);
  }
  if (next === window.__tapshopPointerHoverEl) {
    if (!next) window.tapshopClearPointerHover();
    return;
  }
  window.tapshopClearPointerHover();
  window.__tapshopPointerHoverEl = next;
  if (next) {
    next.classList.add("is-pointer-hover");
    if (
      next.classList.contains("slot-icon-btn")
      || next.classList.contains("profile-color-btn")
    ) {
      var row = next.closest(".row");
      if (row) row.classList.add("is-pointer-hover");
    }
  }
};

window.tapshopUpdateOpacity = function (percent) {
  var p = parseInt(percent, 10);
  if (isNaN(p)) return;
  var opacity = Math.max(0.40, Math.min(1.0, p / 100));
  var root = document.documentElement;
  if (root && root.style) {
    root.style.setProperty("--panel-bg", "rgba(20, 20, 20, " + opacity.toFixed(2) + ")");
  }
};

window.tapshopUpdateActiveWindow = function (payload) {
  payload = payload || {};
  var wrap = document.querySelector(".header-active-win");
  if (!wrap) return false;

  var titleEl = wrap.querySelector(".header-active-win-title");
  if (titleEl && payload.title != null) {
    titleEl.textContent = String(payload.title);
  }

  var iconEl = wrap.querySelector(".header-active-win-icon");
  var iconUrl = typeof payload.iconUrl === "string" ? payload.iconUrl : "";
  var appName = payload.appName != null ? String(payload.appName) : "";

  if (!iconUrl) {
    if (iconEl) iconEl.remove();
    return true;
  }

  if (!iconEl) {
    iconEl = document.createElement("img");
    iconEl.className = "header-active-win-icon";
    iconEl.alt = "";
    iconEl.setAttribute("aria-hidden", "true");
    if (titleEl) {
      wrap.insertBefore(iconEl, titleEl);
    } else {
      wrap.insertBefore(iconEl, wrap.firstChild);
    }
  }

  if (iconEl.getAttribute("src") !== iconUrl) {
    iconEl.setAttribute("src", iconUrl);
  }
  iconEl.setAttribute("title", appName);
  return true;
};

var profileUiState = {
  mode: "slots",
  editingId: null,
  draftName: "",
  draftColor: null,
  originalName: "",
  originalColor: null,
  colorPickerOpen: false
};

var profileSwitchEpoch = 0;
var appliedProfileSwitchEpoch = 0;
// Last slots HTML painted per profile so click-activate can begin-paint like hotkeys.
var tapshopSlotsHtmlByProfile = {};
window.tapshopSlotsHtmlByProfile = tapshopSlotsHtmlByProfile;

function rememberSlotsHtmlForActiveProfile(slotsHtml, activeProfile) {
  if (typeof slotsHtml !== "string") return;
  var id = activeProfile && activeProfile.id;
  if (id == null) return;
  tapshopSlotsHtmlByProfile[id] = slotsHtml;
}

var PENCIL_SVG =
  '<svg class="profile-edit-icon" viewBox="0 0 16 16" aria-hidden="true" focusable="false" fill="currentColor">'
  + '<path d="M12.146 2.146a.5.5 0 0 1 .708 0l1 1a.5.5 0 0 1 0 .708l-1.5 1.5-1.708-1.708 1.5-1.5zm-2.207 2.207L2.5 11.792V13.5h1.708l7.439-7.439-1.708-1.708zM1.5 12.5v2h2l.5-.5H2v-1.5l-.5.5z"/>'
  + "</svg>";

function bodyShell() {
  return document.getElementById("body-shell");
}

function slotsList() {
  return document.getElementById("slots-list");
}

function profilesList() {
  return document.getElementById("profiles-list");
}

function colorPickerEl() {
  return document.getElementById("profile-color-picker");
}

function profileModeToggle() {
  return document.getElementById("profile-mode-toggle");
}

function isColorPickerOpen() {
  return !!(profileUiState.colorPickerOpen && colorPickerEl() && !colorPickerEl().hidden);
}

function isProfilesMode() {
  return profileUiState.mode === "profiles";
}

function normalizeColor(value) {
  if (value == null || value === false || value === "" || value === "none") return null;
  var match = String(value).match(/^\s*(#[0-9a-fA-F]{6})\s*$/);
  return match ? ("#" + match[1].slice(1).toUpperCase()) : null;
}

function paletteColors() {
  var colors = window.tapshopProfilePalette || [];
  var out = [];
  for (var i = 0; i < colors.length; i++) {
    out.push(normalizeColor(colors[i]));
  }
  out.push(null);
  return out;
}

function colorFromButton(btn) {
  if (!btn || btn.classList.contains("is-none")) return null;
  return normalizeColor(btn.getAttribute("data-color") || "");
}

function usedColorsExcluding(exceptId) {
  var used = {};
  var rows = document.querySelectorAll(".is-profile-row");
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var id = parseInt(row.getAttribute("data-profile-id"), 10);
    if (id === exceptId) continue;
    if (profileUiState.editingId === id) {
      var draft = normalizeColor(profileUiState.draftColor);
      if (draft) used[draft] = true;
      continue;
    }
    var color = colorFromButton(row.querySelector(".profile-color-btn"));
    if (color) used[color] = true;
  }
  return used;
}

function syncEscapeArm() {
  if (window.tapshopNeedsEscapeArm && window.tapshopNeedsEscapeArm()) {
    sendAction("profileUiArmEscape");
  } else {
    sendAction("profileUiDisarmEscape");
  }
}

window.tapshopNeedsEscapeArm = function () {
  return !!(
    isUnpairAllConfirmOpen()
    || isColorPickerOpen()
    || profileUiState.editingId != null
    || isProfilesMode()
  );
};

function paintColorButton(btn, color) {
  if (!btn) return;
  var hex = normalizeColor(color);
  btn.classList.toggle("is-none", !hex);
  if (hex) {
    btn.style.background = hex;
    btn.setAttribute("data-color", hex);
  } else {
    btn.style.background = "";
    btn.removeAttribute("data-color");
  }
}

function applyActiveProfileChrome(activeProfile) {
  activeProfile = activeProfile || window.tapshopActiveProfile || {};
  window.tapshopActiveProfile = activeProfile;
  var shell = bodyShell();
  var toggle = profileModeToggle();
  var color = normalizeColor(activeProfile.color);
  var hasColor = !!color;

  if (shell) {
    shell.classList.toggle("has-active-color", profileUiState.mode === "slots" && hasColor);
    if (hasColor) shell.style.setProperty("--active-profile-color", color);
    else shell.style.removeProperty("--active-profile-color");
  }

  var rail = document.getElementById("profile-rail");
  if (rail) {
    rail.style.background = hasColor ? color : "transparent";
  }

  if (toggle) {
    toggle.classList.toggle("has-profile-tint", hasColor);
    toggle.classList.toggle("is-profiles-mode", profileUiState.mode === "profiles");
    if (hasColor) {
      toggle.style.setProperty("--profile-tint", color);
    } else {
      toggle.style.removeProperty("--profile-tint");
    }
  }
}

function setProfileMode(mode, opts) {
  opts = opts || {};
  if (mode === "slots" && profileUiState.editingId != null) {
    cancelProfileEdit(true);
  }
  var previous = profileUiState.mode;
  profileUiState.mode = mode === "profiles" ? "profiles" : "slots";
  if (profileUiState.mode !== "profiles") closeColorPicker();

  var shell = bodyShell();
  var slots = slotsList();
  var profiles = profilesList();
  if (shell) {
    shell.classList.toggle("is-slots-mode", profileUiState.mode === "slots");
    shell.classList.toggle("is-profiles-mode", profileUiState.mode === "profiles");
  }
  if (slots) slots.hidden = profileUiState.mode !== "slots";
  if (profiles) profiles.hidden = profileUiState.mode !== "profiles";

  if (!opts.skipChrome) {
    applyActiveProfileChrome(window.tapshopActiveProfile);
  }
  syncEscapeArm();
  if (!opts.skipNotify && previous !== profileUiState.mode) {
    sendAction("profileModeChanged", { mode: profileUiState.mode });
  }
}

function markSlotsSwitching(isSwitching) {
  var slots = slotsList();
  if (!slots) return;
  if (window._tapshopSwitchRevealTimer) {
    clearTimeout(window._tapshopSwitchRevealTimer);
    window._tapshopSwitchRevealTimer = null;
  }
  slots.classList.toggle("is-switching", !!isSwitching);
  // Failsafe: never leave the list blank if an apply is dropped under rapid load.
  if (isSwitching) {
    window._tapshopSwitchRevealTimer = setTimeout(function () {
      window._tapshopSwitchRevealTimer = null;
      var list = slotsList();
      if (list && list.classList.contains("is-switching")) {
        list.classList.remove("is-switching");
      }
    }, 160);
  }
}

// Apply chrome immediately; paint cached slots when provided so rapid cycles
// never sit on an empty frame waiting for the fresh Lua rebuild.
window.tapshopBeginProfileSwitch = function (payload) {
  payload = payload || {};
  var epoch = parseInt(payload.epoch, 10);
  if (!isNaN(epoch)) {
    // A newer begin already owns the in-flight switch; ignore this one.
    if (epoch < profileSwitchEpoch) {
      return true;
    }
    profileSwitchEpoch = epoch;
  }

  if (payload.activeProfile) {
    window.tapshopActiveProfile = payload.activeProfile;
  }

  if (payload.returnToSlots) {
    cancelProfileEdit(true);
    setProfileMode("slots", { skipChrome: true });
  }

  applyActiveProfileChrome(window.tapshopActiveProfile);

  if (typeof payload.slotsHtml === "string") {
    // Settle/apply for this epoch (or newer) already landed — do not let a late
    // begin rewrite slots with possibly stale cached HTML.
    if (!isNaN(epoch) && appliedProfileSwitchEpoch >= epoch) {
      return true;
    }
    var slots = slotsList();
    if (!slots) return false;
    slots.classList.add("is-switching");
    slots.innerHTML = payload.slotsHtml;
    markSlotsSwitching(false);
    rememberSlotsHtmlForActiveProfile(payload.slotsHtml, window.tapshopActiveProfile);
    if (!isNaN(epoch)) {
      appliedProfileSwitchEpoch = epoch;
    }
  }
  // Cache miss: keep the previous bank visible until apply lands (no blank frame).
  return true;
};

function activateProfileFromSquare(btn, profileId) {
  var row = btn && btn.closest ? btn.closest(".is-profile-row") : null;
  var color = colorFromButton(btn);
  var nameEl = row ? row.querySelector(".profile-label-text") : null;
  var epoch = ++profileSwitchEpoch;
  var activeProfile = {
    id: profileId,
    name: nameEl ? nameEl.textContent : "",
    color: color
  };
  var beginPayload = {
    epoch: epoch,
    returnToSlots: true,
    activeProfile: activeProfile
  };
  if (typeof tapshopSlotsHtmlByProfile[profileId] === "string") {
    beginPayload.slotsHtml = tapshopSlotsHtmlByProfile[profileId];
  }

  window.tapshopBeginProfileSwitch(beginPayload);
  sendAction("activateProfile", {
    profile: profileId,
    returnToSlots: true,
    epoch: epoch
  });
}

function tapshopToggleProfileMode() {
  if (profileUiState.editingId != null) cancelProfileEdit(true);
  markSlotsSwitching(false);
  setProfileMode(profileUiState.mode === "slots" ? "profiles" : "slots");
}
window.tapshopToggleProfileMode = tapshopToggleProfileMode;

function closeColorPicker() {
  profileUiState.colorPickerOpen = false;
  var picker = colorPickerEl();
  if (!picker) return;
  picker.hidden = true;
  picker.classList.remove("is-open");
}

function renderColorPickerGrid() {
  var grid = document.getElementById("profile-color-picker-grid");
  if (!grid) return;
  grid.innerHTML = "";
  var current = normalizeColor(profileUiState.draftColor);
  var used = usedColorsExcluding(profileUiState.editingId);
  var colors = paletteColors();
  for (var i = 0; i < colors.length; i++) {
    var hex = colors[i];
    var selected = (current === hex) || (!current && !hex);
    var disabled = !!(hex && used[hex]);
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "color-pick"
      + (!hex ? " is-none" : "")
      + (selected ? " is-selected" : "")
      + (disabled ? " is-disabled" : "");
    if (hex) btn.style.background = hex;
    btn.title = hex || "No color";
    btn.disabled = disabled;
    (function (pickHex, isDisabled) {
      btn.addEventListener("mousedown", function (e) { e.preventDefault(); });
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        if (isDisabled) return;
        setDraftColor(pickHex);
      });
    })(hex, disabled);
    grid.appendChild(btn);
  }
}

function openColorPicker(anchorEl) {
  if (profileUiState.editingId == null || !anchorEl) return;
  profileUiState.colorPickerOpen = true;
  renderColorPickerGrid();
  var picker = colorPickerEl();
  var container = document.querySelector(".container");
  if (!picker || !container) return;
  picker.hidden = false;
  picker.classList.add("is-open");

  var popRect = container.getBoundingClientRect();
  var a = anchorEl.getBoundingClientRect();
  var left = a.left - popRect.left;
  var top = a.bottom - popRect.top + 4;
  picker.style.left = "0px";
  picker.style.top = "0px";
  var pw = picker.offsetWidth;
  var ph = picker.offsetHeight;
  var maxLeft = Math.max(6, popRect.width - pw - 6);
  var maxTop = Math.max(6, popRect.height - ph - 6);
  left = Math.min(Math.max(6, left), maxLeft);
  if (top + ph > popRect.height - 6) {
    top = a.top - popRect.top - ph - 4;
  }
  top = Math.min(Math.max(6, top), maxTop);
  picker.style.left = left + "px";
  picker.style.top = top + "px";
  syncEscapeArm();
}

function toggleColorPicker(anchorEl) {
  if (profileUiState.colorPickerOpen) {
    closeColorPicker();
    syncEscapeArm();
  } else {
    openColorPicker(anchorEl);
  }
}

function setDraftColor(hex) {
  if (profileUiState.editingId == null) return;
  profileUiState.draftColor = normalizeColor(hex);
  var row = document.querySelector('.is-profile-row[data-profile-id="' + profileUiState.editingId + '"]');
  if (row) paintColorButton(row.querySelector(".profile-color-btn"), profileUiState.draftColor);
  closeColorPicker();
  syncEscapeArm();
}

function clearProfileEditChrome() {
  document.querySelectorAll(".is-profile-row.is-editing-row").forEach(function (row) {
    row.classList.remove("is-editing-row");
    var btn = row.querySelector(".profile-color-btn");
    if (btn) btn.classList.remove("is-wiggle");
  });
}

function beginProfileEdit(profileId) {
  var row = document.querySelector('.is-profile-row[data-profile-id="' + profileId + '"]');
  if (!row) return;
  if (profileUiState.editingId != null && profileUiState.editingId !== profileId) {
    cancelProfileEdit(true);
  }

  var nameEl = row.querySelector(".profile-label-text");
  var colorBtn = row.querySelector(".profile-color-btn");
  var name = nameEl ? nameEl.textContent : "";
  var color = colorBtn ? (colorBtn.getAttribute("data-color") || null) : null;
  if (colorBtn && colorBtn.classList.contains("is-none")) color = null;

  profileUiState.editingId = profileId;
  profileUiState.originalName = name;
  profileUiState.originalColor = normalizeColor(color);
  profileUiState.draftName = name;
  profileUiState.draftColor = normalizeColor(color);
  profileUiState.colorPickerOpen = false;
  setProfileMode("profiles");
  sendAction("profileEditBegin");

  row.classList.add("is-editing-row");
  if (colorBtn) colorBtn.classList.add("is-wiggle");

  var pill = row.querySelector(".profile-label-pill");
  if (pill) {
    pill.classList.add("is-editing");
    var existingText = pill.querySelector(".profile-label-text");
    if (existingText) existingText.remove();
    var existingInput = pill.querySelector(".profile-label-input");
    if (existingInput) existingInput.remove();
    var input = document.createElement("input");
    input.className = "profile-label-input";
    input.type = "text";
    input.value = profileUiState.draftName;
    input.addEventListener("input", function () {
      profileUiState.draftName = input.value;
    });
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        e.preventDefault();
        commitProfileEdit();
      } else if (e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        if (profileUiState.colorPickerOpen) {
          closeColorPicker();
          syncEscapeArm();
          return;
        }
        cancelProfileEdit();
      }
    });
    pill.appendChild(input);
    requestAnimationFrame(function () {
      try { input.focus({ preventScroll: true }); input.select(); }
      catch (_) { input.focus(); input.select(); }
    });
  }

  var actions = row.querySelector(".profile-edit-actions");
  if (actions) {
    actions.innerHTML = "";
    var accept = document.createElement("button");
    accept.type = "button";
    accept.className = "profile-icon-btn accept";
    accept.title = "Save";
    accept.textContent = "✓";
    accept.addEventListener("mousedown", function (e) { e.preventDefault(); });
    accept.addEventListener("click", function (e) {
      e.stopPropagation();
      commitProfileEdit();
    });
    var cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "profile-icon-btn cancel";
    cancel.title = "Cancel";
    cancel.textContent = "✕";
    cancel.addEventListener("mousedown", function (e) { e.preventDefault(); });
    cancel.addEventListener("click", function (e) {
      e.stopPropagation();
      cancelProfileEdit();
    });
    actions.appendChild(accept);
    actions.appendChild(cancel);
  }
  syncEscapeArm();
}

function restoreProfileRowActions(row, profileId) {
  if (!row) return;
  var pill = row.querySelector(".profile-label-pill");
  if (pill) {
    pill.classList.remove("is-editing");
    var input = pill.querySelector(".profile-label-input");
    if (input) input.remove();
    var text = pill.querySelector(".profile-label-text");
    if (!text) {
      text = document.createElement("span");
      text.className = "profile-label-text";
      pill.appendChild(text);
    }
    text.textContent = profileUiState.draftName || profileUiState.originalName || "";
  }
  var actions = row.querySelector(".profile-edit-actions");
  if (actions) {
    actions.innerHTML = "";
    var pencil = document.createElement("button");
    pencil.type = "button";
    pencil.className = "profile-icon-btn profile-edit-btn";
    pencil.setAttribute("data-profile-id", String(profileId));
    pencil.setAttribute("aria-label", "Edit name and color");
    pencil.setAttribute("data-tooltip", "Edit name & color");
    pencil.innerHTML = PENCIL_SVG;
    pencil.addEventListener("click", function (e) {
      e.stopPropagation();
      beginProfileEdit(profileId);
    });
    actions.appendChild(pencil);
  }
}

function cancelProfileEdit(silent) {
  var id = profileUiState.editingId;
  var wasEditing = id != null;
  closeColorPicker();
  if (id == null) {
    clearProfileEditChrome();
    if (!silent) syncEscapeArm();
    return;
  }
  var row = document.querySelector('.is-profile-row[data-profile-id="' + id + '"]');
  profileUiState.draftName = profileUiState.originalName;
  profileUiState.draftColor = profileUiState.originalColor;
  if (row) {
    paintColorButton(row.querySelector(".profile-color-btn"), profileUiState.originalColor);
    var btn = row.querySelector(".profile-color-btn");
    if (btn) btn.classList.remove("is-wiggle");
    row.classList.remove("is-editing-row");
    restoreProfileRowActions(row, id);
    var text = row.querySelector(".profile-label-text");
    if (text) text.textContent = profileUiState.originalName;
  }
  profileUiState.editingId = null;
  clearProfileEditChrome();
  if (wasEditing) sendAction("profileEditEnd");
  if (!silent) syncEscapeArm();
}

function commitProfileEdit() {
  var id = profileUiState.editingId;
  if (id == null) return;
  var name = String(profileUiState.draftName || "").trim();
  if (!name) name = "Untitled profile " + id;
  var color = normalizeColor(profileUiState.draftColor);
  var payload = { profile: id, name: name };
  if (!color) payload.clearColor = true;
  else payload.color = color;

  var row = document.querySelector('.is-profile-row[data-profile-id="' + id + '"]');
  profileUiState.originalName = name;
  profileUiState.originalColor = color;
  profileUiState.draftName = name;
  closeColorPicker();
  if (row) {
    paintColorButton(row.querySelector(".profile-color-btn"), color);
    var btn = row.querySelector(".profile-color-btn");
    if (btn) btn.classList.remove("is-wiggle");
    row.classList.remove("is-editing-row");
    restoreProfileRowActions(row, id);
    var text = row.querySelector(".profile-label-text");
    if (text) text.textContent = name;
  }
  profileUiState.editingId = null;
  sendAction("profileEditEnd");
  sendAction("updateProfileMetadata", payload);
  syncEscapeArm();
}

function wireProfileListInteractions(root) {
  if (!root) return;
  root.querySelectorAll(".profile-color-btn").forEach(function (btn) {
    if (!btn.getAttribute("data-color") && btn.style.background && btn.style.background.indexOf("rgb") !== 0) {
      btn.setAttribute("data-color", normalizeColor(btn.style.background) || "");
      if (!btn.getAttribute("data-color")) btn.removeAttribute("data-color");
    }
    btn.addEventListener("mousedown", function (e) {
      if (btn.classList.contains("is-wiggle")) e.preventDefault();
    });
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      var id = parseInt(btn.getAttribute("data-profile-id"), 10);
      if (profileUiState.editingId != null) {
        if (profileUiState.editingId === id) toggleColorPicker(btn);
        return;
      }
      if (!id) return;
      activateProfileFromSquare(btn, id);
    });
  });
  root.querySelectorAll(".profile-edit-btn").forEach(function (btn) {
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      var id = parseInt(btn.getAttribute("data-profile-id"), 10);
      if (id) beginProfileEdit(id);
    });
  });
}

window.tapshopApplyProfileUi = function (payload) {
  payload = payload || {};
  var epoch = parseInt(payload.epoch, 10);
  if (!isNaN(epoch)) {
    // Ignore stale switch payloads so rapid back/forth cannot flash an older bank.
    if (epoch < appliedProfileSwitchEpoch) {
      return true;
    }
    if (epoch < profileSwitchEpoch) {
      return true;
    }
    appliedProfileSwitchEpoch = epoch;
    if (epoch > profileSwitchEpoch) {
      profileSwitchEpoch = epoch;
    }
  }

  if (payload.activeProfile) {
    window.tapshopActiveProfile = payload.activeProfile;
  }

  if (typeof payload.slotsHtml === "string") {
    var slots = slotsList();
    if (!slots) return false;
    // Instant hide only for the DOM replace itself (transition: none in CSS).
    slots.classList.add("is-switching");
    slots.innerHTML = payload.slotsHtml;
    rememberSlotsHtmlForActiveProfile(payload.slotsHtml, window.tapshopActiveProfile);
  } else {
    markSlotsSwitching(false);
  }

  if (typeof payload.profilesHtml === "string") {
    var profiles = profilesList();
    if (!profiles) return false;
    var keepEditing = profileUiState.editingId;
    profiles.innerHTML = payload.profilesHtml;
    wireProfileListInteractions(profiles);
    if (keepEditing != null && !payload.returnToSlots) {
      beginProfileEdit(keepEditing);
    }
  } else if (payload.activeProfile && payload.activeProfile.id != null) {
    var activeId = payload.activeProfile.id;
    document.querySelectorAll(".is-profile-row").forEach(function (row) {
      var id = parseInt(row.getAttribute("data-profile-id"), 10);
      row.classList.toggle("is-active-profile", id === activeId);
    });
  }

  if (payload.returnToSlots) {
    cancelProfileEdit(true);
    setProfileMode("slots", { skipChrome: true });
    applyActiveProfileChrome(window.tapshopActiveProfile);
  } else {
    applyActiveProfileChrome(window.tapshopActiveProfile);
    if (payload.activeProfile && payload.activeProfile.id != null && typeof payload.profilesHtml === "string") {
      var aid = payload.activeProfile.id;
      document.querySelectorAll(".is-profile-row").forEach(function (row) {
        var id = parseInt(row.getAttribute("data-profile-id"), 10);
        row.classList.toggle("is-active-profile", id === aid);
      });
    }
  }

  if (typeof payload.slotsHtml === "string") {
    markSlotsSwitching(false);
  }

  return true;
};

window.tapshopHandleEscape = function () {
  var handled = false;
  if (isUnpairAllConfirmOpen()) {
    hideUnpairAllConfirm();
    handled = true;
  } else if (profileUiState.colorPickerOpen) {
    closeColorPicker();
    handled = true;
  } else if (profileUiState.editingId != null) {
    cancelProfileEdit();
    handled = true;
  } else if (isProfilesMode()) {
    setProfileMode("slots");
    handled = true;
  }
  if (handled) syncEscapeArm();
  return handled;
};

function getResizeDirectionFromEvent(e) {
  var handle = e.target && e.target.closest && e.target.closest("[data-resize]");
  if (!handle) return "";
  return handle.getAttribute("data-resize") || "";
}

function cursorForDirection(direction) {
  if (direction === "n" || direction === "s") return "ns-resize";
  if (direction === "e" || direction === "w") return "ew-resize";
  if (direction === "ne" || direction === "sw") return "nesw-resize";
  if (direction === "nw" || direction === "se") return "nwse-resize";
  return "";
}

function setInteractionCursor(cursor) {
  var value = cursor || "";
  document.documentElement.style.cursor = value;
  document.body.style.cursor = value;
}

function setResizeHandlesEnabled(enabled) {
  var handles = document.querySelector(".resize-handles");
  if (!handles) return;
  handles.classList.toggle("is-disabled", !enabled);
}

var container = document.querySelector(".container");
var header = document.querySelector(".header");
var headerActions = document.querySelector(".header-actions");
var headerTooltip = document.querySelector(".header-tooltip");
var titleLogo = document.querySelector(".title-logo");
var unpairAllConfirm = document.getElementById("unpair-all-confirm");
var tooltipTarget = null;
var titleTapTimestamps = [];

function hideHeaderTooltip() {
  tooltipTarget = null;
  if (!headerTooltip) return;
  headerTooltip.classList.remove("is-visible");
  headerTooltip.textContent = "";
}

function showHeaderTooltip(el) {
  if (!container || !headerActions || !headerTooltip || !el) return;
  if (dragState.active || resizeState.active) return;

  var tooltipText = el.getAttribute("data-tooltip") || "";
  if (!tooltipText) {
    hideHeaderTooltip();
    return;
  }

  tooltipTarget = el;
  headerTooltip.textContent = tooltipText;
  headerTooltip.classList.add("is-visible");

  var containerRect = container.getBoundingClientRect();
  var headerRect = header ? header.getBoundingClientRect() : null;
  var buttonRect = el.getBoundingClientRect();
  var style = window.getComputedStyle(container);
  var paddingLeft = readPx(style.paddingLeft);
  var paddingRight = readPx(style.paddingRight);
  var tooltipRect = headerTooltip.getBoundingClientRect();
  var minLeft = paddingLeft + 6;
  var maxLeft = containerRect.width - tooltipRect.width - paddingRight - 6;
  var centeredLeft = (buttonRect.left - containerRect.left) + (buttonRect.width / 2) - (tooltipRect.width / 2);
  var left = Math.max(minLeft, Math.min(centeredLeft, maxLeft));
  var topBase = headerRect ? ((headerRect.bottom - containerRect.top) + 4) : 30;

  headerTooltip.style.left = left + "px";
  headerTooltip.style.top = topBase + "px";
}

function triggerTitleHop() {
  if (!titleLogo) return;
  titleLogo.classList.remove("is-hopping");
  void titleLogo.offsetWidth;
  titleLogo.classList.add("is-hopping");
}

function setTitleLogoPressed(pressed) {
  if (!titleLogo) return;
  titleLogo.classList.toggle("is-pressed", pressed);
}

var dragState = {
  active: false,
  lastX: 0,
  lastY: 0
};

var resizeState = {
  active: false,
  lastX: 0,
  lastY: 0,
  direction: ""
};

function resetInteractionGestures() {
  dragState.active = false;
  resizeState.active = false;
  resizeState.direction = "";
  setInteractionCursor("");
  // Hide can run without reloading the DOM; clear confirm so re-show is clean
  // and the Lua Escape tap is not left responsible for a leftover overlay.
  hideUnpairAllConfirm();
}

window.tapshopResetInteractionGestures = resetInteractionGestures;

document.addEventListener("mousedown", function (e) {
  if (e.button !== 0) return;
  if (isUnpairAllConfirmOpen()) return;
  var direction = getResizeDirectionFromEvent(e);
  if (!direction) return;
  resizeState.active = true;
  resizeState.direction = direction;
  resizeState.lastX = e.screenX;
  resizeState.lastY = e.screenY;
  setInteractionCursor(cursorForDirection(direction));
  hideHeaderTooltip();
  sendAction("resizeStart", { direction: direction });
  e.preventDefault();
  e.stopPropagation();
}, true);

function isDragExcludedTarget(target) {
  return !!(
    target
    && target.closest
    && target.closest(".header-actions, .title-logo, .slot-icon-btn, .profile-color-btn, .profile-icon-btn, .profile-label-input, .color-picker, .confirm-shell, .resize-handle, button, input, label, a, select, textarea")
  );
}

function isUnpairAllConfirmOpen() {
  return !!(unpairAllConfirm && !unpairAllConfirm.hidden);
}

function showUnpairAllConfirm() {
  if (!unpairAllConfirm) return;
  hideHeaderTooltip();
  unpairAllConfirm.hidden = false;
  setResizeHandlesEnabled(false);
  window.tapshopClearPointerHover && window.tapshopClearPointerHover();
  // Utility overlay cannot become key — skip focus; Lua Escape tap dismisses.
  if (!(document.body && document.body.classList.contains("is-utility-overlay"))) {
    var okBtn = unpairAllConfirm.querySelector(".confirm-ok");
    if (okBtn && typeof okBtn.focus === "function") {
      try {
        okBtn.focus({ preventScroll: true });
      } catch (_) {
        okBtn.focus();
      }
    }
  }
  sendAction("unpairAllConfirmOpen");
}

function hideUnpairAllConfirm() {
  if (!unpairAllConfirm || unpairAllConfirm.hidden) return;
  unpairAllConfirm.hidden = true;
  setResizeHandlesEnabled(true);
  focusKeyboardSurface();
  sendAction("unpairAllConfirmClose");
}

window.tapshopHideUnpairAllConfirm = hideUnpairAllConfirm;

function confirmUnpairAll() {
  hideUnpairAllConfirm();
  sendAction("unpairAll");
}

document.addEventListener("mousedown", function (e) {
  if (e.button !== 0) return;
  if (isUnpairAllConfirmOpen()) return;
  if (resizeState.active) return;
  if (getResizeDirectionFromEvent(e)) return;
  if (isDragExcludedTarget(e.target)) return;
  if (!e.target.closest || !e.target.closest(".container")) return;

  dragState.active = true;
  dragState.lastX = e.screenX;
  dragState.lastY = e.screenY;
  setInteractionCursor("move");
  hideHeaderTooltip();
  sendAction("dragStart");
  e.preventDefault();
});

window.addEventListener("mousemove", function (e) {
  if (dragState.active) {
    var dx = e.screenX - dragState.lastX;
    var dy = e.screenY - dragState.lastY;
    dragState.lastX = e.screenX;
    dragState.lastY = e.screenY;
    if (dx !== 0 || dy !== 0) {
      sendAction("dragMove", { dx: dx, dy: dy });
    }
  }

  if (resizeState.active) {
    var dw = e.screenX - resizeState.lastX;
    var dh = e.screenY - resizeState.lastY;
    resizeState.lastX = e.screenX;
    resizeState.lastY = e.screenY;
    if (dw !== 0 || dh !== 0) {
      sendAction("resizeMove", { dw: dw, dh: dh, direction: resizeState.direction });
    }
  }
});

window.addEventListener("mouseup", function () {
  setTitleLogoPressed(false);

  if (dragState.active) {
    dragState.active = false;
    setInteractionCursor("");
    sendAction("dragEnd");
  }

  if (resizeState.active) {
    resizeState.active = false;
    resizeState.direction = "";
    setInteractionCursor("");
    sendAction("resizeEnd");
  }
});

document.addEventListener("keydown", function (e) {
  if (e.key === "Escape") {
    e.preventDefault();
    e.stopPropagation();
    if (window.tapshopHandleEscape && window.tapshopHandleEscape()) {
      return;
    }
    sendAction("close");
  }
});

document.addEventListener("mousedown", function (e) {
  if (!profileUiState.colorPickerOpen) return;
  var picker = colorPickerEl();
  var hit = e.target && e.target.closest && e.target.closest(".profile-color-btn.is-wiggle");
  if ((picker && picker.contains(e.target)) || hit) return;
  closeColorPicker();
  syncEscapeArm();
});

document.addEventListener("mousedown", function () {
  hideHeaderTooltip();
});

document.querySelectorAll("[data-tooltip]").forEach(function (el) {
  el.addEventListener("mouseenter", function () {
    showHeaderTooltip(el);
  });
  el.addEventListener("mouseleave", function () {
    if (tooltipTarget === el) hideHeaderTooltip();
  });
  el.addEventListener("focusin", function () {
    showHeaderTooltip(el);
  });
  el.addEventListener("focusout", function () {
    if (tooltipTarget === el) hideHeaderTooltip();
  });
});

if (titleLogo) {
  titleLogo.addEventListener("mousedown", function (e) {
    if (e.button !== 0) return;
    setTitleLogoPressed(true);
    e.stopPropagation();
  });

  titleLogo.addEventListener("mouseleave", function () {
    setTitleLogoPressed(false);
  });

  titleLogo.addEventListener("blur", function () {
    setTitleLogoPressed(false);
  });

  titleLogo.addEventListener("click", function () {
    var now = Date.now();
    titleTapTimestamps.push(now);
    titleTapTimestamps = titleTapTimestamps.filter(function (ts) {
      return now - ts <= TITLE_TAP_WINDOW_MS;
    });
    if (titleTapTimestamps.length >= 3) {
      titleTapTimestamps = [];
      triggerTitleHop();
    }
  });

  titleLogo.addEventListener("animationend", function () {
    titleLogo.classList.remove("is-hopping");
  });
}

window.addEventListener("focus", focusKeyboardSurface);
window.addEventListener("resize", updateUiScale);
(function syncProfileModeFromDom() {
  var shell = bodyShell();
  if (shell && shell.classList.contains("is-profiles-mode")) {
    profileUiState.mode = "profiles";
  }
})();
applyActiveProfileChrome(window.tapshopActiveProfile);
wireProfileListInteractions(profilesList());
updateUiScale();
focusKeyboardSurface();
]=]

return ClientScript
