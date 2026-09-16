local ADDON_NAME, ns = ...

-- AlterArenaDB layout:
-- AlterArenaDB.players["Name-Realm"] = {
--   name, realm, class, faction,
--   matches = {
--     { timestamp, duration, isRated, won, bracket,
--       ratingBefore, ratingAfter, ratingChange },
--     ...
--   }
-- }

AlterArenaDB = AlterArenaDB or {}

local DEFAULTS = {
    players = {},
    settings = {
        enableQueueTimer = true,
        debugMode = false,
    },
}

local function EnsureDBDefaults()
    for key, value in pairs(DEFAULTS) do
        if AlterArenaDB[key] == nil then
            AlterArenaDB[key] = value
        end
    end
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    if AlterArenaDB.settings.enableQueueTimer == nil then
        AlterArenaDB.settings.enableQueueTimer = true
    end
    if AlterArenaDB.settings.debugMode == nil then
        AlterArenaDB.settings.debugMode = false
    end
end

function ns.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return string.format("%s-%s", name, realm)
end

-- Debug logging, gated behind AlterArenaDB.settings.debugMode
function ns.DebugPrint(...)
    if AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode then
        print("|cff40c0ff[AA-DEBUG]|r", ...)
    end
end

function ns.EnsurePlayerRecord()
    local key = ns.GetPlayerKey()
    local players = AlterArenaDB.players

    if not players[key] then
        local _, class = UnitClass("player")
        local faction = UnitFactionGroup("player")
        players[key] = {
            name = UnitName("player"),
            realm = GetRealmName(),
            class = class,
            faction = faction,
            matches = {},
            bracketRatings = {},
        }
    end

    local rec = players[key]
    rec.bracketRatings = rec.bracketRatings or {}

    -- Keep spec and specIcon updated for current character
    if GetSpecialization and GetSpecializationInfo then
        local specIdx = GetSpecialization()
        if specIdx then
            local _, specName, _, specIcon = GetSpecializationInfo(specIdx)
            rec.spec = specName
            rec.specIcon = specIcon
        end
    end

    return rec
end

function ns.UpdateAllCharacterRatings()
    if not GetPersonalRatedInfo then return end
    local rec = ns.EnsurePlayerRecord()
    rec.specStats = rec.specStats or {}

    -- Bracket index fallbacks for Retail WoW
    local brackets = {
        { name = "Shuffle", fallbacks = { 7, 4, 3 } },
        { name = "Blitz", fallbacks = { 9, 8, 4 } },
        { name = "2v2", idx = 1 },
        { name = "3v3", idx = 2 },
    }

    for _, b in ipairs(brackets) do
        local r = nil
        local sWon, sPlayed, rPlayed, rWon = nil, nil, nil, nil
        if b.fallbacks then
            for _, testIdx in ipairs(b.fallbacks) do
                local rating, _, _, seasonPlayed, seasonWon, _, _, _, _, _, _, roundsSeasonPlayed, roundsSeasonWon = GetPersonalRatedInfo(testIdx)
                if rating and rating > 0 then
                    r = rating
                    sPlayed = seasonPlayed
                    sWon = seasonWon
                    rPlayed = roundsSeasonPlayed
                    rWon = roundsSeasonWon
                    break
                end
            end
        else
            local rating, _, _, seasonPlayed, seasonWon = GetPersonalRatedInfo(b.idx)
            if rating and rating > 0 then
                r = rating
                sPlayed = seasonPlayed
                sWon = seasonWon
            end
        end

        if r and r > 0 then
            local data = rec.bracketRatings[b.name]
            if not data then
                rec.bracketRatings[b.name] = { current = r, previous = nil, change = 0 }
                data = rec.bracketRatings[b.name]
            elseif data.current ~= r then
                data.previous = data.current
                data.current = r
                data.change = r - data.previous
            end

            -- Solo Shuffle uses round-level wins and played
            if b.name == "Shuffle" and rPlayed and rWon then
                data.roundsWon = rWon
                data.roundsPlayed = rPlayed
                data.roundsLost = rPlayed - rWon
                data.winRate = (rPlayed > 0) and (math.floor((rWon / rPlayed) * 1000 + 0.5) / 10) or 0

                -- Store per-spec stats for current active spec
                if rec.spec then
                    rec.specStats[rec.spec] = rec.specStats[rec.spec] or {}
                    local sObj = rec.specStats[rec.spec]
                    sObj.name = rec.spec
                    sObj.icon = rec.specIcon
                    sObj.rating = r
                    sObj.roundsWon = rWon
                    sObj.roundsPlayed = rPlayed
                    sObj.roundsLost = data.roundsLost
                    sObj.winRate = data.winRate
                    if data.mmr then
                        sObj.mmr = data.mmr
                    end
                end
            else
                data.seasonWon = sWon or 0
                data.seasonPlayed = sPlayed or 0
                data.seasonLost = (sPlayed and sWon) and (sPlayed - sWon) or 0
                data.winRate = (sPlayed and sPlayed > 0 and sWon) and (math.floor((sWon / sPlayed) * 1000 + 0.5) / 10) or 0
            end
        end
    end

    -- Look through matches to retain latest MMR if not set
    if rec.matches and #rec.matches > 0 then
        for i = #rec.matches, 1, -1 do
            local m = rec.matches[i]
            if m.mmrAfter and m.mmrAfter > 0 then
                if rec.bracketRatings["Shuffle"] and not rec.bracketRatings["Shuffle"].mmr then
                    rec.bracketRatings["Shuffle"].mmr = m.mmrAfter
                end
                if m.spec and rec.specStats[m.spec] and not rec.specStats[m.spec].mmr then
                    rec.specStats[m.spec].mmr = m.mmrAfter
                end
                break
            end
        end
    end

    -- Optional non-intrusive scan of PVPHUB_DB for multi-spec history (e.g. secondary specs like Affliction)
    if _G["PVPHUB_DB"] then
        local pKey = ns.GetPlayerKey()
        local playerName = UnitName("player")
        local hubChar = _G["PVPHUB_DB"][pKey]
        if not hubChar then
            for k, v in pairs(_G["PVPHUB_DB"]) do
                if type(v) == "table" and (k == playerName or string.find(tostring(k), "^" .. tostring(playerName) .. "-")) then
                    hubChar = v
                    break
                end
            end
        end

        if hubChar and hubChar.bracketStats and hubChar.bracketStats.ratingShuffle then
            for specID, stats in pairs(hubChar.bracketStats.ratingShuffle) do
                local sName, _, sIcon = nil, nil, nil
                if GetSpecializationInfoByID then
                    local _, n, _, ic = GetSpecializationInfoByID(specID)
                    sName = n
                    sIcon = ic
                end
                if sName and stats.played and stats.played > 0 then
                    local sMMR = nil
                    if hubChar.lastKnownMMR and hubChar.lastKnownMMR.ratingShuffle and hubChar.lastKnownMMR.ratingShuffle[specID] then
                        sMMR = hubChar.lastKnownMMR.ratingShuffle[specID].mmr
                    end

                    rec.specStats[sName] = rec.specStats[sName] or {}
                    local sObj = rec.specStats[sName]
                    sObj.name = sName
                    sObj.icon = sIcon or sObj.icon
                    sObj.rating = stats.rating or sObj.rating or 0
                    sObj.roundsWon = stats.won or sObj.roundsWon or 0
                    sObj.roundsPlayed = stats.played or sObj.roundsPlayed or 0
                    sObj.roundsLost = stats.lost or (sObj.roundsPlayed - sObj.roundsWon)
                    sObj.winRate = (sObj.roundsPlayed > 0) and (math.floor((sObj.roundsWon / sObj.roundsPlayed) * 1000 + 0.5) / 10) or 0
                    sObj.mmr = sMMR or sObj.mmr
                end
            end
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDBDefaults()
        ns.EnsurePlayerRecord()

        if ns.InitMatchTracker then
            ns.InitMatchTracker()
        end

        if ns.InitQueueTimer then
            ns.InitQueueTimer()
        end

        if ns.SyncExternalPvPData then
            ns.SyncExternalPvPData()
        end

        print("|cff40c0ffAlterArena|r loaded. Type /alterarena (or /aa) to view your history.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PVP_RATED_STATS_UPDATE" then
        if AlterArenaDB and AlterArenaDB.players then
            ns.EnsurePlayerRecord()
            if ns.SyncExternalPvPData then
                ns.SyncExternalPvPData()
            end
            ns.UpdateAllCharacterRatings()
            if ns.RefreshUI then
                ns.RefreshUI()
            end
        end
    end
end)

SLASH_ALTERARENA1 = "/alterarena"
SLASH_ALTERARENA2 = "/aa"
SlashCmdList["ALTERARENA"] = function(msg)
    msg = msg and strtrim(string.lower(msg))
    if msg == "test" then
        if ns.ToggleTestQueueTimer then
            ns.ToggleTestQueueTimer()
        end
    elseif msg == "ratings" or msg == "mmr" then
        if ns.PrintPvPRatings then
            ns.PrintPvPRatings()
        end
    elseif msg == "timer on" then
        if ns.SetQueueTimerEnabled then
            ns.SetQueueTimerEnabled(true)
            print("|cff40c0ffAlterArena|r: Queue timer overlay |cff22c55eENABLED|r.")
        end
    elseif msg == "timer off" then
        if ns.SetQueueTimerEnabled then
            ns.SetQueueTimerEnabled(false)
            print("|cff40c0ffAlterArena|r: Queue timer overlay |cffef4444DISABLED|r.")
        end
    elseif msg == "timer" then
        if ns.IsQueueTimerEnabled and ns.SetQueueTimerEnabled then
            local newState = not ns.IsQueueTimerEnabled()
            ns.SetQueueTimerEnabled(newState)
            local statusStr = newState and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
            print(string.format("|cff40c0ffAlterArena|r: Queue timer overlay %s.", statusStr))
        end
    elseif msg == "debug" then
        if AlterArenaDB and AlterArenaDB.settings then
            AlterArenaDB.settings.debugMode = not AlterArenaDB.settings.debugMode
            local statusStr = AlterArenaDB.settings.debugMode and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
            print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.", statusStr))
        end
    elseif msg == "settings" or msg == "config" or msg == "options" then
        if ns.OpenSettings then
            ns.OpenSettings()
        elseif ns.ToggleUI then
            ns.ToggleUI()
        end
    else
        if ns.ToggleUI then
            ns.ToggleUI()
        end
    end
end
