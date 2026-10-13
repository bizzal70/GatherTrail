local _, ns = ...

-- Learns how the world connects as the account's characters move through
-- it (flight masters, places where one zone was walked into another, and
-- transports such as boats), then plans trips over what it has learned.

local LINK_MERGE_YARDS = 80
-- A change of map with less movement than this between two ticks was walked.
local WALK_JUMP_YARDS = 120
-- A jump this soon after a spell cast is the spell's doing (hearthstone,
-- teleport), not a transport.
local TELEPORT_GRACE = 20
local SUMMON_GRACE = 120

-- Planning costs, in yards of running they are worth.
local WALK_LINK_COST = 5
local TRANSPORT_COST = 800
local FLIGHT_BASE_COST = 150
local FLIGHT_COST_PER_YARD = 0.35

local FLIGHT_CURRENT = Enum.FlightPathState and Enum.FlightPathState.Current or 0
local FLIGHT_REACHABLE = Enum.FlightPathState and Enum.FlightPathState.Reachable or 1

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

-- World position of a point given in map coordinates: the continent it is
-- on and two coordinates in yards. Every world position in this file comes
-- through here, so they are all in the same frame.
function ns.ToWorld(mapID, x, y)
    local inst, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not ns.IsUsable(inst) or not ns.IsUsable(pos) then return end
    local wx, wy = pos:GetXY()
    if not ns.IsUsable(wx) or not ns.IsUsable(wy) then return end
    return inst, wx, wy
end

local function Point(mapID, x, y)
    local inst, wx, wy = ns.ToWorld(mapID, x, y)
    if not inst then return end
    return { map = mapID, x = x, y = y, inst = inst, wx = wx, wy = wy }
end

local function Dist(p, q)
    local dx, dy = p.wx - q.wx, p.wy - q.wy
    return math.sqrt(dx * dx + dy * dy)
end

local function PlayerPoint()
    local mapID, x, y = ns.GetPlayerPosition()
    return mapID and Point(mapID, x, y) or nil
end

---------------------------------------------------------------------------
-- Flight masters
---------------------------------------------------------------------------

-- Flight paths are learned per character; where the flight masters stand is
-- shared by the whole account.
local function KnownFlights()
    local key = UnitGUID("player")
    if not ns.IsUsable(key) then key = "unknown" end
    local character = ns.db.chars[key]
    if not character then
        character = { known = {} }
        ns.db.chars[key] = character
    end
    return character.known
end

function ns.IsFlightKnown(nodeID)
    return KnownFlights()[nodeID] or false
end

-- A learned flight point this account has never stood at is placed from
-- the flight map, then moved onto the zone map it falls in.
local function PointFromTaxiMap(taxiMap, position)
    if not ns.IsUsable(position) then return end
    local tx, ty = position:GetXY()
    if not ns.IsUsable(tx) or not ns.IsUsable(ty) then return end
    local point = Point(taxiMap, tx, ty)
    if not point then return end

    local info = C_Map.GetMapInfoAtPosition(taxiMap, tx, ty)
    local zoneMap = info and info.mapID
    if ns.IsUsable(zoneMap) and zoneMap ~= taxiMap then
        local _, zonePos = C_Map.GetMapPosFromWorldPos(point.inst, CreateVector2D(point.wx, point.wy), zoneMap)
        if ns.IsUsable(zonePos) then
            local zx, zy = zonePos:GetXY()
            if ns.IsUsable(zx) and ns.IsUsable(zy) then
                point.map, point.x, point.y = zoneMap, zx, zy
            end
        end
    end
    return point
end

-- Opening the flight map means the character is standing at a flight
-- master, and lists every flight point they can use.
local function OnTaxiMapOpened()
    local taxiMap = GetTaxiMapID()
    if not ns.IsUsable(taxiMap) then return end
    local nodes = C_TaxiMap.GetAllTaxiNodes(taxiMap)
    if not nodes then return end

    local known = KnownFlights()
    local here = PlayerPoint()
    for _, node in ipairs(nodes) do
        local id, state = node.nodeID, node.state
        if ns.IsUsable(id) and ns.IsUsable(state) and (state == FLIGHT_CURRENT or state == FLIGHT_REACHABLE) then
            known[id] = true
            local name = ns.IsUsable(node.name) and node.name or "Flight master"
            local existing = ns.db.flights[id]
            if state == FLIGHT_CURRENT and here then
                if not existing or not existing.exact then
                    ns.Print(("Recorded flight master: %s."):format(name))
                end
                local point = Point(here.map, here.x, here.y)
                point.name, point.exact = name, true
                ns.db.flights[id] = point
            elseif not existing then
                local point = PointFromTaxiMap(taxiMap, node.position)
                if point then
                    point.name = name
                    ns.db.flights[id] = point
                end
            end
        end
    end
    ns.RefreshPins()
end

---------------------------------------------------------------------------
-- Zone connections
---------------------------------------------------------------------------

-- The client sometimes reports the whole continent as the player's map for
-- a moment (seen at login). Moving between that and a zone is not a
-- crossing, so connections are only kept between zone-level maps.
local ZONE_MAP_TYPE = Enum.UIMapType and Enum.UIMapType.Zone or 3

local function IsZoneLevel(mapID)
    local info = C_Map.GetMapInfo(mapID)
    local mapType = info and info.mapType
    return not ns.IsUsable(mapType) or mapType >= ZONE_MAP_TYPE
end

local function Near(p, q)
    return p.map == q.map and p.inst == q.inst and Dist(p, q) < LINK_MERGE_YARDS
end

local function Copy(p)
    return { map = p.map, x = p.x, y = p.y, inst = p.inst, wx = p.wx, wy = p.wy }
end

-- kind is "walk" (usable both ways) or "transport" (recorded one way; the
-- return trip is learned when it is taken).
local function RecordLink(kind, from, to)
    local pairKnown = false
    for _, link in ipairs(ns.db.links) do
        if link.kind == kind then
            local same = Near(link.a, from) and Near(link.b, to)
            local reversed = kind == "walk" and Near(link.a, to) and Near(link.b, from)
            if same or reversed then
                link.count = link.count + 1
                return
            end
            if (link.a.map == from.map and link.b.map == to.map)
                or (kind == "walk" and link.a.map == to.map and link.b.map == from.map) then
                pairKnown = true
            end
        end
    end
    ns.db.links[#ns.db.links + 1] = { kind = kind, a = Copy(from), b = Copy(to), count = 1 }
    if not pairKnown then
        ns.Print((kind == "walk" and "Learned the way from %s into %s." or "Learned a transport from %s to %s."):format(
            ns.MapName(from.map), ns.MapName(to.map)))
    end
end

-- Adds a flight master from imported data. An exact position beats one
-- placed from the flight map. Returns true if the record was usable.
function ns.ImportFlight(nodeID, mapID, x, y, exact, name)
    if not nodeID or not mapID or not x or not y then return false end
    local existing = ns.db.flights[nodeID]
    if existing and (existing.exact or not exact) then return true end
    local point = Point(mapID, x, y)
    if not point then return false end
    point.name, point.exact = name ~= "" and name or "Flight master", exact or nil
    ns.db.flights[nodeID] = point
    return true
end

-- Adds a connection from imported data, or raises the use count of one
-- already known. Returns true if the record was usable.
function ns.ImportLink(kind, aMap, ax, ay, bMap, bx, by, count)
    if (kind ~= "walk" and kind ~= "transport") or not aMap or not ax or not ay or not bMap or not bx or not by then
        return false
    end
    if not IsZoneLevel(aMap) or not IsZoneLevel(bMap) then return false end
    local from, to = Point(aMap, ax, ay), Point(bMap, bx, by)
    if not from or not to then return false end
    count = count or 1
    for _, link in ipairs(ns.db.links) do
        if link.kind == kind then
            local same = Near(link.a, from) and Near(link.b, to)
            local reversed = kind == "walk" and Near(link.a, to) and Near(link.b, from)
            if same or reversed then
                link.count = math.max(link.count, count)
                return true
            end
        end
    end
    ns.db.links[#ns.db.links + 1] = { kind = kind, a = from, b = to, count = count }
    return true
end

local last            -- where the character was on the previous tick
local riding = false  -- being carried: position changes while the character is not moving
local boardPoint      -- where the character was when the ride began
local lastCast, lastSummon = -1000, -1000

local function Tick()
    local current = PlayerPoint()
    -- No position (loading screen, instance): keep the last known one.
    if not current then return end

    -- Flights and corpse runs cross zones without showing a usable way.
    if UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then
        last, riding = current, false
        return
    end

    if last then
        local moved = current.inst == last.inst and Dist(current, last) or nil
        if current.map ~= last.map and IsZoneLevel(current.map) and IsZoneLevel(last.map) then
            if moved and moved < WALK_JUMP_YARDS then
                RecordLink("walk", last, current)
            elseif GetTime() - lastCast > TELEPORT_GRACE and GetTime() - lastSummon > SUMMON_GRACE then
                RecordLink("transport", riding and boardPoint or last, current)
            end
        end

        local speed = GetUnitSpeed("player")
        if ns.IsUsable(speed) then
            if speed > 0 then
                riding = false
            elseif not riding and moved and moved > 3 and moved < WALK_JUMP_YARDS then
                riding, boardPoint = true, last
            end
        end
    end
    last = current
end

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------

local function Vertex(point, extra)
    local vertex = Copy(point)
    for key, value in pairs(extra) do
        vertex[key] = value
    end
    return vertex
end

-- Cost of going straight from one vertex to another, and how. nil when
-- there is no known way.
local function Edge(u, v)
    if u.link and u.link == v.link then
        if u.link.kind == "walk" then
            return WALK_LINK_COST, "cross"
        elseif u.side == "a" and v.side == "b" then
            return TRANSPORT_COST, "transport"
        end
    end
    if u.inst ~= v.inst then return end
    local cost, mode
    -- On foot, only within one map: crossing between maps needs a known way.
    if u.map == v.map then
        cost, mode = Dist(u, v), "ground"
    end
    if u.flight and v.flight then
        local flightCost = FLIGHT_BASE_COST + Dist(u, v) * FLIGHT_COST_PER_YARD
        if not cost or flightCost < cost then
            cost, mode = flightCost, "fly"
        end
    end
    return cost, mode
end

local function StepText(vertex, mode)
    if mode == "fly" then
        return "Fly to " .. vertex.name
    elseif mode == "cross" then
        return "Cross into " .. ns.MapName(vertex.map)
    elseif mode == "transport" then
        return "Ride to " .. ns.MapName(vertex.map)
    elseif vertex.flight then
        return "Go to the " .. vertex.name .. " flight master"
    elseif vertex.link.kind == "walk" then
        return "Go to the crossing into " .. ns.MapName(vertex.otherMap)
    end
    return "Go to the transport to " .. ns.MapName(vertex.otherMap)
end

-- Works out the cheapest known way from where the character stands to
-- every flight master and connection, once. Returns nil when the
-- character's position is unavailable.
function ns.BuildTravelTree()
    local start = PlayerPoint()
    if not start then return end

    local vertices = { Vertex(start, {}) }
    for _, link in ipairs(ns.db.links) do
        vertices[#vertices + 1] = Vertex(link.a, { link = link, side = "a", otherMap = link.b.map })
        vertices[#vertices + 1] = Vertex(link.b, { link = link, side = "b", otherMap = link.a.map })
    end
    for nodeID in pairs(KnownFlights()) do
        local flight = ns.db.flights[nodeID]
        if flight then
            vertices[#vertices + 1] = Vertex(flight, { flight = true, name = flight.name })
        end
    end

    -- Dijkstra. The graph is small, so a plain scan for the nearest
    -- unvisited vertex is enough.
    local count = #vertices
    local cost, previous, mode, done = { 0 }, {}, {}, {}
    for _ = 1, count do
        local nearest
        for index = 1, count do
            if not done[index] and cost[index] and (not nearest or cost[index] < cost[nearest]) then
                nearest = index
            end
        end
        if not nearest then break end
        done[nearest] = true
        for index = 1, count do
            if not done[index] then
                local edgeCost, edgeMode = Edge(vertices[nearest], vertices[index])
                if edgeCost and (not cost[index] or cost[nearest] + edgeCost < cost[index]) then
                    cost[index] = cost[nearest] + edgeCost
                    previous[index], mode[index] = nearest, edgeMode
                end
            end
        end
    end

    local tree = {}

    -- The steps to get near a point, the total cost in yards, and where on
    -- the destination map the trip arrives (x, y, cost so far). The last
    -- stretch across the destination map is not a step; the caller guides
    -- that itself. Returns nil when no known way reaches that map.
    function tree:PathTo(mapID, x, y)
        local goal = Point(mapID, x, y)
        if not goal then return end
        local best, bestCost
        for index = 1, count do
            local vertex = vertices[index]
            if cost[index] and vertex.map == mapID and vertex.inst == goal.inst then
                local total = cost[index] + Dist(vertex, goal)
                if not bestCost or total < bestCost then
                    best, bestCost = index, total
                end
            end
        end
        if not best then return end

        local steps, index = {}, best
        while previous[index] do
            local vertex = vertices[index]
            table.insert(steps, 1, {
                travel = true,
                mode = mode[index],
                text = StepText(vertex, mode[index]),
                map = vertex.map, x = vertex.x, y = vertex.y,
            })
            index = previous[index]
        end
        local entry = vertices[best]
        return steps, bestCost, { x = entry.x, y = entry.y, cost = cost[best] }
    end

    return tree
end

function ns.PlanTravel(mapID, x, y)
    local tree = ns.BuildTravelTree()
    if tree then
        return tree:PathTo(mapID, x, y)
    end
end

-- "fly to Darkshire, cross into Deadwind Pass"
function ns.TravelSummary(steps)
    local parts = {}
    for _, step in ipairs(steps) do
        if step.mode ~= "ground" then
            parts[#parts + 1] = step.text:sub(1, 1):lower() .. step.text:sub(2)
        end
    end
    return table.concat(parts, ", ")
end

function ns.PrintTravelStats()
    local flights, exact = 0, 0
    for _, flight in pairs(ns.db.flights) do
        flights = flights + 1
        if flight.exact then exact = exact + 1 end
    end
    local known = 0
    for _ in pairs(KnownFlights()) do
        known = known + 1
    end
    local walks, transports = 0, 0
    for _, link in ipairs(ns.db.links) do
        if link.kind == "walk" then walks = walks + 1 else transports = transports + 1 end
    end
    ns.Print(("%d flight masters recorded (%d visited in person); this character can use %d."):format(flights, exact, known))
    ns.Print(("%d zone crossings and %d transports recorded."):format(walks, transports))
end

---------------------------------------------------------------------------

local handlers = {
    TAXIMAP_OPENED = OnTaxiMapOpened,
    CONFIRM_SUMMON = function() lastSummon = GetTime() end,
    UNIT_SPELLCAST_SUCCEEDED = function() lastCast = GetTime() end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event) handlers[event]() end)
pcall(frame.RegisterEvent, frame, "TAXIMAP_OPENED")
pcall(frame.RegisterEvent, frame, "CONFIRM_SUMMON")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

ns.onLogin[#ns.onLogin + 1] = function()
    -- Drop connections recorded to or from a continent-wide map by
    -- versions before 0.13.1.
    for index = #ns.db.links, 1, -1 do
        local link = ns.db.links[index]
        if not IsZoneLevel(link.a.map) or not IsZoneLevel(link.b.map) then
            table.remove(ns.db.links, index)
        end
    end
    C_Timer.NewTicker(1, Tick)
end
