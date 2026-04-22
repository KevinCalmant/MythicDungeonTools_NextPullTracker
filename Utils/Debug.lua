local MDT_NPT = MDT_NPT

---@class DebugChannel
---@field print fun(msg: any)
---@field setEnabled fun(enabled: boolean)
---@field isEnabled fun(): boolean

---Creates a tagged debug printer. Prints only while `enabled` is true.
---@param name string channel tag shown in the chat prefix
---@param enabled boolean initial on/off state
---@return DebugChannel
local function make(name, enabled)
  local channel = { enabled = enabled and true or false }

  function channel.print(msg)
    if channel.enabled then
      print("|cFF00FF00MDT-"..name.."|r: "..tostring(msg))
    end
  end

  function channel.setEnabled(value)
    channel.enabled = value and true or false
  end

  function channel.isEnabled()
    return channel.enabled
  end

  return channel
end

MDT_NPT.Debug = {
  make = make,
}
