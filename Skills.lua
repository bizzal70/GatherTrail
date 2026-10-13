local _, ns = ...

-- Learns how much profession skill each kind of node needs from the
-- account's own history, so the ranking does not send a character to
-- nodes it cannot gather yet.
--
-- For each node name, ns.db.skills[name] may hold:
--   need      the requirement, when a skill error stated it
--   gotAt     the lowest skill any character has gathered it with
--   lackedAt  the highest skill any character was refused at

-- Whether a kind's nodes are refused outright for lack of skill.
local function Gated(profession)
    local skill = ns.KINDS[profession].skill
    return skill and skill.gated or false
end

-- Which kind a profession, as the game reports it, gathers.
local function KindOfSkill(skillLine, name)
    for key, kind in pairs(ns.KINDS) do
        local skill = kind.skill
        if skill and ((ns.IsUsable(skillLine) and skill.line == skillLine) or (ns.IsUsable(name) and skill.name == name)) then
            return key
        end
    end
end

-- This character's skill in the profession that gathers a kind of node, or
-- nil if they have not learned it (or the client will not say).
function ns.GetSkill(profession)
    if not GetProfessions or not GetProfessionInfo then return end
    for slot = 1, 5 do
        local index = (select(slot, GetProfessions()))
        if ns.IsUsable(index) then
            local name, _, level, _, _, _, skillLine = GetProfessionInfo(index)
            if KindOfSkill(skillLine, name) == profession and ns.IsUsable(level) then
                return level
            end
        end
    end
end

local function Info(name)
    local info = ns.db.skills[name]
    if not info then
        info = {}
        ns.db.skills[name] = info
    end
    return info
end

-- Called when a node is gathered.
function ns.NoteGathered(name, profession)
    if not Gated(profession) then return end
    local skill = ns.GetSkill(profession)
    if not skill then return end
    local info = Info(name)
    if not info.gotAt or skill < info.gotAt then
        info.gotAt = skill
    end
end

-- Called when the game refuses a node with a skill error. The error text
-- sometimes states the requirement ("Requires Mining 125").
function ns.NoteRefused(name, profession, message)
    if not Gated(profession) then return end
    local info = Info(name)
    local need = ns.IsUsable(message) and tonumber(message:match("(%d+)"))
    if need and need > 0 and need <= 1000 then
        info.need = need
        return
    end
    local skill = ns.GetSkill(profession)
    if skill and (not info.lackedAt or skill > info.lackedAt) then
        info.lackedAt = skill
    end
end

-- Whether this character can gather a node of that name: "yes", "no", or
-- "unknown" when the history does not settle it. With "no", also returns
-- the skill needed if it is known.
function ns.CanGather(name, profession)
    if not Gated(profession) then return "yes" end
    local skill = ns.GetSkill(profession)
    local info = ns.db.skills[name]
    -- A character without the profession is only scouting; nothing is ruled
    -- out for them.
    if not skill or not info then return "unknown" end
    if info.need then
        if skill >= info.need then return "yes" end
        return "no", info.need
    end
    if info.gotAt and skill >= info.gotAt then return "yes" end
    if info.lackedAt and skill <= info.lackedAt then return "no" end
    return "unknown"
end
