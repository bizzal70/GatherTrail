local _, ns = ...

local PIN_SIZE, TARGET_SIZE = 9, 13
local EDGE_INSET = 5
-- Minimap diameter in yards at each zoom level, used only when the client
-- cannot report its view radius directly.
local OUTDOOR_DIAMETERS = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 }

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar

local holder = CreateFrame("Frame", nil, Minimap)
holder:SetAllPoints(Minimap)
holder:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)

local pins = {}

local function PinOnEnter(self)
    ns.ShowNodeTooltip(self, self.node, "ANCHOR_LEFT")
end

local function PinOnLeave()
    GameTooltip:Hide()
end

local function AcquirePin(index)
    local pin = pins[index]
    if not pin then
        pin = CreateFrame("Frame", nil, holder)
        pin.minimapPin = true
        -- Dark rim so the pin stays readable over any terrain.
        local rim = pin:CreateTexture(nil, "BACKGROUND")
        rim:SetAllPoints()
        rim:SetColorTexture(0, 0, 0, 0.9)
        pin.texture = pin:CreateTexture(nil, "ARTWORK")
        pin.texture:SetPoint("TOPLEFT", 1, -1)
        pin.texture:SetPoint("BOTTOMRIGHT", -1, 1)
        ns.RoundPin(pin, rim, pin.texture)
        pin:SetScript("OnEnter", PinOnEnter)
        pin:SetScript("OnLeave", PinOnLeave)
        -- Hover only, so clicks still reach the minimap underneath.
        if pin.SetMouseClickEnabled then
            pin:SetMouseClickEnabled(false)
        end
        pins[index] = pin
    end
    return pin
end

-- How many yards the minimap shows from its centre to its edge.
local function ViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local radius = C_Minimap.GetViewRadius()
        if ns.IsUsable(radius) and radius > 0 then return radius end
    end
    local zoom = Minimap:GetZoom()
    return (OUTDOOR_DIAMETERS[ns.IsUsable(zoom) and zoom or 0] or OUTDOOR_DIAMETERS[0]) / 2
end

-- With a rotating minimap, up is the way the player faces instead of
-- north. Returns the sine and cosine of that turn (0 and 1 when fixed).
local function Rotation()
    if GetCVar("rotateMinimap") == "1" then
        local facing = GetPlayerFacing()
        if ns.IsUsable(facing) then
            return math.sin(facing), math.cos(facing)
        end
    end
    return 0, 1
end

local function Update()
    local used = 0
    local mapID, px, py = ns.GetPlayerPosition()

    if ns.db.showMinimapPins and mapID then
        local halfWidth = Minimap:GetWidth() / 2
        local pixelsPerYard = halfWidth / ViewRadius()
        local edge = halfWidth - EDGE_INSET
        local sinF, cosF = Rotation()

        local function Place(node, east, south, isTarget)
            local north = -south
            local x = (east * cosF + north * sinF) * pixelsPerYard
            local y = (north * cosF - east * sinF) * pixelsPerYard
            local length = math.sqrt(x * x + y * y)
            if length > edge then
                -- Out of range: only the route's next stop stays, pinned to
                -- the rim in its direction.
                if not isTarget then return end
                x, y = x / length * edge, y / length * edge
            end
            used = used + 1
            local pin = AcquirePin(used)
            pin.node = node
            local size = isTarget and TARGET_SIZE or PIN_SIZE
            pin:SetSize(size, size)
            if node.travel then
                pin.texture:SetColorTexture(1, 1, 1, 1)
            else
                pin.texture:SetColorTexture(ns.NodeColor(node, isTarget))
            end
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
            pin:Show()
        end

        -- The next stop, or the next step of the trip to the route's zone.
        local routeMap, target = ns.GetGuideTarget()

        for _, node in ipairs(ns.db.nodes[mapID] or {}) do
            if node ~= target and ns.IsKindShown(node) then
                local _, east, south = ns.Distance(mapID, px, py, node.x, node.y)
                Place(node, east, south, false)
            end
        end

        -- Drawn last so it sits on top. It may be in another zone.
        if target then
            local tx, ty = px, py
            if routeMap ~= mapID then
                tx, ty = ns.GetPlayerPositionOnMap(routeMap)
            end
            if tx then
                local _, east, south = ns.Distance(routeMap, tx, ty, target.x, target.y)
                Place(target, east, south, true)
            end
        end
    end

    for index = used + 1, #pins do
        pins[index]:Hide()
    end
end

ns.RefreshMinimapPins = Update

---------------------------------------------------------------------------
-- Recording nodes from the game's own minimap blips
--
-- The client does not tell addons where its tracking blips are, so they
-- cannot be read automatically. What it does do is show a tooltip naming
-- the blip under the cursor, and the cursor's place on the minimap gives
-- the blip's place in the world.
---------------------------------------------------------------------------

-- How far east and north of the player the cursor is pointing, in yards.
local function CursorOffsetYards()
    local centerX, centerY = Minimap:GetCenter()
    if not centerX then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local x, y = cursorX / scale - centerX, cursorY / scale - centerY
    local yardsPerPixel = ViewRadius() / (Minimap:GetWidth() / 2)
    local sinF, cosF = Rotation()
    return (x * cosF - y * sinF) * yardsPerPixel, (x * sinF + y * cosF) * yardsPerPixel
end

-- Strips colour codes and inline icons from a line of tooltip text.
local function CleanName(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local lastBlip, lastBlipTime = nil, 0
-- The tooltip text last looked at, so each new tooltip is handled once.
-- false means the text was there but the client would not let it be read.
local lastText

-- Looks at the tooltip while the cursor is over the minimap. This is polled
-- rather than hooked: which frame the client says owns a blip's tooltip,
-- and whether showing it fires a script, both vary between clients, but
-- "the cursor is on the minimap and a tooltip is up" does not.
local function CheckMinimapTooltip()
    if not ns.db.minimapDetect or not GameTooltip:IsShown() or not Minimap:IsMouseOver() then
        lastText = nil
        return
    end
    -- Our own pins and button put up tooltips over the minimap too.
    local owner = GameTooltip:GetOwner()
    if owner and (owner.minimapPin or owner == GatherTrailMinimapButton) then return end

    local text = GameTooltipTextLeft1:GetText()
    if not ns.IsUsable(text) then
        if ns.db.debug and text ~= nil and lastText ~= false then
            ns.Print("minimap tooltip: the game is not letting addons read its text")
        end
        lastText = text ~= nil and false or nil
        return
    end
    if text == lastText then return end
    lastText = text

    local east, north = CursorOffsetYards()
    if not east then return end

    -- Several blips under the cursor are listed one per line.
    for line in text:gmatch("[^\n]+") do
        local name = CleanName(line)
        local profession = name ~= "" and ns.ClassifyNodeName(name)
        if ns.db.debug and name ~= "" then
            ns.Print(("minimap tooltip: \"%s\" is %s"):format(name, profession or "not a node name I know"))
        end
        local now = GetTime()
        if profession and not (name == lastBlip and now - lastBlipTime < 5) then
            lastBlip, lastBlipTime = name, now
            -- A minimap pixel is a few yards wide, so the place is close
            -- but not exact; gathering the node later pins it down.
            ns.RecordNode(name, "seen", true, profession, { east = east, north = north })
        end
    end
end

ns.CheckMinimapTooltip = CheckMinimapTooltip

local elapsedTotal = 0
ns.onLogin[#ns.onLogin + 1] = function()
    holder:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 0.1 then return end
        elapsedTotal = 0
        CheckMinimapTooltip()
        Update()
    end)
end
