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
  var workspaceList = document.querySelector(".workspace-list");
  var total = measureContainerChromeHeight(scale);
  if (!total) return 0;
  if (!workspaceList) return total;
  return total + workspaceList.getBoundingClientRect().height;
}

function readLiveLayoutMetrics() {
  var bodyShell = document.querySelector(".body-shell");
  var workspaceList = document.querySelector(".workspace-list");
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
  return hitTestSelectorList(x, y, [".slot-icon-btn", ".btn", ".header-btn", ".profile-btn"]);
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
    if (next.classList.contains("slot-icon-btn")) {
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
    && target.closest(".header-actions, .title-logo, .slot-icon-btn, .confirm-shell, .resize-handle, button, input, label, a, select, textarea")
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
    if (isUnpairAllConfirmOpen()) {
      hideUnpairAllConfirm();
      return;
    }
    sendAction("close");
  }
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
updateUiScale();
focusKeyboardSurface();
]=]

return ClientScript
