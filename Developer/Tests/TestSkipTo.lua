local MDT = MDT
local MDT_NPT = MDT_NPT
local T = MDT_NPT.test

local function testFunc()
  if not MDT:GetCurrentPreset() then
    T.skip("no MDT preset selected")
  end

  MDT_NPT:Start(true)

  local numPulls = #MDT_NPT.state.pullStates
  if numPulls < 3 then
    MDT_NPT:Stop()
    T.skip("current preset has only "..numPulls.." pulls (need >= 3)")
  end

  MDT_NPT:SkipTo(3)
  T.assertEquals(3, MDT_NPT.state.currentNextPull, "currentNextPull = 3")
  T.assertEquals("completed", MDT_NPT.state.pullStates[1].state, "pull 1 completed")
  T.assertEquals("completed", MDT_NPT.state.pullStates[2].state, "pull 2 completed")
  T.assertEquals("next",      MDT_NPT.state.pullStates[3].state, "pull 3 is NEXT")

  MDT_NPT:Stop()
end

tinsert(T.testList, {
  name = "SkipTo (3 pulls)",
  func = testFunc,
  duration = 2,
})
