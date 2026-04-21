local MDT = MDT
local MDT_NPT = MDT_NPT
local dbg = MDT_NPT.Debug.make("forces", false)

local PullState = MDT_NPT.PullState
local State = MDT_NPT.State
local Wow = MDT_NPT.Wow
local Utils = MDT_NPT.Utils
local tostring = tostring
local GetTime = GetTime

---Reads the current enemy forces from the scenario API, converted to absolute count.
---Scenario APIs report forces either as weighted percent (q=42, tq=100) or raw count
---(q=42, tq=460). Both are converted to the same absolute-count scale the preset pulls
---use, via (quantity / totalQuantity) * dungeonMax. Returns nil if we can't resolve a
---dungeon total — feeding raw percent into the consume loop stalls pull advancement.
local function getScenarioCurrentForces()
  local numCriteria = Wow.getScenarioStepInfo()
  if numCriteria == 0 then return nil end

  local state = MDT_NPT.state
  local dungeonMax = 0

  if state and state.dungeonIndex and MDT.dungeonTotalCount[state.dungeonIndex] then
    dungeonMax = MDT.dungeonTotalCount[state.dungeonIndex].normal or 0
  end

  if dungeonMax == 0 and MDT.GetDB then
    local mdtDatabase = MDT:GetDB()
    local index = mdtDatabase and mdtDatabase.currentDungeonIdx

    if index and MDT.dungeonTotalCount[index] then
      dungeonMax = MDT.dungeonTotalCount[index].normal or 0
    end
  end

  if dungeonMax == 0 then return nil end

  local bestAbsolute = nil
  local bestTotal = 0

  for i = 1, numCriteria do
    local scenarioCriteriaInfo = Wow.getScenarioCriteriaInfo(i)
    if scenarioCriteriaInfo then
      local quantity = Utils.parseNum(scenarioCriteriaInfo.quantity)
      local totalQuantity = Utils.parseNum(scenarioCriteriaInfo.totalQuantity)

      -- Preferred: explicitly flagged as weighted progress (typically enemy forces).
      -- Blizzard reports `quantity` as a 0-100 percentage for weighted criteria
      -- regardless of what `totalQuantity` is (it may be 100 or the dungeon max).
      if scenarioCriteriaInfo.isWeightedProgress and totalQuantity > 0 then
        return (quantity / 100) * dungeonMax
      end

      -- Fallback: largest totalQuantity criteria (skip tiny boss-kill criteria).
      -- For non-weighted criteria we assume (quantity, totalQuantity) is a raw
      -- count pair: absolute = quantity * (dungeonMax / totalQuantity).
      if totalQuantity > bestTotal and totalQuantity > 10 then
        bestTotal = totalQuantity
        bestAbsolute = (quantity / totalQuantity) * dungeonMax
      end
    end
  end

  return bestAbsolute
end

---Advances pulls based on forces delta (scenario-based tracking, 12.0 compatible)
---When forces increase, we consume the delta by marking pulls as complete in order
local function onScenarioForcesUpdate()
  local state = MDT_NPT.state

  if not state or not state.active then
    dbg.print("skipped: no state or not active")
    return
  end

  local currentForces = getScenarioCurrentForces()
  dbg.print("poll: currentForces="..tostring(currentForces)..
    " lastForces="..tostring(state.lastForces)..
    " nextPull="..tostring(state.currentNextPull))
  if not currentForces then return end

  -- If the baseline was never seeded, treat it as 0 so this first poll
  -- attributes all pre-existing scenario forces across the route. This lets
  -- the addon catch up to reality when tracking starts mid-key.
  if state.lastForces == nil then
    state.lastForces = 0
    dbg.print("baseline set to 0 (will consume existing forces="..currentForces..")")
  end

  local forcesDelta = currentForces - state.lastForces
  if forcesDelta <= 0 then
    state.lastForces = currentForces
    return
  end

  dbg.print("DELTA "..forcesDelta.." detected - consuming...")

  -- Scenario rounding tolerance: Blizzard reports weighted progress as floored
  -- integer percentages, so the absolute-count estimate lags actual kills by
  -- strictly less than 1% of dungeonMax. A gap of exactly 1% therefore reflects
  -- a real deficit, not rounding — so the check is strict (>).
  local dungeonMax = 0
  if state.dungeonIndex and MDT.dungeonTotalCount[state.dungeonIndex] then
    dungeonMax = MDT.dungeonTotalCount[state.dungeonIndex].normal or 0
  end
  local tolerance = dungeonMax * 0.01

  local stateChanged = false
  local remainingForces = forcesDelta

  while remainingForces > 0 do
    local nextPull = state.currentNextPull
    if not nextPull then break end

    local pullState = state.pullStates[nextPull]
    if not pullState then break end

    -- First forces gain on this pull transitions it next -> active
    if pullState.state == PullState.NEXT then
      pullState.state = PullState.ACTIVE
      stateChanged = true
    end

    local remainingInPull = (pullState.totalForces or 0) - (pullState.forcesKilled or 0)
    dbg.print("  pull "..nextPull..": totalForces="..tostring(pullState.totalForces)..
      " forcesKilled="..tostring(pullState.forcesKilled)..
      " remainingInPull="..remainingInPull.." remaining="..remainingForces)

    if remainingInPull <= 0 then
      dbg.print("  pull has no forces - skipping to completed")
      pullState.state = PullState.COMPLETED
      State.recomputeNextPull(state)
      stateChanged = true
      -- Avoid infinite loop if a pull with 0 forces gets stuck
      if not state.currentNextPull or state.currentNextPull == nextPull then break end
    elseif remainingForces + tolerance > remainingInPull then
      pullState.forcesKilled = pullState.totalForces
      pullState.state = PullState.COMPLETED
      pullState.lastUpdate = GetTime()
      remainingForces = math.max(0, remainingForces - remainingInPull)
      State.recomputeNextPull(state)
      stateChanged = true
    else
      -- Partial kill in this pull
      pullState.forcesKilled = (pullState.forcesKilled or 0) + remainingForces
      pullState.lastUpdate = GetTime()
      remainingForces = 0
      stateChanged = true
    end
  end

  state.lastForces = currentForces

  if stateChanged then
    dbg.print("State changed - currentNextPull = "..tostring(state.currentNextPull))
    MDT_NPT:UpdateAll()
    if state.authoritative and MDT.LiveSession_SendPullStates then
      MDT:LiveSession_SendPullStates()
    end
  end
end

MDT_NPT.Scenario = {
  onScenarioForcesUpdate = onScenarioForcesUpdate,
  getScenarioCurrentForces = getScenarioCurrentForces,
}
