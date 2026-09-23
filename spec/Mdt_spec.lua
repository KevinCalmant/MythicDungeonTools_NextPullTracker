describe("Mdt.lua", function()
  local function loadModule(mdt, challengeMapId, zoneId, challengeActive)
    _G.MDT_NPT = { MDT = mdt }
    _G.C_ChallengeMode = {
      GetActiveChallengeMapID = function() return challengeMapId end,
      IsChallengeModeActive = function() return challengeActive or false end,
    }
    _G.C_Map = {
      GetBestMapForUnit = function(unit)
        assert.equals("player", unit)
        return zoneId
      end,
    }
    -- Zone lookups only apply inside an instance; tests that need the open
    -- world override this after loading.
    _G.IsInInstance = function() return true, "party" end

    assert(loadfile("Modules/Mdt.lua"))()
    return _G.MDT_NPT.Mdt
  end

  after_each(function()
    _G.MDT_NPT = nil
    _G.C_ChallengeMode = nil
    _G.C_Map = nil
    _G.GetSubZoneText = nil
    _G.IsInInstance = nil
  end)

  it("prefers the active challenge map over a stale UI map mapping", function()
    local db = { currentDungeonIdx = 160 }
    local updatedTo
    local mdt = {
      mapInfo = {
        [160] = { englishName = "Murder Row", mapID = 999 },
        [161] = { englishName = "Den of Nalorakk", mapID = 777 },
      },
      zoneIdToDungeonIdx = { [2214] = 160 },
      GetDB = function() return db end,
      UpdateToDungeon = function(_, dungeonIdx) updatedTo = dungeonIdx end,
    }

    local module = loadModule(mdt, 777, 2214, true)
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.equals(161, dungeonIndex)

    assert.equals(161, updatedTo)
  end)

  it("uses the known Den of Nalorakk challenge mapping when MDT mapInfo is stale", function()
    local db = { currentDungeonIdx = 160 }
    local updatedTo
    local mdt = {
      mapInfo = { [161] = { englishName = "Den of Nalorakk", mapID = 12345 } },
      zoneIdToDungeonIdx = { [2214] = 160 },
      GetDB = function() return db end,
      UpdateToDungeon = function(_, dungeonIdx) updatedTo = dungeonIdx end,
    }

    local module = loadModule(mdt, 586, 2214, true)
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.equals(161, dungeonIndex)

    assert.equals(161, updatedTo)
  end)

  it("waits for the challenge map instead of using a stale UI map mapping", function()
    local updateCount = 0
    local mdt = {
      mapInfo = {},
      zoneIdToDungeonIdx = { [2214] = 160 },
      GetDB = function() return { currentDungeonIdx = 160 } end,
      UpdateToDungeon = function() updateCount = updateCount + 1 end,
    }

    local module = loadModule(mdt, 0, 2214, true)
    assert.is_false(module.syncMDTDungeonToPlayerZone())

    assert.equals(0, updateCount)
  end)

  it("waits when the start event expects a challenge map before the API becomes active", function()
    local updateCount = 0
    local mdt = {
      mapInfo = {},
      zoneIdToDungeonIdx = { [2214] = 160 },
      GetDB = function() return { currentDungeonIdx = 160 } end,
      UpdateToDungeon = function() updateCount = updateCount + 1 end,
    }

    local module = loadModule(mdt, 0, 2214, false)
    assert.is_false(module.syncMDTDungeonToPlayerZone(true))

    assert.equals(0, updateCount)
  end)

  it("falls back to the player UI map outside an active challenge", function()
    local db = { currentDungeonIdx = 1 }
    local updatedTo
    local mdt = {
      mapInfo = {},
      zoneIdToDungeonIdx = { [2501] = 154 },
      GetDB = function() return db end,
      UpdateToDungeon = function(_, dungeonIdx) updatedTo = dungeonIdx end,
    }

    local module = loadModule(mdt, nil, 2501)
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.equals(154, dungeonIndex)

    assert.equals(154, updatedTo)
  end)

  it("passes the subzone to the adapter's zone lookup", function()
    local db = { currentDungeonIdx = 1 }
    local updatedTo, lookedUp
    local mdt = {
      mapInfo = {},
      zoneIdToDungeonIdx = { [2437] = 161 },
      GetDungeonIdxForZone = function(_, zoneId, subzoneText)
        lookedUp = { zoneId, subzoneText }
        return subzoneText == "Maisara Deeps" and 154 or 161
      end,
      GetDB = function() return db end,
      UpdateToDungeon = function(_, dungeonIdx) updatedTo = dungeonIdx end,
    }
    _G.GetSubZoneText = function() return "Maisara Deeps" end

    local module = loadModule(mdt, nil, 2437)
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.equals(154, dungeonIndex)

    assert.same({ 2437, "Maisara Deeps" }, lookedUp)
    assert.equals(154, updatedTo)
  end)

  it("keeps MDT's selected dungeon when a mapped zone is outside an instance", function()
    local db = { currentDungeonIdx = 152 }
    local updateCount = 0
    local mdt = {
      mapInfo = {},
      -- MDT 6.2.17+ maps Silvermoon City, the zone around Murder Row's entrance.
      zoneIdToDungeonIdx = { [2393] = 160 },
      GetDungeonIdxForZone = function() return 160 end,
      GetDB = function() return db end,
      UpdateToDungeon = function() updateCount = updateCount + 1 end,
    }

    local module = loadModule(mdt, nil, 2393)
    _G.IsInInstance = function() return false, "none" end
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.is_nil(dungeonIndex)

    assert.equals(0, updateCount)
    assert.equals(152, db.currentDungeonIdx)
  end)

  it("does not update MDT when the correct dungeon is already selected", function()
    local db = { currentDungeonIdx = 161 }
    local updateCount = 0
    local mdt = {
      mapInfo = { [161] = { mapID = 777 } },
      zoneIdToDungeonIdx = {},
      GetDB = function() return db end,
      UpdateToDungeon = function() updateCount = updateCount + 1 end,
    }

    local module = loadModule(mdt, 777, nil, true)
    local ready, dungeonIndex = module.syncMDTDungeonToPlayerZone()
    assert.is_true(ready)
    assert.equals(161, dungeonIndex)

    assert.equals(0, updateCount)
  end)
end)
