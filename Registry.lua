local _, ns = ...

-- Every kind of thing the addon tracks is described once, in its own file
-- under Kinds\, and registered here. The rest of the addon (the window,
-- the options page, both maps, the ranking, the saved-data rules) reads
-- what it needs from that description instead of keeping its own lists.
--
-- A kind is a table with:
--   key       what records are filed under: "ore", "herb", "fish", ...
--   order     its place among the window's tabs and the options list
--   label     its tab ("Ore")
--   plural    its name in the options page and messages ("Fishing pools")
--   any       the list entry for all of it ("Any ore")
--   heading   the heading over the ranking ("BEST PLACES TO MINE IT")
--   done      past-tense verb for the tooltip ("Mined")
--   notDone   the tooltip line when it has only been seen ("Not mined yet")
--   colors    three pin colours: gathered once, twice or more, five or more
--   tint      colour of the swatch in the window's list; or Tint(name) for
--             a kind whose types have colours of their own
-- and, where they apply:
--   skill           { line = the game's skill line, name = "Mining",
--                     gated = true if a node is refused for lack of skill }
--   mergeYards      how close two finds must be to count as the same one,
--                   when looser than the default
--   repeatsAtOnce   every find counts, however soon after the last
--   quietAfterFirst the chat line for the first find in a place (name,
--                   zone); later finds there are not announced
--   neverStale      routes do not pass it by for having just been gathered
--   notKnownByName  its names are items or creatures, not objects to
--                   recognise when the name shows in a tooltip
--   countsSightings its pin colour grows with sightings as well as finds
--   Weight(count)   what one place is worth in the ranking, when not the
--                   default
-- plus the fields the collection engine reads; see Collector.lua.

ns.KINDS = {}

local list = {}

function ns.RegisterKind(kind)
    ns.KINDS[kind.key] = kind
    list[#list + 1] = kind
    table.sort(list, function(a, b) return a.order < b.order end)
    if kind.casts then
        ns.RegisterGatherer(kind)
    end
end

-- Every kind, in tab order.
function ns.KindList()
    return list
end
