local MDT = MDT
local MDT_NPT = MDT_NPT
---@type DebugChannel
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

---If the current next pull is a boss pull and a boss kill is pending (a non-weighted
---criterion completed that hasn't been matched to a pull yet), marks the pull complete
---and returns true. Consumes one pending kill.
---@return boolean consumed
local function tryConsumeBossKill(state)
  if (state.pendingBossKills or 0) <= 0 then return false end

  local pullIndex = state.currentNextPull
  local pullState = pullIndex and state.pullStates[pullIndex]
  if not (pullState and pullState.hasBoss) then return false end

  dbg.print("consuming pending boss kill - marking pull "..pullIndex.." complete")
  pullState.forcesKilled = pullState.totalForces or 0
  pullState.state = PullState.COMPLETED
  pullState.lastUpdate = GetTime()
  State.recomputeNextPull(state)
  state.pendingBossKills = state.pendingBossKills - 1
  return true
end

---Checks non-weighted scenario criteria (boss-kill criteria), increments the pending
---boss-kill counter on each new transition, and tries to consume against the current
---pull. Bosses usually contribute 0 enemy forces, so without this the forces path
---can't tell the boss is dead — or worse, the 0-forces auto-skip collapses the pull
---before the boss is actually killed. We count pending kills rather than completing
---inline: when the boss dies before the preceding trash's forces have been fully
---consumed, currentNextPull still points at the trash pull, so we need to carry the
---kill forward until the consume loop advances to the boss pull.
---On first call, seeds the "already seen" set so criteria completed before tracking
---started (e.g. mid-key start after a boss is already dead) do not count as pending.
---@return boolean stateChanged true if a boss pull was completed
local function checkBossCriteriaAdvance(state)
  local numCriteria = Wow.getScenarioStepInfo()
  if numCriteria == 0 then return false end

  local seedPass = state.completedBossCriteria == nil
  if seedPass then
    state.completedBossCriteria = {}
    state.pendingBossKills = 0
  end

  for i = 1, numCriteria do
    local info = Wow.getScenarioCriteriaInfo(i)
    if info and not info.isWeightedProgress and info.completed then
      if not state.completedBossCriteria[i] then
        state.completedBossCriteria[i] = true
        if not seedPass then
          state.pendingBossKills = (state.pendingBossKills or 0) + 1
          dbg.print("boss criterion "..i.." completed - pendingBossKills="..state.pendingBossKills)
        end
      end
    end
  end

  return tryConsumeBossKill(state)
end

---Advances pulls based on forces delta (scenario-based tracking, 12.0 compatible)
---When forces increase, we consume the delta by marking pulls as complete in order
local function onScenarioForcesUpdate()
  local state = MDT_NPT.state

  if not state or not state.active then
    dbg.print("skipped: no state or not active")
    return
  end

  -- Followers receive authoritative state from the leader's broadcasts; running
  -- the local detector here would fight inbound updates and flicker the beacon.
  if state.role == "follow" then return end

  -- Boss check runs before forces consumption so a boss kill advances the pull
  -- before any coincident trash delta is attributed to the (now-wrong) pull.
  local stateChanged = checkBossCriteriaAdvance(state)

  local currentForces = getScenarioCurrentForces()
  dbg.print("poll: currentForces="..tostring(currentForces)..
    " lastForces="..tostring(state.lastForces)..
    " nextPull="..tostring(state.currentNextPull))

  if currentForces then
    -- If the baseline was never seeded, treat it as 0 so this first poll
    -- attributes all pre-existing scenario forces across the route. This lets
    -- the addon catch up to reality when tracking starts mid-key.
    if state.lastForces == nil then
      state.lastForces = 0
      dbg.print("baseline set to 0 (will consume existing forces="..currentForces..")")
    end

    local dungeonMax = 0
    if state.dungeonIndex and MDT.dungeonTotalCount[state.dungeonIndex] then
      dungeonMax = MDT.dungeonTotalCount[state.dungeonIndex].normal or 0
    end

    local forcesDelta = currentForces - state.lastForces
    if forcesDelta > 0 then
      dbg.print("DELTA "..forcesDelta.." detected - consuming...")

      -- Scenario rounding tolerance: Blizzard reports weighted progress as floored
      -- integer percentages, so the absolute-count estimate lags actual kills by
      -- strictly less than 1% of dungeonMax. A gap of exactly 1% therefore reflects
      -- a real deficit, not rounding — so the check is strict (>).
      local tolerance = dungeonMax * 0.01

      local remainingForces = forcesDelta

      while remainingForces > 0 do
        local nextPull = state.currentNextPull
        if not nextPull then break end

        local pullState = state.pullStates[nextPull]
        if not pullState then break end

        local remainingInPull = (pullState.totalForces or 0) - (pullState.forcesKilled or 0)
        dbg.print("  pull "..nextPull..": totalForces="..tostring(pullState.totalForces)..
          " forcesKilled="..tostring(pullState.forcesKilled)..
          " remainingInPull="..remainingInPull.." remaining="..remainingForces)

        if remainingInPull <= 0 then
          -- Boss pulls only advance when their boss criterion has fired. If the
          -- kill is already pending (boss died alongside trash, so the criterion
          -- fired earlier in this same update while the boss pull wasn't yet
          -- current), consume it and continue attributing leftover forces to the
          -- pull after the boss. Otherwise break and wait; dropping the leftover
          -- delta is intentional — it's from trash around the boss that has no
          -- later pull to attribute to until the boss actually dies.
          -- Don't transition NEXT -> ACTIVE here either: whether overflow lands
          -- on a boss pull or stops short is an accident of the preceding pull's
          -- exact forces, not a real "engaged with boss" signal.
          if pullState.hasBoss then
            if tryConsumeBossKill(state) then
              stateChanged = true
              -- Continue loop: currentNextPull moved past the boss, leftover
              -- remainingForces now attributes to the pull after.
            else
              dbg.print("  pull is boss - waiting for boss criterion instead of auto-skipping")
              break
            end
          else
            dbg.print("  pull has no forces - skipping to completed")
            pullState.state = PullState.COMPLETED
            State.recomputeNextPull(state)
            stateChanged = true
            -- Avoid infinite loop if a pull with 0 forces gets stuck
            if not state.currentNextPull or state.currentNextPull == nextPull then break end
          end
        else
          -- This pull will receive forces this iteration, so mark it active.
          if pullState.state == PullState.NEXT then
            pullState.state = PullState.ACTIVE
            stateChanged = true
          end

          if remainingForces + tolerance > remainingInPull then
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
      end
    end

    -- Forces capped at 100%: Blizzard won't report further kills once the
    -- dungeon max is reached, so any non-boss pulls still queued in the route
    -- (typically over-planned trash before the last boss) can never auto-
    -- complete via the delta path. Advance through them until we hit a boss
    -- pull — the player has killed enough, whatever the MDT preset claims.
    if dungeonMax > 0 and currentForces >= dungeonMax then
      while state.currentNextPull do
        local idx = state.currentNextPull
        local ps = state.pullStates[idx]
        if ps.hasBoss then break end
        dbg.print("forces capped at dungeonMax - auto-completing non-boss pull "..idx)
        ps.forcesKilled = ps.totalForces or 0
        ps.state = PullState.COMPLETED
        ps.lastUpdate = GetTime()
        State.recomputeNextPull(state)
        stateChanged = true
        if state.currentNextPull == idx then break end
      end
    end

    state.lastForces = currentForces
  end

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
