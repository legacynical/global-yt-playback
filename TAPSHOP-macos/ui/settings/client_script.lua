local ClientScript = {}

ClientScript.script = [=[
var MOD_SYMBOLS = {
  cmd: "⌘",
  alt: "⌥",
  ctrl: "⌃",
  shift: "⇧"
};

// WebKit's default context menu includes Reload, which blanks this injected-HTML
// panel. Tapshop is app chrome, not a browser page — suppress it.
document.addEventListener("contextmenu", function (e) {
  e.preventDefault();
}, true);

var MOD_TITLES = {
  cmd: "Command",
  alt: "Option",
  ctrl: "Control",
  shift: "Shift"
};

var KEY_LABELS = {
  left: "Left",
  right: "Right",
  up: "Up",
  down: "Down",
  return: "Return",
  delete: "Delete",
  forwarddelete: "Forward Delete",
  escape: "Esc",
  space: "Space",
  tab: "Tab",
  BRIGHTNESS_UP: "Brightness Up",
  BRIGHTNESS_DOWN: "Brightness Down",
  SOUND_UP: "Volume Up",
  SOUND_DOWN: "Volume Down",
  PLAY: "Play/Pause",
  LAUNCH_PANEL: "Launchpad"
};

var SYSTEM_KEY_DISPLAY = window.tapshopSystemKeyDisplay || {};

var PHYSICAL_KEY_MAP = {
  Backquote: "`",
  Digit0: "0",
  Digit1: "1",
  Digit2: "2",
  Digit3: "3",
  Digit4: "4",
  Digit5: "5",
  Digit6: "6",
  Digit7: "7",
  Digit8: "8",
  Digit9: "9",
  Minus: "-",
  Equal: "=",
  BracketLeft: "[",
  BracketRight: "]",
  Backslash: "\\",
  Semicolon: ";",
  Quote: "'",
  Comma: ",",
  Period: ".",
  Slash: "/",
  Space: "space",
  Tab: "tab",
  Enter: "return",
  Backspace: "delete",
  Delete: "forwarddelete",
  Escape: "escape",
  ArrowLeft: "left",
  ArrowRight: "right",
  ArrowUp: "up",
  ArrowDown: "down"
};

function currentSettingsTab() {
  return document.body.getAttribute("data-settings-tab") || "general";
}

function layoutPolicy() {
  return window.tapshopSettingsLayoutPolicy || {};
}

function getSearchInput() {
  return document.querySelector(".hotkey-search");
}

function getActiveSettingsPanel() {
  return document.querySelector('.settings-panel[data-settings-panel="' + currentSettingsTab() + '"]');
}

function getSettingsScrollEl() {
  return getActiveSettingsPanel() || document.querySelector(".settings-scroll");
}

function getSearchValue() {
  var input = getSearchInput();
  return input ? input.value : "";
}

function getSettingsScrollTop() {
  var el = getSettingsScrollEl();
  return el ? el.scrollTop : 0;
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
  if (payload.search == null) payload.search = getSearchValue();
  if (payload.scrollTop == null) payload.scrollTop = getSettingsScrollTop();
  if (payload.settingsTab == null) payload.settingsTab = currentSettingsTab();
  window.webkit.messageHandlers.tapshopSettings.postMessage(payload);
}

function setSettingsTabState(tab) {
  document.body.setAttribute("data-settings-tab", tab);
  document.querySelectorAll("[data-settings-tab-button]").forEach(function (button) {
    button.classList.toggle("is-active", button.getAttribute("data-settings-tab-button") === tab);
  });
}

function restoreSettingsScrollState() {
  var el = getSettingsScrollEl();
  if (!el) return;
  var value = parseFloat(document.body.getAttribute("data-settings-scroll-top") || "0") || 0;
  el.scrollTop = Math.max(0, value);
}

function clearValidationUi() {
  document.querySelectorAll(".hotkey-row.has-live-conflict").forEach(function (row) {
    row.classList.remove("has-live-conflict");
  });
  var validation = document.querySelector("[data-hotkey-validation]");
  if (validation) {
    validation.textContent = "";
    validation.classList.add("is-hidden");
  }
  var modalError = document.querySelector("[data-remap-error]");
  if (modalError) {
    modalError.textContent = "";
    modalError.classList.add("is-hidden");
  }
  if (remapState.captureEl) {
    remapState.captureEl.classList.remove("has-error");
  }
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderHotkeyRowHtml(row) {
  var classes = ["hotkey-row"];
  if (row.isModified) classes.push("is-modified");
  if (row.isUnavailable) classes.push("is-unavailable");
  if (row.warning) classes.push("has-warning");
  if ((row.conflictIds || []).length > 0) classes.push("has-conflict");

  var rawKey = row.isAssigned ? String(row.key || "") : "";
  var comboSearch = row.isAssigned ? ((row.mods || []).join(" ") + " " + rawKey).toLowerCase() : "";
  var comboTitle = row.isAssigned ? "Current shortcut" : "No shortcut assigned";
  var comboClass = row.isAssigned ? "hotkey-combo" : "hotkey-combo hotkey-combo-empty";
  var comboInner = row.isAssigned ? comboHtml(row.mods, row.key) : '<span class="hotkey-unset">(unset)</span>';
  var resetHtml = row.isModified
    ? '<button type="button" class="btn hotkey-btn hotkey-reset-btn" title="Reset to default" data-hotkey-action="reset" data-hotkey-id="'
      + escapeHtml(row.id)
      + '">↺</button>'
    : "";

  return ''
    + '<div class="' + classes.join(" ") + '"'
    + ' data-hotkey-row'
    + ' data-id="' + escapeHtml(row.id) + '"'
    + ' data-label="' + escapeHtml(String(row.label || "").toLowerCase()) + '"'
    + ' data-group="' + escapeHtml(String(row.group || "").toLowerCase()) + '"'
    + ' data-key="' + escapeHtml(rawKey) + '"'
    + ' data-mods="' + escapeHtml((row.mods || []).join(" ")) + '"'
    + ' data-assigned="' + (row.isAssigned ? "1" : "0") + '"'
    + ' data-modified="' + (row.isModified ? "1" : "0") + '"'
    + ' data-combo="' + escapeHtml(comboSearch) + '">'
    + '<div class="hotkey-main">'
    + '<span class="hotkey-label">' + escapeHtml(row.label) + '</span>'
    + '<div class="' + comboClass + '" title="' + escapeHtml(comboTitle) + '">' + comboInner + '</div>'
    + '</div>'
    + '<div class="hotkey-actions">'
    + resetHtml
    + '<button type="button" class="btn hotkey-btn hotkey-remap-btn" title="Record shortcut" data-hotkey-action="remap" data-hotkey-id="' + escapeHtml(row.id) + '">Remap</button>'
    + '</div>'
    + '</div>';
}

function renderHotkeyList(rows) {
  var list = document.querySelector("[data-hotkeys-list]");
  if (!list) return;

  var html = "";
  var currentGroup = null;
  (rows || []).forEach(function (row) {
    if (row.group !== currentGroup) {
      if (currentGroup !== null) html += "</section>";
      currentGroup = row.group;
      html += '<section class="hotkey-group" data-hotkey-group="' + escapeHtml(String(row.group || "").toLowerCase()) + '">';
      html += '<div class="hotkey-group-title">' + escapeHtml(row.group) + '</div>';
    }
    html += renderHotkeyRowHtml(row);
  });
  if (currentGroup !== null) html += "</section>";

  list.innerHTML = html;
}

function showValidationUi(result) {
  setHotkeyMutationPending(false);
  clearValidationUi();
  if (!result || !result.message) return;

  var validation = document.querySelector("[data-hotkey-validation]");
  if (validation) {
    validation.textContent = result.message;
    validation.classList.remove("is-hidden");
  }

  if (result.ids) {
    Object.keys(result.ids).forEach(function (id) {
      var row = document.querySelector('[data-hotkey-row][data-id="' + id + '"]');
      if (row) row.classList.add("has-live-conflict");
    });
  }

  if (remapState.open && remapState.errorEl) {
    remapState.errorEl.textContent = result.message;
    remapState.errorEl.classList.remove("is-hidden");
    if (remapState.captureEl) {
      remapState.captureEl.classList.add("has-error");
    }
    focusRemapCapture();
  }
}

window.tapshopApplyValidation = function (result) {
  showValidationUi(result || null);
};

window.tapshopApplyHotkeyState = function (state) {
  state = state || {};
  setHotkeyMutationPending(false);
  cancelRemapModal(true);
  renderHotkeyList(state.rows || []);
  document.body.setAttribute("data-settings-scroll-top", String(state.scrollTop || 0));
  filterHotkeyRows(getSearchValue());
  restoreSettingsScrollState();
  showValidationUi(state.validation || null);
  updateUiScale();
};

window.tapshopApplyHotkeyHtml = function (htmlStr, scrollTop, validation) {
  setHotkeyMutationPending(false);
  cancelRemapModal(true);
  var list = document.querySelector("[data-hotkeys-list]");
  if (list) list.innerHTML = htmlStr || "";
  document.body.setAttribute("data-settings-scroll-top", String(scrollTop || 0));
  filterHotkeyRows(getSearchValue());
  restoreSettingsScrollState();
  showValidationUi(validation || null);
  updateUiScale();
};

function applySettingsConfig(config) {
  if (!config) return;
  document.querySelectorAll("[data-settings-config]").forEach(function (el) {
    var key = el.getAttribute("data-settings-config") || "";
    if (!Object.prototype.hasOwnProperty.call(config, key)) return;
    if (el.type === "checkbox") {
      el.checked = !!config[key];
      return;
    }
    el.value = String(config[key]);
  });
}

window.tapshopApplySettingsWindowState = function (payload) {
  payload = payload || {};
  setHotkeyMutationPending(false);

  applySettingsConfig(payload.config || null);

  var nextTab = payload.settingsTab === "hotkeys" ? "hotkeys" : "general";
  setSettingsTabState(nextTab);

  var input = getSearchInput();
  if (input && typeof payload.search === "string" && input.value !== payload.search) {
    input.value = payload.search;
  }

  document.body.setAttribute("data-settings-scroll-top", String(payload.scrollTop || 0));

  if (typeof payload.hotkeysHtml === "string") {
    var list = document.querySelector("[data-hotkeys-list]");
    if (list) list.innerHTML = payload.hotkeysHtml;
  } else if (Array.isArray(payload.hotkeys)) {
    renderHotkeyList(payload.hotkeys);
  }

  filterHotkeyRows(getSearchValue());
  restoreSettingsScrollState();
  showValidationUi(payload.validation || null);
  updateUiScale();
};

window.tapshopApplyRemapDraft = function (payload) {
  if (hotkeyMutationPending) return;
  payload = payload || {};
  var nextKey = Object.prototype.hasOwnProperty.call(payload, "key") ? payload.key : null;
  applyDraftBinding(Array.isArray(payload.mods) ? payload.mods.slice() : [], nextKey);
};

window.tapshopDidCommitHotkeyAction = function (payload) {
  payload = payload || {};
  setHotkeyMutationPending(false);
  cancelRemapModal(true);
  if (typeof payload.htmlStr === "string") {
    window.tapshopApplyHotkeyHtml(payload.htmlStr, payload.scrollTop || 0, payload.validation || null);
    return;
  }
  if (Array.isArray(payload.rows)) {
    window.tapshopApplyHotkeyState(payload);
  }
};

window.tapshopCancelRemapRecorder = function () {
  cancelRemapModal(true);
};

function updateOpacityCss(percent) {
  var p = parseInt(percent, 10);
  if (isNaN(p)) return;
  var opacity = Math.max(0.40, Math.min(1.0, p / 100));
  var root = document.documentElement;
  if (root && root.style) {
    root.style.setProperty("--panel-bg", "rgba(20, 20, 20, " + opacity.toFixed(2) + ")");
  }
}

function updateOpacityPreview(value) {
  updateOpacityCss(value);
}

window.tapshopUpdateOpacity = function (percent) {
  updateOpacityCss(percent);
};

function switchSettingsTab(tab) {
  if (hotkeyMutationPending) return;
  cancelRemapModal();
  clearValidationUi();
  document.body.setAttribute("data-settings-scroll-top", "0");
  setSettingsTabState(tab);
  restoreSettingsScrollState();
  updateUiScale();
  sendAction("setSettingsTab", { settingsTab: tab, scrollTop: 0 });
}

function resetBinding(id) {
  cancelRemapModal();
  clearValidationUi();
  if (!beginHotkeyMutation()) return;
  sendAction("resetHotkeyBinding", { id: id });
}

function resetAllHotkeys() {
  if (hotkeyMutationPending) return;
  cancelRemapModal();
  if (!window.confirm("Restore all hotkeys to defaults?")) return;
  clearValidationUi();
  if (!beginHotkeyMutation()) return;
  sendAction("resetAllHotkeys");
}

function normalizeKey(e) {
  var code = e.code || "";
  var key = e.key || "";

  if (PHYSICAL_KEY_MAP[code]) {
    return PHYSICAL_KEY_MAP[code];
  }

  if (/^Key[A-Z]$/.test(code)) {
    return code.slice(3).toLowerCase();
  }

  if (/^F\d+$/.test(key)) return key;

  var keyMap = {
    ArrowLeft: "left",
    ArrowRight: "right",
    ArrowUp: "up",
    ArrowDown: "down",
    Escape: "escape",
    Enter: "return",
    Backspace: "delete",
    Delete: "forwarddelete",
    " ": "space",
    Tab: "tab"
  };
  return keyMap[key] || key.toLowerCase();
}

function displayKey(key) {
  var raw = String(key || "");
  var systemMeta = SYSTEM_KEY_DISPLAY[raw];
  if (systemMeta && systemMeta.label) return systemMeta.label;
  if (KEY_LABELS[raw]) return KEY_LABELS[raw];
  var systemCodeMatch = raw.match(/^SYSTEM_(\d+)$/);
  if (systemCodeMatch) {
    return "SYSTEM_" + systemCodeMatch[1];
  }
  if (/^[A-Z0-9_]+$/.test(raw) && raw.indexOf("_") !== -1) {
    return raw
      .toLowerCase()
      .split("_")
      .map(function (part) {
        return part ? part.charAt(0).toUpperCase() + part.slice(1) : part;
      })
      .join(" ");
  }
  return raw.toUpperCase();
}

function keycapHtml(content, title, className) {
  var classes = "keycap";
  if (className) classes += " " + className;
  return '<span class="' + classes + '" title="' + escapeHtml(title || "") + '">' + content + "</span>";
}

function comboHtml(mods, key) {
  if (key === false || key == null || key === "") {
    return "";
  }
  var parts = [];
  (mods || []).forEach(function (mod) {
    parts.push(keycapHtml(escapeHtml(MOD_SYMBOLS[mod] || mod), MOD_TITLES[mod] || String(mod), ""));
  });
  var rawKey = String(key || "");
  var systemMeta = SYSTEM_KEY_DISPLAY[rawKey];
  if (systemMeta && systemMeta.label && systemMeta.svg) {
    parts.push(keycapHtml(systemMeta.svg, systemMeta.label, "keycap-system"));
  } else {
    var label = displayKey(rawKey);
    parts.push(keycapHtml(escapeHtml(label), label, ""));
  }
  return parts.join("");
}

function filterHotkeyRows(value) {
  var query = (value || "").toLowerCase().trim();
  var rows = document.querySelectorAll("[data-hotkey-row]");
  rows.forEach(function (row) {
    var label = row.getAttribute("data-label") || "";
    var group = row.getAttribute("data-group") || "";
    var combo = row.getAttribute("data-combo") || "";
    var match = !query || label.indexOf(query) !== -1 || group.indexOf(query) !== -1 || combo.indexOf(query) !== -1;
    row.classList.toggle("is-hidden", !match);
  });

  document.querySelectorAll("[data-hotkey-group]").forEach(function (group) {
    var visible = group.querySelector("[data-hotkey-row]:not(.is-hidden)");
    group.classList.toggle("is-hidden", !visible);
  });
}

function handleSearchInput(value) {
  filterHotkeyRows(value);
}

var remapState = {
  open: false,
  targetId: null,
  targetLabel: "",
  currentMods: [],
  currentKey: null,
  currentModified: false,
  draftMods: [],
  draftKey: null,
  cleared: false,
  shellEl: null,
  labelEl: null,
  captureEl: null,
  currentEl: null,
  draftEl: null,
  errorEl: null,
  resetEl: null,
  unbindEl: null,
  saveEl: null,
  statusEl: null,
  hintEl: null
};

var hotkeyMutationPending = false;

function syncHotkeyMutationState() {
  document.querySelectorAll("[data-hotkey-action], [data-settings-tab-button], .settings-restore-btn").forEach(function (button) {
    if (button && typeof button.disabled === "boolean") {
      button.disabled = hotkeyMutationPending;
    }
  });
  document.querySelectorAll("[data-remap-mod]").forEach(function (button) {
    if (button && typeof button.disabled === "boolean") {
      button.disabled = hotkeyMutationPending;
    }
  });
  if (remapState.resetEl) {
    remapState.resetEl.disabled = hotkeyMutationPending || !remapState.currentModified;
  }
  if (remapState.unbindEl) {
    remapState.unbindEl.disabled = hotkeyMutationPending;
  }
  document.querySelectorAll('[data-remap-action="cancel"]').forEach(function (button) {
    if (button && typeof button.disabled === "boolean") {
      button.disabled = hotkeyMutationPending;
    }
  });
  if (remapState.captureEl) {
    remapState.captureEl.classList.toggle("is-busy", hotkeyMutationPending);
    remapState.captureEl.setAttribute("aria-busy", hotkeyMutationPending ? "true" : "false");
    remapState.captureEl.tabIndex = hotkeyMutationPending ? -1 : 0;
  }
}

function setHotkeyMutationPending(value) {
  hotkeyMutationPending = value === true;
  syncRemapActionState();
}

function beginHotkeyMutation() {
  if (hotkeyMutationPending) return false;
  setHotkeyMutationPending(true);
  return true;
}

function arraysEqual(left, right) {
  var a = left || [];
  var b = right || [];
  if (a.length !== b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] !== b[index]) return false;
  }
  return true;
}

function normalizeDraftMods(mods) {
  var order = { cmd: 1, alt: 2, ctrl: 3, shift: 4 };
  var seen = {};
  var out = [];
  (mods || []).forEach(function (mod) {
    if (!order[mod] || seen[mod]) return;
    seen[mod] = true;
    out.push(mod);
  });
  out.sort(function (a, b) {
    return order[a] - order[b];
  });
  return out;
}

function remapMatchesCurrent() {
  if (remapState.cleared) {
    return remapState.currentKey === false || remapState.currentKey == null || remapState.currentKey === "";
  }
  if (!remapState.draftKey) return false;
  return remapState.currentKey === remapState.draftKey && arraysEqual(remapState.currentMods, remapState.draftMods);
}

function focusRemapCapture() {
  if (!remapState.captureEl || !remapState.open) return;
  if (typeof remapState.captureEl.focus === "function") {
    try {
      remapState.captureEl.focus({ preventScroll: true });
    } catch (_err) {
      remapState.captureEl.focus();
    }
  }
}

function syncRemapActionState() {
  var canSave = !hotkeyMutationPending && (remapState.cleared || remapState.draftKey) && !remapMatchesCurrent();
  if (remapState.saveEl) {
    remapState.saveEl.disabled = !canSave;
  }
  syncHotkeyMutationState();
}

function renderRemapModifierState() {
  document.querySelectorAll("[data-remap-mod]").forEach(function (button) {
    var mod = button.getAttribute("data-remap-mod") || "";
    var active = remapState.draftMods.indexOf(mod) !== -1;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", active ? "true" : "false");
  });
}

function applyDraftBinding(mods, key) {
  remapState.cleared = false;
  remapState.draftMods = normalizeDraftMods(mods);
  remapState.draftKey = key === false ? false : (key || null);
  if (remapState.errorEl) {
    remapState.errorEl.textContent = "";
    remapState.errorEl.classList.add("is-hidden");
  }
  if (remapState.captureEl) {
    remapState.captureEl.classList.remove("has-error");
  }
  renderRemapPreview();
  focusRemapCapture();
}

function toggleRemapMod(mod) {
  var nextMods = remapState.draftMods.slice();
  var index = nextMods.indexOf(mod);
  if (index === -1) {
    nextMods.push(mod);
  } else {
    nextMods.splice(index, 1);
  }
  applyDraftBinding(nextMods, remapState.draftKey);
}

function setComboPreview(el, mods, key, emptyText) {
  if (!el) return;
  if (key === false || key == null || key === "") {
    el.innerHTML = '<span class="remap-preview-flow" aria-hidden="true"></span>';
    el.setAttribute("title", emptyText || "");
    el.classList.add("is-empty");
    return;
  }
  el.innerHTML = '<span class="remap-preview-flow">' + comboHtml(mods, key) + "</span>";
  el.removeAttribute("title");
  el.classList.remove("is-empty");
}

function renderRemapPreview() {
  if (!remapState.currentEl || !remapState.draftEl) return;
  setComboPreview(remapState.currentEl, remapState.currentMods, remapState.currentKey, "Unbound");

  var draftKey = remapState.cleared ? false : remapState.draftKey;
  var draftMods = remapState.cleared ? [] : remapState.draftMods;
  if (remapState.cleared) {
    setComboPreview(remapState.draftEl, [], false, "Will be unbound");
  } else if (draftKey) {
    setComboPreview(remapState.draftEl, draftMods, draftKey, "Press any shortcut");
  } else {
    setComboPreview(remapState.draftEl, [], false, "Press any shortcut");
  }

  if (remapState.captureEl) {
    remapState.captureEl.classList.toggle("is-armed", !remapState.cleared && !remapState.draftKey);
    remapState.captureEl.classList.toggle("is-ready", !!remapState.draftKey);
    remapState.captureEl.classList.toggle("is-cleared", remapState.cleared);
  }
  if (remapState.statusEl) {
    remapState.statusEl.textContent = remapState.cleared ? "Unbinding" : (draftKey ? "Ready" : "Listening");
  }
  if (remapState.hintEl) {
    if (remapState.cleared) {
      remapState.hintEl.textContent = "Save to remove this shortcut.";
    } else if (draftKey) {
      remapState.hintEl.textContent = remapMatchesCurrent()
        ? "This matches the current binding."
        : "Press Save to apply this binding.";
    } else if (draftMods.length > 0) {
      remapState.hintEl.textContent = "Select a main key, media key, or system key.";
    } else {
      remapState.hintEl.textContent = "Press any key, media key, or system key.";
    }
  }
  renderRemapModifierState();
  syncRemapActionState();
}

function openRemapModal(id) {
  if (hotkeyMutationPending) return;
  var row = document.querySelector('[data-hotkey-row][data-id="' + id + '"]');
  if (!row || !remapState.shellEl) return;

  clearValidationUi();
  remapState.open = true;
  remapState.targetId = id;
  remapState.targetLabel = row.getAttribute("data-label") || "";
  remapState.currentKey = row.getAttribute("data-assigned") === "1" ? row.getAttribute("data-key") : false;
  remapState.currentMods = (row.getAttribute("data-mods") || "").split(" ").filter(Boolean);
  remapState.currentModified = row.getAttribute("data-modified") === "1";
  remapState.draftMods = remapState.currentMods.slice();
  remapState.draftKey = remapState.currentKey || null;
  remapState.cleared = false;

  remapState.labelEl.textContent = row.querySelector(".hotkey-label").textContent;
  remapState.errorEl.textContent = "";
  remapState.errorEl.classList.add("is-hidden");
  remapState.shellEl.hidden = false;
  renderRemapPreview();
  focusRemapCapture();
  sendAction("openRemapRecorder", { id: id });
}

function cancelRemapModal(skipNativeSync) {
  var wasOpen = remapState.open === true;
  clearValidationUi();
  remapState.open = false;
  remapState.targetId = null;
  remapState.targetLabel = "";
  remapState.currentMods = [];
  remapState.currentKey = null;
  remapState.currentModified = false;
  remapState.draftMods = [];
  remapState.draftKey = null;
  remapState.cleared = false;
  if (remapState.errorEl) {
    remapState.errorEl.textContent = "";
    remapState.errorEl.classList.add("is-hidden");
  }
  if (remapState.captureEl) {
    remapState.captureEl.classList.remove("is-armed", "is-ready", "is-cleared", "has-error");
  }
  if (remapState.shellEl) remapState.shellEl.hidden = true;
  syncRemapActionState();
  if (!skipNativeSync && wasOpen) {
    sendAction("cancelRemapRecorder");
  }
}

function unbindRemapBinding() {
  remapState.cleared = true;
  remapState.draftMods = [];
  remapState.draftKey = false;
  if (remapState.errorEl) {
    remapState.errorEl.textContent = "";
    remapState.errorEl.classList.add("is-hidden");
  }
  if (remapState.captureEl) {
    remapState.captureEl.classList.remove("has-error");
  }
  renderRemapPreview();
  focusRemapCapture();
}

function resetRemapBinding() {
  if (!remapState.open || !remapState.targetId || !remapState.currentModified) return;
  clearValidationUi();
  if (!beginHotkeyMutation()) return;
  sendAction("resetHotkeyBinding", {
    id: remapState.targetId
  });
}

function saveRemapModal() {
  if (!remapState.open || !remapState.targetId) return;
  clearValidationUi();
  if (remapState.cleared) {
    if (!beginHotkeyMutation()) return;
    sendAction("updateHotkeyBinding", {
      id: remapState.targetId,
      mods: [],
      key: false
    });
    return;
  }
  if (!remapState.draftKey) return;
  if (!beginHotkeyMutation()) return;
  sendAction("updateHotkeyBinding", {
    id: remapState.targetId,
    mods: remapState.draftMods,
    key: remapState.draftKey
  });
}

var HARD_MIN_UI_SCALE_FLOOR = 0.6;
var MAX_UI_SCALE = 1.75;
var RESIZE_ZONE = 10;
var lastReportedBounds = null;

function setUiScale(scale) {
  document.documentElement.style.setProperty("--ui-scale", scale.toFixed(3));
}

function readPx(value) {
  return parseFloat(value || "0") || 0;
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
    + containerGap;
}

function targetMinHeight() {
  var policy = layoutPolicy();
  if (typeof policy.targetMinHeight === "number") {
    return policy.targetMinHeight;
  }
  return 320;
}

function settingsViewportBaseHeight() {
  var policy = layoutPolicy();
  if (typeof policy.viewportBaseHeight === "number") {
    return policy.viewportBaseHeight;
  }
  return 240;
}

function measureSettingsHeightAtScale(scale) {
  var shell = document.querySelector(".settings-window-shell");
  var settingsHead = document.querySelector(".settings-head");
  var settingsScroll = document.querySelector(".settings-scroll");
  if (!shell || !settingsHead || !settingsScroll) return 0;

  var total = measureContainerChromeHeight(scale);
  if (!total) return 0;

  var shellStyle = window.getComputedStyle(shell);
  var shellGap = readPx(shellStyle.rowGap || shellStyle.gap);
  var scrollStyle = window.getComputedStyle(settingsScroll);
  var viewportHeight = settingsViewportBaseHeight() * scale;

  return total
    + shellGap
    + settingsHead.getBoundingClientRect().height
    + readPx(scrollStyle.paddingTop)
    + readPx(scrollStyle.paddingBottom)
    + readPx(scrollStyle.borderTopWidth)
    + readPx(scrollStyle.borderBottomWidth)
    + viewportHeight;
}

function readLiveLayoutMetrics() {
  var shell = document.querySelector(".settings-window-shell");
  var settingsScroll = document.querySelector(".settings-scroll");
  return {
    shellHeight: shell ? shell.getBoundingClientRect().height : 0,
    scrollHeight: settingsScroll ? settingsScroll.getBoundingClientRect().height : 0
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

function reportSettingsBounds(bounds) {
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
    shellHeight: Number(layout.shellHeight.toFixed(3)),
    scrollHeight: Number(layout.scrollHeight.toFixed(3))
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
    && lastReportedBounds.shellHeight === next.shellHeight
    && lastReportedBounds.scrollHeight === next.scrollHeight
  ) {
    return;
  }
  lastReportedBounds = next;
  sendAction("updateSettingsBounds", next);
}

function computeVerticalSizingModel() {
  var measureFn = function (scale) {
    return measureSettingsHeightAtScale(scale);
  };
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

function updateUiScale() {
  var measureFn = function (scale) {
    return measureSettingsHeightAtScale(scale);
  };
  var minHeight = targetMinHeight();
  var model = computeVerticalSizingModel();
  if (!model) {
    setUiScale(1);
    reportSettingsBounds({
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

  var currentSolution = solveScaleForHeight(window.innerHeight, model.derivedMinUiScale, model.maxUiScale, measureFn);
  setUiScale(currentSolution.scale);
  model.currentHeight = window.innerHeight;
  model.currentUiScale = currentSolution.scale;
  reportSettingsBounds(model);
}

window.tapshopRecomputeBounds = function () {
  lastReportedBounds = null;
  updateUiScale();
};

function getResizeDirection(e) {
  var nearLeft = e.clientX <= RESIZE_ZONE;
  var nearRight = e.clientX >= window.innerWidth - RESIZE_ZONE;
  var nearTop = e.clientY <= RESIZE_ZONE;
  var nearBottom = e.clientY >= window.innerHeight - RESIZE_ZONE;

  if (nearTop && nearLeft) return "nw";
  if (nearTop && nearRight) return "ne";
  if (nearBottom && nearLeft) return "sw";
  if (nearBottom && nearRight) return "se";
  if (nearLeft) return "w";
  if (nearRight) return "e";
  if (nearTop) return "n";
  if (nearBottom) return "s";
  return "";
}

function cursorForDirection(direction) {
  if (direction === "n" || direction === "s") return "ns-resize";
  if (direction === "e" || direction === "w") return "ew-resize";
  if (direction === "ne" || direction === "sw") return "nesw-resize";
  if (direction === "nw" || direction === "se") return "nwse-resize";
  return "";
}

function setGlobalCursor(cursor) {
  document.documentElement.style.cursor = cursor || "";
  document.body.style.cursor = cursor || "";
}

var container = document.querySelector(".container");
var header = document.querySelector(".header");
var headerTooltip = document.querySelector(".header-tooltip");
var tooltipTarget = null;

function hideHeaderTooltip() {
  tooltipTarget = null;
  if (!headerTooltip) return;
  headerTooltip.classList.remove("is-visible");
  headerTooltip.textContent = "";
}

function showHeaderTooltip(el) {
  if (!container || !headerTooltip || !el) return;
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
  var buttonRect = el.getBoundingClientRect();
  var style = window.getComputedStyle(container);
  var paddingLeft = readPx(style.paddingLeft);
  var paddingRight = readPx(style.paddingRight);
  var tooltipRect = headerTooltip.getBoundingClientRect();
  var minLeft = paddingLeft + 6;
  var maxLeft = containerRect.width - tooltipRect.width - paddingRight - 6;
  var centeredLeft = (buttonRect.left - containerRect.left) + (buttonRect.width / 2) - (tooltipRect.width / 2);
  var left = Math.max(minLeft, Math.min(centeredLeft, maxLeft));
  var top = (buttonRect.bottom - containerRect.top) + 6;

  headerTooltip.style.left = left + "px";
  headerTooltip.style.top = top + "px";
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

document.addEventListener("click", function (e) {
  var hotkeyActionEl = e.target && e.target.closest ? e.target.closest("[data-hotkey-action]") : null;
  if (hotkeyActionEl) {
    var hotkeyAction = hotkeyActionEl.getAttribute("data-hotkey-action");
    var hotkeyId = hotkeyActionEl.getAttribute("data-hotkey-id") || "";
    e.preventDefault();
    if (hotkeyAction === "remap") {
      openRemapModal(hotkeyId);
      return;
    }
    if (hotkeyAction === "reset") {
      resetBinding(hotkeyId);
      return;
    }
  }

  var remapActionEl = e.target && e.target.closest ? e.target.closest("[data-remap-action]") : null;
  if (remapActionEl) {
    var remapAction = remapActionEl.getAttribute("data-remap-action");
    e.preventDefault();
    if (remapAction === "cancel") {
      cancelRemapModal();
      return;
    }
    if (remapAction === "reset") {
      resetRemapBinding();
      return;
    }
    if (remapAction === "unbind") {
      unbindRemapBinding();
      return;
    }
    if (remapAction === "save") {
      saveRemapModal();
      return;
    }
  }

  var remapModEl = e.target && e.target.closest ? e.target.closest("[data-remap-mod]") : null;
  if (remapModEl) {
    e.preventDefault();
    toggleRemapMod(remapModEl.getAttribute("data-remap-mod") || "");
    return;
  }

});

document.addEventListener("mousedown", function (e) {
  var captureEl = e.target && e.target.closest ? e.target.closest("[data-remap-capture]") : null;
  if (!captureEl) return;
  e.preventDefault();
  focusRemapCapture();
});

document.addEventListener("mousedown", function (e) {
  if (e.button !== 0) return;
  var direction = getResizeDirection(e);
  if (!direction) return;
  resizeState.active = true;
  resizeState.direction = direction;
  resizeState.lastX = e.screenX;
  resizeState.lastY = e.screenY;
  setGlobalCursor(cursorForDirection(direction));
  hideHeaderTooltip();
  sendAction("resizeStart", { direction: direction });
  e.preventDefault();
  e.stopPropagation();
}, true);

if (header) {
  header.addEventListener("mousedown", function (e) {
    if (e.button !== 0) return;
    if (e.target && e.target.closest && e.target.closest(".header-actions, button, input, label")) return;
    dragState.active = true;
    dragState.lastX = e.screenX;
    dragState.lastY = e.screenY;
    hideHeaderTooltip();
    sendAction("dragStart");
    e.preventDefault();
  });
}

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
  if (dragState.active) {
    dragState.active = false;
    sendAction("dragEnd");
  }

  if (resizeState.active) {
    resizeState.active = false;
    resizeState.direction = "";
    setGlobalCursor("");
    sendAction("resizeEnd");
  }
});

document.addEventListener("mousemove", function (e) {
  if (dragState.active || resizeState.active) return;
  setGlobalCursor(cursorForDirection(getResizeDirection(e)));
});

document.addEventListener("mouseleave", function () {
  if (dragState.active || resizeState.active) return;
  setGlobalCursor("");
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

document.addEventListener("keydown", function (e) {
  if (remapState.open) {
    e.preventDefault();
    e.stopPropagation();
    if (e.key === "Escape") {
      cancelRemapModal();
    }
    return;
  }

  if (e.key === "Escape") {
    e.preventDefault();
    e.stopPropagation();
    sendAction("close");
  }
});

window.addEventListener("resize", updateUiScale);
updateUiScale();
filterHotkeyRows(getSearchValue());
setSettingsTabState(currentSettingsTab());
restoreSettingsScrollState();

remapState.shellEl = document.querySelector("[data-remap-shell]");
remapState.labelEl = document.querySelector("[data-remap-label]");
remapState.captureEl = document.querySelector("[data-remap-capture]");
remapState.currentEl = document.querySelector("[data-remap-current]");
remapState.draftEl = document.querySelector("[data-remap-draft]");
remapState.errorEl = document.querySelector("[data-remap-error]");
remapState.resetEl = document.querySelector("[data-remap-reset]");
remapState.unbindEl = document.querySelector('[data-remap-action="unbind"]');
remapState.saveEl = document.querySelector("[data-remap-save]");
remapState.statusEl = document.querySelector("[data-remap-status]");
remapState.hintEl = document.querySelector("[data-remap-hint]");
syncRemapActionState();
]=]

return ClientScript
