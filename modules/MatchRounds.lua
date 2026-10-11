local ADDON_NAME, ns = ...

-- MatchRounds: Solo Shuffle leg lifecycle (scoreboard snap, resolve, finalize).
-- Depends on MatchOutcome (GetMyShuffleTeamIndex, etc.). Uses ns.MatchTrackerPrivate.

local MT = ns.MatchTrackerPrivate or {}
ns.MatchTrackerPrivate = MT

function MT.ExtractRoundsWon(info)
    if not info then return nil end

    if info.stats then
        -- 1. Try to resolve the victory stat ID safely.
        local victoryID = nil
        if C_PvP and C_PvP.GetCustomVictoryStatID then
            local ok, id = pcall(C_PvP.GetCustomVictoryStatID)
            if ok then victoryID = ns.SafeNumber(id) end
        end

        -- 2. Match by victory stat ID (if we could resolve it)
        if victoryID then
            for _, stat in ipairs(info.stats) do
                local statID = ns.SafeNumber(stat and stat.pvpStatID)
                if statID and statID == victoryID then
                    local v = ns.SafeNumber(stat.pvpStatValue)
                    if v then return v end
                end
            end
        end

        -- 3. Match by stat name — ONLY victory/wins.
        --    Do NOT match bare "round" (hits "Rounds Played" and inflates Most Wins to 6).
        for _, stat in ipairs(info.stats) do
            local sname = ns.SafeString(stat and stat.name)
            if sname and sname ~= "" then
                local n = sname:lower()
                if n:find("victory", 1, true)
                   or n == "wins"
                   or n:find("rounds won", 1, true)
                   or n:find("round won", 1, true)
                   or (n:find("win", 1, true) and not n:find("played", 1, true)) then
                    local v = ns.SafeNumber(stat.pvpStatValue)
                    if v then return v end
                end
            end
        end

        -- 4. No blind first-stat fallback — wrong column was treated as wins.
    end

    -- Legacy fallback for older clients.
    if info.roundStats then
        local v = ns.SafeNumber(info.roundStats.roundsWon)
        if v then return v end
    end

    return nil
end


-- Per-round scoreboard snapshot. Called at the START of each round.
-- Captures each player's cumulative roundsWon so we can diff it when the
-- round ends. Keys are GUIDs (or names as fallback).
function MT.SnapshotScoreboard()
    local snap = {}
    if not C_PvP or not C_PvP.GetScoreInfo or not GetNumBattlefieldScores then
        return snap
    end
    local n = GetNumBattlefieldScores() or 0
    if n == 0 then return snap end

    for i = 1, n do
        local info = C_PvP.GetScoreInfo(i)
        if info then
            -- info.guid is a secret string in 12.x and CANNOT be used as a
            -- table key. Names are plain strings and unique within a match,
            -- so we key by name. Slot index is a fallback only.
            local name = ns.SafeString(info.name)
            local key  = name or ("slot_" .. i)

            local roundsWon = MT.ExtractRoundsWon(info) or 0
            snap[key] = {
                name = name or key,
                roundsWon = roundsWon,
            }
        end
    end
    return snap
end

-- True when a snapshot has no players in it (scoreboard hasn't been pushed yet)
function MT.IsSnapEmpty(snap)
    if not snap then return true end
    return next(snap) == nil
end

-- Per-round W/L: scoreboard roundsWon delta first, then GetActiveMatchWinner.
function MT.TryResolveCurrentRound(force)
    if not MT.pendingMatch or not MT.pendingMatch.currentRound then return end
    local round = MT.pendingMatch.currentRound
    if not force and (round.won ~= nil or round.draw or round.incomplete) then return end
    if round._finalized then return end

    local state = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState() or 0
    local isPost = (type(state) == "number" and state >= 4)
    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end

    -- =====================================================================
    -- PRIMARY (RatedStats / reliable): player's scoreboard roundsWon delta.
    -- If your wins counter went up this leg → win. If others went up and you
    -- did not → loss. Does not depend on flaky myTeam index.
    -- =====================================================================
    local base = MT.pendingMatch.roundStartSnap
    if not MT.IsSnapEmpty(base) then
        local after = MT.SnapshotScoreboard()
        if not MT.IsSnapEmpty(after) then
            local playerName = UnitName("player")
            local myDelta, totalDelta = 0, 0
            for key, a in pairs(after) do
                local b = base[key]
                local before = (b and b.roundsWon) or 0
                local delta  = (a.roundsWon or 0) - before
                if delta > 0 then
                    totalDelta = totalDelta + delta
                    local an = a.name and ns.AmbiguateName(a.name) or a.name
                    if playerName and (a.name == playerName or an == playerName) then
                        myDelta = delta
                    end
                end
            end
            -- totalDelta > 3 ⇒ baseline spans multiple legs (stale) — ignore.
            if totalDelta > 0 and totalDelta <= 3 then
                if myDelta > 0 then
                    round.won = true
                    round.draw = nil
                    round.incomplete = nil
                    round._resolveSource = "scoreboardDelta"
                    MT.MatchProbe("ResolveRound", string.format(
                        "won=true myDelta=%s totalDelta=%s src=scoreboardDelta",
                        tostring(myDelta), tostring(totalDelta)))
                    return
                end
                if isPost and totalDelta >= 3 then
                    round.won = false
                    round.draw = nil
                    round.incomplete = nil
                    round._resolveSource = "scoreboardDelta"
                    MT.MatchProbe("ResolveRound", string.format(
                        "won=false myDelta=0 totalDelta=%s src=scoreboardDelta",
                        tostring(totalDelta)))
                    return
                end
            elseif totalDelta > 3 then
                MT.MatchProbe("ResolveRound", "staleBaseline totalDelta=" .. tostring(totalDelta))
            end
        end
    end

    -- =====================================================================
    -- FALLBACK: GetActiveMatchWinner == myTeam (can mis-read myTeam on 12.x)
    -- =====================================================================
    if isPost and C_PvP and C_PvP.GetActiveMatchWinner then
        local winnerTeam = C_PvP.GetActiveMatchWinner()
        if winnerTeam ~= nil and issecretvalue and issecretvalue(winnerTeam) then
            winnerTeam = nil
        else
            winnerTeam = tonumber(winnerTeam)
        end
        if winnerTeam ~= nil and (winnerTeam < 0 or winnerTeam > 1 or winnerTeam ~= winnerTeam) then
            winnerTeam = nil
        end
        if winnerTeam ~= nil then
            local myTeam = MT.GetMyShuffleTeamIndex()
            if myTeam ~= nil then
                round.won = (winnerTeam == myTeam)
                round.draw = nil
                round.incomplete = nil
                round._resolveSource = "GetActiveMatchWinner"
                MT.MatchProbe("ResolveRound", string.format(
                    "won=%s winnerTeam=%s myTeam=%s src=GetActiveMatchWinner",
                    tostring(round.won), tostring(winnerTeam), tostring(myTeam)))
                return
            end
        end
    end
end

-- Class file IDs used when we only know classToken (inspect/talentSpec missing).
function MT.CommitChatFallback(round)
    if not round or round.won ~= nil or round.draw or round.incomplete then return end

    local w = round._chatWinner
    if not w or w == "" then return end

    local me = UnitName("player")
    local meLower = me and me:lower() or ""
    local wClean = ns.AmbiguateName(w) or w
    local wl = (wClean or w):lower()

    if meLower ~= "" and (wl:find(meLower, 1, true) or (w:lower()):find(meLower, 1, true)) then
        round.won = true
    else
        local faction = UnitFactionGroup("player")
        if (faction == "Alliance" and wl:find("alliance", 1, true))
        or (faction == "Horde"    and wl:find("horde", 1, true)) then
            -- Rare: message names the faction instead of a player.
            round.won = true
        else
            -- Another player / other side won this round.
            round.won = false
        end
    end

    round._resolveSource = "chat"
    ns.DebugPrint("Round", round.round, "resolved by chat:",
                  tostring(round.won), "winner:", w)
    MT.MatchProbe("ChatResolve", string.format("won=%s winner=%s", tostring(round.won), tostring(wClean or w)))
end

-- Idempotent round finalization. Every rollover signal (state change,
-- PVP_MATCH_ACTIVE, match end) calls this. The `_finalized` flag ensures a
-- single round can only ever land in MT.pendingMatch.rounds once, no matter
-- how many signals fire — this is what fixes the "9 rounds in a 6-round
-- match" bug.
function MT.FinalizeRound(round, reason)
    if not round or round._finalized then return false end

    local now = time()

    -- API first (GetActiveMatchWinner). Chat only as last-resort fallback.
    MT.TryResolveCurrentRound()
    if round.won == nil and not round.draw then
        MT.CommitChatFallback(round)
    end

    local elapsed = now - (round.startTime or now)
    local nEnemy = (round.enemy and #round.enemy) or 0

    -- City / pre-port lobby only. Short enemy=0 legs on the arena map used to be
    -- thrown away as "staging", which deleted real round 1 and left 5/6 rows.
    -- Keep any leg that ran long enough to be a real fight even if enemy icons
    -- never filled (still counts toward the 6).
    local zone = (MT.pendingMatch and MT.pendingMatch.map) or (GetRealZoneText and GetRealZoneText()) or ""
    local zl = string.lower(zone)
    -- Only true cities / hubs. Holding areas that still run a full engaged
    -- timer (e.g. first leg before a port) must NOT be discarded or we lose R1.
    local isCity = zl:find("silvermoon", 1, true)
        or zl:find("orgrimmar", 1, true)
        or zl:find("stormwind", 1, true)
        or zl:find("dalaran", 1, true)
        or zl:find("valdrakken", 1, true)

    -- Staging = city/hub lobby only. Never drop an arena/BG leg for missing
    -- enemy icons (that was deleting real rounds and leaving 5/6).
    if nEnemy == 0 and reason ~= "match_end" and not round._chatWinner then
        if isCity then
            round._finalized = true
            ns.DebugPrint("Discarding staging round (no enemies)", round.round, zone, elapsed)
            MT.MatchProbe("FinalizeRound", "discard=staging total=" .. tostring(#(MT.pendingMatch and MT.pendingMatch.rounds or {})))
            return false
        end
        MT.MatchProbe("FinalizeRound", "keepEmptyEnemy elapsed=" .. tostring(elapsed) .. " map=" .. tostring(zone))
    end

    -- RecoverRound/ForceClose phantoms are ~1–5s. Real shuffle legs are far longer.
    if elapsed < 15 and reason ~= "match_end" then
        round._finalized = true
        ns.DebugPrint("Discarding phantom round", round.round, "elapsed:", elapsed)
        MT.MatchProbe("FinalizeRound", "discard=phantom elapsed=" .. tostring(elapsed)
            .. " total=" .. tostring(#(MT.pendingMatch and MT.pendingMatch.rounds or {})))
        return false
    end

    round._finalized = true
    round.duration = math.max(1, elapsed)

    local hasOutcome = (round.won ~= nil) or round.draw or round.incomplete
    local hasChat    = round._chatWinner ~= nil

    if not (hasOutcome or hasChat or elapsed >= 15 or reason == "match_end") then
        ns.DebugPrint("Discarding empty round", round.round, "elapsed:", elapsed)
        MT.MatchProbe("FinalizeRound", "discard=empty total=" .. tostring(#(MT.pendingMatch and MT.pendingMatch.rounds or {})))
        return false
    end

    -- If still no outcome after resolve + chat, mark incomplete so history
    -- does not show a silent nil forever.
    if round.won == nil and not round.draw and not round.incomplete then
        round.incomplete = true
    end

    table.insert(MT.pendingMatch.rounds, round)
    MT.MatchProbe("FinalizeRound", string.format(
        "reason=%s won=%s total=%d",
        tostring(reason), tostring(round.won), #MT.pendingMatch.rounds))
    return true
end