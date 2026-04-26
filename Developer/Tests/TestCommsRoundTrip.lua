local MDT = MDT
local MDT_NPT = MDT_NPT
local T = MDT_NPT.test

local function testFunc()
  if not (MDT_NPT.Comms and MDT_NPT.Comms._test) then
    T.skip("Comms module not loaded")
  end
  if not MDT:GetCurrentPreset() then
    T.skip("no MDT preset selected")
  end

  local seam = MDT_NPT.Comms._test

  MDT_NPT:Start(true)
  T.assertNotNil(MDT_NPT.state, "state created")

  -- Mutate to a non-trivial shape so the round-trip exercises real fields
  local numPulls = #MDT_NPT.state.pullStates
  if numPulls < 2 then
    MDT_NPT:Stop()
    T.skip("preset has fewer than 2 pulls")
  end
  MDT_NPT:SkipTo(2)
  MDT_NPT.state.lastForces = 1234

  local payload = seam.buildStatePayload(MDT_NPT.state)
  T.assertEquals(seam.PROTO_VERSION, payload.v, "payload.v")
  T.assertEquals("state", payload.t, "payload.t")
  T.assertEquals(MDT_NPT.state.presetUID, payload.uid, "payload.uid")
  T.assertEquals(2, payload.cur, "payload.cur")
  T.assertEquals(1234, payload.lf, "payload.lf")

  local encoded = seam.encode(payload)
  T.assertNotNil(encoded, "encoded non-nil")
  T.assertTrue(type(encoded) == "string", "encoded is string")

  local decoded = seam.decode(encoded)
  T.assertNotNil(decoded, "decoded non-nil")
  T.assertTrue(seam.isValidStatePayload(decoded), "decoded passes validation")
  T.assertEquals(payload.uid, decoded.uid, "uid round-trip")
  T.assertEquals(payload.cur, decoded.cur, "cur round-trip")
  T.assertEquals(payload.lf,  decoded.lf,  "lf round-trip")
  T.assertEquals(#payload.ps, #decoded.ps, "pullStates length round-trip")
  T.assertEquals(payload.ps[1].state, decoded.ps[1].state, "ps[1].state round-trip")
  T.assertEquals(payload.ps[2].state, decoded.ps[2].state, "ps[2].state round-trip")

  -- Reject malformed payloads
  T.assertFalse(seam.isValidStatePayload(nil),                                 "rejects nil")
  T.assertFalse(seam.isValidStatePayload({}),                                  "rejects empty")
  T.assertFalse(seam.isValidStatePayload({ v = 999, t = "state", uid = "x", ps = {} }), "rejects bad version")
  T.assertFalse(seam.isValidStatePayload({ v = 1,   t = "state", uid = "x", ps = { { state = "bogus" } } }), "rejects bogus pullState")

  -- Garbage decode should return nil rather than throw
  T.assertNil(seam.decode("not a valid encoded payload at all"), "decode garbage returns nil")

  MDT_NPT:Stop()
end

tinsert(T.testList, {
  name = "Comms round-trip (encode/decode/validate)",
  func = testFunc,
  duration = 1,
})
