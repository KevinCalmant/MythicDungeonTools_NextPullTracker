local AddonName = ...
local MDT_NPT = MDT_NPT
local MDT = MDT_NPT.MDT or MDT
local State = MDT_NPT.State
local Scenario = MDT_NPT.Scenario
local Beacon = MDT_NPT.Beacon
local Mdt = MDT_NPT.Mdt
local Wow = MDT_NPT.Wow

local db, dbChar
local pollTimer
local eventFrame = CreateFrame("Frame")

local defaultSavedVars = {
  global = {
    enabled = true,
    autoStartInKey = true,
    beaconScope = "char",
    beacon = {
      enabled = true,
      scale = 1.0,
      alpha = 1.0,
      anchorFrom = "TOP",
      anchorTo = "TOP",
      xoffset = 0,
      yoffset = -50,
      locked = false,
      showForNonTank = false,
      showUpcoming = true,
      askOnStart = true,
      -- When true, the beacon shrinks to just the minimap and hides the info
      -- panel (pull header, mob count, portraits, progress bar, upcoming).
      mapOnly = false,
      -- Per-state colors for the minimap pull DOTS. {r, g, b, a}. Keys match
      -- BeaconMinimap's pull states.
      pullColors = {
        ["next"] = { 0, 1, 0.5, 1 },
        ["active"] = { 1, 0.5, 0, 1 },
        ["completed"] = { 0.4, 0.4, 0.4, 0.6 },
        ["upcoming"] = { 1, 1, 0, 0.7 },
      },
      -- Color of the OUTLINE (circle) drawn around the current pull, kept
      -- separate from the dot colors. Only the current pull (next/active) has
      -- an outline. Defaults match the dot colors so the look is unchanged.
      pullOutlineColors = {
        ["next"] = { 0, 1, 0.5, 1 },
        ["active"] = { 1, 0.5, 0, 1 },
      },
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

StaticPopupDialogs["NPT_BEACON_ASK"] = {
  text = "Mythic+ started. Display the MDT Next Pull Beacon on your screen?",
  button1 = YES,
  button2 = NO,
  button3 = "Never ask",
  OnAccept = function()
    db.beacon.showForNonTank = true
    MDT_NPT:UpdateAll()
  end,
  OnCancel = function()
    db.beacon.showForNonTank = false
  end,
  OnAlt = function()
    db.beacon.showForNonTank = false
    db.beacon.askOnStart = false
  end,
  timeout = 30,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
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

  Mdt.syncMDTDungeonToPlayerZone()

  local preset = MDT:GetCurrentPreset()
  if not preset then
    local diagnostics = MDT.GetPresetDiagnostics and MDT:GetPresetDiagnostics() or "diagnostics unavailable"
    print("|cFF00FF00MDT-NextPullTracker|r: Cannot start tracking — no non-empty MDT route is available ("..diagnostics..").")
    return
  end

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
  eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")

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
  eventFrame:UnregisterEvent("CHALLENGE_MODE_RESET")

  if pollTimer then
    pollTimer:Cancel()
    pollTimer = nil
  end

  self:UpdateAll()
  print("|cFF00FF00MDT-NextPullTracker|r: Tracking stopped.")
end

---Maybe show the non-tank prompt on dungeon start
local function maybePromptForBeacon()
  if not db.beacon.askOnStart then return end
  if db.beacon.showForNonTank then return end -- already opted in
  local role = Wow and Wow.getPlayerRole and Wow.getPlayerRole() or nil
  if role == "TANK" then return end -- tanks don't need to be asked
  -- Delay the popup slightly so it appears after UI is stable
  C_Timer.After(1, function()
    StaticPopup_Show("NPT_BEACON_ASK")
  end)
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
    maybePromptForBeacon()
  elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
    MDT_NPT:Stop()
  elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_UPDATE" then
    if Scenario and Scenario.onScenarioForcesUpdate then
      Scenario.onScenarioForcesUpdate()
    end
  end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
