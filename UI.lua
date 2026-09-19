local ADDON_NAME, ns = ...

local mainFrame
local activeTab = "roster" -- "roster" or "history"
local rosterSortMode = "name" -- "name", "rating", "recent", "winrate"


-- Curated lists of rated-PvP maps. Names must match GetRealZoneText() output.
-- If a name here doesn't match, that radio just yields zero results until
-- the user plays on it and the dynamic discovery picks up the real string.
local KNOWN_ARENA_MAPS = {
    "Hook Point",
    "Blade's Edge Arena",
    "Ruins of Lordaeron",
    "The Robodrome",
    "Ashamane's Fall",
    "Empyrean Domain",
    "Nokhudon Proving Grounds",
    "Maldraxxus Coliseum",
    "The Tiger's Peak",
    "Enigma Crucible",
    "Cage of Carnage",
    "Tol'viron Arena",
    "Nagrand Arena",
    "Mugambala",
    "Black Rook Hold Arena",
}

local KNOWN_BG_MAPS = {
    "Warsong Gulch",
    "Arathi Basin",
    "Eye of the Storm",
    "Temple of Kotmogu",
    "Silvershard Mines",
    "Deepwind Gorge",
    "Twin Peaks",
    "Battle for Gilneas",
    "Isle of Conquest",
    "Alterac Valley",
    "Seething Shore",
}

-- =========================================================================
-- Roster column definitions
-- =========================================================================
-- Order here is the order they appear in the roster. Add new columns by
-- inserting here; the header and rows build themselves from this list.
-- "always" columns can't be hidden via the Columns dropdown.
local COLUMN_DEFS = {
    { id = "name",     title = "Character",     width = 115, align = "LEFT",   always = true, icon = "Interface\\Icons\\INV_Misc_Head_Human_01" },
    { id = "spec",     title = "Spec / Class",  width = 105, align = "LEFT", icon = "Interface\\Icons\\INV_Misc_QuestionMark" },
    { id = "best",     title = "Best Tier",     width = 95,  align = "CENTER" , icon = "Interface\\Icons\\achievement_pvp_a_01"},
    { id = "shuffle",  title = "Shuffle",       width = 85,  align = "CENTER" , icon = "Interface\\Icons\\achievement_pvp_a_02"},
    { id = "blitz",    title = "Blitz",         width = 80,  align = "CENTER", icon = "Interface\\Icons\\achievement_pvp_a_03" },
    { id = "two",      title = "2v2",           width = 65,  align = "CENTER", icon = "Interface\\Icons\\achievement_pvp_a_04" },
    { id = "three",    title = "3v3",           width = 65,  align = "CENTER", icon = "Interface\\Icons\\achievement_pvp_a_05" },
    { id = "conquest", title = "Conquest",      width = 100, align = "CENTER", currencyKey = "conquest" },
    { id = "honor",    title = "Honor",         width = 90,  align = "CENTER", currencyKey = "honor" },
    { id = "tokens",   title = "Tokens",        width = 85,  align = "CENTER", currencyKey = "tokens" },
    { id = "record",   title = "W - L (Win %)", width = 145, align = "RIGHT" ,  icon = "Interface\\Icons\\INV_Misc_Note_01" },
}

-- Which columns are visible on first run. Honor and Tokens default OFF
-- so the initial roster isn't too crowded.
local DEFAULT_COLUMNS = {
    name = true, spec = true, best = true,
    shuffle = true, blitz = true, two = true, three = true,
    conquest = true, honor = false, tokens = false, record = true,
}


local selectedCharKey = nil
local selectedMatches = {}
local sessionStartTime = time()

local ROW_HEIGHT = 28
local FRAME_WIDTH = 960
local FRAME_HEIGHT = 540

local historyFilters = {
    bracket = "ALL",   -- "ALL" | "Shuffle" | "Blitz" | "2v2" | "3v3"
    result  = "ALL",   -- "ALL" | "WINS" | "LOSSES" | "DRAWS"
    map     = "ALL",   -- "ALL" | <map name string>
    date    = "ALL",   -- "ALL" | "TODAY" | "THISWEEK" | "THISMONTH" | "LAST3MONTHS" | "LAST6MONTHS"
    season  = "ALL",   -- "ALL" | "CURRENT" | "LAST"
}

local BRACKET_LABELS = {
    ALL     = "All Brackets",
    Shuffle = "Solo Shuffle",
    Blitz   = "Battleground Blitz",
    ["2v2"] = "2v2 Arena",
    ["3v3"] = "3v3 Arena",
}

local RESULT_LABELS = {
    ALL    = "Any Result",
    WINS   = "Wins Only",
    LOSSES = "Losses Only",
    DRAWS  = "Draws Only",
}

local DATE_LABELS = {
    ALL         = "All Time",
    TODAY       = "Last 24 Hours",
    THISWEEK    = "Last 7 Days",
    THISMONTH   = "Last 30 Days",
    LAST3MONTHS = "Last 3 Months",
    LAST6MONTHS = "Last 6 Months",
}

local SEASON_LABELS = {
    ALL     = "All Seasons",
    CURRENT = "Current Season",
    LAST    = "Last Season",
}

-- Cutoff in seconds for each date filter key.
local DATE_CUTOFFS = {
    TODAY       = 24 * 3600,
    THISWEEK    = 7 * 24 * 3600,
    THISMONTH   = 30 * 24 * 3600,
    LAST3MONTHS = 90 * 24 * 3600,
    LAST6MONTHS = 180 * 24 * 3600,
}


-- Returns the icon markup string for a currency column, or "" if not found.
-- Fetched lazily from C_CurrencyInfo so we always get the current client's
-- texture IDs.
local function GetColumnIconMarkup(def, size)
    size = size or 12
    if not def then return "" end

    -- Currency-keyed icons come from the client at runtime
    if def.currencyKey and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local id = ns.CURRENCY and ns.CURRENCY[def.currencyKey]
        if id then
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
            if ok and info and info.iconFileID then
                return string.format("|T%s:%d:%d:0:0|t ", info.iconFileID, size, size)
            end
        end
    end

    -- Static icons
    if def.icon then
        return string.format("|T%s:%d:%d:0:0|t ", def.icon, size, size)
    end

    return ""
end

local function GetColumnVisibility()
    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    AlterArenaDB.settings.columns = AlterArenaDB.settings.columns or {}
    local cv = AlterArenaDB.settings.columns
    for id, def in pairs(DEFAULT_COLUMNS) do
        if cv[id] == nil then cv[id] = def end
    end
    return cv
end

local function GetVisibleColumns()
    local cv = GetColumnVisibility()
    local out = {}
    for _, def in ipairs(COLUMN_DEFS) do
        if def.always or cv[def.id] then
            table.insert(out, def)
        end
    end
    return out
end

-- Repositions every FontString on a history row using the current column
-- widths. Call this after `cols` has been stretched.
local function PositionHistoryRow(row, cols)
    if not row or not cols then return end
    local prev = nil
    for i, col in ipairs(cols) do
        local fs = row.textFields and row.textFields[i]
        if fs then
            fs:ClearAllPoints()
            if prev then
                fs:SetPoint("LEFT", prev, "RIGHT", col.gap or 4, 0)
            else
                fs:SetPoint("LEFT", row, "LEFT", 10, 0)
            end
            fs:SetWidth(col.width)
            fs:SetJustifyH(col.align or "LEFT")
            prev = fs
        end
    end
end


-- Repositions every FontString on a roster row to reflect current column
-- visibility. Call before showing the row.
local function PositionRowColumns(row)
    if not row or not row.texts then return end
    local visible = GetVisibleColumns()
    local prev = nil
    for _, def in ipairs(visible) do
        local fs = row.texts[def.id]
        if fs then
            fs:Show()
            fs:ClearAllPoints()
            if prev then
                fs:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            else
                fs:SetPoint("LEFT", row, "LEFT", 10, 0)
            end
            fs:SetWidth(def.width)
            fs:SetJustifyH(def.align or "LEFT")
            prev = fs
        end
    end
    -- Hide any FontString not in the visible set
    for _, def in ipairs(COLUMN_DEFS) do
        local vis = false
        for _, vdef in ipairs(visible) do
            if vdef.id == def.id then vis = true; break end
        end
        local fs = row.texts[def.id]
        if fs and not vis then fs:Hide() end
    end
end

-- Returns the total pixel width needed to render the current set of
-- visible columns, plus left/right padding.
local function GetRequiredRosterWidth()
    local visible = GetVisibleColumns()
    local total = 10 + 20   -- left inset (10) + right slack (20)
    for i, def in ipairs(visible) do
        total = total + def.width
        if i < #visible then total = total + 6 end  -- gap between columns
    end
    return total
end

local function GetPvPTierName(rating)
    if not rating or rating <= 0   then return nil          end
    if rating >= 2400              then return "Elite"      end
    if rating >= 2100              then return "Duelist"    end
    if rating >= 1800              then return "Rival"      end
    if rating >= 1600              then return "Challenger" end
    if rating >= 1400              then return "Combatant"  end
    return nil
end

-- Class colors helper
local function GetClassColor(classFilename)
    if classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename] then
        return RAID_CLASS_COLORS[classFilename]
    end
    return { r = 0.8, g = 0.8, b = 0.8, colorStr = "ffcccccc" }
end

local function getBestRating(rec)
    local best = 0
    if rec and rec.bracketRatings then
        for _, bData in pairs(rec.bracketRatings) do
            if bData.current and bData.current > best then
                best = bData.current
            end
        end
    end
    return best
end

local function GetLastMatchTime(rec)
    if rec and rec.matches and #rec.matches > 0 then
        return rec.matches[#rec.matches].timestamp or 0
    end
    return 0
end

local function GetWinRate(rec)
    local w, l = 0, 0
    if rec and rec.matches then
        for _, m in ipairs(rec.matches) do
            if m.won == true then w = w + 1
            elseif m.won == false then l = l + 1 end
        end
    end
    local total = w + l
    if total == 0 then return -1 end
    return w / total
end

local function GetSortedCharacterKeys(sortMode)
    local keys = {}
    for key in pairs(AlterArenaDB.players or {}) do
        table.insert(keys, key)
    end

    sortMode = sortMode or rosterSortMode or "name"
    if sortMode == "rating" then
        table.sort(keys, function(a, b)
            local ra, rb = getBestRating(AlterArenaDB.players[a]), getBestRating(AlterArenaDB.players[b])
            if ra == rb then return a < b end
            return ra > rb
        end)
    elseif sortMode == "recent" then
        table.sort(keys, function(a, b)
            local ta, tb = GetLastMatchTime(AlterArenaDB.players[a]), GetLastMatchTime(AlterArenaDB.players[b])
            if ta == tb then return a < b end
            return ta > tb
        end)
    elseif sortMode == "winrate" then
        table.sort(keys, function(a, b)
            local wa, wb = GetWinRate(AlterArenaDB.players[a]), GetWinRate(AlterArenaDB.players[b])
            if wa == wb then return a < b end
            return wa > wb
        end)
    else
        table.sort(keys)
    end
    
    return keys
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%dm %02ds", m, s)
end

local function FormatRoundDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format("%d Min %d Sec", m, s)
    else
        return string.format("%d Sec", s)
    end
end

local function GetRatingColor(rating)
    if not rating or rating <= 0 then
        return "ff777788", "---"
    elseif rating >= 2400 then
        return "ffff8000", tostring(rating) -- Elite orange
    elseif rating >= 2100 then
        return "ffa335ee", tostring(rating) -- Duelist purple
    elseif rating >= 1800 then
        return "ff0070dd", tostring(rating) -- Rival blue
    elseif rating >= 1600 then
        return "ff1eff00", tostring(rating) -- Challenger green
    elseif rating >= 1400 then
        return "ffffd100", tostring(rating) -- Combatant yellow
    else
        return "ffffffff", tostring(rating) -- White
    end
end

local function GetMatchBracket(m)
    local b = m and m.bracket
    if b == nil or b == "" then return "Solo Shuffle" end
    if b == "Solo" then return "Solo Shuffle" end
    return b
end

local function GetMatchOutcome(m)
    if not m then return "D" end
    if m.roundsWon ~= nil then
        if m.roundsWon >= 4 then
            return "W"
        elseif m.roundsWon == 3 then
            return "D"
        else
            return "L"
        end
    elseif m.won ~= nil then
        if m.won == true then
            return "W"
        else
            return "L"
        end
    elseif m.ratingChange ~= nil then
        if m.ratingChange > 0 then
            return "W"
        elseif m.ratingChange < 0 then
            return "L"
        else
            return "D"
        end
    end
    return "D"
end

-- Create a flat dark styled button
local function CreateStyledButton(parent, text, width, height)
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
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)

    function btn:SetText(t)
        if self.text then
            self.text:SetText(t)
        end
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

local function UpdateMoreFiltersButton(frame)
    if not frame or not frame.moreFiltersBtn then return end
    local count = 0
    if historyFilters.result ~= "ALL" then count = count + 1 end
    if historyFilters.date   ~= "ALL" then count = count + 1 end
    if historyFilters.map    ~= "ALL" then count = count + 1 end
    if historyFilters.season ~= "ALL" then count = count + 1 end
    
    if count > 0 then
        frame.moreFiltersBtn:SetBackdropColor(0.20, 0.24, 0.32, 1)
        frame.moreFiltersBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        frame.moreFiltersBtn.text:SetText(string.format("|cffffd100Filters (%d)|r", count))
    else
        frame.moreFiltersBtn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
        frame.moreFiltersBtn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        frame.moreFiltersBtn.text:SetText("|cff9999aaMore Filters|r")
    end
end

function ns.ShowMoreFilters(anchor)
    -- Result submenu
    local resultSub = {}
    for _, id in ipairs({ "ALL", "WINS", "LOSSES", "DRAWS" }) do
        local rid = id
        table.insert(resultSub, {
            type  = "radio",
            label = RESULT_LABELS[rid],
            checked = function() return historyFilters.result == rid end,
            onClick = function() historyFilters.result = rid; ns.RefreshUI() end,
        })
    end

    -- Date submenu
    local dateSub = {}
    for _, id in ipairs({ "ALL", "TODAY", "THISWEEK", "THISMONTH", "LAST3MONTHS", "LAST6MONTHS" }) do
        local did = id
        table.insert(dateSub, {
            type  = "radio",
            label = DATE_LABELS[did],
            checked = function() return historyFilters.date == did end,
            onClick = function() historyFilters.date = did; ns.RefreshUI() end,
        })
    end

    -- Season submenu
    local seasonSub = {}
    for _, id in ipairs({ "ALL", "CURRENT", "LAST" }) do
        local sid = id
        table.insert(seasonSub, {
            type  = "radio",
            label = SEASON_LABELS[sid],
            checked = function() return historyFilters.season == sid end,
            onClick = function() historyFilters.season = sid; ns.RefreshUI() end,
        })
    end

    -- Arena maps submenu
    local arenaItems = {}
    for _, mp in ipairs(KNOWN_ARENA_MAPS) do
        local mpm = mp
        table.insert(arenaItems, {
            type  = "radio",
            label = mpm,
            checked = function() return historyFilters.map == mpm end,
            onClick = function() historyFilters.map = mpm; ns.RefreshUI() end,
        })
    end

    -- BG maps submenu
    local bgItems = {}
    for _, mp in ipairs(KNOWN_BG_MAPS) do
        local mpm = mp
        table.insert(bgItems, {
            type  = "radio",
            label = mpm,
            checked = function() return historyFilters.map == mpm end,
            onClick = function() historyFilters.map = mpm; ns.RefreshUI() end,
        })
    end

    -- "Other" submenu — maps discovered from history
    local otherItems = {}
    do
        local effectiveKey = selectedCharKey or (ns.GetPlayerKey and ns.GetPlayerKey())
        local seen = {}
        for _, mp in ipairs(KNOWN_ARENA_MAPS) do seen[mp] = true end
        for _, mp in ipairs(KNOWN_BG_MAPS)   do seen[mp] = true end

        local extras = {}
        local rec = effectiveKey and AlterArenaDB.players[effectiveKey]
        if rec and rec.matches then
            for _, m in ipairs(rec.matches) do
                local mp = m.map
                if mp and mp ~= "" and not seen[mp] then
                    seen[mp] = true
                    table.insert(extras, mp)
                end
            end
        end
        table.sort(extras)

        for _, mp in ipairs(extras) do
            local mpm = mp
            table.insert(otherItems, {
                type  = "radio",
                label = mpm,
                checked = function() return historyFilters.map == mpm end,
                onClick = function() historyFilters.map = mpm; ns.RefreshUI() end,
            })
        end
    end

    -- Map submenu tree
    local mapSub = {
        {
            type  = "radio",
            label = "All Maps",
            checked = function() return historyFilters.map == "ALL" end,
            onClick = function() historyFilters.map = "ALL"; ns.RefreshUI() end,
        },
        { type = "divider" },
        {
            type  = "radio",
            label = "Arena Maps",
            submenu = arenaItems,
            checked = function() return false end,
        },
        {
            type  = "radio",
            label = "Battleground Maps",
            submenu = bgItems,
            checked = function() return false end,
        },
    }
    if #otherItems > 0 then
        table.insert(mapSub, {
            type  = "radio",
            label = "Other / Historical",
            submenu = otherItems,
            checked = function() return false end,
        })
    end

    -- Root menu
    local mapLabel = (historyFilters.map == "ALL") and "Map: All" or ("Map: " .. historyFilters.map)
    local items = {
        {
            type  = "radio",
            label = "Result: " .. RESULT_LABELS[historyFilters.result],
            submenu = resultSub,
            checked = function() return historyFilters.result ~= "ALL" end,
        },
        {
            type  = "radio",
            label = "Date: " .. DATE_LABELS[historyFilters.date],
            submenu = dateSub,
            checked = function() return historyFilters.date ~= "ALL" end,
        },
        {
            type  = "radio",
            label = "Season: " .. SEASON_LABELS[historyFilters.season],
            submenu = seasonSub,
            checked = function() return historyFilters.season ~= "ALL" end,
        },
        {
            type  = "radio",
            label = mapLabel,
            submenu = mapSub,
            checked = function() return historyFilters.map ~= "ALL" end,
        },
        { type = "divider" },
        {
            type  = "button",
            label = "Reset all filters",
            onClick = function()
                historyFilters.bracket = "ALL"
                historyFilters.result  = "ALL"
                historyFilters.map     = "ALL"
                historyFilters.date    = "ALL"
                historyFilters.season  = "ALL"
                ns.RefreshUI()
            end,
        },
    }

    ns.OpenDropdown(anchor, items)
end

-- Create AlterEgo dark main window
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "AlterArenaMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
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
    frame:SetBackdropColor(0.07, 0.07, 0.09, 0.96)
    frame:SetBackdropBorderColor(0.20, 0.21, 0.25, 0.95)

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
        if activeTab ~= "settings" then
            self:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
            self:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
            self.icon:SetVertexColor(0.75, 0.75, 0.8)
        else
            self:SetBackdropColor(0.20, 0.24, 0.32, 1)
            self:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
            self.icon:SetVertexColor(1, 0.82, 0)
        end
        if GameTooltip then GameTooltip:Hide() end
    end)
    settingsBtn:SetScript("OnClick", function()
        if activeTab == "settings" then
            activeTab = "roster"
        else
            activeTab = "settings"
        end
        ns.RefreshUI()
    end)
    frame.settingsBtn = settingsBtn

    -- Navigation Bar with Tabs
    local navBar = CreateFrame("Frame", nil, frame)
    navBar:SetPoint("TOPLEFT", 14, -46)
    navBar:SetPoint("TOPRIGHT", -14, -46)
    navBar:SetHeight(32)

    frame.tabRoster = CreateStyledButton(navBar, "Roster Overview", 125, 26)
    frame.tabRoster:SetPoint("LEFT", 0, 0)

    frame.tabHistory = CreateStyledButton(navBar, "Match History", 115, 26)
    frame.tabHistory:SetPoint("LEFT", frame.tabRoster, "RIGHT", 6, 0)

    -- Bracket filters container for Match History
    local filterBar = CreateFrame("Frame", nil, navBar)
    filterBar:SetPoint("RIGHT", 0, 0)
    filterBar:SetSize(346, 26)
    frame.filterBar = filterBar

    -- Character picker
    local charBtn = CreateStyledButton(filterBar, "Character", 130, 26)
    charBtn:SetPoint("LEFT", 0, 0)
    charBtn:SetScript("OnClick", function(self)
        local items = {}
        local currentKey = ns.GetPlayerKey()

        -- Pinned "This Character" Shortcut
        table.insert(items, {
            type = "radio",
            label = "This Character",
            checked = function() return selectedCharKey == currentKey end,
            onClick = function()
                selectedCharKey = currentKey
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
            local c = GetClassColor(rec and rec.class)
            local label = string.format("|c%s%s|r |cff666677(%d)|r", c.colorStr or "ffffffff", name, count)
            
            table.insert(items, {
                type  = "radio",
                label = label,
                checked = function() return selectedCharKey == key end,
                onClick = function()
                    selectedCharKey = key
                    ns.RefreshUI()
                end,
            })
        end
        ns.OpenDropdown(self, items)
    end)
    frame.charBtn = charBtn

    -- Bracket dropdown
    local bracketBtn = CreateStyledButton(filterBar, "Bracket", 140, 26)
    bracketBtn:SetPoint("LEFT", charBtn, "RIGHT", 6, 0)
    bracketBtn:SetScript("OnClick", function(self)
        local items = {}
        for _, id in ipairs({ "ALL", "Shuffle", "Blitz", "2v2", "3v3" }) do
            local bracketId = id
            table.insert(items, {
                type  = "radio",
                label = BRACKET_LABELS[bracketId],
                checked = function() return historyFilters.bracket == bracketId end,
                onClick = function()
                    historyFilters.bracket = bracketId
                    ns.RefreshUI()
                end,
            })
        end
        ns.OpenDropdown(self, items)
    end)
    frame.bracketBtn = bracketBtn

    -- Clear button
    local clearFiltersBtn = CreateStyledButton(filterBar, "Clear", 64, 26)
    clearFiltersBtn:SetPoint("RIGHT", 0, 0)
    clearFiltersBtn:SetScript("OnClick", function()
        historyFilters.bracket = "ALL"
        historyFilters.result  = "ALL"
        historyFilters.map     = "ALL"
        historyFilters.date    = "ALL"
        historyFilters.season  = "ALL"
        ns.RefreshUI()
    end)
    clearFiltersBtn:Hide()
    frame.clearFiltersBtn = clearFiltersBtn

    local moreBtn = CreateStyledButton(filterBar, "More Filters", 100, 26)
    moreBtn:SetPoint("RIGHT", filterBar, "LEFT", -8, 0)

    moreBtn:SetScript("OnClick", function(self)
        if ns.ShowMoreFilters then
            ns.ShowMoreFilters(self)
        end
    end)
    frame.moreFiltersBtn = moreBtn

    local columnsBtn = CreateStyledButton(navBar, "Columns", 90, 26)
    columnsBtn:SetPoint("RIGHT", navBar, "RIGHT", 0, 0)
    columnsBtn:SetScript("OnClick", function(self)
        local cv = GetColumnVisibility()
        local items = {}
        for _, def in ipairs(COLUMN_DEFS) do
            if not def.always then
                local defId = def.id
                local iconPrefix = GetColumnIconMarkup(def, 14) or ""
                table.insert(items, {
                    type  = "radio",
                    label = iconPrefix .. def.title,
                    checked = function() return cv[defId] == true end,
                    onClick = function()
                        cv[defId] = not cv[defId]
                        ns.RefreshUI()
                    end,
                })
            end
        end
        ns.OpenDropdown(self, items)
    end)
    frame.columnsBtn = columnsBtn

    frame.tabRoster:SetScript("OnClick", function()
        activeTab = "roster"
        ns.RefreshUI()
    end)
    frame.tabHistory:SetScript("OnClick", function()
        activeTab = "history"
        ns.RefreshUI()
    end)

    -- Main Content Area (Scroll Frame)
    local scrollFrame = CreateFrame("ScrollFrame", "AlterArenaScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -84)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 14)

    -- Dark styled scrollbar
    local scrollBarName = scrollFrame:GetName() .. "ScrollBar"
    local scrollBar = _G[scrollBarName]
    if scrollBar then
        scrollBar:SetAlpha(0.7)
    end

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(FRAME_WIDTH - 50, 1)
    scrollFrame:SetScrollChild(content)

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
    local clearSelectedBtn = CreateStyledButton(historyFooter, "Clear Selected", 135, 26)
    clearSelectedBtn:SetPoint("RIGHT", -12, 0)
    clearSelectedBtn:Hide()
    clearSelectedBtn:SetScript("OnClick", function()
        if not selectedCharKey then return end
        local pRec = AlterArenaDB.players[selectedCharKey]
        if not pRec or not pRec.matches then return end

        local deletedCount = 0
        for i = #pRec.matches, 1, -1 do
            local m = pRec.matches[i]
            if selectedMatches[m] then
                table.remove(pRec.matches, i)
                deletedCount = deletedCount + 1
            end
        end

        wipe(selectedMatches)
        if deletedCount > 0 then
            print(string.format("|cff40c0ffAlterArena|r: Cleared %d selected match(es).", deletedCount))
        end
        ns.RefreshUI()
    end)
    historyFooter.clearBtn = clearSelectedBtn

    frame:Hide()
    return frame
end

local function SetTabActive(btn, isActive)
    if not btn then return end
    btn.isActive = isActive
    if isActive then
        btn:SetBackdropColor(0.20, 0.24, 0.32, 1)
        btn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        btn.text:SetText("|cffffd100" .. btn.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
    else
        btn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
        btn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        btn.text:SetText("|cff9999aa" .. btn.text:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
    end
end

local function ClearAllRows(frame)
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
    if frame.settingsPanel then
        frame.settingsPanel:Hide()
    end
end

local function CreateHeaderRow(parent, columns)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetSize(FRAME_WIDTH - 52, 22)
    header:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.10, 0.10, 0.13, 0.95)
    header:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.9)

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
    if activeTab == "settings" then
        frame.settingsBtn:SetBackdropColor(0.20, 0.24, 0.32, 1)
        frame.settingsBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        if frame.settingsBtn.icon then frame.settingsBtn.icon:SetVertexColor(1, 0.82, 0) end
    else
        frame.settingsBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        frame.settingsBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
        if frame.settingsBtn.icon then frame.settingsBtn.icon:SetVertexColor(0.75, 0.75, 0.8) end
    end
end

-- Renders the AlterEgo-style Alt Grid View
local function RenderRosterView(frame)
    frame.filterBar:Hide()
    if frame.columnsBtn then frame.columnsBtn:Show() end
    if frame.historyFooter then frame.historyFooter:Hide() end
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 14)
    selectedMatch = nil
    
    SetTabActive(frame.tabRoster, true)
    SetTabActive(frame.tabHistory, false)
    UpdateSettingsButtonState(frame)
    
    -- Make sure active character's ratings and spec are up-to-date
    if ns.UpdateAllCharacterRatings then
        ns.UpdateAllCharacterRatings()
    end
    
    local keys = GetSortedCharacterKeys()
    local totalMatchesAll = 0
    local totalWinsAll = 0
    local peakRatingAll = 0
    
    -- Aggregate stats across all characters & matches & bracket ratings
    for _, key in ipairs(keys) do
        local rec = AlterArenaDB.players[key]
        if rec then
            if rec.matches then
                for _, m in ipairs(rec.matches) do
                    totalMatchesAll = totalMatchesAll + 1
                    if m.won then totalWinsAll = totalWinsAll + 1 end
                    if m.ratingAfter and m.ratingAfter > peakRatingAll then
                        peakRatingAll = m.ratingAfter
                    end
                    if m.ratingBefore and m.ratingBefore > peakRatingAll then
                        peakRatingAll = m.ratingBefore
                    end
                end
            end
            if rec.bracketRatings then
                for _, bData in pairs(rec.bracketRatings) do
                    if bData.current and bData.current > peakRatingAll then
                        peakRatingAll = bData.current
                    end
                end
            end
        end
    end

    local overallWinRate = totalMatchesAll > 0 and math.floor((totalWinsAll / totalMatchesAll) * 100) or 0

    -- Summary Stat Cards at Top
    local statY = 0
    local cardWidth = (FRAME_WIDTH - 64) / 4
    local statCards = {
        { label = "TRACKED CHARACTERS", value = tostring(#keys), color = "ffffffff" },
        { label = "TOTAL MATCHES", value = tostring(totalMatchesAll), color = "ffffd100" },
        { label = "OVERALL WIN RATE", value = string.format("%d%%", overallWinRate), color = overallWinRate >= 50 and "ff22c55e" or "ffef4444" },
        { label = "PEAK RATING", value = peakRatingAll > 0 and tostring(peakRatingAll) or "---", color = "ff38bdf8" },
    }

    for i, sc in ipairs(statCards) do
        local card = frame.headerCards[i]
        if not card then
            card = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
            card:SetSize(cardWidth - 6, 44)
            card:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            card:SetBackdropColor(0.10, 0.10, 0.13, 0.9)
            card:SetBackdropBorderColor(0.18, 0.19, 0.23, 0.9)

            card.val = card:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
            card.val:SetPoint("TOP", 0, -6)

            card.lbl = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            card.lbl:SetPoint("BOTTOM", 0, 6)
            card.lbl:SetFont(card.lbl:GetFont(), 9)

            frame.headerCards[i] = card
        end
        card:SetPoint("TOPLEFT", (i - 1) * cardWidth + 2, statY)
        card.val:SetText(string.format("|c%s%s|r", sc.color, sc.value))
        card.lbl:SetText(string.format("|cff888899%s|r", sc.label))
        card:Show()
    end

    -- Sort bar
    statY = statY - 54

    local sortBar = frame.sortBar
    if not sortBar then
        sortBar = CreateFrame("Frame", nil, frame.content)
        sortBar:SetSize(FRAME_WIDTH - 52, 24)
        frame.sortBar = sortBar

        local lbl = sortBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", 0, 0)
        lbl:SetText("|cff888899Sort:|r")

        local options = {
            { id = "name",    text = "Name" },
            { id = "rating",  text = "Highest Rating" },
            { id = "recent",  text = "Recent" },
            { id = "winrate", text = "Win Rate" },
        }

        local prev = lbl
        frame.sortButtons = {}
        for _, opt in ipairs(options) do
            local btn = CreateStyledButton(sortBar, opt.text, 100, 20)
            btn:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            btn.sortId = opt.id
            btn:SetScript("OnClick", function(self)
                rosterSortMode = self.sortId
                ns.RefreshUI()
            end)
            frame.sortButtons[opt.id] = btn
            prev = btn
        end
    end
    sortBar:SetPoint("TOPLEFT", 2, statY)
    sortBar:Show()

    for id, btn in pairs(frame.sortButtons) do
        SetTabActive(btn, id == rosterSortMode)
    end

    statY = statY - 30

    -- Table Columns Header ( dynamic based on visible columns)
    local header = frame.rosterHeader

    if not header then
        header = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
        header:SetSize(FRAME_WIDTH - 52, 22)
        header:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        header:SetBackdropColor(0.10, 0.10, 0.13, 0.95)
        header:SetBackdropBorderColor(0.18, 0.18, 0.22, 0.9)
        frame.rosterHeader = header
        frame.rosterHeaderTexts = {}
    end

    do
        local prev = nil
        local cursorX = 10
        for i, def in ipairs(COLUMN_DEFS) do
            local txt = frame.rosterHeaderTexts[i]
            if not txt then
                txt = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                frame.rosterHeaderTexts[i] = txt
            end
            local cv = GetColumnVisibility()
            if def.always or cv[def.id] then
                local iconPrefix = GetColumnIconMarkup(def, 12) or ""
                txt:SetText(iconPrefix .. "|cff888899" .. def.title .. "|r")
                txt:ClearAllPoints()
                txt:SetPoint("LEFT", header, "LEFT", cursorX, 0)
                txt:SetWidth(def.width)
                txt:SetJustifyH(def.align or "LEFT")
                txt:Show()
                cursorX = cursorX + def.width + 6
            else
                txt:Hide()
            end
        end
    end

    header:SetPoint("TOPLEFT", 2, statY)
    header:Show()
    
    -- Auto-widen the main frame if the visible columns need more room.
    -- GetRequiredRosterWidth() returns the CONTENT width (columns + gaps +
    -- padding). The frame itself needs ~50px extra for the scrollbar.
    local contentWidth = GetRequiredRosterWidth()
    frame.rosterContentWidth = contentWidth    -- so new rows can read it

    local frameWidth = contentWidth + 50
    local clampedFrameWidth = math.max(FRAME_WIDTH, math.min(frameWidth, 1400))

    if frame:GetWidth() ~= clampedFrameWidth then
        frame:SetWidth(clampedFrameWidth)
    end

    if frame.content then
        frame.content:SetWidth(contentWidth)
    end
    if frame.rosterHeader then
        frame.rosterHeader:SetWidth(contentWidth)
    end
    for _, row in ipairs(frame.rosterRows) do
        row:SetWidth(contentWidth)
    end

    -- If the frame grew past the right edge, snap it back on-screen.
    local right = frame:GetRight()
    if right and right > (UIParent:GetWidth() - 20) then
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -60)
    end

    local rowY = statY - 26
    local rowCounter = 0

    local function GetOrCreateRosterRow(index)
        local row = frame.rosterRows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.content, "BackdropTemplate")
            row:SetSize(frame.rosterContentWidth or (FRAME_WIDTH - 52), ROW_HEIGHT)
            row:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.16, 0.18, 0.24, 0.9)
                local pRec = self.playerRec
                if not pRec then return end

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()

                local charColor = GetClassColor(pRec.class)
                GameTooltip:AddDoubleLine(
                    string.format("|c%s%s|r", charColor.colorStr or "ffffffff", pRec.name or "Character"),
                    string.format("|cff888899%s|r", pRec.realm or ""),
                    1, 1, 1, 1, 1, 1
                )

                -- Best overall tier
                local bestRating, bestBracket = 0, nil
                if pRec.bracketRatings then
                    for bName, bData in pairs(pRec.bracketRatings) do
                        if bData.current and bData.current > bestRating then
                            bestRating = bData.current
                            bestBracket = bName
                        end
                    end
                end
                if bestRating > 0 then
                    local col = GetRatingColor(bestRating)
                    local tier = GetPvPTierName(bestRating) or "Unranked"
                    GameTooltip:AddDoubleLine(
                        string.format("|cff888899Best:|r |c%s%d|r |cff888899%s|r", col, bestRating, bestBracket or ""),
                        string.format("|c%s%s|r", col, tier)
                    )
                else
                    GameTooltip:AddLine("|cff888899Unranked — no rated matches recorded.|r")
                end

                -- Per-bracket breakdown
                local brackets = { "Shuffle", "Blitz", "2v2", "3v3" }
                local anyBracket = false
                for _, bName in ipairs(brackets) do
                    local cur = pRec.bracketRatings and pRec.bracketRatings[bName]
                    local peak = ns.GetPeak and ns.GetPeak(pRec, bName)
                    local curRating = cur and cur.current or 0
                    if curRating > 0 or (peak and peak > 0) then
                        if not anyBracket then
                            GameTooltip:AddLine(" ")
                            anyBracket = true
                        end
                        local col = GetRatingColor(curRating)
                        local tier = GetPvPTierName(curRating) or "—"
                        local peakStr = (peak and peak > curRating)
                            and string.format("  |cff666677peak %d|r", peak)
                            or ""
                        GameTooltip:AddDoubleLine(
                            string.format("|cffffffff%s|r", bName),
                            string.format("|c%s%s|r |cff888899%s|r%s", col, tostring(curRating), tier, peakStr)
                        )
                    end
                end

                -- Spec breakdown for Solo Shuffle
                if pRec.specStats and next(pRec.specStats) then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffffd100Solo Shuffle — by spec:|r")
                    for sName, sData in pairs(pRec.specStats) do
                        local iconPrefix = sData.icon and string.format("|T%s:14:14:0:0|t ", sData.icon) or ""
                        local col, rStr = GetRatingColor(sData.rating or 0)
                        local peak = ns.GetPeak and ns.GetPeak(pRec, "Shuffle-" .. sName)
                        local peakStr = (peak and peak > (sData.rating or 0))
                            and string.format("  |cff666677peak %d|r", peak)
                            or ""
                        local w = sData.roundsWon or 0
                        local l = sData.roundsLost or 0
                        local pct = sData.winRate or 0
                        local pctCol = (pct >= 50) and "22c55e" or "ef4444"

                        GameTooltip:AddDoubleLine(
                            string.format("%s|cffffffff%s|r", iconPrefix, sName),
                            string.format("|c%s%s|r%s  |cff22c55e%d|r-|cffef4444%d|r (|cff%s%.0f%%|r)",
                                col, rStr, peakStr, w, l, pctCol, pct)
                        )
                    end
                end

                -- Currency snapshot
                if pRec.currency and next(pRec.currency) then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffffd100Currencies|r")

                    local function CurrencyLine(key, label)
                        local c = pRec.currency[key]
                        if not c then return end
                        local wallet = c.amount or 0
                        local earned = c.totalEarned or wallet
                        local cap    = c.max or 0
                        local age = c.updated and (time() - c.updated) or nil
                        local ageStr = ""
                        if age then
                            if age < 3600 then ageStr = string.format("|cff666677%dm|r", math.floor(age/60))
                            elseif age < 86400 then ageStr = string.format("|cff666677%dh|r", math.floor(age/3600))
                            else ageStr = string.format("|cff666677%dd|r", math.floor(age/86400)) end
                        end

                        local iconStr = GetColumnIconMarkup({ currencyKey = key }, 14)

                        GameTooltip:AddDoubleLine(
                            string.format("  %s%s", iconStr, label),
                            string.format("|cffffffffTotal:|r %d   |cff888899Season:|r %d |cff666677/ %d|r   %s",
                                wallet, earned, cap, ageStr)
                        )
                    end

                    CurrencyLine("conquest", "Conquest")
                    CurrencyLine("honor",    "Honor")
                    CurrencyLine("tokens",   "Bloody Tokens")
                end

                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if self.playerRec and self.playerRec.name == UnitName("player") and self.playerRec.realm == GetRealmName() then
                    self:SetBackdropColor(0.10, 0.16, 0.12, 0.85)
                    self:SetBackdropBorderColor(0.22, 0.55, 0.28, 0.9)
                else
                    local bgAlpha = (self.rowIndex % 2 == 0) and 0.5 or 0.25
                    self:SetBackdropColor(0.09, 0.09, 0.12, bgAlpha)
                    self:SetBackdropBorderColor(0.14, 0.14, 0.18, 0.6)
                end
                GameTooltip:Hide()
            end)

            row.texts = row.texts or {}
            for _, def in ipairs(COLUMN_DEFS) do
                if not row.texts[def.id] then
                    row.texts[def.id] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                end
            end
            row.charText     = row.texts.name
            row.specText     = row.texts.spec
            row.bestText     = row.texts.best
            row.shuffleText  = row.texts.shuffle
            row.blitzText    = row.texts.blitz
            row.twoText      = row.texts.two
            row.threeText    = row.texts.three
            row.conquestText = row.texts.conquest
            row.honorText    = row.texts.honor
            row.tokensText   = row.texts.tokens
            row.recordText   = row.texts.record

            frame.rosterRows[index] = row
        end
        return row
    end

    -- Helper to format rating with optional delta (+25)
    local function FormatRatingWithDelta(bData)
        if not bData then return "|cff777788---|r" end
        local rVal = bData.current or bData.rating
        if not rVal or rVal <= 0 then
            return "|cff777788---|r"
        end
        local col, valStr = GetRatingColor(rVal)
        local chg = bData.change or bData.ratingChange
        if chg and chg ~= 0 and math.abs(chg) <= 150 then
            local chgStr = (chg > 0)
                and string.format(" |cff22c55e(+%d)|r", chg)
                or string.format(" |cffef4444(%d)|r", chg)
            return string.format("|c%s%s|r%s", col, valStr, chgStr)
        end
        return string.format("|c%s%s|r", col, valStr)
    end

    for _, key in ipairs(keys) do
        local rec = AlterArenaDB.players[key]
        local isCurrentChar = (key == ns.GetPlayerKey())
        rowCounter = rowCounter + 1
        local row = GetOrCreateRosterRow(rowCounter)

        row.rowIndex = rowCounter
        row.playerRec = rec
        local bgAlpha = (rowCounter % 2 == 0) and 0.5 or 0.25

        if isCurrentChar then
            row:SetBackdropColor(0.10, 0.16, 0.12, 0.85)
            row:SetBackdropBorderColor(0.22, 0.55, 0.28, 0.9)
        else
            row:SetBackdropColor(0.09, 0.09, 0.12, bgAlpha)
            row:SetBackdropBorderColor(0.14, 0.14, 0.18, 0.6)
        end

        row:SetPoint("TOPLEFT", 2, rowY)

        local charColor = GetClassColor(rec.class)
        local curMarker = isCurrentChar and "  |A:communities-icon-notification:13:13|a" or ""
        row.charText:SetText(string.format("|c%s%s|r%s", charColor.colorStr or "ffffffff", rec.name or key, curMarker))

        -- Spec display with icon if available
        local specName = rec.spec
        local specIcon = rec.specIcon
        if isCurrentChar and GetSpecialization and GetSpecializationInfo then
            local sIdx = GetSpecialization()
            if sIdx then
                local _, sName, _, sIcon = GetSpecializationInfo(sIdx)
                if sName then specName = sName rec.spec = sName end
                if sIcon then specIcon = sIcon rec.specIcon = sIcon end
            end
        end

        -- If specName is still missing on alt, check specStats or matches
        if not specName then
            if rec.specStats then
                for sName, sData in pairs(rec.specStats) do
                    if sData and ((sData.roundsPlayed and sData.roundsPlayed > 0) or (sData.rating and sData.rating > 0)) then
                        specName = sName
                        specIcon = sData.icon
                        break
                    end
                end
            end
            if not specName and rec.matches and #rec.matches > 0 then
                for i = #rec.matches, 1, -1 do
                    if rec.matches[i].spec then
                        specName = rec.matches[i].spec
                        specIcon = rec.matches[i].specIcon
                        break
                    end
                end
            end
        end

        local specDisplay = ""
        if specName then
            if specIcon then
                specDisplay = string.format("|T%s:14:14:0:0|t |cffffffff%s|r", specIcon, specName)
            else
                specDisplay = string.format("|cffffffff%s|r", specName)
            end
        else
            specDisplay = string.format("|cffaaaaaa%s|r", rec.class or "Unknown")
        end
        row.specText:SetText(specDisplay)

        -- Best Tier column
        local bestRating = 0
        local bestBracket = nil
        if rec.bracketRatings then
            for bName, bData in pairs(rec.bracketRatings) do
                if bData.current and bData.current > bestRating then
                    bestRating = bData.current
                    bestBracket = bName
                end
            end
        end

        if bestRating > 0 then
            local col = GetRatingColor(bestRating)
            local tier = GetPvPTierName(bestRating)
            local tierStr = tier and string.format(" |c%s%s|r", col, tier) or ""
            row.bestText:SetText(string.format("|c%s%d|r%s", col, bestRating, tierStr))
        else
            row.bestText:SetText("|cff777788---|r")
        end

        local shuffleData = ns.GetCharacterBracketData and ns.GetCharacterBracketData(rec, "Shuffle", specName)
        local blitzData = ns.GetCharacterBracketData and ns.GetCharacterBracketData(rec, "Blitz", specName)
        local twoData = ns.GetCharacterBracketData and ns.GetCharacterBracketData(rec, "2v2")
        local threeData = ns.GetCharacterBracketData and ns.GetCharacterBracketData(rec, "3v3")

        row.shuffleText:SetText(FormatRatingWithDelta(shuffleData))
        row.blitzText:SetText(FormatRatingWithDelta(blitzData))
        row.twoText:SetText(FormatRatingWithDelta(twoData))
        row.threeText:SetText(FormatRatingWithDelta(threeData))

        -- Accurate Wins / Losses: use season rounds if available, otherwise match history
        local charWins = 0
        local charLoss = 0
        local charTotal = 0
        if shuffleData and shuffleData.roundsPlayed and shuffleData.roundsPlayed > 0 then
            charWins = shuffleData.roundsWon or 0
            charTotal = shuffleData.roundsPlayed
            charLoss = shuffleData.roundsLost or (charTotal - charWins)
        elseif specName and rec.specStats and rec.specStats[specName] and rec.specStats[specName].roundsPlayed and rec.specStats[specName].roundsPlayed > 0 then
            local ss = rec.specStats[specName]
            charWins = ss.roundsWon or 0
            charTotal = ss.roundsPlayed
            charLoss = ss.roundsLost or (charTotal - charWins)
        elseif rec.matches and #rec.matches > 0 then
            charTotal = #rec.matches
            for _, m in ipairs(rec.matches) do
                if m.won then charWins = charWins + 1 end
            end
            charLoss = charTotal - charWins
        end
        local charPct = charTotal > 0 and math.floor((charWins / charTotal) * 100) or 0
        local pctColor = charPct >= 50 and "ff22c55e" or (charTotal > 0 and "ffef4444" or "ff888899")

        row.recordText:SetText(string.format("|cff22c55e%d|r - |cffef4444%d|r (|c%s%d%%|r)", charWins, charLoss, pctColor, charPct))
        -- Currency columns (cached values — live API only for the logged-in character)
        do
            local cur = rec.currency or {}

                        local function FormatCurrency(data)
                if not data then return "|cff555566---|r" end
                local wallet = data.amount or 0
                local cap    = data.max or 0

                if cap > 0 then
                    local pct = wallet / cap
                    local col = "ffffffff"
                    if pct >= 0.95      then col = "ff22c55e"   -- near cap, spend it
                    elseif pct >= 0.50  then col = "ffffd100"
                    elseif pct <  0.10  then col = "ffef4444"   -- barely touched
                    end
                    return string.format("|c%s%d|r |cff666677/ %d|r", col, wallet, cap)
                end
                return string.format("|cffffffff%d|r", wallet)
            end

            row.conquestText:SetText(FormatCurrency(cur.conquest))
            row.honorText:SetText(FormatCurrency(cur.honor))
            row.tokensText:SetText(FormatCurrency(cur.tokens))
        end
        PositionRowColumns(row)
        row:Show()
        rowY = rowY - (ROW_HEIGHT + 2)

        -- Check for secondary specs played (e.g. Affliction when Destruction is active)
        if rec.specStats then
            for sName, sData in pairs(rec.specStats) do
                if sName ~= specName and ((sData.roundsPlayed and sData.roundsPlayed > 0) or (sData.rating and sData.rating > 0)) then
                    rowCounter = rowCounter + 1
                    local subRow = GetOrCreateRosterRow(rowCounter)
                    subRow.rowIndex = rowCounter
                    subRow.playerRec = rec
                    subRow:SetBackdropColor(0.07, 0.07, 0.09, 0.4)
                    subRow:SetBackdropBorderColor(0.12, 0.12, 0.15, 0.4)
                    subRow:SetPoint("TOPLEFT", 2, rowY)

                    subRow.charText:SetText("|cff666677  >|r |cff888899(Spec)|r")

                    local subSpecDisplay = ""
                    if sData.icon then
                        subSpecDisplay = string.format("|T%s:13:13:0:0|t |cffcccccc%s|r", sData.icon, sName)
                    else
                        subSpecDisplay = string.format("|cffcccccc%s|r", sName)
                    end
                    subRow.specText:SetText(subSpecDisplay)
                    subRow.bestText:SetText("|cff555566---|r")
                    subRow.conquestText:SetText("|cff555566---|r")
                    subRow.honorText:SetText("|cff555566---|r")
                    subRow.tokensText:SetText("|cff555566---|r")
                    PositionRowColumns(subRow)

                    local subShuffleData = ns.GetCharacterBracketData and ns.GetCharacterBracketData(rec, "Shuffle", sName) or sData
                    subRow.shuffleText:SetText(FormatRatingWithDelta(subShuffleData))
                    subRow.blitzText:SetText("|cff555566---|r")
                    subRow.twoText:SetText("|cff555566---|r")
                    subRow.threeText:SetText("|cff555566---|r")

                    local sW = sData.roundsWon or 0
                    local sL = sData.roundsLost or ((sData.roundsPlayed or 0) - sW)
                    local sTot = (sData.roundsPlayed and sData.roundsPlayed > 0) and sData.roundsPlayed or (sW + sL)
                    local sPct = sData.winRate or ((sTot > 0) and math.floor((sW / sTot) * 100) or 0)
                    local sPctCol = (sPct >= 50) and "ff22c55e" or "ffef4444"
                    subRow.recordText:SetText(string.format("|cff22c55e%d|r - |cffef4444%d|r (|c%s%.0f%%|r)", sW, sL, sPctCol, sPct))

                    subRow:Show()
                    rowY = rowY - (ROW_HEIGHT + 2)
                end
            end
        end
    end

    frame.content:SetHeight(math.abs(rowY) + 20)
end

-- Renders the AlterEgo-style Detailed Match History Ledger
local function RenderHistoryView(frame)
    if frame.rosterHeader then frame.rosterHeader:Hide() end
    if frame.sortBar then frame.sortBar:Hide() end
    frame.filterBar:Show()
    if frame.columnsBtn then frame.columnsBtn:Hide() end
    SetTabActive(frame.tabRoster, false)
    SetTabActive(frame.tabHistory, true)
    UpdateSettingsButtonState(frame)


    -- Update Character button label
    if frame.charBtn then
        local effectiveKey = selectedCharKey or ns.GetPlayerKey()
        local rec = AlterArenaDB.players[effectiveKey]
        local name = (rec and rec.name) or effectiveKey or "Character"
        local c = GetClassColor(rec and rec.class)
        local isCurrent = (effectiveKey == ns.GetPlayerKey())

        frame.charBtn.text:SetText(string.format("|c%s%s|r", c.colorStr or "ffffffff", name))

        if isCurrent then
            frame.charBtn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
            frame.charBtn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        else
            -- Gold border when viewing another character
            frame.charBtn:SetBackdropColor(0.20, 0.24, 0.32, 1)
            frame.charBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        end
    end

    -- Update bracket button label + Clear button visibility
    if frame.bracketBtn then
        local current = BRACKET_LABELS[historyFilters.bracket] or "Bracket"
        local active = (historyFilters.bracket ~= "ALL")
        if active then
            frame.bracketBtn:SetBackdropColor(0.20, 0.24, 0.32, 1)
            frame.bracketBtn:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
            frame.bracketBtn.text:SetText("|cffffd100" .. current .. "|r")
        else
            frame.bracketBtn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
            frame.bracketBtn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
            frame.bracketBtn.text:SetText("|cff9999aa" .. current .. "|r")
        end
    end

    if frame.clearFiltersBtn then
        local anyActive = (historyFilters.bracket ~= "ALL")
                       or (historyFilters.result  ~= "ALL")
                       or (historyFilters.map     ~= "ALL")
                       or (historyFilters.season  ~= "ALL")
                       or (historyFilters.date    ~= "ALL")
        frame.clearFiltersBtn:Show()
        if anyActive then
            frame.clearFiltersBtn:SetAlpha(1)
            frame.clearFiltersBtn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
            frame.clearFiltersBtn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
            frame.clearFiltersBtn.text:SetText("|cffddddddClear|r")
        else
            frame.clearFiltersBtn:SetAlpha(0.4)
            frame.clearFiltersBtn:SetBackdropColor(0.09, 0.10, 0.12, 0.9)
            frame.clearFiltersBtn:SetBackdropBorderColor(0.16, 0.17, 0.20, 0.9)
            frame.clearFiltersBtn.text:SetText("|cff666677Clear|r")
        end
    end

    UpdateMoreFiltersButton(frame)

    selectedCharKey = selectedCharKey or ns.GetPlayerKey()
    local rec = AlterArenaDB.players[selectedCharKey]
    local allMatches = (rec and rec.matches) or {}

    -- Filter matches
    local filteredMatches = {}
    for _, m in ipairs(allMatches) do
        local pass = true
        local b = GetMatchBracket(m)

        --Bracket
        if historyFilters.bracket ~= "ALL" then
            if historyFilters.bracket == "Shuffle" then
                if not (b == "Shuffle" or b == "Solo Shuffle" or not m.bracket) then
                    pass = false
                end
            elseif historyFilters.bracket == "Blitz" then
                if not (b == "Blitz" or b == "Battleground Blitz") then
                    pass = false
                end
            elseif b ~= historyFilters.bracket then
                pass = false
            end
        end

        -- Result
        if pass and historyFilters.result ~= "ALL" then
            local outcome = GetMatchOutcome(m)
            if historyFilters.result == "WINS"   and outcome ~= "W" then pass = false end
            if historyFilters.result == "LOSSES" and outcome ~= "L" then pass = false end
            if historyFilters.result == "DRAWS"  and outcome ~= "D" then pass = false end
        end

        -- Map
        if pass and historyFilters.map ~= "ALL" then
            local mapName = m.map or m.mapName or ""
            if mapName ~= historyFilters.map then
                pass = false
            end
        end

                -- Date
        if pass and historyFilters.date ~= "ALL" then
            local window = DATE_CUTOFFS[historyFilters.date]
            if window then
                local cutoff = time() - window
                if (m.timestamp or 0) < cutoff then
                    pass = false
                end
            end
        end

        -- Season
        if pass and historyFilters.season ~= "ALL" then
            local currentId = ns.currentSeasonId
            local lastId    = AlterArenaDB.lastSeasonId

            if historyFilters.season == "CURRENT" then
                -- If we don't know the current season, show nothing for this filter
                if not currentId or m.seasonId ~= currentId then
                    pass = false
                end
            elseif historyFilters.season == "LAST" then
                if not lastId or m.seasonId ~= lastId then
                    pass = false
                end
            end
        end

        if pass then
            table.insert(filteredMatches, m)
        end
    end

    local cols = {
        { title = "Date",          width = 72,  gap = 4, stretch = false },
        { title = "Outcome",       width = 62,  align = "CENTER", gap = 4, stretch = false },
        { title = "Bracket",       width = 85,  gap = 4 },
        { title = "Team",          width = 55,  align = "CENTER", gap = 4, stretch = false },
        { title = "Enemy Team",    width = 140, align = "CENTER", gap = 4 },
        { title = "Rating & Delta",width = 120, gap = 4 },
        { title = "MMR",           width = 55,  align = "CENTER", gap = 4, stretch = false },
        { title = "Enemy MMR",     width = 75,  align = "CENTER", gap = 4, stretch = false },
        { title = "Map",           width = 145, gap = 4 },
        { title = "Duration",      width = 70,  align = "CENTER", gap = 4, stretch = false },
        { title = "Queue",         width = 65,  align = "CENTER", gap = 4, stretch = false },
    }

    -- Stretch the column widths so they fill the current frame width.
    -- The frame itself stays where it is; only the table adapts.
    local frameInner = frame:GetWidth() - 50      -- matches the scroll frame's usable area
    local baseWidth = 0
    local gapTotal  = 0
    for i, c in ipairs(cols) do
        baseWidth = baseWidth + c.width
        if i < #cols then
            gapTotal = gapTotal + (c.gap or 6)
        end
    end
    -- Total slack we need to distribute across flexible columns
    local slack = frameInner - (baseWidth + gapTotal + 20)
    if slack > 0 then
        -- Columns with stretch=false keep their size; the rest share slack
        local flexCount = 0
        for _, c in ipairs(cols) do
            if c.stretch ~= false then flexCount = flexCount + 1 end
        end
        if flexCount > 0 then
            local perCol = math.floor(slack / flexCount)
            local remainder = slack - perCol * flexCount
            for _, c in ipairs(cols) do
                if c.stretch ~= false then
                    c.width = c.width + perCol
                    if remainder > 0 then
                        c.width = c.width + 1
                        remainder = remainder - 1
                    end
                end
            end
        end
    end

    local historyContentWidth = frameInner

    local header = frame.historyHeader
    if not header then
        header = CreateHeaderRow(frame.content, cols)
        frame.historyHeader = header
    end
    header:SetWidth((frame:GetWidth() or FRAME_WIDTH) - 52)
    header:SetPoint("TOPLEFT", 2, 0)
    header:Show()

    local rowY = -26
    local total = #filteredMatches

    if total == 0 then
        if frame.emptyHistoryMsg then
            frame.emptyHistoryMsg:SetText("|cff888899No recorded matches found for this filter.|r")
            frame.emptyHistoryMsg:Show()
        end
    else
        if frame.emptyHistoryMsg then
            frame.emptyHistoryMsg:Hide()
        end
    end

    -- Compute Footer Statistics
    local totalCount = 0
    local totalWins = 0
    local totalDraws = 0
    local totalLosses = 0

    local sessTotal = 0
    local sessWins = 0
    local sessDraws = 0
    local sessLosses = 0
    local sessRatingDelta = 0
    local oldestSessionTime = nil

    local selCount = 0
    local selWins = 0
    local selDraws = 0
    local selLosses = 0

    local now = time()
    for _, m in ipairs(filteredMatches) do
        local outcome = GetMatchOutcome(m)
        totalCount = totalCount + 1
        if outcome == "W" then
            totalWins = totalWins + 1
        elseif outcome == "D" then
            totalDraws = totalDraws + 1
        else
            totalLosses = totalLosses + 1
        end

        local mTime = m.timestamp or 0
        local isSession = false
        if mTime >= sessionStartTime then
            isSession = true
        elseif (now - mTime) <= 14400 then -- within last 4 hours
            isSession = true
        end

        if isSession then
            sessTotal = sessTotal + 1
            if outcome == "W" then
                sessWins = sessWins + 1
            elseif outcome == "D" then
                sessDraws = sessDraws + 1
            else
                sessLosses = sessLosses + 1
            end

            local rChg = m.ratingChange or 0
            sessRatingDelta = sessRatingDelta + rChg

            if not oldestSessionTime or mTime < oldestSessionTime then
                oldestSessionTime = mTime
            end
        end

        if selectedMatches[m] then
            selCount = selCount + 1
            if outcome == "W" then
                selWins = selWins + 1
            elseif outcome == "D" then
                selDraws = selDraws + 1
            else
                selLosses = selLosses + 1
            end
        end
    end

    if frame.historyFooter then
        frame.historyFooter:Show()
        frame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 58)

        -- Bottom Left 1: Current Session
        local sessWinPct = sessTotal > 0 and math.floor((sessWins / sessTotal) * 100) or 0
        local sessPctColor = sessWinPct >= 50 and "ff22c55e" or (sessTotal > 0 and "ffef4444" or "ff888899")
        local sessDeltaStr = ""
        if sessRatingDelta > 0 then
            sessDeltaStr = string.format("  |cff22c55e'+%d'|r", sessRatingDelta)
        elseif sessRatingDelta < 0 then
            sessDeltaStr = string.format("  |cffef4444'%d'|r", sessRatingDelta)
        else
            sessDeltaStr = "  |cff888888'+0'|r"
        end

        frame.historyFooter.sessionLeft1:SetText(string.format(
            "|cffffd100Current Session :|r %d Arenas =>  |cff22c55e%d|r / |cffffd100%d|r / |cffef4444%d|r  |c%s%d%% Winrate|r%s",
            sessTotal, sessWins, sessDraws, sessLosses, sessPctColor, sessWinPct, sessDeltaStr
        ))

        -- Bottom Left 2: Total Arenas
        local totWinPct = totalCount > 0 and math.floor((totalWins / totalCount) * 100) or 0
        local totPctColor = totWinPct >= 50 and "ff22c55e" or (totalCount > 0 and "ffef4444" or "ff888899")

        frame.historyFooter.sessionLeft2:SetText(string.format(
            "|cffffd100Total Arenas  :|r %d Arenas =>  |cff22c55e%d|r / |cffffd100%d|r / |cffef4444%d|r  |c%s%d%% Winrate|r",
            totalCount, totalWins, totalDraws, totalLosses, totPctColor, totWinPct
        ))

        -- Bottom Center 1: Session Duration
        local sessDurSeconds = now - sessionStartTime
        if oldestSessionTime and (now - oldestSessionTime > sessDurSeconds) then
            sessDurSeconds = now - oldestSessionTime
        end
        local sH = math.floor(sessDurSeconds / 3600)
        local sM = math.floor((sessDurSeconds % 3600) / 60)
        frame.historyFooter.sessionCenter1:SetText(string.format("|cffffd100Session Duration:|r |cffffffff%dh%02dm|r", sH, sM))

        -- Bottom Center 2: Selection summary
        if selCount > 0 then
            local selWinPct = math.floor((selWins / selCount) * 100)
            local selPctColor = selWinPct >= 50 and "ff22c55e" or "ffef4444"
            frame.historyFooter.sessionCenter2:SetText(string.format(
                "|cffffd100Selected|r %d arenas =>  |cff22c55e%d|r / |cffffd100%d|r / |cffef4444%d|r  |c%s%d%% Winrate|r",
                selCount, selWins, selDraws, selLosses, selPctColor, selWinPct
            ))
            frame.historyFooter.clearBtn:Show()
            frame.historyFooter.clearBtn.text:SetText(string.format("Clear Selected (%d)", selCount))
        else
            frame.historyFooter.sessionCenter2:SetText("|cff888899Selected (Click match to select)|r")
            frame.historyFooter.clearBtn:Hide()
        end
    end

    if total == 0 then
        frame.content:SetHeight(120)
        return
    end

    local function GetOrCreateHistoryRow(index)
        local row = frame.historyRows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.content, "BackdropTemplate")
            row:SetSize((frame:GetWidth() or FRAME_WIDTH) - 52, ROW_HEIGHT)
            row:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            row:SetScript("OnClick", function(self)
                if self.matchData then
                    if selectedMatches[self.matchData] then
                        selectedMatches[self.matchData] = nil
                    else
                        selectedMatches[self.matchData] = true
                    end
                    ns.RefreshUI()
                end
            end)
            row:SetScript("OnEnter", function(self)
                if not selectedMatches[self.matchData] then
                    self:SetBackdropColor(0.16, 0.18, 0.24, 0.9)
                end
                local match = self.matchData
                if not match then return end

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()

                local bName = match.bracket or "Solo Shuffle"
                local isShuffle = (bName == "Solo Shuffle" or bName == "Shuffle" or bName == "Solo")

                if isShuffle and match.roundsWon ~= nil then
                    local wCol = match.roundsWon >= 4 and "22c55e" or (match.roundsWon == 3 and "ffd100" or "ef4444")
                    GameTooltip:AddDoubleLine(
                        string.format("|cffffd100%s|r", bName),
                        string.format("|cff%sWins: %d|r", wCol, match.roundsWon),
                        1, 1, 1, 1, 1, 1
                    )
                else
                    local outcomeStr = match.won and "|cff22c55eVICTORY|r" or (match.won == false and "|cffef4444DEFEAT|r" or "|cffffd100DRAW|r")
                    GameTooltip:AddDoubleLine(string.format("|cffffd100%s|r", bName), outcomeStr, 1, 1, 1, 1, 1, 1)
                end

                -- Round-by-round breakdown for Solo Shuffle
                if match.rounds and #match.rounds > 0 then
                    GameTooltip:AddLine(" ")
                    for rNum, rData in ipairs(match.rounds) do
                                                local teamIcons = ""
                        if rData.team then
                            for _, ic in ipairs(rData.team) do
                                teamIcons = teamIcons .. string.format("|T%s:20:20:0:0|t ", ic)
                            end
                        end
                        local enemyIcons = ""
                        if rData.enemy then
                            for _, ic in ipairs(rData.enemy) do
                                enemyIcons = enemyIcons .. string.format("|T%s:20:20:0:0|t ", ic)
                            end
                        end

                        local leftSide = string.format("|cff22c55e%d:|r %s|cffffd100vs|r %s", rNum, teamIcons, enemyIcons)

                        local dColor = (rData.won == true and "22c55e") or (rData.won == false and "ef4444") or "ffd100"
                        local durText = ""
                        if rData.duration and rData.duration > 0 then
                            durText = FormatRoundDuration(rData.duration)
                        elseif rData.won ~= nil then
                            durText = rData.won and "Win" or "Loss"
                        else
                            durText = "—"
                        end
                        local rightSide = string.format("|cff%s%s|r", dColor, durText)

                        GameTooltip:AddDoubleLine(leftSide, rightSide)
                    end

                    if (match.mostWins and match.mostWins.name) or (match.mostDeaths and match.mostDeaths.name) then
                        GameTooltip:AddLine(" ")
                        if match.mostWins and match.mostWins.name then
                            GameTooltip:AddDoubleLine(
                                "|cff9ca3afMost Wins:|r",
                                string.format("|c%s%s|r  |cffffffff%d|r", match.mostWins.classColor or "ffffffff", match.mostWins.name, match.mostWins.wins)
                            )
                        end
                        if match.mostDeaths and match.mostDeaths.name then
                            GameTooltip:AddDoubleLine(
                                "|cff9ca3afMost Deaths:|r",
                                string.format("|c%s%s|r  |cffffffff%d|r", match.mostDeaths.classColor or "ffffffff", match.mostDeaths.name, match.mostDeaths.deaths)
                            )
                        end
                    end
                elseif match.enemyTeam and #match.enemyTeam > 0 then
                    GameTooltip:AddLine(" ")
                    local teamStr = ""
                    if match.team then
                        for _, member in ipairs(match.team) do
                            local ic = member.icon or match.specIcon
                            if ic then teamStr = teamStr .. string.format("|T%s:18:18:0:0|t ", ic) end
                        end
                    elseif match.specIcon then
                        teamStr = string.format("|T%s:18:18:0:0|t", match.specIcon)
                    end
                    GameTooltip:AddDoubleLine("|cff888899Your Team:|r", teamStr)

                    local enemyStr = ""
                    for _, member in ipairs(match.enemyTeam) do
                        local ic = member.icon or (member.spec and ns.GetSpecIcon and ns.GetSpecIcon(member.spec, member.class))
                        if ic then enemyStr = enemyStr .. string.format("|T%s:18:18:0:0|t ", ic) end
                    end
                    GameTooltip:AddDoubleLine("|cff888899Enemy Team:|r", enemyStr)
                elseif match.roundsWon ~= nil then
                    local rLost = (match.roundsPlayed or 6) - match.roundsWon
                    local scColor = match.roundsWon >= 4 and "22c55e" or (match.roundsWon == 3 and "ffd100" or "ef4444")
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("|cff888899Final Score:|r", string.format("|cff%s%d - %d|r", scColor, match.roundsWon, rLost))
                    GameTooltip:AddDoubleLine("|cff888899Rounds Won:|r", string.format("|cff%s%d of %d|r", scColor, match.roundsWon, match.roundsPlayed or 6))
                end

                GameTooltip:AddLine(" ")
                local tStr = date("%m/%d/%y %H:%M", match.timestamp or time())
                local dStr = (match.duration and match.duration > 0) and FormatDuration(match.duration) or "—"
                local qStr = (match.queueDuration and match.queueDuration > 0) and FormatDuration(match.queueDuration) or "—"
                local mapStr = match.map or match.mapName or "Arena"

                GameTooltip:AddDoubleLine(string.format("|cff888899Date:|r %s", tStr), string.format("|cff888899Duration:|r %s", dStr))
                GameTooltip:AddDoubleLine(string.format("|cff888899Map:|r |cffffffff%s|r", mapStr), string.format("|cff888899Queue:|r |cffffd100%s|r", qStr))

                GameTooltip:AddLine(" ")
                local rBefore = match.ratingBefore
                local rAfter = match.ratingAfter or match.rating
                local chg = match.ratingChange or 0
                local goldArrow = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:9:9:0:0:32:32:0:32:0:32:255:209:0|t"
                if rBefore and rAfter then
                    local chgColor = chg > 0 and "22c55e" or (chg < 0 and "ef4444" or "888888")
                    local sign = chg > 0 and "+" or ""
                    GameTooltip:AddDoubleLine(
                        "|cff888899Rating:|r",
                        string.format("%d %s %d |cff%s(%s%d)|r", rBefore, goldArrow, rAfter, chgColor, sign, chg)
                    )
                elseif rAfter then
                    GameTooltip:AddDoubleLine("|cff888899Rating:|r", tostring(rAfter))
                end

                local mVal = match.mmrAfter or match.mmr or match.mmrBefore
                local enemyMMRVal = match.enemyMMR
                if mVal or enemyMMRVal then
                    local mmrStr = mVal and string.format("|cff38bdf8%d|r", mVal) or "—"
                    local enemyStr = enemyMMRVal and string.format("|cffff8888%d|r", enemyMMRVal) or "—"
                    GameTooltip:AddDoubleLine(
                        string.format("|cff888899Player MMR:|r %s", mmrStr),
                        string.format("|cff888899Enemy MMR:|r %s", enemyStr)
                    )
                end

                GameTooltip:AddLine(" ")
                if selectedMatches[match] then
                    GameTooltip:AddLine("|cffffd100[Selected]|r |cff888899Click to deselect|r")
                else
                    GameTooltip:AddLine("|cff888899Click match to select|r")
                end

                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if selectedMatches[self.matchData] then
                    self:SetBackdropColor(0.20, 0.18, 0.32, 0.95)
                    self:SetBackdropBorderColor(0.95, 0.78, 0.20, 1.0)
                else
                    local bgAlpha = (self.rowIndex % 2 == 0) and 0.5 or 0.25
                    self:SetBackdropColor(0.09, 0.09, 0.12, bgAlpha)
                    self:SetBackdropBorderColor(0.14, 0.14, 0.18, 0.6)
                end
                GameTooltip:Hide()
            end)

            row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.dateText:SetPoint("LEFT", 10, 0)
            row.dateText:SetWidth(68)
            row.dateText:SetJustifyH("LEFT")

            row.outcomeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.outcomeText:SetPoint("LEFT", row.dateText, "RIGHT", 4, 0)
            row.outcomeText:SetWidth(58)
            row.outcomeText:SetJustifyH("CENTER")

            row.bracketText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.bracketText:SetPoint("LEFT", row.outcomeText, "RIGHT", 4, 0)
            row.bracketText:SetWidth(78)
            row.bracketText:SetJustifyH("LEFT")

            row.teamText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.teamText:SetPoint("LEFT", row.bracketText, "RIGHT", 4, 0)
            row.teamText:SetWidth(45)
            row.teamText:SetJustifyH("CENTER")

            row.enemyTeamText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.enemyTeamText:SetPoint("LEFT", row.teamText, "RIGHT", 4, 0)
            row.enemyTeamText:SetWidth(115)
            row.enemyTeamText:SetJustifyH("CENTER")

            row.ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.ratingText:SetPoint("LEFT", row.enemyTeamText, "RIGHT", 4, 0)
            row.ratingText:SetWidth(115)
            row.ratingText:SetJustifyH("LEFT")

            row.mmrText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.mmrText:SetPoint("LEFT", row.ratingText, "RIGHT", 4, 0)
            row.mmrText:SetWidth(50)
            row.mmrText:SetJustifyH("CENTER")

            row.enemyMMRText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.enemyMMRText:SetPoint("LEFT", row.mmrText, "RIGHT", 4, 0)
            row.enemyMMRText:SetWidth(70)
            row.enemyMMRText:SetJustifyH("CENTER")

            row.mapText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.mapText:SetPoint("LEFT", row.enemyMMRText, "RIGHT", 4, 0)
            row.mapText:SetWidth(115)
            row.mapText:SetJustifyH("LEFT")

            row.durationText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.durationText:SetPoint("LEFT", row.mapText, "RIGHT", 4, 0)
            row.durationText:SetWidth(65)
            row.durationText:SetJustifyH("CENTER")

            row.queueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.textFields = {
                row.dateText,
                row.outcomeText,
                row.bracketText,
                row.teamText,
                row.enemyTeamText,
                row.ratingText,
                row.mmrText,
                row.enemyMMRText,
                row.mapText,
                row.durationText,
                row.queueText,
            }
            row.queueText:SetPoint("LEFT", row.durationText, "RIGHT", 4, 0)
            row.queueText:SetWidth(60)
            row.queueText:SetJustifyH("CENTER")

            frame.historyRows[index] = row
        end
        return row
    end

    for i = 1, total do
        local m = filteredMatches[total - i + 1] -- Newest first
        local row = GetOrCreateHistoryRow(i)

        row.rowIndex = i
        row.matchData = m
        PositionHistoryRow(row, cols)
        
        local isSelected = (selectedMatches[m] == true)
        if isSelected then
            row:SetBackdropColor(0.20, 0.18, 0.32, 0.95)
            row:SetBackdropBorderColor(0.95, 0.78, 0.20, 1.0)
        else
            local bgAlpha = (i % 2 == 0) and 0.5 or 0.25
            row:SetBackdropColor(0.09, 0.09, 0.12, bgAlpha)
            row:SetBackdropBorderColor(0.14, 0.14, 0.18, 0.6)
        end
        row:SetPoint("TOPLEFT", 2, rowY)

        local t = m.timestamp or time()
        row.dateText:SetText("|cff888899" .. date("%m/%d %H:%M", t) .. "|r")

        -- Outcome
        if m.roundsWon ~= nil then
            local rLost = (m.roundsPlayed or 6) - m.roundsWon
            if m.roundsWon >= 4 then
                row.outcomeText:SetText(string.format("|cff22c55e%d-%d W|r", m.roundsWon, rLost))
            elseif m.roundsWon == 3 then
                row.outcomeText:SetText("|cffffd1003-3 D|r")
            else
                row.outcomeText:SetText(string.format("|cffef4444%d-%d L|r", m.roundsWon, rLost))
            end
        elseif m.won == true or (m.ratingChange and m.ratingChange > 0) then
            row.outcomeText:SetText("|cff22c55eWIN|r")
        elseif m.won == false or (m.ratingChange and m.ratingChange < 0) then
            row.outcomeText:SetText("|cffef4444LOSS|r")
        else
            row.outcomeText:SetText("|cffffd100DRAW|r")
        end

        local bracketName = GetMatchBracket(m)
        row.bracketText:SetText("|cffffffff" .. bracketName .. "|r")

        -- Team spec icon(s)
        local teamDisplay = ""
        if m.team and #m.team > 0 then
            for _, member in ipairs(m.team) do
                local ic = member.icon or m.specIcon
                if ic then
                    teamDisplay = teamDisplay .. string.format("|T%s:22:22:0:0|t ", ic)
                end
            end
        elseif m.specIcon then
            teamDisplay = string.format("|T%s:22:22:0:0|t", m.specIcon)
        else
            teamDisplay = "|cff555566---|r"
        end
        row.teamText:SetText(teamDisplay)

        -- Enemy Team spec icon(s)
        local enemyDisplay = ""
        if m.enemyTeam and #m.enemyTeam > 0 then
            for _, member in ipairs(m.enemyTeam) do
                local ic = member.icon or (member.spec and ns.GetSpecIcon and ns.GetSpecIcon(member.spec, member.class))
                if ic then
                    enemyDisplay = enemyDisplay .. string.format("|T%s:22:22:0:0|t ", ic)
                end
            end
        else
            enemyDisplay = "|cff555566---|r"
        end
        row.enemyTeamText:SetText(enemyDisplay)

        -- Rating & Delta column (matching ArenaAnalytics format: "1536 (+31)", "1531 (-5)", "1434")
        local rVal = m.ratingAfter or m.rating
        local chg = m.ratingChange
        if (not chg or chg == 0) and m.ratingBefore and m.ratingAfter and m.ratingBefore ~= m.ratingAfter then
            chg = m.ratingAfter - m.ratingBefore
        end

        local rText = "---"
        if rVal and rVal > 0 then
            if chg and chg > 0 then
                rText = string.format("%d |cff22c55e(+%d)|r", rVal, chg)
            elseif chg and chg < 0 then
                rText = string.format("%d |cffef4444(%d)|r", rVal, chg)
            else
                rText = tostring(rVal)
            end
        elseif chg and chg ~= 0 then
            if chg > 0 then
                rText = string.format("|cff22c55e(+%d)|r", chg)
            else
                rText = string.format("|cffef4444(%d)|r", chg)
            end
        elseif m.ratingBefore then
            rText = tostring(m.ratingBefore)
        end
        row.ratingText:SetText(rText)

        -- MMR
        local mmrVal = m.mmrAfter or m.mmr or m.mmrBefore
        if mmrVal and mmrVal > 0 then
            row.mmrText:SetText(string.format("|cff38bdf8%d|r", mmrVal))
        else
            row.mmrText:SetText("|cff555566---|r")
        end

        -- Enemy MMR
        local eMMR = m.enemyMMR
        if eMMR and eMMR > 0 then
            row.enemyMMRText:SetText(string.format("|cffff8888%d|r", eMMR))
        else
            row.enemyMMRText:SetText("|cff555566---|r")
        end

        -- Map
        local mapName = m.map or m.mapName or "Arena"
        row.mapText:SetText("|cffffffff" .. mapName .. "|r")

        -- Duration
        local dur = (m.duration and m.duration > 0) and FormatDuration(m.duration) or "|cff555566---|r"
        row.durationText:SetText(dur)

        -- Queue Duration
        local qDur = (m.queueDuration and m.queueDuration > 0) and FormatDuration(m.queueDuration) or "|cff555566---|r"
        row.queueText:SetText("|cffffd100" .. qDur .. "|r")

        row:Show()
        rowY = rowY - (ROW_HEIGHT + 2)
    end

    frame.content:SetHeight(math.abs(rowY) + 20)
end

-- Renders the AlterArena Settings Page
local function RenderSettingsView(frame)
    if frame.rosterHeader then frame.rosterHeader:Hide() end
    if frame.historyHeader then frame.historyHeader:Hide() end
    if frame.filterBar then frame.filterBar:Hide() end
    if frame.historyFooter then frame.historyFooter:Hide() end
    if frame.emptyHistoryMsg then frame.emptyHistoryMsg:Hide() end
    if frame.sortBar then frame.sortBar:Hide() end
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -32, 14)

    SetTabActive(frame.tabRoster, false)
    SetTabActive(frame.tabHistory, false)
    UpdateSettingsButtonState(frame)

    local panel = frame.settingsPanel
    if not panel then
        panel = CreateFrame("Frame", nil, frame.content)
        panel:SetSize(FRAME_WIDTH - 52, 530)
        panel:SetPoint("TOPLEFT", 2, 0)
        frame.settingsPanel = panel

        -- Header Banner Card
        local banner = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        banner:SetSize(FRAME_WIDTH - 52, 54)
        banner:SetPoint("TOPLEFT", 0, 0)
        banner:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        banner:SetBackdropColor(0.10, 0.10, 0.13, 0.95)
        banner:SetBackdropBorderColor(0.18, 0.19, 0.23, 0.9)

        local bTitle = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
        bTitle:SetPoint("TOPLEFT", 14, -10)
        bTitle:SetText("|cffffd100AlterArena Settings & Addon Modules|r")

        local bSub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bSub:SetPoint("TOPLEFT", 14, -30)
        bSub:SetText("|cff888899Configure floating HUD modules, debug diagnostic logging, and database preferences.|r")

        -- Module Card: Queue Timer
        local qCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        qCard:SetSize(FRAME_WIDTH - 52, 180)
        qCard:SetPoint("TOPLEFT", 0, -66)
        qCard:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        qCard:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        qCard:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)
        panel.qCard = qCard

        local qTitle = qCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        qTitle:SetPoint("TOPLEFT", 16, -14)
        qTitle:SetText("|cffffd100PvP Queue Timer Floating HUD|r")

        -- Styled Checkbox
        local cb = CreateFrame("Button", nil, qCard, "BackdropTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 16, -42)
        cb:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        cb:SetBackdropColor(0.13, 0.14, 0.18, 0.95)
        cb:SetBackdropBorderColor(0.30, 0.32, 0.40, 0.95)

        local checkTex = cb:CreateTexture(nil, "OVERLAY")
        checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkTex:SetSize(22, 22)
        checkTex:SetPoint("CENTER", 1, 0)
        cb.checkTex = checkTex

        local cbLabel = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cbLabel:SetPoint("LEFT", cb, "RIGHT", 10, 0)
        cbLabel:SetText("Enable Queue Timer Floating HUD")
        cb.label = cbLabel

        local cbDesc = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbDesc:SetPoint("TOPLEFT", 46, -68)
        cbDesc:SetWidth(FRAME_WIDTH - 120)
        cbDesc:SetJustifyH("LEFT")
        cbDesc:SetText("|cff888899Displays a sleek, draggable floating HUD widget whenever you are queued for Arenas, Solo Shuffle, or Battlegrounds. Shows wait time, estimated duration, and your recent rating/MMR delta.|r")

        local statusText = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("TOPLEFT", 46, -102)
        panel.statusText = statusText

        cb:SetScript("OnClick", function(self)
            local current = ns.IsQueueTimerEnabled and ns.IsQueueTimerEnabled()
            local newState = not current
            if ns.SetQueueTimerEnabled then
                ns.SetQueueTimerEnabled(newState)
            end
            self.checkTex:SetShown(newState)
            panel.UpdateStatus()
        end)
        panel.timerCheckbox = cb

        -- Action Buttons for Queue Timer
        local testBtn = CreateStyledButton(qCard, "Test Timer (Preview)", 150, 26)
        testBtn:SetPoint("TOPLEFT", 46, -132)
        panel.testBtn = testBtn
        testBtn:SetScript("OnClick", function()
            if ns.ToggleTestQueueTimer then
                ns.ToggleTestQueueTimer()
            end
            if panel and panel.UpdateStatus then
                panel.UpdateStatus()
            end
        end)

        local resetPosBtn = CreateStyledButton(qCard, "Reset HUD Position", 150, 26)
        resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
        resetPosBtn:SetScript("OnClick", function()
            if ns.ResetQueueTimerPosition then
                ns.ResetQueueTimerPosition()
            end
            if ns.IsTestQueueTimerActive and not ns.IsTestQueueTimerActive() and ns.ToggleTestQueueTimer then
                ns.ToggleTestQueueTimer()
            end
            if panel and panel.UpdateStatus then
                panel.UpdateStatus()
            end
        end)

        -- Module Card: Debug Mode
        local dCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        dCard:SetSize(FRAME_WIDTH - 52, 130)
        dCard:SetPoint("TOPLEFT", 0, -258)
        dCard:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        dCard:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        dCard:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)
        panel.dCard = dCard

        local dTitle = dCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dTitle:SetPoint("TOPLEFT", 16, -14)
        dTitle:SetText("|cffffd100Developer & Diagnostic Debug Mode|r")

        -- Debug Styled Checkbox
        local dcb = CreateFrame("Button", nil, dCard, "BackdropTemplate")
        dcb:SetSize(20, 20)
        dcb:SetPoint("TOPLEFT", 16, -42)
        dcb:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        dcb:SetBackdropColor(0.13, 0.14, 0.18, 0.95)
        dcb:SetBackdropBorderColor(0.30, 0.32, 0.40, 0.95)

        local dCheckTex = dcb:CreateTexture(nil, "OVERLAY")
        dCheckTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        dCheckTex:SetSize(22, 22)
        dCheckTex:SetPoint("CENTER", 1, 0)
        dcb.checkTex = dCheckTex

        local dcbLabel = dcb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dcbLabel:SetPoint("LEFT", dcb, "RIGHT", 10, 0)
        dcbLabel:SetText("Enable Verbose [AA-DEBUG] Chat Logging")
        dcb.label = dcbLabel

        local dcbDesc = dCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dcbDesc:SetPoint("TOPLEFT", 46, -68)
        dcbDesc:SetWidth(FRAME_WIDTH - 240)
        dcbDesc:SetJustifyH("LEFT")
        dcbDesc:SetText("|cff888899Outputs real-time diagnostic prints to the default chat window for match recovery, rating snapshot diffs, scoreboard processing, and queue state changes.|r")

        local dStatusText = dCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dStatusText:SetPoint("TOPLEFT", 46, -100)
        panel.debugStatusText = dStatusText

        local function ToggleDebugMode()
            AlterArenaDB = AlterArenaDB or {}
            AlterArenaDB.settings = AlterArenaDB.settings or {}
            AlterArenaDB.settings.debugMode = not AlterArenaDB.settings.debugMode
            panel.UpdateStatus()
            local statusStr = AlterArenaDB.settings.debugMode and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
            print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.", statusStr))
        end

        dcb:SetScript("OnClick", ToggleDebugMode)
        panel.debugCheckbox = dcb

        local toggleDebugBtn = CreateStyledButton(dCard, "Toggle Debug Mode", 150, 26)
        toggleDebugBtn:SetPoint("TOPRIGHT", -16, -39)
        toggleDebugBtn:SetScript("OnClick", ToggleDebugMode)
        panel.toggleDebugBtn = toggleDebugBtn

                -- Module Card: Currency Alerts
        local aCard = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        aCard:SetSize(FRAME_WIDTH - 52, 300)
        aCard:SetPoint("TOPLEFT", 0, -516)
        aCard:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        aCard:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
        aCard:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)

        local aTitle = aCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        aTitle:SetPoint("TOPLEFT", 16, -14)
        aTitle:SetText("|cffffd100Currency Cap Alerts|r")

        local aDesc = aCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        aDesc:SetPoint("TOPLEFT", 16, -36)
        aDesc:SetWidth(FRAME_WIDTH - 84)
        aDesc:SetJustifyH("LEFT")
        aDesc:SetText("|cff888899Fires a movable toast when a wallet currency crosses its warning threshold. Useful for Honor and Bloody Tokens, which have fixed caps you can waste.|r")

        -- Per-currency rows
        local currencyMeta = {
            { key = "honor",    label = "Honor",         cap = 15000 },
            { key = "tokens",   label = "Bloody Tokens", cap = 50000 },
            { key = "conquest", label = "Conquest",      cap = 0     },
        }

        local prevY = -74
        panel.currencyToggles = {}

        for _, meta in ipairs(currencyMeta) do
            local row = CreateFrame("Button", nil, aCard, "BackdropTemplate")
            row:SetSize(FRAME_WIDTH - 84, 22)
            row:SetPoint("TOPLEFT", 16, prevY)
            row:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            row:SetBackdropColor(0.13, 0.14, 0.18, 0.95)
            row:SetBackdropBorderColor(0.30, 0.32, 0.40, 0.95)

            local chk = row:CreateTexture(nil, "OVERLAY")
            chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            chk:SetSize(20, 20)
            chk:SetPoint("LEFT", 1, 0)
            row.chk = chk

            local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", row, "LEFT", 28, 0)
            lbl:SetText(meta.label)
            row.lbl = lbl

            local val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            val:SetPoint("RIGHT", -10, 0)
            val:SetJustifyH("RIGHT")
            row.val = val

            local key = meta.key
            row:SetScript("OnClick", function()
                local cfg = ns.GetCurrencyAlertConfig()
                local per = cfg.perCurrency[key]
                per.enabled = not per.enabled
                panel.UpdateStatus()
            end)

            panel.currencyToggles[key] = { row = row, meta = meta }
            prevY = prevY - 26
        end

        -- Sound picker
        local soundBtn = CreateStyledButton(aCard, "Sound: --", 180, 24)
        soundBtn:SetPoint("TOPLEFT", 16, prevY - 6)
        soundBtn:SetScript("OnClick", function(self)
            local cfg = ns.GetCurrencyAlertConfig()
            local items = {}
            for _, s in ipairs(ns.SOUND_OPTIONS) do
                local sid = s.id
                table.insert(items, {
                    type  = "radio",
                    label = s.label,
                    checked = function() return cfg.sound == sid end,
                    onClick = function() cfg.sound = sid; panel.UpdateStatus() end,
                })
            end
            ns.OpenDropdown(self, items)
        end)
        panel.soundBtn = soundBtn

        -- Test + Reset Position
        local testBtn = CreateStyledButton(aCard, "Test Alert", 130, 24)
        testBtn:SetPoint("LEFT", soundBtn, "RIGHT", 8, 0)
        testBtn:SetScript("OnClick", function() ns.TestCurrencyAlert() end)

        local resetAlertBtn = CreateStyledButton(aCard, "Reset Alert Position", 170, 24)
        resetAlertBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)
        resetAlertBtn:SetScript("OnClick", function() ns.ResetCurrencyAlertPosition() end)




        panel.UpdateStatus = function()
            local isEnabled = ns.IsQueueTimerEnabled and ns.IsQueueTimerEnabled()
            panel.timerCheckbox.checkTex:SetShown(isEnabled)
            if isEnabled then
                panel.statusText:SetText("|cff888899Module Status:|r  |cff22c55e[ACTIVE] Overlay will show automatically in queue|r")
            else
                panel.statusText:SetText("|cff888899Module Status:|r  |cffef4444[DISABLED] Overlay will not appear while in queue|r")
            end

            if panel.currencyAlertCheckbox and panel.currencyAlertCheckbox.checkTex then
                local disabled = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.disableCurrencyAlerts
                panel.currencyAlertCheckbox.checkTex:SetShown(not disabled)
            end

            local isDebug = AlterArenaDB and AlterArenaDB.settings and (AlterArenaDB.settings.debugMode == true)
            if panel.debugCheckbox and panel.debugCheckbox.checkTex then
                panel.debugCheckbox.checkTex:SetShown(isDebug)
            end
            if panel.debugStatusText then
                if isDebug then
                    panel.debugStatusText:SetText("|cff888899Debug Status:|r  |cff22c55e[ACTIVE] Detailed [AA-DEBUG] messages printed to chat|r")
                else
                    panel.debugStatusText:SetText("|cff888899Debug Status:|r  |cff888899[OFF] Verbose logging is turned off (normal operation)|r")
                end
            end

            if panel.testBtn then
                local isTesting = ns.IsTestQueueTimerActive and ns.IsTestQueueTimerActive()
                if isTesting then
                    panel.testBtn:SetText("|cffff4444Hide Test Timer|r")
                else
                    panel.testBtn:SetText("Test Timer (Preview)")
                end
            end

            -- Currency alert toggles
            if panel.currencyToggles then
                local cfg = ns.GetCurrencyAlertConfig()
                for key, entry in pairs(panel.currencyToggles) do
                    local per = cfg.perCurrency[key]
                    if per then
                        entry.row.chk:SetShown(per.enabled)
                        if per.threshold > 0 then
                            entry.row.val:SetText(string.format("|cff888899alert at %d|r", per.threshold))
                        else
                            entry.row.val:SetText("|cff888899no fixed cap|r")
                        end
                    end
                end
            end
            if panel.soundBtn then
                local cfg = ns.GetCurrencyAlertConfig()
                for _, s in ipairs(ns.SOUND_OPTIONS) do
                    if s.id == cfg.sound then
                        panel.soundBtn.text:SetText("Sound: " .. s.label)
                        break
                    end
                end
            end

            -- Update database stats
            local totalChars = 0
            local totalMatches = 0
            if AlterArenaDB and AlterArenaDB.players then
                for _, p in pairs(AlterArenaDB.players) do
                    totalChars = totalChars + 1
                    if p.matches then
                        totalMatches = totalMatches + #p.matches
                    end
                end
            end
            panel.infoDesc:SetText(string.format(
                "|cff888899Currently tracking:|r |cffffffff%d character(s)|r with |cffffd100%d match(es)|r recorded.\n|cff888899All match records and alt progression are stored locally in your WTF SavedVariables.|r\n|cff888899Slash command shortcuts:|r |cffffd100/aa debug|r  |  |cffffd100/aa timer on|r  |  |cffffd100/aa timer off|r  |  |cffffd100/aa test|r",
                totalChars, totalMatches
            ))
        end

        ns.UpdateSettingsUI = function()
            if panel and panel.UpdateStatus then
                panel.UpdateStatus()
            end
        end
    end

    panel.UpdateStatus()
    panel:Show()
    frame.content:SetHeight(620)
end

function ns.RefreshUI()
    if not mainFrame then return end
    ClearAllRows(mainFrame)

    if activeTab == "roster" then
        if mainFrame.historyHeader then mainFrame.historyHeader:Hide() end
        RenderRosterView(mainFrame)
    elseif activeTab == "settings" then
        if mainFrame.historyHeader then mainFrame.historyHeader:Hide() end
        RenderSettingsView(mainFrame)
    else
        RenderHistoryView(mainFrame)
    end
end

function ns.OpenSettings()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end
    activeTab = "settings"
    mainFrame:Show()
    ns.RefreshUI()
end

function ns.ToggleUI()
    if not mainFrame then
        mainFrame = CreateMainFrame()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        ns.RefreshUI()
    end
end
