-- =========================================================================
-- Dropdowns.lua — custom dark-themed dropdown menus
-- =========================================================================
-- Replaces Blizzard's MenuUtil (which can't nest, can't be styled, and
-- renders in the game's default theme).
--
-- Features:
--   - Arbitrary nesting depth
--   - Radio / button / title / divider item types
--   - Hover-to-open submenus, 300ms grace period for diagonal movement
--   - Click-outside-to-close
--   - Auto-hides when the main window closes
-- =========================================================================

local ADDON_NAME, ns = ...

-- =========================================================================
-- Theme (single source of truth — swap here for future theming)
-- =========================================================================

local THEME = {
    bg           = { 0.07, 0.07, 0.09, 0.98 },
    border       = { 0.20, 0.21, 0.25, 0.95 },
    hoverBg      = { 0.16, 0.18, 0.24, 0.95 },
    hoverBorder  = { 0.30, 0.35, 0.45, 0.95 },
    gold         = { 0.80, 0.65, 0.20 },
    radioOff     = { 0.35, 0.35, 0.40 },
    text         = "|cffdddddd",
    textDim      = "|cff888899",
    textActive   = "|cffffd100",
    arrowGlyph   = ">",
    arrowColor   = "|cff888899",
}

local LAYOUT = {
    itemHeight    = 22,
    titleHeight   = 18,
    dividerHeight = 8,
    minWidth      = 160,
    pad           = 4,
    submenuOffset = 4,
}

-- =========================================================================
-- State
-- =========================================================================

local openChain = {}          -- [level] = dropdown frame
local pendingCloseToken = nil -- token for delayed child close

local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("HIGH")
catcher:EnableMouse(true)
catcher:Hide()
catcher:SetScript("OnMouseDown", function()
    ns.CloseDropdowns()
end)

-- =========================================================================
-- Chain helpers
-- =========================================================================

local function AnyOpen()
    for _ in pairs(openChain) do return true end
    return false
end

local function HideFromLevel(level)
    for i = #openChain, level, -1 do
        if openChain[i] then
            openChain[i]:Hide()
            openChain[i] = nil
        end
    end
    if not AnyOpen() then catcher:Hide() end
end

function ns.CloseDropdowns()
    for i = #openChain, 1, -1 do
        if openChain[i] then
            openChain[i]:Hide()
            openChain[i] = nil
        end
    end
    wipe(openChain)
    catcher:Hide()
    if pendingCloseToken then
        pendingCloseToken.cancelled = true
        pendingCloseToken = nil
    end
end

local function CancelPendingClose()
    if pendingCloseToken then
        pendingCloseToken.cancelled = true
        pendingCloseToken = nil
    end
end

local function ScheduleCloseFromLevel(level)
    CancelPendingClose()
    local token = { cancelled = false }
    pendingCloseToken = token
    C_Timer.After(0.30, function()
        if not token.cancelled then
            HideFromLevel(level + 1)
            pendingCloseToken = nil
        end
    end)
end

-- =========================================================================
-- Measurement
-- =========================================================================

local scratchFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scratchFS:Hide()

local function ItemHeight(item)
    if item.type == "title"   then return LAYOUT.titleHeight   end
    if item.type == "divider" then return LAYOUT.dividerHeight end
    return LAYOUT.itemHeight
end

local function MeasureItems(items)
    local maxW = LAYOUT.minWidth
    local extraLeft  = 26
    local extraRight = 24
    for _, item in ipairs(items) do
        if item.label and item.type ~= "divider" then
            scratchFS:SetText(item.label)
            local w = scratchFS:GetStringWidth() or 0
            local total = w + extraLeft + extraRight
            if total > maxW then maxW = total end
        end
    end
    return math.ceil(maxW)
end

-- =========================================================================
-- Item rendering
-- =========================================================================

local CreateDropdown  -- forward declaration

local function BuildItemRow(parent, item, yOffset, level)
    local h = ItemHeight(item)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(h)
    btn:SetPoint("TOPLEFT",   LAYOUT.pad, -yOffset)
    btn:SetPoint("TOPRIGHT", -LAYOUT.pad, -yOffset)
    btn:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0, 0, 0, 0)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    -- Title
    if item.type == "title" then
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 8, 0)
        txt:SetText(THEME.textActive .. item.label .. "|r")
        btn:Disable()
        return btn
    end

    -- Divider
    if item.type == "divider" then
        local line = btn:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", 8, 0)
        line:SetPoint("RIGHT", -8, 0)
        line:SetTexture("Interface/Buttons/WHITE8X8")
        line:SetVertexColor(0.25, 0.25, 0.30, 1)
        btn:Disable()
        return btn
    end

    -- Radio dot
    if item.type == "radio" then
        local dot = btn:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", 8, 0)
        dot:SetTexture("Interface/Buttons/WHITE8X8")
        local checked = item.checked and item.checked() or false
        local c = checked and THEME.gold or THEME.radioOff
        dot:SetVertexColor(c[1], c[2], c[3])
    end

    -- Label
    local labelX = (item.type == "radio") and 22 or 10
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", labelX, 0)
    label:SetPoint("RIGHT", item.submenu and -18 or -8, 0)
    label:SetJustifyH("LEFT")

    local checked = item.checked and item.checked() or false
    if item.type == "radio" and checked then
        label:SetText(THEME.textActive .. item.label .. "|r")
    else
        label:SetText(THEME.text .. item.label .. "|r")
    end

    -- Submenu arrow
    if item.submenu then
        local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrow:SetPoint("RIGHT", -8, 0)
        arrow:SetText(THEME.arrowColor .. THEME.arrowGlyph .. "|r")
    end

    -- Hover
    btn:SetScript("OnEnter", function(self)
        CancelPendingClose()
        self:SetBackdropColor(THEME.hoverBg[1], THEME.hoverBg[2], THEME.hoverBg[3], THEME.hoverBg[4])
        self:SetBackdropBorderColor(THEME.hoverBorder[1], THEME.hoverBorder[2], THEME.hoverBorder[3], THEME.hoverBorder[4])

        if item.submenu then
            HideFromLevel(level + 1)
            local subItems = type(item.submenu) == "function" and item.submenu() or item.submenu
            if subItems and #subItems > 0 then
                local sub = CreateDropdown(level + 1, subItems)
                sub:SetPoint("TOPLEFT", self, "TOPRIGHT", LAYOUT.submenuOffset, 0)
            end
        else
            ScheduleCloseFromLevel(level)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self:SetBackdropBorderColor(0, 0, 0, 0)
        if item.submenu then
            ScheduleCloseFromLevel(level)
        end
    end)

    -- Click
    btn:SetScript("OnClick", function(self)
        if item.onClick then
            item.onClick()
        end
        ns.CloseDropdowns()
    end)

    return btn
end

-- =========================================================================
-- Dropdown construction
-- =========================================================================

CreateDropdown = function(level, items)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500 + level)
    frame:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], THEME.bg[4])
    frame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], THEME.border[4])

    local maxWidth = MeasureItems(items)
    local totalH = LAYOUT.pad
    for _, item in ipairs(items) do
        totalH = totalH + ItemHeight(item)
    end
    totalH = totalH + LAYOUT.pad

    frame:SetSize(maxWidth, totalH)

    local cursor = LAYOUT.pad
    for _, item in ipairs(items) do
        BuildItemRow(frame, item, cursor, level)
        cursor = cursor + ItemHeight(item)
    end

    -- Replace any existing dropdown at this level
    if openChain[level] and openChain[level] ~= frame then
        openChain[level]:Hide()
    end
    openChain[level] = frame

    catcher:Show()
    frame:Show()
    return frame
end

-- =========================================================================
-- Public entry point
-- =========================================================================

-- Opens a fresh dropdown chain anchored below the given frame.
-- items = array of { type, label, checked, onClick, submenu }
function ns.OpenDropdown(anchor, items)
    ns.CloseDropdowns()
    local d = CreateDropdown(1, items)
    d:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
end