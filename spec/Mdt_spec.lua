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

    assert(loadfile("Modules/Mdt.lua"))()
    return _G.MDT_NPT.Mdt
  end

  after_each(function()
    _G.MDT_NPT = nil
    _G.C_ChallengeMode = nil
    _G.C_Map = nil
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
