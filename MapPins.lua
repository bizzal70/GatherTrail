local _, ns = ...

-- Sizes are in screen pixels; they are converted for the map's zoom below.
local PIN_SIZE = 9
local STOP_SIZE = 16          -- a numbered stop on the active route
local TARGET_SIZE = 21        -- the stop the route is heading for now
local LEG_THICKNESS = 2
local CHEVRON_SIZE = 6
local OFF_ROUTE_ALPHA = 0.45  -- other nodes fade back while a route is shown

local overlay, playerLine
local pins, lines = {}, {}

local function PinOnEnter(self)
    if self.marker then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.marker.title)
        GameTooltip:AddLine(self.marker.note, 1, 1, 1)
        GameTooltip:Show()
        return
    end
    ns.ShowNodeTooltip(self, self.node, "ANCHOR_RIGHT")
    if self.stop then
        GameTooltip:AddLine(("Stop %d of %d on the current route"):format(self.stop, self.stopCount), 0.2, 1, 0.2)
        GameTooltip:Show()
    end
end

local function PinOnLeave()
    GameTooltip:Hide()
end

local function AcquirePin(index)
    local pin = pins[index]
    if not pin then
        pin = CreateFrame("Frame", nil, overlay)
        -- Dark rim so the pin stays readable over any map art.
        local rim = pin:CreateTexture(nil, "BACKGROUND")
        rim:SetAllPoints()
        rim:SetColorTexture(0, 0, 0, 0.9)
        pin.texture = pin:CreateTexture(nil, "ARTWORK")
        pin.texture:SetPoint("TOPLEFT", 1, -1)
        pin.texture:SetPoint("BOTTOMRIGHT", -1, 1)
        ns.RoundPin(pin, rim, pin.texture)
        pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pin.label:SetPoint("CENTER")
        pin.label:SetTextColor(0, 0, 0)
        pin:SetScript("OnEnter", PinOnEnter)
        pin:SetScript("OnLeave", PinOnLeave)
        -- Hover only, so clicks still reach the map underneath.
        if pin.SetMouseClickEnabled then
            pin:SetMouseClickEnabled(false)
        end
        pins[index] = pin
    end
    return pin
end

local usedLines = 0

local function DrawLine(x1, y1, x2, y2, thickness, r, g, b, a)
    usedLines = usedLines + 1
    local line = lines[usedLines]
    if not line then
        line = overlay:CreateLine(nil, "ARTWORK")
        lines[usedLines] = line
    end
    line:SetColorTexture(r, g, b, a)
    line:SetThickness(thickness)
    line:SetStartPoint("TOPLEFT", overlay, x1, y1)
    line:SetEndPoint("TOPLEFT", overlay, x2, y2)
    line:Show()
end

-- One leg of the route, with a chevron at its midpoint showing which way
-- the loop runs.
local function DrawLeg(x1, y1, x2, y2, unit, r, g, b, a)
    DrawLine(x1, y1, x2, y2, LEG_THICKNESS * unit, r, g, b, a)

    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    local size = CHEVRON_SIZE * unit
    if length < size * 5 then return end
    dx, dy = dx / length, dy / length
    local tipX, tipY = (x1 + x2) / 2 + dx * size, (y1 + y2) / 2 + dy * size
    local backX, backY = tipX - dx * size * 2, tipY - dy * size * 2
    DrawLine(tipX, tipY, backX - dy * size, backY + dx * size, LEG_THICKNESS * unit, r, g, b, 1)
    DrawLine(tipX, tipY, backX + dy * size, backY - dx * size, LEG_THICKNESS * unit, r, g, b, 1)
end

-- A line from the player to the stop the route is heading for. Redrawn as
-- the player moves, while the map is open.
local function UpdatePlayerLine()
    if not playerLine then return end
    playerLine:Hide()
    if not ns.db.showPins then return end
    local mapID = WorldMapFrame:GetMapID()
    local targetMap, target = ns.GetGuideTarget()
    if not target or targetMap ~= mapID then return end
    local _, px, py = ns.GetPlayerPosition(mapID)
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end

    local width, height = overlay:GetSize()
    local scale = overlay:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if scale <= 0 then scale = 1 end
    playerLine:SetThickness(LEG_THICKNESS / scale)
    playerLine:SetStartPoint("TOPLEFT", overlay, px * width, -py * height)
    playerLine:SetEndPoint("TOPLEFT", overlay, target.x * width, -target.y * height)
    playerLine:Show()
end

function ns.RefreshPins()
    if not overlay or not WorldMapFrame:IsShown() then return end

    for _, pin in ipairs(pins) do pin:Hide() end
    for _, line in ipairs(lines) do line:Hide() end
    usedLines = 0
    UpdatePlayerLine()
    if not ns.db.showPins then return end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local nodes = ns.db.nodes[mapID] or {}

    -- The canvas is scaled as the map zooms. Pins are counter-scaled so they
    -- and their numbers keep their on-screen size, which means their
    -- offsets must be given in on-screen units too. Lines live on the
    -- canvas itself, so their sizes are divided instead.
    local width, height = overlay:GetSize()
    local scale = overlay:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if scale <= 0 then scale = 1 end
    local unit = 1 / scale

    local routeMap, route, routeIndex = ns.GetRoute()
    local onThisMap = route and routeMap == mapID
    local stops = {}
    if onThisMap then
        for index, node in ipairs(route) do
            stops[node] = index
        end
    end

    local pinCount = 0
    for _, node in ipairs(nodes) do
      local stop = stops[node]
      -- Hidden kinds are skipped, except stops on the route being followed.
      if stop or ns.IsKindShown(node) then
        pinCount = pinCount + 1
        local pin = AcquirePin(pinCount)
        local isTarget = stop ~= nil and stop == routeIndex
        pin.node, pin.stop, pin.stopCount = node, stop, stop and #route or nil
        pin.marker = nil

        local size = isTarget and TARGET_SIZE or (stop and STOP_SIZE or PIN_SIZE)
        pin:SetScale(unit)
        pin:SetSize(size, size)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", overlay, "TOPLEFT", node.x * width * scale, -node.y * height * scale)
        pin.texture:SetColorTexture(ns.NodeColor(node, isTarget))
        pin.label:SetText(stop and tostring(stop) or "")
        -- Nodes off the route fade back while one is shown, and so do nodes
        -- gathered too recently to be worth going back to.
        local faded = (onThisMap and not stop) or (ns.IsFresh(node) and not isTarget)
        pin:SetAlpha(faded and OFF_ROUTE_ALPHA or 1)
        -- Stops sit above ordinary nodes, and the current one above those.
        pin:SetFrameLevel(overlay:GetFrameLevel() + (isTarget and 3 or (stop and 2 or 1)))
        pin:Show()
      end
    end

    -- Travel knowledge on this map: flight masters ("F"), transports ("T")
    -- and the places zones have been walked between (small, unlabelled).
    local markerCount = pinCount
    local function Marker(point, label, size, r, g, b, title, note)
        markerCount = markerCount + 1
        local pin = AcquirePin(markerCount)
        pin.node, pin.stop, pin.stopCount = nil, nil, nil
        pin.marker = { title = title, note = note }
        pin:SetScale(unit)
        pin:SetSize(size, size)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", overlay, "TOPLEFT", point.x * width * scale, -point.y * height * scale)
        pin.texture:SetColorTexture(r, g, b, 1)
        pin.label:SetText(label)
        pin:SetAlpha(1)
        pin:SetFrameLevel(overlay:GetFrameLevel() + 1)
        pin:Show()
    end

    for nodeID, flight in pairs(ns.db.flights) do
        if flight.map == mapID then
            Marker(flight, "F", 14, 0.4, 0.8, 1, flight.name .. " flight master",
                ns.IsFlightKnown(nodeID) and "This character can fly here" or "Not learned by this character")
        end
    end
    for _, link in ipairs(ns.db.links) do
        local isWalk = link.kind == "walk"
        local note = ("Used %d times"):format(link.count)
        if link.a.map == mapID then
            Marker(link.a, isWalk and "" or "T", isWalk and 7 or 14, 0.85, 0.85, 0.85,
                (isWalk and "Crossing into " or "Transport to ") .. ns.MapName(link.b.map), note)
        end
        if link.b.map == mapID then
            Marker(link.b, isWalk and "" or "T", isWalk and 7 or 14, 0.85, 0.85, 0.85,
                (isWalk and "Crossing into " or "Arrival from ") .. ns.MapName(link.a.map), note)
        end
    end

    if onThisMap and #route >= 2 then
        for index, node in ipairs(route) do
            local nextNode = route[index % #route + 1]
            -- The leg leaving the current stop is the one to follow next.
            local alpha = index == routeIndex and 0.95 or 0.5
            DrawLeg(node.x * width, -node.y * height, nextNode.x * width, -nextNode.y * height,
                unit, 0.2, 1, 0.2, alpha)
        end
    end
end

local function Setup()
    if overlay or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    -- Above Blizzard's own map pins.
    overlay:SetFrameLevel(5000)

    playerLine = overlay:CreateLine(nil, "OVERLAY")
    playerLine:SetColorTexture(1, 1, 1, 0.85)
    playerLine:Hide()

    local elapsedTotal = 0
    overlay:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 0.1 then return end
        elapsedTotal = 0
        UpdatePlayerLine()
    end)

    WorldMapFrame:HookScript("OnShow", ns.RefreshPins)
    if WorldMapFrame.OnMapChanged then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.RefreshPins)
    end
    if WorldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", ns.RefreshPins)
    end
end

ns.onLogin[#ns.onLogin + 1] = function()
    Setup()
    if not overlay then
        -- The world map can be load-on-demand.
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(self)
            Setup()
            if overlay then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end
