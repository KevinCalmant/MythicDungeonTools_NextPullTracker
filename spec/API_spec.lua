local mocks = require("wow_mocks")

describe("API.lua", function()
  local recomputeCalls
  local updateAllCalls

  local function makeState(pullStates, currentNextPull)
    return {
      active = true,
      pullStates = pullStates,
      currentNextPull = currentNextPull,
      dungeonIndex = 1,
    }
  end

  local function pull(state, opts)
    opts = opts or {}
    return {
      state        = state,
      totalCount   = opts.totalCount   or 5,
      totalForces  = opts.totalForces  or 10,
      killedCount  = opts.killedCount  or 0,
      forcesKilled = opts.forcesKilled or 0,
      lastUpdate   = 0,
    }
  end

  before_each(function()
    mocks.reset()

    -- Spies / stubs for the dependencies API.lua captures at load time.
    recomputeCalls  = 0
    updateAllCalls  = 0

    _G.MDT_NPT.State = {
      recomputeNextPull = function(_) recomputeCalls = recomputeCalls + 1 end,
    }
    _G.MDT_NPT.Scenario = {
      getScenarioCurrentForces = function() return 42 end,
    }
    function _G.MDT_NPT:UpdateAll()
      updateAllCalls = updateAllCalls + 1
    end

    mocks.loadSource("Modules/API.lua")
  end)

  describe("MarkComplete", function()
    it("writes all four fields, calls recompute + UpdateAll", function()
      _G.MDT_NPT.state = makeState({
        pull("next",     { totalCount = 3, totalForces = 20 }),
        pull("upcoming", { totalCount = 5, totalForces = 50 }),
      }, 1)

      _G.MDT_NPT:MarkComplete(1)

      local p = _G.MDT_NPT.state.pullStates[1]
      assert.equals("completed", p.state)
      assert.equals(3,           p.killedCount)
      assert.equals(20,          p.forcesKilled)
      assert.equals(1, recomputeCalls)
      assert.equals(1, updateAllCalls)
    end)

    it("is a no-op when state is inactive", function()
      _G.MDT_NPT.state = nil
      _G.MDT_NPT:MarkComplete(1)
      assert.equals(0, recomputeCalls)
      assert.equals(0, updateAllCalls)
    end)

    it("is a no-op when the pull index is out of range", function()
      _G.MDT_NPT.state = makeState({ pull("next") }, 1)
      _G.MDT_NPT:MarkComplete(99)
      assert.equals(0, recomputeCalls)
      assert.equals(0, updateAllCalls)
    end)
  end)

  describe("MarkIncomplete", function()
    it("resets state + counts, calls recompute + UpdateAll", function()
      _G.MDT_NPT.state = makeState({
        pull("completed", { totalCount = 3, totalForces = 20, killedCount = 3, forcesKilled = 20 }),
      }, nil)

      _G.MDT_NPT:MarkIncomplete(1)

      local p = _G.MDT_NPT.state.pullStates[1]
      assert.equals("upcoming", p.state)
      assert.equals(0, p.killedCount)
      assert.equals(0, p.forcesKilled)
      assert.equals(1, recomputeCalls)
      assert.equals(1, updateAllCalls)
    end)

    it("is a no-op when the pull index is out of range", function()
      _G.MDT_NPT.state = makeState({ pull("completed") }, nil)
      _G.MDT_NPT:MarkIncomplete(99)
      assert.equals(0, recomputeCalls)
      assert.equals(0, updateAllCalls)
    end)
  end)

  describe("SkipTo", function()
    -- Build a 5-pull state: all upcoming except currentNextPull=1
    local function fivePullState()
      return makeState({
        pull("next",     { totalCount = 2, totalForces = 10 }),
        pull("upcoming", { totalCount = 3, totalForces = 15 }),
        pull("upcoming", { totalCount = 4, totalForces = 20 }),
        pull("upcoming", { totalCount = 5, totalForces = 25 }),
        pull("upcoming", { totalCount = 6, totalForces = 30 }),
      }, 1)
    end

    it("marks pulls before the target as COMPLETED (i < pullIndex branch)", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT:SkipTo(3)

      local p1 = _G.MDT_NPT.state.pullStates[1]
      local p2 = _G.MDT_NPT.state.pullStates[2]
      assert.equals("completed", p1.state)
      assert.equals(p1.totalCount,  p1.killedCount)
      assert.equals(p1.totalForces, p1.forcesKilled)
      assert.equals("completed", p2.state)
      assert.equals(p2.totalCount,  p2.killedCount)
      assert.equals(p2.totalForces, p2.forcesKilled)
    end)

    it("marks the target pull as NEXT with cleared counts (i == pullIndex branch)", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT:SkipTo(3)

      local p3 = _G.MDT_NPT.state.pullStates[3]
      assert.equals("next", p3.state)
      assert.equals(0, p3.killedCount)
      assert.equals(0, p3.forcesKilled)
      assert.equals(3, _G.MDT_NPT.state.currentNextPull)
    end)

    it("resets non-completed pulls after target to UPCOMING (i > pullIndex branch)", function()
      _G.MDT_NPT.state = fivePullState()
      -- Dirty pull 4 to simulate a previously active pull
      _G.MDT_NPT.state.pullStates[4].state = "active"
      _G.MDT_NPT.state.pullStates[4].forcesKilled = 12

      _G.MDT_NPT:SkipTo(3)

      local p4 = _G.MDT_NPT.state.pullStates[4]
      local p5 = _G.MDT_NPT.state.pullStates[5]
      assert.equals("upcoming", p4.state)
      assert.equals(0, p4.killedCount)
      assert.equals(0, p4.forcesKilled)
      assert.equals("upcoming", p5.state)
    end)

    it("preserves already-completed pulls past the target (i > pullIndex, COMPLETED branch)", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT.state.pullStates[5].state        = "completed"
      _G.MDT_NPT.state.pullStates[5].killedCount  = 6
      _G.MDT_NPT.state.pullStates[5].forcesKilled = 30

      _G.MDT_NPT:SkipTo(3)

      local p5 = _G.MDT_NPT.state.pullStates[5]
      assert.equals("completed", p5.state)
      assert.equals(6,  p5.killedCount)
      assert.equals(30, p5.forcesKilled)
    end)

    it("reseeds state.lastForces from the scenario API", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT.state.lastForces = 0

      _G.MDT_NPT:SkipTo(3)

      assert.equals(42, _G.MDT_NPT.state.lastForces)
    end)

    it("calls UpdateAll exactly once per skip", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT:SkipTo(3)
      assert.equals(1, updateAllCalls)
    end)

    it("is a no-op when the target pull doesn't exist", function()
      _G.MDT_NPT.state = fivePullState()
      _G.MDT_NPT:SkipTo(99)
      assert.equals(1, _G.MDT_NPT.state.currentNextPull) -- unchanged
      assert.equals(0, updateAllCalls)
    end)
  end)
end)
