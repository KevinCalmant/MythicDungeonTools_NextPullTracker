local MDT = MDT
local MDT_NPT = MDT_NPT

-- MDT's own CheckCurrentZone bails while a key is active, so we resolve the
-- player's zone to a dungeonIdx ourselves and nudge MDT's DB before reading
-- the preset. init=true keeps UpdateToDungeon from touching the main frame,
-- which may not exist yet.
local function syncMDTDungeonToPlayerZone()
  if not MDT or not MDT.zoneIdToDungeonIdx or not MDT.UpdateToDungeon then return end
  if not C_Map or not C_Map.GetBestMapForUnit then return end
  local zoneId = C_Map.GetBestMapForUnit("player")
  if not zoneId then return end
  local dungeonIdx = MDT.zoneIdToDungeonIdx[zoneId]
  if not dungeonIdx then return end
  local mdtDB = MDT:GetDB()
  if not mdtDB or mdtDB.currentDungeonIdx == dungeonIdx then return end
  MDT:UpdateToDungeon(dungeonIdx, true, true)
end

MDT_NPT.Mdt = {
  syncMDTDungeonToPlayerZone = syncMDTDungeonToPlayerZone,
}
