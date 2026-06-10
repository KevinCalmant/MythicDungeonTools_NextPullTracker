local mocks = require("wow_mocks")

describe("Pace.lua", function()
  local Pace

  before_each(function()
    mocks.reset()
    mocks.loadSource("Modules/Pace.lua")
    Pace = _G.MDT_NPT.Pace
  end)

  describe("compute", function()
    it("returns nil when any input is missing", function()
      assert.is_nil(Pace.compute(nil, 100, 1800))
      assert.is_nil(Pace.compute(50, nil, 1800))
      assert.is_nil(Pace.compute(50, 100, nil))
    end)

    it("returns nil for a non-positive time limit", function()
      assert.is_nil(Pace.compute(50, 100, 0))
      assert.is_nil(Pace.compute(50, 100, -1))
    end)

    it("is zero when forces% matches elapsed/timeLimit", function()
      assert.equals(0, Pace.compute(50, 900, 1800))
    end)

    it("is positive (ahead) when forces% outruns the clock", function()
      -- 50% of an 1800s key 'deserves' 900s; only 800s spent => 100s ahead
      assert.equals(100, Pace.compute(50, 800, 1800))
    end)

    it("is negative (behind) when the clock outruns forces%", function()
      -- 25% deserves 450s; 600s spent => 150s behind
      assert.equals(-150, Pace.compute(25, 600, 1800))
    end)

    it("equals -elapsed at zero forces", function()
      assert.equals(-30, Pace.compute(0, 30, 1800))
    end)
  end)

  describe("format", function()
    it("renders an ahead pace with a plus sign", function()
      assert.equals("+1:40", Pace.format(100))
    end)

    it("renders a behind pace with a minus sign", function()
      assert.equals("-2:30", Pace.format(-150))
    end)

    it("renders zero as +0:00", function()
      assert.equals("+0:00", Pace.format(0))
    end)

    it("zero-pads seconds and rounds to the nearest second", function()
      assert.equals("-0:05", Pace.format(-4.6))
      assert.equals("+1:40", Pace.format(99.7))
    end)

    it("handles paces over ten minutes", function()
      assert.equals("+12:05", Pace.format(725))
    end)
  end)
end)
