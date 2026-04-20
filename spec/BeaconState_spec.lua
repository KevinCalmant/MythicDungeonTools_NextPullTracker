local mocks = require("wow_mocks")

describe("BeaconState.lua", function()
  local function validState()
    return {
      anchorFrom = "TOP",
      anchorTo   = "TOP",
      xoffset    = 0,
      yoffset    = -50,
      scale      = 1.0,
      locked     = false,
    }
  end

  local function withGlobalDB(beacon)
    function _G.MDT_NPT:GetDB()
      return { beaconScope = "global", beacon = beacon }
    end
  end

  before_each(function()
    mocks.reset()
    -- Core.lua provides GetDB/GetDBChar on MDT_NPT; stub them for test isolation
    function _G.MDT_NPT:GetDB()     return {} end
    function _G.MDT_NPT:GetDBChar() return {} end
    -- Current BeaconState.lua still calls MDT:GetDBChar() for the "char" scope
    function _G.MDT:GetDBChar()     return {} end
    mocks.loadSource("Modules/BeaconState.lua")
  end)

  describe("GetBeaconState (sanitizer via public API)", function()
    it("returns a valid state unchanged", function()
      local input = validState()
      withGlobalDB(input)
      local result = _G.MDT_NPT:GetBeaconState()
      assert.equals("TOP", result.anchorFrom)
      assert.equals("TOP", result.anchorTo)
      assert.equals(0,    result.xoffset)
      assert.equals(-50,  result.yoffset)
      assert.equals(1.0,  result.scale)
      assert.equals(false, result.locked)
    end)

    it("repairs non-string anchorFrom to default TOP", function()
      local bad = validState(); bad.anchorFrom = 42
      withGlobalDB(bad)
      assert.equals("TOP", _G.MDT_NPT:GetBeaconState().anchorFrom)
    end)

    it("repairs invalid anchor string to default TOP", function()
      local bad = validState(); bad.anchorFrom = "NOTANANCHOR"
      withGlobalDB(bad)
      assert.equals("TOP", _G.MDT_NPT:GetBeaconState().anchorFrom)
    end)

    it("accepts every valid anchor enum", function()
      local beacon = validState()
      withGlobalDB(beacon)
      local anchors = { "TOP", "BOTTOM", "LEFT", "RIGHT",
                        "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER" }
      for _, anchor in ipairs(anchors) do
        beacon.anchorFrom = anchor
        beacon.anchorTo   = anchor
        local result = _G.MDT_NPT:GetBeaconState()
        assert.equals(anchor, result.anchorFrom)
        assert.equals(anchor, result.anchorTo)
      end
    end)

    it("repairs non-number xoffset to 0", function()
      local bad = validState(); bad.xoffset = "not-a-number"
      withGlobalDB(bad)
      assert.equals(0, _G.MDT_NPT:GetBeaconState().xoffset)
    end)

    it("repairs non-number yoffset to -50", function()
      local bad = validState(); bad.yoffset = {}
      withGlobalDB(bad)
      assert.equals(-50, _G.MDT_NPT:GetBeaconState().yoffset)
    end)

    it("repairs out-of-range scale (too large) to 1.0", function()
      local bad = validState(); bad.scale = 10
      withGlobalDB(bad)
      assert.equals(1.0, _G.MDT_NPT:GetBeaconState().scale)
    end)

    it("repairs out-of-range scale (too small) to 1.0", function()
      local bad = validState(); bad.scale = 0.1
      withGlobalDB(bad)
      assert.equals(1.0, _G.MDT_NPT:GetBeaconState().scale)
    end)

    it("accepts scale at the boundaries (0.5 and 2.0)", function()
      local beacon = validState()
      withGlobalDB(beacon)
      beacon.scale = 0.5
      assert.equals(0.5, _G.MDT_NPT:GetBeaconState().scale)
      beacon.scale = 2.0
      assert.equals(2.0, _G.MDT_NPT:GetBeaconState().scale)
    end)

    it("repairs non-boolean locked to false", function()
      local bad = validState(); bad.locked = "yes"
      withGlobalDB(bad)
      assert.equals(false, _G.MDT_NPT:GetBeaconState().locked)
    end)

    it("repairs all six fields when every one is invalid", function()
      withGlobalDB({
        anchorFrom = 1,
        anchorTo   = nil,
        xoffset    = "a",
        yoffset    = {},
        scale      = -5,
        locked     = 1,
      })
      local result = _G.MDT_NPT:GetBeaconState()
      assert.equals("TOP", result.anchorFrom)
      assert.equals("TOP", result.anchorTo)
      assert.equals(0,     result.xoffset)
      assert.equals(-50,   result.yoffset)
      assert.equals(1.0,   result.scale)
      assert.equals(false, result.locked)
    end)

    it("returns the char DB beacon table when scope is 'char'", function()
      local charBeacon = validState(); charBeacon.xoffset = 100
      function _G.MDT_NPT:GetDB()
        return { beaconScope = "char", beacon = validState() }
      end
      function _G.MDT:GetDBChar() return { beacon = charBeacon } end

      local result = _G.MDT_NPT:GetBeaconState()
      assert.equals(100, result.xoffset)
    end)

    it("falls back to db.beacon when char DB is unavailable in 'char' scope", function()
      local globalBeacon = validState(); globalBeacon.xoffset = 200
      function _G.MDT_NPT:GetDB()
        return { beaconScope = "char", beacon = globalBeacon }
      end
      function _G.MDT:GetDBChar() return nil end

      local result = _G.MDT_NPT:GetBeaconState()
      assert.equals(200, result.xoffset)
    end)

    it("returns nil when GetDB returns nil", function()
      function _G.MDT_NPT:GetDB() return nil end
      assert.is_nil(_G.MDT_NPT:GetBeaconState())
    end)
  end)
end)
