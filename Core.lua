local AddonName = ...
local MDT = MDT
local MDT_NPT = MDT_NPT
local State = MDT_NPT.State
local Scenario = MDT_NPT.Scenario
local Beacon = MDT_NPT.Beacon

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
-- UpdateAll — fan out to child modules
-- =====================================================================

function MDT_NPT:UpdateAll()
  if Beacon.Update then
    Beacon:Update()
  end
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
-- Lifecycle events
-- =====================================================================

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == AddonName then
      local childDB = LibStub("AceDB-3.0"):New("MythicDungeonToolsNextPullDB", defaultSavedVars, true)
      db = childDB.global
      dbChar = childDB.char
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
