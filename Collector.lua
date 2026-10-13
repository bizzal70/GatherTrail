local _, ns = ...

-- The collection engine. It watches the three things most kinds of node
-- have in common and leaves what is particular to each kind to the files in
-- Kinds\, which describe themselves with ns.RegisterGatherer:
--
--   * a cast on the node (mining a vein, opening a chest)   -> gathered,
--     or a failed attempt
--   * the node's tooltip under the cursor                    -> a sighting
--   * a skill error naming the profession                    -> refused
--
-- A gatherer is a table with:
--   key              the kind it records: "ore", "herb", "fish", ...
--   casts            names the gathering cast can have. Casts are matched
--                    by name because the spell IDs on this client are not
--                    known; /gt debug prints the real names and IDs.
--   spellIDs         original-game spells whose names, if they exist here,
--                    are added to casts so other languages work
--   professionWords  what a node's tooltip or a skill error calls the
--                    profession ("Mining"); optional
--   nameWords        whole words that mark a bare name as this kind of
--                    node ("Vein"); English only; optional
-- and, optionally, three functions for kinds that do not fit the pattern:
--   ResolveTarget(self, targetName)  the name to record for a cast, or nil
--                                    to ignore the cast
--   Finish(self, name, outcome)      called instead of the default record
--                                    when the cast ends; outcome is "mined"
--                                    or "failed"
--   Sighted(self, name)              called when the node is pointed at

local gatherers = {}       -- key -> gatherer
local order = {}           -- gatherers in the order they registered
local castGatherer = {}    -- cast name -> gatherer
local professionWords = {} -- { word, gatherer } pairs

local function AddProfessionWord(word, gatherer)
    for _, entry in ipairs(professionWords) do
        if entry[1] == word then return end
    end
    professionWords[#professionWords + 1] = { word, gatherer }
end

function ns.RegisterGatherer(gatherer)
    gatherers[gatherer.key] = gatherer
    order[#order + 1] = gatherer
    for _, name in ipairs(gatherer.casts or {}) do
        castGatherer[name] = gatherer
    end
    for _, word in ipairs(gatherer.professionWords or {}) do
        AddProfessionWord(word, gatherer)
    end
end

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

-- Whether a name contains a word as a whole word, so that "Lode" would not
-- match "Lodestone", nor "Pool" match "Whirlpool".
function ns.HasWord(name, word)
    return name:find("%f[%a]" .. word .. "%f[%A]") ~= nil
end

-- Whether a name contains one of a gatherer's nameWords.
function ns.NameFits(gatherer, name)
    for _, word in ipairs(gatherer.nameWords or {}) do
        if ns.HasWord(name, word) then return true end
    end
    return false
end

-- Which kind a bare name belongs to, judged by the name alone: one already
-- in the saved data, or one that reads like a kind's nodes. Where two kinds
-- could both claim a name, the one registered first (listed first in the
-- TOC) gets it.
function ns.ClassifyNodeName(name)
    if castGatherer[name] then return end
    local known = ns.knownNames[name]
    if known then return known end
    for _, gatherer in ipairs(order) do
        if ns.NameFits(gatherer, name) then return gatherer.key end
    end
end

-- Which kind's profession a piece of text names, if any.
local function ProfessionMentioned(text)
    if not ns.IsUsable(text) then return end
    for _, entry in ipairs(professionWords) do
        if text:find(entry[1], 1, true) then return entry[2].key end
    end
end

local function SpellName(spellID)
    if not ns.IsUsable(spellID) then return end
    local name = C_Spell.GetSpellName(spellID)
    if ns.IsUsable(name) then return name end
end

---------------------------------------------------------------------------
-- Tooltips: sightings
---------------------------------------------------------------------------

local function TooltipLine(fontString)
    if not fontString or not fontString:IsShown() then return end
    local text = fontString:GetText()
    if ns.IsUsable(text) and text ~= "" then return text end
end

-- The name and kind of the node under the cursor, if there is one. A node's
-- tooltip names the profession on its second line, or carries a name that
-- ns.ClassifyNodeName recognises.
local function HoveredNode()
    if not GameTooltip:IsShown() then return end
    local name = TooltipLine(GameTooltipTextLeft1)
    if not name or castGatherer[name] then return end
    local kind = ProfessionMentioned(TooltipLine(GameTooltipTextLeft2)) or ns.ClassifyNodeName(name)
    if kind then
        return name, kind
    end
end

-- The node's name normally arrives as the cast target. If it does not, the
-- tooltip under the cursor is the node being clicked.
local function TargetName(target)
    if ns.IsUsable(target) and target ~= "" then
        return target
    end
    return GameTooltip:IsShown() and TooltipLine(GameTooltipTextLeft1) or nil
end

-- Any character that points at a node learns roughly where it is, whether
-- or not they can gather it. The position is the character's, so it is
-- stored as approximate.
local lastSeenName, lastSeenTime = nil, 0

local function OnTooltip(tooltip)
    if tooltip ~= GameTooltip then return end
    -- Minimap blips are handled in MinimapPins.lua, which knows where on
    -- the map the cursor is pointing.
    if Minimap:IsMouseOver() then return end
    local name, kind = HoveredNode()
    if ns.db.debug then
        local first = TooltipLine(GameTooltipTextLeft1)
        if first then
            ns.Print(("tooltip: \"%s\" / \"%s\" is %s"):format(first,
                TooltipLine(GameTooltipTextLeft2) or "", kind or "not a node I recognise"))
        end
    end
    if not name then return end

    local gatherer = gatherers[kind]
    if gatherer and gatherer.Sighted then
        gatherer:Sighted(name)
    end
    local now = GetTime()
    if name == lastSeenName and now - lastSeenTime < 5 then return end
    lastSeenName, lastSeenTime = name, now
    ns.RecordNode(name, "seen", true, kind)
end

---------------------------------------------------------------------------
-- Casts: gathered, or tried and failed
---------------------------------------------------------------------------

-- The gathering cast in progress: { cast = its id, name = the node,
-- gatherer = whose cast it is }.
local pending

local handlers = {}

function handlers.UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    local castName = SpellName(spellID)
    local targetName = TargetName(target)
    if ns.db.debug then
        ns.Print(("cast sent: %s (id %s), target %s"):format(
            tostring(castName), ns.IsUsable(spellID) and tostring(spellID) or "?", tostring(targetName)))
    end

    pending = nil
    local gatherer = castName and castGatherer[castName]
    if not gatherer or not ns.IsUsable(castGUID) then return end
    local name = targetName
    if gatherer.ResolveTarget then
        name = gatherer:ResolveTarget(targetName)
    end
    -- Opening the profession window is also a cast with the profession's
    -- name; a real node has a name that differs from it.
    if name and not castGatherer[name] then
        pending = { cast = castGUID, name = name, gatherer = gatherer }
    end
end

local function FinishCast(castGUID, outcome)
    local cast = pending
    if not cast or not ns.IsUsable(castGUID) or castGUID ~= cast.cast then return end
    pending = nil
    if cast.gatherer.Finish then
        cast.gatherer:Finish(cast.name, outcome)
    else
        -- A cast only starts within reach of the node, so the position is
        -- exact even when the cast then fails.
        ns.RecordNode(cast.name, outcome, false, cast.gatherer.key)
    end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(_, castGUID)
    FinishCast(castGUID, "mined")
end

local function CastFailed(_, castGUID)
    FinishCast(castGUID, "failed")
end
handlers.UNIT_SPELLCAST_FAILED = CastFailed
handlers.UNIT_SPELLCAST_FAILED_QUIET = CastFailed
handlers.UNIT_SPELLCAST_INTERRUPTED = CastFailed

---------------------------------------------------------------------------
-- Skill errors: refused
---------------------------------------------------------------------------

-- Clicking a node without the skill for it never starts a cast; the game
-- just shows an error that names the profession.
function handlers.UI_ERROR_MESSAGE(_, message)
    if ns.db.debug and ns.IsUsable(message) then
        ns.Print("error message: " .. message)
    end
    local kind = ProfessionMentioned(message)
    if not kind then return end
    local name = HoveredNode() or TargetName(nil)
    if name and not castGatherer[name] then
        ns.RecordNode(name, "failed", true, kind)
        ns.NoteRefused(name, kind, message)
    end
end

---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
frame:RegisterEvent("UNIT_SPELLCAST_SENT")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
-- Registering an event this client does not have throws, so the less
-- certain ones are registered defensively.
for _, event in ipairs({ "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
    pcall(frame.RegisterUnitEvent, frame, event, "player")
end
pcall(frame.RegisterEvent, frame, "UI_ERROR_MESSAGE")

ns.onLogin[#ns.onLogin + 1] = function()
    -- Add each cast's name in the client's own language.
    for _, gatherer in ipairs(order) do
        for _, spellID in ipairs(gatherer.spellIDs or {}) do
            local localized = SpellName(spellID)
            if localized then
                castGatherer[localized] = gatherer
                if gatherer.professionWords then
                    AddProfessionWord(localized, gatherer)
                end
            end
        end
    end

    if TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, OnTooltip)
    else
        GameTooltip:HookScript("OnShow", OnTooltip)
    end
end
