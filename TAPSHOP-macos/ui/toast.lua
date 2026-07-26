local Toast = {}

local DEFAULT_TEXT_COLOR = { white = 1, alpha = 1 }
local SWATCH_IMAGE_CACHE = {}

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = item
  end
  return out
end

local function parseHexColor(value)
  if type(value) ~= "string" then
    return nil
  end
  local r, g, b = value:match("^%s*#(%x%x)(%x%x)(%x%x)%s*$")
  if not r then
    return nil
  end
  return {
    red = tonumber(r, 16) / 255,
    green = tonumber(g, 16) / 255,
    blue = tonumber(b, 16) / 255,
    alpha = 1,
  }
end

local function normalizeColorValue(value)
  if type(value) == "table" and value.red ~= nil then
    return {
      red = tonumber(value.red) or 0,
      green = tonumber(value.green) or 0,
      blue = tonumber(value.blue) or 0,
      alpha = tonumber(value.alpha) or 1,
    }
  end
  return parseHexColor(value)
end

function Toast.colorSwatchImage(color, size)
  local fill = normalizeColorValue(color)
  if not fill or not hs.canvas then
    return nil
  end

  local px = math.max(12, math.floor(tonumber(size) or 16))
  local cacheKey = string.format(
    "%d_%.3f_%.3f_%.3f_%.3f",
    px,
    fill.red,
    fill.green,
    fill.blue,
    fill.alpha
  )
  local cached = SWATCH_IMAGE_CACHE[cacheKey]
  if cached then
    return cached
  end

  local radius = math.max(2, math.floor(px * 0.22))
  local canvas = hs.canvas.new({ x = 0, y = 0, w = px, h = px })
  canvas[1] = {
    type = "rectangle",
    action = "fill",
    frame = { x = 0, y = 0, w = px, h = px },
    fillColor = fill,
    roundedRectRadii = { xRadius = radius, yRadius = radius },
  }
  canvas[2] = {
    type = "rectangle",
    action = "stroke",
    frame = { x = 0.5, y = 0.5, w = px - 1, h = px - 1 },
    strokeColor = { white = 1, alpha = 0.22 },
    strokeWidth = 1,
    roundedRectRadii = { xRadius = radius, yRadius = radius },
  }

  local image = canvas:imageFromCanvas()
  canvas:delete()
  if not image then
    return nil
  end

  SWATCH_IMAGE_CACHE[cacheKey] = image
  return image
end

local function normalizeSegment(segment)
  if type(segment) ~= "table" then
    return {
      text = tostring(segment or ""),
      color = copyTable(DEFAULT_TEXT_COLOR),
    }
  end

  return {
    text = tostring(segment.text or ""),
    color = copyTable(segment.color) or copyTable(DEFAULT_TEXT_COLOR),
  }
end

local function normalizeLine(line)
  if type(line) ~= "table" then
    return {
      segments = {
        normalizeSegment(line),
      },
    }
  end

  local segments = {}
  if type(line.segments) == "table" then
    for _, segment in ipairs(line.segments) do
      segments[#segments + 1] = normalizeSegment(segment)
    end
  elseif line.text ~= nil then
    segments[#segments + 1] = normalizeSegment({
      text = line.text,
      color = line.color,
    })
  end

  if #segments == 0 then
    segments[#segments + 1] = normalizeSegment("")
  end

  local bundleID = nil
  if type(line.imageBundleID) == "string" and line.imageBundleID ~= "" then
    bundleID = line.imageBundleID
  end

  local appName = nil
  if type(line.imageAppName) == "string" and line.imageAppName ~= "" then
    appName = line.imageAppName
  end

  local imagePath = nil
  if type(line.imagePath) == "string" and line.imagePath ~= "" then
    imagePath = line.imagePath
  end

  local imageColor = nil
  if line.imageColor ~= nil then
    imageColor = line.imageColor
  end

  return {
    image = line.image,
    imageBundleID = bundleID,
    imageAppName = appName,
    imagePath = imagePath,
    imageColor = imageColor,
    segments = segments,
  }
end

Toast.message = {}

function Toast.message.plain(text, opts)
  local options = opts or {}
  return {
    duration = options.duration,
    lines = {
      {
        segments = {
          {
            text = tostring(text or ""),
            color = copyTable(options.color) or copyTable(DEFAULT_TEXT_COLOR),
          },
        },
      },
    },
  }
end

function Toast.message.status(text, opts)
  local message = Toast.message.plain(text, opts)
  local options = opts or {}

  if type(options.imageBundleID) == "string" and options.imageBundleID ~= "" then
    message.lines[1].imageBundleID = options.imageBundleID
  end
  if type(options.imageAppName) == "string" and options.imageAppName ~= "" then
    message.lines[1].imageAppName = options.imageAppName
  end
  if type(options.imagePath) == "string" and options.imagePath ~= "" then
    message.lines[1].imagePath = options.imagePath
  end
  if options.imageColor ~= nil then
    message.lines[1].imageColor = options.imageColor
  end
  if options.image ~= nil then
    message.lines[1].image = options.image
  end

  return message
end

function Toast.message.profile(name, color, opts)
  local options = opts or {}
  return Toast.message.status(tostring(name or ""), {
    duration = options.duration or 2.0,
    color = options.color,
    imageColor = color,
  })
end

function Toast.message.windowAction(opts)
  local options = opts or {}
  local titleText = options.titleText
  if titleText == nil or titleText == "" then
    titleText = "[empty]"
  end

  local segments = {
    {
      text = tostring(options.prefixText or ""),
      color = copyTable(options.prefixColor) or copyTable(DEFAULT_TEXT_COLOR),
    },
  }

  -- Optional label after a leading color swatch: "Pairing " + swatch + "Matcha [3]: "
  if options.labelText ~= nil and tostring(options.labelText) ~= "" then
    segments[#segments + 1] = {
      text = tostring(options.labelText),
      color = copyTable(options.labelColor)
        or copyTable(options.prefixColor)
        or copyTable(DEFAULT_TEXT_COLOR),
    }
  end

  segments[#segments + 1] = {
    text = tostring(titleText),
    color = copyTable(options.titleColor) or copyTable(DEFAULT_TEXT_COLOR),
  }

  local line = {
    imageBundleID = options.bundleID,
    imageAppName = options.appName,
    imagePath = options.imagePath,
    imageColor = options.imageColor,
    image = options.image,
    segments = segments,
  }

  if options.suffixText ~= nil and options.suffixText ~= "" then
    line.segments[#line.segments + 1] = {
      text = tostring(options.suffixText),
      color = copyTable(options.suffixColor) or copyTable(DEFAULT_TEXT_COLOR),
    }
  end

  return {
    duration = options.duration,
    lines = { line },
  }
end

function Toast.message.normalize(input, defaultDuration)
  if type(input) == "table" then
    local lines = {}

    if type(input.lines) == "table" then
      for _, line in ipairs(input.lines) do
        lines[#lines + 1] = normalizeLine(line)
      end
    elseif type(input.segments) == "table" or input.text ~= nil then
      lines[#lines + 1] = normalizeLine(input)
    end

    if #lines > 0 then
      return {
        duration = input.duration ~= nil and input.duration or defaultDuration,
        lines = lines,
      }
    end
  end

  local plain = Toast.message.plain(tostring(input or ""), {
    duration = defaultDuration,
  })

  return {
    duration = plain.duration,
    lines = {
      normalizeLine(plain.lines[1]),
    },
  }
end

function Toast.new(cfg)
  local lines = {}
  local timer = nil
  local canvas = nil
  local defaultSecs = 2.0
  local prefixColor = { white = 1, alpha = 0.55 }
  local hiddenPrefixColor = { white = 1, alpha = 0 }
  local iconGap = 8
  local padding = 14
  local cornerRadius = 8

  local function styledChunk(text, color)
    return hs.styledtext.new(tostring(text), {
      color = color or DEFAULT_TEXT_COLOR,
      font = {
        name = ".AppleSystemUIFont",
        size = cfg.tapshopMsgTextSize,
      },
    })
  end

  local function lineHeight()
    return math.floor(cfg.tapshopMsgTextSize * 1.35)
  end

  local function imagePixelSize()
    return math.max(12, math.floor(lineHeight() * 0.95))
  end

  local function sizedImage(image)
    if not image then
      return nil
    end
    local size = imagePixelSize()
    -- Avoid mutating Hammerspoon's shared app-bundle image cache.
    if image.copy and image.setSize then
      return image:copy():setSize({ h = size, w = size })
    end
    if image.setSize then
      return image:setSize({ h = size, w = size })
    end
    return image
  end

  local function colorSwatchImage(line)
    if type(line) ~= "table" or line.imageColor == nil then
      return nil
    end
    return Toast.colorSwatchImage(line.imageColor, imagePixelSize())
  end

  local function appOrPathImage(line)
    if type(line) ~= "table" then
      return nil
    end

    if line.image then
      return sizedImage(line.image)
    end

    local imagePath = line.imagePath
    if type(imagePath) == "string"
      and imagePath ~= ""
      and hs.image
      and hs.image.imageFromPath then
      local image = hs.image.imageFromPath(imagePath)
      if image then
        return sizedImage(image)
      end
    end

    local bundleID = line.imageBundleID
    if (type(bundleID) ~= "string" or bundleID == "")
      and type(line.imageAppName) == "string"
      and line.imageAppName ~= "" then
      local app = hs.application.find(line.imageAppName)
      bundleID = app and app:bundleID() or nil
    end

    if type(bundleID) ~= "string" or bundleID == "" then
      return nil
    end

    local image = hs.image.imageFromAppBundle(bundleID)
    if not image then
      return nil
    end

    return sizedImage(image)
  end

  local function lineImage(line)
    -- Prefer explicit image / app icon; fall back to color swatch for status/profile lines.
    return appOrPathImage(line) or colorSwatchImage(line)
  end

  local function pickScreen()
    return hs.mouse.getCurrentScreen()
      or (hs.window.frontmostWindow() and hs.window.frontmostWindow():screen())
      or hs.screen.mainScreen()
  end

  local function computeRects(lineCount)
    local screen = pickScreen()
    local visibleFrame = screen:frame()
    local width = cfg.tapshopMsgWidth
    local height = padding * 2 + (lineCount * lineHeight())

    local x = math.floor(visibleFrame.x + (visibleFrame.w - width) / 2)
    local y = math.floor(visibleFrame.y + visibleFrame.h - cfg.tapshopMsgBottomMargin - height)

    local rect = hs.geometry.rect(x, y, width, height)
    local contentRect = {
      x = padding,
      y = padding,
      w = width - padding * 2,
      h = height - padding * 2,
    }

    return rect, contentRect
  end

  local function destroy()
    if timer then
      timer:stop()
      timer = nil
    end
    if canvas then
      canvas:delete()
      canvas = nil
    end
  end

  local function styledSegments(segments, prefixStyled)
    local styledText = prefixStyled

    for _, segment in ipairs(segments or {}) do
      styledText = (styledText or styledChunk("", DEFAULT_TEXT_COLOR))
        .. styledChunk(segment.text or "", segment.color)
    end

    return styledText or styledChunk(" ", DEFAULT_TEXT_COLOR)
  end

  local function prefixStyledText(isLatest, showPrefixes)
    if not showPrefixes then
      return nil
    end

    local styledText = styledChunk("", DEFAULT_TEXT_COLOR)
    if isLatest then
      return styledText .. styledChunk("> ", prefixColor)
    end

    return styledText
      .. styledChunk(">", hiddenPrefixColor)
      .. styledChunk(" ", prefixColor)
  end

  local function resolveLineParts(line, isLatest, showPrefixes)
    local prefix = prefixStyledText(isLatest, showPrefixes)
    local segments = line.segments or {}
    local appImage = appOrPathImage(line)
    local swatchImage = colorSwatchImage(line)

    -- windowAction with label split:
    -- "> Pairing " + swatch + "Matcha [3]: " + app icon + title
    if appImage and #segments >= 3 then
      local parts = {}
      if prefix then
        parts[#parts + 1] = { kind = "text", styled = prefix }
      end
      parts[#parts + 1] = { kind = "text", styled = styledSegments({ segments[1] }) }
      if swatchImage then
        parts[#parts + 1] = { kind = "image", image = swatchImage }
      end
      parts[#parts + 1] = { kind = "text", styled = styledSegments({ segments[2] }) }
      parts[#parts + 1] = { kind = "image", image = appImage }
      parts[#parts + 1] = {
        kind = "text",
        styled = styledSegments({ table.unpack(segments, 3) }),
        flexible = true,
      }
      return parts
    end

    -- Legacy windowAction: "> Pairing …:" + app icon + title
    if appImage and #segments >= 2 then
      local parts = {}
      if prefix then
        parts[#parts + 1] = { kind = "text", styled = prefix }
      end
      if swatchImage then
        parts[#parts + 1] = { kind = "image", image = swatchImage }
      end
      parts[#parts + 1] = { kind = "text", styled = styledSegments({ segments[1] }) }
      parts[#parts + 1] = { kind = "image", image = appImage }
      parts[#parts + 1] = {
        kind = "text",
        styled = styledSegments({ table.unpack(segments, 2) }),
        flexible = true,
      }
      return parts
    end

    -- status/profile: "> " + swatch/icon + title (arrow must not sit between swatch and name)
    local image = appImage or swatchImage
    if image then
      local parts = {}
      if prefix then
        parts[#parts + 1] = { kind = "text", styled = prefix }
      end
      parts[#parts + 1] = { kind = "image", image = image }
      parts[#parts + 1] = {
        kind = "text",
        styled = styledSegments(segments),
        flexible = true,
      }
      return parts
    end

    return {
      { kind = "text", styled = styledSegments(segments, prefix), flexible = true },
    }
  end

  local function buildElements(rect, contentRect)
    local elements = {
      {
        id = "background",
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = cornerRadius, yRadius = cornerRadius },
        fillColor = { red = 0, green = 0, blue = 0, alpha = 0.70 },
        frame = { x = 0, y = 0, w = rect.w, h = rect.h },
      },
    }

    local currentLineHeight = lineHeight()
    local imageSize = math.max(12, math.floor(currentLineHeight * 0.95))
    local showPrefixes = #lines > 1

    for i = 1, #lines do
      local line = lines[i]
      local parts = resolveLineParts(line, i == #lines, showPrefixes)
      local lineY = contentRect.y + ((i - 1) * currentLineHeight)
      local cursorX = contentRect.x
      local remainingWidth = contentRect.w

      for partIndex, part in ipairs(parts) do
        if part.kind == "image" then
          elements[#elements + 1] = {
            id = string.format("line_%d_part_%d_image", i, partIndex),
            type = "image",
            action = "fill",
            image = part.image,
            imageScaling = "scaleProportionally",
            frame = {
              x = cursorX,
              y = lineY + math.max(0, math.floor((currentLineHeight - imageSize) / 2)),
              w = imageSize,
              h = imageSize,
            },
          }
          cursorX = cursorX + imageSize + iconGap
          remainingWidth = math.max(0, (contentRect.x + contentRect.w) - cursorX)
        else
          local desired = hs.drawing.getTextDrawingSize(part.styled)
          local partWidth = remainingWidth
          if not part.flexible then
            partWidth = desired and math.ceil(desired.w) + 4 or remainingWidth
            partWidth = math.min(math.max(1, partWidth), remainingWidth)
          end

          elements[#elements + 1] = {
            id = string.format("line_%d_part_%d_text", i, partIndex),
            type = "text",
            action = "fill",
            text = part.styled,
            frame = {
              x = cursorX,
              y = lineY,
              w = math.max(1, partWidth),
              h = currentLineHeight,
            },
          }
          cursorX = cursorX + partWidth
          remainingWidth = math.max(0, (contentRect.x + contentRect.w) - cursorX)
        end
      end
    end

    return elements
  end

  local function ensureCanvas(rect)
    if not canvas then
      canvas = hs.canvas.new(rect)
      canvas:level(hs.canvas.windowLevels.popUpMenu)
      canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    else
      canvas:frame(rect)
    end
    return canvas
  end

  local function render()
    local rect, contentRect = computeRects(#lines)
    local target = ensureCanvas(rect)
    local elements = buildElements(rect, contentRect)
    target:replaceElements(table.unpack(elements))
    target:show()
  end

  local function scheduleClear(secs)
    if timer then
      timer:stop()
      timer = nil
    end

    timer = hs.timer.doAfter(secs or defaultSecs, function()
      lines = {}
      destroy()
    end)
  end

  -- Append line(s), paint immediately, reset the shared expiry timer.
  -- Rapid callers (profile hops) naturally rebuild the stack; no deferred latch.
  return function(msg, secs)
    local normalized = Toast.message.normalize(msg, secs)
    for _, line in ipairs(normalized.lines) do
      lines[#lines + 1] = line
    end
    if #lines > cfg.tapshopMsgMaxLines then
      while #lines > cfg.tapshopMsgMaxLines do
        table.remove(lines, 1)
      end
    end
    render()
    scheduleClear(normalized.duration or secs or defaultSecs)
  end
end

return Toast
