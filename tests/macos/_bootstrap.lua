-- Shared package.path bootstrap for tests/macos runners.
-- Load with: dofile(<this-dir> .. "/_bootstrap.lua")
local source = debug.getinfo(1, "S").source
local scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
if scriptPath:sub(1, 1) ~= "/" then
  local pwd = assert(io.popen("pwd", "r")):read("*l")
  scriptPath = pwd .. "/" .. scriptPath
end

local repoRoot = scriptPath:match("^(.*)/tests/macos/")
if not repoRoot then
  error("Unable to resolve repository root from " .. tostring(scriptPath))
end

package.path = table.concat({
  repoRoot .. "/tests/helpers/?.lua",
  repoRoot .. "/tests/macos/?.lua",
  repoRoot .. "/TAPSHOP-macos/?.lua",
  repoRoot .. "/TAPSHOP-macos/?/init.lua",
  package.path,
}, ";")
