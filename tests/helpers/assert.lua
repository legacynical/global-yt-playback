local Assert = {}

local function render(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

function Assert.equal(actual, expected, message)
  if actual ~= expected then
    error(message or string.format("expected %s, got %s", render(expected), render(actual)), 2)
  end
end

function Assert.truthy(value, message)
  if not value then
    error(message or string.format("expected truthy value, got %s", render(value)), 2)
  end
end

function Assert.falsy(value, message)
  if value then
    error(message or string.format("expected falsy value, got %s", render(value)), 2)
  end
end

function Assert.sameKeys(actual, expected, message)
  for key, value in pairs(expected) do
    if actual[key] ~= value then
      error(message or string.format("expected key %s to be %s, got %s", tostring(key), render(value), render(actual[key])), 2)
    end
  end
end

return Assert
