local mocks = require("wow_mocks")

describe("State.lua", function()
  local State

  before_each(function()
    mocks.reset()
    mocks.loadSource("Modules/State.lua")
    State = _G.MDT_NPT.State
  end)

  describe("buildStateFromPreset", function()
    it("returns nil when the preset has no pulls", function()
      _G.MDT.dungeonEnemies[1] = {}
      local preset = { value = { pulls = {}, currentDungeonIdx = 1 } }
      assert.is_nil(State.buildStateFromPreset(preset))
    end)

    it("returns nil when dungeon enemy data is missing", function()
      local preset = { value = { pulls = { [1] = {} }, currentDungeonIdx = 42 } }
      assert.is_nil(State.buildStateFromPreset(preset))
    end)

    it("marks first pull NEXT, rest UPCOMING, currentNextPull=1", function()
      _G.MDT.dungeonEnemies[1] = {
        [1] = { id = 101, count = 5, clones = { {}, {}, {} } },
      }
      local preset = {
        value = {
          pulls = {
            [1] = { [1] = { 1, 2 } },
            [2] = { [1] = { 3 } },
          },
          currentDungeonIdx = 1,
        },
      }
      local state = State.buildStateFromPreset(preset)
      assert.is_not_nil(state)
      assert.equals("next",     state.pullStates[1].state)
      assert.equals("upcoming", state.pullStates[2].state)
      assert.equals(1, state.currentNextPull)
    end)

    it("computes totalCount and totalForces from clone lists", function()
      _G.MDT.dungeonEnemies[1] = {
        [1] = { id = 101, count = 5, clones = { {}, {}, {} } },
      }
      local preset = {
        value = {
          pulls = { [1] = { [1] = { 1, 2 } } }, -- 2 clones × 5 count = 10 forces
          currentDungeonIdx = 1,
        },
      }
      local state = State.buildStateFromPreset(preset)
      assert.equals(2,  state.pullStates[1].totalCount)
      assert.equals(10, state.pullStates[1].totalForces)
    end)

    it("flags hasBoss when any enemy in the pull has isBoss", function()
      _G.MDT.dungeonEnemies[1] = {
        [1] = { id = 101, count = 5, clones = { {} } },
        [2] = { id = 202, count = 0, clones = { {} }, isBoss = true },
      }
      local preset = {
        value = {
          pulls = {
            [1] = { [1] = { 1 } },          -- trash only
            [2] = { [2] = { 1 } },          -- boss only
            [3] = { [1] = { 1 }, [2] = { 1 } }, -- mixed
          },
          currentDungeonIdx = 1,
        },
      }
      local state = State.buildStateFromPreset(preset)
      assert.is_false(state.pullStates[1].hasBoss)
      assert.is_true(state.pullStates[2].hasBoss)
      assert.is_true(state.pullStates[3].hasBoss)
    end)

    it("falls back to MDT:GetDB().currentDungeonIdx when preset omits it", function()
      _G.MDT.dungeonEnemies[1] = {
        [1] = { id = 101, count = 1, clones = { {} } },
      }
      local preset = { value = { pulls = { [1] = { [1] = { 1 } } } } }
      local state = State.buildStateFromPreset(preset)
      assert.is_not_nil(state)
      assert.equals(1, state.dungeonIndex)
    end)
  end)

  describe("recomputeNextPull", function()
    local function makeState(pullStates, currentNextPull)
      return { pullStates = pullStates, currentNextPull = currentNextPull }
    end

    it("promotes the lowest non-completed, non-active pull to NEXT", function()
      local state = makeState({
        { state = "completed" },
        { state = "completed" },
        { state = "upcoming" },
        { state = "upcoming" },
      }, 3)
      State.recomputeNextPull(state)
      assert.equals("next", state.pullStates[3].state)
      assert.equals(3,      state.currentNextPull)
    end)

    it("leaves currentNextPull nil when all pulls are completed", function()
      local state = makeState({
        { state = "completed" },
        { state = "completed" },
      }, 2)
      State.recomputeNextPull(state)
      assert.is_nil(state.currentNextPull)
    end)

    it("skips ACTIVE pulls when picking NEXT", function()
      local state = makeState({
        { state = "completed" },
        { state = "active" },
        { state = "upcoming" },
      }, nil)
      State.recomputeNextPull(state)
      assert.equals("active", state.pullStates[2].state) -- untouched
      assert.equals("next",   state.pullStates[3].state)
      assert.equals(3,        state.currentNextPull)
    end)

    it("clears duplicate NEXT markers and promotes a single one", function()
      local state = makeState({
        { state = "next" },
        { state = "next" }, -- stale duplicate
        { state = "upcoming" },
      }, 1)
      State.recomputeNextPull(state)
      assert.equals("next",     state.pullStates[1].state)
      assert.equals("upcoming", state.pullStates[2].state) -- downgraded
      assert.equals("upcoming", state.pullStates[3].state)
      assert.equals(1, state.currentNextPull)
    end)

    it("returns true when currentNextPull moved, false otherwise", function()
      local state = makeState({
        { state = "upcoming" },
        { state = "upcoming" },
      }, 1)
      assert.is_false(State.recomputeNextPull(state))

      state.pullStates[1].state = "completed"
      assert.is_true(State.recomputeNextPull(state))
      assert.equals(2, state.currentNextPull)
    end)
  end)
end)
