local _, ns = ...

local WIDTH, HEIGHT = 780, 480
local HEADER_HEIGHT, STATS_HEIGHT, FOOTER_HEIGHT = 40, 24, 54
local PADDING = 12
local TYPE_WIDTH, TYPE_ROW = 290, 24
local ZONE_WIDTH, ZONE_ROW = WIDTH - TYPE_WIDTH - PADDING * 3, 64
local LIST_TOP = HEADER_HEIGHT + STATS_HEIGHT + 30
local LIST_HEIGHT = HEIGHT - LIST_TOP - FOOTER_HEIGHT - PADDING
local SCORE_BAR_WIDTH = 86

local UI = ns.UI
local Fill, Gradient, Outline, Label, Heading = UI.Fill, UI.Gradient, UI.Outline, UI.Label, UI.Heading
local Num, Click, CreateButton, CreateList = UI.Num, UI.Click, UI.CreateButton, UI.CreateList
local ACCENT_R, ACCENT_G, ACCENT_B = unpack(UI.ACCENT)

local window, typeList, zoneList, contextLabel, statsLabel, emptyText
local skillLabel, optionsButton
local summaryTitle, summaryDetail, startButton, mapButton, stopButton
local zoneHeading
local tabs = {}
local profession = "ore"   -- which tab is showing; the key of a kind
local selectedTypes = {}
local selectedZone
local topScore = 1

---------------------------------------------------------------------------
-- Type rows: checkbox, colour swatch, name, node count
---------------------------------------------------------------------------

-- The swatch colour for one type of the open tab's kind.
local function Tint(name)
    local kind = ns.KINDS[profession]
    if kind.Tint then
        return kind.Tint(name)
    end
    return kind.tint[1], kind.tint[2], kind.tint[3]
end

local function BuildTypeRow(row)
    row.selected = Fill(row, ACCENT_R, ACCENT_G, ACCENT_B, 0.16)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)

    local box = CreateFrame("Frame", nil, row)
    box:SetSize(12, 12)
    box:SetPoint("LEFT", 8, 0)
    Fill(box, 0, 0, 0, 0.5)
    Outline(box, ACCENT_R, ACCENT_G, ACCENT_B, 0.7)
    row.check = box:CreateTexture(nil, "ARTWORK")
    row.check:SetPoint("TOPLEFT", 3, -3)
    row.check:SetPoint("BOTTOMRIGHT", -3, 3)
    row.check:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    row.swatch = row:CreateTexture(nil, "ARTWORK")
    row.swatch:SetSize(10, 10)
    row.swatch:SetPoint("LEFT", box, "RIGHT", 8, 0)

    row.name = Label(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.swatch, "RIGHT", 7, 0)
    row.name:SetPoint("RIGHT", -44, 0)
    row.count = Label(row, "GameFontHighlightSmall", "RIGHT")
    row.count:SetPoint("RIGHT", -8, 0)
    row.count:SetTextColor(0.72, 0.72, 0.72)
end

local function ConfigureTypeRow(row, item)
    local selected
    if item.any then
        selected = not next(selectedTypes)
        row.swatch:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    else
        selected = selectedTypes[item.name] or false
        row.swatch:SetColorTexture(Tint(item.name))
    end
    row.name:SetText(item.name)
    -- A node type this character lacks the skill for is greyed, with the
    -- skill it needs if that is known.
    local able, need = "yes", nil
    if not item.any then
        able, need = ns.CanGather(item.name, profession)
    end
    if able == "no" then
        row.name:SetTextColor(0.55, 0.55, 0.55)
        row.count:SetText(need and ("|cffff5050needs %d|r"):format(need) or "|cffff5050skill too low|r")
    else
        row.name:SetTextColor(1, 1, 1)
        row.count:SetText(Num(item.nodes))
    end
    row.selected:SetShown(selected)
    row.check:SetShown(selected)
end

---------------------------------------------------------------------------
-- Zone cards: rank badge, name, score bar, details, level and faction tags
---------------------------------------------------------------------------

local PVP_TAGS = {
    hostile = "|cffff5050Hostile|r",
    contested = "|cffffa040Contested|r",
    friendly = "|cff50d050Friendly|r",
    sanctuary = "|cff50c0ffSanctuary|r",
}

local function LevelRange(zone)
    if zone.minLevel == zone.maxLevel then
        return tostring(zone.minLevel)
    end
    return zone.minLevel .. "-" .. zone.maxLevel
end

local function TagText(zone)
    local tags = {}
    if zone.minLevel then
        if zone.tooHigh then
            tags[#tags + 1] = "|cffff5050Level " .. LevelRange(zone) .. "|r"
        else
            tags[#tags + 1] = "|cffb0b0b0Level " .. LevelRange(zone) .. "|r"
        end
    end
    if zone.pvp and PVP_TAGS[zone.pvp] then
        tags[#tags + 1] = PVP_TAGS[zone.pvp]
    end
    if zone.tooHard > 0 then
        tags[#tags + 1] = ("|cffff5050Skill too low for %d|r"):format(zone.tooHard)
    end
    return table.concat(tags, "   ")
end

local function TravelText(zone)
    if not zone.travel then
        return "no known way there"
    elseif zone.here and zone.travel < 50 then
        return "you are here"
    elseif zone.via and zone.via ~= "" then
        return Num(zone.travel) .. " yd by known routes"
    elseif zone.here or zone.via then
        return Num(zone.travel) .. " yd away"
    end
    return Num(zone.travel) .. " yd in a straight line"
end

-- Explains how the score was reached.
local function ZoneOnEnter(row)
    local zone = row.item
    if not zone then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(zone.name)
    GameTooltip:AddLine(("%s nodes: %s mined before, %s only spotted or attempted"):format(
        Num(zone.nodeCount), Num(zone.minedCount), Num(zone.nodeCount - zone.minedCount)), 1, 1, 1)
    GameTooltip:AddLine(("One lap of the loop: %s yd"):format(Num(zone.loop)), 1, 1, 1)
    GameTooltip:AddLine("Getting there: " .. TravelText(zone), 1, 1, 1)
    if zone.via and zone.via ~= "" then
        GameTooltip:AddLine(zone.via, 0.7, 0.7, 0.7, true)
    end
    if zone.minLevel then
        local sources = {
            game = "as the game reports it",
            seen = "going by the creatures seen there",
            book = "as it was in the original game; not yet confirmed here",
        }
        GameTooltip:AddLine(("Level %s, %s"):format(LevelRange(zone), sources[zone.levelSource]), 0.7, 0.7, 0.7, true)
    end
    if zone.tooHigh then
        GameTooltip:AddLine("That is above this character, so the score is cut heavily.", 1, 0.35, 0.35, true)
    end
    if zone.pvp == "hostile" then
        GameTooltip:AddLine("Hostile to this character's faction, so the score is cut.", 1, 0.35, 0.35, true)
    end
    if zone.tooHard > 0 then
        GameTooltip:AddLine(("%s of the nodes need more skill than this character has, and are not counted."):format(Num(zone.tooHard)), 1, 0.35, 0.35, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Score %.1f: reliable nodes per 1,000 yd, counting the trip and one lap."):format(zone.score), ACCENT_R, ACCENT_G, ACCENT_B, true)
    GameTooltip:Show()
end

local function BuildZoneRow(row)
    -- The card is inset so neighbouring cards have a gap between them.
    local card = CreateFrame("Frame", nil, row)
    card:SetPoint("TOPLEFT", 0, -2)
    card:SetPoint("BOTTOMRIGHT", 0, 2)
    Fill(card, 1, 1, 1, 0.045)
    row.selected = Fill(card, ACCENT_R, ACCENT_G, ACCENT_B, 0.14, "BORDER")
    row.stripe = card:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(3)
    row.stripe:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", card)
    hover:SetPoint("BOTTOMRIGHT", card)
    hover:SetColorTexture(1, 1, 1, 0.05)

    local badge = CreateFrame("Frame", nil, card)
    badge:SetSize(26, 26)
    badge:SetPoint("LEFT", 12, 0)
    row.badgeFill = Fill(badge, 0, 0, 0, 0.45)
    Outline(badge, ACCENT_R, ACCENT_G, ACCENT_B, 0.6)
    row.rank = Label(badge, "GameFontNormal", "CENTER")
    row.rank:SetPoint("CENTER")

    row.title = Label(card, "GameFontNormalLarge")
    row.title:SetPoint("TOPLEFT", 48, -12)
    row.title:SetPoint("RIGHT", card, "RIGHT", -(SCORE_BAR_WIDTH + 60), 0)
    row.title:SetTextColor(1, 1, 1)

    row.detail = Label(card, "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", 48, 12)
    row.detail:SetTextColor(0.75, 0.75, 0.75)

    -- Score as a bar relative to the best zone, with the figure beside it.
    row.score = Label(card, "GameFontNormal", "RIGHT")
    row.score:SetPoint("TOPRIGHT", -10, -13)
    local track = CreateFrame("Frame", nil, card)
    track:SetSize(SCORE_BAR_WIDTH, 6)
    track:SetPoint("RIGHT", row.score, "LEFT", -8, 0)
    Fill(track, 0, 0, 0, 0.5)
    row.bar = track:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)

    row.tags = Label(card, "GameFontHighlightSmall", "RIGHT")
    row.tags:SetPoint("BOTTOMRIGHT", -10, 12)

    row:SetScript("OnEnter", ZoneOnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ConfigureZoneRow(row, zone)
    local isSelected = zone == selectedZone
    row.rank:SetText(zone.rank)
    row.title:SetText(zone.name)
    row.detail:SetText(("%s nodes   %s yd loop   %s"):format(Num(zone.nodeCount), Num(zone.loop), TravelText(zone)))
    row.score:SetText(("%.1f"):format(zone.score))
    row.bar:SetWidth(math.max(1, SCORE_BAR_WIDTH * math.min(1, zone.score / topScore)))
    row.tags:SetText(TagText(zone))
    row.selected:SetShown(isSelected)
    row.stripe:SetShown(isSelected)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function SelectionText()
    local names = {}
    for name in pairs(selectedTypes) do
        names[#names + 1] = name
    end
    if #names == 0 then return ns.KINDS[profession].any:lower() end
    table.sort(names)
    return table.concat(names, ", ")
end

local function UpdateFooter()
    local _, route = ns.GetRoute()
    stopButton:SetShown(route ~= nil)

    if selectedZone then
        summaryTitle:SetText(("%s  |cffb0b0b0for %s|r"):format(selectedZone.name, SelectionText()))
        local via = selectedZone.via
        if via and via ~= "" then
            summaryDetail:SetText("Trip: " .. via)
        else
            summaryDetail:SetText(("%s nodes on a %s yd loop, %s"):format(
                Num(selectedZone.nodeCount), Num(selectedZone.loop), TravelText(selectedZone)))
        end
        startButton:Show()
        mapButton:Show()
    else
        summaryTitle:SetText("")
        summaryDetail:SetText("")
        startButton:Hide()
        mapButton:Hide()
    end
end

local function StatsText()
    local totalNodes, zones, flights, crossings, transports = 0, 0, 0, 0, 0
    for _, nodes in pairs(ns.db.nodes) do
        totalNodes = totalNodes + #nodes
        if #nodes > 0 then zones = zones + 1 end
    end
    for _ in pairs(ns.db.flights) do
        flights = flights + 1
    end
    for _, link in ipairs(ns.db.links) do
        if link.kind == "walk" then crossings = crossings + 1 else transports = transports + 1 end
    end
    return ("%s nodes in %s zones      %s flight masters      %s zone crossings      %s transports"):format(
        Num(totalNodes), Num(zones), Num(flights), Num(crossings), Num(transports))
end

local function Refresh()
    local level, faction = UnitLevel("player"), UnitFactionGroup("player")
    local mapID = C_Map.GetBestMapForUnit("player")
    contextLabel:SetText(("Level %s %s  |cff808080in|r  %s"):format(
        ns.IsUsable(level) and tostring(level) or "?",
        ns.IsUsable(faction) and faction or "",
        ns.IsUsable(mapID) and ns.MapName(mapID) or "an unknown place"))

    -- The open tab's profession and this character's skill in it, shown at
    -- the right of the strip under the header.
    local skillInfo = ns.KINDS[profession].skill
    local skillName = skillInfo and skillInfo.name
    if skillName then
        local skill = ns.GetSkill(profession)
        if skill then
            skillLabel:SetText(("%s |cffffffff%d|r"):format(skillName, skill))
        else
            skillLabel:SetText(("This character has not learned %s"):format(skillName))
        end
    else
        skillLabel:SetText("")
    end

    local kind = ns.KINDS[profession]
    for key, tab in pairs(tabs) do
        tab.selected:SetShown(key == profession)
    end
    zoneHeading:SetText(kind.heading)

    local types, total = ns.GetNodeTypes(profession)
    statsLabel:SetText(StatsText())

    local known = {}
    for _, entry in ipairs(types) do
        known[entry.name] = true
    end
    for name in pairs(selectedTypes) do
        if not known[name] then selectedTypes[name] = nil end
    end

    local items = { { any = true, name = kind.any, nodes = total } }
    for _, entry in ipairs(types) do
        items[#items + 1] = entry
    end
    typeList.items = items
    typeList.Refresh()

    local ranked = ns.RankZones(selectedTypes, profession)
    for rank, zone in ipairs(ranked) do
        zone.rank = rank
    end
    topScore = ranked[1] and ranked[1].score > 0 and ranked[1].score or 1
    -- Keep the chosen zone across refreshes; otherwise pick the best one.
    local previous = selectedZone and selectedZone.mapID
    selectedZone = ranked[1]
    for _, zone in ipairs(ranked) do
        if zone.mapID == previous then selectedZone = zone end
    end
    zoneList.items = ranked
    zoneList.Refresh()

    emptyText:SetShown(#ranked == 0)
    UpdateFooter()
end

local function OnTypeClicked(item)
    if item.any then
        for name in pairs(selectedTypes) do
            selectedTypes[name] = nil
        end
    else
        selectedTypes[item.name] = not selectedTypes[item.name] or nil
    end
    selectedZone = nil
    zoneList.offset = 0
    Refresh()
end

local function SelectProfession(key)
    if profession == key then return end
    profession = key
    for name in pairs(selectedTypes) do
        selectedTypes[name] = nil
    end
    selectedZone = nil
    typeList.offset, zoneList.offset = 0, 0
    Refresh()
end

-- One segment of the profession switch above the type list.
local function CreateTab(parent, key, width)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width, 22)
    Fill(tab, 0, 0, 0, 0.35)
    tab.selected = Fill(tab, ACCENT_R, ACCENT_G, ACCENT_B, 0.45, "BORDER")
    Outline(tab, ACCENT_R, ACCENT_G, ACCENT_B, 0.45, "ARTWORK")
    local hover = tab:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.08)
    local label = Label(tab, "GameFontHighlightSmall", "CENTER")
    label:SetPoint("CENTER")
    label:SetText(ns.KINDS[key].label)
    tab:SetScript("OnClick", function()
        Click()
        SelectProfession(key)
    end)
    tabs[key] = tab
    return tab
end

local function OnZoneClicked(zone)
    selectedZone = zone
    zoneList.Refresh()
    UpdateFooter()
end

local function StartSelectedRoute()
    local zone = selectedZone
    if not zone then return end
    ns.StartRoute(zone.mapID, zone.route)
    ns.RefreshPins()
    ns.Print(("Route to %s: %d nodes, about %d yards per loop."):format(zone.name, #zone.route, zone.loop))
    window:Hide()
end

local function ShowSelectedOnMap()
    if not selectedZone then return end
    if InCombatLockdown() then
        ns.Print("The map cannot be opened from here during combat.")
        return
    end
    C_Map.OpenWorldMap(selectedZone.mapID)
end

local function StopActiveRoute()
    ns.StopRoute()
    ns.RefreshPins()
    ns.Print("Route stopped.")
    UpdateFooter()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function CreateCloseButton(parent)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(HEADER_HEIGHT, HEADER_HEIGHT)
    close:SetPoint("RIGHT")
    local hover = close:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.9, 0.2, 0.2, 0.45)
    -- The cross is two drawn strokes, so it needs no font glyph or texture.
    for _, direction in ipairs({ 1, -1 }) do
        local stroke = close:CreateLine(nil, "ARTWORK")
        stroke:SetThickness(2)
        stroke:SetColorTexture(0.9, 0.9, 0.9, 1)
        stroke:SetStartPoint("CENTER", close, -6, 6 * direction)
        stroke:SetEndPoint("CENTER", close, 6, -6 * direction)
    end
    close:SetScript("OnClick", function() window:Hide() end)
    return close
end

local function CreateWindow()
    window = CreateFrame("Frame", "GatherTrailWindow", UIParent)
    window:SetSize(WIDTH, HEIGHT)
    local position = ns.db.windowPosition
    if position then
        window:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:Hide()
    Gradient(window, "BACKGROUND", 0.035, 0.035, 0.045, 0.97, 0.085, 0.08, 0.085, 0.97)
    Outline(window, ACCENT_R, ACCENT_G, ACCENT_B, 0.55)
    -- Lets Escape close the window.
    tinsert(UISpecialFrames, "GatherTrailWindow")

    -- A soft dark rim outside the border, standing in for a drop shadow.
    local shadow = CreateFrame("Frame", nil, window)
    shadow:SetPoint("TOPLEFT", -3, 3)
    shadow:SetPoint("BOTTOMRIGHT", 3, -3)
    shadow:SetFrameLevel(math.max(0, (window:GetFrameLevel() or 1) - 1))
    Fill(shadow, 0, 0, 0, 0.45)

    -- Header: drag handle, icon, title, who and where, close.
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relativePoint, x, y = window:GetPoint()
        ns.db.windowPosition = { point, relativePoint, x, y }
    end)
    Gradient(header, "BACKGROUND", 0.11, 0.085, 0.06, 1, 0.22, 0.165, 0.11, 1)
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    rule:SetHeight(1)
    rule:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)

    local iconFrame = CreateFrame("Frame", nil, header)
    iconFrame:SetSize(26, 26)
    iconFrame:SetPoint("LEFT", 9, 0)
    Outline(iconFrame, ACCENT_R, ACCENT_G, ACCENT_B, 0.8, "OVERLAY")
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local title = Label(header, "GameFontNormalLarge")
    title:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    title:SetText("GatherTrail")
    title:SetTextColor(1, 0.9, 0.75)

    local close = CreateCloseButton(header)
    -- Opens the options page over the lists, and reads "Back" while it is up.
    optionsButton = CreateButton(header, "Options", 76, false, function()
        local open = ns.ToggleSettings(window, HEADER_HEIGHT + 1)
        optionsButton.label:SetText(open and "Back" or "Options")
    end)
    optionsButton:SetHeight(24)
    optionsButton:SetPoint("RIGHT", close, "LEFT", -4, 0)
    contextLabel = Label(header, "GameFontHighlight", "RIGHT")
    contextLabel:SetPoint("RIGHT", optionsButton, "LEFT", -10, 0)

    -- A one-line count of what the account has learned so far.
    local stats = CreateFrame("Frame", nil, window)
    stats:SetPoint("TOPLEFT", 1, -(HEADER_HEIGHT + 1))
    stats:SetPoint("TOPRIGHT", -1, -(HEADER_HEIGHT + 1))
    stats:SetHeight(STATS_HEIGHT)
    Fill(stats, 0, 0, 0, 0.3)
    statsLabel = Label(stats, "GameFontDisableSmall")
    statsLabel:SetPoint("LEFT", PADDING, 0)
    skillLabel = Label(stats, "GameFontDisableSmall", "RIGHT")
    skillLabel:SetPoint("RIGHT", -PADDING, 0)

    local kinds = ns.KindList()
    local tabWidth = (TYPE_WIDTH - 2 * (#kinds - 1)) / #kinds
    local previousTab
    for _, kind in ipairs(kinds) do
        local tab = CreateTab(window, kind.key, tabWidth)
        if previousTab then
            tab:SetPoint("LEFT", previousTab, "RIGHT", 2, 0)
        else
            tab:SetPoint("BOTTOMLEFT", window, "TOPLEFT", PADDING, -(LIST_TOP - 3))
        end
        previousTab = tab
    end

    typeList = CreateList(window, TYPE_WIDTH, LIST_HEIGHT, TYPE_ROW, BuildTypeRow, ConfigureTypeRow, OnTypeClicked)
    typeList:SetPoint("TOPLEFT", PADDING, -LIST_TOP)
    Fill(typeList, 0, 0, 0, 0.25)
    Outline(typeList, 1, 1, 1, 0.06)

    local zoneLeft = TYPE_WIDTH + PADDING * 2
    zoneHeading = Heading(window, "")
    zoneHeading:SetPoint("TOPLEFT", zoneLeft + 2, -(LIST_TOP - 16))
    local scoreHeading = Label(window, "GameFontDisableSmall", "RIGHT")
    scoreHeading:SetPoint("TOPRIGHT", -(PADDING + 10), -(LIST_TOP - 16))
    scoreHeading:SetText("score")

    zoneList = CreateList(window, ZONE_WIDTH, LIST_HEIGHT, ZONE_ROW, BuildZoneRow, ConfigureZoneRow, OnZoneClicked)
    zoneList:SetPoint("TOPLEFT", zoneLeft, -LIST_TOP)

    emptyText = zoneList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("CENTER")
    emptyText:SetWidth(ZONE_WIDTH - 80)
    emptyText:SetText("Nothing recorded here yet.\n\nGather a node, or just point at one, on any character. The places you find them will be ranked here.")

    -- Footer: what is selected, and what to do with it.
    local footer = CreateFrame("Frame", nil, window)
    footer:SetPoint("BOTTOMLEFT", 1, 1)
    footer:SetPoint("BOTTOMRIGHT", -1, 1)
    footer:SetHeight(FOOTER_HEIGHT)
    Fill(footer, 0, 0, 0, 0.35)
    local footerRule = footer:CreateTexture(nil, "ARTWORK")
    footerRule:SetPoint("TOPLEFT")
    footerRule:SetPoint("TOPRIGHT")
    footerRule:SetHeight(1)
    footerRule:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.35)

    startButton = CreateButton(footer, "Start route", 120, true, StartSelectedRoute)
    startButton:SetPoint("RIGHT", -PADDING, 0)
    mapButton = CreateButton(footer, "Show on map", 110, false, ShowSelectedOnMap)
    mapButton:SetPoint("RIGHT", startButton, "LEFT", -8, 0)
    stopButton = CreateButton(footer, "Stop route", 96, false, StopActiveRoute)
    stopButton:SetPoint("RIGHT", mapButton, "LEFT", -8, 0)

    summaryTitle = Label(footer, "GameFontNormal")
    summaryTitle:SetPoint("TOPLEFT", PADDING + 2, -11)
    summaryTitle:SetPoint("RIGHT", stopButton, "LEFT", -10, 0)
    summaryTitle:SetTextColor(1, 1, 1)
    summaryDetail = Label(footer, "GameFontDisableSmall")
    summaryDetail:SetPoint("BOTTOMLEFT", PADDING + 2, 11)
    summaryDetail:SetPoint("RIGHT", stopButton, "LEFT", -10, 0)
end

function ns.ToggleWindow()
    if not window then CreateWindow() end
    if window:IsShown() then
        window:Hide()
    else
        ns.HideSettings()
        optionsButton.label:SetText("Options")
        Refresh()
        window:Show()
    end
end

-- Which tab is open: "ore", "herb", "fish", "skin", "chest" or "rare".
function ns.GetWindowProfession()
    return profession
end

-- Called when the saved data changes.
function ns.RefreshWindow()
    if window and window:IsShown() then
        Refresh()
    end
end
