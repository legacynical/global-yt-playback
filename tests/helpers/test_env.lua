local FakeHs = require("fake_hs")

local TestEnv = {}

function TestEnv.reset(modules)
  FakeHs.install()
  rawset(_G, "__tapshop_test_data_dir", nil)
  for _, name in ipairs(modules or {}) do
    package.loaded[name] = nil
  end
end

function TestEnv.freshRequire(name)
  package.loaded[name] = nil
  return require(name)
end

return TestEnv
