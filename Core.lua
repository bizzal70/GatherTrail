local addonName, ns = ...

-- Two sightings closer than this are the same node.
ns.MERGE_YARDS = 12
-- A vein takes several strikes; strikes inside this window count as one visit.
ns.REVISIT_SECONDS = 120
-- A kind can widen that with mergeYards, where its position is looser.
-- Names versions before 0.14.2 recorded as ore because they contained
-- "Lode". A Lodestone is not a mining node.
local MISRECORDED = { Lodestone = true }

-- The layout of the saved data (records and settings alike). Whenever a
-- change means existing saved data has to be converted, raise this by one
-- and add the conversion to MIGRATIONS under the new number.
ns.DATA_VERSION = 2

-- MIGRATIONS[n] converts saved data from layout n - 1 to layout n. Each must
-- be safe to run on an account with no records at all.
local MIGRATIONS = {
    -- Layout 2: records of things mistaken for nodes are dropped.
    [2] = function(db)
        for _, nodes in pairs(db.nodes) do
            for index = #nodes, 1, -1 do
                local node = nodes[index]
                local onlyMistakes = next(node.names) ~= nil
                for name in pairs(node.names) do
                    if not MISRECORDED[name] then onlyMistakes = false end
                end
                if onlyMistakes and node.count == 0 then
                    table.remove(nodes, index)
                end
            end
        end
        for name in pairs(MISRECORDED) do
            db.skills[name] = nil
        end
    end,
}

-- Brings saved data up to the layout this version works with. Data saved
-- before the version number existed is layout 1. Data from a newer version
-- of the addon is left exactly as it is, and ns.dataFromNewer is set to its
-- layout so the player can be told.
function ns.MigrateData(db)
    local from = db.version or 1
    if from > ns.DATA_VERSION then
        ns.dataFromNewer = from
        return
    end
    for layout = from + 1, ns.DATA_VERSION do
        MIGRATIONS[layout](db)
        db.version = layout
    end
    db.version = ns.DATA_VERSION
end

-- "GatherTrail 0.16.0, saved data layout 2"
function ns.VersionText()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
    return ("GatherTrail %s, saved data layout %d"):format(
        ns.IsUsable(version) and version or "(unknown version)", ns.db.version or 1)
end
-- A node spotted from a distance is matched to the same ore within this range.
ns.APPROX_YARDS = 60
-- The navigator moves on to the next node once you are this close.
ns.ARRIVE_YARDS = 20
ns.ROUTE_MAX_NODES = 60

ns.onLogin = {}
-- Every node name in the saved data, used to recognise nodes on sight.
ns.knownNames = {}

-- GatherTrailDB is declared as SavedVariables (not SavedVariablesPerCharacter),
-- so every character on the account shares one node history.
local defaults = {
    debug = false,
    showPins = true,
    showMinimapPins = true,
    minimapDetect = true,
    -- Minutes a gathered node is left out of routes; 0 turns that off.
    skipRecentMinutes = 10,
    beacon = true,
    sound = true,
    minimapAngle = 3.6,
}

function ns.Print(msg)
    print("|cffd9a066GatherTrail|r: " .. tostring(msg))
end

-- Values can be secret on this client (mostly in combat). Secret values
-- cannot be compared or stored, so treat them as missing.
function ns.IsUsable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Returns mapID, x, y (map coordinates 0-1), or nil if unavailable.
function ns.GetPlayerPosition(mapID)
    mapID = mapID or C_Map.GetBestMapForUnit("player")
    if not ns.IsUsable(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not ns.IsUsable(pos) then return end
    local x, y = pos:GetXY()
    if not ns.IsUsable(x) or not ns.IsUsable(y) then return end
    return mapID, x, y
end

local mapContinents = {}

local function GetMapContinent(mapID)
    local continentID = mapContinents[mapID]
    if continentID == nil then
        continentID = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        continentID = ns.IsUsable(continentID) and continentID or false
        mapContinents[mapID] = continentID
    end
    return continentID
end

-- The player's position expressed in another map's coordinates, which may
-- fall outside 0-1 when the player is in a different zone. Returns nil when
-- the map is on another continent or the position is unavailable.
function ns.GetPlayerPositionOnMap(mapID)
    local _, x, y = ns.GetPlayerPosition(mapID)
    if x then return x, y end

    -- Convert through world coordinates, using the same pair of map
    -- functions in both directions so the result is self-consistent.
    local ownMap, ownX, ownY = ns.GetPlayerPosition()
    if not ownMap then return end
    local instanceID, worldX, worldY = ns.ToWorld(ownMap, ownX, ownY)
    if not instanceID or GetMapContinent(mapID) ~= instanceID then return end
    local _, pos = C_Map.GetMapPosFromWorldPos(instanceID, CreateVector2D(worldX, worldY), mapID)
    if not ns.IsUsable(pos) then return end
    x, y = pos:GetXY()
    if not ns.IsUsable(x) or not ns.IsUsable(y) then return end
    return x, y
end

local mapSizes = {}

-- Map size in yards, used to turn map coordinates into distances.
function ns.GetMapSize(mapID)
    local size = mapSizes[mapID]
    if not size then
        local width, height = C_Map.GetMapWorldSize(mapID)
        if not width or not height or width <= 0 or height <= 0 then
            width, height = 1500, 1000
        end
        size = { width, height }
        mapSizes[mapID] = size
    end
    return size[1], size[2]
end

-- Returns distance in yards, plus the east and south components.
function ns.Distance(mapID, x1, y1, x2, y2)
    local width, height = ns.GetMapSize(mapID)
    local dx, dy = (x2 - x1) * width, (y2 - y1) * height
    return math.sqrt(dx * dx + dy * dy), dx, dy
end

function ns.MapName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("map " .. tostring(mapID))
end

-- The ore type seen most often at this spot.
function ns.NodeName(node)
    local bestName, bestCount = "Unknown node", 0
    for name, count in pairs(node.names) do
        if count > bestCount then
            bestName, bestCount = name, count
        end
    end
    return bestName
end

-- Which profession gathers a node: "ore" or "herb". Nodes saved before
-- herbs were tracked have no field and are ore.
function ns.NodeProfession(node)
    return node.kind or "ore"
end

-- The nearest recorded node within maxYards, optionally of one profession.
local function NearestNode(mapID, x, y, maxYards, profession)
    local nodes = ns.db.nodes[mapID]
    if not nodes then return end
    local found, foundIndex, best = nil, nil, maxYards
    for index, node in ipairs(nodes) do
        if not profession or ns.NodeProfession(node) == profession then
            local distance = ns.Distance(mapID, x, y, node.x, node.y)
            if distance <= best then
                found, foundIndex, best = node, index, distance
            end
        end
    end
    return found, foundIndex
end

-- The recorded node of one kind at a place, if there is one.
function ns.FindNode(mapID, x, y, profession)
    return (NearestNode(mapID, x, y, ns.KINDS[profession].mergeYards or ns.MERGE_YARDS, profession))
end

-- Refills the list of node names recognised on sight from the saved data.
function ns.RebuildKnownNames()
    for name in pairs(ns.knownNames) do
        ns.knownNames[name] = nil
    end
    for _, nodes in pairs(ns.db.nodes) do
        for _, node in ipairs(nodes) do
            if not ns.KINDS[ns.NodeProfession(node)].notKnownByName then
                for name in pairs(node.names) do
                    ns.knownNames[name] = ns.NodeProfession(node)
                end
            end
        end
    end
end

-- Whether the maps should draw this node, going by its kind.
function ns.IsKindShown(node)
    return ns.db.showKinds[ns.NodeProfession(node)] ~= false
end

-- Whether a node was gathered so recently that a route should pass it by.
function ns.IsFresh(node)
    local minutes = ns.db.skipRecentMinutes or 0
    if minutes <= 0 or ns.KINDS[ns.NodeProfession(node)].neverStale or not node.lastMined then
        return false
    end
    return time() - node.lastMined < minutes * 60
end

-- Remembers whether this zone is friendly, contested or hostile for the
-- current character's faction, so other characters can be warned later.
local function RecordZoneStatus(mapID)
    local faction = UnitFactionGroup("player")
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if not ns.IsUsable(faction) or not ns.IsUsable(pvpType) then return end
    local zone = ns.db.zones[mapID]
    if not zone then
        zone = {}
        ns.db.zones[mapID] = zone
    end
    zone[faction] = pvpType
end

-- What each kind of evidence counts into, and how long before the same
-- node can be counted again.
local KINDS = {
    mined = { counter = "count", stamp = "lastMined", window = ns.REVISIT_SECONDS },
    failed = { counter = "fails", stamp = "lastFailed", window = ns.REVISIT_SECONDS },
    seen = { counter = "seen", stamp = "lastSeen", window = 600 },
}

-- Records evidence of a node at the player's position.
--   kind:   "mined" (successful gather), "failed" (attempt that did not
--           succeed), or "seen" (spotted without gathering, e.g. by an alt).
--   approx: true when the player may be standing some way from the node.
--           A later exact sighting of the same node nearby replaces the
--           approximate position.
--   profession: "ore" (default), "herb", "fish", "skin", "chest" or "rare".
-- Returns the node the evidence was added to.
--   offset: where the node is relative to the player, instead of under
--           their feet. A number is yards straight ahead (a fishing pool is
--           out in the water); a table { east =, north = } is yards on the
--           map (a blip pointed at on the minimap); a table { x =, y = }
--           is a known place in map coordinates (a marker the game shows).
function ns.RecordNode(name, kind, approx, profession, offset)
    local info = KINDS[kind or "mined"]
    profession = profession or "ore"
    local mapID, x, y = ns.GetPlayerPosition()
    if mapID and offset then
        local width, height = ns.GetMapSize(mapID)
        if type(offset) == "table" and offset.x then
            x, y = offset.x, offset.y
        elseif type(offset) == "table" then
            -- Map y grows south.
            x = x + offset.east / width
            y = y - offset.north / height
        else
            local facing = GetPlayerFacing()
            if ns.IsUsable(facing) then
                -- Facing is 0 at north and grows counter-clockwise.
                x = x - math.sin(facing) * offset / width
                y = y - math.cos(facing) * offset / height
            end
        end
    end
    if not mapID then
        if kind ~= "seen" then
            ns.Print("Could not read your position, so this node was not recorded.")
        end
        return
    end

    local nodes = ns.db.nodes[mapID]
    if not nodes then
        nodes = {}
        ns.db.nodes[mapID] = nodes
    end

    local now = time()
    -- A herb beside a vein is a separate node, so only match the same profession.
    local node = NearestNode(mapID, x, y, ns.KINDS[profession].mergeYards or ns.MERGE_YARDS, profession)
    if not node then
        -- An approximate sighting belongs to any nearby node of that name,
        -- and an exact one pins down a nearby approximate node.
        local best = ns.APPROX_YARDS
        for _, candidate in ipairs(nodes) do
            if candidate.names[name] and ns.NodeProfession(candidate) == profession
                and (approx or candidate.approx) then
                local distance = ns.Distance(mapID, x, y, candidate.x, candidate.y)
                if distance <= best then
                    node, best = candidate, distance
                end
            end
        end
    end

    local isNew = not node
    if isNew then
        node = { x = x, y = y, count = 0, first = now, last = 0, names = {}, approx = approx or nil,
            kind = profession ~= "ore" and profession or nil }
        nodes[#nodes + 1] = node
    elseif node.approx and not approx then
        node.x, node.y, node.approx = x, y, nil
    end

    -- Each skinned creature is a separate find, so skins are never held back
    -- as repeats of one visit.
    local window = ns.KINDS[profession].repeatsAtOnce and 0 or info.window
    if now - (node[info.stamp] or 0) >= window then
        node[info.counter] = (node[info.counter] or 0) + 1
        node[info.stamp] = now
        node.names[name] = (node.names[name] or 0) + 1
        local quiet = ns.KINDS[profession].quietAfterFirst
        if quiet then
            -- Found over and over in one place: only the first is announced.
            if isNew then
                ns.Print(quiet:format(name, ns.MapName(mapID)))
            end
        elseif kind == "seen" then
            if isNew then
                ns.Print(("Spotted %s in %s%s."):format(name, ns.MapName(mapID),
                    approx and " (approximate location)" or ""))
            end
        elseif kind == "failed" then
            ns.Print(("Noted %s in %s (not mined)."):format(name, ns.MapName(mapID)))
        elseif isNew then
            ns.Print(("New node: %s in %s (%d known here)."):format(name, ns.MapName(mapID), #nodes))
        else
            ns.Print(("%s, visit %d."):format(name, node.count))
        end
    end
    node.last = now
    if not ns.KINDS[profession].notKnownByName then
        ns.knownNames[name] = profession
    end
    RecordZoneStatus(mapID)

    -- Only actually gathering a node moves a route past it; pointing at it
    -- from a distance does not.
    if (kind or "mined") == "mined" then
        ns.NoteGathered(name, profession)
        ns.OnNodeMined(node)
    end
    ns.RefreshPins()
    ns.RefreshWindow()
    return node
end

local function StartZoneRoute(minVisits)
    local mapID, x, y = ns.GetPlayerPosition()
    if not mapID then
        ns.Print("Could not read your position.")
        return
    end
    local pool = {}
    for _, node in ipairs(ns.db.nodes[mapID] or {}) do
        if node.count >= minVisits then
            pool[#pool + 1] = node
        end
    end
    local route, length = ns.BuildRoute(mapID, x, y, pool)
    if #route == 0 then
        ns.Print(("No nodes mined at least %d times recorded in %s yet."):format(minVisits, ns.MapName(mapID)))
        return
    end
    ns.StartRoute(mapID, route)
    ns.Print(("Route through %d nodes in %s, about %d yards per loop."):format(#route, ns.MapName(mapID), length))
end

local function PrintStats()
    local zones, total = 0, 0
    for _, nodes in pairs(ns.db.nodes) do
        if #nodes > 0 then
            zones = zones + 1
            total = total + #nodes
        end
    end
    ns.Print(("%d nodes recorded across %d zones."):format(total, zones))

    local mapID = ns.GetPlayerPosition()
    local nodes = mapID and ns.db.nodes[mapID]
    if nodes and #nodes > 0 then
        local visits = 0
        for _, node in ipairs(nodes) do
            visits = visits + node.count
        end
        ns.Print(("%s: %d nodes, %d visits."):format(ns.MapName(mapID), #nodes, visits))
    end
end

function ns.ForgetNearest()
    local mapID, x, y = ns.GetPlayerPosition()
    if not mapID then return end
    local node, index = NearestNode(mapID, x, y, 30)
    if not node then
        ns.Print("No recorded node within 30 yards.")
        return
    end
    table.remove(ns.db.nodes[mapID], index)
    ns.StopRoute()
    ns.RefreshPins()
    ns.RefreshWindow()
    ns.Print(("Forgot %s."):format(ns.NodeName(node)))
end

local function PrintHelp()
    ns.Print("/gt - open the GatherTrail window")
    ns.Print("/gt route [min times mined] - route through every node in this zone")
    ns.Print("/gt skip - skip to the next node on the route")
    ns.Print("/gt stop - stop the route")
    ns.Print("/gt stats - how many nodes are recorded")
    ns.Print("/gt version - the addon's version and the layout of its saved data")
    ns.Print("/gt zone - what is known about this zone's level and faction, and from where")
    ns.Print("/gt travel - how many flight masters and zone connections are recorded")
    ns.Print("/gt travel clear - forget recorded transports (boats and the like)")
    ns.Print("/gt show [kind] - show or hide one kind of pin: ore, herb, fish, skin, chest, rare")
    ns.Print("/gt pins - show or hide nodes on the world map")
    ns.Print("/gt minimap - show or hide nodes on the minimap")
    ns.Print("/gt detect - record nodes you point at on the minimap, on or off")
    ns.Print("/gt beacon - turn the in-world marker on the next node on or off")
    ns.Print("/gt sound - turn the arrival sound on or off")
    ns.Print("/gt add [name] - record an ore node where you stand (/gt add herb, fish, skin, chest or rare [name] for the others)")
    ns.Print("/gt forget - delete the recorded node nearest to you")
    ns.Print("/gt debug - print every spell cast, to diagnose nodes not recording")
end

SLASH_GATHERTRAIL1 = "/gt"
SLASH_GATHERTRAIL2 = "/gather"
SLASH_GATHERTRAIL3 = "/gathertrail"
SlashCmdList.GATHERTRAIL = function(msg)
    local command, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        ns.ToggleWindow()
    elseif command == "route" then
        StartZoneRoute(tonumber(rest) or 0)
    elseif command == "skip" then
        ns.SkipNode()
    elseif command == "stop" then
        ns.StopRoute()
        ns.RefreshPins()
        ns.Print("Route stopped.")
    elseif command == "stats" then
        PrintStats()
    elseif command == "version" then
        ns.Print(ns.VersionText() .. ".")
    elseif command == "zone" then
        ns.PrintZoneInfo()
    elseif command == "travel" then
        if rest:lower() == "clear" then
            -- Transports are the one kind of connection that can be learned
            -- wrongly (an unexplained jump looks like a boat ride).
            for index = #ns.db.links, 1, -1 do
                if ns.db.links[index].kind == "transport" then
                    table.remove(ns.db.links, index)
                end
            end
            ns.RefreshPins()
            ns.Print("Recorded transports cleared.")
        else
            ns.PrintTravelStats()
        end
    elseif command == "pins" then
        ns.db.showPins = not ns.db.showPins
        ns.RefreshPins()
        ns.Print("World map pins " .. (ns.db.showPins and "on." or "off."))
    elseif command == "minimap" then
        ns.db.showMinimapPins = not ns.db.showMinimapPins
        ns.RefreshMinimapPins()
        ns.Print("Minimap pins " .. (ns.db.showMinimapPins and "on." or "off."))
    elseif command == "detect" then
        ns.db.minimapDetect = not ns.db.minimapDetect
        ns.Print("Recording nodes pointed at on the minimap " .. (ns.db.minimapDetect and "on." or "off."))
    elseif command == "beacon" then
        ns.db.beacon = not ns.db.beacon
        ns.RefreshBeacon()
        ns.Print("In-world marker " .. (ns.db.beacon and "on." or "off."))
    elseif command == "sound" then
        ns.db.sound = not ns.db.sound
        ns.Print("Arrival sound " .. (ns.db.sound and "on." or "off."))
    elseif command == "add" then
        -- "/gt add herb Peacebloom" records a herb, and likewise for the
        -- other kinds; with no kind given it is ore.
        local kind, kindName = rest:match("^(%a+)%s*(.*)$")
        kind = kind and kind:lower()
        if kind ~= "ore" and ns.KINDS[kind] then
            ns.RecordNode(kindName ~= "" and kindName or ("Manual " .. kind), "mined", false, kind)
        else
            ns.RecordNode(rest ~= "" and rest or "Manual node")
        end
    elseif command == "forget" then
        ns.ForgetNearest()
    elseif command == "show" then
        local kind = rest:lower()
        if ns.KINDS[kind] then
            ns.db.showKinds[kind] = not ns.db.showKinds[kind]
            ns.RefreshPins()
            ns.RefreshMinimapPins()
            ns.Print(("%s pins %s."):format(kind, ns.db.showKinds[kind] and "shown" or "hidden"))
        else
            ns.Print("Use /gt show ore, herb, fish, skin, chest or rare.")
        end
    elseif command == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("Debug " .. (ns.db.debug and "on." or "off."))
    else
        PrintHelp()
    end
end

-- Entry in the minimap's addon list.
function GatherTrail_OnAddonCompartmentClick()
    ns.ToggleWindow()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        GatherTrailDB = GatherTrailDB or {}
        for key, value in pairs(defaults) do
            if GatherTrailDB[key] == nil then
                GatherTrailDB[key] = value
            end
        end
        GatherTrailDB.nodes = GatherTrailDB.nodes or {}
        GatherTrailDB.zones = GatherTrailDB.zones or {}
        GatherTrailDB.flights = GatherTrailDB.flights or {}
        GatherTrailDB.skills = GatherTrailDB.skills or {}
        -- Which kinds of node are drawn on the maps.
        GatherTrailDB.showKinds = GatherTrailDB.showKinds or {}
        for kind in pairs(ns.KINDS) do
            if GatherTrailDB.showKinds[kind] == nil then
                GatherTrailDB.showKinds[kind] = true
            end
        end
        GatherTrailDB.links = GatherTrailDB.links or {}
        GatherTrailDB.chars = GatherTrailDB.chars or {}
        ns.db = GatherTrailDB
        ns.MigrateData(ns.db)
        ns.RebuildKnownNames()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        if ns.dataFromNewer then
            ns.Print(("Your saved records were written by a newer GatherTrail (layout %d; this version understands %d). Update the addon before relying on it, or records may be misread."):format(
                ns.dataFromNewer, ns.DATA_VERSION))
        end
        for _, init in ipairs(ns.onLogin) do
            init()
        end
    end
end)
