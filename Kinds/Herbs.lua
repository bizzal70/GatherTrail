local _, ns = ...

-- Herbs. They share no word in their names, so a herb is recognised by its
-- tooltip naming the profession, or by a name already in the saved data.

ns.RegisterKind({
    key = "herb",
    order = 2,
    label = "Herbs",
    plural = "Herbs",
    any = "Any herb",
    heading = "BEST PLACES TO PICK IT",
    done = "Picked",
    notDone = "Not picked yet",
    -- Violet.
    colors = { { 0.55, 0.38, 0.70 }, { 0.72, 0.45, 0.88 }, { 0.90, 0.55, 1.00 } },
    tint = { 0.45, 0.80, 0.45 },
    skill = { line = 182, name = "Herbalism", gated = true },

    casts = { "Herb Gathering", "Herbalism" },
    spellIDs = { 2366 },
    professionWords = { "Herbalism", "Herb Gathering" },
})
