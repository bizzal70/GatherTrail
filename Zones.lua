local _, ns = ...

-- What level a zone is. The client's own answer is used when it has one,
-- but on Forever it has been coming back empty, so there are two fallbacks:
--   "seen"  the levels of hostile creatures the account's characters have
--           come across there
--   "book"  the zone's level range in the original game

-- How many creatures must have been seen before their levels are trusted.
local MIN_SAMPLES = 15
-- The range shown runs between these fractions of the levels seen, so a
-- stray critter or one elite does not stretch it.
local LOW_FRACTION, HIGH_FRACTION = 0.10, 0.90

-- Level ranges from the original game, by map. Forever uses the same maps,
-- but whether it kept the same levels is not confirmed; creatures actually
-- seen override this once there are enough of them.
local BOOK = {
    [1411] = { 1, 10 },  -- Durotar
    [1412] = { 1, 10 },  -- Mulgore
    [1413] = { 10, 25 }, -- The Barrens
    [1416] = { 30, 40 }, -- Alterac Mountains
    [1417] = { 30, 40 }, -- Arathi Highlands
    [1418] = { 35, 45 }, -- Badlands
    [1419] = { 45, 55 }, -- Blasted Lands
    [1420] = { 1, 10 },  -- Tirisfal Glades
    [1421] = { 10, 20 }, -- Silverpine Forest
    [1422] = { 51, 58 }, -- Western Plaguelands
    [1423] = { 53, 60 }, -- Eastern Plaguelands
    [1424] = { 20, 30 }, -- Hillsbrad Foothills
    [1425] = { 40, 50 }, -- The Hinterlands
    [1426] = { 1, 10 },  -- Dun Morogh
    [1427] = { 43, 50 }, -- Searing Gorge
    [1428] = { 50, 58 }, -- Burning Steppes
    [1429] = { 1, 10 },  -- Elwynn Forest
    [1430] = { 55, 60 }, -- Deadwind Pass
    [1431] = { 18, 30 }, -- Duskwood
    [1432] = { 10, 20 }, -- Loch Modan
    [1433] = { 15, 25 }, -- Redridge Mountains
    [1434] = { 30, 45 }, -- Stranglethorn Vale
    [1435] = { 35, 45 }, -- Swamp of Sorrows
    [1436] = { 10, 20 }, -- Westfall
    [1437] = { 20, 30 }, -- Wetlands
    [1438] = { 1, 10 },  -- Teldrassil
    [1439] = { 10, 20 }, -- Darkshore
    [1440] = { 18, 30 }, -- Ashenvale
    [1441] = { 25, 35 }, -- Thousand Needles
    [1442] = { 15, 27 }, -- Stonetalon Mountains
    [1443] = { 30, 40 }, -- Desolace
    [1444] = { 40, 50 }, -- Feralas
    [1445] = { 35, 45 }, -- Dustwallow Marsh
    [1446] = { 40, 50 }, -- Tanaris
    [1447] = { 45, 55 }, -- Azshara
    [1448] = { 48, 55 }, -- Felwood
    [1449] = { 48, 55 }, -- Un'Goro Crater
    [1450] = { 55, 60 }, -- Moonglade
    [1451] = { 55, 60 }, -- Silithus
    [1452] = { 53, 60 }, -- Winterspring
}

-- Each creature is counted once per session.
local counted = {}

local function Fact(value)
    if ns.IsUsable(value) then return value end
end

-- Notes the level of a hostile creature in the zone the player is in.
local function NoteUnit(unit)
    if not Fact(UnitExists(unit)) then return end
    if Fact(UnitIsPlayer(unit)) or Fact(UnitPlayerControlled(unit)) then return end
    -- Guards and quest givers are far above the zone they stand in.
    if not UnitCanAttack or not Fact(UnitCanAttack("player", unit)) then return end
    local level = Fact(UnitLevel(unit))
    if not level or level < 1 then return end
    local class = Fact(UnitClassification(unit))
    if class == "trivial" or class == "minus" or class == "worldboss" then return end
    local guid = Fact(UnitGUID(unit))
    if not guid or counted[guid] then return end

    local mapID = Fact(C_Map.GetBestMapForUnit("player"))
    if not mapID then return end
    counted[guid] = true
    local zone = ns.db.zones[mapID]
    if not zone then
        zone = {}
        ns.db.zones[mapID] = zone
    end
    zone.mobLevels = zone.mobLevels or {}
    zone.mobLevels[level] = (zone.mobLevels[level] or 0) + 1
end

-- The level range between two fractions of the creatures seen in a zone, and
-- how many were seen; nil with fewer than MIN_SAMPLES.
local function SeenLevels(mapID)
    local zone = ns.db.zones[mapID]
    local counts = zone and zone.mobLevels
    if not counts then return nil, nil, 0 end
    local levels, total = {}, 0
    for level, count in pairs(counts) do
        levels[#levels + 1] = level
        total = total + count
    end
    if total < MIN_SAMPLES then return nil, nil, total end
    table.sort(levels)

    local low, high
    local running = 0
    for _, level in ipairs(levels) do
        running = running + counts[level]
        if not low and running >= total * LOW_FRACTION then low = level end
        if not high and running >= total * HIGH_FRACTION then high = level end
    end
    return low, high, total
end

-- A zone's level range and where it came from: "game", "seen" or "book".
-- nil when nothing is known.
function ns.GetZoneLevels(mapID)
    local minLevel, maxLevel = C_Map.GetMapLevels(mapID)
    if ns.IsUsable(minLevel) and ns.IsUsable(maxLevel) and minLevel > 0 and maxLevel >= minLevel then
        return minLevel, maxLevel, "game"
    end
    local low, high = SeenLevels(mapID)
    if low then
        return low, high, "seen"
    end
    local book = BOOK[mapID]
    if book then
        return book[1], book[2], "book"
    end
end

-- "/gt zone": what is known about the zone the player is in, and from where.
function ns.PrintZoneInfo()
    local mapID = Fact(C_Map.GetBestMapForUnit("player"))
    if not mapID then
        ns.Print("Could not read which zone you are in.")
        return
    end
    ns.Print(("%s is map %d."):format(ns.MapName(mapID), mapID))

    local gameMin, gameMax = C_Map.GetMapLevels(mapID)
    ns.Print(("The game reports its level range as: %s to %s."):format(
        ns.IsUsable(gameMin) and tostring(gameMin) or "nothing", ns.IsUsable(gameMax) and tostring(gameMax) or "nothing"))

    local low, high, samples = SeenLevels(mapID)
    if low then
        ns.Print(("Creatures seen here: %d, mostly level %d to %d."):format(samples, low, high))
    else
        ns.Print(("Creatures seen here: %d (%d needed before their levels are used)."):format(samples, MIN_SAMPLES))
    end
    local book = BOOK[mapID]
    ns.Print(book and ("In the original game it was level %d to %d."):format(book[1], book[2])
        or "It is not a zone from the original game.")

    local minLevel, maxLevel, source = ns.GetZoneLevels(mapID)
    if minLevel then
        ns.Print(("GatherTrail is using level %d to %d."):format(minLevel, maxLevel))
    else
        ns.Print("GatherTrail has no level range for it yet.")
    end
    local status = ns.db.zones[mapID]
    local faction = Fact(UnitFactionGroup("player"))
    ns.Print(("For your faction it is: %s."):format(status and faction and status[faction] or "not recorded yet"))
    return source
end

local handlers = {
    PLAYER_TARGET_CHANGED = function() NoteUnit("target") end,
    UPDATE_MOUSEOVER_UNIT = function() NoteUnit("mouseover") end,
    NAME_PLATE_UNIT_ADDED = function(unit) if ns.IsUsable(unit) then NoteUnit(unit) end end,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end
