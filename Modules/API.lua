function MDT_NPT:IsActive()
  return self.state ~= nil and self.state.active == true
end

function MDT_NPT:GetCurrentNextPull()
  local s = self.state
  if not s or not s.active then return nil end
  return s.currentNextPull
end

function MDT_NPT:GetPullState(pullIndex)
  local s = self.state
  if not s or not s.active then return nil end
  local ps = s.pullStates[pullIndex]
  return ps and ps.state or nil
end

function MDT_NPT:GetPullStateData(pullIndex)
  local s = self.state
  if not s or not s.active then return nil end
  return s.pullStates[pullIndex]
end
