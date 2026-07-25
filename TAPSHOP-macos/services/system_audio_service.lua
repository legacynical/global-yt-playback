-- SystemAudioService: default output device mute + volume step adjustments.

local SystemAudioService = {}
SystemAudioService.__index = SystemAudioService

function SystemAudioService.new()
  return setmetatable({}, SystemAudioService)
end

function SystemAudioService:toggleMute()
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    dev:setMuted(not dev:muted())
  end
end

function SystemAudioService:adjustVolume(delta)
  local dev = hs.audiodevice.defaultOutputDevice()
  if dev then
    local base = dev:volume() or 25
    if delta < 0 then
      dev:setVolume(math.max(0, base + delta))
    else
      dev:setVolume(math.min(100, base + delta))
    end
  end
end

return SystemAudioService
