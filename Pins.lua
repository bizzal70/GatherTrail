local _, ns = ...

-- What the world map and the minimap share: a pin's colour, its round
-- shape, and the tooltip for a recorded node.

-- Pin colour, shared by the world map and the minimap: green for the
-- route's next stop, blue for something only spotted or attempted, and
-- otherwise the kind's own colour, stronger the more often it was found.
local TARGET_COLOR = { 0.2, 1, 0.2, 1 }
local SPOTTED_COLOR = { 0.45, 0.65, 0.9, 0.9 }

function ns.NodeColor(node, isTarget)
    if isTarget then
        return unpack(TARGET_COLOR)
    end
    local kind = ns.KINDS[ns.NodeProfession(node)]
    local evidence = node.count
    if kind.countsSightings then
        -- Mostly seen, not gathered, so sightings count here too.
        evidence = evidence + (node.seen or 0)
    elseif evidence < 1 then
        return unpack(SPOTTED_COLOR)
    end
    local color = kind.colors[evidence >= 5 and 3 or (evidence >= 2 and 2 or 1)]
    return color[1], color[2], color[3], 1
end

-- "3 min ago", "2 h ago", "5 days ago"
local function Ago(timestamp)
    local seconds = math.max(0, time() - timestamp)
    if seconds < 90 then
        return "a moment ago"
    elseif seconds < 5400 then
        return ("%d min ago"):format(seconds / 60)
    elseif seconds < 172800 then
        return ("%d h ago"):format(seconds / 3600)
    end
    return ("%d days ago"):format(seconds / 86400)
end

-- Turns a square pin into a round one: a dark disc with a slightly smaller
-- coloured disc on it. Where the client has no texture masks the pin simply
-- stays square.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function ns.RoundPin(pin, rim, fill)
    pcall(function()
        local outer = pin:CreateMaskTexture()
        outer:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        outer:SetAllPoints(pin)
        rim:AddMaskTexture(outer)
        local inner = pin:CreateMaskTexture()
        inner:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        inner:SetPoint("TOPLEFT", 1.5, -1.5)
        inner:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
        fill:AddMaskTexture(inner)
    end)
end

-- 1 -> "once", 2 -> "twice", 5 -> "5 times"
local function Times(count)
    if count == 1 then
        return "once"
    elseif count == 2 then
        return "twice"
    end
    return ("%d times"):format(count)
end

function ns.ShowNodeTooltip(owner, node, anchor)
    GameTooltip:SetOwner(owner, anchor)
    if node.travel then
        -- A step of the trip to the route's zone, not a mining node.
        GameTooltip:AddLine(node.text)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddLine(ns.NodeName(node))
    local kind = ns.KINDS[ns.NodeProfession(node)]
    if node.level then
        GameTooltip:AddLine(("Level %d%s"):format(node.level, node.elite and " elite" or ""), 1, 0.82, 0)
    end
    if node.count > 0 then
        GameTooltip:AddLine(kind.done .. " " .. Times(node.count), 1, 1, 1)
    else
        GameTooltip:AddLine(kind.notDone, 0.7, 0.7, 0.7)
    end
    if node.mobs then
        -- Which creatures were skinned here, most often first.
        local mobs = {}
        for mob in pairs(node.mobs) do
            mobs[#mobs + 1] = mob
        end
        table.sort(mobs, function(a, b) return node.mobs[a] > node.mobs[b] end)
        GameTooltip:AddLine("From: " .. table.concat(mobs, ", ", 1, math.min(3, #mobs)), 1, 1, 1, true)
    end
    if (node.fails or 0) > 0 then
        GameTooltip:AddLine("Tried without success " .. Times(node.fails), 1, 1, 1)
    end
    if (node.seen or 0) > 0 then
        GameTooltip:AddLine("Spotted " .. Times(node.seen), 1, 1, 1)
    end
    if ns.IsFresh(node) then
        GameTooltip:AddLine(("Gathered %s; routes pass it by for now"):format(Ago(node.lastMined)), 0.6, 0.8, 1)
    elseif node.last and node.last > 0 then
        GameTooltip:AddLine("Last here " .. Ago(node.last), 0.7, 0.7, 0.7)
    end
    if node.approx then
        GameTooltip:AddLine("Approximate location", 1, 0.6, 0.2)
    end
    if node.first and node.first > 0 then
        GameTooltip:AddLine("First recorded " .. date("%Y-%m-%d", node.first), 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end
