local TempDir = {}

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function TempDir.create(prefix)
  local base = os.tmpname()
  os.remove(base)
  local dir = string.format("%s-%s", base, tostring(prefix or "tapshop"))
  os.execute("mkdir -p " .. shellQuote(dir))
  return dir
end

function TempDir.remove(path)
  if not path or path == "" then
    return
  end
  os.execute("rm -rf " .. shellQuote(path))
end

function TempDir.with(prefix, fn)
  local dir = TempDir.create(prefix)
  local previous = rawget(_G, "__tapshop_test_data_dir")
  rawset(_G, "__tapshop_test_data_dir", dir)

  local ok, resultOrErr = xpcall(function()
    return fn(dir)
  end, debug.traceback)

  rawset(_G, "__tapshop_test_data_dir", previous)
  TempDir.remove(dir)

  if not ok then
    error(resultOrErr, 0)
  end

  return resultOrErr
end

return TempDir
