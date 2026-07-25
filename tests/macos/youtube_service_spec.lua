local Assert = require("assert")
local FakeHs = require("fake_hs")
local Fakes = require("fakes")
local TestEnv = require("test_env")

local function makeConfig()
  return {
    browserBundleIDs = {
      ["com.apple.Safari"] = true,
      ["com.google.Chrome"] = true,
    },
    youtubeDirectDispatch = true,
    inputDelay = 0,
  }
end

local function makeService(windowService, toast)
  TestEnv.reset({
    "services.youtube_service",
  })
  local YoutubeService = require("services.youtube_service")
  return YoutubeService.new(makeConfig(), windowService, toast)
end

return {
  name = "YoutubeService",
  cases = {
    {
      name = "detects supported YouTube windows by bundle id and title",
      run = function()
        local windowService = Fakes.createWindowService()
        local service = makeService(windowService, function() end)
        local valid = FakeHs.makeWindow({
          id = 51,
          title = "Track - YouTube",
          bundleId = "com.apple.Safari",
        })
        local subscriptions = FakeHs.makeWindow({
          id = 52,
          title = "Subscriptions - YouTube",
          bundleId = "com.apple.Safari",
        })
        local unsupported = FakeHs.makeWindow({
          id = 53,
          title = "Track - YouTube",
          bundleId = "com.example.Other",
        })

        Assert.truthy(service:isYouTubeWindow(valid))
        Assert.falsy(service:isYouTubeWindow(subscriptions))
        Assert.falsy(service:isYouTubeWindow(unsupported))
      end,
    },
    {
      name = "tracks the latest YouTube target and emits a toast",
      run = function()
        local windowService = Fakes.createWindowService()
        local toast, toasts = Fakes.createToast()
        local service = makeService(windowService, toast)
        local first = FakeHs.makeWindow({
          id = 61,
          title = "First - YouTube",
        })
        local second = FakeHs.makeWindow({
          id = 62,
          title = "Second - YouTube",
        })

        service:handleWindowCandidate(first)
        service:handleWindowCandidate(second)

        Assert.equal(service:getTargetId(), 62)
        Assert.equal(#toasts, 2)
        Assert.equal(toasts[2].message.lines[1].segments[1].text, "YT Target Updated: ")
        Assert.equal(toasts[2].message.lines[1].segments[2].text, "Second - YouTube")
      end,
    },
    {
      name = "falls back to candidate windows when cached target is missing",
      run = function()
        local candidate = FakeHs.makeWindow({
          id = 71,
          title = "Fallback - YouTube",
        })
        local windowService = Fakes.createWindowService({
          candidate,
        })
        local service = makeService(windowService, function() end)

        local target = service:getTargetWindow()

        Assert.truthy(target)
        Assert.equal(target:id(), 71)
        Assert.equal(service:getTargetId(), 71)
      end,
    },
    {
      name = "sends direct-dispatch key strokes to the target app",
      run = function()
        local target = FakeHs.makeWindow({
          id = 81,
          title = "Video - YouTube",
          bundleId = "com.google.Chrome",
        })
        local windowService = Fakes.createWindowService({
          target,
        })
        local service = makeService(windowService, function() end)

        service:handleWindowCandidate(target)
        local result = service:sendCommand("{Left}")

        local state = FakeHs.state()
        Assert.truthy(result.ok)
        Assert.equal(result.code, "direct_dispatch")
        Assert.equal(#state.keyStrokes, 1)
        Assert.equal(state.keyStrokes[1].key, "left")
        Assert.equal(#windowService.ensureFrontmostAsyncCalls, 0)
      end,
    },
    {
      name = "fallback focus failure toasts without blocking sendCommand return",
      run = function()
        local target = FakeHs.makeWindow({
          id = 82,
          title = "Video - YouTube",
          bundleId = "com.google.Chrome",
        })
        local windowService = Fakes.createWindowService({
          target,
        })
        windowService.ensureFrontmostAsyncResult = {
          ok = false,
          code = "focus_timeout",
          windowId = 82,
        }
        local toast, toasts = Fakes.createToast()
        local service = makeService(windowService, toast)
        service.cfg.youtubeDirectDispatch = false

        service:handleWindowCandidate(target)
        local result = service:sendCommand("k")

        Assert.truthy(result.ok)
        Assert.equal(result.code, "focus_send_requested")
        Assert.equal(result.focusResult, nil)
        Assert.equal(#windowService.ensureFrontmostAsyncCalls, 1)
        Assert.equal(toasts[#toasts].message.lines[1].segments[1].text, "Focus failed for YT window")
        Assert.equal(#FakeHs.state().keyStrokes, 0)
      end,
    },
    {
      name = "fallback focus success sends keys then restores previous window",
      run = function()
        local previous = FakeHs.makeWindow({
          id = 80,
          title = "Docs",
          bundleId = "com.google.Chrome",
        })
        local target = FakeHs.makeWindow({
          id = 83,
          title = "Video - YouTube",
          bundleId = "com.google.Chrome",
        })
        local windowService = Fakes.createWindowService({
          previous,
          target,
        })
        local service = makeService(windowService, function() end)
        service.cfg.youtubeDirectDispatch = false
        service.cfg.inputDelay = 0.01
        FakeHs.setFrontmostWindow(previous)

        service:handleWindowCandidate(target)
        local result = service:sendCommand("k")

        Assert.truthy(result.ok)
        Assert.equal(result.code, "focus_send_requested")
        Assert.equal(#FakeHs.state().keyStrokes, 0)

        FakeHs.flushScheduledTimers(8)

        Assert.equal(#FakeHs.state().keyStrokes, 1)
        Assert.equal(FakeHs.state().keyStrokes[1].key, "k")
        Assert.equal(#windowService.requestFrontmostCalls, 1)
        Assert.equal(windowService.requestFrontmostCalls[1].win:id(), 80)
      end,
    },
  },
}
