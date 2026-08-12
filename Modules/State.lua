local MDT_NPT = MDT_NPT
local MDT = MDT_NPT.MDT or MDT

local tonumber, pairs, ipairs = tonumber, pairs, ipairs

local PullState = MDT_NPT.PullState

-- Init the nextPullState data model from the current preset's pulls
-- @param preset table the current preset
-- @return table|nil state the initialized state, or nil if no pulls
local function buildStateFromPreset(preset)
  local pulls = preset.value.pulls
  if not pulls or #pulls == 0 then return nil end

  local dungeonIndex = preset.value.currentDungeonIdx or MDT:GetDB().currentDungeonIdx
  local enemies = MDT.dungeonEnemies[dungeonIndex]

  if not enemies then return nil end

  local state = {
    active = true,
    dungeonIndex = dungeonIndex,
    presetUID = preset.uid,
    pullStates = {},
    currentNextPull = nil,
    authoritative = true,
    lastSyncTime = 0,
  }

  for pullIndex, pull in ipairs(pulls) do
    local totalCount = 0
    local totalForces = 0
    local hasBoss = false

    for enemyIndex, clones in pairs(pull) do
      if tonumber(enemyIndex) then
        local enemyData = enemies[enemyIndex]
        if enemyData then
          local cloneCount = #clones
          totalCount = totalCount + cloneCount
          totalForces = totalForces + (enemyData.count or 0) * cloneCount
          if enemyData.isBoss then hasBoss = true end
        end
      end
    end

    state.pullStates[pullIndex] = {
      state = PullState.UPCOMING,
      killedCount = 0,
      forcesKilled = 0,
      totalCount = totalCount,
      totalForces = totalForces,
      hasBoss = hasBoss,
      lastUpdate = 0,
    }
  end

  if #state.pullStates > 0 then
    state.pullStates[1].state = PullState.NEXT
    state.currentNextPull = 1
  end

  return state
end

local function recomputeNextPull(state)
  local previousNextPull = state.currentNextPull
  state.currentNextPull = nil

  for _, pullState in ipairs(state.pullStates) do
    if pullState.state == PullState.NEXT then
      pullState.state = PullState.UPCOMING
    end
  end

  -- Find the lowest-numbered pull that is neither completed nor active
  for pullIndex, pullState in ipairs(state.pullStates) do
    if pullState.state ~= PullState.COMPLETED and pullState.state ~= PullState.ACTIVE then
      pullState.state = PullState.NEXT
      state.currentNextPull = pullIndex
      break;
    end
  end

  return state.currentNextPull ~= previousNextPull
end

MDT_NPT.State = {
  buildStateFromPreset = buildStateFromPreset,
  recomputeNextPull = recomputeNextPull,
}
