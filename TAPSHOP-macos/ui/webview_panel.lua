local WebviewPanel = {}

function WebviewPanel.new(opts)
  local panel = {}
  local webview = nil
  local usercontent = nil
  local isShown = false
  local cachedHtml = nil
  local isHtmlDirty = true

  local function resolveValue(value)
    if type(value) == "function" then
      return value(panel)
    end
    return value
  end

  local function applyBehavior(view)
    local behavior = resolveValue(opts.behavior)
    if behavior == nil then
      return
    end

    if type(behavior) == "table" and type(view.behaviorAsLabels) == "function" then
      view:behaviorAsLabels(behavior)
      return
    end

    if type(view.behavior) == "function" then
      if type(behavior) == "number" then
        view:behavior(behavior)
        return
      end

      if type(behavior) == "table" and hs.drawing and hs.drawing.windowBehaviors then
        local mask = 0
        for _, value in ipairs(behavior) do
          local flag = type(value) == "number" and value or hs.drawing.windowBehaviors[value]
          if type(flag) ~= "number" then
            return
          end
          mask = mask | flag
        end
        view:behavior(mask)
      end
    end
  end

  local function ensureWebview()
    if webview then
      return webview
    end

    if opts.messageHandler then
      usercontent = hs.webview.usercontent.new(opts.messageHandler)
      if opts.handleAction then
        usercontent:setCallback(function(msg)
          opts.handleAction(panel, msg)
        end)
      end
    end

    local rect = resolveValue(opts.initialRect)
    webview = hs.webview.new(rect, opts.webviewOptions or { developerExtrasEnabled = false }, usercontent)

    if opts.windowStyle then
      webview:windowStyle(resolveValue(opts.windowStyle))
    end
    if opts.transparent ~= nil then
      webview:transparent(opts.transparent)
    end
    if opts.level then
      webview:level(resolveValue(opts.level))
    end
    applyBehavior(webview)

    webview:allowNewWindows(false)
    webview:allowNavigationGestures(false)
    webview:allowTextEntry(opts.allowTextEntry == true)

    if opts.windowCallback then
      webview:windowCallback(function(...)
        opts.windowCallback(panel, ...)
      end)
    end

    if opts.onCreate then
      opts.onCreate(panel, webview)
    end

    return webview
  end

  function panel:getWebview()
    return ensureWebview()
  end

  function panel:isShown()
    return isShown
  end

  function panel:hasContent()
    return cachedHtml ~= nil
  end

  function panel:markDirty()
    isHtmlDirty = true
  end

  function panel:setLevel(level)
    if webview then
      webview:level(level)
    end
  end

  function panel:syncBehavior()
    if webview then
      applyBehavior(webview)
    end
  end

  function panel:evaluateJavaScript(script, callback)
    local view = ensureWebview()
    if callback then
      return view:evaluateJavaScript(script, callback)
    end
    return view:evaluateJavaScript(script)
  end

  function panel:refresh()
    local view = ensureWebview()
    cachedHtml = opts.buildHtml(panel)
    isHtmlDirty = false
    view:html(cachedHtml)
  end

  function panel:show()
    local view = ensureWebview()
    if opts.beforeShow then
      opts.beforeShow(panel, view)
    end
    if opts.level then
      view:level(resolveValue(opts.level))
    end
    applyBehavior(view)
    if isHtmlDirty or not cachedHtml then
      panel:refresh()
    end
    view:show()
    isShown = true
    if opts.afterShow then
      opts.afterShow(panel, view)
    end
  end

  function panel:hide()
    if not isShown then
      return
    end
    if opts.beforeHide then
      opts.beforeHide(panel, webview)
    end
    isShown = false
    if webview then
      webview:hide()
    end
    if opts.afterHide then
      opts.afterHide(panel, webview)
    end
  end

  function panel:toggle()
    if isShown then
      panel:hide()
    else
      panel:show()
    end
  end

  function panel:syncVisibility(enabled)
    if enabled then
      panel:show()
      return
    end
    panel:hide()
  end

  return panel
end

return WebviewPanel
