local mocks = require("wow_mocks")

describe("Wow.lua", function()
  before_each(function()
    mocks.reset()
  end)

  it("reads the player role through the WoW 12.1 specialization namespace", function()
    _G.C_SpecializationInfo = {
      GetSpecialization = function() return 2 end,
      GetSpecializationInfo = function(index)
        assert.equals(2, index)
        return 104, "Guardian", nil, nil, "TANK"
      end,
    }
    mocks.loadSource("Utils/Wow.lua")
    assert.equals("TANK", _G.MDT_NPT.Wow.getPlayerRole())
  end)

  it("keeps the legacy specialization fallback", function()
    _G.GetSpecialization = function() return 3 end
    _G.GetSpecializationRole = function(index)
      assert.equals(3, index)
      return "HEALER"
    end
    mocks.loadSource("Utils/Wow.lua")
    assert.equals("HEALER", _G.MDT_NPT.Wow.getPlayerRole())
  end)

  it("returns nil safely when specialization data is unavailable", function()
    mocks.loadSource("Utils/Wow.lua")
    assert.is_nil(_G.MDT_NPT.Wow.getPlayerRole())
  end)
end)
