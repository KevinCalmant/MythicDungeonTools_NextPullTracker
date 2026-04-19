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
        print("|cFF00FF00MDT-NPT|r: Next pull is #"..idx..
          " (mobs 0/"..tostring(ps.totalCount)..
          ", forces "..tostring(ps.forcesKilled).."/"..tostring(ps.totalForces)..
          ", state="..tostring(ps.state)..")")
      else
        print("|cFF00FF00MDT-NPT|r: Route complete.")
      end
    else
      print("|cFF00FF00MDT-NPT|r: Tracking is not active.")
    end
  else
    print("|cFF00FF00MDT-NPT|r: Usage: /mdtnp <start|stop|status>")
  end
end

SLASH_MDTNPT1 = "/mdtnp"
SlashCmdList["MDTNPT"] = function(msg) MDT_NPT:Slash(msg or "") end
