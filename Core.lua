-- =========================================================================
-- AlterArena data model
-- =========================================================================
-- Three data sources, in priority order:
--   1. Live Blizzard API (GetPersonalRatedInfo, C_CurrencyInfo, etc.)
--      Authoritative for the logged-in character.
--   2. AlterArenaDB.players[key].matches
--      Match records captured by MatchTracker. Authoritative for alts.
--   3. AlterArenaDB.players[key].bracketRatings / .specStats
--      Derived cache. Rebuilt from (1) and (2) on every load.
--
-- Rules:
--   - The addon NEVER reads from another addon's SavedVariables.
--   - The cache is disposable. Deleting it is always safe.
--   - .matches is the only append-only table. It is never rewritten by
--     migration code.
-- =========================================================================


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

-- AlterArenaDB + DEFAULTS: see Core/Database.lua

-- ns.CURRENCY: see Data/Currency.lua

-- ns.SOUNDS / ns.SOUND_BY_ID: see Data/Sounds.lua

-- Plays a sound entry by id. Prefers SOUNDKIT name resolution, Master channel.
-- PlaySound rarely errors, so "ok" from pcall is not proof the kit exists —
-- we still try name → numeric → file in order.
function ns.PlaySoundById(id)
    if not id or id == "none" then
        return false
    end
    local entry = ns.SOUND_BY_ID and ns.SOUND_BY_ID[id]
    if not entry then
        if AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode then
            print("|cff40c0ff[AA-SOUND]|r unknown id:", tostring(id))
        end
        return false
    end

    local detail = {}
    local kitID, source = nil, nil
    if ns.ResolveSoundKit then
        kitID, source = ns.ResolveSoundKit(entry)
    elseif type(entry.soundKit) == "number" then
        kitID, source = entry.soundKit, "numeric"
    end

    local function TryPlayKit(kit)
        if not kit or not PlaySound then return false end
        -- Channel "Master" so the sound is audible even if Dialog is low.
        local ok = pcall(PlaySound, kit, "Master")
        if not ok then
            ok = pcall(PlaySound, kit)
        end
        return ok and true or false
    end

    local played = false
    if kitID then
        played = TryPlayKit(kitID)
        table.insert(detail, string.format("%s=%s play=%s", tostring(source), tostring(kitID), tostring(played)))
    else
        table.insert(detail, "unresolved")
    end

    -- File path fallback (rare)
    if not played and entry.file and PlaySoundFile then
        local ok = pcall(PlaySoundFile, entry.file, "Master")
        played = ok and true or false
        table.insert(detail, "file=" .. tostring(played))
    end

    if AlterArenaDB and AlterArenaDB.settings and (
        AlterArenaDB.settings.debugMode or AlterArenaDB.settings.mirrorDebugChat
    ) then
        print("|cff40c0ff[AA-SOUND]|r", id, table.concat(detail, " "))
    end
    return played
end

-- Cached at load so filter logic can run synchronously without pcall noise.
ns.currentSeasonId = nil

function ns.RefreshCurrentSeason()
    if C_Seasons and C_Seasons.GetActiveSeason then
        local ok, id = pcall(C_Seasons.GetActiveSeason)
        if ok and id and type(id) == "number" then
            ns.currentSeasonId = id
            return
        end
    end
    if GetCurrentArenaSeason then
        local ok, n = pcall(GetCurrentArenaSeason)
        if ok and n and type(n) == "number" then
            ns.currentSeasonId = n
            return
        end
    end
    ns.currentSeasonId = nil

    -- Detect a season rollover: if the cached ID changed and we had one
    -- before, remember the old one as "last season".
    if ns.currentSeasonId and AlterArenaDB.lastKnownSeasonId
       and AlterArenaDB.lastKnownSeasonId ~= ns.currentSeasonId then
        AlterArenaDB.lastSeasonId = AlterArenaDB.lastKnownSeasonId
    end
    if ns.currentSeasonId then
        AlterArenaDB.lastKnownSeasonId = ns.currentSeasonId
    end
end

-- Debug logging: full implementation in modules/Debug.lua (ns.DebugLog / ns.DebugPrint).
-- Stub here so early Core calls before Debug.lua loads still work.
function ns.DebugPrint(...)
    if AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode then
        print("|cff40c0ff[AA-DEBUG]|r", ...)
    end
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
        { name = "Blitz", idx = blitzIdx, isSpecSpecific = false },
        { name = "2v2", idx = 1, isSpecSpecific = false },
        { name = "3v3", idx = 2, isSpecSpecific = false },
    }

    for _, b in ipairs(brackets) do
        local rating, _, _, seasonPlayed, seasonWon, _, _, _, _, _, _, roundsSeasonPlayed, roundsSeasonWon = GetPersonalRatedInfo(b.idx)
        local r = rating or 0
        local sWon = seasonWon or 0
        local sPlayed = seasonPlayed or 0
        local rPlayed = roundsSeasonPlayed or 0
        local rWon = roundsSeasonWon or 0
        local hasLiveData = (r > 0) or (sPlayed > 0) or (rPlayed > 0)
        if r > 0 then
            ns.UpdatePeak(rec, b.name, r)
            if b.isSpecSpecific and curSpec then
                ns.UpdatePeak(rec, b.name .. "-" .. curSpec, r)
            end
        end
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
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PVP_RATED_STATS_UPDATE")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ns.EnsureDBDefaults()
        ns.RefreshCurrentSeason()
        ns.RefreshPlayerCurrency()
        ns.CheckCurrencyAlerts()
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
            print(string.format("|cff40c0ffAlterArena|r: Rating cache rebuilt (cleared %d record(s)). Rebuilding from live API and match history…", cleared))
        end

        if ns.UI and ns.UI.Init then ns.UI.Init() end
        if ns.InitDebug then ns.InitDebug() end
        if ns.InitMinimap then ns.InitMinimap() end
        print("|cff40c0ffAlterArena|r loaded. Type /alterarena (or /aa) to view your history.")
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PVP_RATED_STATS_UPDATE" then
        if AlterArenaDB and AlterArenaDB.players then
            ns.RefreshCurrentSeason()
            ns.RefreshPlayerCurrency()
            ns.CheckCurrencyAlerts()
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
    elseif msg == "alerts" then
        if AlterArenaDB and AlterArenaDB.settings then
            AlterArenaDB.settings.disableCurrencyAlerts = not AlterArenaDB.settings.disableCurrencyAlerts
            local statusStr = AlterArenaDB.settings.disableCurrencyAlerts and "|cffef4444DISABLED|r" or "|cff22c55eENABLED|r"
            print(string.format("|cff40c0ffAlterArena|r: Currency alerts %s.", statusStr))
        end

    elseif msg == "alerttest" then
        if ns.TestCurrencyAlert then ns.TestCurrencyAlert() end
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
    elseif msg == "debug" or msg == "debugwindow" or msg == "dbg"
        or (msg and (msg:match("^debug%s") or msg:match("^dbg%s"))) then
        -- /aa debug          → toggle debug window
        -- /aa debug on|off   → force flag
        -- /aa debug test     → run self-test
        local sub = msg:match("^debug%s+(.+)$") or msg:match("^dbg%s+(.+)$")
        if sub == "on" then
            if AlterArenaDB and AlterArenaDB.settings then
                AlterArenaDB.settings.debugMode = true
                print("|cff40c0ffAlterArena|r: Debug mode |cff22c55eENABLED|r.")
            end
        elseif sub == "off" then
            if AlterArenaDB and AlterArenaDB.settings then
                AlterArenaDB.settings.debugMode = false
                print("|cff40c0ffAlterArena|r: Debug mode |cffef4444DISABLED|r.")
            end
        elseif sub == "test" or sub == "selftest" then
            if ns.RunDebugSelfTest then
                ns.RunDebugSelfTest()
            else
                print("|cff40c0ffAlterArena|r: Debug module not loaded.")
            end
            if ns.ToggleDebugWindow then ns.ToggleDebugWindow(true) end
        elseif sub == "match" or sub == "matchdump" or sub == "dump" then
            if ns.ToggleDebugWindow then ns.ToggleDebugWindow(true) end
            local f = _G.AlterArenaDebugFrame
            if f and f.ShowTab then f:ShowTab("match") end
            if ns.DumpMatchTrackerState then
                local text = ns.DumpMatchTrackerState()
                if f and f.RefreshMatchTab then f:RefreshMatchTab() end
                if text and ns.ShowDebugCopyPanel then
                    ns.ShowDebugCopyPanel(text, f)
                end
            else
                print("|cff40c0ffAlterArena|r: MatchTracker dump unavailable.")
            end
        elseif sub == "toggle" then
            if AlterArenaDB and AlterArenaDB.settings then
                AlterArenaDB.settings.debugMode = not AlterArenaDB.settings.debugMode
                local statusStr = AlterArenaDB.settings.debugMode and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
                print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.", statusStr))
            end
        else
            -- bare /aa debug → open/close debug window (and enable logging)
            if AlterArenaDB and AlterArenaDB.settings and not AlterArenaDB.settings.debugMode then
                AlterArenaDB.settings.debugMode = true
                print("|cff40c0ffAlterArena|r: Debug mode |cff22c55eENABLED|r (window open).")
            end
            if ns.ToggleDebugWindow then
                ns.ToggleDebugWindow()
            else
                print("|cff40c0ffAlterArena|r: Debug module not loaded.")
            end
        end
    elseif msg == "minimap" then
        if ns.ToggleMinimap then
            local shown = ns.ToggleMinimap()
            print(string.format("|cff40c0ffAlterArena|r: Minimap button %s.",
                shown and "|cff22c55eSHOWN|r" or "|cffef4444HIDDEN|r"))
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
    elseif msg and msg:match("^soundtest%s+(.+)$") then
        local sid = msg:match("^soundtest%s+(.+)$")
        print("|cff40c0ffAlterArena|r: Playing sound:", sid)
        if ns.PlaySoundById then ns.PlaySoundById(sid) end
    elseif msg == "soundlist" then
        print("|cff40c0ffAlterArena|r: Available sounds:")
        for _, s in ipairs(ns.SOUNDS) do
            local kit = s.soundKit and tostring(s.soundKit) or "—"
            print(string.format("  %-10s | %-16s | %-22s | kit=%s", s.category, s.id, s.label, kit))
        end
    elseif msg and msg:match("^soundsearch%s+(.+)$") then
        local needle = msg:match("^soundsearch%s+(.+)$"):upper()
        print("|cff40c0ffAlterArena|r: Searching SOUNDKIT for '" .. needle .. "'")
        local found = 0
        for name, id in pairs(SOUNDKIT or {}) do
            if type(name) == "string" and name:upper():find(needle, 1, true) then
                print(string.format("  %-45s = %d", name, id))
                found = found + 1
                if found >= 40 then
                    print("  ... (truncated)")
                    break
                end
            end
        end
        if found == 0 then
            print("  (nothing found — that name may not exist on this client)")
        end
    elseif msg and msg:match("^sounddump") then
        local needle = msg:match("^sounddump%s+(.+)$")
        local pat = needle and needle:upper() or nil
        local names = {
            "READY_CHECK", "RAID_WARNING", "RAID_BOSS_EMOTE_WARNING",
            "ALARM_CLOCK_WARNING_1", "ALARM_CLOCK_WARNING_2", "ALARM_CLOCK_WARNING_3",
            "PVP_THROUGH_QUEUE", "PVP_ENTER_QUEUE", "LFG_ROLE_CHECK",
            "UI_BATTLEGROUND_COUNTDOWN_FINISHED", "UI_BATTLEGROUND_COUNTDOWN_TIMER",
            "UI_RAID_BOSS_WHISPER_WARNING", "UI_BNET_TOAST", "UI_AUTO_QUEST_COMPLETE",
            "ACHIEVEMENT_MENU_OPEN", "IG_PVP_UPDATE", "MAP_PING", "TELL_MESSAGE",
        }
        print("|cff40c0ffAlterArena|r: SOUNDKIT dump " .. (pat and ("matching '"..pat.."'") or "(known names)"))
        for _, n in ipairs(names) do
            if not pat or n:find(pat, 1, true) then
                local v = SOUNDKIT and SOUNDKIT[n]
                print(string.format("  %-40s = %s", n, tostring(v)))
            end
        end
    else
        if ns.ToggleUI then
            ns.ToggleUI()
        end
    end
end