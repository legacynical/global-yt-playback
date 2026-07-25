local Assert = require("assert")
local TestEnv = require("test_env")

return {
  name = "Workspace",
  cases = {
    {
      name = "initializes with empty slot state",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 2)

        Assert.equal(workspace.name, "Window 1")
        Assert.falsy(workspace:isPaired())
        Assert.equal(workspace.binding.kind, "empty")
        Assert.equal(workspace.interaction.repeatBuffer, 2)
      end,
    },
    {
      name = "pairs and clears a window",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 3)

        workspace:pair(42, {
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Example - YouTube",
          titleNormalized = "example - youtube",
        })
        Assert.truthy(workspace:isPaired())
        Assert.equal(workspace.binding.kind, "paired")
        Assert.equal(workspace.binding.baseWindowId, 42)
        Assert.equal(workspace.binding.fingerprint.bundleID, "com.apple.Safari")
        Assert.equal(workspace.binding.fingerprint.titleNormalized, "example - youtube")
        Assert.equal(workspace.interaction.repeatBuffer, 3)

        workspace:clear()
        Assert.falsy(workspace:isPaired())
        Assert.equal(workspace.binding.kind, "empty")
        Assert.equal(workspace.binding.baseWindowId, nil)
        Assert.equal(workspace.binding.baseSpaceId, nil)
        Assert.equal(workspace.binding.fingerprint.bundleID, nil)
        Assert.equal(workspace.interaction.repeatBuffer, 3)
      end,
    },
    {
      name = "destroy-path clears live id and preserves recovery metadata",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 2)

        workspace:pair(42, {
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Example - YouTube",
          titleNormalized = "example - youtube",
        })
        workspace:markClosedForRecovery()

        Assert.falsy(workspace:isPaired())
        Assert.equal(workspace.binding.kind, "recoverable")
        Assert.equal(workspace.binding.baseWindowId, nil)
        Assert.equal(workspace.binding.baseSpaceId, nil)
        Assert.equal(workspace.binding.fingerprint.bundleID, "com.apple.Safari")
        Assert.equal(workspace.binding.fingerprint.titleNormalized, "example - youtube")
        Assert.truthy(workspace:canRecover())
      end,
    },
    {
      name = "recoverable slots remain durable until explicitly cleared",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 2)

        workspace:setRecoverable({
          bundleID = "com.apple.Safari",
          appName = "Safari",
          titleRaw = "Example - YouTube",
          titleNormalized = "example - youtube",
        })

        Assert.equal(workspace.binding.kind, "recoverable")
        Assert.truthy(workspace:canRecover())
        Assert.equal(workspace.binding.fingerprint.bundleID, "com.apple.Safari")

        workspace:clear()

        Assert.equal(workspace.binding.kind, "empty")
        Assert.equal(workspace.binding.fingerprint.bundleID, nil)
        Assert.falsy(workspace:canRecover())
      end,
    },
    {
      name = "consumes repeat presses until minimize threshold",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 2)

        workspace:pair(7, "Browser")
        Assert.equal(workspace:consumeRepeatPress(), 1)
        Assert.falsy(workspace:shouldMinimize())
        Assert.equal(workspace:consumeRepeatPress(), 0)
        Assert.truthy(workspace:shouldMinimize())
      end,
    },
    {
      name = "tracks and clears fullscreen state independently of base pairing",
      run = function()
        TestEnv.reset({
          "state.workspace",
        })
        local Workspace = require("state.workspace")
        local workspace = Workspace.new(1, "Window 1", 2)

        workspace:pair(7, "Browser")
        workspace:setBaseSpaceId(1)
        workspace:setFullscreenState({
          fullscreenWindowId = 8,
          fullscreenSpaceId = 4,
        })

        Assert.truthy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(workspace.binding.fullscreenTarget.windowId, 8)
        Assert.equal(workspace.binding.fullscreenTarget.spaceId, 4)
        -- Overlay-only updates must not clobber advisory home Space.
        Assert.equal(workspace.binding.baseSpaceId, 1)

        workspace:setFullscreenState({
          fullscreenWindowId = 8,
          fullscreenSpaceId = 4,
          lastKnownSpaceId = 9,
        })
        Assert.equal(workspace.binding.baseSpaceId, 9)

        workspace:clearFullscreenState()

        Assert.equal(workspace.binding.baseWindowId, 7)
        Assert.falsy(workspace:hasTrackedFullscreenTarget())
        Assert.equal(workspace.binding.baseSpaceId, 9)
      end,
    },
  },
}
