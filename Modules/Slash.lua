local MDT_NPT = MDT_NPT

local PREFIX       = "|cFF00FF00MDT-NextPullTracker|r"
local CMD_COLOR    = "|cff00ff7f"
local LABEL_COLOR  = "|cffffd100"
local DIM          = "|cff808080"

-- Command metadata — source of truth for dispatch AND help output.
-- Adding a new command: append an entry here with { name, usage, help, handler }.
-- Dispatch runs by matching `name` against the first whitespace-delimited token
-- of the slash args; the rest of the string is passed to `handler(rest)`.
local commands = {}

local function printHelp()
  print(PREFIX.." commands:")
  for _, c in ipairs(commands) do
    local usage = CMD_COLOR.."/npt "..c.usage.."|r"
    print("  "..usage.." "..DIM.."—|r "..c.help)
  end
end

local function commandByName(name)
  for _, c in ipairs(commands) do
    if c.name == name then return c end
  end
  return nil
end

-- ============ handlers ============

local function handleStart()
  MDT_NPT:Start(true)
end

local function handleStop()
  MDT_NPT:Stop()
end

local function handleStatus()
  if not MDT_NPT:IsActive() then
    print(PREFIX..": tracking is not active.")
    return
  end
  local idx = MDT_NPT:GetCurrentNextPull()
  if not idx then
    print(PREFIX..": route complete.")
    return
  end
  local ps = MDT_NPT:GetPullStateData(idx)
  print(PREFIX..": "..LABEL_COLOR.."pull #"..idx.."|r "
    ..DIM.."("..ps.state..")|r "
    ..LABEL_COLOR.."mobs|r "..ps.killedCount.."/"..ps.totalCount.." "
    ..LABEL_COLOR.."forces|r "..ps.forcesKilled.."/"..ps.totalForces)
end

local function handleShow()
  if not (MDT_NPT.Beacon and MDT_NPT.Beacon.Update) then
    print(PREFIX..": beacon module not loaded.")
    return
  end
  -- Right-click "Hide Beacon" persists db.beacon.enabled = false; flip it back on
  -- so Beacon:Update() no longer short-circuits and the HUD can appear again.
  local db = MDT_NPT.GetDB and MDT_NPT:GetDB()
  if db and db.beacon then db.beacon.enabled = true end
  MDT_NPT.Beacon:Update()
end

local function handleHide()
  if not (MDT_NPT.Beacon and MDT_NPT.Beacon.Hide) then return end
  local db = MDT_NPT.GetDB and MDT_NPT:GetDB()
  if db and db.beacon then db.beacon.enabled = false end
  MDT_NPT.Beacon:Hide()
end

local function handleSkip(rest)
  local n = tonumber(rest)
  if not n then
    print(PREFIX..": "..CMD_COLOR.."/npt skip <N>|r requires a pull number.")
    return
  end
  if not MDT_NPT:IsActive() then
    print(PREFIX..": tracking is not active; run "..CMD_COLOR.."/npt start|r first.")
    return
  end
  MDT_NPT:SkipTo(n)
  print(PREFIX..": skipped to pull "..n..".")
end

local function handleComplete()
  if not MDT_NPT:IsActive() then
    print(PREFIX..": tracking is not active.")
    return
  end
  local state = MDT_NPT.state
  for i, ps in ipairs(state.pullStates) do
    if ps.state == "active" or ps.state == "next" then
      MDT_NPT:MarkComplete(i)
      print(PREFIX..": marked pull "..i.." complete.")
      return
    end
  end
  print(PREFIX..": no active/next pull to complete.")
end

local function handleRevert()
  if not MDT_NPT:IsActive() then
    print(PREFIX..": tracking is not active.")
    return
  end
  local idx = MDT_NPT:GetCurrentNextPull()
  local target = idx and (idx - 1) or nil
  if not target or target < 1 then
    print(PREFIX..": nothing to revert.")
    return
  end
  MDT_NPT:MarkIncomplete(target)
  print(PREFIX..": reverted pull "..target..".")
end

local function handleTest()
  if MDT_NPT.test and MDT_NPT.test.RunAllTests then
    MDT_NPT.test:RunAllTests()
  else
    print(PREFIX..": test harness not loaded.")
  end
end

-- ============ command table ============

commands = {
  { name = "start",    usage = "start",       help = "begin tracking the current MDT preset",             handler = handleStart },
  { name = "stop",     usage = "stop",        help = "stop tracking and clear tracking state",            handler = handleStop },
  { name = "status",   usage = "status",      help = "print the current pull's state and forces",         handler = handleStatus },
  { name = "skip",     usage = "skip <N>",    help = "jump directly to pull N (marks prior pulls done)",  handler = handleSkip },
  { name = "complete", usage = "complete",    help = "mark the current active/next pull as complete",     handler = handleComplete },
  { name = "revert",   usage = "revert",      help = "undo the most recent pull completion",              handler = handleRevert },
  { name = "show",     usage = "show",        help = "enable and show the beacon HUD",                    handler = handleShow },
  { name = "hide",     usage = "hide",        help = "disable and hide the beacon HUD",                   handler = handleHide },
  { name = "test",     usage = "test",        help = "run the integration test suite",                    handler = handleTest },
  { name = "help",     usage = "help",        help = "show this help message",                            handler = printHelp },
}

function MDT_NPT:Slash(args)
  args = args or ""
  local cmd, rest = args:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  local command = commandByName(cmd)
  if command then
    command.handler(rest)
  else
    printHelp()
  end
end

SLASH_MDTNPT1 = "/npt"
SlashCmdList["MDTNPT"] = function(msg) MDT_NPT:Slash(msg or "") end
