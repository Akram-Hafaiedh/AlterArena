-- =========================================================================
-- History.lua — Match History tab
-- =========================================================================

local ADDON_NAME, ns = ...
local ui = ns.ui


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



-- ui.BRACKET_LABELS lives on ns.ui

-- ui.RESULT_LABELS lives on ns.ui

-- ui.DATE_LABELS lives on ns.ui

-- ui.SEASON_LABELS lives on ns.ui

-- ui.DATE_CUTOFFS lives on ns.ui


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


local function UpdateMoreFiltersButton(frame)
    if not frame or not frame.moreFiltersBtn then return end
    local count = 0
    if ui.historyFilters.result ~= "ALL" then count = count + 1 end
    if ui.historyFilters.date   ~= "ALL" then count = count + 1 end
    if ui.historyFilters.map    ~= "ALL" then count = count + 1 end
    if ui.historyFilters.season ~= "ALL" then count = count + 1 end
    
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
            label = ui.RESULT_LABELS[rid],
            checked = function() return ui.historyFilters.result == rid end,
            onClick = function() ui.historyFilters.result = rid; ns.RefreshUI() end,
        })
    end

    -- Date submenu
    local dateSub = {}
    for _, id in ipairs({ "ALL", "TODAY", "THISWEEK", "THISMONTH", "LAST3MONTHS", "LAST6MONTHS" }) do
        local did = id
        table.insert(dateSub, {
            type  = "radio",
            label = ui.DATE_LABELS[did],
            checked = function() return ui.historyFilters.date == did end,
            onClick = function() ui.historyFilters.date = did; ns.RefreshUI() end,
        })
    end

    -- Season submenu
    local seasonSub = {}
    for _, id in ipairs({ "ALL", "CURRENT", "LAST" }) do
        local sid = id
        table.insert(seasonSub, {
            type  = "radio",
            label = ui.SEASON_LABELS[sid],
            checked = function() return ui.historyFilters.season == sid end,
            onClick = function() ui.historyFilters.season = sid; ns.RefreshUI() end,
        })
    end

    -- Arena maps submenu
    local arenaItems = {}
    for _, mp in ipairs(KNOWN_ARENA_MAPS) do
        local mpm = mp
        table.insert(arenaItems, {
            type  = "radio",
            label = mpm,
            checked = function() return ui.historyFilters.map == mpm end,
            onClick = function() ui.historyFilters.map = mpm; ns.RefreshUI() end,
        })
    end

    -- BG maps submenu
    local bgItems = {}
    for _, mp in ipairs(KNOWN_BG_MAPS) do
        local mpm = mp
        table.insert(bgItems, {
            type  = "radio",
            label = mpm,
            checked = function() return ui.historyFilters.map == mpm end,
            onClick = function() ui.historyFilters.map = mpm; ns.RefreshUI() end,
        })
    end

    -- "Other" submenu — maps discovered from history
    local otherItems = {}
    do
        local effectiveKey = ui.selectedCharKey or (ns.GetPlayerKey and ns.GetPlayerKey())
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
                checked = function() return ui.historyFilters.map == mpm end,
                onClick = function() ui.historyFilters.map = mpm; ns.RefreshUI() end,
            })
        end
    end

    -- Map submenu tree
    local mapSub = {
        {
            type  = "radio",
            label = "All Maps",
            checked = function() return ui.historyFilters.map == "ALL" end,
            onClick = function() ui.historyFilters.map = "ALL"; ns.RefreshUI() end,
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
    local mapLabel = (ui.historyFilters.map == "ALL") and "Map: All" or ("Map: " .. ui.historyFilters.map)
    local items = {
        {
            type  = "radio",
            label = "Result: " .. ui.RESULT_LABELS[ui.historyFilters.result],
            submenu = resultSub,
            checked = function() return ui.historyFilters.result ~= "ALL" end,
        },
        {
            type  = "radio",
            label = "Date: " .. ui.DATE_LABELS[ui.historyFilters.date],
            submenu = dateSub,
            checked = function() return ui.historyFilters.date ~= "ALL" end,
        },
        {
            type  = "radio",
            label = "Season: " .. ui.SEASON_LABELS[ui.historyFilters.season],
            submenu = seasonSub,
            checked = function() return ui.historyFilters.season ~= "ALL" end,
        },
        {
            type  = "radio",
            label = mapLabel,
            submenu = mapSub,
            checked = function() return ui.historyFilters.map ~= "ALL" end,
        },
        { type = "divider" },
        {
            type  = "button",
            label = "Reset all filters",
            onClick = function()
                ui.historyFilters.bracket = "ALL"
                ui.historyFilters.result  = "ALL"
                ui.historyFilters.map     = "ALL"
                ui.historyFilters.date    = "ALL"
                ui.historyFilters.season  = "ALL"
                ns.RefreshUI()
            end,
        },
    }

    ns.OpenDropdown(anchor, items)
end

-- Create AlterEgo dark main window

-- Renders the AlterEgo-style Detailed Match History Ledger
function ns.RenderHistoryView(frame)
    if frame.rosterHeader then frame.rosterHeader:Hide() end
    if frame.sortBar then frame.sortBar:Hide() end
    frame.filterBar:Show()
    if frame.columnsBtn then frame.columnsBtn:Hide() end
    ns.SetTabActive(frame.tabRoster, false)
    ns.SetTabActive(frame.tabHistory, true)
    ns.UpdateSettingsButtonState(frame)


    -- Update Character button label
    if frame.charBtn then
        local effectiveKey = ui.selectedCharKey or ns.GetPlayerKey()
        local rec = AlterArenaDB.players[effectiveKey]
        local name = (rec and rec.name) or effectiveKey or "Character"
        local c = ns.GetClassColor(rec and rec.class)
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
        local current = ui.BRACKET_LABELS[ui.historyFilters.bracket] or "Bracket"
        local active = (ui.historyFilters.bracket ~= "ALL")
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
        local anyActive = (ui.historyFilters.bracket ~= "ALL")
                       or (ui.historyFilters.result  ~= "ALL")
                       or (ui.historyFilters.map     ~= "ALL")
                       or (ui.historyFilters.season  ~= "ALL")
                       or (ui.historyFilters.date    ~= "ALL")
        if anyActive then
            frame.clearFiltersBtn:Show()
        else
            frame.clearFiltersBtn:Hide()
        end
    end

    UpdateMoreFiltersButton(frame)

    ui.selectedCharKey = ui.selectedCharKey or ns.GetPlayerKey()
    local rec = AlterArenaDB.players[ui.selectedCharKey]
    local allMatches = (rec and rec.matches) or {}

    -- Filter matches
    local filteredMatches = {}
    for _, m in ipairs(allMatches) do
        local pass = true
        local b = ns.GetMatchBracket(m)

        --Bracket
        if ui.historyFilters.bracket ~= "ALL" then
            if ui.historyFilters.bracket == "Shuffle" then
                if not (b == "Shuffle" or b == "Solo Shuffle" or not m.bracket) then
                    pass = false
                end
            elseif ui.historyFilters.bracket == "Blitz" then
                if not (b == "Blitz" or b == "Battleground Blitz") then
                    pass = false
                end
            elseif b ~= ui.historyFilters.bracket then
                pass = false
            end
        end

        -- Result
        if pass and ui.historyFilters.result ~= "ALL" then
            local outcome = ns.GetMatchOutcome(m)
            if ui.historyFilters.result == "WINS"   and outcome ~= "W" then pass = false end
            if ui.historyFilters.result == "LOSSES" and outcome ~= "L" then pass = false end
            if ui.historyFilters.result == "DRAWS"  and outcome ~= "D" then pass = false end
        end

        -- Map
        if pass and ui.historyFilters.map ~= "ALL" then
            local mapName = m.map or m.mapName or ""
            if mapName ~= ui.historyFilters.map then
                pass = false
            end
        end

                -- Date
        if pass and ui.historyFilters.date ~= "ALL" then
            local window = ui.DATE_CUTOFFS[ui.historyFilters.date]
            if window then
                local cutoff = time() - window
                if (m.timestamp or 0) < cutoff then
                    pass = false
                end
            end
        end

        -- Season
        if pass and ui.historyFilters.season ~= "ALL" then
            local currentId = ns.currentSeasonId
            local lastId    = AlterArenaDB.lastSeasonId

            if ui.historyFilters.season == "CURRENT" then
                -- If we don't know the current season, show nothing for this filter
                if not currentId or m.seasonId ~= currentId then
                    pass = false
                end
            elseif ui.historyFilters.season == "LAST" then
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
        { title = "Date", width = 68, gap = 4 },
        { title = "Outcome", width = 58, align = "CENTER", gap = 4 },
        { title = "Bracket", width = 78, gap = 4 },
        { title = "Team", width = 45, align = "CENTER", gap = 4 },
        { title = "Enemy Team", width = 115, align = "CENTER", gap = 4 },
        { title = "Rating & Delta", width = 115, gap = 4 },
        { title = "MMR", width = 50, align = "CENTER", gap = 4 },
        { title = "Enemy MMR", width = 70, align = "CENTER", gap = 4 },
        { title = "Map", width = 115, gap = 4 },
        { title = "Duration", width = 65, align = "CENTER", gap = 4 },
        { title = "Queue", width = 60, align = "CENTER", gap = 4 },
    }

    local header = frame.historyHeader
    if not header then
        header = ns.CreateHeaderRow(frame.content, cols)
        frame.historyHeader = header
    end
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
        local outcome = ns.GetMatchOutcome(m)
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
        if mTime >= ui.sessionStartTime then
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

        if ui.selectedMatches[m] then
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
        local sessDurSeconds = now - ui.sessionStartTime
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
            row:SetSize(ui.FRAME_WIDTH - 52, ui.ROW_HEIGHT)
            row:SetBackdrop({
                bgFile = "Interface/Buttons/WHITE8X8",
                edgeFile = "Interface/Buttons/WHITE8X8",
                edgeSize = 1,
            })
            row:SetScript("OnClick", function(self)
                if self.matchData then
                    if ui.selectedMatches[self.matchData] then
                        ui.selectedMatches[self.matchData] = nil
                    else
                        ui.selectedMatches[self.matchData] = true
                    end
                    ns.RefreshUI()
                end
            end)
            row:SetScript("OnEnter", function(self)
                if not ui.selectedMatches[self.matchData] then
                    self:SetBackdropColor(0.16, 0.18, 0.24, 0.9)
                end
                local match = self.matchData
                if not match then return end

                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()

                local bName = match.bracket or "Solo Shuffle"
                local isShuffle = (bName == "Solo Shuffle" or bName == "Shuffle")

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
                                teamIcons = teamIcons .. string.format("|T%s:16:16:0:0|t ", ic)
                            end
                        end
                        local enemyIcons = ""
                        if rData.enemy then
                            for _, ic in ipairs(rData.enemy) do
                                enemyIcons = enemyIcons .. string.format("|T%s:16:16:0:0|t ", ic)
                            end
                        end

                        local leftSide = string.format("|cff22c55e%d:|r %s|cffffd100vs|r %s", rNum, teamIcons, enemyIcons)

                        local dColor = (rData.won == true and "22c55e") or (rData.won == false and "ef4444") or "ffd100"
                        local durText = ""
                        if rData.duration and rData.duration > 0 then
                            durText = ns.FormatRoundDuration(rData.duration)
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
                            if ic then teamStr = teamStr .. string.format("|T%s:14:14:0:0|t ", ic) end
                        end
                    elseif match.specIcon then
                        teamStr = string.format("|T%s:14:14:0:0|t", match.specIcon)
                    end
                    GameTooltip:AddDoubleLine("|cff888899Your Team:|r", teamStr)

                    local enemyStr = ""
                    for _, member in ipairs(match.enemyTeam) do
                        local ic = member.icon or (member.spec and ns.GetSpecIcon and ns.GetSpecIcon(member.spec, member.class))
                        if ic then enemyStr = enemyStr .. string.format("|T%s:14:14:0:0|t ", ic) end
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
                local dStr = (match.duration and match.duration > 0) and ns.FormatDuration(match.duration) or "—"
                local qStr = (match.queueDuration and match.queueDuration > 0) and ns.FormatDuration(match.queueDuration) or "—"
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
                if ui.selectedMatches[match] then
                    GameTooltip:AddLine("|cffffd100[Selected]|r |cff888899Click to deselect|r")
                else
                    GameTooltip:AddLine("|cff888899Click match to select|r")
                end

                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if ui.selectedMatches[self.matchData] then
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
        
        local isSelected = (ui.selectedMatches[m] == true)
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

        local bracketName = ns.GetMatchBracket(m)
        row.bracketText:SetText("|cffffffff" .. bracketName .. "|r")

        -- Team spec icon(s)
        local teamDisplay = ""
        if m.team and #m.team > 0 then
            for _, member in ipairs(m.team) do
                local ic = member.icon or m.specIcon
                if ic then
                    teamDisplay = teamDisplay .. string.format("|T%s:17:17:0:0|t ", ic)
                end
            end
        elseif m.specIcon then
            teamDisplay = string.format("|T%s:17:17:0:0|t", m.specIcon)
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
                    enemyDisplay = enemyDisplay .. string.format("|T%s:16:16:0:0|t ", ic)
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
        local dur = (m.duration and m.duration > 0) and ns.FormatDuration(m.duration) or "|cff555566---|r"
        row.durationText:SetText(dur)

        -- Queue Duration
        local qDur = (m.queueDuration and m.queueDuration > 0) and ns.FormatDuration(m.queueDuration) or "|cff555566---|r"
        row.queueText:SetText("|cffffd100" .. qDur .. "|r")

        row:Show()
        rowY = rowY - (ui.ROW_HEIGHT + 2)
    end

    frame.content:SetHeight(math.abs(rowY) + 20)
end