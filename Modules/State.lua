local MDT = MDT
local MDT_NPT = MDT_NPT

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
    npcIdToPulls = {}, -- todo: remove this part because beleive this is against addons CLUF
    seenGUIDs = {},
    currentNextPull = nil,
    authoritative = true,
    lastSyncTime = 0,
  }

  for pullIndex, pull in ipairs(pulls) do
    local totalCount = 0
    local totalForces = 0

    for enemyIndex, clones in pairs(pull) do
      if tonumber(enemyIndex) then
        local enemyData = enemies[enemyIndex]
        if enemyData then
          local cloneCount = #clones
          totalCount = totalCount + cloneCount
          totalForces = totalForces + (enemyData.count or 0) * cloneCount

          local npcId = enemyData.id
          if npcId then
            if not state.npcIdToPulls[npcId] then
              state.npcIdToPulls[npcId] = {}
            end

            local found = false
            for _, npcEntry in ipairs(state.npcIdToPulls[npcId]) do
              if npcEntry.pullIndex == pullIndex then
                npcEntry.count = npcEntry.count + cloneCount
                found = true
                break
              end
            end

            if not found then
              table.insert(state.npcIdToPulls[npcId], { pullIndex = pullIndex, count = cloneCount })
            end
          end
        end
      end
    end

    state.pullStates[pullIndex] = {
      state = PullState.UPCOMING,
      killedCount = 0,
      forcesKilled = 0,
      totalCount = totalCount,
      totalForces = totalForces,
      lastUpdate = 0,
    }
  end

  if #state.pullStates > 0 then
    state.pullStates[1].state = PullState.NEXT
    state.currentNextPull = 1
  end

  return state
end

MDT_NPT.State = {
  buildStateFromPreset = buildStateFromPreset,
}
