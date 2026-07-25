local source = debug.getinfo(1, "S").source
local scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
dofile((scriptPath:match("^(.*)/") or ".") .. "/_bootstrap.lua")

local TestRunner = require("test_runner")

TestRunner.run({
  require("app_restart_edge_recovery_spec"),
})
