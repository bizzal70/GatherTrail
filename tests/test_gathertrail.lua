local ns = LoadAddon(ADDON_DIR, "GatherTrail")
local P = PLAYER
local function check(cond, what) if not cond then error("CHECK FAILED: " .. what, 2) end; io.write("pass  ", what, "\n") end
local function mine(name, guid, ok)
    Fire("UNIT_SPELLCAST_SENT", "player", name, guid, 7777)
    Fire(ok and "UNIT_SPELLCAST_SUCCEEDED" or "UNIT_SPELLCAST_INTERRUPTED", "player", guid, 7777)
end

-- saved data from an older version: a node, a thing once mistaken for a
-- node, and a bogus connection between the continent map and a zone
GatherTrailDB = {
    nodes = {
        [2521] = { { x = 0.3632886409759522, y = 0.5979678630828857, count = 0, first = 1, last = 1, names = { ["Copper Vein"] = 1 } } },
        [77] = { { x = 0.5, y = 0.5, count = 0, seen = 1, approx = true, first = 1, last = 1, names = { Lodestone = 1 } } },
    },
    links = { { kind = "walk", count = 1,
        a = { map = 10, x = 0.5, y = 0.5, inst = 0, wx = 0, wy = 0 },
        b = { map = 1, x = 0.5, y = 0.5, inst = 0, wx = 0, wy = 0 } } },
}
Fire("ADDON_LOADED", "GatherTrail"); Fire("PLAYER_LOGIN")
check(GatherTrailDB and ns.db == GatherTrailDB, "saved variables initialised")
check(#ns.db.nodes[2521] == 1, "records already saved are kept")
check(#ns.db.links == 0, "a connection recorded against the continent map is dropped")
check(#ns.db.nodes[77] == 0 and ns.ClassifyNodeName("Lodestone") == nil, "a Lodestone is no longer taken for an ore node, and the one recorded is removed")
check(ns.ClassifyNodeName("Small Thorium Vein") == "ore" and ns.ClassifyNodeName("Mithril Deposit") == "ore" and ns.ClassifyNodeName("Whirlpool") == nil and ns.ClassifyNodeName("Oil Spill") == "fish", "node names are matched on whole words")
ns.db.nodes[2521] = nil
check(ns.db.skipRecentMinutes == 10, "new settings get their defaults")
check(ns.db.version == ns.DATA_VERSION and ns.DATA_VERSION >= 2, "saved data from before version numbers is brought up to the current layout")
do
    local lodestone = { x = 0.5, y = 0.5, count = 0, seen = 1, names = { Lodestone = 1 } }
    local mined = { x = 0.6, y = 0.5, count = 2, names = { Lodestone = 2 } }
    local old = { version = 1, nodes = { [5] = { lodestone, mined } }, skills = { Lodestone = { gotAt = 1 } } }
    ns.MigrateData(old)
    check(old.version == ns.DATA_VERSION and #old.nodes[5] == 1 and old.nodes[5][1] == mined and old.skills.Lodestone == nil, "each layout step converts the data and records the new number")
    ns.MigrateData(old)
    check(old.version == ns.DATA_VERSION and #old.nodes[5] == 1, "data already at the current layout is left alone")
    local empty = { nodes = {}, skills = {} }
    ns.MigrateData(empty)
    check(empty.version == ns.DATA_VERSION, "a new account starts at the current layout")
    local newer = { version = ns.DATA_VERSION + 5, nodes = { [5] = { lodestone } }, skills = {} }
    ns.MigrateData(newer)
    check(newer.version == ns.DATA_VERSION + 5 and #newer.nodes[5] == 1 and ns.dataFromNewer == ns.DATA_VERSION + 5, "data from a newer version of the addon is not touched, and is flagged")
    ns.dataFromNewer = nil
    SlashCmdList.GATHERTRAIL("version")
    check(PRINTED[#PRINTED]:find("0.0.0-test, saved data layout " .. ns.DATA_VERSION, 1, true) ~= nil, "/gt version reports the addon version and data layout")
end
ns.db.skipRecentMinutes = 0   -- the route tests below revisit nodes at once; freshness has its own test

mine("Copper Vein", "g1", true)
check(#ns.db.nodes[1] == 1 and ns.db.nodes[1][1].count == 1, "successful mine recorded")
mine("Copper Vein", "g2", true)
check(#ns.db.nodes[1] == 1 and ns.db.nodes[1][1].count == 1, "second strike inside window not double counted")
Fire("UNIT_SPELLCAST_SENT", "player", nil, "g3", 1); Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g3", 1)
check(#ns.db.nodes[1] == 1, "non-mining cast ignored")

P.x = 0.7
mine("Copper Vein", "g4", false)
check(#ns.db.nodes[1] == 2 and ns.db.nodes[1][2].fails == 1 and ns.db.nodes[1][2].count == 0 and not ns.db.nodes[1][2].approx, "interrupted cast recorded as exact failed attempt")

-- alt without mining hovers a node
P.x, P.y = 0.3, 0.3
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Tin Vein"; GameTooltipTextLeft2.__text = "Requires Mining"
GameTooltip.__scripts.OnShow(GameTooltip)
local tin = ns.db.nodes[1][3]
check(tin and tin.seen == 1 and tin.approx == true and tin.count == 0, "hover sighting recorded as approximate")
P.x = 0.32
GameTooltip.__scripts.OnShow(GameTooltip)
check(#ns.db.nodes[1] == 3, "repeat sighting nearby merges")
-- alt right-clicks it
Fire("UI_ERROR_MESSAGE", 50, "Requires Mining")
check(#ns.db.nodes[1] == 3 and tin.fails == 1 and tin.approx == true, "skill error recorded as failed attempt, still approximate")
GameTooltip.__shown = false
-- miner later mines it 30 yards away
P.x = 0.33
mine("Tin Vein", "g5", true)
check(#ns.db.nodes[1] == 3 and tin.count == 1 and tin.approx == nil and tin.x == 0.33, "exact mine pins down approximate node")
-- hovering a non-node does nothing
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Mailbox"; GameTooltipTextLeft2.__shown = false
GameTooltip.__scripts.OnShow(GameTooltip)
check(#ns.db.nodes[1] == 3, "non-node tooltip ignored")
GameTooltip.__shown = false

for i = 1, 8 do P.x, P.y = 0.1 + i * 0.09, 0.2 + ((i * 37) % 50) / 100; SlashCmdList.GATHERTRAIL("add Copper Vein") end
check(#ns.db.nodes[1] == 11, "manual adds")
P.map = 2
for i = 1, 3 do P.x, P.y = 0.2 + i * 0.02, 0.5; SlashCmdList.GATHERTRAIL("add Iron Deposit") end
P.map = 3; P.x, P.y = 0.5, 0.5; SlashCmdList.GATHERTRAIL("add Copper Vein")
check(ns.db.zones[2].Alliance == "hostile", "zone faction status recorded")

P.map, P.x, P.y = 1, 0.5, 0.5
local types, total = ns.GetNodeTypes()
check(total == 15 and #types == 3, "ore types: " .. #types .. " types, " .. total .. " nodes")
local ranked = ns.RankZones({})
check(#ranked == 3 and ranked[1].mapID == 1, "ranking puts current well-stocked zone first")
for _, z in ipairs(ranked) do io.write(("      %s nodes=%d loop=%d travel=%s tooHigh=%s pvp=%s score=%.2f\n"):format(z.name, z.nodeCount, z.loop, tostring(z.travel and math.floor(z.travel)), tostring(z.tooHigh), tostring(z.pvp), z.score)) end
local z2, z3
for _, z in ipairs(ranked) do if z.mapID == 2 then z2 = z elseif z.mapID == 3 then z3 = z end end
check(z2.tooHigh and z2.pvp == "hostile" and z2.travel, "level and faction flags on zone 2, reachable by land")
check(z3.travel == nil, "other continent has no land distance")
local ironOnly = ns.RankZones({ ["Iron Deposit"] = true })
check(#ironOnly == 1 and ironOnly[1].mapID == 2, "filter by ore type")

-- route sanity: every node once
local r = ranked[1].route
local seen = {}; for _, n in ipairs(r) do assert(not seen[n]); seen[n] = true end
check(#r == 11, "route visits each node once")

SlashCmdList.GATHERTRAIL("")
check(GatherTrailWindow:IsShown(), "window opens")
-- click everything clickable in the UI
local clicks = 0
for _, f in ipairs(Frames()) do
    local label = rawget(f, "label")
    local isOptions = label and label.__text == "Options"   -- the options page has its own test
    if f.__scripts.OnClick and f.__shown ~= false and f ~= GatherTrailMinimapButton and not isOptions then
        if not GatherTrailWindow:IsShown() then SlashCmdList.GATHERTRAIL("") end
        if f.__scripts.OnEnter then f.__scripts.OnEnter(f) end   -- row and button tooltips
        f.__scripts.OnClick(f, "LeftButton"); clicks = clicks + 1
    end
end
check(clicks > 5, "clicked " .. clicks .. " UI controls without error")
local mb = GatherTrailMinimapButton
mb.__scripts.OnClick(mb, "LeftButton")
mb.__scripts.OnEnter(mb)
mb.__scripts.OnDragStart(mb); mb.__scripts.OnUpdate(mb, 0.1); mb.__scripts.OnDragStop(mb)
check(type(ns.db.minimapAngle) == "number", "minimap button drag")

-- beacon: the player's own pin is kept and restored
ns.StopRoute()
local ownPin = { 9, 0.1, 0.1 }
WAYPOINT = ownPin
ns.StartRoute(2, z2.route)
check(WAYPOINT[1] == 2 and WAYPOINT[2] == z2.route[1].x and SUPERTRACKED == true, "beacon placed on first node in another zone and tracked")
local nav = GatherTrailNavigator
nav.__scripts.OnUpdate(nav, 0.2)
ns.StartRoute(3, z3.route); nav.__scripts.OnUpdate(nav, 0.2)
SlashCmdList.GATHERTRAIL("route")
local _, route, index = ns.GetRoute()
check(route and index == 1, "zone route started")
P.x, P.y = route[1].x + 0.3, route[1].y
nav.__scripts.OnUpdate(nav, 0.2)
check(select(3, ns.GetRoute()) == 1, "no advance while far from the node")
P.x, P.y = route[1].x, route[1].y
local soundsBefore = SOUNDS
nav.__scripts.OnUpdate(nav, 0.2)
check(select(3, ns.GetRoute()) == 2, "arrival advances route")
check(SOUNDS == soundsBefore + 1, "arrival plays a sound")
check(WAYPOINT[2] == route[2].x and WAYPOINT[3] == route[2].y, "beacon follows the route to the next node")
-- draw the arrow at a few headings
for _, facing in ipairs({ 0, 1.5, 3.1, 4.7, 6.2 }) do
    P.x, P.y, P.facing = route[2].x + 0.1, route[2].y + 0.2, facing
    nav.__scripts.OnUpdate(nav, 0.2)
end
SlashCmdList.GATHERTRAIL("beacon")
check(WAYPOINT == ownPin and not ns.db.beacon, "turning the beacon off restores the player's own pin")
SlashCmdList.GATHERTRAIL("beacon")
check(WAYPOINT[1] == 1 and SUPERTRACKED == true, "turning it back on re-places it")
-- client refuses the tracking call
Fire("ADDON_ACTION_FORBIDDEN", "GatherTrail", "C_SuperTrack.SetSuperTrackedUserWaypoint()")
SUPERTRACKED = false
SlashCmdList.GATHERTRAIL("skip")
check(SUPERTRACKED == false and WAYPOINT[2] == route[3].x, "after a refusal: map pin still moves, tracking no longer attempted")
SlashCmdList.GATHERTRAIL("stop")
check(WAYPOINT == ownPin, "stopping the route restores the player's own pin")
SlashCmdList.GATHERTRAIL("sound"); SlashCmdList.GATHERTRAIL("sound")
SlashCmdList.GATHERTRAIL("route")
_, route = ns.GetRoute()
WorldMapFrame.__shown = true
ns.RefreshPins()
for _, f in ipairs(Frames()) do if rawget(f, "node") and f.__scripts.OnEnter then f.__scripts.OnEnter(f); break end end
for _, cmd in ipairs({ "skip", "stats", "pins", "pins", "debug", "debug", "help", "forget", "stop", "route 5" }) do SlashCmdList.GATHERTRAIL(cmd) end
GatherTrail_OnAddonCompartmentClick()
mb.__scripts.OnClick(mb, "RightButton")
check(true, "slash commands, pins and compartment entry ran")
-- world map route: numbered stops, legs, player line
P.map, P.x, P.y = 1, 0.5, 0.5
SlashCmdList.GATHERTRAIL("route")
local _, mapRoute, mapIndex = ns.GetRoute()
WorldMapFrame.__shown = true
ns.RefreshPins()
local stopPins, plainPins = 0, 0
for _, f in ipairs(Frames()) do
    if rawget(f, "label") and rawget(f, "node") and f.__shown then
        if rawget(f, "stop") then
            stopPins = stopPins + 1
            assert(f.label.__text == tostring(f.stop), "stop label")
            assert(mapRoute[f.stop] == f.node, "stop number matches route order")
            f.__scripts.OnEnter(f)
        else
            plainPins = plainPins + 1
            assert(f.label.__text == "", "plain pin has no number")
        end
    end
end
check(stopPins == #mapRoute and stopPins + plainPins == #ns.db.nodes[1], ("world map numbers %d stops and shows %d other nodes"):format(stopPins, plainPins))
for _, f in ipairs(Frames()) do
    if f.__scripts.OnUpdate then f.__scripts.OnUpdate(f, 0.2) end
end
P.map = 2; ns.RefreshPins()   -- viewing a map the route is not on
for _, f in ipairs(Frames()) do
    if f.__scripts.OnUpdate then f.__scripts.OnUpdate(f, 0.2) end
end
check(true, "map and player line redraw on and off the route's map")

-- minimap pins: stub minimap is 140 wide showing 100 yards, so 0.7 px per yard
ns.StopRoute()
P.map, P.y, P.facing = 5, 0.5, 0
P.x = 0.55; SlashCmdList.GATHERTRAIL("add Near Vein")   -- 50 yards east of centre
P.x = 0.90; SlashCmdList.GATHERTRAIL("add Far Vein")    -- 400 yards east
P.x = 0.50
local function minimapPins()
    local shown = {}
    for _, f in ipairs(Frames()) do
        if rawget(f, "minimapPin") and f.__shown then shown[#shown + 1] = f end
    end
    return shown
end
local function near(a, b) return math.abs(a - b) < 0.01 end
ns.RefreshMinimapPins()
local shown = minimapPins()
check(#shown == 1 and ns.NodeName(shown[1].node) == "Near Vein", "minimap shows the node in range and hides the one out of range")
check(near(shown[1].__point[4], 35) and near(shown[1].__point[5], 0), "node to the east sits right of centre")
ROTATE_MINIMAP, P.facing = "1", math.pi / 2          -- facing west, so east is behind
ns.RefreshMinimapPins()
shown = minimapPins()
check(near(shown[1].__point[4], 0) and near(shown[1].__point[5], -35), "rotating minimap puts a node behind the player at the bottom")
ROTATE_MINIMAP, P.facing = "0", 0
ns.StartRoute(5, { ns.db.nodes[5][2] })
ns.RefreshMinimapPins()
shown = minimapPins()
local rim = shown[#shown]
check(#shown == 2 and ns.NodeName(rim.node) == "Far Vein" and near(rim.__point[4], 65) and near(rim.__point[5], 0), "route target out of range is held on the rim")
shown[1].__scripts.OnEnter(shown[1])
SlashCmdList.GATHERTRAIL("minimap")
check(#minimapPins() == 0, "minimap pins can be turned off")
SlashCmdList.GATHERTRAIL("minimap")
ns.StopRoute()

-- travel knowledge -------------------------------------------------------
local tick = TICKERS[1]
check(type(tick) == "function", "movement tracker started at login")
local function has(steps, i, text) return steps[i] and steps[i].text:find(text, 1, true) ~= nil end
local nav = GatherTrailNavigator

-- flight masters: standing at Alpha in zone 1; Beta (zone 2) is learned but
-- never visited; Gamma is not learned
P.map, P.x, P.y = 1, 0.2, 0.2
TAXI_NODES = {
    { nodeID = 101, name = "Alpha", state = 0, position = CreateVector2D(0.84, 0.2) },
    { nodeID = 102, name = "Beta", state = 1, position = CreateVector2D(0.7, 0.5) },
    { nodeID = 103, name = "Gamma", state = 2, position = CreateVector2D(0.1, 0.5) },
}
Fire("TAXIMAP_OPENED")
local alpha, beta = ns.db.flights[101], ns.db.flights[102]
check(alpha and alpha.exact and alpha.map == 1 and alpha.x == 0.2, "flight master recorded where the character stands")
check(beta and not beta.exact and beta.map == 2 and near(beta.x, 0.5), "learned flight point placed on its zone map from the flight map")
check(ns.db.flights[103] == nil and ns.IsFlightKnown(101) and ns.IsFlightKnown(102) and not ns.IsFlightKnown(103), "unlearned flight point ignored")

-- walking across the border between zone 1 and zone 2
P.map, P.x, P.y = 1, 0.02, 0.5; tick()
P.map, P.x, P.y = 2, 0.99, 0.5; tick()
check(#ns.db.links == 1 and ns.db.links[1].kind == "walk", "walking between zones records a crossing")
P.map, P.x = 1, 0.02; tick()
check(#ns.db.links == 1 and ns.db.links[1].count == 2, "walking back reuses the same crossing")

-- things that must not create connections
ON_TAXI = true; P.map, P.x, P.y = 10, 0.5, 0.5; tick(); ON_TAXI = false; tick()
P.map, P.x = 5, 0.5; tick()   -- the same spot, reported first as the continent and then as its zone
check(#ns.db.links == 1, "the map flipping between continent and zone records no connection")
ON_TAXI = true; P.map, P.x = 5, 0.5; tick(); ON_TAXI = false; tick()
check(#ns.db.links == 1, "taking a flight records no connection")
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "hearth", 1)
P.map, P.x = 1, 0.5; tick()
check(#ns.db.links == 1, "a teleport spell records no connection")
IS_DEAD = true; P.map, P.x = 2, 0.99; tick(); IS_DEAD = false; tick()
check(#ns.db.links == 1, "a corpse run records no connection")

-- planning: flying beats walking when the character knows the flights
P.map, P.x, P.y = 1, 0.6, 0.5
local steps, cost = ns.PlanTravel(2, 0.5, 0.5)
check(steps and #steps == 2 and has(steps, 1, "Alpha flight master") and has(steps, 2, "Fly to Beta"), "plan uses the flight: " .. ns.TravelSummary(steps))
PLAYER_GUID = "Player-2"   -- an alt who has learned no flights
steps = ns.PlanTravel(2, 0.5, 0.5)
check(steps and #steps == 2 and has(steps, 1, "crossing into Zone2") and has(steps, 2, "Cross into Zone2"), "alt without flights is sent over the crossing")
check(ns.PlanTravel(5, 0.5, 0.5) == nil, "no plan to a zone nothing connects to")
PLAYER_GUID = "Player-1"

-- a boat: carried while standing still, then a different continent
NOW = NOW + 300   -- well clear of the teleport spell above
ON_TAXI = true; P.map, P.x, P.y = 1, 0.9, 0.9; tick(); ON_TAXI = false   -- get to the dock without leaving a trace
SPEED = 7; tick()
SPEED = 0; P.x = 0.92; tick(); P.x = 0.95; tick()
P.map, P.x, P.y = 3, 0.1, 0.1; tick()
SPEED = 7
local boat = ns.db.links[2]
check(boat and boat.kind == "transport" and boat.a.map == 1 and near(boat.a.x, 0.9) and boat.b.map == 3, "transport recorded from where the ride began")
P.map, P.x, P.y = 1, 0.6, 0.5
steps = ns.PlanTravel(3, 0.5, 0.5)
check(steps and has(steps, 1, "transport to Zone3") and has(steps, 2, "Ride to Zone3"), "plan reaches another continent by the transport")

-- ranking now knows the way
ranked = ns.RankZones({})
for _, z in ipairs(ranked) do if z.mapID == 2 then z2 = z elseif z.mapID == 3 then z3 = z end end
check(z3.travel and z3.via:find("ride to Zone3", 1, true), "ranking reaches the other continent: " .. z3.via)
check(z2.via:find("fly to Beta", 1, true), "ranking uses the flight to zone 2: " .. z2.via)

-- guidance follows the trip, step by step
ns.StartRoute(2, z2.route)
local targetMap, target, travelling = ns.GetGuideTarget()
check(travelling and targetMap == 1 and target.text:find("Alpha", 1, true) and WAYPOINT[1] == 1, "route to another zone starts with the first travel step")
nav.__scripts.OnUpdate(nav, 0.2)
P.x, P.y = 0.2, 0.2
nav.__scripts.OnUpdate(nav, 0.2)
_, target, travelling = ns.GetGuideTarget()
check(travelling and target.text == "Fly to Beta", "arriving at the flight master moves on to the flight")
ns.RefreshMinimapPins()
WorldMapFrame.__shown = true; ns.RefreshPins()
local markers = 0
for _, f in ipairs(Frames()) do
    if rawget(f, "marker") and f.__shown then markers = markers + 1; f.__scripts.OnEnter(f) end
end
check(markers >= 3, "world map shows flight master, crossing and transport markers (" .. markers .. ")")
P.map, P.x, P.y = 2, beta.x, beta.y
Fire("PLAYER_CONTROL_GAINED")
targetMap, target, travelling = ns.GetGuideTarget()
check(not travelling and targetMap == 2 and target == z2.route[1], "landing in the destination zone hands over to the mining route")
SlashCmdList.GATHERTRAIL("travel")
ns.StopRoute()
SlashCmdList.GATHERTRAIL("travel clear")
check(#ns.db.links == 1 and ns.db.links[1].kind == "walk", "clearing transports keeps walked crossings")

-- herbalism ---------------------------------------------------------------
ON_TAXI = true; P.map, P.x, P.y = 6, 0.5, 0.5; tick(); ON_TAXI = false
Fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "h1", 8888)
Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "h1", 8888)
local herbs = ns.db.nodes[6]
check(#herbs == 1 and herbs[1].kind == "herb" and herbs[1].count == 1, "picking a herb records a herb node")
P.x = 0.505   -- a vein five yards from the herb
mine("Copper Vein", "h2", true)
check(#herbs == 2 and ns.NodeProfession(herbs[2]) == "ore" and herbs[1].count == 1, "a vein beside a herb is its own node")
P.x = 0.7
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Silverleaf"
GameTooltipTextLeft2.__shown = true; GameTooltipTextLeft2.__text = "Requires Herbalism"
NOW = NOW + 10
GameTooltip.__scripts.OnShow(GameTooltip)
check(#herbs == 3 and herbs[3].kind == "herb" and herbs[3].seen == 1 and herbs[3].approx, "pointing at a herb without Herbalism records a sighting")
Fire("UI_ERROR_MESSAGE", 50, "Requires Herbalism")
check(#herbs == 3 and herbs[3].fails == 1, "a Herbalism skill error counts as a failed attempt on the herb")
GameTooltip.__shown = false
P.x = 0.3; SlashCmdList.GATHERTRAIL("add herb Mageroyal")
check(#herbs == 4 and herbs[4].kind == "herb" and ns.NodeName(herbs[4]) == "Mageroyal", "/gt add herb records a herb")

local herbTypes, herbTotal = ns.GetNodeTypes("herb")
check(#herbTypes == 3 and herbTotal == 3, "herb tab lists only herbs: " .. #herbTypes .. " types, " .. herbTotal .. " nodes")
local herbZones = ns.RankZones({}, "herb")
check(#herbZones == 1 and herbZones[1].mapID == 6 and herbZones[1].nodeCount == 3, "herb ranking counts only herb nodes")
local oreHere
for _, z in ipairs(ns.RankZones({}, "ore")) do if z.mapID == 6 then oreHere = z end end
check(oreHere and oreHere.nodeCount == 1, "ore ranking ignores the herbs in the same zone")
local hr, hg, hb = ns.NodeColor(herbs[1], false)
local or_, og, ob = ns.NodeColor(herbs[2], false)
check(hr ~= or_ or hg ~= og or hb ~= ob, "herb and ore pins use different colours")
-- fishing pools ----------------------------------------------------------
local function fish(guid)
    Fire("UNIT_SPELLCAST_SENT", "player", nil, guid, 9999)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 9999)
end
ON_TAXI = true; P.map, P.x, P.y, P.facing = 7, 0.5, 0.5, 0; tick(); ON_TAXI = false
NOW = NOW + 100
fish("f0")
check(ns.db.nodes[7] == nil, "fishing in open water records nothing")
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Oily Blackmouth School"; GameTooltipTextLeft2.__shown = false
GameTooltip.__scripts.OnShow(GameTooltip)
local pools = ns.db.nodes[7]
check(pools and #pools == 1 and pools[1].kind == "fish" and pools[1].seen == 1 and pools[1].approx and pools[1].count == 0, "pointing at a pool records a sighting")
GameTooltip.__shown = false
NOW = NOW + 5
fish("f1")
check(#pools == 1 and pools[1].count == 1 and not pools[1].approx, "casting beside a pool just pointed at counts as fishing it")
check(near(pools[1].x, 0.5) and near(pools[1].y, 0.5 - 15 / 667), "the pool is placed out in front of the player, not under their feet")
NOW = NOW + 600
fish("f2")
check(pools[1].count == 1, "a cast long after pointing at the pool does not count")
P.x = 0.8; SlashCmdList.GATHERTRAIL("add fish Floating Wreckage")
check(#pools == 2 and pools[2].kind == "fish", "/gt add fish records a pool")
local poolTypes, poolTotal = ns.GetNodeTypes("fish")
check(#poolTypes == 2 and poolTotal == 2, "fish tab lists only pools")
local poolZones = ns.RankZones({}, "fish")
check(#poolZones == 1 and poolZones[1].mapID == 7, "fish ranking counts only pools")
WorldMapFrame.__shown = true; P.map = 7; ns.RefreshPins(); ns.RefreshMinimapPins()
for _, f in ipairs(Frames()) do
    if rawget(f, "node") and ns.NodeProfession(f.node) == "fish" and f.__shown and f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
end

-- skinning ---------------------------------------------------------------
local function skin(mob, guid, loot)
    Fire("UNIT_SPELLCAST_SENT", "player", mob, guid, 6666)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 6666)
    if loot then LOOT = loot; Fire("LOOT_READY") end
end
local function runTimers() local pending = AFTERS; AFTERS = {}; for _, fn in ipairs(pending) do fn() end end
ON_TAXI = true; P.map, P.x, P.y = 8, 0.5, 0.5; tick(); ON_TAXI = false
skin("Young Forest Bear", "s1", { "Light Leather" })
local spots = ns.db.nodes[8]
check(spots and #spots == 1 and spots[1].kind == "skin" and spots[1].names["Light Leather"] == 1 and spots[1].mobs["Young Forest Bear"] == 1, "a skin is recorded under what it gave, with the creature noted")
runTimers()
check(#spots == 1 and spots[1].count == 1, "the fallback timer does not record the same skin twice")
P.x = 0.52   -- twenty yards on, seconds later
skin("Forest Spider", "s2", { "Light Leather", "Light Hide" })
check(#spots == 1 and spots[1].count == 2 and spots[1].names["Light Hide"] == 1 and spots[1].mobs["Forest Spider"] == 1, "a nearby skin moments later adds to the same spot")
P.x = 0.7
skin("Elder Bear", "s3", nil)
check(#spots == 1, "a skin with no loot seen yet is held back")
runTimers()
check(#spots == 2 and spots[2].names["Elder Bear"] == 1, "with no loot seen, the skin is recorded under the creature's name")
Fire("UNIT_SPELLCAST_SENT", "player", "Wolf", "s4", 6666); Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "s4", 6666); runTimers()
check(#spots == 2, "an interrupted skin records nothing")
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Light Leather"; GameTooltipTextLeft2.__shown = false
GameTooltip.__scripts.OnShow(GameTooltip); GameTooltip.__shown = false
check(#spots == 2 and (spots[1].seen or 0) == 0, "an item tooltip for a skinned material is not mistaken for a node")
local skinTypes = ns.GetNodeTypes("skin")
check(#skinTypes == 3, "skins tab lists leather types (and the creature fallback)")
local leather = ns.RankZones({ ["Light Leather"] = true }, "skin")
check(#leather == 1 and leather[1].mapID == 8 and leather[1].nodeCount == 1, "skin ranking filters by material")
SlashCmdList.GATHERTRAIL("add skin Heavy Leather")
WorldMapFrame.__shown = true; ns.RefreshPins()
for _, f in ipairs(Frames()) do
    if rawget(f, "node") and ns.NodeProfession(f.node) == "skin" and f.__shown and f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
end

-- minimap blips -----------------------------------------------------------
-- Stub minimap: centre (100,100), 140 wide, showing 100 yards; the cursor is
-- at (150,120), so it points 50 px right and 20 px up of centre.
ON_TAXI = true; P.map, P.x, P.y, P.facing = 9, 0.5, 0.5, 0; tick(); ON_TAXI = false
NOW = NOW + 100
-- The tooltip's owner is deliberately not the minimap: in the real client it
-- was not, and the first version of this recorded nothing because of it.
local owner = UIParent
GameTooltip.GetOwner = function() return owner end
MOUSE_OVER_MINIMAP = true
GameTooltip.__shown = true; GameTooltipTextLeft2.__shown = false
GameTooltipTextLeft1.__text = "|cffffffffCopper Vein|r\nSome Player"
GameTooltip.__scripts.OnShow(GameTooltip)   -- the in-world tooltip handler must leave this alone
check(ns.db.nodes[9] == nil, "a tooltip over the minimap is not treated as a node in the world")
ns.CheckMinimapTooltip()
local blips = ns.db.nodes[9]
local yardsPerPixel = 100 / 70
check(blips and #blips == 1 and ns.NodeName(blips[1]) == "Copper Vein" and blips[1].seen == 1 and blips[1].approx, "a node blip pointed at on the minimap is recorded; other names on the tooltip are not")
check(near(blips[1].x, 0.5 + 50 * yardsPerPixel / 1000) and near(blips[1].y, 0.5 - 20 * yardsPerPixel / 667), "the blip is placed where the cursor points, not where the player stands")
NOW = NOW + 10; ROTATE_MINIMAP, P.facing = "1", math.pi / 2   -- facing west: screen-right is north
GameTooltipTextLeft1.__text = "Tin Vein"
ns.CheckMinimapTooltip(); ns.CheckMinimapTooltip()   -- polled repeatedly while the cursor rests there
check(#blips == 2 and near(blips[2].x, 0.5 - 20 * yardsPerPixel / 1000) and near(blips[2].y, 0.5 - 50 * yardsPerPixel / 667), "a rotating minimap is turned back before placing the blip")
ROTATE_MINIMAP, P.facing = "0", 0
NOW = NOW + 10; GameTooltipTextLeft1.__text = "Stormwind Guard"
SlashCmdList.GATHERTRAIL("debug"); ns.CheckMinimapTooltip(); SlashCmdList.GATHERTRAIL("debug")
check(#blips == 2, "a minimap blip that is not a node is ignored")
check(PRINTED[#PRINTED - 1]:find("Stormwind Guard", 1, true) ~= nil, "debug mode says what the minimap tooltip read and why it was passed over")
NOW = NOW + 10; SlashCmdList.GATHERTRAIL("detect"); GameTooltipTextLeft1.__text = "Iron Deposit"
ns.CheckMinimapTooltip()
check(#blips == 2, "minimap recording can be turned off")
SlashCmdList.GATHERTRAIL("detect")
-- our own minimap pin's tooltip names a node, and must not be read back in
NOW = NOW + 10; owner = { minimapPin = true }; GameTooltipTextLeft1.__text = "Silver Vein"
ns.CheckMinimapTooltip()
check(#blips == 2, "the addon's own pin tooltips are not recorded as blips")
owner = nil; GameTooltip.__shown = false; MOUSE_OVER_MINIMAP = false

-- treasure chests ---------------------------------------------------------
local function open(target, guid)
    Fire("UNIT_SPELLCAST_SENT", "player", target, guid, 5555)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 5555)
end
ON_TAXI = true; P.map, P.x, P.y = 11, 0.5, 0.5; tick(); ON_TAXI = false
NOW = NOW + 100
open("Rusty Lever", "c0")
check(ns.db.nodes[11] == nil, "opening something that is not a chest records nothing")
open("Battered Chest", "c1")
local chests = ns.db.nodes[11]
check(chests and #chests == 1 and chests[1].kind == "chest" and chests[1].count == 1, "opening a chest records it")
P.x = 0.7
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Solid Chest"; GameTooltipTextLeft2.__shown = false
GameTooltip.__scripts.OnShow(GameTooltip); GameTooltip.__shown = false
check(#chests == 2 and chests[2].kind == "chest" and chests[2].seen == 1 and chests[2].approx, "pointing at a chest records a sighting")
P.x = 0.3; SlashCmdList.GATHERTRAIL("add chest Large Iron Bound Chest")
check(#chests == 3 and chests[3].kind == "chest", "/gt add chest records a chest")
local chestTypes = ns.GetNodeTypes("chest")
local chestZones = ns.RankZones({}, "chest")
check(#chestTypes == 3 and #chestZones == 1 and chestZones[1].mapID == 11, "chests tab lists and ranks only chests")
WorldMapFrame.__shown = true; ns.RefreshPins()
for _, f in ipairs(Frames()) do
    if rawget(f, "node") and ns.NodeProfession(f.node) == "chest" and f.__shown and f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
end

-- rare creatures -----------------------------------------------------------
ON_TAXI = true; P.map, P.x, P.y = 12, 0.5, 0.5; tick(); ON_TAXI = false
NOW = NOW + 100
UNITS.target = { name = "Ordinary Wolf", class = "normal", level = 10 }
Fire("PLAYER_TARGET_CHANGED")
UNITS.target = { name = "Some Player", class = "rare", level = 60, player = true }
Fire("PLAYER_TARGET_CHANGED")
check(ns.db.nodes[12] == nil, "ordinary creatures and players are not recorded as rares")
UNITS.mouseover = { name = "Old Greyfang", class = "rareelite", level = 24 }
Fire("UPDATE_MOUSEOVER_UNIT")
local rares = ns.db.nodes[12]
check(rares and #rares == 1 and rares[1].kind == "rare" and rares[1].seen == 1 and rares[1].approx and rares[1].level == 24 and rares[1].elite, "mousing over a rare records a sighting with its level")
UNITS.nameplate3 = UNITS.mouseover
Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
check(#rares == 1 and rares[1].seen == 1, "seeing the same rare again straight away is not counted twice")
P.x = 0.52
UNITS.target = { name = "Old Greyfang", class = "rareelite", level = 24, dead = true }
Fire("LOOT_READY")
check(#rares == 1 and rares[1].count == 1 and not rares[1].approx and rares[1].x == 0.52, "looting the dead rare counts as a kill and fixes its position")
UNITS.target = nil
VIGNETTES.v1 = { name = "Silvermane", atlasName = "VignetteKill", x = 0.8, y = 0.2 }
VIGNETTES.v2 = { name = "Glinting Hoard", atlasName = "VignetteLoot", x = 0.3, y = 0.7 }
VIGNETTES.v3 = { name = "Zone Event", atlasName = "VignetteEvent", x = 0.1, y = 0.1 }
Fire("VIGNETTES_UPDATED")
check(#rares == 3 and rares[2].x and not rares[2].approx and not rares[3].approx, "the game's minimap markers are recorded automatically at their exact place")
local byName = {}
for _, n in ipairs(rares) do byName[ns.NodeName(n)] = n end
check(byName.Silvermane.kind == "rare" and byName.Silvermane.x == 0.8 and byName["Glinting Hoard"].kind == "chest" and byName["Zone Event"] == nil, "a kill marker is a rare, a treasure marker is a chest, others are ignored")
Fire("VIGNETTES_UPDATED")
check(#rares == 3 and byName.Silvermane.seen == 1, "a marker is only recorded once")
local rareZones = ns.RankZones({}, "rare")
check(#ns.GetNodeTypes("rare") == 2 and #rareZones == 1 and rareZones[1].nodeCount == 2, "rares tab lists and ranks only rares")
SlashCmdList.GATHERTRAIL("add rare Test Rare")
WorldMapFrame.__shown = true; ns.RefreshPins(); ns.RefreshMinimapPins()
for _, f in ipairs(Frames()) do
    if rawget(f, "node") and ns.NodeProfession(f.node) == "rare" and f.__shown and f.__scripts.OnEnter then f.__scripts.OnEnter(f) end
end

-- 1. pin filter -------------------------------------------------------------
local function shownPins(test)
    local count = 0
    for _, f in ipairs(Frames()) do
        if rawget(f, "node") and f.__shown and test(f) then count = count + 1 end
    end
    return count
end
local function isHerbMapPin(f) return rawget(f, "label") and ns.NodeProfession(f.node) == "herb" end
local function isHerbMiniPin(f) return rawget(f, "minimapPin") and ns.NodeProfession(f.node) == "herb" end
ns.StopRoute()
ON_TAXI = true; P.map, P.x, P.y = 6, 0.5, 0.5; tick(); ON_TAXI = false
WorldMapFrame.__shown = true; ns.RefreshPins(); ns.RefreshMinimapPins()
check(shownPins(isHerbMapPin) == 3 and shownPins(isHerbMiniPin) >= 1, "herb pins show on both maps by default")
SlashCmdList.GATHERTRAIL("show herb")
check(shownPins(isHerbMapPin) == 0 and shownPins(isHerbMiniPin) == 0, "/gt show herb hides herb pins on both maps")
check(shownPins(function(f) return rawget(f, "label") and ns.NodeProfession(f.node) == "ore" end) == 1, "other kinds stay visible")
ns.StartRoute(6, { ns.db.nodes[6][1] })
ns.RefreshPins()
check(shownPins(isHerbMapPin) == 1, "a hidden kind still shows the stops of the route being followed")
ns.StopRoute()
SlashCmdList.GATHERTRAIL("show herb")
check(ns.db.showKinds.herb == true, "the kind can be shown again")

-- 2. skill awareness -------------------------------------------------------
ON_TAXI = true; P.map, P.x, P.y = 13, 0.5, 0.5; tick(); ON_TAXI = false
check(ns.GetSkill("ore") == nil and ns.CanGather("Tin Vein", "ore") == "unknown", "a character without Mining has nothing ruled out")
SKILLS[186] = 40
check(ns.GetSkill("ore") == 40 and ns.GetSkill("herb") == nil, "profession skill is read for the right profession")
NOW = NOW + 100
mine("Copper Vein", "k1", true)
check(ns.db.skills["Copper Vein"].gotAt == 40 and ns.CanGather("Copper Vein", "ore") == "yes", "a successful gather records the skill it was done at")
P.x = 0.6
GameTooltip.GetOwner = function() return nil end
GameTooltip.__shown = true; GameTooltipTextLeft1.__text = "Tin Vein"; GameTooltipTextLeft2.__shown = true; GameTooltipTextLeft2.__text = "Mining"
Fire("UI_ERROR_MESSAGE", 50, "Requires Mining 65")
GameTooltip.__shown = false
local able, need = ns.CanGather("Tin Vein", "ore")
check(able == "no" and need == 65, "a skill error teaches the requirement")
P.x = 0.7; SlashCmdList.GATHERTRAIL("add Tin Vein")
P.x = 0.5
local skillZone
for _, z in ipairs(ns.RankZones({}, "ore")) do if z.mapID == 13 then skillZone = z end end
check(skillZone.nodeCount == 3 and skillZone.tooHard == 2, "ranking flags the nodes beyond this character's skill")
local tinOnly
for _, z in ipairs(ns.RankZones({ ["Tin Vein"] = true }, "ore")) do if z.mapID == 13 then tinOnly = z end end
check(tinOnly.score == 0, "a zone with only nodes the character cannot gather scores nothing")
SKILLS[186] = 70
check(ns.CanGather("Tin Vein", "ore") == "yes", "with enough skill the node counts again")
SKILLS[186] = nil

-- 4. freshness ---------------------------------------------------------------
ON_TAXI = true; P.map, P.x, P.y = 14, 0.1, 0.5; tick(); ON_TAXI = false
for i = 1, 3 do P.x = 0.1 + i * 0.2; SlashCmdList.GATHERTRAIL("add Iron Deposit") end
local fresh = ns.db.nodes[14]
ns.db.skipRecentMinutes = 10
check(ns.IsFresh(fresh[1]), "a node gathered just now is fresh")
fresh[2].lastMined = time() - 3600; fresh[3].lastMined = time() - 3600
P.x = 0.3
ns.StartRoute(14, { fresh[1], fresh[2], fresh[3] })
check(select(3, ns.GetRoute()) == 2, "a route starts past a stop gathered a moment ago")
SlashCmdList.GATHERTRAIL("skip"); SlashCmdList.GATHERTRAIL("skip")
check(select(3, ns.GetRoute()) == 2, "going round the loop passes the fresh stop by")
ns.db.skipRecentMinutes = 0
check(not ns.IsFresh(fresh[1]), "skipping can be turned off")
ns.db.skipRecentMinutes = 10
check(not ns.IsFresh(ns.db.nodes[8][1]), "skinning spots are never treated as used up")
WorldMapFrame.__shown = true; ns.RefreshPins()
for _, f in ipairs(Frames()) do
    if rawget(f, "label") and rawget(f, "node") and f.__shown then f.__scripts.OnEnter(f) end
end
ns.StopRoute()

-- 5. skinning score ----------------------------------------------------------
ON_TAXI = true; P.map, P.x, P.y = 15, 0.5, 0.5; tick(); ON_TAXI = false
SlashCmdList.GATHERTRAIL("add skin Rugged Leather")
local camp = ns.db.nodes[15][1]
local function campScore() for _, z in ipairs(ns.RankZones({}, "skin")) do if z.mapID == 15 then return z.score end end end
camp.count = 3; local few = campScore()
camp.count = 50; local many = campScore()
check(many > few * 3, ("a camp with 50 skins outranks one with 3 (%.1f against %.1f)"):format(many, few))

-- 6. data management ---------------------------------------------------------
local text, records = ns.ExportData()
check(text:sub(1, 12) == "GatherTrail1" and records > 30, "export produces " .. records .. " records")
local function snapshot()
    local nodes, visits = 0, 0
    for _, list in pairs(ns.db.nodes) do
        for _, n in ipairs(list) do nodes = nodes + 1; visits = visits + n.count + (n.seen or 0) + (n.fails or 0) end
    end
    local flights = 0; for _ in pairs(ns.db.flights) do flights = flights + 1 end
    return nodes, visits, flights, #ns.db.links
end
local n1, v1, f1, l1 = snapshot()
local added, merged, other = ns.ImportData(text)
local n2, v2, f2, l2 = snapshot()
check(added == 0 and merged == n1 and n2 == n1 and v2 == v1 and f2 == f1 and l2 == l1, "importing your own export changes nothing")
local kept = { nodes = ns.db.nodes, flights = ns.db.flights, links = ns.db.links, skills = ns.db.skills }
ns.db.nodes, ns.db.flights, ns.db.links, ns.db.skills = {}, {}, {}, {}
added, merged, other = ns.ImportData(text)
local n3, v3, f3, l3 = snapshot()
check(added == n1 and merged == 0 and n3 == n1 and v3 == v1 and f3 == f1 and l3 == l1, "importing into an empty account restores every record")
check(ns.db.nodes[8][1].mobs["Young Forest Bear"] == 1 and ns.db.nodes[6][1].kind == "herb" and ns.db.skills["Tin Vein"].need == 65, "kinds, creatures and skill notes survive the round trip")
check(ns.ImportData("hello") == nil, "text that is not an export is refused")
local before = ns.CountNodes(6, "herb")
check(before == 3 and ns.DeleteNodes(6, "herb") == 3 and ns.CountNodes(6, "herb") == 0 and ns.CountNodes(6, "ore") == 1, "deleting one kind in one zone leaves the rest")

-- 3. options page ------------------------------------------------------------
if not GatherTrailWindow:IsShown() then SlashCmdList.GATHERTRAIL("") end
local toggles = 0
ns.ToggleSettings(GatherTrailWindow, 41)
for _, f in ipairs(Frames()) do
    if rawget(f, "Refresh") and f.__scripts.OnClick and not rawget(f, "items") then
        f.__scripts.OnClick(f, "LeftButton"); f.__scripts.OnClick(f, "LeftButton"); toggles = toggles + 1
    end
end
check(toggles == 11, "every options checkbox toggles and toggles back (" .. toggles .. ")")
check(ns.db.showPins and ns.db.showMinimapPins and ns.db.beacon and ns.db.sound and ns.db.minimapDetect and ns.db.showKinds.rare, "options are back where they started")
-- every button on the page and in the export dialog
local pressed = 0
for _, f in ipairs(Frames()) do
    if rawget(f, "label") and not rawget(f, "node") and f.__scripts.OnClick and f.__shown and f.label.__text
        and f.label.__text ~= "Start route" and f.label.__text ~= "Options" then
        f.__scripts.OnClick(f, "LeftButton"); pressed = pressed + 1
    end
end
check(pressed >= 6, "options and data buttons run without error (" .. pressed .. ")")
ns.ToggleSettings(GatherTrailWindow, 41)
if GatherTrailWindow:IsShown() then SlashCmdList.GATHERTRAIL("") end
ns.db.skipRecentMinutes = 10

-- zone level ranges -------------------------------------------------------
local lo, hi, source = ns.GetZoneLevels(2)
check(lo == 30 and hi == 40 and source == "game", "the game's own level range is used when it gives one")
lo, hi, source = ns.GetZoneLevels(1436)
check(lo == 10 and hi == 20 and source == "book", "a zone the game says nothing about falls back to the original game's range")
check(ns.GetZoneLevels(2521) == nil, "a new zone with nothing seen in it has no range")
ON_TAXI = true; P.map, P.x, P.y = 2521, 0.5, 0.5; tick(); ON_TAXI = false
local function see(name, level, extra)
    UNITS.mouseover = { name = name, guid = name, class = "normal", level = level }
    for key, value in pairs(extra or {}) do UNITS.mouseover[key] = value end
    Fire("UPDATE_MOUSEOVER_UNIT")
end
for i = 1, 14 do see("Boar " .. i, 12 + i % 5) end
check(ns.GetZoneLevels(2521) == nil, "a handful of creatures is not enough to go on")
see("Stormwind Guard", 55, { friendly = true })
see("Some Player", 60, { player = true })
see("Rabbit", 1, { class = "trivial" })
see("Boar 1", 12)   -- already counted
check(ns.GetZoneLevels(2521) == nil, "guards, players, critters and repeats are not counted")
for i = 15, 30 do see("Wolf " .. i, 12 + i % 5) end
see("Stray Elite", 40, { class = "elite" })
lo, hi, source = ns.GetZoneLevels(2521)
check(lo == 12 and hi == 16 and source == "seen", ("enough creatures give a range, and one stray does not stretch it (%s-%s)"):format(tostring(lo), tostring(hi)))
SlashCmdList.GATHERTRAIL("add Copper Vein")
local learned
for _, z in ipairs(ns.RankZones({}, "ore")) do if z.mapID == 2521 then learned = z end end
check(learned and learned.minLevel == 12 and learned.levelSource == "seen" and not learned.tooHigh, "the ranking uses the learned range")
SlashCmdList.GATHERTRAIL("zone")
local exported = ns.ExportData()
ns.db.zones[2521].mobLevels = nil
ns.ImportData(exported)
lo, hi = ns.GetZoneLevels(2521)
check(lo == 12 and hi == 16, "creature levels survive export and import")
UNITS.mouseover = nil

-- the window's profession tabs
if not GatherTrailWindow:IsShown() then SlashCmdList.GATHERTRAIL("") end
local tabClicks = 0
for _, f in ipairs(Frames()) do
    if rawget(f, "selected") and not rawget(f, "item") and f.__scripts.OnClick and f.__shown then
        f.__scripts.OnClick(f, "LeftButton"); tabClicks = tabClicks + 1
    end
end
check(tabClicks == 6, "all six tabs switch without error")
SlashCmdList.GATHERTRAIL("")

io.write("--- chat output sample ---\n"); for i = 1, math.min(8, #PRINTED) do io.write("  ", PRINTED[i], "\n") end
