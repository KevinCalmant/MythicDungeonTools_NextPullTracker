local mocks = require("wow_mocks")

describe("Core.lua — NPT_BEACON_ASK popup", function()
  local eventFrame
  local popupShowCalls
  local timerDelayed
  local updateAllCalls
  local mockDb, mockDbChar

  local function fireOnEvent(event, ...)
    eventFrame._scripts.OnEvent(eventFrame, event, ...)
  end

  before_each(function()
    mocks.reset()

    -- Frames: capture every CreateFrame so the test can fire events on the first one.
    local frames = {}
    _G.CreateFrame = function(_)
      local f = { _scripts = {}, _events = {} }
      function f:SetScript(n, fn) self._scripts[n] = fn end
      function f:RegisterEvent(e) self._events[e] = true end
      function f:UnregisterEvent(e) self._events[e] = nil end
      table.insert(frames, f)
      return f
    end

    -- AceDB via LibStub: hand Core.lua a pre-built db/dbChar shaped like defaultSavedVars.
    mockDb = {
      enabled = true,
      autoStartInKey = false, -- keep Start() out of these tests
      beacon = {
        enabled = true,
        showForNonTank = false,
        askOnStart = true,
      },
    }
    mockDbChar = { beacon = {} }
    _G.LibStub = function()
      return { New = function() return { global = mockDb, char = mockDbChar } end }
    end

    -- Popup surface
    _G.StaticPopupDialogs = {}
    popupShowCalls = {}
    _G.StaticPopup_Show = function(name) table.insert(popupShowCalls, name) end
    _G.YES = "Yes"
    _G.NO = "No"

    -- C_Timer.After: capture the callback so tests can fire it deterministically.
    timerDelayed = nil
    _G.C_Timer = { After = function(_, fn) timerDelayed = fn end }

    -- Role APIs default to non-tank so the popup path is the default.
    _G.GetSpecialization = function() return 1 end
    _G.GetSpecializationRole = function() return "DAMAGER" end

    -- Child modules Core.lua captures as upvalues at load time.
    _G.MDT_NPT.State = { buildStateFromPreset = function() return nil end }
    _G.MDT_NPT.Scenario = {}
    _G.MDT_NPT.Beacon = {}
    _G.MDT_NPT.Mdt = { syncMDTDungeonToPlayerZone = function() end }

    -- Silence the in-game prints Core.lua fires on Start/Stop.
    _G.print = function() end

    -- Execute Core.lua with the addon-name vararg the real harness provides.
    local chunk = assert(loadfile("Core.lua"))
    chunk("MythicDungeonTools_NextPullTracker")

    eventFrame = frames[1]

    -- Replace UpdateAll with a spy *after* Core.lua has installed its own version.
    updateAllCalls = 0
    function _G.MDT_NPT:UpdateAll() updateAllCalls = updateAllCalls + 1 end

    -- Populate the db upvalue inside Core.lua.
    fireOnEvent("ADDON_LOADED", "MythicDungeonTools_NextPullTracker")
  end)

  describe("popup registration", function()
    it("registers NPT_BEACON_ASK with three buttons and escape/timeout behaviour", function()
      local popup = _G.StaticPopupDialogs["NPT_BEACON_ASK"]
      assert.is_not_nil(popup)
      assert.is_string(popup.text)
      assert.equals("Yes", popup.button1)
      assert.equals("No", popup.button2)
      assert.equals("Never ask", popup.button3)
      assert.is_function(popup.OnAccept)
      assert.is_function(popup.OnCancel)
      assert.is_function(popup.OnAlt)
      assert.equals(30, popup.timeout)
      assert.is_true(popup.whileDead)
      assert.is_true(popup.hideOnEscape)
    end)

    it("OnAccept opts in for non-tanks and triggers a UI refresh", function()
      _G.StaticPopupDialogs["NPT_BEACON_ASK"].OnAccept()
      assert.is_true(mockDb.beacon.showForNonTank)
      assert.equals(1, updateAllCalls)
    end)

    it("OnCancel clears the non-tank opt-in without disabling future prompts", function()
      mockDb.beacon.showForNonTank = true
      _G.StaticPopupDialogs["NPT_BEACON_ASK"].OnCancel()
      assert.is_false(mockDb.beacon.showForNonTank)
      assert.is_true(mockDb.beacon.askOnStart)
    end)

    it("OnAlt (\"Never ask\") disables both the opt-in and future prompts", function()
      mockDb.beacon.showForNonTank = true
      _G.StaticPopupDialogs["NPT_BEACON_ASK"].OnAlt()
      assert.is_false(mockDb.beacon.showForNonTank)
      assert.is_false(mockDb.beacon.askOnStart)
    end)
  end)

  describe("CHALLENGE_MODE_START — maybePromptForBeacon", function()
    local function fireStart()
      fireOnEvent("CHALLENGE_MODE_START")
      if timerDelayed then timerDelayed() end
    end

    it("shows the popup on key start for a non-tank who hasn't opted in", function()
      fireStart()
      assert.same({ "NPT_BEACON_ASK" }, popupShowCalls)
    end)

    it("skips the popup when askOnStart is disabled", function()
      mockDb.beacon.askOnStart = false
      fireStart()
      assert.same({}, popupShowCalls)
      assert.is_nil(timerDelayed) -- no delay scheduled either
    end)

    it("skips the popup when the player already opted non-tanks in", function()
      mockDb.beacon.showForNonTank = true
      fireStart()
      assert.same({}, popupShowCalls)
      assert.is_nil(timerDelayed)
    end)

    it("skips the popup for tanks", function()
      _G.GetSpecializationRole = function() return "TANK" end
      fireStart()
      assert.same({}, popupShowCalls)
      assert.is_nil(timerDelayed)
    end)
  end)
end)
