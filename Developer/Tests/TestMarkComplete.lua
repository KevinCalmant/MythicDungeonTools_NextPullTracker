local MDT = MDT
local MDT_NPT = MDT_NPT
local T = MDT_NPT.test

local function testFunc()
  if not MDT:GetCurrentPreset() then
    T.skip("no MDT preset selected")
  end

  MDT_NPT:Start(true)

  local ps1 = MDT_NPT.state.pullStates[1]
  T.assertNotNil(ps1, "pullStates[1] exists")
  T.assertEquals("next", ps1.state, "pull 1 starts as NEXT")

  MDT_NPT:MarkComplete(1)
  T.assertEquals("completed", ps1.state, "pull 1 completed")
  T.assertEquals(ps1.totalCount,  ps1.killedCount,  "killedCount filled")
  T.assertEquals(ps1.totalForces, ps1.forcesKilled, "forcesKilled filled")

  MDT_NPT:MarkIncomplete(1)
  -- After MarkIncomplete + recompute, pull 1 becomes NEXT again (lowest non-terminal)
  T.assertEquals("next", ps1.state, "pull 1 reverted to NEXT")
  T.assertEquals(0, ps1.killedCount,  "killedCount cleared")
  T.assertEquals(0, ps1.forcesKilled, "forcesKilled cleared")

  MDT_NPT:Stop()
end

tinsert(T.testList, {
  name = "MarkComplete / MarkIncomplete",
  func = testFunc,
  duration = 2,
})
