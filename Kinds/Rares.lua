local _, ns = ...

-- Rare creatures, found three ways:
--   * the game's own minimap markers (vignettes), which carry an exact
--     position and need no action from the player;
--   * any rare the player targets, mouses over, or gets a nameplate for,
--     recorded at the player's own position because the client does not
--     say where another creature stands;
--   * looting a dead rare, which counts as a kill at an exact position.
-- Treasure markers among the vignettes are recorded as chests.

local RARE_CLASSES = { rare = true, rareelite = true }

-- Rares are not gathered by a cast, so this kind has no collection fields;
-- the events below do the recording.
ns.RegisterKind({
    key = "rare",
    order = 6,
    label = "Rares",
    plural = "Rare creatures",
    any = "Any rare",
    heading = "BEST PLACES TO HUNT IT",
    done = "Killed",
    notDone = "Not killed yet",
    -- Pink.
    colors = { { 0.75, 0.30, 0.50 }, { 0.90, 0.32, 0.58 }, { 1.00, 0.35, 0.65 } },
    tint = { 1.00, 0.35, 0.65 },
    neverStale = true,
    notKnownByName = true,
    countsSightings = true,
})

-- Each minimap marker is recorded once per session.
local seenVignettes = {}

-- Reads a unit fact that the client may withhold; nil means "do not know".
local function Fact(value)
    if ns.IsUsable(value) then return value end
end

-- The unit's name and classification if it is a rare creature.
local function RareUnit(unit)
    if not Fact(UnitExists(unit)) then return end
    local class = Fact(UnitClassification(unit))
    if not class or not RARE_CLASSES[class] then return end
    if Fact(UnitIsPlayer(unit)) or Fact(UnitPlayerControlled(unit)) then return end
    local name = Fact(UnitName(unit))
    if not name or name == "" then return end
    return name, class
end

local function Describe(node, unit, class)
    if not node then return end
    node.elite = class == "rareelite" or nil
    local level = Fact(UnitLevel(unit))
    if level and level > 0 then
        node.level = level
    end
end

local function OnUnitSeen(unit)
    local name, class = RareUnit(unit)
    if name then
        Describe(ns.RecordNode(name, "seen", true, "rare"), unit, class)
    end
end

-- Looting a dead rare means it was killed, and the player is at its corpse.
local function OnLoot()
    local name, class = RareUnit("target")
    if name and Fact(UnitIsDead("target")) then
        Describe(ns.RecordNode(name, "mined", false, "rare"), "target", class)
    end
end

-- Blizzard's marker art names say what a marker is for.
local function VignetteProfession(atlas)
    local lower = atlas:lower()
    if lower:find("kill", 1, true) then
        return "rare"
    elseif lower:find("loot", 1, true) then
        return "chest"
    end
end

local function ScanVignettes()
    local mapID = Fact(C_Map.GetBestMapForUnit("player"))
    local guids = mapID and C_VignetteInfo.GetVignettes()
    if not guids then return end
    for _, guid in ipairs(guids) do
        if ns.IsUsable(guid) and not seenVignettes[guid] then
            local info = C_VignetteInfo.GetVignetteInfo(guid)
            local name = info and Fact(info.name)
            local atlas = info and Fact(info.atlasName)
            local profession = name and name ~= "" and atlas and VignetteProfession(atlas)
            local position = profession and Fact(C_VignetteInfo.GetVignettePosition(guid, mapID))
            if position then
                local x, y = position:GetXY()
                if ns.IsUsable(x) and ns.IsUsable(y) then
                    seenVignettes[guid] = true
                    ns.RecordNode(name, "seen", false, profession, { x = x, y = y })
                end
            end
        end
    end
end

local handlers = {
    PLAYER_TARGET_CHANGED = function() OnUnitSeen("target") end,
    UPDATE_MOUSEOVER_UNIT = function() OnUnitSeen("mouseover") end,
    NAME_PLATE_UNIT_ADDED = function(unit) if ns.IsUsable(unit) then OnUnitSeen(unit) end end,
    LOOT_READY = OnLoot,
    LOOT_OPENED = OnLoot,
    VIGNETTE_MINIMAP_UPDATED = ScanVignettes,
    VIGNETTES_UPDATED = ScanVignettes,
}

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
-- Registering an event this client does not have throws.
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end
