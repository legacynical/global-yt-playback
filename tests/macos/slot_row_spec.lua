local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TestEnv = require("test_env")

local function loadModules()
  TestEnv.reset({
    "state.workspace",
    "state.slot_row",
  })
  local Workspace = require("state.workspace")
  local SlotRow = require("state.slot_row")
  return Workspace, SlotRow
end

return {
  name = "SlotRow",
  cases = {
    {
      name = "renders empty rows without icon or badge",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local slot = Workspace.new(1, "Window 1", 2)
        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = Fakes.createWindowService(),
        })

        Assert.equal(row.state, "empty")
        Assert.equal(row.badgeText, nil)
        Assert.equal(row.iconBundleID, nil)
        Assert.equal(row.className, "unpaired")
      end,
    },
    {
      name = "renders minimized rows from the live paired window",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local paired = FakeHs.makeWindow({
          id = 11,
          title = "Docs",
          minimized = true,
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 1 },
        })
        local windowService = Fakes.createWindowService({
          paired,
        })
        local slot = Workspace.new(1, "Window 1", 2)

        slot:pair(11, windowService.pairingMetadata(paired))
        slot:setBaseSpaceId(1)

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = windowService,
        })

        Assert.equal(row.state, "minimized")
        Assert.equal(row.label, "Docs")
        Assert.equal(row.badgeText, "MIN")
        Assert.equal(row.iconBundleID, "com.apple.Safari")
        Assert.equal(row.className, "paired-minimized")
      end,
    },
    {
      name = "renders fullscreen rows with the full badge",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local paired = FakeHs.makeWindow({
          id = 21,
          title = "Docs",
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 1 },
        })
        local fullscreen = FakeHs.makeWindow({
          id = 22,
          title = "Video",
          fullscreen = true,
          bundleId = "com.apple.Safari",
          appName = "Safari",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          paired,
          fullscreen,
        })
        local slot = Workspace.new(1, "Window 1", 2)

        slot:pair(21, windowService.pairingMetadata(paired))
        slot:setBaseSpaceId(1)
        slot:setFullscreenState({
          fullscreenWindowId = 22,
          fullscreenSpaceId = 2,
          lastKnownSpaceId = 1,
        })

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = windowService,
        })

        Assert.equal(row.state, "fullscreen")
        Assert.equal(row.label, "Video")
        Assert.equal(row.badgeText, "FULL")
        Assert.equal(row.className, "paired-fullscreen")
      end,
    },
    {
      name = "renders tracked fullscreen rows even when live lookup is temporarily unavailable",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local slot = Workspace.new(1, "Window 1", 2)

        slot:pair(21, {
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Video",
          titleNormalized = "video",
        })
        slot:setBaseSpaceId(1)
        slot:setFullscreenState({
          fullscreenWindowId = 22,
          fullscreenSpaceId = 2,
          lastKnownSpaceId = 1,
        })

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = Fakes.createWindowService(),
        })

        Assert.equal(row.state, "fullscreen")
        Assert.equal(row.label, "Video")
        Assert.equal(row.badgeText, "FULL")
        Assert.equal(row.className, "paired-fullscreen")
      end,
    },
    {
      name = "renders off-space rows cheaply from cached base space",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local paired = FakeHs.makeWindow({
          id = 31,
          title = "Mail",
          bundleId = "com.apple.mail",
          appName = "Mail",
          spaceIds = { 2 },
        })
        local windowService = Fakes.createWindowService({
          paired,
        })
        local slot = Workspace.new(1, "Window 1", 2)

        slot:pair(31, windowService.pairingMetadata(paired))
        slot:setBaseSpaceId(2)

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = windowService,
        })

        Assert.equal(row.state, "off_space")
        Assert.equal(row.label, "Mail")
        Assert.equal(row.badgeText, nil)
        Assert.equal(row.className, "paired-off-space")
      end,
    },
    {
      name = "renders unresolved rows from stored fingerprint metadata",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local slot = Workspace.new(1, "Window 1", 2)

        slot:pair(41, {
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Release Notes",
          titleNormalized = "release notes",
        })
        slot:setBaseSpaceId(1)

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = Fakes.createWindowService(),
        })

        Assert.equal(row.state, "unresolved")
        Assert.equal(row.label, "Release Notes")
        Assert.equal(row.iconBundleID, "com.apple.Safari")
        Assert.equal(row.className, "paired-unresolved")
      end,
    },
    {
      name = "renders recoverable rows with muted icon and stored title",
      run = function()
        FakeHs.install()
        local Workspace, SlotRow = loadModules()
        local slot = Workspace.new(1, "Window 1", 2)

        slot:setRecoverable({
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Release Notes",
          titleNormalized = "release notes",
        }, 100)

        local row = SlotRow.build(slot, { focusedSpaceId = 1 }, {
          windowService = Fakes.createWindowService(),
        })

        Assert.equal(row.state, "recoverable")
        Assert.equal(row.label, "Release Notes")
        Assert.equal(row.iconBundleID, "com.apple.Safari")
        Assert.truthy(row.iconMuted)
        Assert.equal(row.badgeText, nil)
        Assert.equal(row.className, "recoverable")
      end,
    },
  },
}
