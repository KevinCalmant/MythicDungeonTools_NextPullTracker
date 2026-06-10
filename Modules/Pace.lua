local MDT_NPT = MDT_NPT

local math_floor, math_abs = math.floor, math.abs
local string_format = string.format

---Even-pace baseline: at elapsed time t you are "on pace" when the forces
---percentage equals t / timeLimit. Returns the lead (positive) or deficit
---(negative) in seconds against that baseline, or nil when any input is
---missing. Bosses contribute time but no forces, so expect the readout to dip
---during and right after boss fights — it converges as trash is consumed.
local function compute(forcesPct, elapsed, timeLimit)
  if not forcesPct or not elapsed or not timeLimit or timeLimit <= 0 then return nil end
  return (forcesPct / 100) * timeLimit - elapsed
end

---Formats pace seconds as "+m:ss" / "-m:ss"; the sign is always shown.
local function format(seconds)
  local sign = seconds < 0 and "-" or "+"
  local absSeconds = math_floor(math_abs(seconds) + 0.5)
  return string_format("%s%d:%02d", sign, math_floor(absSeconds / 60), absSeconds % 60)
end

MDT_NPT.Pace = {
  compute = compute,
  format = format,
}
