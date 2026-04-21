local mocks = require("wow_mocks")

describe("Scenario.lua", function()
  local Scenario
  local currentForcesReading

  local function makeState(pullStates, currentNextPull)
    return {
      active = true,
      dungeonIndex = 1,
      lastForces = 0,
      currentNextPull = currentNextPull,
      pullStates = pullStates,
    }
  end

  local function pull(state, totalForces)
    return {
      state = state, totalCount = 5, totalForces = totalForces,
      forcesKilled = 0, killedCount = 0, lastUpdate = 0,
    }
  end

  before_each(function()
    mocks.reset()
    currentForcesReading = 0

    -- Minimal recompute: promotes the lowest non-terminal pull to NEXT.
    -- Matches the real State.recomputeNextPull contract for the consume loop.
    _G.MDT_NPT.State = {
      recomputeNextPull = function(state)
        state.currentNextPull = nil
        for _, ps in ipairs(state.pullStates) do
          if ps.state == "next" then ps.state = "upcoming" end
        end
        for i, ps in ipairs(state.pullStates) do
          if ps.state ~= "completed" and ps.state ~= "active" then
            ps.state = "next"
            state.currentNextPull = i
            return
          end
        end
      end,
    }

    -- Scenario reads forces via MDT_NPT.Wow; tests control the reading via
    -- `currentForcesReading` (closure captured here).
    _G.MDT_NPT.Wow = {
      getScenarioStepInfo = function() return 1 end,
      getScenarioCriteriaInfo = function()
        return {
          quantity       = currentForcesReading,
          totalQuantity  = 200,  -- matches dungeonMax below
          isWeightedProgress = false,
        }
      end,
    }
    _G.MDT_NPT.Utils = {
      parseNum = function(v) return tonumber(v) or 0 end,
    }
    _G.MDT_NPT.Debug = {
      make = function(_, _) return { print = function() end } end,
    }
    function _G.MDT_NPT:UpdateAll() end

    _G.MDT.dungeonTotalCount[1] = { normal = 200 }

    mocks.loadSource("Modules/Scenario.lua")
    Scenario = _G.MDT_NPT.Scenario
  end)

  describe("onScenarioForcesUpdate", function()
    it("is a no-op when tracking state is nil or inactive", function()
      _G.MDT_NPT.state = nil
      assert.has_no.errors(function() Scenario.onScenarioForcesUpdate() end)
    end)

    it("ignores zero deltas (lastForces == currentForces)", function()
      _G.MDT_NPT.state = makeState({ pull("next", 50) }, 1)
      _G.MDT_NPT.state.lastForces = 50
      currentForcesReading = 50
      Scenario.onScenarioForcesUpdate()
      local p = _G.MDT_NPT.state.pullStates[1]
      assert.equals(0, p.forcesKilled)
      assert.equals("next", p.state)
    end)

    it("transitions the next pull from NEXT to ACTIVE on first forces gain", function()
      _G.MDT_NPT.state = makeState({ pull("next", 100) }, 1)
      currentForcesReading = 30
      Scenario.onScenarioForcesUpdate()
      local p = _G.MDT_NPT.state.pullStates[1]
      assert.equals("active", p.state)
      assert.equals(30, p.forcesKilled)
    end)

    it("partial kill: accumulates forcesKilled without completing the pull", function()
      _G.MDT_NPT.state = makeState({ pull("next", 100) }, 1)
      currentForcesReading = 30
      Scenario.onScenarioForcesUpdate()
      assert.equals(30, _G.MDT_NPT.state.pullStates[1].forcesKilled)
      assert.equals("active", _G.MDT_NPT.state.pullStates[1].state)
    end)

    it("completes a pull and consumes overflow into the next pull", function()
      _G.MDT_NPT.state = makeState({
        pull("next",     50),
        pull("upcoming", 30),
      }, 1)
      currentForcesReading = 60 -- 50 completes pull 1, 10 bleeds into pull 2
      Scenario.onScenarioForcesUpdate()

      local p1 = _G.MDT_NPT.state.pullStates[1]
      local p2 = _G.MDT_NPT.state.pullStates[2]
      assert.equals("completed", p1.state)
      assert.equals(50, p1.forcesKilled)
      assert.equals("active", p2.state)
      assert.equals(10, p2.forcesKilled)
    end)

    it("applies the tolerance when the gap is strictly below 1% of dungeonMax", function()
      -- dungeonMax=200 → tolerance=2. delta=49, remainingInPull=50 → 49+2>50 → complete
      _G.MDT_NPT.state = makeState({ pull("next", 50) }, 1)
      currentForcesReading = 49
      Scenario.onScenarioForcesUpdate()
      assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
    end)

    it("does NOT apply tolerance when the gap equals exactly 1% of dungeonMax", function()
      -- Blizzard's floor-rounding error is strictly < 1%, so a gap of exactly 1%
      -- is a real deficit. delta=48, tolerance=2, remainingInPull=50 → 48+2=50, NOT > 50 → partial
      _G.MDT_NPT.state = makeState({ pull("next", 50) }, 1)
      currentForcesReading = 48
      Scenario.onScenarioForcesUpdate()
      assert.equals("active", _G.MDT_NPT.state.pullStates[1].state)
      assert.equals(48, _G.MDT_NPT.state.pullStates[1].forcesKilled)
    end)

    it("does NOT apply tolerance when the gap exceeds 1% of dungeonMax", function()
      -- delta=47, tolerance=2, remainingInPull=50 → 47+2<50 → partial
      _G.MDT_NPT.state = makeState({ pull("next", 50) }, 1)
      currentForcesReading = 47
      Scenario.onScenarioForcesUpdate()
      assert.equals("active", _G.MDT_NPT.state.pullStates[1].state)
      assert.equals(47, _G.MDT_NPT.state.pullStates[1].forcesKilled)
    end)

    it("advances currentNextPull across multiple consumed pulls in one delta", function()
      _G.MDT_NPT.state = makeState({
        pull("next",     20),
        pull("upcoming", 20),
        pull("upcoming", 20),
      }, 1)
      currentForcesReading = 45 -- pull 1 (20) + pull 2 (20) + 5 into pull 3
      Scenario.onScenarioForcesUpdate()

      assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
      assert.equals("completed", _G.MDT_NPT.state.pullStates[2].state)
      assert.equals(5,           _G.MDT_NPT.state.pullStates[3].forcesKilled)
      assert.equals(3, _G.MDT_NPT.state.currentNextPull)
    end)

    it("seeds baseline to 0 when lastForces is nil (catches up mid-key)", function()
      _G.MDT_NPT.state = makeState({
        pull("next", 20),
        pull("upcoming", 20),
      }, 1)
      _G.MDT_NPT.state.lastForces = nil
      currentForcesReading = 30 -- should attribute 20 to pull 1 (complete) + 10 to pull 2
      Scenario.onScenarioForcesUpdate()
      assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
      assert.equals(10,          _G.MDT_NPT.state.pullStates[2].forcesKilled)
    end)

    it("updates state.lastForces to the current reading after consuming", function()
      _G.MDT_NPT.state = makeState({ pull("next", 100) }, 1)
      currentForcesReading = 30
      Scenario.onScenarioForcesUpdate()
      assert.equals(30, _G.MDT_NPT.state.lastForces)
    end)
  end)
end)
