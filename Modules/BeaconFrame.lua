local MDT = MDT
local MDT_NPT = MDT_NPT
local L = MDT_NPT.L

local Beacon = MDT_NPT.Beacon
local Minimap = MDT_NPT.BeaconMinimap
local PullState = MDT_NPT.PullState
local pairs, ipairs, unpack, string_format, tonumber = pairs, ipairs, unpack, string.format, tonumber

---Builds the Beacon's UI frame and all its child widgets. Caller owns the returned frame.
local function create()
  local db = MDT_NPT:GetDB()

  -- === Beacon Frame ===
  local beaconFrame = CreateFrame("Frame", "MDTNextPullBeaconFrame", UIParent)
  beaconFrame:SetSize(360, 170)
  beaconFrame:SetFrameStrata("MEDIUM")
  beaconFrame:SetClampedToScreen(true)
  beaconFrame:SetMovable(true)
  beaconFrame:EnableMouse(true)
  beaconFrame:RegisterForDrag("LeftButton")

  local anchor = MDT_NPT:GetBeaconState()
  beaconFrame:SetPoint(anchor.anchorFrom, UIParent, anchor.anchorTo, anchor.xoffset, anchor.yoffset)
  beaconFrame:SetScale(anchor.scale)

  local background = beaconFrame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(unpack(MDT.BackdropColor or { 0.058, 0.058, 0.058, 0.9 }))

  -- Using function nesting here because createBeaconFrame is truly private and a one-shot initializer (no recreation cost)
  local function createBeaconEdge(point, width, height, offsetX, offsetY)
    local edge = beaconFrame:CreateTexture(nil, "BORDER")
    edge:SetSize(width, height)
    edge:SetPoint(point, beaconFrame, point, offsetX, offsetY)
    edge:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    return edge
  end

  createBeaconEdge("TOPLEFT", 360, 1, 0, 0)
  createBeaconEdge("BOTTOMLEFT", 360, 1, 0, 0)
  createBeaconEdge("TOPLEFT", 1, 170, 0, 0)
  createBeaconEdge("TOPRIGHT", 1, 170, 0, 0)

  -- === MINIMAP ===
  -- Viewport (fixed size, clips the scrollable container so only a 150x150 window is visible)
  beaconFrame.minimapFrame = CreateFrame("Frame", nil, beaconFrame)
  beaconFrame.minimapFrame:SetSize(Minimap.SIZE, Minimap.SIZE)
  beaconFrame.minimapFrame:SetPoint("TOPLEFT", beaconFrame, "TOPLEFT", 8, -8)
  beaconFrame.minimapFrame:SetClipsChildren(true)
  beaconFrame.minimapFrame:EnableMouseWheel(true)
  beaconFrame.minimapFrame:SetScript("OnMouseWheel", function(_, delta)
    Minimap.adjustUserZoom(beaconFrame, delta)
    Beacon:Update()
  end)

  -- Dark background so the viewport is visible even before tiles load
  local minimapBackground = beaconFrame.minimapFrame:CreateTexture(nil, "BACKGROUND")
  minimapBackground:SetAllPoints()
  minimapBackground:SetColorTexture(0.02, 0.02, 0.02, 1)

  -- Scrollable container holding all 15x10 tiles; panned by centerOnPull.
  -- Size and tile positioning are set dynamically each render by BeaconMinimap.applyZoom.
  beaconFrame.minimapContainer = CreateFrame("Frame", nil, beaconFrame.minimapFrame)
  beaconFrame.minimapContainer:SetSize(Minimap.GRID_COLS * Minimap.DEFAULT_TILE_SIZE, Minimap.GRID_ROWS * Minimap.DEFAULT_TILE_SIZE)
  beaconFrame.minimapContainer:SetPoint("TOPLEFT", beaconFrame.minimapFrame, "TOPLEFT", 0, 0)

  -- Create the 150 mini tile textures (sizes/positions set by applyZoom on first render)
  beaconFrame.minimapTiles = {}
  for i = 1, Minimap.GRID_ROWS do
    for j = 1, Minimap.GRID_COLS do
      local tileIndex = (i - 1) * Minimap.GRID_COLS + j
      local tile = beaconFrame.minimapContainer:CreateTexture(nil, "ARTWORK")
      tile:SetSize(Minimap.DEFAULT_TILE_SIZE, Minimap.DEFAULT_TILE_SIZE)
      tile:SetPoint(
        "TOPLEFT",
        beaconFrame.minimapContainer,
        "TOPLEFT",
        (j - 1) * Minimap.DEFAULT_TILE_SIZE,
        -(i - 1) * Minimap.DEFAULT_TILE_SIZE
      )
      tile:Hide()
      beaconFrame.minimapTiles[tileIndex] = tile
    end
  end

  -- This table will contain enemy positions
  beaconFrame.dots = {}

  -- Minimap border overlay
  local minimapBorder = beaconFrame.minimapFrame:CreateTexture(nil, "OVERLAY")
  minimapBorder:SetAllPoints()
  minimapBorder:SetColorTexture(0, 1, 0.5, 0.5)
  -- Hollow rectangle effect using 4 thin textures is nicer but simpler to skip
  -- We'll just use a thin colored overlay that wraps - actually let's just do a thin border
  minimapBorder:Hide()

  local function createEdge(edgeAnchor, width, height, offsetX, offsetY)
    local edge = beaconFrame.minimapFrame:CreateTexture(nil, "OVERLAY")
    edge:SetSize(width, height)
    edge:SetPoint(edgeAnchor, beaconFrame.minimapFrame, edgeAnchor, offsetX, offsetY)
    edge:SetColorTexture(0.4, 0.4, 0.4, 0.9)
    return edge
  end

  createEdge("TOPLEFT", Minimap.SIZE, 1, 0, 0)
  createEdge("BOTTOMLEFT", Minimap.SIZE, 1, 0, 0)
  createEdge("TOPLEFT", 1, Minimap.SIZE, 0, 0)
  createEdge("TOPRIGHT", 1, Minimap.SIZE, 0, 0)

  -- Zoom buttons (bottom-right corner of minimap)
  local function createZoomButton(label, offsetY, delta)
    local btn = CreateFrame("Button", nil, beaconFrame.minimapFrame)
    btn:SetSize(16, 16)
    btn:SetPoint("BOTTOMRIGHT", beaconFrame.minimapFrame, "BOTTOMRIGHT", -2, offsetY)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.65)

    local border = btn:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 1, 0.5, 0.6)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER", btn, "CENTER", 0, 1)
    text:SetText(label)
    text:SetTextColor(0, 1, 0.5, 1)

    btn:SetScript("OnEnter", function() bg:SetColorTexture(0.1, 0.4, 0.25, 0.9) end)
    btn:SetScript("OnLeave", function() bg:SetColorTexture(0, 0, 0, 0.65) end)
    btn:SetScript("OnClick", function()
      Minimap.adjustUserZoom(beaconFrame, delta)
      Beacon:Update()
    end)
    return btn
  end

  createZoomButton("+", 20, 1)
  createZoomButton("-", 2, -1)

  -- === Information panel (right side of the beacon) ===
  local infoPanelX = Minimap.SIZE + 16
  local infoPanelWidth = 360 - infoPanelX - 10

  -- Pull number badge
  local infoPanelPullBadge = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  infoPanelPullBadge:SetPoint("TOPLEFT", beaconFrame, "TOPLEFT", infoPanelX, -10)
  infoPanelPullBadge:SetTextColor(0, 1, 0.5, 1)
  beaconFrame.pullBadge = infoPanelPullBadge

  -- Status text (NEXT / IN COMBAT / ROUTE COMPLETE...)
  local infoPanelStatusText = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  infoPanelStatusText:SetPoint("TOPLEFT", infoPanelPullBadge, "BOTTOMLEFT", 0, -2)
  infoPanelStatusText:SetTextColor(0.8, 0.8, 0.8, 1)
  beaconFrame.statusText = infoPanelStatusText

  -- Mob count + forces next info text
  local mobAndForceInfoText = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mobAndForceInfoText:SetPoint("TOPLEFT", infoPanelStatusText, "BOTTOMLEFT", 0, -2)
  mobAndForceInfoText:SetTextColor(1, 1, 1, 1)
  beaconFrame.infoText = mobAndForceInfoText

  -- Enemies portraits (up to 4)
  beaconFrame.portraits = {}
  for i = 1, 4 do
    local portrait = beaconFrame:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(22, 22)
    if i == 1 then
      portrait:SetPoint("TOPLEFT", beaconFrame, "TOPLEFT", infoPanelX, -70)
    else
      portrait:SetPoint("LEFT", beaconFrame.portraits[i - 1], "RIGHT", 2, 0)
    end
    portrait:Hide()
    beaconFrame.portraits[i] = portrait
  end

  -- Progress bar (for active pull)
  local progressBar = CreateFrame("StatusBar", nil, beaconFrame)
  progressBar:SetSize(infoPanelWidth, 8)
  progressBar:SetPoint("TOPLEFT", beaconFrame, "TOPLEFT", infoPanelX, -102)
  progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  progressBar:SetStatusBarColor(0, 1, 0.5, 0.8)
  progressBar:SetMinMaxValues(0, 1)
  progressBar:SetValue(0)
  beaconFrame.progressBarWidth = infoPanelWidth
  beaconFrame.progressBar = progressBar

  -- Preview overlay (showing what this pull will add)
  local previewOverlay = progressBar:CreateTexture(nil, "OVERLAY")
  previewOverlay:SetColorTexture(1, 0.84, 0, 0.65)
  previewOverlay:SetHeight(8)
  previewOverlay:Hide()
  beaconFrame.previewOverlay = previewOverlay

  local progressBarBackground = progressBar:CreateTexture(nil, "BACKGROUND")
  progressBarBackground:SetAllPoints()
  progressBarBackground:SetColorTexture(0, 0, 0, 0.5)

  -- Upcoming preview (next+1 pull)
  local upcomingText = beaconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  upcomingText:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -4)
  upcomingText:SetTextColor(0.6, 0.6, 0.6, 1)
  upcomingText:SetScale(0.85)
  beaconFrame.upcomingText = upcomingText

  -- === Beacon Actions ===
  beaconFrame:SetScript("OnDragStart", function(self)
    if not MDT_NPT:GetBeaconState().locked then
      self:StartMoving()
    end
  end)

  beaconFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    local state = MDT_NPT:GetBeaconState()
    state.anchorFrom = point
    state.anchorTo = relativePoint
    state.xoffset = x
    state.yoffset = y
  end)

  beaconFrame:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
      MenuUtil.CreateContextMenu(self, function(_, rootDescription)
        rootDescription:CreateTitle(L["Next Pull Beacon"])
        rootDescription:CreateCheckbox(L["Locked"],
          function() return MDT_NPT:GetBeaconState().locked end,
          function()
            local state = MDT_NPT:GetBeaconState()
            state.locked = not state.locked
          end)
        rootDescription:CreateCheckbox(L["Show Upcoming"], function() return db.beacon.showUpcoming end, function()
          db.beacon.showUpcoming = not db.beacon.showUpcoming
          Beacon:Update()
        end)
        rootDescription:CreateButton(L["Hide Beacon"], function()
          db.beacon.enabled = false
          beaconFrame:Hide()
        end)
        rootDescription:CreateButton(L["Stop Tracking"], function()
          MDT_NPT:Stop()
        end)
      end)
    end
  end)

  -- Manual pull buttons
  local function createControlButton(parent, texture, offsetX, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", offsetX, -4)
    btn:SetNormalTexture(texture)
    btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    btn:SetAlpha(0)
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self)
      self:SetAlpha(1)
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      GameTooltip:SetText(tooltip, 1, 1, 1)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
      self:SetAlpha(0)
      GameTooltip:Hide()
    end)
    return btn
  end

  beaconFrame.completeBtn = createControlButton(
    beaconFrame,
    "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    -4,
    L["Mark Complete"],
    function()
      local state = MDT_NPT.state
      if state and state.active then
        for i, pullState in ipairs(state.pullStates) do
          if pullState.state == PullState.ACTIVE or pullState.state == PullState.NEXT then
            MDT_NPT:MarkComplete(i)
            return
          end
        end
      end
    end
  )

  beaconFrame.skipBtn = createControlButton(
    beaconFrame,
    "Interface\\MINIMAP\\MiniMap-VignetteArrow",
    -22,
    L["Skip Pull"],
    function()
      local state = MDT.nextPullState
      if state and state.active and state.currentNextPull then
        local nextIdx = state.currentNextPull + 1
        if nextIdx <= #state.pullStates then
          MDT:SkipTo(nextIdx)
        end
      end
    end
  )

  beaconFrame.revertBtn = createControlButton(
    beaconFrame,
    "Interface\\BUTTONS\\UI-RefreshButton",
    -40,
    L["Revert Pull"],
    function()
      local state = MDT.nextPullState
      if state and state.active and state.currentNextPull then
        local prevIdx = state.currentNextPull - 1
        if prevIdx >= 1 then
          MDT:MarkIncomplete(prevIdx)
        end
      end
    end
  )

  beaconFrame:SetScript("OnEnter", function(self)
    self.completeBtn:SetAlpha(0.7)
    self.skipBtn:SetAlpha(0.7)
    self.revertBtn:SetAlpha(0.7)
  end)

  beaconFrame:SetScript("OnLeave", function(self)
    if not MouseIsOver(self) then
      self.completeBtn:SetAlpha(0)
      self.skipBtn:SetAlpha(0)
      self.revertBtn:SetAlpha(0)
    end
  end)

  beaconFrame:Hide()
  return beaconFrame
end

local function renderRouteComplete(frame, state, totalForcesMax)
  local totalKilled = 0
  for _, ps in ipairs(state.pullStates) do
    totalKilled = totalKilled + ps.totalForces
  end

  local overUnder = totalKilled - totalForcesMax
  local pctText = string_format("%.1f%%", (overUnder / totalForcesMax) * 100)

  frame.pullBadge:SetText(L["Done"])
  frame.statusText:SetText(L["Route Complete"])
  frame.infoText:SetText((overUnder >= 0 and "+" or "")..pctText.." "..L["forces"])
  frame.progressBar:SetValue(1)
  frame.previewOverlay:Hide()
  frame.upcomingText:SetText("")

  for i = 1, 4 do frame.portraits[i]:Hide() end
  for _, dot in ipairs(frame.dots) do dot:Hide() end
  Minimap.drawCurrentPullOutline(frame, nil)
end

local function renderPullHeader(frame, nextPull, pullState, totalPulls)
  frame.pullBadge:SetText(L["Pull"].." "..nextPull.." / "..totalPulls)

  if pullState.state == PullState.ACTIVE then
    frame.statusText:SetText(L["In Combat"])
    frame.statusText:SetTextColor(1, 0.3, 0.3, 1)
  else
    frame.statusText:SetText(L["Next"])
    frame.statusText:SetTextColor(0, 1, 0.5, 1)
  end
end

local function renderPercentageInfoText(frame, totalCount, basePercentageForText, pullPercentage, targetPercentage)
  local currentStr = string.format("|cFF00BFFF%.1f%%|r", basePercentageForText)
  local pullStr = string.format("|cFFFFD700+%.1f%%|r", pullPercentage)
  local targetStr = string.format("|cFF00FF7F%.1f%%|r", targetPercentage)
  frame.infoText:SetText(totalCount.." "..L["mobs"].."  "..
    currentStr.." "..pullStr.." / "..targetStr)
end

local function updateProgressBar(frame, currentPct)
  local basePercentage = currentPct or 0
  frame.progressBar:SetValue(basePercentage / 100)
  frame.progressBar:SetStatusBarColor(0, 0.75, 1, 0.8)
end


local function renderCurrentPullContribution(frame, basePercentage, pullPercentage)
  local barWidth = frame.progressBarWidth or 180
  local startPercentage = math.min(basePercentage, 100)
  local endPercentage = math.min(basePercentage + pullPercentage, 100)
  local overlayWith = (endPercentage - startPercentage) / 100 * barWidth

  if overlayWith > 0.5 then
    frame.previewOverlay:ClearAllPoints()
    frame.previewOverlay:SetPoint(
      "LEFT",
      frame.progressBar,
      "LEFT",
      (startPercentage / 100) * barWidth,
      0
    )
    frame.previewOverlay:SetSize(overlayWith, 8)
    frame.previewOverlay:Show()
  else
    frame.previewOverlay:Hide()
  end
end

local function renderEnemiesProtraits(frame, pull, enemies)
  local portraitIndex = 0
  if pull and enemies then
    for enemyIndex in pairs(pull) do
      if tonumber(enemyIndex) and enemies[enemyIndex] and portraitIndex < 4 then
        portraitIndex = portraitIndex + 1
        local displayId = enemies[enemyIndex].displayId or 39490
        SetPortraitTextureFromCreatureDisplayID(frame.portraits[portraitIndex], displayId)
        frame.portraits[portraitIndex]:Show()
      end
    end
  end
  for i = portraitIndex + 1, 4 do
    frame.portraits[i]:Hide()
  end
end

local function renderUpcompingPreview(frame, pullStates, nextPull, showUpcoming, totalForcesMax)
  if showUpcoming and nextPull + 1 <= #pullStates then
    local upcompingPullState = pullStates[nextPull + 1]
    if upcompingPullState and upcompingPullState.state ~= PullState.COMPLETED then
      local upcomingForcePercentage = string.format(
        "%.1f%%",
        (upcompingPullState.totalForces / totalForcesMax) * 100
      )
      frame.upcomingText:SetText(L["Then"]..
        ": "..L["Pull"].." "..(nextPull + 1).." - "..upcompingPullState.totalCount.." "..L["mobs"].." - "..upcomingForcePercentage)
      frame.upcomingText:Show()
    else
      frame.upcomingText:Hide()
    end
  else
    frame.upcomingText:Hide()
  end
end

MDT_NPT.BeaconFrame = {
  create = create,
  renderRouteComplete = renderRouteComplete,
  renderPullHeader = renderPullHeader,
  renderPercentageInfoText = renderPercentageInfoText,
  updateProgressBar = updateProgressBar,
  renderCurrentPullContribution = renderCurrentPullContribution,
  renderEnemiesProtraits = renderEnemiesProtraits,
  renderUpcompingPreview = renderUpcompingPreview,
}
