local MDT_NPT = MDT_NPT

local Beacon = {}
MDT_NPT.Beacon = Beacon

function Beacon:Show()
  self.frame = self.frame or MDT_NPT.BeaconFrame.create()
  self.frame:Show()
end

function Beacon:Hide()
  if self.frame then self.frame:Hide() end
end

function Beacon:GetFrame()
  self.frame = self.frame or MDT_NPT.BeaconFrame.create()
  return self.frame
end
