local Assert = require("assert")
local TestEnv = require("test_env")

local function loadPolicy()
  TestEnv.reset({
    "state.popover_fullscreen_visibility",
  })
  return require("state.popover_fullscreen_visibility")
end

local function makePopoverStub(opts)
  opts = opts or {}
  local shown = opts.shown == true
  local stub = {
    hideCalls = 0,
    ensureCalls = 0,
    showCalls = 0,
    syncCalls = 0,
  }

  function stub:isShown()
    return shown
  end

  function stub:hide()
    stub.hideCalls = stub.hideCalls + 1
    shown = false
  end

  function stub:ensureVisible()
    stub.ensureCalls = stub.ensureCalls + 1
    shown = true
  end

  function stub:show()
    stub.showCalls = stub.showCalls + 1
    shown = true
  end

  function stub:syncWindowLevel()
    stub.syncCalls = stub.syncCalls + 1
  end

  return stub
end

local function makePolicy(opts)
  opts = opts or {}
  local PopoverFullscreenVisibility = loadPolicy()
  local focusedSpaceId = opts.focusedSpaceId or 1
  local enabled = opts.enabled ~= false
  local fullscreenSpaces = opts.fullscreenSpaces or { [9] = true }
  local popover = opts.popover or makePopoverStub({ shown = opts.shown == true })
  local scheduled = {}

  local policy = PopoverFullscreenVisibility.new({
    isEnabled = function()
      return enabled
    end,
    isSpaceFullscreen = function(spaceId)
      return fullscreenSpaces[spaceId] == true
    end,
    getFocusedSpaceId = function()
      return focusedSpaceId
    end,
    refreshFocusedSpaceId = function()
      return focusedSpaceId
    end,
    getPopover = function()
      return popover
    end,
    schedule = function(delay, fn)
      scheduled[#scheduled + 1] = { delay = delay, fn = fn }
    end,
  })

  return {
    policy = policy,
    popover = popover,
    scheduled = scheduled,
    setFocusedSpaceId = function(spaceId)
      focusedSpaceId = spaceId
    end,
    setEnabled = function(value)
      enabled = value == true
    end,
    runOldestSettle = function()
      local item = table.remove(scheduled, 1)
      if item then
        item.fn()
      end
    end,
  }
end

return {
  name = "PopoverFullscreenVisibility",
  cases = {
    {
      name = "hides shown popover on fullscreen Space and restores after leaving",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 9 })
        ctx.policy:onFocusedSpaceChanged()

        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.popover:isShown(), false)
        Assert.equal(ctx.policy:isRestorePinned(), true)
        Assert.equal(ctx.popover.ensureCalls, 0)

        ctx.setFocusedSpaceId(1)
        ctx.policy:onFocusedSpaceChanged()

        Assert.equal(ctx.popover.ensureCalls, 1)
        Assert.equal(ctx.popover:isShown(), true)
        Assert.equal(ctx.policy:isRestorePinned(), false)
      end,
    },
    {
      name = "does not force-show when leaving fullscreen if popover was not open",
      run = function()
        local ctx = makePolicy({ shown = false, focusedSpaceId = 9 })
        ctx.policy:onFocusedSpaceChanged()

        Assert.equal(ctx.popover.hideCalls, 0)
        Assert.equal(ctx.policy:isRestorePinned(), false)

        ctx.setFocusedSpaceId(1)
        ctx.policy:onFocusedSpaceChanged()

        Assert.equal(ctx.popover.ensureCalls, 0)
        Assert.equal(ctx.popover.showCalls, 0)
      end,
    },
    {
      name = "beforeEnteringSpace hides preemptively for fullscreen targets",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 1 })
        ctx.policy:beforeEnteringSpace(9)

        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), true)

        ctx.policy:beforeEnteringSpace(1)
        Assert.equal(ctx.popover.hideCalls, 1)
      end,
    },
    {
      name = "intentional dismiss clears restore pin",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 9 })
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.policy:isRestorePinned(), true)

        ctx.policy:noteIntentionalDismiss()
        Assert.equal(ctx.policy:isRestorePinned(), false)

        ctx.setFocusedSpaceId(1)
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.popover.ensureCalls, 0)
      end,
    },
    {
      name = "enabling the setting while on a fullscreen Space hides immediately",
      run = function()
        local ctx = makePolicy({
          shown = true,
          focusedSpaceId = 9,
          enabled = false,
        })
        ctx.setEnabled(true)
        ctx.policy:onSettingChanged(true)

        Assert.equal(ctx.popover.syncCalls, 1)
        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), true)
      end,
    },
    {
      name = "disabling the setting clears a stale restore pin",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 9 })
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.policy:isRestorePinned(), true)

        ctx.setEnabled(false)
        ctx.policy:onSettingChanged(false)

        Assert.equal(ctx.popover.syncCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), false)

        ctx.setFocusedSpaceId(1)
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.popover.ensureCalls, 0)
      end,
    },
    {
      name = "settle pass re-reconciles after lagged Space type",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 1 })
        -- First pass: still looks like a desktop Space.
        ctx.policy:onWindowFullscreened()
        Assert.equal(ctx.popover.hideCalls, 0)
        Assert.equal(#ctx.scheduled, 3)

        -- Lag resolves on the first settle tick.
        ctx.setFocusedSpaceId(9)
        ctx.runOldestSettle()

        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), true)
      end,
    },
    {
      name = "leave-FS restore retries across settle ladder when Space type lags",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 9 })
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), true)
        Assert.equal(#ctx.scheduled, 3)

        -- Immediate + first settles still look like FS (stale).
        ctx.runOldestSettle()
        Assert.equal(ctx.popover.ensureCalls, 0)
        Assert.equal(ctx.policy:isRestorePinned(), true)

        -- Second settle finally sees the desktop Space.
        ctx.setFocusedSpaceId(1)
        ctx.runOldestSettle()
        Assert.equal(ctx.popover.ensureCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), false)
      end,
    },
    {
      name = "keeps restore pin when ensureVisible does not stick",
      run = function()
        local popover = makePopoverStub({ shown = true })
        function popover:ensureVisible()
          popover.ensureCalls = popover.ensureCalls + 1
          -- Fail to become shown.
        end
        local ctx = makePolicy({
          shown = true,
          focusedSpaceId = 9,
          popover = popover,
        })
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.policy:isRestorePinned(), true)

        ctx.setFocusedSpaceId(1)
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.popover.ensureCalls, 1)
        Assert.equal(ctx.popover:isShown(), false)
        Assert.equal(ctx.policy:isRestorePinned(), true)
      end,
    },
    {
      name = "reconcile restores after preemptive hide if still on a desktop Space",
      run = function()
        local ctx = makePolicy({ shown = true, focusedSpaceId = 1 })
        ctx.policy:beforeEnteringSpace(9)
        Assert.equal(ctx.popover.hideCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), true)

        -- Space switch never left the desktop (failed gotoSpace / cancelled).
        ctx.policy:onFocusedSpaceChanged()
        Assert.equal(ctx.popover.ensureCalls, 1)
        Assert.equal(ctx.policy:isRestorePinned(), false)
      end,
    },
    {
      name = "disabled policy is a no-op",
      run = function()
        local ctx = makePolicy({
          shown = true,
          focusedSpaceId = 9,
          enabled = false,
        })
        ctx.policy:onFocusedSpaceChanged()
        ctx.policy:beforeEnteringSpace(9)

        Assert.equal(ctx.popover.hideCalls, 0)
        Assert.equal(ctx.policy:isRestorePinned(), false)
      end,
    },
  },
}
