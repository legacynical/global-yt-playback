local TestRunner = {}

local function runCase(suiteName, case)
  if case.beforeEach then
    case.beforeEach()
  end
  case.run()
  io.write(string.format("PASS %s :: %s\n", suiteName, case.name))
end

function TestRunner.run(suites)
  local total = 0
  local failed = 0

  for suiteIndex = 1, #suites do
    local suite = suites[suiteIndex]
    local cases = suite.cases or {}
    for caseIndex = 1, #cases do
      local case = cases[caseIndex]
      total = total + 1
      local ok, err = xpcall(function()
        runCase(suite.name, case)
      end, debug.traceback)

      if not ok then
        failed = failed + 1
        io.write(string.format("FAIL %s :: %s\n%s\n", suite.name, case.name, err))
      end
    end
  end

  io.write(string.format("\n%d run, %d failed\n", total, failed))
  if failed > 0 then
    os.exit(1)
  end
end

return TestRunner
