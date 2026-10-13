local _, ns = ...

-- Fishing pools. A Fishing cast has no target and can be made anywhere, and
-- a pool's tooltip does not name the profession, so pools are recognised by
-- their names and a cast is tied to a pool by what the player last pointed
-- at. Open-water fishing records nothing.

-- A pool sits out in the water, about this far in front of someone fishing it.
local FORWARD_YARDS = 15
-- A cast counts for a pool pointed at this recently, from this close to
-- where the player stood when pointing.
local CAST_SECONDS = 30
local CAST_YARDS = 15

-- The pool last pointed at, and where the player stood at the time.
local lastPool

ns.RegisterKind({
    key = "fish",
    order = 3,
    label = "Fish",
    plural = "Fishing pools",
    any = "Any pool",
    heading = "BEST PLACES TO FISH IT",
    done = "Fished",
    notDone = "Not fished yet",
    -- Teal.
    colors = { { 0.20, 0.60, 0.55 }, { 0.25, 0.80, 0.70 }, { 0.35, 1.00, 0.85 } },
    tint = { 0.30, 0.75, 0.90 },
    skill = { line = 356, name = "Fishing" },
    -- A pool's position is estimated from where the player stood.
    mergeYards = 30,

    casts = { "Fishing" },
    spellIDs = { 7620 },
    -- "Oily Blackmouth School", "Floating Wreckage". On other languages
    -- pools are learned with "/gt add fish <name>" and known by name after.
    nameWords = { "School", "Pool", "Wreckage", "Debris", "Swarm", "Floating", "Oil Spill" },

    Sighted = function(_, name)
        local mapID, x, y = ns.GetPlayerPosition()
        lastPool = mapID and { name = name, time = GetTime(), map = mapID, x = x, y = y } or nil
    end,

    ResolveTarget = function()
        local mapID, x, y = ns.GetPlayerPosition()
        if lastPool and mapID == lastPool.map and GetTime() - lastPool.time <= CAST_SECONDS
            and ns.Distance(mapID, x, y, lastPool.x, lastPool.y) <= CAST_YARDS then
            return lastPool.name
        end
    end,

    -- The pool is placed out in front of the player, not under their feet.
    Finish = function(self, name, outcome)
        ns.RecordNode(name, outcome, false, self.key, FORWARD_YARDS)
    end,
})
