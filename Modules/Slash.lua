local MDT_NPT = MDT_NPT

function MDT_NPT:Slash(args)
  args = args or ""
  local cmd = (args:match("^%S*") or ""):lower()

  if cmd == "start" then
    self:Start(true)
  elseif cmd == "stop" then
    self:Stop()
  elseif cmd == "status" then
    if self:IsActive() then
      local idx = self:GetCurrentNextPull()
      if idx then
        local ps = self:GetPullStateData(idx)
        print("|cFF00FF00MDT-NextPullTracker|r: Next pull is #"..idx..
          " (mobs 0/"..tostring(ps.totalCount)..
          ", forces "..tostring(ps.forcesKilled).."/"..tostring(ps.totalForces)..
          ", state="..tostring(ps.state)..")")
      else
        print("|cFF00FF00MDT-NextPullTracker|r: Route complete.")
      end
    else
      print("|cFF00FF00MDT-NextPullTracker|r: Tracking is not active.")
    end
  elseif cmd == "test" then
    if MDT_NPT.test and MDT_NPT.test.RunAllTests then
      MDT_NPT.test:RunAllTests()
    else
      print("|cFF00FF00MDT-NextPullTracker|r: Test harness not loaded.")
    end
  else
    print("|cFF00FF00MDT-NextPullTracker|r: Usage: /npt <start|stop|status|test>")
  end
end

SLASH_MDTNPT1 = "/npt"
SlashCmdList["MDTNPT"] = function(msg) MDT_NPT:Slash(msg or "") end
