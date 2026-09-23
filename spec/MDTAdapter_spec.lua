describe("MDTAdapter.lua", function()
  local function loadAdapter(namespace)
    local chunk = assert(loadfile("Modules/MDTAdapter.lua"))
    chunk("MythicDungeonTools_NextPullTracker", namespace)
    return namespace.MDT
  end

  before_each(function()
    _G.MythicDungeonToolsDB = nil
    _G.MythicDungeonToolsAPI = nil
    _G.C_AddOns = nil
    _G.C_Map = nil
  end)

  after_each(function()
    _G.MythicDungeonToolsDB = nil
    _G.MythicDungeonToolsAPI = nil
    _G.C_AddOns = nil
    _G.C_Map = nil
  end)

  it("maps zones registered through MDT's dungeon location API", function()
    local adapter = loadAdapter({ L = {} })
    adapter:RegisterDungeonLocation(161, { zoneIds = { 2513, 2514 }, subzoneAreaIDs = { 16189 } })

    assert.equals(161, adapter.zoneIdToDungeonIdx[2513])
    assert.equals(161, adapter.zoneIdToDungeonIdx[2514])
    assert.equals(161, adapter:GetDungeonIdxForZone(2513))
    assert.is_nil(adapter:GetDungeonIdxForZone(9999))
  end)

  it("keeps the first dungeon registered for a shared zone", function()
    local adapter = loadAdapter({ L = {} })
    adapter:RegisterDungeonLocation(161, { zoneIds = { 2437, 2513 } })
    adapter:RegisterDungeonLocation(154, { zoneIds = { 2437, 2501 } })

    assert.equals(161, adapter.zoneIdToDungeonIdx[2437])
    assert.equals(154, adapter.zoneIdToDungeonIdx[2501])
  end)

  it("resolves a shared zone by subzone name", function()
    local areaNames = { [16189] = "Nalorakk's Prowl", [16199] = "Maisara Deeps" }
    _G.C_Map = { GetAreaInfo = function(areaID) return areaNames[areaID] end }

    local adapter = loadAdapter({ L = {} })
    adapter:RegisterDungeonLocation(161, { zoneIds = { 2437 }, subzoneAreaIDs = { 16189 } })
    adapter:RegisterDungeonLocation(154, { zoneIds = { 2437 }, subzoneAreaIDs = { 16199 } })

    assert.equals(154, adapter:GetDungeonIdxForZone(2437, "Maisara Deeps"))
    assert.equals(161, adapter:GetDungeonIdxForZone(2437, "Nalorakk's Prowl"))
    assert.equals(161, adapter:GetDungeonIdxForZone(2437, "Somewhere Else"))
    assert.equals(161, adapter:GetDungeonIdxForZone(2437, ""))
  end)

  it("ignores malformed dungeon locations", function()
    local adapter = loadAdapter({ L = {} })
    adapter:RegisterDungeonLocation(161)
    adapter:RegisterDungeonLocation(161, { subzoneAreaIDs = { 16189 } })
    adapter:RegisterDungeonLocation(nil, { zoneIds = { 2437 } })

    assert.is_nil(next(adapter.zoneIdToDungeonIdx))
  end)

  -- Loads MDT's own Midnight dungeon files the way the TOC does, so an MDT
  -- release that expects more from the adapter fails here instead of in game.
  -- CI checks MDT out and sets MDT_PATH; locally it defaults to the sibling
  -- AddOns folder the TOC reads from.
  describe("with MDT's Midnight dungeon files", function()
    local configuredRoot = os.getenv("MDT_PATH")
    if configuredRoot == "" then configuredRoot = nil end
    local mdtRoot = configuredRoot or "../MythicDungeonTools"
    local xmlFile = io.open(mdtRoot.."/Midnight/load_midnight.xml", "rb")
    if not xmlFile then
      if configuredRoot then
        -- An explicit path that does not resolve must fail, or CI would skip
        -- the check without anyone noticing.
        it("finds MDT at MDT_PATH", function()
          error("load_midnight.xml not found under MDT_PATH="..configuredRoot)
        end)
      else
        pending("MDT source not found at "..mdtRoot.." (set MDT_PATH)")
      end
      return
    end
    local xml = xmlFile:read("*a")
    xmlFile:close()

    local scripts = {}
    for fileName in xml:gmatch("<Script%s+file%s*=%s*[\"']([^\"']+)[\"']") do
      scripts[#scripts + 1] = fileName
    end

    it("loads every dungeon file into the adapter", function()
      assert.is_true(#scripts > 0, "no Script entries in load_midnight.xml")
      local adapter = loadAdapter({ L = {} })

      local failures = {}
      for _, fileName in ipairs(scripts) do
        local chunk, loadError = loadfile(mdtRoot.."/Midnight/"..fileName)
        local ok, runError = false, loadError
        if chunk then ok, runError = pcall(chunk, "MythicDungeonTools_NextPullTracker", adapter) end
        if not ok then failures[#failures + 1] = fileName..": "..tostring(runError) end
      end
      assert.same({}, failures)

      local dungeonCount = 0
      for dungeonIdx in pairs(adapter.dungeonList) do
        dungeonCount = dungeonCount + 1
        assert.is_table(adapter.mapInfo[dungeonIdx], "mapInfo for dungeon "..dungeonIdx)
        assert.is_table(adapter.dungeonEnemies[dungeonIdx], "dungeonEnemies for dungeon "..dungeonIdx)
        assert.is_table(adapter.dungeonMaps[dungeonIdx], "dungeonMaps for dungeon "..dungeonIdx)
        assert.is_number((adapter.dungeonTotalCount[dungeonIdx] or {}).normal,
          "dungeonTotalCount for dungeon "..dungeonIdx)
      end
      assert.equals(#scripts, dungeonCount)
      assert.is_not_nil(next(adapter.zoneIdToDungeonIdx), "no zones registered")
    end)
  end)

  it("uses the public MDT database without relying on the removed global", function()
    local db = { currentDungeonIdx = 7, currentPreset = { [7] = 2 }, presets = { [7] = {} } }
    db.presets[7][2] = { uid = "route-7", value = { pulls = { {} } } }
    _G.MythicDungeonToolsAPI = { GetDB = function() return db end }

    local namespace = { L = {} }
    local adapter = loadAdapter(namespace)

    assert.is_nil(_G.MDT)
    assert.equals(db, adapter:GetDB())
    assert.equals("route-7", adapter:GetCurrentPreset().uid)
  end)

  it("falls back to MDT saved variables when the public API is unavailable", function()
    local db = { currentDungeonIdx = 3 }
    _G.MythicDungeonToolsDB = { global = db }

    local adapter = loadAdapter({ L = {} })
    assert.equals(db, adapter:GetDB())
  end)

  it("prefers the active AceDB table over MDT's stale bootstrap database", function()
    local bootstrapDB = { currentDungeonIdx = 1 }
    local activeDB = { currentDungeonIdx = 8, currentPreset = { [8] = 1 }, presets = { [8] = {} } }
    activeDB.presets[8][1] = { uid = "ace-route", value = { pulls = { {} } } }
    _G.MythicDungeonToolsAPI = { GetDB = function() return bootstrapDB end }
    _G.MythicDungeonToolsDB = { global = activeDB }

    local adapter = loadAdapter({ L = {} })
    assert.equals(activeDB, adapter:GetDB())
    assert.equals("ace-route", adapter:GetCurrentPreset().uid)
  end)

  it("updates the selected dungeon and initializes its preset selection", function()
    local db = { currentPreset = {}, presets = {} }
    _G.MythicDungeonToolsAPI = { GetDB = function() return db end }

    local adapter = loadAdapter({ L = {} })
    assert.is_true(adapter:UpdateToDungeon(42))
    assert.equals(42, db.currentDungeonIdx)
    assert.equals(1, db.currentPreset[42])
  end)

  it("returns nil safely when no preset is selected", function()
    _G.MythicDungeonToolsAPI = { GetDB = function() return {} end }
    local adapter = loadAdapter({ L = {} })
    assert.is_nil(adapter:GetCurrentPreset())
  end)

  it("loads MDT's UI addon before reading its presets", function()
    local uiLoaded = false
    local db = { currentDungeonIdx = 9, currentPreset = { [9] = 1 }, presets = { [9] = {} } }
    db.presets[9][1] = { uid = "loaded-route", value = { pulls = { {} } } }
    _G.MythicDungeonToolsAPI = { GetDB = function() return db end }
    _G.C_AddOns = {
      IsAddOnLoaded = function() return uiLoaded end,
      LoadAddOn = function(addonName)
        assert.equals("MythicDungeonTools_UI", addonName)
        uiLoaded = true
        return true
      end,
    }

    local adapter = loadAdapter({ L = {} })
    assert.equals("loaded-route", adapter:GetCurrentPreset().uid)
    assert.is_true(uiLoaded)
  end)

  it("accepts migrated string keys and skips MDT's empty new-preset entry", function()
    local db = {
      currentDungeonIdx = 12,
      currentPreset = { ["12"] = "2" },
      presets = { ["12"] = {
        ["1"] = { uid = "usable", value = { pulls = { {} } } },
        ["2"] = { value = 0 },
      } },
    }
    _G.MythicDungeonToolsDB = { global = db }

    local adapter = loadAdapter({ L = {} })
    assert.equals("usable", adapter:GetCurrentPreset().uid)
  end)

  it("reads a requested dungeon independently of MDT's current selection", function()
    local db = {
      currentDungeonIdx = 160,
      currentPreset = { [160] = 1, [161] = 2 },
      presets = {
        [160] = {
          [1] = { uid = "murder-route", value = { currentDungeonIdx = 160, pulls = { {} } } },
        },
        [161] = {
          [2] = { uid = "nalorakk-route", value = { currentDungeonIdx = 161, pulls = { {} } } },
        },
      },
    }
    _G.MythicDungeonToolsDB = { global = db }

    local adapter = loadAdapter({ L = {} })
    assert.equals("nalorakk-route", adapter:GetCurrentPreset(161).uid)
    assert.equals(160, db.currentDungeonIdx)
  end)
end)
