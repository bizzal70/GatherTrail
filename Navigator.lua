local addonName, ns = ...

local ARROW_HALF_LENGTH = 20
local ARROW_HEAD_LENGTH = 16
local ARROW_HEAD_WIDTH = 13
local ARRIVE_SOUND = SOUNDKIT and SOUNDKIT.MAP_PING or 3175

local STEP_ARRIVE_YARDS = 30

local routeMap, route, routeIndex
-- While the route's zone is somewhere else, the steps of the trip there
-- (flight masters, crossings, transports) come first.
local travel, travelIndex

-- What the arrow, beacon and pins should point at now: the map it is on,
-- the point itself, and whether it is a step of the trip rather than a node.
function ns.GetGuideTarget()
    if not route then return end
    if travel then
        local step = travel[travelIndex]
        return step.map, step, true
    end
    return routeMap, route[routeIndex], false
end

-- Plans the trip again from wherever the character is now. Called when the
-- route starts and whenever they change zone or land from a flight, so the
-- steps stay right after detours.
local function PlanTravel()
    travel, travelIndex = nil, nil
    if not route then return end
    local currentMap = C_Map.GetBestMapForUnit("player")
    if ns.IsUsable(currentMap) and currentMap == routeMap then return end
    local node = route[routeIndex]
    local steps = ns.PlanTravel(routeMap, node.x, node.y)
    if steps and #steps > 0 then
        travel, travelIndex = steps, 1
    end
end

---------------------------------------------------------------------------
-- In-world beacon: the game's own tracked map pin, moved to the next node.
---------------------------------------------------------------------------

local beaconSet = false
local savedWaypoint          -- the player's own pin, restored when the route ends
local beaconForbidden = false -- the client refused the tracking call this session
local beaconRetry = false     -- tracking was refused in combat; try again after

local function ClearBeacon()
    if not beaconSet then return end
    beaconSet = false
    C_Map.ClearUserWaypoint()
    if savedWaypoint then
        pcall(C_Map.SetUserWaypoint, savedWaypoint)
        savedWaypoint = nil
    end
end

local function UpdateBeacon()
    if not route then return end
    if not ns.db.beacon then
        ClearBeacon()
        return
    end
    local targetMap, target = ns.GetGuideTarget()
    if not UiMapPoint or not C_Map.CanSetUserWaypointOnMap(targetMap) then return end

    if not beaconSet and C_Map.HasUserWaypoint() then
        savedWaypoint = C_Map.GetUserWaypoint()
    end
    if not pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(targetMap, target.x, target.y)) then return end
    beaconSet = true

    -- The map pin alone is useful; tracking it is what draws the marker in
    -- the world. If the client refuses that call it reports it through the
    -- ADDON_ACTION events below, not through an error.
    if not beaconForbidden then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        if ns.db.debug then
            ns.Print("beacon tracking active: " .. tostring(C_SuperTrack.IsSuperTrackingUserWaypoint()))
        end
    end
end

ns.RefreshBeacon = UpdateBeacon

local ShowTarget

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, addon, functionName)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_CONTROL_GAINED" then
        if route then
            PlanTravel()
            ShowTarget()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if beaconRetry then
            beaconRetry = false
            UpdateBeacon()
        end
    elseif addon == addonName and ns.IsUsable(functionName) and functionName:find("SuperTrack", 1, true) then
        if event == "ADDON_ACTION_FORBIDDEN" then
            if not beaconForbidden then
                beaconForbidden = true
                ns.Print("This client does not let addons place the in-world marker. The arrow and the map pin still work.")
            end
        else
            beaconRetry = true
        end
    end
end)
for _, event in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED", "PLAYER_REGEN_ENABLED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED" }) do
    pcall(watcher.RegisterEvent, watcher, event)
end

---------------------------------------------------------------------------
-- Arrow panel
---------------------------------------------------------------------------

local nav = CreateFrame("Frame", "GatherTrailNavigator", UIParent)
nav:SetSize(250, 64)
nav:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
nav:SetMovable(true)
nav:SetClampedToScreen(true)
nav:EnableMouse(true)
nav:RegisterForDrag("LeftButton")
nav:SetScript("OnDragStart", nav.StartMoving)
nav:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    ns.db.navPosition = { point, relativePoint, x, y }
end)
nav:Hide()

local background = nav:CreateTexture(nil, "BACKGROUND")
background:SetAllPoints()
background:SetColorTexture(0, 0, 0, 0.6)

-- The arrow is three thick lines (shaft and two barbs) redrawn at the
-- current heading, so it needs no texture file. Up means straight ahead.
local arrow = CreateFrame("Frame", nil, nav)
arrow:SetSize(56, 56)
arrow:SetPoint("LEFT", nav, "LEFT", 4, 0)

local arrowLines = {}
for i = 1, 3 do
    local line = arrow:CreateLine(nil, "ARTWORK")
    line:SetThickness(5)
    line:SetColorTexture(1, 1, 1, 1)
    arrowLines[i] = line
end

local function DrawArrow(angle)
    -- Unit vector towards the node, and the one at right angles to it.
    local dx, dy = -math.sin(angle), math.cos(angle)
    local px, py = dy, -dx
    local headX, headY = dx * ARROW_HALF_LENGTH, dy * ARROW_HALF_LENGTH
    local baseX, baseY = headX - dx * ARROW_HEAD_LENGTH, headY - dy * ARROW_HEAD_LENGTH

    arrowLines[1]:SetStartPoint("CENTER", arrow, -headX, -headY)
    arrowLines[1]:SetEndPoint("CENTER", arrow, headX, headY)
    arrowLines[2]:SetStartPoint("CENTER", arrow, headX, headY)
    arrowLines[2]:SetEndPoint("CENTER", arrow, baseX + px * ARROW_HEAD_WIDTH, baseY + py * ARROW_HEAD_WIDTH)
    arrowLines[3]:SetStartPoint("CENTER", arrow, headX, headY)
    arrowLines[3]:SetEndPoint("CENTER", arrow, baseX - px * ARROW_HEAD_WIDTH, baseY - py * ARROW_HEAD_WIDTH)

    -- Green when heading straight at the node, through yellow, to red when
    -- it is directly behind.
    local off = math.abs((angle + math.pi) % (2 * math.pi) - math.pi) / math.pi
    local r, g = math.min(1, off * 2), math.min(1, (1 - off) * 2)
    for _, line in ipairs(arrowLines) do
        line:SetVertexColor(r, g, 0.1, 1)
    end
end

local title = nav:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", nav, "TOPLEFT", 66, -7)
title:SetPoint("RIGHT", nav, "RIGHT", -44, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)

local distanceText = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
distanceText:SetPoint("LEFT", nav, "LEFT", 66, -2)
distanceText:SetJustifyH("LEFT")

local detail = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
detail:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 66, 7)
detail:SetPoint("RIGHT", nav, "RIGHT", -6, 0)
detail:SetJustifyH("LEFT")
detail:SetWordWrap(false)

local function SmallButton(text, tooltip, onClick)
    local button = CreateFrame("Button", nil, nav)
    button:SetSize(18, 18)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.2)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

function ShowTarget()
    local _, target, travelling = ns.GetGuideTarget()
    title:SetText(travelling and target.text or ns.NodeName(target))
    UpdateBeacon()
    ns.RefreshPins()
end

-- The next stop after one that was not gathered too recently to be worth
-- going back to. nil when every stop was.
local function NextStop(from)
    local index = from
    for _ = 1, #route do
        index = index % #route + 1
        if not ns.IsFresh(route[index]) then return index end
    end
end

local function Advance(arrived)
    routeIndex = NextStop(routeIndex) or (routeIndex % #route + 1)
    if arrived and ns.db.sound then
        pcall(PlaySound, ARRIVE_SOUND, "SFX")
    end
    ShowTarget()
end

-- Moves the trip on to the given step, or ends it after the last one.
local function AdvanceTravel(index)
    if index > #travel then
        travel, travelIndex = nil, nil
    else
        travelIndex = index
    end
    if ns.db.sound then
        pcall(PlaySound, ARRIVE_SOUND, "SFX")
    end
    ShowTarget()
end

-- Reaching any later step counts too, so shortcuts are not punished.
local function CheckTravelProgress()
    for index = #travel, travelIndex, -1 do
        local step = travel[index]
        local sx, sy = ns.GetPlayerPositionOnMap(step.map)
        if sx and ns.Distance(step.map, sx, sy, step.x, step.y) < STEP_ARRIVE_YARDS then
            AdvanceTravel(index + 1)
            return true
        end
    end
    return false
end

local stopButton = SmallButton("x", "Stop the route", function()
    ns.StopRoute()
    ns.RefreshPins()
end)
stopButton:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -3, -3)

local skipButton = SmallButton(">", "Skip to the next node", function()
    ns.SkipNode()
end)
skipButton:SetPoint("RIGHT", stopButton, "LEFT", -2, 0)

local function FormatSeconds(seconds)
    if seconds >= 60 then
        return ("%dm %02ds"):format(seconds / 60, seconds % 60)
    end
    return ("%ds"):format(seconds)
end

local elapsedTotal = 0
nav:SetScript("OnUpdate", function(self, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 0.05 then return end
    elapsedTotal = 0

    if travel and CheckTravelProgress() then return end

    local targetMap, node, travelling = ns.GetGuideTarget()
    local px, py = ns.GetPlayerPositionOnMap(targetMap)
    if not px then
        distanceText:SetText("")
        detail:SetText("Travel to " .. ns.MapName(targetMap))
        arrow:Hide()
        return
    end

    local distance, east, south = ns.Distance(targetMap, px, py, node.x, node.y)
    if not travelling and distance < ns.ARRIVE_YARDS and #route > 1 then
        Advance(true)
        return
    end

    local speed = GetUnitSpeed("player")
    local eta = ns.IsUsable(speed) and speed > 0 and ("   " .. FormatSeconds(distance / speed)) or ""
    distanceText:SetText(("%d yd%s"):format(distance, eta))

    local inZone = px >= 0 and px <= 1 and py >= 0 and py <= 1
    if travelling then
        detail:SetText(("Step %d of %d to %s"):format(travelIndex, #travel, ns.MapName(routeMap)))
    elseif inZone then
        detail:SetText(("Stop %d of %d   %s"):format(routeIndex, #route,
            node.approx and "approximate spot" or ("gathered %dx"):format(node.count)))
    else
        detail:SetText("In " .. ns.MapName(routeMap))
    end

    -- Facing is 0 at north and grows counter-clockwise, so the angle here
    -- is how far to the left of straight ahead the node lies.
    local facing = GetPlayerFacing()
    if not ns.IsUsable(facing) then
        arrow:Hide()
        return
    end
    DrawArrow(math.atan2(-east, -south) - facing)
    arrow:Show()
end)

function ns.StartRoute(mapID, nodes)
    routeMap, route, routeIndex = mapID, nodes, 1
    if ns.IsFresh(route[1]) then
        routeIndex = NextStop(1) or 1
    end
    PlanTravel()
    ShowTarget()
    nav:Show()
end

function ns.StopRoute()
    routeMap, route, routeIndex = nil, nil, nil
    travel, travelIndex = nil, nil
    ClearBeacon()
    nav:Hide()
end

function ns.SkipNode()
    if not route then
        ns.Print("No route is active. Open /gt to start one.")
        return
    end
    if travel then
        AdvanceTravel(travelIndex + 1)
    else
        Advance(false)
    end
end

-- Returns the active route's map, node list, and current index.
function ns.GetRoute()
    return routeMap, route, routeIndex
end

-- Mining a node on the route moves the route on to the one after it.
function ns.OnNodeMined(node)
    if not route then return end
    for index, routeNode in ipairs(route) do
        if routeNode == node then
            routeIndex = index
            Advance(true)
            return
        end
    end
end

ns.onLogin[#ns.onLogin + 1] = function()
    local position = ns.db.navPosition
    if position then
        nav:ClearAllPoints()
        nav:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    end
end
