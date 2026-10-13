local _, ns = ...

-- Treasure chests. "Opening" is the cast for chests, but also for levers,
-- doors and quest objects, so it only counts on a name that reads like a
-- chest. The same words recognise chests under the cursor and on the
-- minimap. English only.

ns.RegisterKind({
    key = "chest",
    order = 5,
    label = "Chests",
    plural = "Treasure chests",
    any = "Any chest",
    heading = "BEST PLACES TO FIND IT",
    done = "Opened",
    notDone = "Not opened yet",
    -- Grey to white.
    colors = { { 0.68, 0.68, 0.68 }, { 0.85, 0.85, 0.85 }, { 1.00, 1.00, 1.00 } },
    tint = { 0.92, 0.92, 0.92 },

    casts = { "Opening" },
    spellIDs = { 3365 },
    nameWords = { "Chest", "Lockbox", "Footlocker", "Strongbox", "Coffer", "Cache", "Trunk", "Treasure" },

    ResolveTarget = function(self, targetName)
        if targetName and ns.NameFits(self, targetName) then
            return targetName
        end
    end,
})
