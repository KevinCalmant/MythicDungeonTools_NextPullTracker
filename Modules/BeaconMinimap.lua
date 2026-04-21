local MDT = MDT
local MDT_NPT = MDT_NPT
local pairs, tonumber, type = pairs, tonumber, type
local math_max, math_min, math_huge = math.max, math.min, math.huge

local SIZE = 150                -- viewport width/height in pixels
local GRID_COLS = 15
local GRID_ROWS = 10
local BASE_TILE = 840 / GRID_COLS -- 56 world units per tile in MDT's native coord space

-- Adaptive zoom bounds
local PADDING = 40                              -- world units padded around the pull bbox
local MIN_BBOX = 120                            -- floor on bbox size so single-enemy pulls don't over-zoom
local MIN_SCALE = SIZE / (GRID_COLS * BASE_TILE) -- "show whole map" floor (~0.179)
local AUTO_MAX_SCALE = 0.8                      -- cap for the auto-zoom calc (keeps tiny pulls from filling the viewport)
local MAX_SCALE = 2.5                           -- absolute cap, reachable only via user zoom
local DEFAULT_TILE_SIZE = 22                    -- initial tile pixel size before first render applies zoom

-- User-controlled zoom (applied on top of auto-zoom via mouse wheel)
local ZOOM_STEP = 1.2                           -- geometric factor per wheel tick
local USER_ZOOM_MIN = 0.5                       -- how far below auto-zoom the user may go
local USER_ZOOM_MAX = 6.0                       -- how far above auto-zoom the user may go (final scale still clamped by MAX_SCALE)

local function applyZoom(frame, scale)
  if not frame or not frame.minimapContainer or not frame.minimapTiles then return end
  frame.minimapScale = scale
  local tileSize = BASE_TILE * scale
  frame.minimapContainer:SetSize(GRID_COLS * tileSize, GRID_ROWS * tileSize)
  for i = 1, GRID_ROWS do
    for j = 1, GRID_COLS do
      local tileIndex = (i - 1) * GRID_COLS + j
      local tile = frame.minimapTiles[tileIndex]
      if tile then
        tile:SetSize(tileSize, tileSize)
        tile:SetPoint(
          "TOPLEFT",
          frame.minimapContainer,
          "TOPLEFT",
          (j - 1) * tileSize,
          -(i - 1) * tileSize
        )
      end
    end
  end
end

---Loads dungeon map textures into the mini-map tiles of the given beacon frame.
local function loadTextures(beaconFrame, dungeonIndex, sublevel)
  if not beaconFrame or not beaconFrame.minimapTiles then return end

  local dungeonMaps = MDT.dungeonMaps and MDT.dungeonMaps[dungeonIndex]
  if not dungeonMaps then return end

  local textureInfo = dungeonMaps[sublevel] or dungeonMaps[1]
  if not textureInfo then return end

  for i = 1, GRID_ROWS do
    for j = 1, GRID_COLS do
      local tileIndex = (i - 1) * GRID_COLS + j
      local tile = beaconFrame.minimapTiles[tileIndex]
      if tile then
        local textureName
        if type(textureInfo) == "string" then
          local mapName = MDT.mapInfo[dungeonIndex] and MDT.mapInfo[dungeonIndex].englishName or ""
          textureName = "Interface\\WorldMap\\"..mapName.."\\"..textureInfo..tileIndex
        elseif type(textureInfo) == "table" then
          textureName = textureInfo.customTextures.."\\"..(sublevel or 1).."_"..tileIndex..".png"
        end

        if textureName then
          tile:SetTexture(textureName)
          tile:Show()
        else
          tile:Hide()
        end
      end
    end
  end
end

---Computes the centroid and axis-aligned bounding box of the given pull's enemies on the active sublevel.
local function calculatePullBounds(pull, sublevel, enemies)
  if not pull or not enemies then return nil end

  local sumX, sumY, count = 0, 0, 0
  local minX, minY = math_huge, math_huge
  local maxX, maxY = -math_huge, -math_huge
  for enemyIndex, clones in pairs(pull) do
    if tonumber(enemyIndex) and enemies[enemyIndex] then
      for _, cloneIndex in ipairs(clones) do
        local clone = enemies[enemyIndex].clones and enemies[enemyIndex].clones[cloneIndex]
        if clone and (clone.sublevel == sublevel or not clone.sublevel) then
          sumX = sumX + clone.x
          sumY = sumY + clone.y
          count = count + 1
          if clone.x < minX then minX = clone.x end
          if clone.x > maxX then maxX = clone.x end
          if clone.y < minY then minY = clone.y end
          if clone.y > maxY then maxY = clone.y end
        end
      end
    end
  end
  if count == 0 then return nil end
  return {
    centroidX = sumX / count,
    centroidY = sumY / count,
    minX = minX, minY = minY,
    maxX = maxX, maxY = maxY,
  }
end

---Picks a zoom scale that fits the pull's bbox + padding into the viewport, clamped to sane bounds.
---`userMultiplier` (default 1) lets the user override the auto-zoom via mouse wheel.
local function computeZoomScale(bounds, userMultiplier)
  userMultiplier = userMultiplier or 1
  local scale
  if not bounds then
    scale = MIN_SCALE
  else
    local bboxW = math_max(bounds.maxX - bounds.minX, MIN_BBOX)
    local bboxH = math_max(bounds.maxY - bounds.minY, MIN_BBOX)
    scale = math_min(SIZE / (bboxW + 2 * PADDING), SIZE / (bboxH + 2 * PADDING))
    scale = math_min(scale, AUTO_MAX_SCALE)
  end
  return math_max(MIN_SCALE, math_min(MAX_SCALE, scale * userMultiplier))
end

---Bumps the user's zoom multiplier one wheel tick in the given direction, clamped to sane bounds.
local function adjustUserZoom(frame, delta)
  if not frame then return end
  local mult = frame.userZoomMultiplier or 1
  mult = mult * (delta > 0 and ZOOM_STEP or (1 / ZOOM_STEP))
  if mult < USER_ZOOM_MIN then mult = USER_ZOOM_MIN end
  if mult > USER_ZOOM_MAX then mult = USER_ZOOM_MAX end
  frame.userZoomMultiplier = mult
end

local function centerMinimapOnPull(frame, centroidX, centroidY)
  if not frame or not frame.minimapContainer then return end
  local scale = frame.minimapScale or MIN_SCALE
  frame.minimapContainer:ClearAllPoints()
  frame.minimapContainer:SetPoint(
    "TOPLEFT",
    frame.minimapFrame,
    "TOPLEFT",
    -centroidX * scale + SIZE / 2,
    -centroidY * scale - SIZE / 2
  )
end

local function getDot(frame, dotIndex)
  dotIndex = dotIndex + 1
  local dot = frame.dots[dotIndex]
  if not dot then
    dot = frame.minimapContainer:CreateTexture(nil, "OVERLAY")
    dot:SetTexture("Interface\\AddOns\\MythicDungeonTools\\Textures\\Circle_White")
    frame.dots[dotIndex] = dot
  end
  return dot, dotIndex
end

local function updateMinimapDots(frame, state, pulls, enemies, sublevel)
  if not frame or not frame.minimapContainer then return end
  if not enemies then return end

  local scale = frame.minimapScale or MIN_SCALE

  -- Hide all existing dots
  for _, dot in ipairs(frame.dots) do
    dot:Hide()
  end

  -- Draw dots for relevant pulls (next, +/-1 for context)
  local nextPull = state.currentNextPull
  if not nextPull then return end

  local dotIndex = 0
  for pullIndex = math.max(1, nextPull - 1), math.min(#pulls, nextPull + 1) do
    local pull = pulls[pullIndex]
    if pull then
      local pullState = state.pullStates[pullIndex] and state.pullStates[pullIndex].state
      -- Color: next=green, active=orange, completed=gray, upcoming=yellow
      local r, g, b, a
      if pullState == "next" then
        r, g, b, a = 0, 1, 0.5, 1
      elseif pullState == "active" then
        r, g, b, a = 1, 0.5, 0, 1
      elseif pullState == "completed" then
        r, g, b, a = 0.4, 0.4, 0.4, 0.6
      else
        r, g, b, a = 1, 1, 0, 0.7
      end

      for enemyIndex, clones in pairs(pull) do
        if tonumber(enemyIndex) and enemies[enemyIndex] then
          for _, cloneIndex in ipairs(clones) do
            local clone = enemies[enemyIndex].clones and enemies[enemyIndex].clones[cloneIndex]
            if clone and (clone.sublevel == sublevel or not clone.sublevel) then
              local dot
              dot, dotIndex = getDot(frame, dotIndex)
              dot:SetVertexColor(r, g, b, a)
              -- Position relative to the container (scaled from original coords)
              local scaledX = clone.x * scale
              local scaledY = clone.y * scale
              dot:ClearAllPoints()
              dot:SetPoint("CENTER", frame.minimapContainer, "TOPLEFT", scaledX, scaledY)
              -- Next pull dots are bigger
              if pullState == "next" or pullState == "active" then
                dot:SetSize(5, 5)
              else
                dot:SetSize(3, 3)
              end
              dot:Show()
            end
          end
        end
      end
    end
  end
end

MDT_NPT.BeaconMinimap = {
  SIZE = SIZE,
  GRID_COLS = GRID_COLS,
  GRID_ROWS = GRID_ROWS,
  BASE_TILE = BASE_TILE,
  DEFAULT_TILE_SIZE = DEFAULT_TILE_SIZE,
  MIN_SCALE = MIN_SCALE,
  MAX_SCALE = MAX_SCALE,
  applyZoom = applyZoom,
  loadTextures = loadTextures,
  calculatePullBounds = calculatePullBounds,
  computeZoomScale = computeZoomScale,
  adjustUserZoom = adjustUserZoom,
  centerMinimapOnPull = centerMinimapOnPull,
  updateMinimapDots = updateMinimapDots,
}
