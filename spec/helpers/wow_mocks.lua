-- Minimal stubs for the slice of the WoW runtime + parent-MDT surface that the
-- pure-Lua child-addon modules (State, Scenario, API, BeaconState) actually touch.
-- Extend as more modules come under test.

local M = {}

local function installGlobals()
  _G.GetTime = function() return 0 end

  _G.MDT = {
    dungeonEnemies = {},
    dungeonTotalCount = {},
    -- L[key] returns the key itself so assertions can compare on English text
    L = setmetatable({}, { __index = function(_, k) return k end }),
  }
  function _G.MDT:GetDB()     return { currentDungeonIdx = 1 } end
  function _G.MDT:GetDBChar() return {} end

  -- Matches init.lua's shape so Modules/*.lua files capture the same fields.
  _G.MDT_NPT = {
    -- L[key] returns the key itself so render tests can assert on English strings.
    L = setmetatable({}, { __index = function(_, k) return k end }),
    PullState = {
      COMPLETED = "completed",
      ACTIVE    = "active",
      NEXT      = "next",
      UPCOMING  = "upcoming",
    },
  }
end

---Fresh mock state. Call in `before_each` so every test starts from a known baseline.
function M.reset()
  installGlobals()
end

---Executes a child-addon source file (repo-relative path) in the current globals.
---Re-executing is cheap and gives tests a fresh MDT_NPT.<Module> each call.
function M.loadSource(relPath)
  local chunk, err = loadfile(relPath)
  assert(chunk, err)
  return chunk()
end

return M
