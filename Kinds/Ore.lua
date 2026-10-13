local _, ns = ...

-- Mining veins and deposits.

-- Swatch colour for each ore, matched on words in the node's name. Order
-- matters: "dark iron" must be tried before "iron".
local TINTS = {
    { "dark iron", 0.50, 0.26, 0.26 },
    { "truesilver", 0.72, 0.95, 1.00 },
    { "copper", 0.85, 0.50, 0.25 },
    { "tin", 0.72, 0.75, 0.78 },
    { "silver", 0.86, 0.89, 0.96 },
    { "iron", 0.56, 0.52, 0.50 },
    { "gold", 1.00, 0.82, 0.20 },
    { "mithril", 0.55, 0.80, 0.95 },
    { "thorium", 0.35, 0.75, 0.45 },
}

ns.RegisterKind({
    key = "ore",
    order = 1,
    label = "Ore",
    plural = "Ore",
    any = "Any ore",
    heading = "BEST PLACES TO MINE IT",
    done = "Mined",
    notDone = "Not mined yet",
    -- Copper to gold.
    colors = { { 0.75, 0.45, 0.25 }, { 1.00, 0.55, 0.10 }, { 1.00, 0.82, 0.00 } },
    Tint = function(name)
        local lower = name:lower()
        for _, tint in ipairs(TINTS) do
            if lower:find(tint[1], 1, true) then
                return tint[2], tint[3], tint[4]
            end
        end
        return 0.6, 0.6, 0.62
    end,
    skill = { line = 186, name = "Mining", gated = true },

    casts = { "Mining" },
    spellIDs = { 2575 },
    professionWords = { "Mining" },
    -- Used where nothing else says what a name is, such as a tracking blip
    -- on the minimap. English only.
    nameWords = { "Vein", "Deposit" },
})
