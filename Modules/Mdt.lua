local MDT_NPT = MDT_NPT
local MDT = MDT_NPT.MDT or MDT

-- Keep a small fallback for newly released dungeons whose MDT mapInfo may
-- still contain placeholder data. These are challenge map IDs, not UI map IDs.
local knownChallengeMapDungeonIndexes = {
  [586] = 161, -- Den of Nalorakk
  [587] = 160, -- Murder Row
}

local function dungeonIndexForChallengeMap(challengeMapId)
  if not challengeMapId or challengeMapId == 0 then return nil end

  if MDT.mapInfo then
    for dungeonIdx, mapInfo in pairs(MDT.mapInfo) do
      if mapInfo and mapInfo.mapID == challengeMapId then
        return dungeonIdx
      end
    end
  end
  return knownChallengeMapDungeonIndexes[challengeMapId]
end

-- MDT's own CheckCurrentZone bails while a key is active. Prefer the active
-- challenge map because it identifies the dungeon directly; UI map IDs can be
-- shared, changed between builds, or temporarily wrong in MDT's dungeon data.
-- Keep the zone lookup as a fallback for manual starts outside a key.
local function syncMDTDungeonToPlayerZone(challengeExpected)
  if not MDT or not MDT.UpdateToDungeon then return false end

  local challengeMapId = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and
    C_ChallengeMode.GetActiveChallengeMapID()
  local dungeonIdx = dungeonIndexForChallengeMap(challengeMapId)

  local challengeActive = challengeExpected or
    (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and
      C_ChallengeMode.IsChallengeModeActive())

  -- CHALLENGE_MODE_START can fire one or more frames before the active map ID
  -- becomes available. Never use a possibly stale UI map mapping during that
  -- window; tell the caller to retry instead.
  if challengeActive and not dungeonIdx then return false end

  if not challengeActive and not dungeonIdx and MDT.zoneIdToDungeonIdx and
      C_Map and C_Map.GetBestMapForUnit then
    local zoneId = C_Map.GetBestMapForUnit("player")
    dungeonIdx = zoneId and MDT.zoneIdToDungeonIdx[zoneId]
  end
  if not dungeonIdx then return true, nil end

  local mdtDB = MDT:GetDB()
  if not mdtDB then return false end
  if mdtDB.currentDungeonIdx ~= dungeonIdx then
    MDT:UpdateToDungeon(dungeonIdx, true, true)
  end
  return true, dungeonIdx
end

MDT_NPT.Mdt = {
  syncMDTDungeonToPlayerZone = syncMDTDungeonToPlayerZone,
}
