local MDT = MDT
local MDT_NPT = MDT_NPT
local pairs, tonumber, type = pairs, tonumber, type

local SIZE = 150                     -- viewport width/height
local TILE_SIZE = 22                 -- each scaled-down tile (original is ~56 at 840 map)
local SCALE = TILE_SIZE / (840 / 15) -- ~0.393

---Loads dungeon map textures into the mini-map tiles of the given beacon frame.
local function loadTextures(beaconFrame, dungeonIndex, sublevel)
  if not beaconFrame or not beaconFrame.minimapTiles then return end

  local dungeonMaps = MDT.dungeonMaps and MDT.dungeonMaps[dungeonIndex]
  if not dungeonMaps then return end

  local textureInfo = dungeonMaps[sublevel] or dungeonMaps[1]
  if not textureInfo then return end

  for i = 1, 10 do
    for j = 1, 15 do
      local tileIndex = (i - 1) * 15 + j
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

local function calculatePullCentroid(pull, sublevel, enemies)
  if not pull then return nil, nil end
  if not enemies then return nil, nil end

  local sumX, sumY, count = 0, 0, 0
  for enemyIndex, clones in pairs(pull) do
    if tonumber(enemyIndex) and enemies[enemyIndex] then
      for _, cloneIndex in ipairs(clones) do
        local clone = enemies[enemyIndex].clones and enemies[enemyIndex].clones[cloneIndex]
        if clone and (clone.sublevel == sublevel or not clone.sublevel) then
          sumX = sumX + clone.x
          sumY = sumY + clone.y
          count = count + 1
        end
      end
    end
  end
  if count == 0 then return nil, nil end
  return sumX / count, sumY / count
end

local function centerMinimapOnPull(frame, centroidX, centroidY)
  if not frame or not frame.minimapContainer then return end
  -- Scale centroid to container coords
  local scaledCentroidX = centroidX * SCALE
  local scaledCentroidY = centroidY * SCALE
  -- Offset the container so the centroid is centered in the viewport
  frame.minimapContainer:ClearAllPoints()
  frame.minimapContainer:SetPoint(
    "TOPLEFT",
    frame.minimapFrame,
    "TOPLEFT",
    -scaledCentroidX + SIZE / 2,
    -scaledCentroidY - SIZE / 2
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
              local scaledX = clone.x * SCALE
              local scaledY = clone.y * SCALE
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
  TILE_SIZE = TILE_SIZE,
  SCALE = SCALE,
  loadTextures = loadTextures,
  calculatePullCentroid = calculatePullCentroid,
  centerMinimapOnPull = centerMinimapOnPull,
  updateMinimapDots = updateMinimapDots,
}
