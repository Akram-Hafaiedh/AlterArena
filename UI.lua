local ADDON_NAME, ns = ...

-- =========================================================================
-- UI shell + shared helpers
-- Roster view  → Roster.lua  (ns.RenderRosterView)
-- History view → History.lua (ns.RenderHistoryView)
-- Settings     → Settings.lua
-- =========================================================================

local mainFrame

-- Shared UI state (modules read/write these)
ns.ui = ns.ui or {}
local ui = ns.ui
ui.activeTab = ui.activeTab or "roster"
ui.rosterSortMode = ui.rosterSortMode or "name"
ui.selectedCharKey = ui.selectedCharKey
ui.selectedMatch = ui.selectedMatch
ui.selectedMatches = ui.selectedMatches or {}
ui.sessionStartTime = ui.sessionStartTime or time()

ui.FRAME_WIDTH = 960
ui.FRAME_HEIGHT = 540
ui.ROW_HEIGHT = 28

ui.historyFilters = ui.historyFilters or {
    bracket = "ALL",
    result  = "ALL",
    map     = "ALL",
    date    = "ALL",
    season  = "ALL",
}

-- Filter labels: see Data/Labels.lua (ns.ui.*)


function ns.GetMainFrame()
    return mainFrame
end

-- =========================================================================
-- Shared formatters / colors
-- =========================================================================

function ns.GetPvPTierName(rating)
    if not rating or rating <= 0   then return nil          end
    if rating >= 2400              then return "Elite"      end
    if rating >= 2100              then return "Duelist"    end
    if rating >= 1800              then return "Rival"      end
    if rating >= 1600              then return "Challenger" end
    if rating >= 1400              then return "Combatant"  end
    return nil
end

function ns.GetClassColor(classFilename)
    if classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename] then
        return RAID_CLASS_COLORS[classFilename]
    end
    return { r = 0.8, g = 0.8, b = 0.8, colorStr = "ffcccccc" }
end

-- =========================================================================
-- Custom scrollbar (from RealmDisplay) — track + draggable thumb
-- Returns scrollFrame, scrollChild. Call scroll:UpdateThumb() after resizing child.
-- =========================================================================
function ns.CreateScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)

    local track = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    track:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    track:SetBackdropColor(0.08, 0.09, 0.11, 1)
    track:SetBackdropBorderColor(0.18, 0.20, 0.24, 1)

    local thumb = CreateFrame("Button", nil, track, "BackdropTemplate")
    thumb:SetWidth(6)
    thumb:SetHeight(40)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    local function AccentThumb()
        local a = (ns.UI and ns.UI.colors and ns.UI.colors.accent) or { 0.25, 0.75, 1.0, 1 }
        thumb:SetBackdropColor(a[1], a[2], a[3], 0.45)
        thumb:SetBackdropBorderColor(a[1], a[2], a[3], 0.7)
    end
    AccentThumb()
    if ns.UI and ns.UI.RegisterThemed then
        ns.UI.RegisterThemed(thumb, AccentThumb)
    end
    thumb:RegisterForDrag("LeftButton")
    thumb:SetMovable(true)
    thumb:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.75, 1.0, 0.75)
    end)
    thumb:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.25, 0.75, 1.0, 0.45)
    end)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local function UpdateThumb()
        local viewH = scroll:GetHeight() or 1
        local childH = child:GetHeight() or 1
        local maxScroll = math.max(childH - viewH, 0)
        if maxScroll <= 0 then
            track:Hide()
            scroll:SetVerticalScroll(0)
            return
        end
        track:Show()
        local ratio = viewH / math.max(childH, 1)
        local thumbH = math.max(24, viewH * ratio)
        thumb:SetHeight(thumbH)
        local cur = scroll:GetVerticalScroll() or 0
        local trackH = track:GetHeight() or 1
        local y = 0
        if maxScroll > 0 and (trackH - thumbH) > 0 then
            y = -(cur / maxScroll) * (trackH - thumbH)
        end
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, y)
    end

    scroll:SetScript("OnVerticalScroll", function()
        UpdateThumb()
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local viewH = self:GetHeight() or 1
        local childH = child:GetHeight() or 1
        local maxScroll = math.max(childH - viewH, 0)
        local cur = self:GetVerticalScroll() or 0
        local step = 28
        local new = math.min(maxScroll, math.max(0, cur - delta * step))
        self:SetVerticalScroll(new)
        UpdateThumb()
    end)

    thumb:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)
    thumb:SetScript("OnDragStop", function(self)
        self.dragging = false
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local scale = self:GetEffectiveScale()
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / scale
        local top = track:GetTop() or 0
        local trackH = track:GetHeight() or 1
        local thumbH = self:GetHeight() or 24
        local rel = top - cursorY - thumbH / 2
        rel = math.min(math.max(rel, 0), trackH - thumbH)
        local viewH = scroll:GetHeight() or 1
        local childH = child:GetHeight() or 1
        local maxScroll = math.max(childH - viewH, 0)
        local offset = 0
        if trackH > thumbH then
            offset = (rel / (trackH - thumbH)) * maxScroll
        end
        scroll:SetVerticalScroll(offset)
        self:ClearAllPoints()
        self:SetPoint("TOP", track, "TOP", 0, -rel)
    end)

    scroll.UpdateThumb = UpdateThumb
    scroll.track = track
    scroll.thumb = thumb

    scroll:SetScript("OnSizeChanged", function()
        UpdateThumb()
    end)

    return scroll, child
end

function ns.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%dm %02ds", m, s)
end

function ns.FormatRoundDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format("%d Min %d Sec", m, s)
    else
        return string.format("%d Sec", s)
    end
end

function ns.GetRatingColor(rating)
    if not rating or rating <= 0 then
        return "ff777788", "---"
    elseif rating >= 2400 then
        return "ffff8000", tostring(rating)
    elseif rating >= 2100 then
        return "ffa335ee", tostring(rating)
    elseif rating >= 1800 then
        return "ff0070dd", tostring(rating)
    elseif rating >= 1600 then
        return "ff1eff00", tostring(rating)
    elseif rating >= 1400 then
        return "ffffd100", tostring(rating)
    else
        return "ffffffff", tostring(rating)
    end
end

function ns.GetMatchBracket(m)
    local b = m and m.bracket
    if b == nil or b == "" then return "Solo Shuffle" end
    if b == "Solo" then return "Solo Shuffle" end
    return b
end

function ns.GetMatchOutcome(m)
    if not m then return "D" end
    if m.won == true then return "W" end
    if m.won == false then return "L" end
    if m.won == nil and m.roundsWon ~= nil then
        local played = m.roundsPlayed or 6
        local winThreshold = math.floor(played / 2) + 1
        local drawThreshold = played / 2
        if m.roundsWon >= winThreshold then
            return "W"
        elseif played % 2 == 0 and m.roundsWon == drawThreshold then
            return "D"
        else
            return "L"
        end
    elseif m.ratingChange ~= nil then
        if m.ratingChange > 0 then return "W"
        elseif m.ratingChange < 0 then return "L"
        else return "D" end
    end
    return "D"
end

function ns.CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
    btn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("LEFT", 6, 0)
    btn.text:SetPoint("RIGHT", -6, 0)
    btn.text:SetJustifyH("CENTER")
    btn.text:SetWordWrap(false)
    btn.text:SetMaxLines(1)
    btn.text:SetText(text)

    function btn:SetText(t)
        if self.text then self.text:SetText(t) end
    end
    function btn:GetText()
        return (self.text and self.text:GetText()) or ""
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1)
        self:SetBackdropBorderColor(0.4, 0.45, 0.55, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isActive then
            self:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
            self:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        end
    end)
    return btn
end

function ns.SetTabActive(btn, isActive)
    if not btn then return end
    btn.isActive = isActive
    if isActive then
        btn:SetBackdropColor(0.20, 0.24, 0.32, 1)
        btn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        if btn.text then btn.text:SetText(btn.text:GetText():gsub("|cff%x%x%x%x%x%x", "|cffffd100")) end
    else
        btn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
        btn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
    end
end

function ns.ClearAllRows(frame)
    if not frame then return end
    if frame.rosterRows then
        for _, row in ipairs(frame.rosterRows) do row:Hide() end
    end
    if frame.rosterHeader then
        frame.rosterHeader:Hide()
    end
    if frame.historyRows then
        for _, row in ipairs(frame.historyRows) do row:Hide() end
    end
    if frame.headerCards then
        for _, card in ipairs(frame.headerCards) do card:Hide() end
    end
    if frame.emptyHistoryMsg then
        frame.emptyHistoryMsg:Hide()
    end
    if frame.historyFooter then
        frame.historyFooter:Hide()
    end
    if frame.sortBar then
        frame.sortBar:Hide()
    end
end

function ns.CreateHeaderRow(parent, columns)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetSize(ui.FRAME_WIDTH - 52, 22)
    header:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.10, 0.10, 0.13, 0.8)
    header:SetBackdropBorderColor(0.16, 0.16, 0.20, 0.6)
    local curX = 10
    for _, col in ipairs(columns) do
        local txt = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", header, "LEFT", curX, 0)
        txt:SetWidth(col.width)
        txt:SetJustifyH(col.align or "LEFT")
        txt:SetText("|cff888899" .. col.title .. "|r")
        curX = curX + col.width + (col.gap or 6)
    end
    return header
end

local function UpdateSettingsButtonState(frame)
    if not frame or not frame.settingsBtn then return end
    local open = ns.IsSettingsPanelOpen and ns.IsSettingsPanelOpen()
    if open then
        frame.settingsBtn:SetBackdropColor(0.20, 0.24, 0.32, 1)
        frame.settingsBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        if frame.settingsBtn.icon then frame.settingsBtn.icon:SetVertexColor(1, 0.82, 0) end
    else
        frame.settingsBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        frame.settingsBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
        if frame.settingsBtn.icon then frame.settingsBtn.icon:SetVertexColor(0.75, 0.75, 0.8) end
    end
end

function ns.UpdateMainSettingsButtonState()
    if mainFrame then
        UpdateSettingsButtonState(mainFrame)
    end
end

ns.UpdateSettingsButtonState = UpdateSettingsButtonState

local function CreateMainFrame()
    local frame = CreateFrame("Frame", "AlterArenaMainFrame", UIParent, "BackdropTemplate")
    if ns.UI and ns.UI.GetWindowSize then
        local sz = ns.UI.GetWindowSize()
        if sz then
            ui.FRAME_WIDTH = sz.w
            ui.FRAME_HEIGHT = sz.h
        end
    end
    frame:SetSize(ui.FRAME_WIDTH, ui.FRAME_HEIGHT)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if AlterArenaDB then
            AlterArenaDB.mainWindowPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    if AlterArenaDB and AlterArenaDB.mainWindowPos then
        local p = AlterArenaDB.mainWindowPos
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        frame:SetPoint("CENTER", 0, 40)
    end

    -- AlterEgo dark glass frame styling
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    local c = ns.UI and ns.UI.colors
    if c then
        frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4] or 1)
        frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4] or 1)
    else
        frame:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
        frame:SetBackdropBorderColor(0.20, 0.21, 0.25, 0.95)
    end

    -- Top Title Bar
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(40)
    titleBar:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    titleBar:SetBackdropColor(0.09, 0.09, 0.12, 0.9)
    titleBar:SetBackdropBorderColor(0.16, 0.16, 0.20, 0.8)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    title:SetPoint("LEFT", 14, 0)
    title:SetText("|cffffd100AlterArena|r |cff888899— PvP & Alt Progression|r")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", -10, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
    closeBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.text:SetPoint("CENTER", 0, 1)
    closeBtn.text:SetText("|cffaaaaaa×|r")
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 0.9)
        self.text:SetText("|cffffffff×|r")
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        self.text:SetText("|cffaaaaaa×|r")
    end)
    closeBtn:SetScript("OnClick", function()
        if ns.CloseDropdowns then ns.CloseDropdowns() end
        frame:Hide()
    end)

    -- Cogwheel Settings Button (Top-Right near Close Button)
    local settingsBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    settingsBtn:SetSize(22, 22)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    settingsBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
    settingsBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)

    settingsBtn.icon = settingsBtn:CreateTexture(nil, "ARTWORK")
    settingsBtn.icon:SetSize(14, 14)
    settingsBtn.icon:SetPoint("CENTER", 0, 0)
    settingsBtn.icon:SetTexture("Interface\\WorldMap\\Gear_64")
    settingsBtn.icon:SetTexCoord(0, 1, 0, 1)
    settingsBtn.icon:SetVertexColor(0.75, 0.75, 0.8)

    settingsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1)
        self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        self.icon:SetVertexColor(1, 0.82, 0)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            GameTooltip:AddLine("AlterArena Settings", 1, 0.82, 0)
            GameTooltip:AddLine("Configure floating HUD, debug mode, and database.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    settingsBtn:SetScript("OnLeave", function(self)
        local open = ns.IsSettingsPanelOpen and ns.IsSettingsPanelOpen()
        if open then
            self:SetBackdropColor(0.20, 0.24, 0.32, 1)
            self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
            self.icon:SetVertexColor(1, 0.82, 0)
        else
            self:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
            self:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
            self.icon:SetVertexColor(0.75, 0.75, 0.8)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    settingsBtn:SetScript("OnClick", function()
        if ns.ToggleSettingsPanel then
            ns.ToggleSettingsPanel()
        end
    end)
    frame.settingsBtn = settingsBtn

    -- Navigation Bar with Tabs
    local navBar = CreateFrame("Frame", nil, frame)
    navBar:SetPoint("TOPLEFT", 14, -46)
    navBar:SetPoint("TOPRIGHT", -14, -46)
    navBar:SetHeight(32)

    frame.tabRoster = ns.CreateStyledButton(navBar, "Roster Overview", 125, 26)
    frame.tabRoster:SetPoint("LEFT", 0, 0)

    frame.tabHistory = ns.CreateStyledButton(navBar, "Match History", 115, 26)
    frame.tabHistory:SetPoint("LEFT", frame.tabRoster, "RIGHT", 6, 0)

    -- Bracket filters container for Match History
    local filterBar = CreateFrame("Frame", nil, navBar)
    filterBar:SetPoint("RIGHT", 0, 0)
    filterBar:SetSize(346, 26)
    frame.filterBar = filterBar

    -- Character picker
    local charBtn = ns.CreateStyledButton(filterBar, "Character", 130, 26)
    charBtn:SetPoint("LEFT", 0, 0)
    charBtn:SetScript("OnClick", function(self)
        local items = {}
        local currentKey = ns.GetPlayerKey()

        -- Pinned "This Character" Shortcut
        table.insert(items, {
            type = "radio",
            label = "This Character",
            checked = function() return ui.selectedCharKey == currentKey end,
            onClick = function()
                ui.selectedCharKey = currentKey
                ns.RefreshUI()
            end,
        })
        -- Space
        table.insert(items, { type = "divider" })

        -- Every tracked character, alphabetical
        local keys = {}
        for key in pairs(AlterArenaDB.players or {}) do
            table.insert(keys, key)
        end
        table.sort(keys)

        for _, key in ipairs(keys) do
            local rec = AlterArenaDB.players[key]
            local name = (rec and rec.name) or key
            local count = (rec and rec.matches and #rec.matches) or 0
            local c = ns.GetClassColor(rec and rec.class)
            local label = string.format("|c%s%s|r |cff666677(%d)|r", c.colorStr or "ffffffff", name, count)
            
            table.insert(items, {
                type  = "radio",
                label = label,
                checked = function() return ui.selectedCharKey == key end,
                onClick = function()
                    ui.selectedCharKey = key
                    ns.RefreshUI()
                end,
            })
        end
        ns.OpenDropdown(self, items)
    end)
    frame.charBtn = charBtn

    -- Bracket dropdown
    local bracketBtn = ns.CreateStyledButton(filterBar, "Bracket", 140, 26)
    bracketBtn:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
    bracketBtn:SetScript("OnClick", function(self)
        local items = {}
        for _, id in ipairs({ "ALL", "Shuffle", "Blitz", "2v2", "3v3" }) do
            local bracketId = id
            table.insert(items, {
                type  = "radio",
                label = ui.BRACKET_LABELS[bracketId],
                checked = function() return ui.historyFilters.bracket == bracketId end,
                onClick = function()
                    ui.historyFilters.bracket = bracketId
                    ns.RefreshUI()
                end,
            })
        end
        ns.OpenDropdown(self, items)
    end)
    frame.bracketBtn = bracketBtn

    -- Clear button
    local clearFiltersBtn = ns.CreateStyledButton(filterBar, "Clear", 64, 26)
    clearFiltersBtn:SetPoint("RIGHT", 0, 0)
    clearFiltersBtn:SetScript("OnClick", function()
        ui.historyFilters.bracket = "ALL"
        ui.historyFilters.result  = "ALL"
        ui.historyFilters.map     = "ALL"
        ui.historyFilters.date    = "ALL"
        ui.historyFilters.season  = "ALL"
        ns.RefreshUI()
    end)
    clearFiltersBtn:Hide()
    frame.clearFiltersBtn = clearFiltersBtn

    local moreBtn = ns.CreateStyledButton(filterBar, "More Filters", 100, 26)
    moreBtn:SetPoint("RIGHT", filterBar, "LEFT", -8, 0)

    moreBtn:SetScript("OnClick", function(self)
        if ns.ShowMoreFilters then
            ns.ShowMoreFilters(self)
        end
    end)
    frame.moreFiltersBtn = moreBtn

    -- Roster tools (shown on Overview, hidden on History)
    local columnsBtn = ns.CreateStyledButton(navBar, "Columns", 90, 26)
    columnsBtn:SetPoint("RIGHT", navBar, "RIGHT", 0, 0)
    columnsBtn:SetScript("OnClick", function(self)
        if ns.OpenColumnsDropdown then
            ns.OpenColumnsDropdown(self)
        end
    end)
    frame.columnsBtn = columnsBtn

    local sortBtn = ns.CreateStyledButton(navBar, "Sort: Name", 130, 26)
    sortBtn:SetPoint("RIGHT", columnsBtn, "LEFT", -6, 0)
    sortBtn:SetScript("OnClick", function(self)
        if ns.OpenRosterSortDropdown then
            ns.OpenRosterSortDropdown(self)
        end
    end)
    frame.sortBtn = sortBtn

    frame.tabRoster:SetScript("OnClick", function()
        ui.activeTab = "roster"
        ns.RefreshUI()
    end)
    frame.tabHistory:SetScript("OnClick", function()
        ui.activeTab = "history"
        ns.RefreshUI()
    end)

    -- Main Content Area (custom scrollbar)
    local scrollFrame, content = ns.CreateScrollFrame(frame)
    scrollFrame:SetPoint("TOPLEFT", 14, -84)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 14)
    content:SetSize(ui.FRAME_WIDTH - 40, 1)

    frame.scrollFrame = scrollFrame
    frame.content = content

    -- Dedicated rows to prevent widget type collisions
    frame.rosterRows = {}
    frame.historyRows = {}
    frame.headerCards = {}

    -- Dedicated empty history message string
    frame.emptyHistoryMsg = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.emptyHistoryMsg:SetPoint("CENTER", content, "CENTER", 0, -40)
    frame.emptyHistoryMsg:Hide()

    -- Bottom Footer Bar for Match History (Arena Analytics style session & selection stats)
    local historyFooter = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    historyFooter:SetPoint("BOTTOMLEFT", 14, 8)
    historyFooter:SetPoint("BOTTOMRIGHT", -14, 8)
    historyFooter:SetHeight(44)
    historyFooter:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    historyFooter:SetBackdropColor(0.07, 0.07, 0.09, 0.95)
    historyFooter:SetBackdropBorderColor(0.18, 0.19, 0.23, 0.9)
    historyFooter:Hide()
    frame.historyFooter = historyFooter

    -- Bottom Left: Current Session & Total Arenas
    local sessionLeft1 = historyFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionLeft1:SetPoint("TOPLEFT", 12, -6)
    sessionLeft1:SetJustifyH("LEFT")
    historyFooter.sessionLeft1 = sessionLeft1

    local sessionLeft2 = historyFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionLeft2:SetPoint("TOPLEFT", 12, -24)
    sessionLeft2:SetJustifyH("LEFT")
    historyFooter.sessionLeft2 = sessionLeft2

    -- Bottom Center: Session Duration & Selection summary
    local sessionCenter1 = historyFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionCenter1:SetPoint("TOPLEFT", 430, -6)
    sessionCenter1:SetJustifyH("LEFT")
    historyFooter.sessionCenter1 = sessionCenter1

    local sessionCenter2 = historyFooter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionCenter2:SetPoint("TOPLEFT", 430, -24)
    sessionCenter2:SetJustifyH("LEFT")
    historyFooter.sessionCenter2 = sessionCenter2

    -- Bottom Right: Clear Selected Button (appears only when matches are selected)
    local clearSelectedBtn = ns.CreateStyledButton(historyFooter, "Clear Selected", 135, 26)
    clearSelectedBtn:SetPoint("RIGHT", -12, 0)
    clearSelectedBtn:Hide()
    clearSelectedBtn:SetScript("OnClick", function()
        if not ui.selectedCharKey then return end
        local pRec = AlterArenaDB.players[ui.selectedCharKey]
        if not pRec or not pRec.matches then return end

        local deletedCount = 0
        for i = #pRec.matches, 1, -1 do
            local m = pRec.matches[i]
            if ui.selectedMatches[m] then
                table.remove(pRec.matches, i)
                deletedCount = deletedCount + 1
            end
        end

        wipe(ui.selectedMatches)
        if deletedCount > 0 then
            print(string.format("|cff40c0ffAlterArena|r: Cleared %d selected match(es).", deletedCount))
        end
        ns.RefreshUI()
    end)
    historyFooter.clearBtn = clearSelectedBtn

    frame:Hide()
    return frame
end



function ns.RefreshUI()
    if not mainFrame then return end
    ns.ClearAllRows(mainFrame)

    if ui.activeTab == "roster" then
        if mainFrame.historyHeader then mainFrame.historyHeader:Hide() end
        if ns.RenderRosterView then
            ns.RenderRosterView(mainFrame)
        end
    else
        if ns.RenderHistoryView then
            ns.RenderHistoryView(mainFrame)
        end
    end
end

--- Ensure the main frame exists (create only; do not toggle visibility).
function ns.EnsureMainFrame()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end
    return mainFrame
end

function ns.ToggleUI()
    local frame = ns.EnsureMainFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        ns.RefreshUI()
    end
end