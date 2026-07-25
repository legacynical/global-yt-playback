-- SpotifyService: thin wrappers around hs.spotify / AppleScript for transport,
-- seek, volume, and like. Seek falls back to AppleScript when getPosition fails.

local SpotifyService = {}
SpotifyService.__index = SpotifyService

local function adjustPosition(delta)
  local pos = hs.spotify.getPosition()
  if type(pos) == "number" then
    hs.spotify.setPosition(math.max(0, pos + delta))
    return
  end

  local script = string.format(
    [[
      tell application "Spotify"
        if it is running then
          try
            set p to player position
            set player position to (p + %f)
          end try
        end if
      end tell
    ]],
    delta
  )
  hs.osascript.applescript(script)
end

function SpotifyService.new()
  return setmetatable({}, SpotifyService)
end

function SpotifyService:previous()
  hs.spotify.previous()
end

function SpotifyService:next()
  hs.spotify.next()
end

function SpotifyService:playPause()
  hs.spotify.playpause()
end

function SpotifyService:seekBack(seconds)
  adjustPosition(-(seconds or 5))
end

function SpotifyService:seekForward(seconds)
  adjustPosition(seconds or 5)
end

function SpotifyService:volumeDown(step)
  pcall(function()
    local currentVolume = hs.spotify.getVolume()
    if currentVolume == nil then
      currentVolume = 50
    end
    hs.spotify.setVolume(math.max(0, currentVolume - (step or 6)))
  end)
end

function SpotifyService:volumeUp(step)
  pcall(function()
    local currentVolume = hs.spotify.getVolume()
    if currentVolume == nil then
      currentVolume = 50
    end
    hs.spotify.setVolume(math.min(100, currentVolume + (step or 6)))
  end)
end

function SpotifyService:toggleLike()
  local script = [[
    tell application "Spotify"
      if it is running then
        try
          set t to current track
          try
            set liked of t to not (liked of t)
          on error
            set starred of t to not (starred of t)
          end try
        end try
      end if
    end tell
  ]]
  hs.osascript.applescript(script)
end

return SpotifyService
