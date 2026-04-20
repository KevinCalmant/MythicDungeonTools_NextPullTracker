local MDT_NPT = MDT_NPT

local select = select

---Gets scenario step info, trying both legacy C_Scenario and modern C_ScenarioInfo APIs
local function getScenarioStepInfo()
  -- Modern API (WoW 10.0+)
  if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
    local info = C_ScenarioInfo.GetScenarioStepInfo()
    if info then return info.numCriteria or 0 end
  end
  -- Legacy API fallback: will be used if this addon is port to classic versions of the game.
  if C_Scenario and C_Scenario.GetStepInfo then
    return select(3, C_Scenario.GetStepInfo()) or 0
  end
  return 0
end

---Gets criteria info, trying modern then legacy APIs
local function getScenarioCriteriaInfo(index)
  -- Modern API (WoW 10.0+)
  if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
    return C_ScenarioInfo.GetCriteriaInfo(index)
  end
  -- Legacy API fallback: will be used if this addon is port to classic versions of the game.
  if C_Scenario and C_Scenario.GetCriteriaInfo then
    return C_Scenario.GetCriteriaInfo(index)
  end
  return nil
end

---Dumps all scenario criteria to chat for debugging
local function dumpScenarioInfo()
  print("|cFF00FF00MDT|r: C_Scenario available = "..tostring(C_Scenario ~= nil))
  print("|cFF00FF00MDT|r: C_ScenarioInfo available = "..tostring(C_ScenarioInfo ~= nil))

  -- Try legacy API
  if C_Scenario and C_Scenario.GetStepInfo then
    local stepName, _, numCriteria = C_Scenario.GetStepInfo()
    print("Legacy C_Scenario.GetStepInfo: step = '"..tostring(stepName).."', numCriteria = "..tostring(numCriteria))
  end

  -- Try modern API
  if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
    local info = C_ScenarioInfo.GetScenarioStepInfo()
    if info then
      print("Modern C_ScenarioInfo.GetScenarioStepInfo: title = '"..tostring(info.title)..
        "', numCriteria = "..tostring(info.numCriteria))
    else
      print("Modern C_ScenarioInfo.GetScenarioStepInfo: nil (not in scenario?)")
    end
  end

  -- Print scenario overall info
  if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
    local scenario = C_ScenarioInfo.GetScenarioInfo()
    if scenario then
      print("Scenario: '"..tostring(scenario.name).."', stage "..
        tostring(scenario.currentStage).."/"..tostring(scenario.numStages))
    end
  end

  local numCriteria = getScenarioStepInfo()
  print("Using numCriteria = "..tostring(numCriteria))
  for i = 1, numCriteria do
    local info = getScenarioCriteriaInfo(i)
    if info then
      print(string.format("  [%d] %s | q=%s/%s | isWP=%s | completed=%s",
        i, tostring(info.description), tostring(info.quantity),
        tostring(info.totalQuantity), tostring(info.isWeightedProgress),
        tostring(info.completed)))
    end
  end
end

MDT_NPT.Wow = {
  getScenarioStepInfo = getScenarioStepInfo,
  getScenarioCriteriaInfo = getScenarioCriteriaInfo,
  dumpScenarioInfo = dumpScenarioInfo,
}
