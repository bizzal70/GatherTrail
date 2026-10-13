-- Minimal fake of the WoW API, enough to execute GatherTrail end to end.
local frames = {}
local player = { map = 1, x = 0.5, y = 0.5, facing = 0 }
local printed = {}
_G.PLAYER = player
_G.PRINTED = printed

local function Stub()
    local o = { __scripts = {}, __events = {}, __shown = true }
    return setmetatable(o, { __index = function(t, k)
        -- Widget methods are PascalCase; anything else is an unset field.
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        local f
        if k == "SetScript" then f = function(self, ev, fn) self.__scripts[ev] = fn end
        elseif k == "HookScript" then f = function(self, ev, fn)
            local previous = self.__scripts[ev]
            self.__scripts[ev] = previous and function(...) previous(...); fn(...) end or fn
        end
        elseif k == "RegisterEvent" or k == "RegisterUnitEvent" then f = function(self, ev) self.__events[ev] = true end
        elseif k == "UnregisterEvent" then f = function(self, ev) self.__events[ev] = nil end
        elseif k:match("^Create") or k == "GetCanvas" then f = function() local c = Stub(); frames[#frames + 1] = c; return c end
        elseif k == "GetSize" then f = function() return 1000, 667 end
        elseif k == "GetWidth" then f = function() return 140 end
        elseif k == "GetHeight" then f = function() return 140 end
        elseif k == "GetEffectiveScale" or k == "GetScale" then f = function() return 1 end
        elseif k == "GetCenter" then f = function() return 100, 100 end
        elseif k == "GetPoint" then f = function() return "CENTER", nil, "CENTER", 0, 0 end
        elseif k == "IsShown" or k == "IsVisible" then f = function(self) return self.__shown end
        elseif k == "SetOwner" then f = function(self, ...) self.__owner = { ... } end
        elseif k == "SetVertexColor" then f = function(self, ...) self.__color = { ... } end
        elseif k == "Show" then f = function(self) self.__shown = true end
        elseif k == "Hide" then f = function(self) self.__shown = false end
        elseif k == "SetShown" then f = function(self, v) assert(type(v) == "boolean", "SetShown needs boolean"); self.__shown = v end
        elseif k == "SetText" then f = function(self, v) assert(v ~= nil, "SetText nil"); self.__text = tostring(v) end
        elseif k == "GetText" then f = function(self) return self.__text end
        elseif k == "GetMapID" then f = function() return player.map end
        elseif k == "SetPoint" then f = function(self, ...) self.__point = { ... } end
        elseif k == "GetFrameLevel" then f = function() return 1 end
        elseif k == "GetName" then f = function(self) return self.__name end
        elseif k == "IsMouseOver" then f = function(self) return self == Minimap and MOUSE_OVER_MINIMAP end
        else f = function() end end
        return f
    end })
end

function CreateFrame(_, name) local f = Stub(); frames[#frames + 1] = f; f.__name = name; if name then _G[name] = f end; return f end
UIParent, Minimap, GameTooltip, GameTooltipTextLeft1, GameTooltipTextLeft2 = Stub(), Stub(), Stub(), Stub(), Stub()
GameTooltip.__shown = false
WorldMapFrame = Stub(); WorldMapFrame.OnMapChanged = function() end
UISpecialFrames = {}
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
BreakUpLargeNumbers = function(n) return tostring(n) end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, MAP_PING = 3175 }
tinsert = table.insert
-- Like the real one: the original runs first, then the hook, and the
-- original's results are what the caller gets. Works on a global function
-- (name, hook) or a method (table, name, hook).
hooksecurefunc = function(a, b, c)
    local owner, name, hook = _G, a, b
    if type(a) == "table" then owner, name, hook = a, b, c end
    local original = owner[name]
    assert(type(original) == "function", "hooksecurefunc: no function called " .. tostring(name))
    rawset(owner, name, function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end)
end
SlashCmdList = {}
time, date = os.time, os.date
NOW = 1000           -- session clock, advanced by the tests
GetTime = function() return NOW end
print = function(m) printed[#printed + 1] = m end
issecretvalue = function() return false end
IN_COMBAT = false
InCombatLockdown = function() return IN_COMBAT end
GetCursorPosition = function() return 150, 120 end
GetPlayerFacing = function() return player.facing end
UnitLevel = function(unit) if unit ~= "player" and UNITS and UNITS[unit] then return UNITS[unit].level end return 22 end
UnitFactionGroup = function() return "Alliance" end
Enum = {}

-- World layout: zones are 1000 x 667 yards. Zone m sits (m - 1) zones west
-- of zone 1 on continent 0, except zone 3, which is on continent 1. Map 10
-- is the continent-wide map of continent 0, used as the flight map.
function Geo(mapID)
    if mapID == 3 then return { inst = 1, origin = 0, width = 1000 } end
    if mapID == 10 then return { inst = 0, origin = -4000, width = 5000 } end
    return { inst = 0, origin = -(mapID - 1) * 1000, width = 1000 }
end

PLAYER_GUID = "Player-1"
ON_TAXI, IS_DEAD, SPEED = false, false, 7
TAXI_NODES = {}
TICKERS = {}
UnitGUID = function(unit)
    if unit and unit ~= "player" then return UNITS[unit] and (UNITS[unit].guid or UNITS[unit].name) end
    return PLAYER_GUID
end
-- This character's professions: skill line id -> skill level
SKILLS = {}
GetProfessions = function()
    local first, second
    for line in pairs(SKILLS) do
        if not first then first = line elseif not second then second = line end
    end
    return first, second
end
GetProfessionInfo = function(line) return "Profession", "icon", SKILLS[line], 300, 0, 0, line end
-- Other units, keyed by unit token: { name, class, level, dead, player }
UNITS = {}
UnitExists = function(unit) return UNITS[unit] ~= nil end
UnitClassification = function(unit) return UNITS[unit] and UNITS[unit].class end
UnitName = function(unit) return UNITS[unit] and UNITS[unit].name end
UnitIsPlayer = function(unit) return UNITS[unit] and UNITS[unit].player or false end
UnitPlayerControlled = function(unit) return UNITS[unit] and UNITS[unit].player or false end
UnitIsDead = function(unit) return UNITS[unit] and UNITS[unit].dead or false end
UnitCanAttack = function(_, unit) return UNITS[unit] and not UNITS[unit].friendly or false end
-- The game's minimap markers: guid -> { name, atlasName, x, y }
VIGNETTES = {}
C_VignetteInfo = {
    GetVignettes = function() local list = {}; for guid in pairs(VIGNETTES) do list[#list + 1] = guid end; return list end,
    GetVignetteInfo = function(guid) return VIGNETTES[guid] end,
    GetVignettePosition = function(guid) local v = VIGNETTES[guid]; return v and CreateVector2D(v.x, v.y) end,
}
UnitOnTaxi = function() return ON_TAXI end
UnitIsDeadOrGhost = function() return IS_DEAD end
GetTaxiMapID = function() return 10 end
C_TaxiMap = { GetAllTaxiNodes = function() return TAXI_NODES end }
AFTERS = {}          -- delayed callbacks, run by the tests
LOOT = {}            -- item names in the open loot window
GetNumLootItems = function() return #LOOT end
GetLootSlotInfo = function(slot) return "icon", LOOT[slot], 1 end
C_Timer = {
    NewTicker = function(_, fn) TICKERS[#TICKERS + 1] = fn end,
    After = function(_, fn) AFTERS[#AFTERS + 1] = fn end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
local function Vec(x, y) return { GetXY = function() return x, y end } end
CreateVector2D = Vec
MOUSE_OVER_MINIMAP = false
ROTATE_MINIMAP = "0"
C_CVar = { GetCVar = function(name) if name == "rotateMinimap" then return ROTATE_MINIMAP end end }
C_Minimap = { GetViewRadius = function() return 100 end }
WAYPOINT = nil       -- the current user map pin
SUPERTRACKED = false
SOUNDS = 0
GetUnitSpeed = function() return SPEED end
PlaySound = function() SOUNDS = SOUNDS + 1 end
C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(v) SUPERTRACKED = v end,
    IsSuperTrackingUserWaypoint = function() return SUPERTRACKED end,
}
C_Map = {
    HasUserWaypoint = function() return WAYPOINT ~= nil end,
    GetUserWaypoint = function() return WAYPOINT end,
    ClearUserWaypoint = function() WAYPOINT = nil; SUPERTRACKED = false end,
    GetBestMapForUnit = function() return player.map end,
    GetPlayerMapPosition = function(mapID) if mapID == player.map then return Vec(player.x, player.y) end end,
    GetMapWorldSize = function(mapID) return Geo(mapID).width, 667 end,
    GetMapInfo = function(mapID) return { name = "Zone" .. mapID, mapType = mapID == 10 and 2 or 3 } end,
    GetWorldPosFromMapPos = function(mapID, pos)
        local geo, x, y = Geo(mapID), pos:GetXY()
        return geo.inst, Vec(geo.origin + x * geo.width, y * 667)
    end,
    GetMapPosFromWorldPos = function(_, pos, mapID)
        local geo, wx, wy = Geo(mapID), pos:GetXY()
        return mapID, Vec((wx - geo.origin) / geo.width, wy / 667)
    end,
    -- Which zone a point on the continent map (10) falls in.
    GetMapInfoAtPosition = function(mapID, x)
        local wx = Geo(mapID).origin + x * Geo(mapID).width
        for _, zone in ipairs({ 1, 2, 5 }) do
            local geo = Geo(zone)
            if wx >= geo.origin and wx < geo.origin + geo.width then return { mapID = zone } end
        end
    end,
    -- Like the real client, it has nothing to say about most maps: only
    -- maps 1 to 15 get an answer.
    GetMapLevels = function(mapID)
        if mapID > 15 then return 0, 0 end
        if mapID == 2 then return 30, 40 end
        return 10, 20
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) WAYPOINT = point end,
    OpenWorldMap = function() end,
}
C_Spell = { GetSpellName = function(id)
    if id == 2575 or id == 7777 then return "Mining" end
    if id == 2366 or id == 8888 then return "Herb Gathering" end
    if id == 7620 or id == 9999 then return "Fishing" end
    if id == 8613 or id == 6666 then return "Skinning" end
    if id == 3365 or id == 5555 then return "Opening" end
    return "Fireball"
end }
C_PvP = { GetZonePVPInfo = function() return player.map == 2 and "hostile" or "friendly" end }

function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end
function Frames() return frames end

-- The files an addon's TOC lists, in order. Loading from the TOC means a
-- file that was written but never added to it is caught here, not in game.
function TocFiles(dir, name)
    local files = {}
    local toc = assert(io.open(dir .. "/" .. name .. ".toc", "r"), "no TOC for " .. name)
    for line in toc:lines() do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            -- TOC paths use backslashes; forward slashes open everywhere.
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    toc:close()
    return files
end

ADDON_VERSION = "0.0.0-test"
C_AddOns = { GetAddOnMetadata = function() return ADDON_VERSION end }

function LoadAddon(dir, name, files)
    files = files or TocFiles(dir, name)
    local ns = {}
    for _, file in ipairs(files) do
        local h = assert(io.open(dir .. "/" .. file, "r")); local src = h:read("*a"); h:close()
        local chunk = assert(loadstring(src, "@" .. file))
        chunk(name, ns)
    end
    return ns
end
