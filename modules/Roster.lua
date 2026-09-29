-- =========================================================================
-- Roster.lua — Roster Overview tab
-- =========================================================================

local ADDON_NAME, ns = ...
local ui = ns.ui

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

local SORT_OPTIONS = {
    { id = "name",    label = "Name" },
    { id = "rating",  label = "Highest Rating" },
    { id = "recent",  label = "Recent" },
    { id = "winrate", label = "Win Rate" },
}

local SORT_LABELS = {}
for _, opt in ipairs(SORT_OPTIONS) do
    SORT_LABELS[opt.id] = opt.label
end

function ns.GetRosterSortLabel()
    local mode = ui.rosterSortMode or "name"
    return SORT_LABELS[mode] or "Name"
end




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

function ns.OpenRosterSortDropdown(anchor)
    local items = {}
    for _, opt in ipairs(SORT_OPTIONS) do
        local id = opt.id
        table.insert(items, {
            type  = "radio",
            label = opt.label,
            checked = function() return (ui.rosterSortMode or "name") == id end,
            onClick = function()
                ui.rosterSortMode = id
                if ns.RefreshUI then ns.RefreshUI() end
            end,
        })
    end
    if ns.OpenDropdown then
        ns.OpenDropdown(anchor, items)
    end
end

function ns.OpenColumnsDropdown(anchor)
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
                    if ns.RefreshUI then ns.RefreshUI() end
                end,
            })
        end
    end
    if ns.OpenDropdown then
        ns.OpenDropdown(anchor, items)
    end
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

    sortMode = sortMode or ui.rosterSortMode or "name"
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


-- Renders the roster overview
function ns.RenderRosterView(frame)
    frame.filterBar:Hide()
    if frame.columnsBtn then frame.columnsBtn:Show() end
    if frame.sortBtn then
        frame.sortBtn:Show()
        local label = ns.GetRosterSortLabel and ns.GetRosterSortLabel() or "Name"
        frame.sortBtn:SetText("Sort: " .. label)
    end
    if frame.historyFooter then frame.historyFooter:Hide() end
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", -18, 14)
    ui.selectedMatch = nil
    
    ns.SetTabActive(frame.tabRoster, true)
    ns.SetTabActive(frame.tabHistory, false)
    ns.UpdateSettingsButtonState(frame)
    
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
    local cardWidth = (ui.FRAME_WIDTH - 64) / 4
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

    -- Sort lives in the nav bar dropdown (frame.sortBtn), not inline.
    -- Small gap under the stat cards before the table header.
    statY = statY - 54

    -- Table Columns Header ( dynamic based on visible columns)
    local header = frame.rosterHeader

    if not header then
        header = CreateFrame("Frame", nil, frame.content, "BackdropTemplate")
        header:SetSize(ui.FRAME_WIDTH - 52, 22)
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
    local clampedFrameWidth = math.max(ui.FRAME_WIDTH, math.min(frameWidth, 1400))

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
            row:SetSize(frame.rosterContentWidth or (ui.FRAME_WIDTH - 52), ui.ROW_HEIGHT)
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

                local charColor = ns.GetClassColor(pRec.class)
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
                    local col = ns.GetRatingColor(bestRating)
                    local tier = ns.GetPvPTierName(bestRating) or "Unranked"
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
                        local col = ns.GetRatingColor(curRating)
                        local tier = ns.GetPvPTierName(curRating) or "—"
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
                        local col, rStr = ns.GetRatingColor(sData.rating or 0)
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
        local col, valStr = ns.GetRatingColor(rVal)
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

        local charColor = ns.GetClassColor(rec.class)
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
        if rec.bracketRatings then
            for _, bData in pairs(rec.bracketRatings) do
                if bData.current and bData.current > bestRating then
                    bestRating = bData.current
                end
            end
        end

        if bestRating > 0 then
            local col = ns.GetRatingColor(bestRating)
            local tier = ns.GetPvPTierName(bestRating)
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
        rowY = rowY - (ui.ROW_HEIGHT + 2)

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
                    rowY = rowY - (ui.ROW_HEIGHT + 2)
                end
            end
        end
    end

    frame.content:SetHeight(math.abs(rowY) + 20)
    if frame.scrollFrame and frame.scrollFrame.UpdateThumb then
        frame.scrollFrame:UpdateThumb()
    end
end