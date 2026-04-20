local MDT_NPT = MDT_NPT
local T = MDT_NPT.test

local function testFunc()
  local Beacon = MDT_NPT.Beacon
  T.assertNotNil(Beacon, "MDT_NPT.Beacon exists")

  Beacon:Show()
  T.assertNotNil(Beacon.frame, "Beacon.frame created")
  T.assertTrue(Beacon.frame:IsShown(), "Beacon.frame visible after Show")

  Beacon:Hide()
  T.assertFalse(Beacon.frame:IsShown(), "Beacon.frame hidden after Hide")
end

tinsert(T.testList, {
  name = "Beacon Show/Hide",
  func = testFunc,
  duration = 1,
})
