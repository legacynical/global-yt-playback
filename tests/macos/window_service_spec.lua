local Assert = require("assert")
local FakeHs = require("fake_hs")
local TestEnv = require("test_env")

local function makeConfig(overrides)
  local cfg = {
    focusWaitTimeout = 0.05,
    focusPollMicros = 1000,
    focusPollInterval = 0.001,
    spaceSwitchPollInterval = 0.05,
    spaceSwitchPollMaxInterval = 0.20,
    spaceSwitchPollBackoff = 1.5,
    spaceSwitchMaxAttempts = 5,
    fullscreenSpaceSwitchDelay = 0.20,
    spaceSwitchFocusVerifyDelay = 0.05,
    spaceSwitchWindowResolveAttempts = 4,
    spaceSwitchFocusAttempts = 2,
    isGuiDebugMode = false,
  }

  for key, value in pairs(overrides or {}) do
    cfg[key] = value
  end

  return cfg
end

local function scheduledDelays()
  local delays = {}
  for _, entry in ipairs(FakeHs.state().doAfterCalls) do
    if not entry.stopped then
      delays[#delays + 1] = entry.delay
    end
  end
  return delays
end

local function makeService()
  TestEnv.reset({
    "services.window_service",
  })
  return require("services.window_service")
end

return {
  name = "WindowService",
  cases = {
    {
      name = "focused-space helpers do not rely on mainScreen when focusedSpace is available",
      run = function()
        local service = makeService()
        local mainScreenCalls = 0
        local activeSpaceOnScreenCalls = 0
        local focusedSpaceCalls = 0

        hs.screen.mainScreen = function()
          mainScreenCalls = mainScreenCalls + 1
          return {}
        end
        hs.spaces.activeSpaceOnScreen = function()
          activeSpaceOnScreenCalls = activeSpaceOnScreenCalls + 1
          return 3
        end
        hs.spaces.focusedSpace = function()
          focusedSpaceCalls = focusedSpaceCalls + 1
          return 9
        end

        local result = service.focusedSpaceId()

        Assert.equal(result, 9)
        Assert.equal(focusedSpaceCalls, 1)
        Assert.equal(mainScreenCalls, 0)
        Assert.equal(activeSpaceOnScreenCalls, 0)
      end,
    },
    {
      name = "requestFrontmost focuses immediately without blocking waits",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 101,
          title = "Mail",
          minimized = true,
        })
        local app = target:application()
        app.hidden = true
        FakeHs.setFrontmostWindow(nil)

        local result = service.requestFrontmost(target)
        local state = FakeHs.state()

        Assert.truthy(result.ok)
        Assert.equal(result.code, "focus_requested")
        Assert.equal(result.windowId, 101)
        Assert.equal(target.focusCalls, 1)
        Assert.equal(target.unminimizeCalls, 1)
        Assert.equal(app.unhideCalls, 1)
        Assert.equal(app.activations, 0)
        Assert.equal(#state.sleepMicros, 0)
        Assert.equal(#state.doAfterCalls, 0)
      end,
    },
    {
      name = "requestFrontmost does not schedule retries or delayed work",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 102,
          title = "Notes",
        })
        FakeHs.setFrontmostWindow(nil)

        local result = service.requestFrontmost(target)
        Assert.equal(result.code, "focus_requested")
        Assert.equal(target.focusCalls, 1)

        FakeHs.setFrontmostWindow(nil)
        FakeHs.runScheduledTimers()

        Assert.equal(target.focusCalls, 1)
      end,
    },
    {
      name = "ensureFrontmostAsync verifies frontmost without usleep busy-wait",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 103,
          title = "Safari",
          frontmostOnFocus = false,
        })
        FakeHs.setFrontmostWindowSequence({
          nil,
          nil,
          target,
        })

        local completion = nil
        local started = service.ensureFrontmostAsync(target, makeConfig(), function(result, win, token)
          completion = {
            result = result,
            win = win,
            token = token,
          }
        end)

        Assert.truthy(started.ok)
        Assert.equal(started.code, "ensure_frontmost_async_started")
        Assert.equal(target.focusCalls, 1)
        Assert.equal(completion, nil)
        Assert.equal(#FakeHs.state().sleepMicros, 0)

        -- Opening isFrontmost check already consumed the first nil in the sequence.
        FakeHs.runScheduledTimers()
        Assert.equal(completion, nil)

        FakeHs.runScheduledTimers()
        Assert.truthy(completion)
        Assert.truthy(completion.result.ok)
        Assert.equal(completion.result.code, "focus_verified")
        Assert.equal(completion.result.windowId, 103)
        Assert.equal(completion.win:id(), 103)
        Assert.equal(#FakeHs.state().sleepMicros, 0)
      end,
    },
    {
      name = "ensureFrontmostAsync reports missing_window for nil targets",
      run = function()
        local service = makeService()
        local completion = nil

        local started = service.ensureFrontmostAsync(nil, makeConfig(), function(result, win, token)
          completion = {
            result = result,
            win = win,
            token = token,
          }
        end)

        Assert.truthy(started.ok)
        Assert.equal(started.code, "ensure_frontmost_async_started")
        Assert.truthy(completion)
        Assert.falsy(completion.result.ok)
        Assert.equal(completion.result.code, "missing_window")
        Assert.equal(completion.result.windowId, nil)
        Assert.equal(completion.win, nil)
      end,
    },
    {
      name = "ensureFrontmostAsync times out without blocking the hotkey thread",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 113,
          title = "Never Front",
          frontmostOnFocus = false,
        })
        FakeHs.setFrontmostWindow(nil)

        local completion = nil
        service.ensureFrontmostAsync(target, makeConfig({
          focusWaitTimeout = 0.003,
          focusPollInterval = 0.001,
        }), function(result)
          completion = result
        end)

        FakeHs.flushScheduledTimers(16)

        Assert.truthy(completion)
        Assert.falsy(completion.ok)
        Assert.equal(completion.code, "focus_timeout")
        Assert.equal(#FakeHs.state().sleepMicros, 0)
      end,
    },
    {
      name = "newer ensureFrontmostAsync cancels an in-flight verification",
      run = function()
        local service = makeService()
        local first = FakeHs.makeWindow({
          id = 114,
          title = "First",
          frontmostOnFocus = false,
        })
        local second = FakeHs.makeWindow({
          id = 115,
          title = "Second",
          frontmostOnFocus = true,
        })
        FakeHs.setFrontmostWindow(nil)

        local firstCompletion = "pending"
        local secondCompletion = nil
        service.ensureFrontmostAsync(first, makeConfig({
          focusWaitTimeout = 1.0,
          focusPollInterval = 0.05,
        }), function(result)
          firstCompletion = result
        end)
        service.ensureFrontmostAsync(second, makeConfig(), function(result)
          secondCompletion = result
        end)

        FakeHs.flushScheduledTimers(8)

        Assert.equal(firstCompletion, "pending")
        Assert.truthy(secondCompletion)
        Assert.truthy(secondCompletion.ok)
        Assert.equal(secondCompletion.code, "focus_verified")
      end,
    },
    {
      name = "normalizes titles for conservative recovery matching",
      run = function()
        local service = makeService()

        local result = service.normalizeWindowTitle("  ChatGPT  -  Chrome \n")

        Assert.equal(result, "chatgpt - chrome")
      end,
    },
    {
      name = "builds pairing metadata from window and app state",
      run = function()
        local service = makeService()
        local win = FakeHs.makeWindow({
          id = 104,
          title = "Docs - YouTube",
          bundleId = "com.apple.Safari",
          appName = "Safari",
        })

        local result = service.pairingMetadata(win)

        Assert.equal(result.bundleID, "com.apple.Safari")
        Assert.equal(result.appName, "Safari")
        Assert.equal(result.titleRaw, "Docs - YouTube")
        Assert.equal(result.titleNormalized, "docs - youtube")
        Assert.equal(result.displayTitle, "[Safari] Docs - YouTube")
      end,
    },
    {
      name = "returns fullscreen space information for tracked windows",
      run = function()
        local service = makeService()
        local win = FakeHs.makeWindow({
          id = 105,
          title = "Video",
          fullscreen = true,
          spaceIds = { 7 },
        })
        FakeHs.setSpaceType(7, "fullscreen")

        Assert.truthy(service.isWindowFullscreen(win))
        Assert.equal(service.getPrimarySpaceForWindow(win), 7)
        Assert.truthy(service.isFullscreenSpace(7))
      end,
    },
    {
      name = "fullscreen check tolerates stale window handles",
      run = function()
        local service = makeService()
        local staleWindow = {
          isFullScreen = function()
            error("window handle is stale")
          end,
        }

        Assert.falsy(service.isWindowFullscreen(staleWindow))
      end,
    },
    {
      name = "cross-space focus waits asynchronously for delayed Space settlement",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 106,
          title = "Video",
        })
        local gotoCalls = {}
        local completion = nil
        hs.spaces.gotoSpace = function(spaceId)
          gotoCalls[#gotoCalls + 1] = spaceId
          return true
        end
        FakeHs.setFocusedSpace(2)
        FakeHs.setFrontmostWindow(nil)

        local result = service.requestFrontmostInSpace(106, 8, makeConfig(), function(outcome)
          completion = outcome
        end)

        Assert.truthy(result.ok)
        Assert.equal(result.code, "space_switch_requested")
        Assert.equal(gotoCalls[1], 8)
        Assert.equal(target.focusCalls, 0)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 0)
        Assert.equal(#FakeHs.state().sleepMicros, 0)

        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 0)
        Assert.equal(completion, nil)

        FakeHs.setFocusedSpace(8)
        FakeHs.runScheduledTimers()
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1, "dismiss Mission Control once on Space settle")
        Assert.equal(target.focusCalls, 0)

        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 1)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1, "happy-path focus must not re-dismiss Mission Control")

        FakeHs.runScheduledTimers()
        Assert.truthy(completion.ok)
        Assert.equal(completion.code, "focus_verified_after_space_switch")
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)
      end,
    },
    {
      name = "cross-space settle polling uses adaptive backoff",
      run = function()
        local service = makeService()
        FakeHs.makeWindow({ id = 116, title = "Backoff" })
        hs.spaces.gotoSpace = function()
          return true
        end
        FakeHs.setFocusedSpace(2)

        local result = service.requestFrontmostInSpace(116, 8, makeConfig({
          spaceSwitchPollInterval = 0.05,
          spaceSwitchPollMaxInterval = 0.20,
          spaceSwitchPollBackoff = 1.5,
          spaceSwitchMaxAttempts = 6,
        }))
        Assert.truthy(result.ok)

        local observed = {}
        for _ = 1, 4 do
          local delays = scheduledDelays()
          Assert.equal(#delays, 1)
          observed[#observed + 1] = delays[1]
          FakeHs.runScheduledTimers()
        end

        Assert.equal(observed[1], 0.05)
        Assert.truthy(math.abs(observed[2] - 0.075) < 1e-9, "second settle delay should grow by backoff")
        Assert.truthy(math.abs(observed[3] - 0.1125) < 1e-9, "third settle delay should continue backoff")
        Assert.truthy(math.abs(observed[4] - 0.16875) < 1e-9, "fourth settle delay should continue backoff")
        Assert.equal(FakeHs.state().closeMissionControlCalls, 0, "settle misses must not dismiss Mission Control")
      end,
    },
    {
      name = "cross-space focus waits for exact window materialization after settlement",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 107,
          title = "Mail",
        })
        local baseGetWindowById = service.getWindowById
        local materialized = false
        local completion = nil
        service.getWindowById = function(id)
          if id == 107 and not materialized then
            return nil
          end
          return baseGetWindowById(id)
        end

        local result = service.requestFrontmostInSpace(107, 8, makeConfig(), function(outcome)
          completion = outcome
        end)
        Assert.truthy(result.ok)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1, "immediate settle dismisses once")

        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 0)
        Assert.equal(completion, nil)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1, "resolve retries must not dismiss Mission Control")

        materialized = true
        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 1)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)
        FakeHs.runScheduledTimers()
        Assert.truthy(completion.ok)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)
      end,
    },
    {
      name = "cross-space focus failure dismisses Mission Control once then retries",
      run = function()
        local service = makeService()
        local target = FakeHs.makeWindow({
          id = 117,
          title = "Retry Focus",
          frontmostOnFocus = false,
        })
        local completion = nil
        FakeHs.setFrontmostWindow(nil)

        local result = service.requestFrontmostInSpace(117, 8, makeConfig({
          spaceSwitchFocusAttempts = 2,
        }), function(outcome)
          completion = outcome
        end)
        Assert.truthy(result.ok)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)

        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 1)
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)

        FakeHs.runScheduledTimers()
        Assert.equal(FakeHs.state().closeMissionControlCalls, 2, "first verify miss may dismiss Mission Control once more")
        Assert.equal(completion, nil)

        FakeHs.setFrontmostWindow(target)
        FakeHs.runScheduledTimers()
        Assert.equal(target.focusCalls, 2)
        FakeHs.runScheduledTimers()
        Assert.truthy(completion.ok)
        Assert.equal(completion.code, "focus_verified_after_space_switch")
        Assert.equal(FakeHs.state().closeMissionControlCalls, 2, "later focus retries must not keep dismissing")
      end,
    },
    {
      name = "newer focus request cancels pending cross-space focus",
      run = function()
        local service = makeService()
        local first = FakeHs.makeWindow({ id = 108, title = "First" })
        local second = FakeHs.makeWindow({ id = 109, title = "Second" })
        local firstCompletion = nil
        local secondCompletion = nil

        service.requestFrontmostInSpace(108, 8, makeConfig(), function(outcome)
          firstCompletion = outcome
        end)
        service.requestFrontmostInSpace(109, 9, makeConfig(), function(outcome)
          secondCompletion = outcome
        end)
        FakeHs.runScheduledTimers()
        FakeHs.runScheduledTimers()

        Assert.equal(first.focusCalls, 0)
        Assert.equal(firstCompletion, nil)
        Assert.equal(second.focusCalls, 1)
        FakeHs.runScheduledTimers()
        Assert.truthy(secondCompletion.ok)
      end,
    },
    {
      name = "cross-space timeout dismisses Mission Control and reports final failure",
      run = function()
        local service = makeService()
        FakeHs.makeWindow({ id = 110, title = "Target" })
        local completion = nil
        hs.spaces.gotoSpace = function()
          return true
        end
        FakeHs.setFocusedSpace(2)

        local result = service.requestFrontmostInSpace(110, 8, makeConfig({
          spaceSwitchMaxAttempts = 2,
        }), function(outcome)
          completion = outcome
        end)
        Assert.truthy(result.ok)
        Assert.equal(completion, nil)

        FakeHs.runScheduledTimers()

        Assert.falsy(completion.ok)
        Assert.equal(completion.code, "space_switch_timeout")
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)
      end,
    },
    {
      name = "failed Space initiation dismisses Mission Control without scheduling work",
      run = function()
        local service = makeService()
        hs.spaces.gotoSpace = function()
          return nil, "Mission Control unavailable"
        end

        local result = service.requestFrontmostInSpace(111, 8, makeConfig())

        Assert.falsy(result.ok)
        Assert.equal(result.code, "space_switch_not_initiated")
        Assert.equal(FakeHs.state().closeMissionControlCalls, 1)
        Assert.equal(#FakeHs.state().doAfterCalls, 0)
      end,
    },
    {
      name = "recovery candidate predicate accepts minimized concrete event windows",
      run = function()
        local service = makeService()
        local minimized = FakeHs.makeWindow({
          id = 210,
          title = "Minimized Doc",
          bundleId = "com.apple.TextEdit",
          appName = "TextEdit",
          minimized = true,
          visible = false,
        })
        local untitled = FakeHs.makeWindow({
          id = 211,
          title = "",
          bundleId = "com.apple.TextEdit",
          appName = "TextEdit",
          minimized = true,
          visible = false,
        })

        Assert.truthy(service.isRecoveryCandidateWindow(minimized))
        Assert.falsy(service.isRecoveryCandidateWindow(untitled))
      end,
    },
  },
}
