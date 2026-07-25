-- Factory defaults and shared palette for multi-profile identity.
-- Chromatic hues are unique across profiles; "none" (nil color) may be shared.

local ProfilePalette = {}

-- Ordered chromatic palette (index 1–9) plus nil = no color in picker.
ProfilePalette.COLORS = {
  "#4C8DFF",
  "#FF6B4A",
  "#3DDC97",
  "#B388FF",
  "#FFC857",
  "#8B95A8",
  "#FF4D6D",
  "#EDE6DC",
  "#7A4F2E",
}

ProfilePalette.FACTORY = {
  { id = 1, name = "Blueberry", color = "#4C8DFF" },
  { id = 2, name = "Peach", color = "#FF6B4A" },
  { id = 3, name = "Matcha", color = "#3DDC97" },
  { id = 4, name = "Ube", color = "#B388FF" },
  { id = 5, name = "Yuzu", color = "#FFC857" },
  { id = 6, name = "Earl Grey", color = "#8B95A8" },
  { id = 7, name = "Hibiscus", color = "#FF4D6D" },
  { id = 8, name = "Lychee", color = "#EDE6DC" },
  { id = 9, name = "Mocha", color = "#7A4F2E" },
}

local COLOR_SET = {}
for index, hex in ipairs(ProfilePalette.COLORS) do
  local upper = "#" .. string.upper(hex:sub(2))
  COLOR_SET[upper] = upper
  ProfilePalette.COLORS[index] = upper
  if ProfilePalette.FACTORY[index] then
    ProfilePalette.FACTORY[index].color = upper
  end
end

function ProfilePalette.factoryFor(profileId)
  local id = tonumber(profileId)
  if not id then
    return nil
  end
  return ProfilePalette.FACTORY[id]
end

function ProfilePalette.defaultName(profileId)
  local factory = ProfilePalette.factoryFor(profileId)
  if factory then
    return factory.name
  end
  return "Untitled profile " .. tostring(profileId or "?")
end

function ProfilePalette.defaultColor(profileId)
  local factory = ProfilePalette.factoryFor(profileId)
  if factory then
    return factory.color
  end
  return nil
end

function ProfilePalette.untitledName(profileId)
  return "Untitled profile " .. tostring(math.floor(tonumber(profileId) or 0))
end

function ProfilePalette.normalizeColor(value)
  if value == nil or value == false or value == "" or value == "none" then
    return nil
  end
  local hex = tostring(value):match("^%s*(#%x%x%x%x%x%x)%s*$")
  if not hex then
    return nil
  end
  local normalized = "#" .. string.upper(hex:sub(2))
  return COLOR_SET[normalized]
end

function ProfilePalette.isPaletteColor(value)
  return ProfilePalette.normalizeColor(value) ~= nil
end

function ProfilePalette.normalizeName(value, profileId)
  local text = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if text == "" then
    return ProfilePalette.untitledName(profileId)
  end
  return text
end

return ProfilePalette
