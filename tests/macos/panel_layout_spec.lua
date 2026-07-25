local Assert = require("assert")
local TestEnv = require("test_env")

local function loadPanelLayout()
  TestEnv.reset({
    "ui.panel_layout",
  })
  return require("ui.panel_layout")
end

local function makePopoverLayout(PanelLayout)
  return PanelLayout.create({
    defaultSize = { w = 500, h = 273 },
    minWidth = 150,
    targetMinHeight = 125,
    loadSavedSize = function(appdata)
      return appdata.getPopoverSize()
    end,
  })
end

local function makeSettingsLayout(PanelLayout)
  return PanelLayout.create({
    defaultSize = { w = 420, h = 320 },
    minWidth = 420,
    targetMinHeight = 320,
    viewportBaseHeight = 240,
    loadSavedSize = function(appdata)
      return appdata.getSettingsWindowSize()
    end,
  })
end

return {
  name = "PanelLayout",
  cases = {
    {
      name = "popover profile clamps size and frames",
      run = function()
        local PanelLayout = loadPanelLayout()
        local Layout = makePopoverLayout(PanelLayout)
        local screenFrame = { x = 100, y = 50, w = 1200, h = 900 }
        local runtimeBounds = Layout.initialRuntimeBounds()

        Assert.equal(Layout.clientPolicy().targetMinHeight, 125)
        Assert.equal(runtimeBounds.minHeight, nil)
        Assert.equal(runtimeBounds.maxHeight, nil)

        local size = Layout.loadSavedSize({
          getPopoverSize = function()
            return { w = 480, h = 290 }
          end,
        })
        Assert.equal(size.w, 480)
        Assert.equal(size.h, 290)

        size = Layout.clampSize({ w = 120, h = 90 }, screenFrame, runtimeBounds)
        Assert.equal(size.w, 150)
        Assert.equal(size.h, 125)

        local frame = Layout.clampFrame({
          x = 1100,
          y = 700,
          w = 900,
          h = 1000,
        }, screenFrame, runtimeBounds)
        Assert.equal(frame.x, 400)
        Assert.equal(frame.y, 82)
        Assert.equal(frame.w, 900)
        Assert.equal(frame.h, 868)

        local measured = Layout.initialRuntimeBounds()
        measured.maxHeight = 320
        frame = Layout.clampFrame({
          x = 1100,
          y = 700,
          w = 900,
          h = 700,
        }, screenFrame, measured)
        Assert.equal(frame.x, 400)
        Assert.equal(frame.y, 630)
        Assert.equal(frame.w, 900)
        Assert.equal(frame.h, 320)

        frame = Layout.frameForTopLeft({
          x = 160,
          y = 120,
        }, screenFrame, {
          w = 260,
          h = 180,
        }, runtimeBounds)
        Assert.equal(frame.x, 160)
        Assert.equal(frame.y, 120)
        Assert.equal(frame.w, 260)
        Assert.equal(frame.h, 180)
      end,
    },
    {
      name = "settings profile clamps size, frames, and centered layout",
      run = function()
        local PanelLayout = loadPanelLayout()
        local Layout = makeSettingsLayout(PanelLayout)
        local screenFrame = { x = 100, y = 50, w = 1200, h = 900 }
        local runtimeBounds = Layout.initialRuntimeBounds()
        local policy = Layout.clientPolicy()

        Assert.equal(policy.targetMinHeight, 320)
        Assert.equal(policy.viewportBaseHeight, 240)

        local size = Layout.loadSavedSize({
          getSettingsWindowSize = function()
            return { w = 600, h = 440 }
          end,
        })
        Assert.equal(size.w, 600)
        Assert.equal(size.h, 440)

        size = Layout.clampSize({ w = 200, h = 200 }, screenFrame, runtimeBounds)
        Assert.equal(size.w, 420)
        Assert.equal(size.h, 320)

        local frame = Layout.clampFrame({
          x = 1100,
          y = 700,
          w = 900,
          h = 1000,
        }, screenFrame, runtimeBounds)
        Assert.equal(frame.x, 400)
        Assert.equal(frame.y, 82)
        Assert.equal(frame.w, 900)
        Assert.equal(frame.h, 868)

        local measured = Layout.initialRuntimeBounds()
        measured.maxHeight = 560
        frame = Layout.clampFrame({
          x = 1100,
          y = 700,
          w = 900,
          h = 700,
        }, screenFrame, measured)
        Assert.equal(frame.x, 400)
        Assert.equal(frame.y, 390)
        Assert.equal(frame.w, 900)
        Assert.equal(frame.h, 560)

        frame = Layout.centeredFrame(screenFrame, {
          w = 560,
          h = 420,
        }, runtimeBounds)
        Assert.equal(frame.x, 420)
        Assert.equal(frame.y, 290)
        Assert.equal(frame.w, 560)
        Assert.equal(frame.h, 420)
      end,
    },
  },
}
