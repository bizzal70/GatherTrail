local _, ns = ...

-- Skinning has no nodes. Each skinned creature is recorded where it lay,
-- under the names of what it gave (leather, hide, scales), with the
-- creature noted. A failed skin leaves nothing worth recording.

-- How long after a Skinning cast its loot is waited for before the skin is
-- recorded under the creature's name instead.
local LOOT_SECONDS = 4

-- A skinned creature whose loot has not been seen yet.
local pendingSkin

local function Commit(skin, names)
    if pendingSkin ~= skin then return end
    pendingSkin = nil
    local node = ns.RecordNode(names[1], "mined", false, "skin")
    if not node then return end
    for index = 2, #names do
        node.names[names[index]] = (node.names[names[index]] or 0) + 1
    end
    node.mobs = node.mobs or {}
    node.mobs[skin.mob] = (node.mobs[skin.mob] or 0) + 1
    ns.RefreshWindow()
end

local function LootNames()
    local names = {}
    local count = GetNumLootItems()
    if not ns.IsUsable(count) then return names end
    for slot = 1, count do
        local _, itemName = GetLootSlotInfo(slot)
        if ns.IsUsable(itemName) and itemName ~= "" then
            names[#names + 1] = itemName
        end
    end
    return names
end

ns.RegisterKind({
    key = "skin",
    order = 4,
    label = "Skins",
    plural = "Skinning spots",
    any = "Any skin",
    heading = "BEST PLACES TO SKIN FOR IT",
    done = "Skinned",
    notDone = "Not skinned yet",
    -- Red.
    colors = { { 0.65, 0.35, 0.35 }, { 0.85, 0.40, 0.40 }, { 1.00, 0.45, 0.45 } },
    tint = { 0.80, 0.58, 0.42 },
    skill = { line = 393, name = "Skinning" },
    -- Every skin within this range of a spot adds to that one spot, and
    -- each skinned creature is a separate find.
    mergeYards = 40,
    repeatsAtOnce = true,
    quietAfterFirst = "New skinning spot: %s in %s.",
    neverStale = true,
    notKnownByName = true,
    -- A spot is a camp of creatures, so more skins there means more to
    -- skin, with diminishing returns.
    Weight = function(count) return math.sqrt(count) end,

    casts = { "Skinning" },
    spellIDs = { 8613 },

    Finish = function(_, mob, outcome)
        if outcome ~= "mined" then return end
        local skin = { mob = mob, time = GetTime() }
        pendingSkin = skin
        C_Timer.After(LOOT_SECONDS, function()
            Commit(skin, { skin.mob })
        end)
    end,
})

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
    local skin = pendingSkin
    if not skin or GetTime() - skin.time > LOOT_SECONDS then return end
    local names = LootNames()
    if #names > 0 then
        Commit(skin, names)
    end
end)
pcall(frame.RegisterEvent, frame, "LOOT_READY")
pcall(frame.RegisterEvent, frame, "LOOT_OPENED")
