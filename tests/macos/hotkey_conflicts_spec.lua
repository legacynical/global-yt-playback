local Assert = require("assert")
local TestEnv = require("test_env")

local function loadConflicts()
  TestEnv.reset({
    "hotkeys.manager",
    "hotkeys.registry",
  })
  return require("hotkeys.manager")._conflicts
end

return {
  name = "HotkeyConflicts",
  cases = {
    {
      name = "normalizes mods and combos and detects conflicts",
      run = function()
        local Conflicts = loadConflicts()

        local mods = Conflicts.normalizeMods({ "shift", "cmd", "alt", "cmd", "ctrl" })
        Assert.equal(table.concat(mods, ","), "cmd,alt,ctrl,shift")

        local combo = Conflicts.normalizeCombo({ "shift", "cmd", "alt" }, "K")
        Assert.equal(combo, "cmd+alt+shift+k")

        local functionKeyCombo = Conflicts.normalizeCombo({ "ctrl" }, "F19")
        Assert.equal(functionKeyCombo, "ctrl+F19")

        local detected = Conflicts.detect({
          a = { enabled = true, mods = { "cmd", "alt" }, key = "k" },
          b = { enabled = true, mods = { "alt", "cmd" }, key = "K" },
          c = { enabled = false, mods = { "cmd", "alt" }, key = "k" },
          d = { enabled = true, mods = {}, key = false },
        })

        Assert.truthy(detected.a ~= nil)
        Assert.truthy(detected.b ~= nil)
        Assert.equal(#detected.a, 1)
        Assert.equal(detected.a[1], "b")
        Assert.equal(detected.d, nil)
      end,
    },
  },
}
