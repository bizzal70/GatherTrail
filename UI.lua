local _, ns = ...

-- Drawing helpers shared by the main window and the options page. The look
-- is built from plain colours and lines, so it depends on no texture files.

local ACCENT_R, ACCENT_G, ACCENT_B = 0.85, 0.63, 0.40

local function Fill(frame, r, g, b, a, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a)
    return texture
end

-- A vertical fade from one colour (bottom) to another (top). Falls back to
-- the top colour where the client has no gradient support.
local function Gradient(frame, layer, r1, g1, b1, a1, r2, g2, b2, a2)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetAllPoints()
    texture:SetColorTexture(1, 1, 1, 1)
    local ok = CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
        CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    if not ok then
        texture:SetColorTexture(r2, g2, b2, a2)
    end
    return texture
end

local function Outline(frame, r, g, b, a, layer)
    local edges = {}
    local function Edge(point1, point2, isVertical)
        local edge = frame:CreateTexture(nil, layer or "BORDER")
        edge:SetColorTexture(r, g, b, a)
        edge:SetPoint(point1)
        edge:SetPoint(point2)
        if isVertical then edge:SetWidth(1) else edge:SetHeight(1) end
        edges[#edges + 1] = edge
    end
    Edge("TOPLEFT", "TOPRIGHT", false)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", false)
    Edge("TOPLEFT", "BOTTOMLEFT", true)
    Edge("TOPRIGHT", "BOTTOMRIGHT", true)
    return edges
end

local function Label(parent, font, justify)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

local function Heading(parent, text)
    local label = Label(parent, "GameFontDisableSmall")
    label:SetText(text)
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    return label
end

-- 1234567 -> "1,234,567"
local function Num(value)
    value = math.floor(value + 0.5)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(value)
    end
    return tostring(value)
end

local function Click()
    if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local function CreateButton(parent, text, width, primary, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 28)
    if primary then
        Gradient(button, "BACKGROUND", ACCENT_R * 0.45, ACCENT_G * 0.45, ACCENT_B * 0.45, 1,
            ACCENT_R * 0.75, ACCENT_G * 0.75, ACCENT_B * 0.75, 1)
    else
        Gradient(button, "BACKGROUND", 0.13, 0.13, 0.15, 1, 0.22, 0.22, 0.25, 1)
    end
    Outline(button, ACCENT_R, ACCENT_G, ACCENT_B, primary and 0.95 or 0.35)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)
    local label = Label(button, primary and "GameFontNormal" or "GameFontHighlight", "CENTER")
    label:SetPoint("CENTER")
    label:SetText(text)
    if primary then label:SetTextColor(1, 1, 1) end
    button.label = label
    button:SetScript("OnClick", function()
        Click()
        onClick()
    end)
    return button
end

-- A fixed-height list of clickable rows that scrolls with the mouse wheel.
local function CreateList(parent, width, height, rowHeight, buildRow, configureRow, onClick)
    local list = CreateFrame("Frame", nil, parent)
    list:SetSize(width, height)
    list.items, list.rows, list.offset = {}, {}, 0
    local visible = math.floor(height / rowHeight)

    local thumb = list:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.6)

    function list.Refresh()
        local count = #list.items
        list.offset = math.min(list.offset, math.max(0, count - visible))
        for i = 1, visible do
            local item = list.items[i + list.offset]
            local row = list.rows[i]
            if item then
                if not row then
                    row = CreateFrame("Button", nil, list)
                    row:SetSize(width - 8, rowHeight)
                    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
                    row:SetScript("OnClick", function(self)
                        Click()
                        onClick(self.item)
                    end)
                    buildRow(row)
                    list.rows[i] = row
                end
                row.item = item
                configureRow(row, item)
                row:Show()
            elseif row then
                row:Hide()
            end
        end

        if count > visible then
            thumb:SetHeight(height * visible / count)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -height * list.offset / count)
            thumb:Show()
        else
            thumb:Hide()
        end
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        list.offset = math.max(0, list.offset - delta)
        list.Refresh()
    end)
    return list
end

ns.UI = {
    ACCENT = { ACCENT_R, ACCENT_G, ACCENT_B },
    Fill = Fill,
    Gradient = Gradient,
    Outline = Outline,
    Label = Label,
    Heading = Heading,
    Num = Num,
    Click = Click,
    CreateButton = CreateButton,
    CreateList = CreateList,
}
