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
    schemaVersion = 2,
}

local function EnsureDBDefaults()
    for key, value in pairs(DEFAULTS) do
        if AlterArenaDB[key] == nil then
            AlterArenaDB[key] = value
        end
    end
    if AlterArenaDB.schemaVersion == nil then
        AlterArenaDB.schemaVersion = 1
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

-- rating model: bracketRatings and specStats are treated as a *cache* rebuilt from
-- (a) live GetPersonalRatedInfo for the current character
-- (b) match history for everyone else
-- Any prior seeding is discarded.
function ns.MigrateRatings()
    if not AlterArenaDB or not AlterArenaDB.players then return 0 end
    local cleared = 0
    for _, rec in pairs(AlterArenaDB.players) do
        if rec.bracketRatings and next(rec.bracketRatings) then
            rec.bracketRatings = {}
            cleared = cleared + 1
        end
        if rec.specStats and next(rec.specStats) then
            rec.specStats = {}
            cleared = cleared + 1
        end
        -- intentionally DO NOT touch rec.matches: those are event records
    end

    return cleared
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

function ns.RequestPVPStats()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_PVPUI")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_PVPUI")
    end
    if RequestRatedInfo then
        pcall(RequestRatedInfo)
    elseif C_PvP and C_PvP.RequestRatedInfo then
        pcall(C_PvP.RequestRatedInfo)
    end
end

-- Unified getter for any character's bracket rating (supporting per-spec data & match history fallback)
function ns.GetCharacterBracketData(rec, bracketName, specName)
    if not rec then return nil end
    local bRatings = rec.bracketRatings or {}
    local target = string.lower(bracketName or "")

    local bKey = "2v2"
    if target == "3v3" then
        bKey = "3v3"
    elseif target == "shuffle" or target == "solo shuffle" then
        bKey = "Shuffle"
    elseif target == "blitz" or target == "battleground blitz" then
        bKey = "Blitz"
    end

    -- 1. Check spec-specific rating first if specName is given
    if specName and (bKey == "Shuffle" or bKey == "Blitz") then
        local specKey = bKey .. "-" .. specName
        local sData = bRatings[specKey]
        if sData and sData.current and sData.current > 0 then
            return sData
        end
        if bKey == "Shuffle" and rec.specStats and rec.specStats[specName] then
            local ss = rec.specStats[specName]
            if ss.rating and ss.rating > 0 then
                return {
                    current = ss.rating,
                    previous = ss.previousRating,
                    change = ss.ratingChange or 0,
                    roundsWon = ss.roundsWon,
                    roundsPlayed = ss.roundsPlayed,
                    roundsLost = ss.roundsLost,
                    winRate = ss.winRate,
                    mmr = ss.mmr,
                    spec = specName,
                }
            end
        end
    end

    -- 2. Direct bracket data
    local direct = bRatings[bKey]
        or (bKey == "Shuffle" and bRatings["Solo Shuffle"])
        or (bKey == "Blitz" and bRatings["Battleground Blitz"])

    if direct and direct.current and direct.current > 0 then
        return direct
    end

    -- 3. If Shuffle without direct rating, search specStats for best spec rating
    if bKey == "Shuffle" and rec.specStats then
        local best = nil
        for sName, ss in pairs(rec.specStats) do
            if ss.rating and ss.rating > 0 then
                if not best or ss.rating > (best.current or 0) then
                    best = {
                        current = ss.rating,
                        previous = ss.previousRating,
                        change = ss.ratingChange or 0,
                        roundsWon = ss.roundsWon,
                        roundsPlayed = ss.roundsPlayed,
                        roundsLost = ss.roundsLost,
                        winRate = ss.winRate,
                        mmr = ss.mmr,
                        spec = sName,
                    }
                end
            end
        end
        if best then return best end
    end

    -- 4. Check match history as fallback (for alts not logged in recently)
    if rec.matches and #rec.matches > 0 then
        for i = #rec.matches, 1, -1 do
            local m = rec.matches[i]
            local mBracket = string.lower(m.bracket or "")
            local isMatchBracket = (mBracket == target)
                or (bKey == "Shuffle" and (mBracket == "shuffle" or mBracket == "solo shuffle"))
                or (bKey == "Blitz" and (mBracket == "blitz" or mBracket == "battleground blitz"))
                or (bKey == "2v2" and mBracket == "2v2")
                or (bKey == "3v3" and mBracket == "3v3")

            local isMatchSpec = (not specName) or (not m.spec) or (m.spec == specName)

            if isMatchBracket and isMatchSpec and m.ratingAfter and m.ratingAfter > 0 then
                return {
                    current = m.ratingAfter,
                    previous = m.ratingBefore,
                    change = m.ratingChange or ((m.ratingBefore and m.ratingAfter) and (m.ratingAfter - m.ratingBefore) or 0),
                    mmr = m.mmrAfter,
                    spec = m.spec,
                }
            end
        end
    end

    return direct
end

-- Backfills ratings for alts from match history if they have not been logged into recently
function ns.SanitizeAllPlayerRecords()
    local currentKey = ns.GetPlayerKey and ns.GetPlayerKey()
    if not AlterArenaDB or not AlterArenaDB.players then return end

    for key, rec in pairs(AlterArenaDB.players) do
        if key~=currentKey then
            rec.bracketRatings = rec.bracketRatings or {}
            rec.specStats = rec.specStats or {}
    
            if rec.matches and #rec.matches > 0 then
                for i = #rec.matches, 1, -1 do
                    local m = rec.matches[i]
                    if m and m.bracket and m.ratingAfter and m.ratingAfter > 0 then
                        local bName = m.bracket
                        if bName == "Solo Shuffle" then bName = "Shuffle" end
                        if bName == "Battleground Blitz" then bName = "Blitz" end
    
                        if not rec.bracketRatings[bName] or not rec.bracketRatings[bName].current or rec.bracketRatings[bName].current <= 0 then
                            rec.bracketRatings[bName] = {
                                current = m.ratingAfter,
                                previous = m.ratingBefore,
                                change = m.ratingChange or ((m.ratingBefore and m.ratingAfter) and (m.ratingAfter - m.ratingBefore) or 0),
                                mmr = m.mmrAfter,
                                spec = m.spec,
                            }
                        end
    
                        if m.spec and (bName == "Shuffle" or bName == "Blitz") then
                            local specKey = bName .. "-" .. m.spec
                            if not rec.bracketRatings[specKey] or not rec.bracketRatings[specKey].current or rec.bracketRatings[specKey].current <= 0 then
                                rec.bracketRatings[specKey] = {
                                    current = m.ratingAfter,
                                    previous = m.ratingBefore,
                                    change = m.ratingChange or 0,
                                    mmr = m.mmrAfter,
                                    spec = m.spec,
                                }
                            end
    
                            if bName == "Shuffle" and not rec.specStats[m.spec] then
                                rec.specStats[m.spec] = {
                                    name = m.spec,
                                    icon = m.specIcon,
                                    rating = m.ratingAfter,
                                    mmr = m.mmrAfter,
                                }
                            end
                        end
                    end
                end
            end
    
            if not rec.spec then
                if rec.specStats then
                    for sName, sData in pairs(rec.specStats) do
                        if sData and (sData.rating or 0) > 0 then
                            rec.spec = sName
                            rec.specIcon = sData.icon
                            break
                        end
                    end
                end
                if not rec.spec and rec.matches and #rec.matches > 0 then
                    for i = #rec.matches, 1, -1 do
                        if rec.matches[i].spec then
                            rec.spec = rec.matches[i].spec
                            rec.specIcon = rec.matches[i].specIcon
                            break
                        end
                    end
                end
            end
        end
    end
end

function ns.UpdateAllCharacterRatings()
    if not GetPersonalRatedInfo then return end
    local rec = ns.EnsurePlayerRecord()

    local recentMatch = ns.lastMatchTimestamp and (time() - ns.lastMatchTimestamp) < 90

    local function ApplyRatingDelta(data, newRating)
        if not data or not newRating or newRating <= 0 then return end
        if data.current == newRating then return end

        if recentMatch and data.current then
            -- A match actually just happened: record the real delta.
            data.previous = data.current
            data.current  = newRating
            data.change   = newRating - data.previous
        else
            -- Live API moved but we didn't observe a match: silent refresh.
            -- No fabricated delta.
            data.current  = newRating
            data.previous = nil
            data.change   = 0
        end
    end


    rec.specStats = rec.specStats or {}
    rec.bracketRatings = rec.bracketRatings or {}

    local curSpec = rec.spec
    if GetSpecialization and GetSpecializationInfo then
        local sIdx = GetSpecialization()
        if sIdx then
            local _, sName, _, sIcon = GetSpecializationInfo(sIdx)
            if sName then
                curSpec = sName
                rec.spec = sName
            end
            if sIcon then
                rec.specIcon = sIcon
            end
        end
    end

    -- In Retail WoW:
    -- Index 1: 2v2 Arena
    -- Index 2: 3v3 Arena
    -- Index 7: Solo Shuffle (bracket 4 is 10v10 RBG, do NOT fall back to 4)
    -- Index 9: Battleground Blitz (fallback 8)


    -- Resolve GetPersonalRatedInfo index by NAME, not by position.
    -- In 12.1.0 CONQUEST_BRACKET_INDEXES keys are NOT in display order, so
    -- positional lookups ([4]/[5]) return the wrong bracket entirely.
    local function ResolveBracketIndex(target)
        if CONQUEST_SIZE_STRINGS and CONQUEST_BRACKET_INDEXES then
            for i, name in pairs(CONQUEST_SIZE_STRINGS) do
                if name and string.find(string.lower(name), target) then
                    return CONQUEST_BRACKET_INDEXES[i] or i
                end
            end
        end
        if target == "2v2"     then return 1 end
        if target == "3v3"     then return 2 end
        if target == "shuffle" then return 7 end
        if target == "blitz"   then return 9 end
        return nil
    end

    local shuffleIdx = ResolveBracketIndex("shuffle") or 7
    local blitzIdx   = ResolveBracketIndex("blitz")   or 9

    local brackets = {
        { name = "Shuffle", idx = shuffleIdx, isSpecSpecific = true },
        { name = "Blitz", idx = blitzIdx, fallbackIdx = 8, isSpecSpecific = false },
        { name = "2v2", idx = 1, isSpecSpecific = false },
        { name = "3v3", idx = 2, isSpecSpecific = false },
    }

    for _, b in ipairs(brackets) do
        local rating, _, _, seasonPlayed, seasonWon, _, _, _, _, _, _, roundsSeasonPlayed, roundsSeasonWon = GetPersonalRatedInfo(b.idx)
        if b.fallbackIdx and (not rating or rating <= 0) and (not seasonPlayed or seasonPlayed == 0) then
            local rF, _, _, spF, swF = GetPersonalRatedInfo(b.fallbackIdx)
            if (rF and rF > 0) or (spF and spF > 0) then
                rating, seasonPlayed, seasonWon = rF, spF, swF
            end
        end

        local r = rating or 0
        local sWon = seasonWon or 0
        local sPlayed = seasonPlayed or 0
        local rPlayed = roundsSeasonPlayed or 0
        local rWon = roundsSeasonWon or 0
        local hasLiveData = (r > 0) or (sPlayed > 0) or (rPlayed > 0)
        if not hasLiveData then
            rec.bracketRatings[b.name] = nil
            if b.isSpecSpecific and curSpec then
                rec.bracketRatings[b.name .. "-" .. curSpec] = nil
            end
            if b.name == "Shuffle" and curSpec and rec.specStats[curSpec] then
                local so = rec.specStats[curSpec]
                so.rating = 0
                so.mmr = 0
                so.seasonPlayed = 0
                so.seasonWon = 0
                so.seasonLost = 0
                so.winRate = 0
                so.roundsWon = 0
                so.roundsPlayed = 0
                so.roundsLost = 0
            end
        else
            -- 1. Spec-specific storage for Shuffle and Blitz
            if b.isSpecSpecific and curSpec then
                local specKey = b.name .. "-" .. curSpec
                local sData = rec.bracketRatings[specKey]
    
                if not sData then
                    if r > 0 then
                        rec.bracketRatings[specKey] = { current = r, previous = nil, change = 0, spec = curSpec }
                        sData = rec.bracketRatings[specKey]
                    end
                else
                    ApplyRatingDelta(sData, r)
                end
    
                if sData then
                    if b.name == "Shuffle" and rPlayed > 0 then
                        sData.roundsWon = rWon
                        sData.roundsPlayed = rPlayed
                        sData.roundsLost = rPlayed - rWon
                        sData.winRate = (rPlayed > 0) and (math.floor((rWon / rPlayed) * 1000 + 0.5) / 10) or 0
                    else
                        sData.seasonWon = sWon
                        sData.seasonPlayed = sPlayed
                        sData.seasonLost = (sPlayed > sWon) and (sPlayed - sWon) or 0
                        sData.winRate = (sPlayed > 0) and (math.floor((sWon / sPlayed) * 1000 + 0.5) / 10) or 0
                    end
                end
            end
    
            -- 2. Base bracket storage
            local data = rec.bracketRatings[b.name]
            if not data then
                if r > 0 then
                    rec.bracketRatings[b.name] = { current = r, previous = nil, change = 0, spec = curSpec }
                    data = rec.bracketRatings[b.name]
                end
            else
                if b.isSpecSpecific then
                    -- NEW
                    if data.spec == curSpec then
                        ApplyRatingDelta(data, r)
                    else
                        data.spec = curSpec
                        if r > 0 then
                            data.current = r
                            data.previous = nil
                            data.change = 0
                        end
                    end
                else
                    ApplyRatingDelta(data, r)
                end
            end
    
            if data then
                if b.name == "Shuffle" and rPlayed and rPlayed > 0 then
                    data.roundsWon = rWon
                    data.roundsPlayed = rPlayed
                    data.roundsLost = rPlayed - rWon
                    data.winRate = (rPlayed > 0) and (math.floor((rWon / rPlayed) * 1000 + 0.5) / 10) or 0
                else
                    data.seasonWon = sWon
                    data.seasonPlayed = sPlayed
                    data.seasonLost = (sPlayed and sWon) and (sPlayed - sWon) or 0
                    data.winRate = (sPlayed and sPlayed > 0 and sWon) and (math.floor((sWon / sPlayed) * 1000 + 0.5) / 10) or 0
                end
            end
    
            -- 3. Update specStats for current spec in Shuffle
            if b.name == "Shuffle" and curSpec and (r > 0 or rPlayed > 0) then
                rec.specStats[curSpec] = rec.specStats[curSpec] or {}
                local sObj = rec.specStats[curSpec]
                sObj.name = curSpec
                sObj.icon = rec.specIcon or sObj.icon
                sObj.rating = r
                sObj.roundsWon = rWon
                sObj.roundsPlayed = rPlayed
                sObj.roundsLost = (rPlayed > rWon) and (rPlayed - rWon) or 0
                sObj.winRate = (rPlayed > 0) and (math.floor((rWon / rPlayed) * 1000 + 0.5) / 10) or 0
                if data and data.mmr then
                    sObj.mmr = data.mmr
                end
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

    -- Optional non-intrusive scan of PVPHUB_DB for multi-spec history.
-- SAFETY: exact "Name-Realm" key only. No fuzzy/name-only fallback search -
-- that's how data from a different character could get attributed here.
if _G["PVPHUB_DB"] and type(_G["PVPHUB_DB"]) == "table" then
    local pKey = ns.GetPlayerKey()
    local hubChar = _G["PVPHUB_DB"][pKey]

    if hubChar and hubChar.realm and hubChar.realm ~= GetRealmName() then
        hubChar = nil
    end
    if hubChar and hubChar.name and hubChar.name ~= UnitName("player") then
        hubChar = nil
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

                -- Never let an import overwrite a spec we've already confirmed
                -- ourselves (live API read or our own match history).
                if sObj.source == "pvphub" or not sObj.rating or sObj.rating <= 0 then
                    sObj.name = sName
                    sObj.icon = sIcon or sObj.icon
                    sObj.rating = stats.rating or sObj.rating or 0
                    sObj.roundsWon = stats.won or sObj.roundsWon or 0
                    sObj.roundsPlayed = stats.played or sObj.roundsPlayed or 0
                    sObj.roundsLost = stats.lost or (sObj.roundsPlayed - sObj.roundsWon)
                    sObj.winRate = (sObj.roundsPlayed > 0) and (math.floor((sObj.roundsWon / sObj.roundsPlayed) * 1000 + 0.5) / 10) or 0
                    sObj.mmr = sMMR or sObj.mmr
                    sObj.source = "pvphub"
                end
            end
        end
    end
end
end


-- Removes any bracket/spec rating seeded from an external addon's data
-- (source == "pvphub") that isn't corroborated by this character's own
-- recorded matches.
function ns.CleanPhantomRatings()
    if not AlterArenaDB or not AlterArenaDB.players then return 0, 0 end

    local removedCount, charCount = 0, 0

    for key, rec in pairs(AlterArenaDB.players) do
        local removedHere = 0

        local function HasCorroboratingMatch(bracketOrSpecName)
            if not rec.matches then return false end
            for _, m in ipairs(rec.matches) do
                if m and m.ratingAfter and m.ratingAfter > 0 then
                    if m.bracket == bracketOrSpecName or m.spec == bracketOrSpecName then
                        return true
                    end
                end
            end
            return false
        end

        if rec.bracketRatings then
            for bName, bData in pairs(rec.bracketRatings) do
                if type(bData) == "table" and bData.source == "pvphub" and not HasCorroboratingMatch(bName) then
                    rec.bracketRatings[bName] = nil
                    removedHere = removedHere + 1
                end
            end
        end

        if rec.specStats then
            for sName, sData in pairs(rec.specStats) do
                if type(sData) == "table" and sData.source == "pvphub" and not HasCorroboratingMatch(sName) then
                    rec.specStats[sName] = nil
                    removedHere = removedHere + 1
                end
            end
        end

        if removedHere > 0 then
            charCount = charCount + 1
            removedCount = removedCount + removedHere
        end
    end

    return removedCount, charCount
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

        ns.RequestPVPStats()
        ns.SanitizeAllPlayerRecords()
        
        if (AlterArenaDB.schemaVersion or 1) < 2 then
            local cleared = ns.MigrateRatings()
            AlterArenaDB.schemaVersion = 2
            AlterArenaDB.cleanedPhantomRatingsV1 = true  -- keep old flag so older builds don't re-run
            print(string.format("|cff40c0ffAlterArena|r: Rating cache rebuilt (cleared %d record(s)). Rebuilding from live API and match history…", cleared))
        end

        print("|cff40c0ffAlterArena|r loaded. Type /alterarena (or /aa) to view your history.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PVP_RATED_STATS_UPDATE" then
        if AlterArenaDB and AlterArenaDB.players then
            ns.EnsurePlayerRecord()
            ns.RequestPVPStats()
            ns.SanitizeAllPlayerRecords()
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
    elseif msg == "reset" then
        if AlterArenaDB and AlterArenaDB.players then
            for _, rec in pairs(AlterArenaDB.players) do
               rec.bracketRatings = {}
               rec.specStats = {}
            end
        end
        ns.RequestPVPStats()
        ns.UpdateAllCharacterRatings()
        ns.SanitizeAllPlayerRecords()
        if ns.RefreshUI then ns.RefreshUI() end
        print("|cff40c0ffAlterArena|r: Rating cache wiped and rebuilt from live API + match history.")
    elseif msg == "clean" then
        local removed, chars = ns.CleanPhantomRatings and ns.CleanPhantomRatings()
        if removed and removed > 0 then
            print(string.format("|cff40c0ffAlterArena|r: Removed %d unverified rating(s) across %d character(s).", removed, chars))
        else
            print("|cff40c0ffAlterArena|r: Nothing to clean.")
        end
        if ns.RefreshUI then ns.RefreshUI() end
    else
        if ns.ToggleUI then
            ns.ToggleUI()
        end
    end
end
