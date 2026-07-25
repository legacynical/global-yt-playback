local source = debug.getinfo(1, "S").source
local scriptPath = source:sub(1, 1) == "@" and source:sub(2) or source
dofile((scriptPath:match("^(.*)/") or ".") .. "/_bootstrap.lua")

local TestRunner = require("test_runner")

TestRunner.run({
  require("debug_logger_spec"),
  require("toast_spec"),
  require("panel_layout_spec"),
  require("popover_spec"),
  require("popover_fullscreen_visibility_spec"),
  require("settings_window_spec"),
  require("workspace_spec"),
  require("slot_row_spec"),
  require("app_state_spec"),
  require("settings_store_spec"),
  require("real_appdata_restart_spec"),
  require("window_service_spec"),
  require("youtube_service_spec"),
  require("hotkey_conflicts_spec"),
  require("hotkey_manager_spec"),
})
