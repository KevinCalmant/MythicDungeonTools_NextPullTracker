local MDT_NPT = MDT_NPT
MDT_NPT.test = {}
local T = MDT_NPT.test

---@class NPTTest
---@field name     string
---@field func     function
---@field duration number seconds to wait before firing the next test

T.testList = {}

local function color(hex, msg) return "|cff"..hex..msg.."|r" end

---Run every registered test sequentially. Each test runs inside pcall so one
---failure doesn't abort the suite; `duration` is the cooldown between tests
---(needed for tests that spawn async UI work via C_Timer).
function T:RunAllTests()
  print(color("00ff00", "[MDT-NextPullTracker test]").." running "..#self.testList.." tests")
  local delay = 0.1
  local passed, failed = 0, 0

  for i, test in ipairs(self.testList) do
    C_Timer.After(delay, function()
      print(color("ffff00", "[MDT-NextPullTracker test] "..test.name))
      local ok, err = pcall(test.func)
      if ok then
        print(color("00ff00", "  PASS"))
        passed = passed + 1
      else
        print(color("ff4040", "  FAIL: "..tostring(err)))
        failed = failed + 1
      end
      if i == #self.testList then
        -- Defer final summary so any trailing async assertions can settle
        C_Timer.After(0.2, function()
          print(color("00ff00", "[MDT-NextPullTracker test] ").."done: "
            ..passed.." passed, "..failed.." failed")
        end)
      end
    end)
    delay = delay + test.duration
  end
end

-- Tiny assertion helpers. Tests use these to fail via Lua error, which the
-- runner's pcall turns into a PASS/FAIL line in chat.

function T.assertEquals(expected, actual, label)
  if expected ~= actual then
    error("["..(label or "assertEquals").."] expected "..tostring(expected)
      .." but got "..tostring(actual), 2)
  end
end

function T.assertTrue(condition, label)
  if not condition then
    error("["..(label or "assertTrue").."] expected truthy, got "..tostring(condition), 2)
  end
end

function T.assertFalse(condition, label)
  if condition then
    error("["..(label or "assertFalse").."] expected falsy, got "..tostring(condition), 2)
  end
end

function T.assertNil(value, label)
  if value ~= nil then
    error("["..(label or "assertNil").."] expected nil, got "..tostring(value), 2)
  end
end

function T.assertNotNil(value, label)
  if value == nil then
    error("["..(label or "assertNotNil").."] expected non-nil", 2)
  end
end

---Skips the test with a readable message. Shows up as FAIL but the message
---makes it clear the test couldn't run (vs. actually failing).
function T.skip(reason)
  error("SKIPPED: "..reason, 2)
end
