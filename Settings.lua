local _, ns = ...

-- The options page inside the main window, and the export/import dialog.
-- Drawing helpers are shared from Window.lua through ns.UI.

-- Choices for how long a gathered node is left out of routes; 0 is never.
local SKIP_CHOICES = { 0, 5, 10, 15, 30 }

local panel, dialog, editBox, dialogNote, importButton
local checkboxes = {}
local skipButton, deleteZoneButton
local deleteArmed = false

local function RefreshEverything()
    ns.RefreshPins()
    ns.RefreshMinimapPins()
    ns.RefreshBeacon()
end

---------------------------------------------------------------------------
-- Export / import dialog
---------------------------------------------------------------------------

local function CreateDialog()
    local UI = ns.UI
    dialog = CreateFrame("Frame", "GatherTrailDataDialog", UIParent)
    dialog:SetSize(560, 380)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetToplevel(true)
    dialog:EnableMouse(true)
    dialog:Hide()
    UI.Fill(dialog, 0.05, 0.05, 0.06, 0.98)
    UI.Outline(dialog, UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.6)
    tinsert(UISpecialFrames, "GatherTrailDataDialog")

    dialog.title = UI.Label(dialog, "GameFontNormalLarge")
    dialog.title:SetPoint("TOPLEFT", 14, -12)

    dialogNote = UI.Label(dialog, "GameFontHighlightSmall")
    dialogNote:SetPoint("TOPLEFT", 14, -36)
    dialogNote:SetPoint("RIGHT", -14, 0)

    local scroll = CreateFrame("ScrollFrame", nil, dialog)
    scroll:SetPoint("TOPLEFT", 12, -58)
    scroll:SetPoint("BOTTOMRIGHT", -12, 48)
    UI.Fill(scroll, 0, 0, 0, 0.55)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetWidth(530)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(editBox)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() editBox:SetFocus() end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local target = (self:GetVerticalScroll() or 0) - delta * 40
        self:SetVerticalScroll(math.max(0, math.min(range, target)))
    end)

    local close = UI.CreateButton(dialog, "Close", 90, false, function() dialog:Hide() end)
    close:SetPoint("BOTTOMRIGHT", -12, 10)
    local selectAll = UI.CreateButton(dialog, "Select all", 100, false, function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("RIGHT", close, "LEFT", -8, 0)
    importButton = UI.CreateButton(dialog, "Import", 110, true, function()
        local added, merged, other = ns.ImportData(editBox:GetText())
        if not added then
            ns.Print(merged)
            return
        end
        ns.Print(("Import done: %d new nodes, %d already known, %d other records."):format(added, merged, other))
        dialog:Hide()
    end)
    importButton:SetPoint("RIGHT", selectAll, "LEFT", -8, 0)
end

local function ShowExport()
    if not dialog then CreateDialog() end
    local text, count = ns.ExportData()
    dialog.title:SetText("Export")
    dialogNote:SetText(("%d records. Press Ctrl+C to copy them, then paste them wherever you want to keep or send them."):format(count))
    importButton:Hide()
    editBox:SetText(text)
    dialog:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end

local function ShowImport()
    if not dialog then CreateDialog() end
    dialog.title:SetText("Import")
    dialogNote:SetText("Paste exported GatherTrail data here (Ctrl+V), then press Import. Nothing you already have is lost.")
    importButton:Show()
    editBox:SetText("")
    dialog:Show()
    editBox:SetFocus()
end

---------------------------------------------------------------------------
-- Options page
---------------------------------------------------------------------------

local function CreateCheckbox(parent, text, get, set, r, g, b)
    local UI = ns.UI
    local box = CreateFrame("Button", nil, parent)
    box:SetSize(300, 22)
    local hover = box:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.05)

    local square = CreateFrame("Frame", nil, box)
    square:SetSize(14, 14)
    square:SetPoint("LEFT", 2, 0)
    UI.Fill(square, 0, 0, 0, 0.5)
    UI.Outline(square, UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.7)
    local tick = square:CreateTexture(nil, "ARTWORK")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)

    local label = UI.Label(box, "GameFontHighlight")
    if r then
        -- A swatch in the kind's pin colour.
        local swatch = box:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(10, 10)
        swatch:SetPoint("LEFT", square, "RIGHT", 8, 0)
        swatch:SetColorTexture(r, g, b, 1)
        label:SetPoint("LEFT", swatch, "RIGHT", 7, 0)
    else
        label:SetPoint("LEFT", square, "RIGHT", 8, 0)
    end
    label:SetText(text)

    function box.Refresh()
        tick:SetShown(get() and true or false)
    end
    box:SetScript("OnClick", function()
        UI.Click()
        set(not get())
        box.Refresh()
        RefreshEverything()
    end)
    checkboxes[#checkboxes + 1] = box
    return box
end

local function SkipText()
    local minutes = ns.db.skipRecentMinutes or 0
    if minutes <= 0 then
        return "Routes revisit nodes straight away"
    end
    return ("Routes skip nodes gathered in the last %d min"):format(minutes)
end

local function CycleSkip()
    local current = ns.db.skipRecentMinutes or 0
    local nextChoice = SKIP_CHOICES[1]
    for index, minutes in ipairs(SKIP_CHOICES) do
        if minutes == current then
            nextChoice = SKIP_CHOICES[index % #SKIP_CHOICES + 1]
        end
    end
    ns.db.skipRecentMinutes = nextChoice
    skipButton.label:SetText(SkipText())
    ns.RefreshPins()
end

local function ResetDeleteButton()
    deleteArmed = false
    if deleteZoneButton then
        deleteZoneButton.label:SetText("Delete this zone's records of the open tab")
    end
end

-- Two presses: the first says how many records would go, the second does it.
local function DeleteZoneRecords()
    local mapID = ns.GetPlayerPosition()
    local profession = ns.GetWindowProfession()
    if not mapID then
        ns.Print("Could not read which zone you are in.")
        return
    end
    if not deleteArmed then
        local count = ns.CountNodes(mapID, profession)
        if count == 0 then
            ns.Print(("There are no %s records in %s."):format(ns.KINDS[profession].plural:lower(), ns.MapName(mapID)))
            return
        end
        deleteArmed = true
        deleteZoneButton.label:SetText(("Press again to delete %d %s records in %s"):format(
            count, ns.KINDS[profession].plural:lower(), ns.MapName(mapID)))
        C_Timer.After(6, ResetDeleteButton)
        return
    end
    local removed = ns.DeleteNodes(mapID, profession)
    ns.Print(("Deleted %d records."):format(removed))
    ResetDeleteButton()
end

local function CreatePanel(window, topOffset)
    local UI = ns.UI
    panel = CreateFrame("Frame", nil, window)
    panel:SetPoint("TOPLEFT", 1, -topOffset)
    panel:SetPoint("BOTTOMRIGHT", -1, 1)
    panel:SetFrameLevel((window:GetFrameLevel() or 1) + 20)
    -- Opaque and mouse-enabled, so the lists underneath cannot be clicked.
    panel:EnableMouse(true)
    panel:Hide()
    UI.Fill(panel, 0.05, 0.05, 0.06, 1)
    panel:SetScript("OnHide", ResetDeleteButton)

    local left, right, top, line = 24, 380, -20, 24

    local mapsHeading = UI.Heading(panel, "SHOW ON THE MAPS")
    mapsHeading:SetPoint("TOPLEFT", left, top)
    local y = top - 22
    local function Place(box, x)
        box:SetPoint("TOPLEFT", x, y)
        y = y - line
    end
    Place(CreateCheckbox(panel, "Pins on the world map",
        function() return ns.db.showPins end, function(v) ns.db.showPins = v end), left)
    Place(CreateCheckbox(panel, "Pins on the minimap",
        function() return ns.db.showMinimapPins end, function(v) ns.db.showMinimapPins = v end), left)
    y = y - 8
    for _, kind in ipairs(ns.KindList()) do
        local key = kind.key
        local r, g, b = unpack(kind.colors[3])
        Place(CreateCheckbox(panel, kind.plural,
            function() return ns.db.showKinds[key] end, function(v) ns.db.showKinds[key] = v end, r, g, b), left)
    end
    local routeNote = UI.Label(panel, "GameFontDisableSmall")
    routeNote:SetPoint("TOPLEFT", left, y - 4)
    routeNote:SetText("Stops on the route you are following are always shown.")

    local versionNote = UI.Label(panel, "GameFontDisableSmall")
    versionNote:SetPoint("BOTTOMLEFT", left, 14)
    versionNote:SetText(ns.VersionText())

    local guideHeading = UI.Heading(panel, "GUIDANCE AND RECORDING")
    guideHeading:SetPoint("TOPLEFT", right, top)
    y = top - 22
    Place(CreateCheckbox(panel, "In-world marker on the next stop",
        function() return ns.db.beacon end, function(v) ns.db.beacon = v end), right)
    Place(CreateCheckbox(panel, "Sound on reaching a stop",
        function() return ns.db.sound end, function(v) ns.db.sound = v end), right)
    Place(CreateCheckbox(panel, "Record nodes pointed at on the minimap",
        function() return ns.db.minimapDetect end, function(v) ns.db.minimapDetect = v end), right)
    y = y - 6
    skipButton = UI.CreateButton(panel, "", 320, false, CycleSkip)
    skipButton:SetPoint("TOPLEFT", right, y)
    y = y - 44

    local dataHeading = UI.Heading(panel, "YOUR RECORDS")
    dataHeading:SetPoint("TOPLEFT", right, y)
    y = y - 22
    local export = UI.CreateButton(panel, "Export", 156, false, ShowExport)
    export:SetPoint("TOPLEFT", right, y)
    local import = UI.CreateButton(panel, "Import", 156, false, ShowImport)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    y = y - 36
    local forget = UI.CreateButton(panel, "Delete the record nearest to me", 320, false, function() ns.ForgetNearest() end)
    forget:SetPoint("TOPLEFT", right, y)
    y = y - 36
    deleteZoneButton = UI.CreateButton(panel, "", 320, false, DeleteZoneRecords)
    deleteZoneButton:SetPoint("TOPLEFT", right, y)
    ResetDeleteButton()
end

-- Shows or hides the options page over the main window's lists. Returns
-- whether it is now showing.
function ns.ToggleSettings(window, topOffset)
    if not panel then CreatePanel(window, topOffset) end
    if panel:IsShown() then
        panel:Hide()
        ns.RefreshWindow()
        return false
    end
    for _, box in ipairs(checkboxes) do
        box.Refresh()
    end
    skipButton.label:SetText(SkipText())
    panel:Show()
    return true
end

function ns.HideSettings()
    if panel then panel:Hide() end
end
