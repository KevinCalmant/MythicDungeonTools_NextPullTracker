local AddonName, MDT_NPT = ...
_G["MDT_NPT"] = MDT_NPT
MDT_NPT.L = {}

MDT_NPT.PullState = {
  COMPLETED = "completed",
  ACTIVE    = "active",
  NEXT      = "next",
  UPCOMING  = "upcoming",
}
