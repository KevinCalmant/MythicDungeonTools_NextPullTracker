local MDT = MDT
local MDT_NPT = MDT_NPT
local T = MDT_NPT.test

local function testFunc()
  if not MDT:GetCurrentPreset() then
    T.skip("no MDT preset selected — open MDT and pick a preset before running tests")
  end

  MDT_NPT:Start(true)
  T.assertNotNil(MDT_NPT.state, "state table built")
  T.assertTrue(MDT_NPT.state.active, "state.active = true")
  T.assertEquals(1, MDT_NPT.state.currentNextPull, "currentNextPull starts at 1")
  T.assertNotNil(MDT_NPT.state.pullStates, "pullStates populated")
  T.assertTrue(#MDT_NPT.state.pullStates > 0, "pullStates has entries")

  MDT_NPT:Stop()
  T.assertNil(MDT_NPT.state, "state cleared after Stop")
end

tinsert(T.testList, {
  name = "Start/Stop lifecycle",
  func = testFunc,
  duration = 2,
})
