local MDT_NPT = MDT_NPT
local Wow = MDT_NPT.Wow

---Reads the current enemy forces from the scenario API, converted to absolute count.
---Scenario APIs report forces either as weighted percent (q=42, tq=100) or raw count
---(q=42, tq=460). Both are converted to the same absolute-count scale the preset pulls
---use, via (quantity / totalQuantity) * dungeonMax. Returns nil if we can't resolve a
---dungeon total — feeding raw percent into the consume loop stalls pull advancement.
local function getScenarioCurrentForces()
  local numCriteria = Wow.getScenarioStepInfo()
end
