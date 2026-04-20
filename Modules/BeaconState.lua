local MDT = MDT
local MDT_NPT = MDT_NPT
local pairs, type, print = pairs, type, print

-- Persisted-per-scope fields (spec §6.1). Feature toggles (enabled/showUpcoming/...) are
-- always account-wide and stay in db.global.beacon regardless of scope.
local BEACON_STATE_DEFAULTS = {
  anchorFrom = "TOP",
  anchorTo = "TOP",
  xoffset = 0,
  yoffset = -50,
  scale = 1.0,
  locked = false,
}

local VALID_ANCHORS = {
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
  CENTER = true,
}

local SCALE_MIN, SCALE_MAX = 0.5, 2.0

local BEACON_STATE_SCHEMA = {
  anchorFrom = { type = "string", check = function(v) return VALID_ANCHORS[v] end },
  anchorTo   = { type = "string", check = function(v) return VALID_ANCHORS[v] end },
  xoffset    = { type = "number" },
  yoffset    = { type = "number" },
  scale      = { type = "number", check = function(v) return v >= SCALE_MIN and v <= SCALE_MAX end },
  locked     = { type = "boolean" },
}

local corruptionWarned = false
local function sanitizeBeaconState(state)
  if type(state) ~= "table" then return end
  local fixed = false
  for key, rule in pairs(BEACON_STATE_SCHEMA) do
    local v = state[key]
    if type(v) ~= rule.type or (rule.check and not rule.check(v)) then
      state[key] = BEACON_STATE_DEFAULTS[key]
      fixed = true
    end
  end
  if fixed and not corruptionWarned then
    corruptionWarned = true
    print("|cff00ff00[MDT]|r Beacon saved state had invalid fields; defaults restored.")
  end
end

local db

---Returns the beacon position/scale/lock table for the current scope.
---Only the six persisted fields (spec §6.1) live in this table. Feature
---toggles like `enabled`/`showUpcoming` remain on db.global.beacon.
function MDT_NPT:GetBeaconState()
  db = db or MDT_NPT:GetDB()
  if not db then return nil end

  local scope = db.beaconScope or "char"
  local state
  if scope == "global" then
    state = db.beacon
  else
    local charDB = MDT:GetDBChar()
    if not charDB then
      -- fallback if char DB unavailable
      state = db.beacon
    else
      charDB.beacon = charDB.beacon or {}
      state = charDB.beacon
    end
  end
  sanitizeBeaconState(state)
  return state
end
