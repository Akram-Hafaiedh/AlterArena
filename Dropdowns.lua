-- =========================================================================
-- Dropdowns.lua — custom dark-themed dropdown menus
-- =========================================================================
-- v2 — submenu search boxes, working right-side icon buttons, and
-- in-place refresh of radio state for keepOpen menus.
-- =========================================================================

local ADDON_NAME, ns = ...

-- =========================================================================
-- Theme
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
    searchHeight  = 30,
    iconSize      = 16,
    iconReserved  = 22,
}

-- =========================================================================
-- State
-- =========================================================================

local openChain = {}
local pendingCloseToken = nil

local catcher = CreateFrame("Frame", nil, UIParent)
catcher:SetAllPoints(UIParent)
catcher:SetFrameStrata("HIGH")
catcher:EnableMouse(true)
catcher:Hide()
catcher:SetScript("OnMouseDown", function()
    ns.CloseDropdowns()
end)

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

local function StripMarkup(s)
    if not s then return "" end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    return s
end

local function MeasureItems(items)
    local maxW = LAYOUT.minWidth
    local extraLeft  = 26
    local extraRight = 30
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

    -- ---------- Title ----------
    if item.type == "title" then
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 8, 0)
        txt:SetText(THEME.textActive .. item.label .. "|r")
        btn:Disable()
        return btn
    end

    -- ---------- Divider ----------
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

    -- ---------- Radio dot ----------
    local dot
    if item.type == "radio" then
        dot = btn:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", 8, 0)
        dot:SetTexture("Interface/Buttons/WHITE8X8")
        local checked = item.checked and item.checked() or false
        local c = checked and THEME.gold or THEME.radioOff
        dot:SetVertexColor(c[1], c[2], c[3])
    end

    -- ---------- Right-side icon (real Button so clicks land reliably) ----------
    if item.icon then
        local iconBtn = CreateFrame("Button", nil, btn)
        iconBtn:SetSize(LAYOUT.iconSize, LAYOUT.iconSize)
        iconBtn:SetPoint("RIGHT", -4, 0)
        iconBtn:EnableMouse(true)

        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexture(item.icon)
        iconTex:SetVertexColor(0.70, 0.70, 0.76)
        iconBtn.tex = iconTex

        -- When the mouse enters the child icon button, the parent row gets
        -- OnLeave and clears its hover colour. Re-apply the parent's hover
        -- visuals here so the row doesn't flicker on/off as you cross in.
        iconBtn:SetScript("OnEnter", function(self)
            self.tex:SetVertexColor(1, 0.82, 0)
            btn:SetBackdropColor(THEME.hoverBg[1], THEME.hoverBg[2], THEME.hoverBg[3], THEME.hoverBg[4])
            btn:SetBackdropBorderColor(THEME.hoverBorder[1], THEME.hoverBorder[2], THEME.hoverBorder[3], THEME.hoverBorder[4])
            if GameTooltip and item.iconTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(item.iconTooltip, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function(self)
            self.tex:SetVertexColor(0.70, 0.70, 0.76)
            btn:SetBackdropColor(0, 0, 0, 0)
            btn:SetBackdropBorderColor(0, 0, 0, 0)
            if GameTooltip then GameTooltip:Hide() end
        end)
        iconBtn:SetScript("OnClick", function()
            if item.onIconClick then pcall(item.onIconClick) end
        end)
    end

    -- ---------- Label ----------
    local labelX = (item.type == "radio") and 22 or 10
    local labelRight = 8
    if item.submenu then
        labelRight = 18
    elseif item.icon then
        labelRight = LAYOUT.iconReserved
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", labelX, 0)
    label:SetPoint("RIGHT", -labelRight, 0)
    label:SetJustifyH("LEFT")

    local function ApplyLabel()
        local checked = item.checked and item.checked() or false
        if item.type == "radio" and checked then
            label:SetText(THEME.textActive .. item.label .. "|r")
        else
            label:SetText(THEME.text .. item.label .. "|r")
        end
    end
    ApplyLabel()

    -- Store a refresh closure so a parent can update the checkmark in place
    -- without tearing the menu down and rebuilding it.
    btn._refresh = function()
        if dot then
            local checked = item.checked and item.checked() or false
            local c = checked and THEME.gold or THEME.radioOff
            dot:SetVertexColor(c[1], c[2], c[3])
        end
        ApplyLabel()
    end

    -- ---------- Submenu arrow (texture, not a glyph) ----------
    if item.submenu then
        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", -8, 0)
        arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        arrow:SetVertexColor(0.60, 0.60, 0.70)
    end

    -- ---------- Hover ----------
    btn:SetScript("OnEnter", function(self)
        CancelPendingClose()
        self:SetBackdropColor(THEME.hoverBg[1], THEME.hoverBg[2], THEME.hoverBg[3], THEME.hoverBg[4])
        self:SetBackdropBorderColor(THEME.hoverBorder[1], THEME.hoverBorder[2], THEME.hoverBorder[3], THEME.hoverBorder[4])

        if item.onHover then pcall(item.onHover) end
        if item.submenu then
            HideFromLevel(level + 1)
            local subItems = type(item.submenu) == "function" and item.submenu() or item.submenu
            if subItems and #subItems > 0 then
                -- Auto-search: honour an explicit submenuSearch flag, else
                -- turn search on automatically for long submenus.
                local wantSearch = item.submenuSearch
                if wantSearch == nil and #subItems >= 10 then
                    wantSearch = true
                end
                local sub = CreateDropdown(level + 1, subItems, { search = wantSearch })
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

    -- ---------- Click ----------
    btn:SetScript("OnClick", function()
        if item.onClick then pcall(item.onClick) end

        if not item.keepOpen then
            ns.CloseDropdowns()
        else
            -- Refresh every open level so radio checks/labels reflect the
            -- config change immediately, without closing the menu.
            for _, dd in pairs(openChain) do
                if dd._refreshRows then dd._refreshRows() end
            end
        end
    end)

    return btn
end

-- =========================================================================
-- Dropdown construction
-- =========================================================================

CreateDropdown = function(level, items, opts)
    opts = opts or {}

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
    if opts.search then maxWidth = math.max(maxWidth, 220) end
    frame:SetWidth(maxWidth)

    -- ---------- Optional search box ----------
    local searchHeight = 0
    local searchBox
    if opts.search then
        searchHeight = LAYOUT.searchHeight
        searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
        searchBox:SetHeight(22)
        searchBox:SetPoint("TOPLEFT", 4, -4)
        searchBox:SetPoint("TOPRIGHT", -4, -4)
        searchBox:SetBackdrop({
            bgFile   = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        searchBox:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
        searchBox:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)
        searchBox:SetAutoFocus(false)
        searchBox:SetFontObject("GameFontHighlightSmall")
        searchBox:SetTextInsets(6, 6, 0, 0)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            ns.CloseDropdowns()
        end)
        searchBox:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)

        searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        searchBox.placeholder:SetPoint("LEFT", 6, 0)
        searchBox.placeholder:SetText("|cff555566Search…|r")

        frame.searchBox = searchBox
    end

    -- ---------- Row container ----------
    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("TOPLEFT",  0, -searchHeight)
    container:SetPoint("TOPRIGHT", 0, -searchHeight)
    container:SetHeight(10)
    frame.container = container

    local function ClearRows()
        local children = { container:GetChildren() }
        for _, c in ipairs(children) do
            if c:IsObjectType("Button") then c:Hide() end
        end
    end

    local function Rebuild(filterText)
        ClearRows()
        HideFromLevel(level + 1)

        local visible = {}
        if not filterText or filterText == "" then
            for _, it in ipairs(items) do table.insert(visible, it) end
        else
            local needle = filterText:lower()
            for _, it in ipairs(items) do
                local lbl = StripMarkup(it.label or ""):lower()
                if lbl:find(needle, 1, true) then
                    table.insert(visible, it)
                end
            end
        end

        local totalH = LAYOUT.pad
        for _, it in ipairs(visible) do
            totalH = totalH + ItemHeight(it)
        end
        totalH = totalH + LAYOUT.pad
        if totalH < 20 then totalH = 20 end

        container:SetHeight(totalH)
        frame:SetHeight(searchHeight + totalH)

        local cursor = LAYOUT.pad
        for _, it in ipairs(visible) do
            BuildItemRow(container, it, cursor, level)
            cursor = cursor + ItemHeight(it)
        end
    end

    frame._refreshRows = function()
        local children = { container:GetChildren() }
        for _, c in ipairs(children) do
            if c._refresh then c._refresh() end
        end
    end

    if searchBox then
        searchBox:SetScript("OnTextChanged", function(self)
            local txt = self:GetText() or ""
            self.placeholder:SetShown(txt == "")
            Rebuild(txt)
        end)
        searchBox:SetScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(0.80, 0.65, 0.20, 1)
        end)
        searchBox:SetScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)
        end)
    end

    frame:SetHeight(searchHeight + 10)
    Rebuild("")

    if openChain[level] and openChain[level] ~= frame then
        openChain[level]:Hide()
    end
    openChain[level] = frame

    catcher:Show()
    frame:Show()
    return frame
end

-- =========================================================================
-- Public entry
-- =========================================================================

function ns.OpenDropdown(anchor, items, opts)
    ns.CloseDropdowns()
    local d = CreateDropdown(1, items, opts)
    d:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)

    if opts and opts.search and d.searchBox then
        C_Timer.After(0.05, function()
            if d.searchBox and d:IsShown() then
                d.searchBox:SetFocus()
            end
        end)
    end
end

-- Force a visual refresh of every open dropdown (radio state, label colours).
function ns.RefreshAllDropdowns()
    for _, dd in pairs(openChain) do
        if dd._refreshRows then dd._refreshRows() end
    end
end