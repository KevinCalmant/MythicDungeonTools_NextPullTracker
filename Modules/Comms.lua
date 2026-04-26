local MDT_NPT = MDT_NPT
local PullState = MDT_NPT.PullState

local C_Timer, GetTime, Ambiguate, UnitName, IsInGroup =
  C_Timer, GetTime, Ambiguate, UnitName, IsInGroup
local GetSpecialization, GetSpecializationRole =
  GetSpecialization, GetSpecializationRole
local ipairs, type, tostring = ipairs, type, tostring

local PREFIX_MSG    = "MDTNPT"
local CHANNEL       = "PARTY"
local PROTO_VERSION = 1
local THROTTLE_SEC  = 0.5
local CHAT_PREFIX   = "|cFF00FF00MDT-NextPullTracker|r"

local Comms = {}
MDT_NPT.Comms = Comms

local AceComm       = LibStub and LibStub("AceComm-3.0", true)
local AceSerializer = LibStub and LibStub("AceSerializer-3.0", true)
local LibDeflate    = LibStub and LibStub("LibDeflate", true)

if AceComm then AceComm:Embed(Comms) end

local eventFrame = CreateFrame("Frame")
local commsActive = false
local lastBroadcastAt = 0
local pendingBroadcast = false
local playerName -- short ambiguated form, cached on Init
local warnedMismatches = {} -- key: "sender|presetUID" -> true

local PULL_STATE_VALID = {
  [PullState.COMPLETED] = true,
  [PullState.ACTIVE]    = true,
  [PullState.NEXT]      = true,
  [PullState.UPCOMING]  = true,
}

-- =====================================================================
-- Helpers
-- =====================================================================

local function libsAvailable()
  return AceComm and AceSerializer and LibDeflate
end

local function isPlayerTank()
  if not (GetSpecialization and GetSpecializationRole) then return false end
  local spec = GetSpecialization()
  if not spec then return false end
  return GetSpecializationRole(spec) == "TANK"
end

local function shortName(name)
  if not name then return nil end
  return Ambiguate(name, "short")
end

local function encode(payload)
  local serialized = AceSerializer:Serialize(payload)
  local compressed = LibDeflate:CompressDeflate(serialized, { level = 3 })
  return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

local function decode(message)
  local compressed = LibDeflate:DecodeForWoWAddonChannel(message)
  if not compressed then return nil end
  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then return nil end
  local ok, payload = AceSerializer:Deserialize(serialized)
  if not ok then return nil end
  return payload
end

-- =====================================================================
-- Role resolution
-- =====================================================================

function Comms:ResolveRole()
  local state = MDT_NPT.state
  if not state or not state.active then return "off" end

  local db = MDT_NPT:GetDB()
  local setting = (db and db.sync and db.sync.authority) or "auto"
  local role

  if setting == "lead" or setting == "follow" or setting == "off" then
    role = setting
  else -- "auto" or unknown
    if not IsInGroup() then
      role = "off"
    elseif isPlayerTank() then
      role = "lead"
    else
      -- Auto non-tank: stay "off" until a leader broadcast arrives, at which
      -- point OnCommReceived promotes us to "follow". This lets followers
      -- resume local tracking automatically when the leader stops.
      role = "off"
    end
  end

  state.role = role
  state.authoritative = (role == "lead")
  return role
end

-- =====================================================================
-- Outbound (leader)
-- =====================================================================

local function buildStatePayload(state)
  return {
    v   = PROTO_VERSION,
    t   = "state",
    uid = state.presetUID,
    cur = state.currentNextPull,
    lf  = state.lastForces or 0,
    ps  = state.pullStates,
  }
end

local function sendNow(state)
  if not libsAvailable() then return end
  if not IsInGroup() then return end

  local encoded = encode(buildStatePayload(state))
  if not encoded then return end
  Comms:SendCommMessage(PREFIX_MSG, encoded, CHANNEL, nil, "NORMAL")
  lastBroadcastAt = GetTime()
end

function Comms:BroadcastState()
  local state = MDT_NPT.state
  if not state or not state.active then return end
  if state.role ~= "lead" then return end

  local now = GetTime()
  local elapsed = now - lastBroadcastAt
  if elapsed >= THROTTLE_SEC then
    sendNow(state)
    return
  end

  if pendingBroadcast then return end
  pendingBroadcast = true
  C_Timer.After(THROTTLE_SEC - elapsed, function()
    pendingBroadcast = false
    local s = MDT_NPT.state
    if s and s.active and s.role == "lead" then sendNow(s) end
  end)
end

local function sendStop()
  if not libsAvailable() then return end
  if not IsInGroup() then return end
  local encoded = encode({ v = PROTO_VERSION, t = "stop" })
  if not encoded then return end
  Comms:SendCommMessage(PREFIX_MSG, encoded, CHANNEL, nil, "NORMAL")
end

-- =====================================================================
-- Inbound (follower)
-- =====================================================================

local function isValidStatePayload(p)
  if type(p) ~= "table" then return false end
  if p.v ~= PROTO_VERSION then return false end
  if p.t ~= "state" then return false end
  if type(p.uid) ~= "string" then return false end
  if type(p.ps) ~= "table" then return false end
  if p.cur ~= nil and type(p.cur) ~= "number" then return false end
  for _, ps in ipairs(p.ps) do
    if type(ps) ~= "table" or not PULL_STATE_VALID[ps.state] then
      return false
    end
  end
  return true
end

function Comms:ApplyState(payload)
  local state = MDT_NPT.state
  if not state or not state.active then return end

  state.pullStates     = payload.ps
  state.currentNextPull = payload.cur
  state.lastForces     = payload.lf or state.lastForces or 0
  state.lastSyncTime   = GetTime()
  MDT_NPT:UpdateAll()
end

local function warnPresetMismatch(senderShort, leaderUID)
  local key = (senderShort or "?").."|"..(leaderUID or "?")
  if warnedMismatches[key] then return end
  warnedMismatches[key] = true
  print(CHAT_PREFIX..": "..senderShort.." is broadcasting a different MDT preset (uid "
    ..tostring(leaderUID).."). Switch to the same preset to follow them.")
end

function Comms:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= PREFIX_MSG then return end
  if not commsActive then return end

  local senderShort = shortName(sender)
  if senderShort == playerName then return end

  local payload = decode(message)
  if type(payload) ~= "table" or payload.v ~= PROTO_VERSION then return end

  if payload.t == "stop" then
    local state = MDT_NPT.state
    if state and state.active and state.role == "follow" then
      Comms:ResolveRole()
      MDT_NPT:UpdateAll()
    end
    return
  end

  if not isValidStatePayload(payload) then return end

  -- Receiving a state broadcast means someone is acting as leader.
  -- Promote ourselves to follower if our local setting allows it.
  local state = MDT_NPT.state
  if not state or not state.active then return end
  if state.role == "lead" then return end -- our own broadcasts win locally
  if state.role ~= "follow" then
    -- state.role == "off" — only auto-promote if the user's setting is "auto".
    -- Explicit "off" stays off; explicit "lead" was rejected above.
    local db = MDT_NPT:GetDB()
    local setting = (db and db.sync and db.sync.authority) or "auto"
    if setting ~= "auto" then return end
    state.role = "follow"
    state.authoritative = false
  end

  if state.presetUID ~= payload.uid then
    warnPresetMismatch(senderShort, payload.uid)
    return
  end

  Comms:ApplyState(payload)
end

-- =====================================================================
-- Lifecycle
-- =====================================================================

local function onEvent(_, event)
  if event == "GROUP_ROSTER_UPDATE" then
    warnedMismatches = {}
    Comms:ResolveRole()
    if MDT_NPT.state and MDT_NPT.state.role == "lead" then
      sendNow(MDT_NPT.state) -- push current state to any newly-joined member
    end
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    Comms:ResolveRole()
  end
end

function Comms:Init()
  if not libsAvailable() then
    print(CHAT_PREFIX..": party sync unavailable (Ace libraries not loaded).")
    return
  end
  if commsActive then return end
  commsActive = true
  warnedMismatches = {}
  playerName = shortName(UnitName("player"))
  Comms:RegisterComm(PREFIX_MSG)
  eventFrame:SetScript("OnEvent", onEvent)
  eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
  eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  Comms:ResolveRole()
end

function Comms:Shutdown()
  if not commsActive then return end
  if MDT_NPT.state and MDT_NPT.state.role == "lead" then
    sendStop()
  end
  commsActive = false
  pendingBroadcast = false
  warnedMismatches = {}
  if AceComm and AceComm.UnregisterComm then
    Comms:UnregisterComm(PREFIX_MSG)
  end
  eventFrame:UnregisterAllEvents()
  eventFrame:SetScript("OnEvent", nil)
end

-- =====================================================================
-- Test seam
-- =====================================================================

Comms._test = {
  encode = encode,
  decode = decode,
  buildStatePayload = buildStatePayload,
  isValidStatePayload = isValidStatePayload,
  PROTO_VERSION = PROTO_VERSION,
}
