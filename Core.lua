local AddonName = ...
local MDT = MDT
local MDT_NPT = MDT_NPT
local L = MDT_NPT.L
local State = MDT_NPT.State
local Scenario = MDT_NPT.Scenario

local pairs = pairs

local db, dbChar
local pollTimer
local eventFrame = CreateFrame("Frame")
local nameplateFrame = CreateFrame("Frame")

local defaultSavedVars = {
  global = {
    enabled = true,
    autoStartInKey = true,
    dimUpcoming = 0,
    highlightColor = { 0, 1, 0.5 },
    beaconScope = "char",
    beacon = {
      enabled = true,
      scale = 1.0,
      anchorFrom = "TOP",
      anchorTo = "TOP",
      xoffset = 0,
      yoffset = -50,
      locked = false,
      showForNonTank = false,
      showUpcoming = true,
      askOnStart = true,
    },
    sync = {
      authority = "auto",
    },
    _migratedFromParent = false,
  },
  char = {
    beacon = {
      anchorFrom = "TOP",
      anchorTo = "TOP",
      xoffset = 0,
      yoffset = -50,
      scale = 1.0,
      locked = false,
    },
  },
}

function MDT_NPT:GetDB() return db end

function MDT_NPT:GetDBChar() return dbChar end

-- =====================================================================
-- Public API — state queries
-- =====================================================================

function MDT_NPT:IsActive()
  return self.state ~= nil and self.state.active == true
end

function MDT_NPT:GetCurrentNextPull()
  local s = self.state
  if not s or not s.active then return nil end
  return s.currentNextPull
end

function MDT_NPT:GetPullState(pullIndex)
  local s = self.state
  if not s or not s.active then return nil end
  local ps = s.pullStates[pullIndex]
  return ps and ps.state or nil
end

function MDT_NPT:GetPullStateData(pullIndex)
  local s = self.state
  if not s or not s.active then return nil end
  return s.pullStates[pullIndex]
end

-- =====================================================================
-- UpdateAll — fan out to parent hooks and (future) child modules
-- =====================================================================

function MDT_NPT:UpdateAll()
  if MDT.DungeonEnemies_UpdateNextPullGlow then
    MDT:DungeonEnemies_UpdateNextPullGlow()
  end
  if MDT.DrawAllHulls and MDT.main_frame and MDT.main_frame.mapPanelFrame then
    MDT:DrawAllHulls(nil, true)
  end
  if MDT.UpdatePullButtonStates then
    MDT:UpdatePullButtonStates()
  end
  -- TODO: nameplate markers, Beacon:Update()
end

-- =====================================================================
-- Start / Stop
-- =====================================================================

function MDT_NPT:Start(manual)
  if not db then db = self:GetDB() end
  if not db or not db.enabled then return end

  local preset = MDT:GetCurrentPreset()
  if not preset then return end

  local state = State.buildStateFromPreset(preset)
  if not state then
    print("|cFF00FF00MDT-NextPullTracker|r: Cannot start tracking — no pulls in current preset.")
    return
  end

  if manual then state.manuallyStarted = true end
  state.lastForces = 0

  MDT_NPT.state = state

  eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
  eventFrame:RegisterEvent("SCENARIO_UPDATE")
  eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

  if pollTimer then pollTimer:Cancel() end
  pollTimer = C_Timer.NewTicker(1.0, function()
    if MDT_NPT.state and MDT_NPT.state.active and Scenario and Scenario.onScenarioForcesUpdate then
      Scenario.onScenarioForcesUpdate()
    end
  end)

  self:UpdateAll()
  print("|cFF00FF00MDT-NextPullTracker|r: Tracking started. Pull 1 is next.")
end

function MDT_NPT:Stop()
  MDT_NPT.state = nil

  eventFrame:UnregisterEvent("SCENARIO_CRITERIA_UPDATE")
  eventFrame:UnregisterEvent("SCENARIO_UPDATE")
  eventFrame:UnregisterEvent("CHALLENGE_MODE_COMPLETED")

  if pollTimer then
    pollTimer:Cancel()
    pollTimer = nil
  end

  self:UpdateAll()
  print("|cFF00FF00MDT-NextPullTracker|r: Tracking stopped.")
end

-- =====================================================================
-- One-shot migration from parent's MythicDungeonToolsDB
-- =====================================================================

local function migrateFromParent()
  if not db or db._migratedFromParent then return end

  local parentDB     = MDT and MDT.GetDB and MDT:GetDB()
  local parentDBChar = MDT and MDT.GetDBChar and MDT:GetDBChar()

  if parentDB and parentDB.nextPull then
    for k, v in pairs(parentDB.nextPull) do
      if type(v) == "table" then
        db[k] = CopyTable(v)
      else
        db[k] = v
      end
    end
  end
  if parentDBChar and parentDBChar.nextPull and parentDBChar.nextPull.beacon then
    dbChar.beacon = CopyTable(parentDBChar.nextPull.beacon)
  end

  db._migratedFromParent = true
end

-- =====================================================================
-- Lifecycle events
-- =====================================================================

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == AddonName then
      local childDB = LibStub("AceDB-3.0"):New("MythicDungeonToolsNextPullDB", defaultSavedVars, true)
      db = childDB.global
      dbChar = childDB.char
      migrateFromParent()
      eventFrame:UnregisterEvent("ADDON_LOADED")
    end
  elseif event == "CHALLENGE_MODE_START" then
    if db and db.enabled and db.autoStartInKey then
      MDT_NPT:Start()
    end
  elseif event == "CHALLENGE_MODE_COMPLETED" then
    MDT_NPT:Stop()
  elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_UPDATE" then
    if Scenario and Scenario.onScenarioForcesUpdate then
      Scenario.onScenarioForcesUpdate()
    end
  end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
