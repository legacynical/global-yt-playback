local FakeHs = {}

local state = {}

local function makeScreen()
  return {
    frame = function()
      return { x = 0, y = 0, w = 1440, h = 900 }
    end,
  }
end

local function makeOutputDevice()
  return {
    level = 25,
    volume = function(self)
      return self.level
    end,
    setVolume = function(self, nextVolume)
      self.level = nextVolume
    end,
  }
end

local function makeImage(source)
  local image = {
    source = source,
    size = nil,
  }

  function image:setSize(size)
    self.size = {
      h = size and size.h or nil,
      w = size and size.w or nil,
    }
    return self
  end

  function image:encodeAsURLString()
    local width = self.size and self.size.w or 0
    local height = self.size and self.size.h or 0
    return string.format(
      "data:image/mock,%s:%s@%sx%s",
      tostring(self.source.kind),
      tostring(self.source.value),
      tostring(width),
      tostring(height)
    )
  end

  return image
end

local function resetState()
  state.settings = {}
  state.keyStrokes = {}
  state.sleepMicros = {}
  state.doAfterCalls = {}
  state.printf = {}
  state.frontmostWindow = nil
  state.frontmostWindowSequence = nil
  state.frontmostWindowIndex = 0
  state.absoluteTime = 0
  state.epochSeconds = 0
  state.outputDevice = makeOutputDevice()
  state.mouseScreen = makeScreen()
  state.mainScreen = makeScreen()
  state.mouseAbsolutePosition = { x = 0, y = 0 }
  state.runningApplications = {}
  state.windowsById = {}
  state.drawings = {}
  state.spaceTypes = {}
  state.activeSpace = 1
  state.focusedSpace = 1
  state.gotoSpaceCalls = {}
  state.closeMissionControlCalls = 0
  state.spaceWatchers = {}
  state.eventtaps = {}
end

local function encodeJson(value)
  local valueType = type(value)
  if valueType == "nil" then
    return "null"
  end
  if valueType == "number" or valueType == "boolean" then
    return tostring(value)
  end
  if valueType == "string" then
    return string.format("%q", value)
  end
  if valueType ~= "table" then
    return "\"<unsupported>\""
  end

  local maxIndex = 0
  local count = 0
  local isArray = true
  for key, _ in pairs(value) do
    count = count + 1
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      isArray = false
      break
    end
    if key > maxIndex then
      maxIndex = key
    end
  end
  if isArray and maxIndex ~= count then
    isArray = false
  end

  local parts = {}
  if isArray then
    for i = 1, maxIndex do
      parts[#parts + 1] = encodeJson(value[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  for key, item in pairs(value) do
    parts[#parts + 1] = string.format("%q", tostring(key)) .. ":" .. encodeJson(item)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local StyledText = {}
StyledText.__index = StyledText

local function coerceStyledText(value)
  if getmetatable(value) == StyledText then
    return value
  end

  return setmetatable({
    text = tostring(value or ""),
    runs = {},
  }, StyledText)
end

function StyledText.__concat(left, right)
  local lhs = coerceStyledText(left)
  local rhs = coerceStyledText(right)
  local runs = {}

  for _, run in ipairs(lhs.runs or {}) do
    runs[#runs + 1] = run
  end
  for _, run in ipairs(rhs.runs or {}) do
    runs[#runs + 1] = run
  end

  return setmetatable({
    text = (lhs.text or "") .. (rhs.text or ""),
    runs = runs,
  }, StyledText)
end

local function makeDrawing(kind, frame, payload)
  local drawing = {
    kind = kind,
    frame = frame,
    payload = payload,
    visible = false,
    deleted = false,
  }

  function drawing:setFill(value)
    self.fill = value
    return self
  end

  function drawing:setFillColor(value)
    self.fillColor = value
    return self
  end

  function drawing:setStroke(value)
    self.stroke = value
    return self
  end

  function drawing:setRoundedRectRadii(x, y)
    self.roundedRectRadii = { x = x, y = y }
    return self
  end

  function drawing:setLevel(value)
    self.level = value
    return self
  end

  function drawing:setBehavior(value)
    self.behavior = value
    return self
  end

  function drawing:setFrame(value)
    self.frame = value
    return self
  end

  function drawing:setTextSize(value)
    self.textSize = value
    return self
  end

  function drawing:setStyledText(value)
    self.payload = value
    return self
  end

  function drawing:show()
    self.visible = true
    return self
  end

  function drawing:delete()
    self.deleted = true
    self.visible = false
    return self
  end

  state.drawings[#state.drawings + 1] = drawing
  return drawing
end

local function makeCanvas(rect)
  local canvas = {
    rect = rect,
    elements = {},
    drawings = {},
    deleted = false,
    visible = false,
  }

  function canvas:level(value)
    self.levelValue = value
    return self
  end

  function canvas:behavior(value)
    self.behaviorValue = value
    return self
  end

  function canvas:frame(value)
    self.rect = value
    return self
  end

  function canvas:replaceElements(...)
    for _, drawing in ipairs(self.drawings) do
      drawing:delete()
    end
    self.drawings = {}
    self.elements = { ... }
    for _, element in ipairs(self.elements) do
      local drawing = makeDrawing(element.type, element.frame, element.text or element.image)
      drawing.canvasElement = element
      drawing.visible = self.visible
      self.drawings[#self.drawings + 1] = drawing
    end
    return self
  end

  function canvas:show()
    self.visible = true
    for _, drawing in ipairs(self.drawings) do
      if not drawing.deleted then
        drawing.visible = true
      end
    end
    return self
  end

  function canvas:delete()
    self.deleted = true
    self.visible = false
    for _, drawing in ipairs(self.drawings) do
      drawing:delete()
    end
    return self
  end

  return canvas
end

function FakeHs.install()
  resetState()
  _G.hs = {
    settings = {
      get = function(key)
        return state.settings[key]
      end,
      set = function(key, value)
        state.settings[key] = value
      end,
      clear = function(key)
        state.settings[key] = nil
      end,
    },
    json = {
      encode = function(value)
        return encodeJson(value)
      end,
    },
    application = {
      runningApplications = function()
        return state.runningApplications
      end,
    },
    window = {
      get = function(id)
        if state.windowsById then
          return state.windowsById[id]
        end
        return nil
      end,
      filter = {
        windowCreated = "windowCreated",
        windowDestroyed = "windowDestroyed",
        windowFocused = "windowFocused",
        windowTitleChanged = "windowTitleChanged",
        windowFullscreened = "windowFullscreened",
        windowUnfullscreened = "windowUnfullscreened",
        windowInCurrentSpace = "windowInCurrentSpace",
        windowNotInCurrentSpace = "windowNotInCurrentSpace",
        windowVisible = "windowVisible",
        windowMinimized = "windowMinimized",
        windowUnminimized = "windowUnminimized",
      },
      frontmostWindow = function()
        if state.frontmostWindowSequence then
          state.frontmostWindowIndex = state.frontmostWindowIndex + 1
          return state.frontmostWindowSequence[state.frontmostWindowIndex]
            or state.frontmostWindowSequence[#state.frontmostWindowSequence]
        end
        return state.frontmostWindow
      end,
    },
    spaces = {
      windowSpaces = function(win)
        if not win or not win.spaceIds then
          return {}
        end
        return win:spaceIds()
      end,
      spaceType = function(spaceId)
        return state.spaceTypes[spaceId] or "user"
      end,
      gotoSpace = function(spaceId)
        state.gotoSpaceCalls[#state.gotoSpaceCalls + 1] = spaceId
        state.activeSpace = spaceId
        state.focusedSpace = spaceId
        return true
      end,
      closeMissionControl = function()
        state.closeMissionControlCalls = state.closeMissionControlCalls + 1
        return true
      end,
      activeSpaceOnScreen = function()
        return state.activeSpace
      end,
      focusedSpace = function()
        return state.focusedSpace
      end,
      watcher = {
        new = function(fn)
          local watcher = {
            _fn = fn,
            _running = false,
          }
          function watcher:start()
            self._running = true
            state.spaceWatchers[#state.spaceWatchers + 1] = self
            return self
          end
          function watcher:stop()
            self._running = false
            return self
          end
          return watcher
        end,
      },
    },
    eventtap = {
      event = {
        types = {
          mouseMoved = 5,
          keyDown = 10,
          keyUp = 11,
          systemDefined = 14,
        },
      },
      new = function(types, fn)
        local tap = {
          _types = types,
          _fn = fn,
          _running = false,
        }
        function tap:start()
          self._running = true
          state.eventtaps[#state.eventtaps + 1] = self
          return self
        end
        function tap:stop()
          self._running = false
          return self
        end
        return tap
      end,
      keyStroke = function(mods, key, delay, app)
        state.keyStrokes[#state.keyStrokes + 1] = {
          mods = mods,
          key = key,
          delay = delay,
          app = app,
        }
      end,
    },
    timer = {
      absoluteTime = function()
        return state.absoluteTime
      end,
      secondsSinceEpoch = function()
        return state.epochSeconds
      end,
      doAfter = function(delay, fn)
        local handle = {
          delay = delay,
          fn = fn,
          stopped = false,
        }
        state.doAfterCalls[#state.doAfterCalls + 1] = handle
        return {
          stop = function()
            handle.stopped = true
          end,
        }
      end,
      usleep = function(micros)
        state.sleepMicros[#state.sleepMicros + 1] = micros
        state.epochSeconds = state.epochSeconds + (micros / 1e6)
      end,
    },
    mouse = {
      getCurrentScreen = function()
        return state.mouseScreen
      end,
      absolutePosition = function()
        return {
          x = state.mouseAbsolutePosition.x,
          y = state.mouseAbsolutePosition.y,
        }
      end,
    },
    screen = {
      mainScreen = function()
        return state.mainScreen
      end,
    },
    geometry = {
      rect = function(x, y, w, h)
        return {
          x = x,
          y = y,
          w = w,
          h = h,
        }
      end,
    },
    styledtext = {
      new = function(text, style)
        return setmetatable({
          text = tostring(text or ""),
          runs = {
            {
              text = tostring(text or ""),
              style = style,
            },
          },
        }, StyledText)
      end,
    },
    image = {
      imageFromAppBundle = function(bundleId)
        if type(bundleId) ~= "string" or bundleId == "" then
          return nil
        end
        return makeImage({
          kind = "bundle",
          value = bundleId,
        })
      end,
      imageFromPath = function(path)
        if type(path) ~= "string" or path == "" then
          return nil
        end
        return makeImage({
          kind = "path",
          value = path,
        })
      end,
    },
    drawing = {
      getTextDrawingSize = function(styledText)
        local text = styledText and styledText.text or ""
        return {
          w = #tostring(text) * 8,
          h = 16,
        }
      end,
      rectangle = function(frame)
        return makeDrawing("rectangle", frame, nil)
      end,
      text = function(frame, styledText)
        return makeDrawing("text", frame, styledText)
      end,
      windowLevels = {
        popUpMenu = 42,
      },
      windowBehaviors = {
        canJoinAllSpaces = 7,
      },
    },
    canvas = {
      new = function(rect)
        return makeCanvas(rect)
      end,
      windowLevels = {
        popUpMenu = 42,
      },
      windowBehaviors = {
        canJoinAllSpaces = 7,
      },
    },
    audiodevice = {
      defaultOutputDevice = function()
        return state.outputDevice
      end,
    },
    printf = function(fmt, ...)
      state.printf[#state.printf + 1] = string.format(fmt, ...)
    end,
  }
  return _G.hs
end

function FakeHs.state()
  return state
end

function FakeHs.setFrontmostWindow(win)
  state.frontmostWindow = win
  state.frontmostWindowSequence = nil
  state.frontmostWindowIndex = 0
end

function FakeHs.setFrontmostWindowSequence(sequence)
  state.frontmostWindowSequence = sequence
  state.frontmostWindowIndex = 0
end

function FakeHs.runScheduledTimers()
  local callbacks = state.doAfterCalls
  state.doAfterCalls = {}
  table.sort(callbacks, function(left, right)
    return left.delay < right.delay
  end)
  for _, entry in ipairs(callbacks) do
    if not entry.stopped then
      -- Keep wall-clock helpers in sync: async focus uses secondsSinceEpoch,
      -- while some debug paths use absoluteTime.
      state.absoluteTime = state.absoluteTime + math.floor(entry.delay * 1e9)
      state.epochSeconds = state.epochSeconds + entry.delay
      entry.fn()
    end
  end
end

function FakeHs.advanceAbsoluteTime(nanos)
  state.absoluteTime = state.absoluteTime + nanos
end

function FakeHs.advanceEpochSeconds(seconds)
  state.epochSeconds = state.epochSeconds + (seconds or 0)
end

function FakeHs.flushScheduledTimers(limit)
  local maxPasses = limit or 32
  for _ = 1, maxPasses do
    if #state.doAfterCalls == 0 then
      return
    end
    FakeHs.runScheduledTimers()
  end
end

function FakeHs.makeApplication(bundleId, appName, pid)
  local application = {
    _bundleId = bundleId,
    _appName = appName or "Test App",
    _pid = pid or 4242,
    _windows = {},
    hidden = false,
    activations = 0,
    unhideCalls = 0,
    bundleID = function()
      return bundleId
    end,
    name = function(self)
      return self._appName
    end,
    pid = function(self)
      return self._pid
    end,
    isHidden = function(self)
      return self.hidden
    end,
    unhide = function(self)
      self.hidden = false
      self.unhideCalls = self.unhideCalls + 1
    end,
    activate = function(self)
      self.activations = self.activations + 1
      return true
    end,
    allWindows = function(self)
      return self._windows
    end,
    setWindows = function(self, windows)
      self._windows = windows or {}
    end,
  }
  return application
end

function FakeHs.setRunningApplications(apps)
  state.runningApplications = apps or {}
end

function FakeHs.makeWindow(opts)
  local window = {
    _id = assert(opts.id, "window id is required"),
    _title = opts.title or "",
    _visible = opts.visible ~= false,
    _application = opts.application or FakeHs.makeApplication(opts.bundleId or "com.apple.Safari", opts.appName, opts.pid),
    _screen = opts.screen or makeScreen(),
    _frontmostOnFocus = opts.frontmostOnFocus ~= false,
    _fullscreen = opts.fullscreen == true,
    _spaceIds = opts.spaceIds or { 1 },
    minimized = opts.minimized == true,
    focusCalls = 0,
    unminimizeCalls = 0,
  }

  function window:id()
    return self._id
  end

  function window:title()
    return self._title
  end

  function window:setTitle(nextTitle)
    self._title = nextTitle
  end

  function window:isVisible()
    return self._visible
  end

  function window:setVisible(nextVisible)
    self._visible = nextVisible
  end

  function window:application()
    return self._application
  end

  function window:isFullScreen()
    return self._fullscreen
  end

  function window:setFullScreen(nextValue)
    self._fullscreen = nextValue == true
  end

  function window:spaceIds()
    return self._spaceIds
  end

  function window:setSpaceIds(nextSpaceIds)
    self._spaceIds = nextSpaceIds or {}
  end

  function window:isMinimized()
    return self.minimized
  end

  function window:unminimize()
    self.minimized = false
    self.unminimizeCalls = self.unminimizeCalls + 1
  end

  function window:focus()
    self.focusCalls = self.focusCalls + 1
    if self._frontmostOnFocus then
      state.frontmostWindow = self
      state.frontmostWindowSequence = nil
      state.frontmostWindowIndex = 0
    end
  end

  function window:isStandard()
    return true
  end

  function window:screen()
    return self._screen
  end

  function window:minimize()
    self.minimized = true
  end

  state.windowsById[window:id()] = window

  return window
end

function FakeHs.setSpaceType(spaceId, spaceType)
  state.spaceTypes[spaceId] = spaceType
end

function FakeHs.setActiveSpace(spaceId)
  state.activeSpace = spaceId
  state.focusedSpace = spaceId
end

function FakeHs.setFocusedSpace(spaceId)
  state.focusedSpace = spaceId
end

function FakeHs.setMouseAbsolutePosition(x, y)
  state.mouseAbsolutePosition = { x = x or 0, y = y or 0 }
end

function FakeHs.triggerSpaceChange()
  for _, watcher in ipairs(state.spaceWatchers) do
    if watcher._running and type(watcher._fn) == "function" then
      watcher._fn()
    end
  end
end

return FakeHs
