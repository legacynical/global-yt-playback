local Assert = require("assert")
local FakeHs = require("fake_hs")
local TestEnv = require("test_env")

local function makeConfig(overrides)
  local cfg = {
    tapshopMsgBottomMargin = 100,
    tapshopMsgWidth = 760,
    tapshopMsgTextSize = 14,
    tapshopMsgMaxLines = 25,
  }

  for key, value in pairs(overrides or {}) do
    cfg[key] = value
  end

  return cfg
end

local function makeToast(overrides)
  TestEnv.reset({
    "ui.toast",
  })
  local Toast = require("ui.toast")
  return Toast.new(makeConfig(overrides))
end

local function currentTextDrawing()
  local drawings = FakeHs.state().drawings
  for index = #drawings, 1, -1 do
    local drawing = drawings[index]
    if drawing.kind == "text" and not drawing.deleted then
      return drawing
    end
  end
  return nil
end

local function currentTextPayloads()
  local drawings = FakeHs.state().drawings
  local out = {}
  for _, drawing in ipairs(drawings) do
    if drawing.kind == "text" and not drawing.deleted then
      out[#out + 1] = drawing.payload
    end
  end
  return out
end

local function visibleText(styledText)
  local out = {}
  for _, run in ipairs(styledText.runs or {}) do
    local color = run.style and run.style.color or {}
    if (color.alpha == nil) or color.alpha > 0 then
      out[#out + 1] = run.text
    end
  end
  return table.concat(out)
end

local function visibleTexts()
  local out = {}
  for _, payload in ipairs(currentTextPayloads()) do
    out[#out + 1] = visibleText(payload)
  end
  return table.concat(out, "\n")
end

local function runTextByAlpha(styledText, alpha)
  local out = {}
  for _, run in ipairs(styledText.runs or {}) do
    local color = run.style and run.style.color or {}
    if color.alpha == alpha then
      out[#out + 1] = run.text
    end
  end
  return table.concat(out)
end

local function runTextsByAlpha(alpha)
  local out = {}
  for _, payload in ipairs(currentTextPayloads()) do
    out[#out + 1] = runTextByAlpha(payload, alpha)
  end
  return table.concat(out)
end

return {
  name = "Toast",
  cases = {
    {
      name = "renders the first plain-string toast with no prefix",
      run = function()
        local toast = makeToast()

        toast("Pairing Window 1")

        local textDrawing = currentTextDrawing()
        Assert.truthy(textDrawing, "expected a visible text drawing")
        Assert.equal(visibleText(textDrawing.payload), "Pairing Window 1")
      end,
    },
    {
      name = "renders the first styled toast with no prefix",
      run = function()
        local toast = makeToast()
        local accent = { red = 0.4, green = 0.8, blue = 1.0, alpha = 1 }

        toast({
          segments = {
            { text = "Pairing Window 2: " },
            { text = "[Browser] Docs", color = accent },
          },
        })

        local textDrawing = currentTextDrawing()
        Assert.truthy(textDrawing, "expected a visible text drawing")
        Assert.equal(visibleText(textDrawing.payload), "Pairing Window 2: [Browser] Docs")
      end,
    },
    {
      name = "appends new toasts beneath older ones with the newest marked",
      run = function()
        local toast = makeToast()

        toast("Destroyed")
        toast("Restored")
        toast("YT Target Updated")

        Assert.truthy(#currentTextPayloads() > 0, "expected visible text drawings")
        Assert.equal(visibleTexts(), " Destroyed\n Restored\n> YT Target Updated")
        Assert.equal(runTextsByAlpha(0), ">>")
      end,
    },
    {
      name = "resets the shared expiry timer when a new toast is appended",
      run = function()
        local toast = makeToast()

        toast("Destroyed", 0.5)
        toast("Restored", 2.0)

        local timers = FakeHs.state().doAfterCalls
        Assert.equal(#timers, 2)
        Assert.truthy(timers[1].stopped, "expected the older timer to be cancelled")
        Assert.falsy(timers[2].stopped, "expected the latest timer to remain active")
        Assert.equal(timers[2].delay, 2.0)

        FakeHs.runScheduledTimers()

        Assert.falsy(currentTextDrawing(), "expected the full stack to clear on the latest expiry")
      end,
    },
    {
      name = "stacks repeated identical toast lines with prefixes",
      run = function()
        local toast = makeToast()

        toast("Window 3 is recoverable")
        toast("Window 3 is recoverable")
        toast("Window 3 is recoverable")

        Assert.truthy(#currentTextPayloads() > 0, "expected visible text drawings")
        Assert.equal(visibleTexts(), " Window 3 is recoverable\n Window 3 is recoverable\n> Window 3 is recoverable")
        Assert.equal(runTextsByAlpha(0), ">>")
      end,
    },
    {
      name = "drops the oldest line when the stack exceeds the configured cap",
      run = function()
        local toast = makeToast({
          tapshopMsgMaxLines = 2,
        })

        toast("First")
        toast("Second")
        toast("Third")

        Assert.truthy(#currentTextPayloads() > 0, "expected visible text drawings")
        Assert.equal(visibleTexts(), " Second\n> Third")
        Assert.equal(runTextsByAlpha(0), ">")
      end,
    },
    {
      name = "clears the full stack and destroys both drawings when the timer expires",
      run = function()
        local toast = makeToast()

        toast("Pair")
        toast("Unpair")
        FakeHs.runScheduledTimers()

        local drawings = FakeHs.state().drawings
        Assert.falsy(currentTextDrawing(), "expected no visible text drawing after expiry")
        Assert.truthy(drawings[1].deleted, "expected the background drawing to be deleted")
        Assert.truthy(drawings[2].deleted, "expected the text drawing to be deleted")
      end,
    },
    {
      name = "preserves styled segmented payloads in the stacked renderer",
      run = function()
        local toast = makeToast()
        local accent = { red = 0.4, green = 0.8, blue = 1.0, alpha = 1 }

        toast({
          segments = {
            { text = "Restored Window 2: " },
            { text = "[Browser] Docs", color = accent },
          },
        })
        toast("YT Target Updated")

        Assert.truthy(#currentTextPayloads() > 0, "expected visible text drawings")
        Assert.equal(visibleTexts(), " Restored Window 2: [Browser] Docs\n> YT Target Updated")
        Assert.equal(runTextsByAlpha(0), ">")

        local foundAccent = false
        for _, payload in ipairs(currentTextPayloads()) do
          for _, run in ipairs(payload.runs or {}) do
            if run.text == "[Browser] Docs" then
              Assert.sameKeys(run.style.color, accent)
              foundAccent = true
            end
          end
        end
        Assert.truthy(foundAccent, "expected to preserve the styled segment color")
      end,
    },
  },
}
