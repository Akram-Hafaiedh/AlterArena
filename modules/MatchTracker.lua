local ADDON_NAME, ns = ...

-- MatchTracker: rated match lifecycle (start → rounds → complete → history).
-- Debug dump archive lives in Debug.lua (ns.SaveMatchDebugDump).

local MT = ns.MatchTrackerPrivate or {}
ns.MatchTrackerPrivate = MT
MT.detectedPlayerSpecs = MT.detectedPlayerSpecs or {}
local detectedPlayerSpecs = MT.detectedPlayerSpecs -- shared with MatchOutcome
local pendingMatch = nil
MT.pendingMatch = nil

----------------------------------------------------------------------
-- Live match probe (feeds Debug window; no chat unless mirror is on)
----------------------------------------------------------------------
local lastProbeSummary = ""
local lastScoreProbe = 0
local lastOppProbe = 0
local lastMatchSnapshot = nil -- retained after match ends so Dump still works
local probeRing = {}          -- recent [MATCH] lines for dump
local PROBE_RING_MAX = 80

local function CountKeys(t)
    if not t then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function DescribeComp(list)
    if not list or #list == 0 then return "0"
    end
    local parts = {}
    for i, entry in ipairs(list) do
        if type(entry) == "number" then
            parts[#parts + 1] = tostring(entry)
        elseif type(entry) == "table" then
            parts[#parts + 1] = tostring(entry.specId or entry.spec or entry.icon or "?")
        else
            parts[#parts + 1] = "?"
        end
        if i >= 6 then break end
    end
    return string.format("%d[%s]", #list, table.concat(parts, ","))
end

--- Compact one-line state for the debug log.
local function MatchProbe(tag, extra)
    MT.pendingMatch = pendingMatch
    local pm = pendingMatch
    local parts = { "[MATCH]", tostring(tag or "?") }
    if not pm then
        parts[#parts + 1] = "pending=nil"
    else
        local r = pm.currentRound
        local rIdx = r and r.round or "-"
        local nRounds = (pm.rounds and #pm.rounds) or 0
        parts[#parts + 1] = string.format("rounds=%d", nRounds)
        parts[#parts + 1] = string.format("cur=%s", tostring(rIdx))
        if r then
            parts[#parts + 1] = "team=" .. DescribeComp(r.team)
            parts[#parts + 1] = "enemy=" .. DescribeComp(r.enemy)
            if r.won ~= nil then
                parts[#parts + 1] = "won=" .. tostring(r.won)
            end
            if r._finalized then
                parts[#parts + 1] = "finalized"
            end
        end
        parts[#parts + 1] = "snap=" .. tostring(CountKeys(pm.roundStartSnap))
        if pm.bracket then
            parts[#parts + 1] = "bracket=" .. tostring(pm.bracket)
        end
        if pm.map then
            parts[#parts + 1] = "map=" .. tostring(pm.map)
        end
    end
    if extra and extra ~= "" then
        parts[#parts + 1] = tostring(extra)
    end
    local line = table.concat(parts, " ")
    lastProbeSummary = line
    probeRing[#probeRing + 1] = { t = date("%H:%M:%S"), text = line }
    while #probeRing > PROBE_RING_MAX do
        table.remove(probeRing, 1)
    end
    if ns.DebugLog then
        ns.DebugLog(line)
    end
    if ns.RefreshMatchDebugTab then
        ns.RefreshMatchDebugTab()
    end
    return line
end

MT.MatchProbe = MatchProbe

--- Shallow snapshot of pendingMatch for post-match dump.
local function SnapshotPending(pm, reason)
    if not pm then return nil end
    local roundsCopy = {}
    for i, rd in ipairs(pm.rounds or {}) do
        roundsCopy[i] = {
            round = rd.round,
            team = rd.team,
            enemy = rd.enemy,
            won = rd.won,
            draw = rd.draw,
            duration = rd.duration,
            _finalizeReason = rd._finalizeReason,
        }
    end
    local cur = pm.currentRound
    local curCopy = nil
    if cur then
        curCopy = {
            round = cur.round,
            team = cur.team,
            enemy = cur.enemy,
            won = cur.won,
            draw = cur.draw,
            _finalized = cur._finalized,
            _chatWinner = cur._chatWinner,
        }
    end
    return {
        map = pm.map,
        bracket = pm.bracket,
        isRated = pm.isRated,
        matchStartTime = pm.matchStartTime or pm.startTime,
        earlyTermination = pm.earlyTermination,
        snapKeys = CountKeys(pm.roundStartSnap),
        ratingBefore = pm.ratingBefore,
        rounds = roundsCopy,
        currentRound = curCopy,
        closedAt = time(),
        closeReason = reason or "unknown",
    }
end

--- Full structured dump for Copy / inspection.
--- Uses live pendingMatch if active, otherwise lastMatchSnapshot from the
--- most recently completed match (so Dump still works after the game ends).
function ns.GetMatchTrackerDump()
    local lines = {}
    local function add(fmt, ...)
        lines[#lines + 1] = string.format(fmt, ...)
    end

    add("=== AlterArena MatchTracker dump %s ===", date("%Y-%m-%d %H:%M:%S"))

    local live = pendingMatch ~= nil
    local pm = pendingMatch
    local snap = lastMatchSnapshot

    if not pm and snap then
        add("status: POST-MATCH (live pendingMatch cleared)")
        add("closedAt: %s reason: %s", date("%H:%M:%S", snap.closedAt or 0), tostring(snap.closeReason))
        -- Adapt snapshot shape so the rest of the formatter can reuse it
        pm = {
            map = snap.map,
            bracket = snap.bracket,
            isRated = snap.isRated,
            matchStartTime = snap.matchStartTime,
            earlyTermination = snap.earlyTermination,
            roundStartSnap = nil,
            _snapKeys = snap.snapKeys,
            ratingBefore = snap.ratingBefore,
            rounds = snap.rounds,
            currentRound = snap.currentRound,
        }
    elseif not pm then
        add("status: IDLE (no live match, no saved snapshot yet)")
        add("lastProbe: %s", lastProbeSummary ~= "" and lastProbeSummary or "(none)")
        add("")
        add("-- Recent probes --")
        if #probeRing == 0 then
            add("(none)")
        else
            for i = 1, #probeRing do
                local e = probeRing[i]
                add("[%s] %s", e.t, e.text)
            end
        end
        return table.concat(lines, "\n")
    else
        add("status: LIVE match in progress")
    end

    add("map: %s", tostring(pm.map))
    add("bracket: %s", tostring(pm.bracket))
    add("isRated: %s", tostring(pm.isRated))
    add("matchStart: %s", tostring(pm.matchStartTime or pm.startTime))
    add("earlyTermination: %s", tostring(pm.earlyTermination))
    add("roundStartSnap keys: %d", pm._snapKeys or CountKeys(pm.roundStartSnap))

    if pm.ratingBefore then
        for bIdx, b in pairs(pm.ratingBefore) do
            add("  ratingBefore[%s]: rating=%s rounds=%s/%s",
                tostring(bIdx),
                tostring(b.rating),
                tostring(b.roundsWon),
                tostring(b.roundsPlayed))
        end
    end

    local rounds = pm.rounds or {}
    add("finalized rounds: %d", #rounds)
    for i, rd in ipairs(rounds) do
        add("  round %d: team=%s enemy=%s won=%s duration=%s reason=%s",
            rd.round or i,
            DescribeComp(rd.team),
            DescribeComp(rd.enemy),
            tostring(rd.won),
            tostring(rd.duration),
            tostring(rd._finalizeReason or ""))
    end

    if pm.currentRound then
        local r = pm.currentRound
        add("currentRound: #%s team=%s enemy=%s won=%s finalized=%s chatWinner=%s",
            tostring(r.round),
            DescribeComp(r.team),
            DescribeComp(r.enemy),
            tostring(r.won),
            tostring(r._finalized),
            tostring(r._chatWinner))
    else
        add("currentRound: nil")
    end

    if live then
        local nOpp = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
        add("API GetNumArenaOpponents: %s", tostring(nOpp))
        for i = 1, math.min(nOpp, 3) do
            local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
            add("  opponent[%d] specId=%s", i, tostring(specID))
        end
        local nScore = (GetNumBattlefieldScores and GetNumBattlefieldScores()) or 0
        add("API GetNumBattlefieldScores: %s", tostring(nScore))
        if C_PvP and C_PvP.GetActiveMatchState then
            add("API GetActiveMatchState: %s", tostring(C_PvP.GetActiveMatchState()))
        end
    end

    add("lastProbe: %s", lastProbeSummary ~= "" and lastProbeSummary or "(none)")
    add("")
    add("-- Recent probes (last %d) --", #probeRing)
    for i = 1, #probeRing do
        local e = probeRing[i]
        add("[%s] %s", e.t, e.text)
    end
    return table.concat(lines, "\n")
end

function ns.DumpMatchTrackerState()
    local text = ns.GetMatchTrackerDump()
    if ns.DebugLog then
        ns.DebugLog("-- MatchTracker dump --")
        for line in string.gmatch(text, "[^\n]+") do
            ns.DebugLog(line)
        end
    end
    return text
end

function ns.GetLastMatchProbe()
    return lastProbeSummary
end

local function EnsurePVPInfo()
    -- Same rule as Core: never force-load Blizzard_PVPUI early.
    if RequestRatedInfo then
        pcall(RequestRatedInfo)
    elseif C_PvP and C_PvP.RequestRatedInfo then
        pcall(C_PvP.RequestRatedInfo)
    end
end

local function GetCurrentSeasonId()
    if C_Seasons and C_Seasons.GetActiveSeason then
        local ok, seasonID = pcall(C_Seasons.GetActiveSeason)
        if ok and seasonID and type(seasonID) == "number" then
            return seasonID
        end
    end
    if GetCurrentArenaSeason then
        local ok, n = pcall(GetCurrentArenaSeason)
        if ok and n and type(n) == "number" then
            return n
        end
    end
    return nil
end
ns.GetCurrentSeasonId = GetCurrentSeasonId

local function GetBracketName(bracketIndex)
    if CONQUEST_SIZE_STRINGS and CONQUEST_BRACKET_INDEXES then
        for i, idx in pairs(CONQUEST_BRACKET_INDEXES) do
            if idx == bracketIndex and CONQUEST_SIZE_STRINGS[i] then
                local str = CONQUEST_SIZE_STRINGS[i]
                local lower = string.lower(str or "")
                if string.find(lower, "shuffle") or lower == "solo" then return "Solo Shuffle" end
                if string.find(lower, "blitz") then return "Blitz" end
                return str
            end
        end
    end
    local fallbackNames = {
        [1] = "2v2", [2] = "3v3", [3] = "10v10", [4] = "10v10",
        [7] = "Solo Shuffle", [8] = "Blitz", [9] = "Blitz",
    }
    return fallbackNames[bracketIndex] or ("Bracket " .. tostring(bracketIndex))
end

-- Snapshots every rated bracket's current rating and games/rounds played
-- so we can diff before/after a match and determine which bracket updated.
local function CaptureRatingSnapshot()
    local snapshot = {}
    if not GetPersonalRatedInfo then return snapshot end

    for bracketIndex = 1, 12 do
        local rating, _, _, seasonPlayed, seasonWon, _, _, _, _, _, _, roundsPlayed, roundsWon = GetPersonalRatedInfo(bracketIndex)
        if rating or seasonPlayed or roundsPlayed then
            snapshot[bracketIndex] = {
                rating = rating or 0,
                seasonPlayed = seasonPlayed or 0,
                seasonWon = seasonWon or 0,
                roundsPlayed = roundsPlayed or 0,
                roundsWon = roundsWon or 0,
            }
        end
    end
    return snapshot
end

local function SanitizeMatches(record)
    if not record or not record.matches then return end

    for _, m in ipairs(record.matches) do
        if not m.bracket or m.bracket == "" then
            m.bracket = "Unknown"
        end
        if not m.spec then
            m.spec = record.spec or "Destruction"
            m.specIcon = record.specIcon or 136186
        end
        if not m.map or m.map == "" then
            m.map = "Arena"
        end

        -- Solo Shuffle history row:
        --   Team column  → YOU only (player icon). Per-round allies belong in the
        --                  tooltip, not this column — do not promote round.team here.
        --   Enemy column → FULL lobby minus self (up to 5 unique), merged from
        --                  scoreboard enemyTeam + all round enemy lists.
        local isShuffle = (m.bracket == "Solo Shuffle" or m.bracket == "Shuffle")
        if isShuffle then
            local playerName = UnitName("player") or record.name or "Player"
            local playerNameLower = playerName:lower()
            local playerSpec = record.spec or (m.team and m.team[1] and m.team[1].spec)
            local playerIcon = record.specIcon or (m.team and m.team[1] and m.team[1].icon)
            local _, playerClass = UnitClass("player")
            playerClass = playerClass or record.class or (m.team and m.team[1] and m.team[1].class)

            -- Force Team column to a single player entry (never 3-man from rounds).
            m.team = {
                {
                    name = playerName,
                    spec = playerSpec,
                    icon = playerIcon,
                    class = playerClass,
                },
            }

            -- Enemy: merge unique opponents from scoreboard + every round.
            -- Prefer richer entries (name/spec tables) over bare icon ids.
            local merged = {}
            local seen = {}

            local function addEnemy(entry)
                if #merged >= 5 then return end
                local mem
                if type(entry) == "number" then
                    mem = { icon = entry }
                elseif type(entry) == "table" then
                    mem = entry
                else
                    return
                end
                local memName = mem.name and ns.AmbiguateName(mem.name)
                if memName and memName:lower() == playerNameLower then
                    return -- never list self as enemy
                end
                local key
                if memName and memName ~= "" then
                    key = "n:" .. memName:lower()
                elseif mem.icon then
                    key = "i:" .. tostring(mem.icon)
                else
                    key = "s:" .. tostring(mem.spec or "") .. "_" .. tostring(mem.class or "")
                end
                if seen[key] then
                    -- Upgrade a bare icon entry if we later get a richer table
                    if type(entry) == "table" and (mem.name or mem.spec) then
                        for i, existing in ipairs(merged) do
                            local eKey
                            if existing.name and ns.AmbiguateName(existing.name) then
                                eKey = "n:" .. ns.AmbiguateName(existing.name):lower()
                            elseif existing.icon then
                                eKey = "i:" .. tostring(existing.icon)
                            else
                                eKey = "s:" .. tostring(existing.spec or "") .. "_" .. tostring(existing.class or "")
                            end
                            if eKey == key or (existing.icon and mem.icon and existing.icon == mem.icon and not existing.name) then
                                local ic = mem.icon or ns.GetSpecIcon(mem.spec, mem.class)
                                if ic then mem.icon = ic end
                                merged[i] = mem
                                break
                            end
                        end
                    end
                    return
                end
                seen[key] = true
                if not mem.icon then
                    local ic = ns.GetSpecIcon(mem.spec, mem.class)
                    if ic then mem.icon = ic end
                end
                table.insert(merged, mem)
            end

            -- 1) Existing scoreboard list (richest source when present)
            if m.enemyTeam then
                for _, mem in ipairs(m.enemyTeam) do
                    addEnemy(mem)
                end
            end
            -- 2) Every round's enemy list (fills gaps / older matches)
            if m.rounds then
                for _, rd in ipairs(m.rounds) do
                    if rd.enemy then
                        for _, ic in ipairs(rd.enemy) do
                            addEnemy(ic)
                        end
                    end
                end
            end

            if #merged > 0 then
                m.enemyTeam = merged
            end
        else
            -- Non-shuffle: ensure spec icons are evaluated
            if m.team then
                for _, mem in ipairs(m.team) do
                    local ic = ns.GetSpecIcon(mem.spec, mem.class)
                    if ic then mem.icon = ic end
                end
            end
            if m.enemyTeam then
                for _, mem in ipairs(m.enemyTeam) do
                    local ic = ns.GetSpecIcon(mem.spec, mem.class)
                    if ic then mem.icon = ic end
                end
            end
        end
    end

    -- Ensure won flag matches rounds or rating change (scaled for early leaves)
    for _, m in ipairs(record.matches) do
        if m.roundsWon ~= nil then
            local played = m.roundsPlayed or 6
            local winThreshold = math.floor(played / 2) + 1
            local drawThreshold = played / 2
            if m.roundsWon >= winThreshold then
                m.won = true
            elseif played % 2 == 0 and m.roundsWon == drawThreshold then
                m.won = nil
            else
                m.won = false
            end
        elseif m.ratingChange and m.ratingChange ~= 0 then
            m.won = (m.ratingChange > 0)
        end
    end
end

function ns.SyncExternalPvPData()
    local playerKey = ns.GetPlayerKey and ns.GetPlayerKey()
    if not playerKey or not AlterArenaDB or not AlterArenaDB.players then return end
    local record = AlterArenaDB.players[playerKey]
    if not record then return end

    SanitizeMatches(record)
end

local activePoller = nil

-- Extracts the player's rounds won from the new 12.1 scoreboard format.
-- The old info.roundStats.roundsWon is gone. Stats now live in info.stats,
-- an array of { pvpStatID, pvpStatValue, name, ... }.

-- Fill currentRound.enemy from arena opponent APIs (retries needed; often 0 at MatchStart).
local function CaptureArenaEnemies(round)
    if not round or type(round.enemy) ~= "table" then return end
    if #round.enemy >= 3 then return end
    local numOpp = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
    if numOpp <= 0 then return end
    local seen = {}
    for _, ic in ipairs(round.enemy) do
        local key = type(ic) == "table" and (ic.icon or ic.spec) or ic
        if key then seen[key] = true end
    end
    for i = 1, math.min(numOpp, 3) do
        if #round.enemy >= 3 then break end
        local specID = nil
        if GetArenaOpponentSpec then
            local ok, id = pcall(GetArenaOpponentSpec, i)
            if ok and id and not (issecretvalue and issecretvalue(id)) and type(id) == "number" and id > 0 then
                specID = id
            end
        end
        if not specID and C_PvP and C_PvP.GetArenaOpponentSpec then
            local ok, id = pcall(C_PvP.GetArenaOpponentSpec, i)
            if ok and id and type(id) == "number" and id > 0 then specID = id end
        end
        if specID and GetSpecializationInfoByID then
            local ok, sName, _, sIcon, _, classToken = pcall(GetSpecializationInfoByID, specID)
            if ok and sIcon and not seen[sIcon] then
                seen[sIcon] = true
                table.insert(round.enemy, {
                    icon = sIcon,
                    spec = sName,
                    class = classToken,
                    specId = specID,
                })
            end
        end
    end
end

local CITY_MAP_HINTS = {
    silvermoon = true, orgrimmar = true, stormwind = true,
    dalaran = true, valdrakken = true, ironforge = true,
    undercity = true, thunderbluff = true, shattrath = true,
}

local function IsCityZoneName(zone)
    if not zone or zone == "" then return false end
    local lower = string.lower(zone)
    for hint in pairs(CITY_MAP_HINTS) do
        if lower:find(hint, 1, true) then return true end
    end
    return false
end

-- Prefer real arena/BG name over city lobby text.
local function RefreshMatchMap(pm)
    if not pm then return end
    local zone = (GetRealZoneText and GetRealZoneText()) or ""
    local instanceName = nil
    if GetInstanceInfo then
        local ok, name, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
        if ok and name and name ~= "" then instanceName = name end
    end
    local candidate = nil
    if instanceName and not IsCityZoneName(instanceName) then
        candidate = instanceName
    elseif zone ~= "" and not IsCityZoneName(zone) then
        candidate = zone
    end
    if candidate and candidate ~= "" then
        pm.map = candidate
    end
end

local function OnMatchStart()
    ns.DebugPrint("OnMatchStart, pendingMatch =", pendingMatch)
    EnsurePVPInfo()
    local qDur = (ns.GetLastQueueDuration and ns.GetLastQueueDuration()) or ns.lastQueueDuration
    local now = time()
    local currentZone = GetRealZoneText() or "Arena"

    -- Solo Shuffle: PVP_MATCH_ACTIVE fires in the city (e.g. Silvermoon) and
    -- again after porting into the arena. Map string changes — do NOT reset
    -- the session on map change. Continue while still inside the time window.
    local sameSession = pendingMatch
        and (now - (pendingMatch.matchStartTime or pendingMatch.startTime or now)) < 2400

    if sameSession then
        -- Update map once we land in the real arena/BG (skip city lobby names).
        RefreshMatchMap(pendingMatch)
        -- Re-detect bracket after zoning. Always allow Blitz/RBG to override a
        -- wrong Solo Shuffle label (IsRatedSoloShuffle can stick true in city).
        local again = MT.DetectBracketAtStart(pendingMatch.ratingBefore)
        if again then
            if not pendingMatch.bracket or pendingMatch.bracket == "" then
                pendingMatch.bracket = again
            elseif again == "Blitz" or again == "10v10" then
                pendingMatch.bracket = again
            elseif (pendingMatch.bracket == "Solo Shuffle" or pendingMatch.bracket == "Shuffle")
                   and again ~= "Solo Shuffle" and again ~= "Shuffle" then
                pendingMatch.bracket = again
            end
        end
        -- Shuffle only: force-close previous leg before opening the next.
        -- Blitz / arena / RBG are single-match — never split on a second ACTIVE.
        local isShuffleSession = (pendingMatch.bracket == "Solo Shuffle"
            or pendingMatch.bracket == "Shuffle")
        if isShuffleSession
           and pendingMatch.currentRound
           and not pendingMatch.currentRound._finalized then
            local prev = pendingMatch.currentRound
            if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
            MT.TryResolveCurrentRound(true)
            MT.FillRoundAllies(prev)
            MT.FinalizeRound(prev, "next_round")
            pendingMatch.currentRound = nil
            MatchProbe("ForceClose", "reason=next_active total=" .. tostring(#(pendingMatch.rounds or {})))
        end
    else
        -- Brand new match
        local ratingBefore = CaptureRatingSnapshot()
        local apiRated = (C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle())
            or (C_PvP and C_PvP.IsRatedArena and C_PvP.IsRatedArena())
            or (C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground())
            or (C_PvP and C_PvP.IsBlitz and C_PvP.IsBlitz())
            or (C_PvP and C_PvP.IsRatedMap and C_PvP.IsRatedMap())
            or false
        -- IsRated* can be false while still in the city; treat Shuffle as rated
        -- when bracket 7 already has a rating on this character.
        local shuffleRated = ratingBefore and ratingBefore[7]
            and type(ratingBefore[7].rating) == "number"
            and ratingBefore[7].rating > 0
        local bracket = MT.DetectBracketAtStart(ratingBefore)
        -- Only fall back to Shuffle when the API says so or bracket 7 is active.
        if not bracket then
            if ratingBefore and ratingBefore[7]
               and type(ratingBefore[7].rating) == "number"
               and ratingBefore[7].rating > 0
               and C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
                bracket = GetBracketName(7) or "Solo Shuffle"
            end
        end
        pendingMatch = {
            startTime = now,
            matchStartTime = now,
            ratingBefore = ratingBefore,
            isRated = apiRated or shuffleRated or false,
            map = currentZone,
            queueDuration = qDur,
            rounds = {},
            roundIndex = 0,
            bracket = bracket, -- may be nil until rating snapshot
        }
        MT.pendingMatch = pendingMatch
    end

    -- Number rounds by how many are already finalized (ignores discarded staging).
    local rIdx = (#pendingMatch.rounds or 0) + 1
    pendingMatch.roundIndex = rIdx

    local playerSpecIcon = nil
    if GetSpecialization and GetSpecializationInfo then
        local specIdx = GetSpecialization()
        if specIdx then
            local _, _, _, sIcon = GetSpecializationInfo(specIdx)
            playerSpecIcon = sIcon
        end
    end

    pendingMatch.currentRound = {
        round = rIdx,
        startTime = now,
        duration = 0,
        team = { playerSpecIcon or 136186 },
        enemy = {},
        won = nil,
    }

    -- Baseline snapshot. Scoreboard data isn't always pushed immediately,
    -- so retry until non-empty. Do NOT clobber a non-empty baseline that
    -- was rolled over from the previous round's PostRound snapshot.
    if RequestBattlefieldScoreData then
        pcall(RequestBattlefieldScoreData)
    end

    local function CaptureBaseline(attempt)
        if not pendingMatch or pendingMatch.currentRound == nil then return end
        if pendingMatch.currentRound.round ~= rIdx then return end
        attempt = attempt or 1

        if RequestBattlefieldScoreData then
            pcall(RequestBattlefieldScoreData)
        end

        local snap = MT.SnapshotScoreboard()

        if MT.IsSnapEmpty(snap) and attempt < 5 then
            C_Timer.After(0.5, function() CaptureBaseline(attempt + 1) end)
            return
        end

        -- Always overwrite: a stale baseline from the previous leg causes
        -- myDelta to re-count old wins (false green on the next round).
        if not MT.IsSnapEmpty(snap) then
            pendingMatch.roundStartSnap = snap
        end

        local c = 0
        for _ in pairs(pendingMatch.roundStartSnap or {}) do c = c + 1 end
        ns.DebugPrint("Round", rIdx, "baseline ready:", c, "players (attempt", attempt .. ")")
        MatchProbe("Baseline", "round=" .. tostring(rIdx) .. " keys=" .. tostring(c))
    end

    MatchProbe("MatchStart")
    C_Timer.After(1.0, function() CaptureBaseline(1) end)
    -- Enemy specs: often 0 at MatchStart (still in city). Retry until filled.
    local function CaptureEnemiesAttempt(attempt)
        if not pendingMatch or not pendingMatch.currentRound then return end
        if pendingMatch.currentRound.round ~= rIdx then return end
        RefreshMatchMap(pendingMatch)
        CaptureArenaEnemies(pendingMatch.currentRound)
        local n = #pendingMatch.currentRound.enemy
        local numOpp = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
        MatchProbe("EnemySpecs", "nOpp=" .. tostring(numOpp) .. " filled=" .. tostring(n)
            .. " attempt=" .. tostring(attempt or 1))
        if n < 3 and (attempt or 1) < 8 then
            C_Timer.After(1.5, function() CaptureEnemiesAttempt((attempt or 1) + 1) end)
        end
    end
    C_Timer.After(1.0, function() CaptureEnemiesAttempt(1) end)

    -- Ally fill: party1/party2 + scoreboard same team (see MT.FillRoundAllies).
    -- Critical capture is at PostRound; these mid-round tries help when inspect is ready early.
    local function CaptureTeammates(attempt)
        if not pendingMatch or not pendingMatch.currentRound then return end
        if pendingMatch.currentRound.round ~= rIdx then return end
        local round = pendingMatch.currentRound
        attempt = attempt or 1
        MT.FillRoundAllies(round)
        MatchProbe("TeamSpecs", string.format("n=%d attempt=%d", #round.team, attempt))
        if #round.team < 3 and attempt < 4 then
            C_Timer.After(2.0, function() CaptureTeammates(attempt + 1) end)
        else
            round.teamCaptured = true
        end
    end

    C_Timer.After(2.0, function() CaptureTeammates(1) end)
end


local function UpdateFromScoreboard(matchEntry, record)
    if not C_PvP or not C_PvP.GetScoreInfo or not GetNumBattlefieldScores then return false end
    local numScores = GetNumBattlefieldScores() or 0
    if numScores == 0 then return false end

    local playerGUID = UnitGUID("player")
    local playerName = UnitName("player")
    local playerFullName = (playerName or "") .. "-" .. (GetRealmName() or "")
    local playerTeam = nil
    local foundPlayer = false
    -- Arena/BG team index when scoreboard faction is still secret/empty.
    if GetBattlefieldArenaFaction then
        local ok, fac = pcall(GetBattlefieldArenaFaction)
        if ok and fac ~= nil and not (issecretvalue and issecretvalue(fac)) then
            playerTeam = tonumber(fac)
        end
    end

    local isSoloShuffle = (matchEntry.bracket == "Solo Shuffle" or matchEntry.bracket == "Shuffle")
    local enemyTotal, enemyCount = 0, 0
    local teamList = {}
    local enemyList = {}
    local enemySeen = {}

    local mostWinsName = playerName
    local mostWinsCount = 0
    local mostWinsColor = "ffffffff"
    local mostDeathsName = nil
    local mostDeathsCount = -1
    local mostDeathsColor = "ffffffff"

    for i = 1, numScores do
        local info = C_PvP.GetScoreInfo(i)
        if info then
            -- Name is safe to read and compare. GUID is a secret string in
            -- 12.x, so we cannot compare it directly. We identify the local
            -- player by name only.
            local infoName = ns.SafeString(info.name)
            local cleanInfoName = infoName and ns.AmbiguateName(infoName) or nil
            local isPlayer = (infoName and (infoName == playerName
                                            or infoName == playerFullName
                                            or cleanInfoName == playerName)) or false

            local infoTeam = ns.SafeNumber(info.team) or ns.SafeNumber(info.faction)

            if isPlayer then
                foundPlayer = true
                playerTeam = infoTeam

                local rChange = ns.SafeNumber(info.ratingChange)
                if rChange and rChange ~= 0 then
                    matchEntry.ratingChange = rChange
                    if matchEntry.ratingBefore then
                        matchEntry.ratingAfter = matchEntry.ratingBefore + rChange
                    end
                end

                local function readMMR(v)
                    local n = ns.SafeNumber(v)
                    if n and n > 0 then return n end
                    if type(v) == "number" and v > 0 then return v end
                    return nil
                end
                local preMMR  = readMMR(info.prematchMMR)
                local postMMR = readMMR(info.postmatchMMR)
                local mmrChg  = ns.SafeNumber(info.mmrChange)
                if type(info.mmrChange) == "number" and not mmrChg then mmrChg = info.mmrChange end
                if preMMR and preMMR > 0 then
                    matchEntry.mmrBefore = preMMR
                    matchEntry.mmrAfter  = postMMR or (preMMR + (mmrChg or 0))
                    matchEntry.mmrChange = mmrChg or (matchEntry.mmrAfter - matchEntry.mmrBefore)
                    local bKey = matchEntry.bracket
                    if bKey == "Solo Shuffle" then bKey = "Shuffle" end
                    if record and record.bracketRatings and bKey and record.bracketRatings[bKey] then
                        record.bracketRatings[bKey].mmr = matchEntry.mmrAfter
                    end
                end

                local pWins = MT.ExtractRoundsWon(info)
                if pWins then
                    matchEntry.roundsWon = pWins
                    -- Don't hardcode 6: an early-termination match can have
                    -- fewer completed rounds. Prefer the value we actually
                    -- recorded; fall back to 6 only if we somehow have none.
                    local recordedRounds = (pendingMatch and #(pendingMatch.rounds or {})) or 0
                    if recordedRounds > 0 then
                        matchEntry.roundsPlayed = recordedRounds
                    elseif matchEntry.roundsPlayed == nil then
                        matchEntry.roundsPlayed = 6
                    end
                end
            end

            -- Track most wins and most deaths. Both MT.ExtractRoundsWon and
            -- info.deaths may return nil if the underlying values are secret.
            local wins = MT.ExtractRoundsWon(info) or 0
            if wins > mostWinsCount then
                mostWinsCount = wins
                mostWinsName = cleanInfoName or infoName or "Player"
                local cToken = ns.SafeString(info.classToken)
                if cToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cToken] then
                    mostWinsColor = RAID_CLASS_COLORS[cToken].colorStr or "ffffffff"
                end
            end

            local deaths = ns.SafeNumber(info.deaths) or 0
            if deaths > mostDeathsCount then
                mostDeathsCount = deaths
                mostDeathsName = cleanInfoName or infoName or "Player"
                local cToken = ns.SafeString(info.classToken)
                if cToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cToken] then
                    mostDeathsColor = RAID_CLASS_COLORS[cToken].colorStr or "ffffffff"
                end
            end

            local cToken = (ns.SafeString(info.classToken) or ""):upper()
            local sName  = ns.SafeString(info.talentSpec) or ns.SafeString(info.specName)
            local sIcon  = (sName and ns.GetSpecIcon and ns.GetSpecIcon(sName, cToken))
            -- talentSpec is often a numeric spec ID on modern clients.
            if not sIcon then
                local specId = ns.SafeNumber(info.talentSpec) or ns.SafeNumber(info.specID)
                if (not specId or specId <= 0) and type(info.talentSpec) == "number" then
                    specId = info.talentSpec
                end
                if specId and specId > 0 and GetSpecializationInfoByID then
                    local ok, sn, _, _, ic = pcall(GetSpecializationInfoByID, specId)
                    if ok and ic then
                        sIcon = ic
                        sName = sName or sn
                    end
                end
            end
            if not sIcon then
                sIcon = MT.IconFromTalentSpecOrClass and MT.IconFromTalentSpecOrClass(nil, cToken)
            end

            if not sIcon or not sName then
                local d = nil
                if infoName then d = detectedPlayerSpecs[infoName] end
                if not d and cleanInfoName then d = detectedPlayerSpecs[cleanInfoName] end
                if d then
                    sName = sName or d.spec
                    sIcon = sIcon or d.icon
                    if cToken == "" and d.class then cToken = d.class end
                end
            end

            local member = {
                name  = cleanInfoName or infoName,
                spec  = sName,
                icon  = sIcon,
                class = cToken,
            }

            if isPlayer then
                if #teamList == 0 then
                    table.insert(teamList, member)
                end
            elseif isSoloShuffle then
                local eKey = (member.name and member.name:lower()) or (tostring(sName) .. "_" .. tostring(cToken))
                if not enemySeen[eKey] and #enemyList < 5 then
                    enemySeen[eKey] = true
                    table.insert(enemyList, member)
                end
                local m = ns.SafeNumber(info.postmatchMMR) or ns.SafeNumber(info.prematchMMR)
                if m and m > 0 then
                    enemyTotal = enemyTotal + m
                    enemyCount = enemyCount + 1
                end
            else
                -- 2v2 / 3v3 / Blitz: group by team/faction when available.
                local sameTeam = (infoTeam ~= nil and playerTeam ~= nil and infoTeam == playerTeam)
                if sameTeam then
                    table.insert(teamList, member)
                elseif infoTeam ~= nil and playerTeam ~= nil then
                    local eKey = (member.name and member.name:lower()) or (tostring(sName) .. "_" .. tostring(cToken))
                    if not enemySeen[eKey] then
                        enemySeen[eKey] = true
                        table.insert(enemyList, member)
                    end
                    local m = ns.SafeNumber(info.postmatchMMR) or ns.SafeNumber(info.prematchMMR)
                    if m and m > 0 then
                        enemyTotal = enemyTotal + m
                        enemyCount = enemyCount + 1
                    end
                else
                    -- team/faction missing (common on 12.x): treat non-player as enemy for now;
                    -- party fill below recovers real allies.
                    local eKey = (member.name and member.name:lower()) or (tostring(sName) .. "_" .. tostring(cToken))
                    if not enemySeen[eKey] then
                        enemySeen[eKey] = true
                        table.insert(enemyList, member)
                    end
                end
            end
        end
    end

    -- Arena allies: party units when scoreboard didn't tag the same team.
    if not isSoloShuffle and #teamList < 3 then
        local function addUnitAlly(unit)
            if #teamList >= 3 then return end
            if not UnitExists or not UnitExists(unit) then return end
            if UnitIsUnit and UnitIsUnit(unit, "player") then return end
            local okN, name = pcall(UnitName, unit)
            if not okN or not name then return end
            local clean = ns.AmbiguateName(name) or name
            for _, m in ipairs(teamList) do
                if m.name and (m.name == clean or m.name == name) then return end
            end
            -- Drop from enemy list if we wrongly classified them.
            for i = #enemyList, 1, -1 do
                local e = enemyList[i]
                if e.name and (e.name == clean or e.name == name) then
                    table.remove(enemyList, i)
                end
            end
            local okC, _, classToken = pcall(UnitClass, unit)
            classToken = classToken and tostring(classToken):upper() or ""
            local icon, specName = nil, nil
            if GetInspectSpecialization then
                local ok, sid = pcall(GetInspectSpecialization, unit)
                if ok and sid and type(sid) == "number" and sid > 0 and GetSpecializationInfoByID then
                    local ok2, sn, _, _, ic = pcall(GetSpecializationInfoByID, sid)
                    if ok2 and ic then icon, specName = ic, sn end
                end
            end
            if not icon and MT.IconFromTalentSpecOrClass then
                icon = MT.IconFromTalentSpecOrClass(nil, classToken)
            end
            table.insert(teamList, {
                name = clean,
                spec = specName,
                icon = icon,
                class = classToken,
            })
        end
        addUnitAlly("party1")
        addUnitAlly("party2")
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, math.min(n, 5) do
            addUnitAlly("raid" .. i)
        end
    end

    if enemyCount > 0 then
        matchEntry.enemyMMR = math.floor((enemyTotal / enemyCount) + 0.5)
    end
    if #teamList > 0 then matchEntry.team = teamList end
    if #enemyList > 0 then matchEntry.enemyTeam = enemyList end

    if mostWinsCount > 0 then
        matchEntry.mostWins = { name = mostWinsName, wins = mostWinsCount, classColor = mostWinsColor }
    end
    if mostDeathsCount >= 0 and mostDeathsName then
        matchEntry.mostDeaths = { name = mostDeathsName, deaths = mostDeathsCount, classColor = mostDeathsColor }
    end

    return foundPlayer
end

local function CheckRatingSnapshotDiff(matchEntry, pendingRatingBefore)
    local ratingAfter = CaptureRatingSnapshot()
    -- Collect all changed brackets; prefer Blitz/RBG/arena over Shuffle so a
    -- stuck shuffle index does not mislabel a BG.
    local hits = {}
    for bracketIndex, before in pairs(pendingRatingBefore or {}) do
        local after = ratingAfter[bracketIndex]
        if after then
            local playedChanged = (after.seasonPlayed ~= before.seasonPlayed)
                              or (after.roundsPlayed ~= before.roundsPlayed)
            local ratingChanged = (after.rating ~= before.rating)
            if playedChanged or ratingChanged then
                hits[#hits + 1] = {
                    index = bracketIndex,
                    before = before,
                    after = after,
                    name = GetBracketName(bracketIndex),
                }
            end
        end
    end
    if #hits == 0 then return false end

    local priority = {
        ["Blitz"] = 1, ["10v10"] = 2, ["3v3"] = 3, ["2v2"] = 4,
        ["Solo Shuffle"] = 9, ["Shuffle"] = 9,
    }
    table.sort(hits, function(a, b)
        local pa = priority[a.name or ""] or 5
        local pb = priority[b.name or ""] or 5
        if pa ~= pb then return pa < pb end
        return (a.index or 0) < (b.index or 0)
    end)
    local best = hits[1]
    matchEntry.bracket = best.name
    matchEntry.ratingBefore = best.before.rating
    matchEntry.ratingAfter = best.after.rating
    matchEntry.ratingChange = best.after.rating - best.before.rating
    if best.after.roundsPlayed and best.before.roundsPlayed
       and best.after.roundsPlayed > best.before.roundsPlayed then
        matchEntry.roundsPlayed = best.after.roundsPlayed - best.before.roundsPlayed
        matchEntry.roundsWon = (best.after.roundsWon or 0) - (best.before.roundsWon or 0)
    end
    return true
end

local function OnMatchComplete()
    MatchProbe("MatchComplete")
    if not pendingMatch then
        return
    end

    ns.DebugPrint("OnMatchComplete fired, rounds recorded =", #pendingMatch.rounds)

    local record = ns.EnsurePlayerRecord()
    local now = time()

    -- Last leg often goes state 3→5 with no PostRound. Finalize whatever is
    -- still open: currentRound OR the detached closingRound from PostRound.
    local last = pendingMatch.currentRound or pendingMatch.closingRound
    if last and not last._finalized then
        pendingMatch.currentRound = last
        if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
        MT.TryResolveCurrentRound(true)
        MT.FillRoundAllies(last)
        MT.FinalizeRound(last, "match_end")
        pendingMatch.currentRound = nil
        pendingMatch.closingRound = nil
        pendingMatch.postRoundClosing = nil
        MatchProbe("MatchEndFinalize", "total=" .. tostring(#pendingMatch.rounds))
    end
    local specName = nil
    local specIcon = nil
    if GetSpecialization and GetSpecializationInfo then
        local specIdx = GetSpecialization()
        if specIdx then
            local _, sName, _, sIcon = GetSpecializationInfo(specIdx)
            specName = sName
            specIcon = sIcon
        end
    end

    -- Initial rating snapshot diff
    local detectedBracket = pendingMatch.bracket -- may be nil / 2v2 / 3v3 / Shuffle
    local ratingBeforeVal = nil
    local ratingAfterVal = nil
    local ratingChangeVal = nil
    local roundsWonDelta = nil
    local roundsPlayedDelta = nil

    -- Capture the diff into a named table so its fields (bracket, rating,
    -- rounds, etc.) can actually be read back afterward.
    local diffEntry = { bracket = detectedBracket }
    local snapshotDiffFound = CheckRatingSnapshotDiff(diffEntry, pendingMatch.ratingBefore)

    if snapshotDiffFound then
        detectedBracket = diffEntry.bracket
        ratingBeforeVal = diffEntry.ratingBefore
        ratingAfterVal = diffEntry.ratingAfter
        ratingChangeVal = diffEntry.ratingChange
        roundsWonDelta = diffEntry.roundsWon
        roundsPlayedDelta = diffEntry.roundsPlayed
    end
    if not detectedBracket then
        detectedBracket = MT.DetectBracketAtStart(pendingMatch.ratingBefore) or "Arena"
    end

    ns.DebugPrint("snapshotDiffFound =", snapshotDiffFound, "bracket =", detectedBracket, "ratingChange =", ratingChangeVal)

    -- BG map + Solo Shuffle label is almost always a mis-detect (Blitz/RBG).
    local function MapLooksLikeBG(mapName)
        if not mapName or mapName == "" then return false end
        local lower = string.lower(mapName)
        if ns.KNOWN_BG_MAPS then
            for _, bg in ipairs(ns.KNOWN_BG_MAPS) do
                if lower:find(string.lower(bg), 1, true) then return true end
            end
        end
        -- Fallback name fragments for Blitz / RBG maps
        local hints = {
            "arathi", "warsong", "eye of the storm", "gilneas", "seething shore",
            "deepwind", "silvershard", "kotmogu", "twin peaks", "alterac",
            "isle of conquest", "wintergrasp", "ashran", "basin", "gulch",
        }
        for _, h in ipairs(hints) do
            if lower:find(h, 1, true) then return true end
        end
        return false
    end
    local mapForBracket = (pendingMatch and pendingMatch.map) or ""
    if (detectedBracket == "Solo Shuffle" or detectedBracket == "Shuffle")
       and MapLooksLikeBG(mapForBracket) then
        detectedBracket = "Blitz"
        MatchProbe("BracketFix", "shuffle->Blitz map=" .. tostring(mapForBracket))
    end
    if pendingMatch and (pendingMatch.bracket == "Solo Shuffle" or pendingMatch.bracket == "Shuffle")
       and MapLooksLikeBG(pendingMatch.map) then
        pendingMatch.bracket = "Blitz"
    end


    -- If initial diff didn't catch it yet, use pre-match rating
    if not ratingBeforeVal and pendingMatch.ratingBefore then
        for bIdx, bData in pairs(pendingMatch.ratingBefore) do
            if bData.roundsPlayed and bData.roundsPlayed > 0 then
                ratingBeforeVal = bData.rating
                break
            end
        end
        if not ratingBeforeVal and pendingMatch.ratingBefore[7] then
            ratingBeforeVal = pendingMatch.ratingBefore[7].rating
        end
    end

    local apiDur = C_PvP and C_PvP.GetPVPActiveMatchDuration and C_PvP.GetPVPActiveMatchDuration()
    local totalDuration = nil
    if pendingMatch.rounds and #pendingMatch.rounds > 1 then
        -- Solo Shuffle: sum up active combat duration of each round
        local sumRounds = 0
        for _, rd in ipairs(pendingMatch.rounds) do
            sumRounds = sumRounds + (rd.duration or 0)
        end
        if sumRounds > 0 then
            totalDuration = sumRounds
        end
    end

    if not totalDuration or totalDuration <= 0 then
        if apiDur and apiDur > 0 then
            totalDuration = math.floor(apiDur + 0.5)
        else
            totalDuration = math.max(1, now - (pendingMatch.matchStartTime or pendingMatch.startTime or now))
        end
    end

    local matchEntry = {
        timestamp = pendingMatch.matchStartTime or pendingMatch.startTime or now,
        duration = totalDuration,
        queueDuration = pendingMatch.queueDuration,
        isRated = pendingMatch.isRated,
        map = pendingMatch.map or GetRealZoneText() or "Arena",
        spec = specName,
        specIcon = specIcon,
        bracket = detectedBracket,
        ratingBefore = ratingBeforeVal,
        ratingAfter = ratingAfterVal,
        ratingChange = ratingChangeVal or 0,
        roundsWon = roundsWonDelta,
        roundsPlayed = roundsPlayedDelta,
        rounds = pendingMatch.rounds,
        seasonId = GetCurrentSeasonId(),
        earlyTermination = pendingMatch.earlyTermination or false,
    }
    -- Solo Shuffle is 6 legs; fewer usually means leaver / instance end.
    local isSh = (matchEntry.bracket == "Solo Shuffle" or matchEntry.bracket == "Shuffle")
    if isSh and matchEntry.rounds and #matchEntry.rounds < 6 then
        matchEntry.earlyTermination = true
        MatchProbe("EarlyTerm", "rounds=" .. tostring(#matchEntry.rounds) .. " expected=6")
    end


    -- Request server scoreboard data
    if RequestBattlefieldScoreData then
        RequestBattlefieldScoreData()
    end
    UpdateFromScoreboard(matchEntry, record)

    -- Arena: prefer live round comps when scoreboard split is incomplete.
    RefreshMatchMap(pendingMatch)
    if pendingMatch and pendingMatch.map and not IsCityZoneName(pendingMatch.map) then
        matchEntry.map = pendingMatch.map
    elseif matchEntry.map and IsCityZoneName(matchEntry.map) then
        local z = (GetRealZoneText and GetRealZoneText()) or ""
        if z ~= "" and not IsCityZoneName(z) then matchEntry.map = z end
        if GetInstanceInfo then
            local ok, name = pcall(GetInstanceInfo)
            if ok and name and not IsCityZoneName(name) then matchEntry.map = name end
        end
    end

    local lastRound = nil
    if matchEntry.rounds and #matchEntry.rounds > 0 then
        lastRound = matchEntry.rounds[#matchEntry.rounds]
        if lastRound and (not lastRound.enemy or #lastRound.enemy == 0) then
            CaptureArenaEnemies(lastRound)
        end
    end
    if lastRound then
        if (not matchEntry.team or #matchEntry.team < 2) and lastRound.team and #lastRound.team > 0 then
            local teamOut = {}
            for _, ic in ipairs(lastRound.team) do
                if type(ic) == "table" then
                    teamOut[#teamOut + 1] = ic
                else
                    teamOut[#teamOut + 1] = { icon = ic }
                end
            end
            if #teamOut > 0 then matchEntry.team = teamOut end
        end
        if (not matchEntry.enemyTeam or #matchEntry.enemyTeam == 0) and lastRound.enemy and #lastRound.enemy > 0 then
            local enemyOut = {}
            for _, ic in ipairs(lastRound.enemy) do
                if type(ic) == "table" then
                    enemyOut[#enemyOut + 1] = ic
                else
                    enemyOut[#enemyOut + 1] = { icon = ic }
                end
            end
            if #enemyOut > 0 then matchEntry.enemyTeam = enemyOut end
        end
    end
    -- Last chance: live arena units still available briefly after complete.
    if (not matchEntry.enemyTeam or #matchEntry.enemyTeam == 0) then
        local tmp = { enemy = {} }
        CaptureArenaEnemies(tmp)
        if #tmp.enemy > 0 then matchEntry.enemyTeam = tmp.enemy end
    end


    -- Scoreboard roundsWon is authoritative. GetActiveMatchWinner can mis-read
    -- myTeam on a single round; reconcile per-round flags so the tooltip matches.
    local function ReconcileRoundOutcomes(entry)
        if not entry or not entry.rounds or #entry.rounds == 0 then return end
        local expected = entry.roundsWon
        if expected == nil then return end
        local n = #entry.rounds
        local counted = 0
        for _, r in ipairs(entry.rounds) do
            if r.won == true then counted = counted + 1 end
        end
        if counted == expected then return end

        if expected >= n then
            for _, r in ipairs(entry.rounds) do
                r.won = true
                r.draw = nil
                r.incomplete = nil
            end
            MatchProbe("Reconcile", string.format("allWin n=%d expected=%d was=%d", n, expected, counted))
        elseif expected <= 0 then
            for _, r in ipairs(entry.rounds) do
                r.won = false
                r.draw = nil
                r.incomplete = nil
            end
            MatchProbe("Reconcile", string.format("allLoss n=%d expected=%d was=%d", n, expected, counted))
        elseif counted > expected then
            -- Too many greens vs scoreboard (stale delta / early leave).
            -- Demote the shortest wins first (phantoms + mid-round leaves).
            local wins = {}
            for i, r in ipairs(entry.rounds) do
                if r.won == true then
                    wins[#wins + 1] = { r = r, dur = r.duration or 9999, i = i }
                end
            end
            table.sort(wins, function(a, b) return a.dur < b.dur end)
            local drop = counted - expected
            for k = 1, math.min(drop, #wins) do
                wins[k].r.won = false
                wins[k].r._resolveSource = (wins[k].r._resolveSource or "") .. "+reconcileDemote"
            end
            MatchProbe("Reconcile", string.format("demote %d n=%d expected=%d was=%d",
                math.min(drop, #wins), n, expected, counted))
        else
            MatchProbe("Reconcile", string.format("skipPartial n=%d expected=%d was=%d", n, expected, counted))
        end
    end
    ReconcileRoundOutcomes(matchEntry)

    -- Determine outcome.
    local isShuffle = (matchEntry.bracket == "Solo Shuffle" or matchEntry.bracket == "Shuffle")

    if isShuffle and matchEntry.roundsWon ~= nil then
        -- Shuffle: threshold by rounds played.
        local played = matchEntry.roundsPlayed or 6
        local winThreshold = math.floor(played / 2) + 1
        local drawThreshold = played / 2
        if matchEntry.roundsWon >= winThreshold then
            matchEntry.won = true
        elseif played % 2 == 0 and matchEntry.roundsWon == drawThreshold then
            matchEntry.won = nil -- true draw (3-3)
        else
            matchEntry.won = false
        end
    elseif not isShuffle then
        -- 2v2 / 3v3 / Blitz / RBG: single match winner (not roundsWon).
        if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
        local winnerTeam = nil
        if C_PvP and C_PvP.GetActiveMatchWinner then
            local w = C_PvP.GetActiveMatchWinner()
            if w ~= nil and not (issecretvalue and issecretvalue(w)) then
                winnerTeam = tonumber(w)
            end
        end
        -- Classic BG API fallback (still used on some clients for Blitz/RBG).
        if winnerTeam == nil and GetBattlefieldWinner then
            local ok, w = pcall(GetBattlefieldWinner)
            if ok and w ~= nil and not (issecretvalue and issecretvalue(w)) then
                winnerTeam = tonumber(w)
            end
        end
        if winnerTeam ~= nil and (winnerTeam < 0 or winnerTeam > 1) then
            winnerTeam = nil
        end
        local myTeam = MT.GetMyShuffleTeamIndex()
        if winnerTeam ~= nil and myTeam ~= nil then
            matchEntry.won = (winnerTeam == myTeam)
            MatchProbe("MatchOutcome", string.format(
                "won=%s winnerTeam=%s myTeam=%s bracket=%s src=GetActiveMatchWinner",
                tostring(matchEntry.won), tostring(winnerTeam), tostring(myTeam),
                tostring(matchEntry.bracket)))
        elseif matchEntry.ratingChange and matchEntry.ratingChange ~= 0 then
            matchEntry.won = (matchEntry.ratingChange > 0)
            MatchProbe("MatchOutcome", "won=" .. tostring(matchEntry.won)
                .. " bracket=" .. tostring(matchEntry.bracket) .. " src=ratingChange")
        else
            local rw = nil
            if matchEntry.rounds then
                for _, r in ipairs(matchEntry.rounds) do
                    if r.won ~= nil then rw = r.won end
                end
            end
            if rw ~= nil then
                matchEntry.won = rw
            else
                matchEntry.won = false
                MatchProbe("MatchOutcome", "won=false bracket="
                    .. tostring(matchEntry.bracket) .. " src=defaultLoss")
            end
        end
    elseif matchEntry.ratingChange and matchEntry.ratingChange ~= 0 then
        matchEntry.won = (matchEntry.ratingChange > 0)
    else
        matchEntry.won = nil
    end

    -- Drop city-only phantoms (never ported / no enemies / no rating move).
    local mapLower = string.lower(matchEntry.map or "")
    local isCityMap = mapLower:find("silvermoon", 1, true)
        or mapLower:find("orgrimmar", 1, true)
        or mapLower:find("stormwind", 1, true)
        or mapLower:find("dalaran", 1, true)
        or mapLower:find("valdrakken", 1, true)
    local hasEnemy = false
    if matchEntry.rounds then
        for _, r in ipairs(matchEntry.rounds) do
            if r.enemy and #r.enemy > 0 then hasEnemy = true break end
        end
    end
    if matchEntry.enemyTeam and #matchEntry.enemyTeam > 0 then hasEnemy = true end
    local ratingMoved = matchEntry.ratingChange and matchEntry.ratingChange ~= 0
    if isCityMap and not hasEnemy and not ratingMoved then
        MatchProbe("SnapshotSkipped", "cityPhantom map=" .. tostring(matchEntry.map))
        pendingMatch = nil; MT.pendingMatch = nil
        return
    end

    table.insert(record.matches, matchEntry)
    ns.DebugPrint("Match recorded — bracket:", matchEntry.bracket, "won:", tostring(matchEntry.won), "ratingChange:", matchEntry.ratingChange)

    -- Persist full probe dump for this queue so we can debug without replaying.
    if ns.SaveMatchDebugDump and ns.GetMatchTrackerDump then
        local dumpText = ns.GetMatchTrackerDump()
        ns.SaveMatchDebugDump(dumpText, {
            bracket = matchEntry.bracket or "Unknown",
            map = matchEntry.map,
            reason = "match_complete",
            won = matchEntry.won,
            rounds = matchEntry.rounds and #matchEntry.rounds or 0,
        })
    end

    -- Setup background poller to ensure rating diff is captured when server updates
    local savedPending = pendingMatch
    local pollCount = 0
    local function PollRating()
        pollCount = pollCount + 1
        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        local scoreUpdated = UpdateFromScoreboard(matchEntry, record)
        local snapUpdated = CheckRatingSnapshotDiff(matchEntry, savedPending.ratingBefore)

        ns.DebugPrint("UpdateFromScoreboard done, roundsWon =", matchEntry.roundsWon, "ratingChange =", matchEntry.ratingChange)

        -- Re-run reconcile after delayed scoreboard poll (roundsWon may arrive late).
        do
            local expected = matchEntry.roundsWon
            local rounds = matchEntry.rounds
            if expected ~= nil and rounds and #rounds > 0 then
                local counted = 0
                for _, r in ipairs(rounds) do
                    if r.won == true then counted = counted + 1 end
                end
                if counted ~= expected then
                    if expected >= #rounds then
                        for _, r in ipairs(rounds) do r.won = true; r.draw = nil; r.incomplete = nil end
                    elseif expected <= 0 then
                        for _, r in ipairs(rounds) do r.won = false; r.draw = nil; r.incomplete = nil end
                    end
                end
            end
        end

        -- Same scaled thresholds as OnMatchComplete (handles early leaves)
        if matchEntry.roundsWon ~= nil then
            local played = matchEntry.roundsPlayed or 6
            local winThreshold = math.floor(played / 2) + 1
            local drawThreshold = played / 2
            if matchEntry.roundsWon >= winThreshold then
                matchEntry.won = true
            elseif played % 2 == 0 and matchEntry.roundsWon == drawThreshold then
                matchEntry.won = nil
            else
                matchEntry.won = false
            end
        elseif matchEntry.ratingChange and matchEntry.ratingChange ~= 0 then
            matchEntry.won = (matchEntry.ratingChange > 0)
        end

        if matchEntry.bracket and matchEntry.ratingAfter and ns.UpdateBracketRatingTracking then
            ns.UpdateBracketRatingTracking(matchEntry.bracket, matchEntry.ratingAfter)
        end

        if ns.RefreshUI then
            ns.RefreshUI()
        end

        if (not snapUpdated or not scoreUpdated or matchEntry.roundsWon == nil) and pollCount < 8 then
            C_Timer.After(1.5, PollRating)
        end
    end

    ns.lastMatchTimestamp = time()
    
    if matchEntry.bracket and matchEntry.ratingAfter and ns.UpdateBracketRatingTracking then
        ns.UpdateBracketRatingTracking(matchEntry.bracket, matchEntry.ratingAfter)
    end
    
    C_Timer.After(1.0, PollRating)
    lastMatchSnapshot = SnapshotPending(pendingMatch, "match_complete")
    MatchProbe("SnapshotSaved", string.format("rounds=%d", #(pendingMatch.rounds or {})))
    pendingMatch = nil; MT.pendingMatch = nil

    if ns.RefreshUI then
        ns.RefreshUI()
    end
end

function ns.InitMatchTracker()
    -- Hard dependency: MatchOutcome.lua + MatchRounds.lua must load first (see TOC).
    local required = {
        "TryResolveCurrentRound", "FinalizeRound", "FillRoundAllies",
        "SnapshotScoreboard", "IsSnapEmpty", "DetectBracketAtStart",
    }
    local missing = {}
    for _, name in ipairs(required) do
        if type(MT[name]) ~= "function" then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        local msg = "|cffff4040[AlterArena]|r Match modules incomplete — missing: "
            .. table.concat(missing, ", ")
            .. ". Ensure MatchOutcome.lua and MatchRounds.lua are in modules/ and listed in AlterArena.toc before MatchTracker.lua, then /reload."
        print(msg)
        if ns.DebugLog then ns.DebugLog(msg) end
    end

    if ns.SyncExternalPvPData then
        ns.SyncExternalPvPData()
    end

    local frame = CreateFrame("Frame")

    if IsActiveBattlefieldArena and IsActiveBattlefieldArena() and not pendingMatch then
        ns.DebugPrint("Recovery triggered: already in active arena on load")
        C_Timer.After(0, OnMatchStart)
    end
    frame:RegisterEvent("PVP_MATCH_ACTIVE")
    frame:RegisterEvent("PVP_MATCH_COMPLETE")
    frame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    frame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("ZONE_CHANGED")

    -- Per-round win/loss detection for Solo Shuffle. Blizzard announces
    -- "Round N won by <name>" on the BG system channel at the end of each
    -- round. All three faction variants are hooked in case the message
    -- routes through a different one on non-standard clients.
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")
    frame:RegisterEvent("CHAT_MSG_SYSTEM") -- some clients route round winners here

    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
           or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
           or event == "CHAT_MSG_BG_SYSTEM_HORDE"
           or event == "CHAT_MSG_SYSTEM" then
            -- 12.x can mark chat payloads as secret; never compare/index them raw.
            local rawMsg = ...
            local msg = ns.SafeString(rawMsg)
            if not msg or msg == "" then return end

            if pendingMatch
               and (msg:find("has left", 1, true)
                    or msg:find("has fled", 1, true)
                    or msg:find("abandoned", 1, true)) then
                pendingMatch.earlyTermination = true
                ns.DebugPrint("Early termination detected:", msg)
            end

            -- Chat is last-resort only; primary W/L is GetActiveMatchWinner.
            local lower = msg:lower()
            local isRoundWin = lower:find("won by", 1, true)
                or lower:find("wins the round", 1, true)
                or lower:find("round.-won", 1)
            if pendingMatch and isRoundWin then
                local roundNum = tonumber(msg:match("[Rr]ound%s+(%d+)"))
                local winner = msg:match("[Ww]on by%s+(.+)$")
                    or msg:match("[Ww]ins the round[:%s]+(.+)$")
                if winner then
                    winner = winner:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s+$", "")
                end

                local target = pendingMatch.currentRound
                if (not target or target._finalized) and pendingMatch.rounds and #pendingMatch.rounds > 0 then
                    target = pendingMatch.rounds[#pendingMatch.rounds]
                end

                if target and winner and winner ~= "" then
                    target._chatWinner = winner
                    if roundNum and not target._finalized then
                        target.round = roundNum
                    end
                    MatchProbe("ChatWinner", string.format("r=%s winner=%s", tostring(roundNum or target.round), winner))
                    -- Apply outcome immediately (don't wait for PostRound scoreboard).
                    if target.won == nil and not target.draw then
                        MT.CommitChatFallback(target)
                    end
                end
            end

        elseif event == "PVP_MATCH_ACTIVE" then
            MatchProbe("EVT_ACTIVE")
            OnMatchStart()
        elseif event == "PVP_MATCH_STATE_CHANGED" then
            local st = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
            MatchProbe("EVT_STATE", "state=" .. tostring(st))
            local state = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState() or nil
            ns.DebugPrint("PVP_MATCH_STATE_CHANGED ->", state)

            if pendingMatch and state then
                local lastState = pendingMatch.matchState or 0

                -- Recover missed ACTIVE only during prep/combat, never while
                -- a PostRound finalize is in flight (that spawned 5s phantoms).
                if state >= 2 and state < 4
                   and not pendingMatch.currentRound
                   and not pendingMatch.postRoundClosing
                   and #(pendingMatch.rounds or {}) < 6 then
                    MatchProbe("RecoverRound", "state=" .. tostring(state) .. " total=" .. tostring(#(pendingMatch.rounds or {})))
                    OnMatchStart()
                end

                -- Engaged (3) -> PostRound (4) / Complete (5): round is over.
                -- Detach currentRound immediately so the next leg can open while
                -- we finish resolve/finalize on the detached round object.
                if state >= 4 and lastState < 4 and pendingMatch.currentRound then
                    local round = pendingMatch.currentRound
                    if pendingMatch.currentRound == round then
                        pendingMatch.currentRound = nil
                    end
                    pendingMatch.closingRound = round
                    pendingMatch.postRoundClosing = true
                    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end

                    local function FinishPostRound(attempt)
                        attempt = attempt or 1
                        if not pendingMatch or not round or round._finalized then
                            if pendingMatch then
                                pendingMatch.postRoundClosing = nil
                                if pendingMatch.closingRound == round then
                                    pendingMatch.closingRound = nil
                                end
                            end
                            return
                        end

                        if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
                        if not round._finalized then
                            round.won = nil
                            round.draw = nil
                            round.incomplete = nil
                        end
                        local prevCur = pendingMatch.currentRound
                        pendingMatch.currentRound = round
                        MT.TryResolveCurrentRound(true)
                        pendingMatch.currentRound = prevCur

                        local resolved = (round.won ~= nil) or round.draw
                        -- state=5 / match complete: commit immediately, no delay.
                        local stNow = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState()
                        if (not resolved) and attempt < 2 and stNow and stNow < 5 then
                            C_Timer.After(0.4, function() FinishPostRound(attempt + 1) end)
                            return
                        end

                        MT.FillRoundAllies(round)
                        MT.FinalizeRound(round, (stNow and stNow >= 5) and "match_end" or "post_round")
                        pendingMatch.postRoundClosing = nil
                        if pendingMatch.closingRound == round then
                            pendingMatch.closingRound = nil
                        end
                        if pendingMatch then
                            local snap = MT.SnapshotScoreboard()
                            if not MT.IsSnapEmpty(snap) then
                                pendingMatch.roundStartSnap = snap
                            end
                            if pendingMatch.currentRound == round then
                                pendingMatch.currentRound = nil
                            end
                            MatchProbe("PostRoundDone", string.format(
                                "attempt=%d won=%s total=%d",
                                attempt, tostring(round.won), #pendingMatch.rounds))
                        end
                    end

                    -- Match complete (state 5): finalize sync so we never drop the last leg.
                    if state >= 5 then
                        FinishPostRound(1)
                    else
                        C_Timer.After(0.3, function() FinishPostRound(1) end)
                    end
                end

                pendingMatch.matchState = state
            end
        elseif event == "PVP_MATCH_COMPLETE" then
            OnMatchComplete()
        elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
            if pendingMatch then
                RefreshMatchMap(pendingMatch)
            end
        elseif event == "ARENA_OPPONENT_UPDATE" then
            local nowOpp = GetTime and GetTime() or time()
            if (nowOpp - lastOppProbe) >= 1.0 then
                lastOppProbe = nowOpp
                MatchProbe("EVT_OPP_UPDATE")
            end
            -- Recover missed round start: enemies visible, no open round, not mid-PostRound.
            if pendingMatch
               and not pendingMatch.currentRound
               and not pendingMatch.postRoundClosing
               and (pendingMatch.matchState or 0) < 4
               and #(pendingMatch.rounds or {}) < 6
               and GetNumArenaOpponents and (GetNumArenaOpponents() or 0) > 0 then
                MatchProbe("RecoverRound", "src=OPP_UPDATE total=" .. tostring(#(pendingMatch.rounds or {})))
                OnMatchStart()
            end
            if pendingMatch then
                RefreshMatchMap(pendingMatch)
                if pendingMatch.currentRound then
                    CaptureArenaEnemies(pendingMatch.currentRound)
                end
            end
            if GetNumArenaOpponents then
                for i = 1, GetNumArenaOpponents() do
                    local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
                    if specID and specID > 0 and GetSpecializationInfoByID then
                        local _, sName, _, sIcon, _, classToken = GetSpecializationInfoByID(specID)
                        local u = "arena" .. i
                        local guid = UnitGUID(u)
                        local name = UnitName(u)
                        local data = { spec = sName, icon = sIcon, class = classToken }
                        if ns.IsIndexable(guid) then
                            detectedPlayerSpecs[guid] = data
                        end
                        if ns.IsIndexable(name) then
                            detectedPlayerSpecs[name] = data
                            local clean = ns.AmbiguateName(name)
                            if ns.IsIndexable(clean) and clean ~= "" and clean ~= name then
                                detectedPlayerSpecs[clean] = data
                            end
                        end
                    end
                end
            end
            for i = 1, 2 do
                local u = "party" .. i
                if UnitExists(u) then
                    local guid = UnitGUID(u)
                    local name = UnitName(u)
                    local _, classToken = UnitClass(u)
                    if classToken and ns.IsIndexable(guid) and not detectedPlayerSpecs[guid] then
                        detectedPlayerSpecs[guid] = { class = classToken }
                        if ns.IsIndexable(name) then
                            detectedPlayerSpecs[name] = { class = classToken }
                            local clean = ns.AmbiguateName(name)
                            if ns.IsIndexable(clean) and clean ~= "" and clean ~= name then
                                detectedPlayerSpecs[clean] = { class = classToken }
                            end
                        end
                    end
                end
            end
        elseif event == "UPDATE_BATTLEFIELD_SCORE" then
            -- The primary per-round resolver trigger. Fires whenever the
            -- server pushes new scoreboard data — including the moment a
            -- round ends.
            if pendingMatch then
                local now = GetTime and GetTime() or time()
                if (now - lastScoreProbe) >= 1.5 then
                    lastScoreProbe = now
                    MatchProbe("EVT_SCORE", "n=" .. tostring(GetNumBattlefieldScores and GetNumBattlefieldScores() or 0))
                end
                MT.TryResolveCurrentRound()
            end

            local pKey = ns.GetPlayerKey and ns.GetPlayerKey()
            local rec = pKey and AlterArenaDB and AlterArenaDB.players and AlterArenaDB.players[pKey]
            if rec and rec.matches and #rec.matches > 0 then
                local lastM = rec.matches[#rec.matches]
                if (time() - (lastM.timestamp or 0)) < 300 then
                    UpdateFromScoreboard(lastM, rec)
                    if ns.RefreshUI then ns.RefreshUI() end
                end
            end
            if ns.SyncExternalPvPData then
                ns.SyncExternalPvPData()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            if ns.SyncExternalPvPData then
                ns.SyncExternalPvPData()
            end
        end
    end)
end