local _, ns = ...

-- Export, import and bulk deletion of the saved records.
--
-- The export is plain text, one record per line, fields separated by
-- commas:
--   N  a node           F  a flight master
--   L  a connection     S  what is known about a node's skill requirement
--   Z  the creature levels seen in a zone
-- Importing merges: a record already present is updated to the larger of
-- each count, so importing the same text twice changes nothing.

local HEADER = "GatherTrail1"

local function Escape(text)
    return (tostring(text):gsub("[%%,;=\n\r]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function Split(line)
    local fields = {}
    for field in (line .. ","):gmatch("([^,]*),") do
        fields[#fields + 1] = field
    end
    return fields
end

-- { Copper = 3, Tin = 1 } <-> "Copper=3;Tin=1"
local function PackCounts(counts)
    local parts = {}
    for name, count in pairs(counts or {}) do
        parts[#parts + 1] = Escape(name) .. "=" .. count
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

local function UnpackCounts(text)
    local counts = {}
    for name, count in text:gmatch("([^;=]+)=(%d+)") do
        counts[Unescape(name)] = tonumber(count)
    end
    return counts
end

local function Coordinate(value)
    return ("%.5f"):format(value)
end

function ns.ExportData()
    local lines = { HEADER }
    for mapID, nodes in pairs(ns.db.nodes) do
        for _, node in ipairs(nodes) do
            lines[#lines + 1] = table.concat({
                "N", mapID, ns.NodeProfession(node), Coordinate(node.x), Coordinate(node.y),
                node.count or 0, node.fails or 0, node.seen or 0, node.approx and 1 or 0,
                node.first or 0, node.last or 0, node.lastMined or 0,
                node.level or 0, node.elite and 1 or 0,
                PackCounts(node.names), PackCounts(node.mobs),
            }, ",")
        end
    end
    for nodeID, flight in pairs(ns.db.flights) do
        lines[#lines + 1] = table.concat({
            "F", nodeID, flight.map, Coordinate(flight.x), Coordinate(flight.y),
            flight.exact and 1 or 0, Escape(flight.name or ""),
        }, ",")
    end
    for _, link in ipairs(ns.db.links) do
        lines[#lines + 1] = table.concat({
            "L", link.kind, link.a.map, Coordinate(link.a.x), Coordinate(link.a.y),
            link.b.map, Coordinate(link.b.x), Coordinate(link.b.y), link.count or 1,
        }, ",")
    end
    for mapID, zone in pairs(ns.db.zones) do
        if zone.mobLevels and next(zone.mobLevels) then
            lines[#lines + 1] = table.concat({ "Z", mapID, PackCounts(zone.mobLevels) }, ",")
        end
    end
    for name, info in pairs(ns.db.skills) do
        lines[#lines + 1] = table.concat({
            "S", Escape(name), info.need or 0, info.gotAt or 0, info.lackedAt or 0,
        }, ",")
    end
    return table.concat(lines, "\n"), #lines - 1
end

local function Larger(a, b)
    a, b = a or 0, b or 0
    local larger = a > b and a or b
    return larger > 0 and larger or nil
end

local function Smaller(a, b)
    a, b = a or 0, b or 0
    if a == 0 then return b end
    if b == 0 then return a end
    return a < b and a or b
end

local function MergeCounts(into, from)
    for name, count in pairs(from) do
        into[name] = math.max(into[name] or 0, count)
    end
end

-- Returns "added" or "merged", or nil for a line that makes no sense.
local function ImportNode(f)
    local mapID, profession, x, y = tonumber(f[2]), f[3], tonumber(f[4]), tonumber(f[5])
    if not mapID or not ns.KINDS[profession] or not x or not y then return end
    local names = UnpackCounts(f[15] or "")
    if not next(names) then return end
    local approx = f[9] == "1"
    local mobs = UnpackCounts(f[16] or "")

    local node = ns.FindNode(mapID, x, y, profession)
    local result = "merged"
    if not node then
        result = "added"
        node = { x = x, y = y, count = 0, names = {}, approx = approx or nil,
            kind = profession ~= "ore" and profession or nil }
        local nodes = ns.db.nodes[mapID]
        if not nodes then
            nodes = {}
            ns.db.nodes[mapID] = nodes
        end
        nodes[#nodes + 1] = node
    elseif node.approx and not approx then
        node.x, node.y, node.approx = x, y, nil
    end

    node.count = math.max(node.count or 0, tonumber(f[6]) or 0)
    node.fails = Larger(node.fails, tonumber(f[7]))
    node.seen = Larger(node.seen, tonumber(f[8]))
    node.first = Smaller(node.first, tonumber(f[10]))
    node.last = math.max(node.last or 0, tonumber(f[11]) or 0)
    node.lastMined = Larger(node.lastMined, tonumber(f[12]))
    node.level = node.level or Larger(tonumber(f[13]), 0)
    node.elite = node.elite or (f[14] == "1") or nil
    MergeCounts(node.names, names)
    if next(mobs) then
        node.mobs = node.mobs or {}
        MergeCounts(node.mobs, mobs)
    end
    return result
end

local function ImportSkill(f)
    local name = f[2] and Unescape(f[2])
    if not name or name == "" then return end
    local info = ns.db.skills[name]
    if not info then
        info = {}
        ns.db.skills[name] = info
    end
    local need, gotAt, lackedAt = tonumber(f[3]) or 0, tonumber(f[4]) or 0, tonumber(f[5]) or 0
    if need > 0 then info.need = need end
    if gotAt > 0 and (not info.gotAt or gotAt < info.gotAt) then info.gotAt = gotAt end
    if lackedAt > 0 and (not info.lackedAt or lackedAt > info.lackedAt) then info.lackedAt = lackedAt end
    return true
end

-- Creature levels seen in a zone: the larger count for each level is kept.
local function ImportZone(f)
    local mapID = tonumber(f[2])
    if not mapID then return end
    local zone = ns.db.zones[mapID]
    if not zone then
        zone = {}
        ns.db.zones[mapID] = zone
    end
    zone.mobLevels = zone.mobLevels or {}
    for level, count in pairs(UnpackCounts(f[3] or "")) do
        level = tonumber(level)
        if level then
            zone.mobLevels[level] = math.max(zone.mobLevels[level] or 0, count)
        end
    end
    return true
end

-- Merges exported text into the saved data. Returns how many nodes were
-- new, how many matched existing ones, and how many other records (flight
-- masters, connections, skill notes) were read; or nil and a reason.
function ns.ImportData(text)
    if type(text) ~= "string" then return nil, "There is nothing to import." end
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        lines[#lines + 1] = line:match("^%s*(.-)%s*$")
    end
    if lines[1] ~= HEADER then
        return nil, "That does not look like GatherTrail data."
    end

    local added, merged, other = 0, 0, 0
    for index = 2, #lines do
        local f = Split(lines[index])
        local record = f[1]
        if record == "N" then
            local result = ImportNode(f)
            if result == "added" then added = added + 1 elseif result then merged = merged + 1 end
        elseif record == "F" then
            if ns.ImportFlight(tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), f[6] == "1", Unescape(f[7] or "")) then
                other = other + 1
            end
        elseif record == "L" then
            if ns.ImportLink(f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]), tonumber(f[9])) then
                other = other + 1
            end
        elseif record == "S" then
            if ImportSkill(f) then other = other + 1 end
        elseif record == "Z" then
            if ImportZone(f) then other = other + 1 end
        end
    end

    ns.RebuildKnownNames()
    ns.RefreshPins()
    ns.RefreshWindow()
    return added, merged, other
end

function ns.CountNodes(mapID, profession)
    local count = 0
    for _, node in ipairs(ns.db.nodes[mapID] or {}) do
        if ns.NodeProfession(node) == profession then
            count = count + 1
        end
    end
    return count
end

-- Deletes every record of one kind in one zone. Returns how many went.
function ns.DeleteNodes(mapID, profession)
    local nodes = ns.db.nodes[mapID]
    if not nodes then return 0 end
    local removed = 0
    for index = #nodes, 1, -1 do
        if ns.NodeProfession(nodes[index]) == profession then
            table.remove(nodes, index)
            removed = removed + 1
        end
    end
    if removed > 0 then
        ns.StopRoute()
        ns.RebuildKnownNames()
        ns.RefreshPins()
        ns.RefreshWindow()
    end
    return removed
end
