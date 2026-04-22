local mocks = require("wow_mocks")

describe("Scenario.lua", function()
  local Scenario
  local currentForcesReading
  local scenarioCriteria

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
    scenarioCriteria = nil -- default: a single non-weighted criterion driven by currentForcesReading

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

    -- Scenario reads forces via MDT_NPT.Wow. Default mock: one non-weighted
    -- criterion whose quantity is driven by `currentForcesReading`. Tests that
    -- need multiple criteria (e.g. boss-kill criteria) assign to
    -- `scenarioCriteria` directly.
    _G.MDT_NPT.Wow = {
      getScenarioStepInfo = function()
        return scenarioCriteria and #scenarioCriteria or 1
      end,
      getScenarioCriteriaInfo = function(index)
        if scenarioCriteria then return scenarioCriteria[index] end
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

    -- Boss pulls typically have totalForces=0 (the boss itself contributes no
    -- enemy forces). The forces-delta path alone would either collapse the pull
    -- on overflow from the preceding trash pull, or leave it stuck if no delta
    -- arrives at all. Completion must come from the non-weighted boss-kill
    -- criterion in the scenario, not from forces math.
    describe("boss pull handling", function()
      local function bossPull(state)
        return {
          state = state, totalCount = 1, totalForces = 0,
          forcesKilled = 0, killedCount = 0, lastUpdate = 0,
          hasBoss = true,
        }
      end

      it("does NOT auto-complete a 0-forces boss pull when delta overflows into it", function()
        _G.MDT_NPT.state = makeState({
          pull("next",     20),
          bossPull("upcoming"),
          pull("upcoming", 30),
        }, 1)
        -- pull 1 (20) completes; 5 overflow must NOT collapse boss pull
        scenarioCriteria = {
          { quantity = 25, totalQuantity = 200, isWeightedProgress = false, completed = false },
        }

        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals("next",      _G.MDT_NPT.state.pullStates[2].state)
        assert.is_true(_G.MDT_NPT.state.pullStates[2].hasBoss)
        assert.equals(0, _G.MDT_NPT.state.pullStates[2].forcesKilled)
        assert.equals(2, _G.MDT_NPT.state.currentNextPull)
      end)

      it("completes the current boss pull when its boss criterion flips to completed", function()
        _G.MDT_NPT.state = makeState({ bossPull("next"), pull("upcoming", 30) }, 1)
        -- Two criteria: weighted forces (idle) + a boss criterion that is now completed.
        scenarioCriteria = {
          { quantity = 0, totalQuantity = 100, isWeightedProgress = true },
          { quantity = 1, totalQuantity = 1,   isWeightedProgress = false, completed = true },
        }

        -- Seed pass: first call registers the already-completed criterion without
        -- firing, so pre-existing completions at start don't wrongly advance.
        Scenario.onScenarioForcesUpdate()
        assert.equals("next", _G.MDT_NPT.state.pullStates[1].state)
      end)

      it("fires boss advance when a boss criterion transitions from pending to completed", function()
        _G.MDT_NPT.state = makeState({ bossPull("next"), pull("upcoming", 30) }, 1)
        scenarioCriteria = {
          { quantity = 0, totalQuantity = 100, isWeightedProgress = true },
          { quantity = 0, totalQuantity = 1,   isWeightedProgress = false, completed = false },
        }
        -- First call seeds the "already seen" set.
        Scenario.onScenarioForcesUpdate()
        assert.equals("next", _G.MDT_NPT.state.pullStates[1].state)

        -- Boss dies: criterion flips to completed.
        scenarioCriteria[2].completed = true
        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals(2, _G.MDT_NPT.state.currentNextPull)
      end)

      it("does not fire boss advance when current pull has no boss", function()
        _G.MDT_NPT.state = makeState({ pull("next", 30), pull("upcoming", 30) }, 1)
        scenarioCriteria = {
          { quantity = 0, totalQuantity = 100, isWeightedProgress = true },
          { quantity = 0, totalQuantity = 1,   isWeightedProgress = false, completed = false },
        }
        Scenario.onScenarioForcesUpdate()
        scenarioCriteria[2].completed = true
        Scenario.onScenarioForcesUpdate()

        assert.equals("next", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals(1, _G.MDT_NPT.state.currentNextPull)
      end)

      it("consumes a pending boss kill when overflow from trash advances into the boss pull", function()
        -- User-reported "over percentage" case: trash + boss + more trash all die in
        -- one forces event. The boss criterion fires while currentNextPull still
        -- points at the first trash pull, so inline completion would be a no-op.
        -- The pending kill must carry forward and get consumed once the consume
        -- loop advances into the boss pull.
        _G.MDT_NPT.state = makeState({
          pull("next",     50), -- trash before boss
          bossPull("upcoming"), -- boss, 0 forces
          pull("upcoming", 30), -- trash after boss
        }, 1)
        scenarioCriteria = {
          { quantity = 0, totalQuantity = 100, isWeightedProgress = true },
          { quantity = 0, totalQuantity = 1,   isWeightedProgress = false, completed = false },
        }
        Scenario.onScenarioForcesUpdate() -- seed pass

        -- 80 raw forces delta: 50 → pull 1, boss criterion flips → pull 2, 30 → pull 3.
        -- dungeonMax=200, so quantity=40 → absolute forces = 40*(200/100)=80 via weighted branch.
        scenarioCriteria[1].quantity = 40
        scenarioCriteria[2].completed = true
        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals("completed", _G.MDT_NPT.state.pullStates[2].state)
        assert.equals("completed", _G.MDT_NPT.state.pullStates[3].state)
        assert.equals(0, _G.MDT_NPT.state.pendingBossKills)
      end)

      it("auto-completes an over-planned trash pull when scenario forces cap at 100%", function()
        -- Last trash before the last boss is often over-planned (more forces in
        -- the pull than are needed to reach dungeonMax). Once forces cap at 100%,
        -- Blizzard won't report further kills, so the pull can never complete
        -- via the delta path. The cap-advance pass must close it so the boss
        -- pull becomes NEXT.
        _G.MDT_NPT.state = makeState({
          pull("next",     300), -- over-planned: route has 300, dungeon only needs 200
          bossPull("upcoming"),
        }, 1)
        -- Reading maxes out at 100% of dungeonMax (200).
        scenarioCriteria = {
          { quantity = 100, totalQuantity = 100, isWeightedProgress = true },
        }

        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals("next",      _G.MDT_NPT.state.pullStates[2].state)
        assert.equals(2, _G.MDT_NPT.state.currentNextPull)
      end)

      it("cap-advance stops at the next boss pull without collapsing it", function()
        _G.MDT_NPT.state = makeState({
          pull("next",     300),
          bossPull("upcoming"),
          pull("upcoming", 50),  -- post-boss trash (unusual, but shouldn't be touched)
        }, 1)
        scenarioCriteria = {
          { quantity = 100, totalQuantity = 100, isWeightedProgress = true },
        }

        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        assert.equals("next",      _G.MDT_NPT.state.pullStates[2].state) -- boss untouched
        assert.equals("upcoming",  _G.MDT_NPT.state.pullStates[3].state)
        assert.equals(2, _G.MDT_NPT.state.currentNextPull)
      end)

      it("cap-advance is a no-op when current pull is already a boss pull", function()
        _G.MDT_NPT.state = makeState({
          { state = "completed", totalCount = 5, totalForces = 200, forcesKilled = 200,
            killedCount = 5, lastUpdate = 0 },
          bossPull("next"),
        }, 2)
        scenarioCriteria = {
          { quantity = 100, totalQuantity = 100, isWeightedProgress = true },
        }

        Scenario.onScenarioForcesUpdate()

        assert.equals("next", _G.MDT_NPT.state.pullStates[2].state)
        assert.equals(2, _G.MDT_NPT.state.currentNextPull)
      end)

      it("advances the boss pull before attributing coincident trash forces to the next pull", function()
        _G.MDT_NPT.state = makeState({ bossPull("next"), pull("upcoming", 30) }, 1)
        scenarioCriteria = {
          { quantity = 0, totalQuantity = 100, isWeightedProgress = true },
          { quantity = 0, totalQuantity = 1,   isWeightedProgress = false, completed = false },
        }
        -- Seed pass.
        Scenario.onScenarioForcesUpdate()

        -- Boss dies AND trash from the next pull dies in the same update.
        scenarioCriteria[1].quantity = 20 -- 20% of dungeonMax=200 → 40 absolute
        scenarioCriteria[2].completed = true
        Scenario.onScenarioForcesUpdate()

        assert.equals("completed", _G.MDT_NPT.state.pullStates[1].state)
        -- The 40 absolute delta should consume pull 2 (30) entirely.
        assert.equals("completed", _G.MDT_NPT.state.pullStates[2].state)
      end)
    end)
  end)
end)
