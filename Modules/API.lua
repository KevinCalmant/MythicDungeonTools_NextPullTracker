local State = MDT_NPT.State
local PullState = MDT_NPT.PullState
local Scenario = MDT_NPT.Scenario

local GetTime = GetTime

function MDT_NPT:IsActive()
  return self.state ~= nil and self.state.active == true
end

function MDT_NPT:GetCurrentNextPull()
  local state = self.state
  if not state or not state.active then return nil end
  return state.currentNextPull
end

function MDT_NPT:GetPullState(pullIndex)
  local state = self.state
  if not state or not state.active then return nil end
  local ps = state.pullStates[pullIndex]
  return ps and ps.state or nil
end

function MDT_NPT:GetPullStateData(pullIndex)
  local s = self.state
  if not s or not s.active then return nil end
  return s.pullStates[pullIndex]
end

function MDT_NPT:MarkComplete(pullIndex)
  local state = self.state
  if not state or not state.active then return end
  local pullState = state.pullStates[pullIndex]
  if not pullState then return end

  pullState.state        = PullState.COMPLETED
  pullState.killedCount  = pullState.totalCount
  pullState.forcesKilled = pullState.totalForces
  pullState.lastUpdate   = GetTime()

  State.recomputeNextPull(state)

  self:UpdateAll()
end

function MDT_NPT:MarkIncomplete(pullIndex)
  local state = self.state
  if not state or not state.active then return end
  local ps = state.pullStates[pullIndex]
  if not ps then return end

  ps.state        = PullState.UPCOMING
  ps.killedCount  = 0
  ps.forcesKilled = 0
  ps.lastUpdate   = GetTime()

  State.recomputeNextPull(state)

  self:UpdateAll()
end

function MDT_NPT:SkipTo(pullIndex)
  local state = self.state
  if not state or not state.active then return end
  if not state.pullStates[pullIndex] then return end

  for i, pullState in ipairs(state.pullStates) do
    if i < pullIndex then
      pullState.state        = PullState.COMPLETED
      pullState.killedCount  = pullState.totalCount
      pullState.forcesKilled = pullState.totalForces
    elseif i == pullIndex then
      pullState.state        = PullState.NEXT
      pullState.killedCount  = 0
      pullState.forcesKilled = 0
    elseif pullState.state ~= PullState.COMPLETED then
      pullState.state        = PullState.UPCOMING
      pullState.killedCount  = 0
      pullState.forcesKilled = 0
    end
    pullState.lastUpdate = GetTime()
  end
  state.currentNextPull = pullIndex
  state.lastForces = Scenario.getScenarioCurrentForces()

  self:UpdateAll()
end
