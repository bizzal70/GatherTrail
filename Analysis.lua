local _, ns = ...

-- Scoring: reliable nodes gained per 1000 yards covered, counting the trip
-- there and one lap of the loop.
local TRAVEL_WEIGHT = 0.5      -- the trip is paid once, the loop is repeated
local FAR_YARDS = 8000         -- assumed trip to a zone on another continent
local BASE_YARDS = 400         -- stops a single nearby node from scoring absurdly high
local UNMINED_WEIGHT = 0.4
local TOO_HIGH_FACTOR = 0.3
local HOSTILE_FACTOR = 0.4

-- An empty selection means anything that profession gathers.
local function Matches(node, selection, profession)
    if ns.NodeProfession(node) ~= profession then return false end
    if not next(selection) then return true end
    for name in pairs(selection) do
        if node.names[name] then return true end
    end
    return false
end

-- Every node type one profession ("ore" by default, or "herb") has in the
-- saved data, sorted by name, plus that profession's total node count.
function ns.GetNodeTypes(profession)
    profession = profession or "ore"
    local byName, list, total = {}, {}, 0
    for mapID, nodes in pairs(ns.db.nodes) do
        for _, node in ipairs(nodes) do
            local matches = ns.NodeProfession(node) == profession
            if matches then total = total + 1 end
            for name in pairs(matches and node.names or {}) do
                local entry = byName[name]
                if not entry then
                    entry = { name = name, nodes = 0, zones = {}, zoneCount = 0 }
                    byName[name] = entry
                    list[#list + 1] = entry
                end
                entry.nodes = entry.nodes + 1
                if not entry.zones[mapID] then
                    entry.zones[mapID] = true
                    entry.zoneCount = entry.zoneCount + 1
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list, total
end


-- Ranks every zone that has nodes of the selected ore types, best first.
-- Considers how many nodes there are and how reliably they have been there,
-- how tight a loop they form, how far away they are, whether the zone is
-- above the character's level, and whether it is hostile to their faction.
function ns.RankZones(selection, profession)
    profession = profession or "ore"
    local playerLevel = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    local currentMap = C_Map.GetBestMapForUnit("player")
    local kind = ns.KINDS[profession]
    local tree = ns.BuildTravelTree()
    local ranked = {}

    for mapID, nodes in pairs(ns.db.nodes) do
        local matching, weight, minedCount, tooHard = {}, 0, 0, 0
        for _, node in ipairs(nodes) do
            if Matches(node, selection, profession) then
                matching[#matching + 1] = node
                if ns.CanGather(ns.NodeName(node), profession) == "no" then
                    -- Beyond this character's skill: worth nothing to them yet.
                    tooHard = tooHard + 1
                    if node.count > 0 then minedCount = minedCount + 1 end
                elseif node.count > 0 then
                    minedCount = minedCount + 1
                    if kind.Weight then
                        weight = weight + kind.Weight(node.count)
                    else
                        -- One visit could be a fluke; repeat visits approach full weight.
                        weight = weight + (1 - 0.5 ^ node.count)
                    end
                else
                    -- Seen or attempted but never mined: real, but unproven.
                    weight = weight + UNMINED_WEIGHT
                end
            end
        end

        if #matching > 0 then
            -- Where the trip there would arrive: by known flights, crossings
            -- and transports if they reach the zone, otherwise a straight
            -- line when it is on this continent.
            local px, py = ns.GetPlayerPositionOnMap(mapID)
            local steps, arrivalCost
            if tree then
                local cx, cy = 0, 0
                for _, node in ipairs(matching) do
                    cx, cy = cx + node.x, cy + node.y
                end
                local planned, _, arrival = tree:PathTo(mapID, cx / #matching, cy / #matching)
                if planned then
                    steps, arrivalCost = planned, arrival.cost
                    px, py = arrival.x, arrival.y
                end
            end

            local route, loop = ns.BuildRoute(mapID, px, py, matching)
            local travel = px and ns.Distance(mapID, px, py, route[1].x, route[1].y) or nil
            if steps then
                travel = travel + arrivalCost
            end

            local minLevel, maxLevel, levelSource = ns.GetZoneLevels(mapID)
            local tooHigh = minLevel and ns.IsUsable(playerLevel) and playerLevel < minLevel or false
            local status = ns.db.zones[mapID]
            local pvp = status and ns.IsUsable(faction) and status[faction] or nil

            local score = weight / ((travel or FAR_YARDS) * TRAVEL_WEIGHT + loop + BASE_YARDS) * 1000
            if tooHigh then score = score * TOO_HIGH_FACTOR end
            if pvp == "hostile" then score = score * HOSTILE_FACTOR end

            ranked[#ranked + 1] = {
                mapID = mapID,
                name = ns.MapName(mapID),
                route = route,
                nodeCount = #matching,
                minedCount = minedCount,
                -- How many of the nodes need more skill than this character has.
                tooHard = tooHard,
                loop = loop,
                travel = travel,
                -- Known way there ("fly to X, cross into Y"); nil when the
                -- distance is only a straight-line guess.
                via = steps and ns.TravelSummary(steps) or nil,
                here = ns.IsUsable(currentMap) and currentMap == mapID,
                minLevel = minLevel,
                -- Where the level range came from: "game", "seen" or "book".
                levelSource = levelSource,
                maxLevel = maxLevel,
                tooHigh = tooHigh,
                pvp = pvp,
                score = score,
            }
        end
    end

    table.sort(ranked, function(a, b) return a.score > b.score end)
    return ranked
end
