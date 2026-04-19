local MDT_NPT = MDT_NPT

local function parseNum(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then
    local n = tonumber(value:match("(%d+%.?%d*)"))
    return n or 0
  end
  return 0
end

MDT_NPT.Utils = {
  parseNum = parseNum,
}
