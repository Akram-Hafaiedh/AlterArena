local ADDON_NAME, ns = ...

-- v0.1 scope: record match outcome (win/loss), bracket, and rating delta
-- per character. Deeper per-match detail (opponents, damage/healing,
-- comp data) is a stretch goal for a later version once this foundation
-- is confirmed working in-client.

local pendingMatch = nil

local function EnsurePVPInfo()
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

-- WoW 12.x returns "secret values" for enemy GUIDs and names during arena
-- matches. A secret value cannot be used as a table key or passed to most
-- string functions. This helper returns true only when a value is safe to
-- use as an index.
local function IsIndexable(v)
    if v == nil then return false end
    if issecretvalue then
        return not issecretvalue(v)
    end
    return true
end

-- WoW 12.x seals many scoreboard fields as "secret values". Reading them is
-- fine, but using them as table keys, in arithmetic, or in comparisons will
-- throw. These helpers return nil for anything we can't safely use.
local function IsSecret(v)
    return v ~= nil and issecretvalue and issecretvalue(v) or false
end

local function SafeValue(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local function SafeNumber(v)
    v = SafeValue(v)
    if v == nil then return nil end
    return tonumber(v)
end

local function SafeString(v)
    v = SafeValue(v)
    if v == nil then return nil end
    if type(v) ~= "string" then return nil end
    return v
end

-- Returns the current PvP season number, or nil if the API isn't available.
-- Used to tag each match so we can filter by season later.
local function GetCurrentSeasonId()
    -- Retail 10.x / 11.x: C_Seasons API
    if C_Seasons and C_Seasons.GetActiveSeason then
        local ok, seasonID = pcall(C_Seasons.GetActiveSeason)
        if ok and seasonID and type(seasonID) == "number" then
            return seasonID
        end
    end
    -- Legacy fallback (still present in some builds)
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
                -- Blizzard has shipped the shuffle bracket under several names
                -- across patches: "Solo Shuffle", "Solo", "Rated Solo Shuffle".
                if string.find(lower, "shuffle") or lower == "solo" then return "Solo Shuffle" end
                if string.find(lower, "blitz") then return "Blitz" end
                return str
            end
        end
    end

    local fallbackNames = {
        [1] = "2v2",
        [2] = "3v3",
        [3] = "10v10",
        [4] = "10v10",
        [7] = "Solo Shuffle",
        [8] = "Blitz",
        [9] = "Blitz",
    }
    return fallbackNames[bracketIndex] or ("Bracket " .. tostring(bracketIndex))
end

-- Comprehensive Spec ID, Class, and Icon Mapping
local specCache = {}
local knownSpecIDs = {
    62, 63, 64, 65, 66, 70, 71, 72, 73, 102, 103, 104, 105,
    250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260,
    261, 262, 263, 264, 265, 266, 267, 268, 269, 270,
    577, 581, 1467, 1468, 1473
}

local fallbackSpecIcons = {
    -- WARLOCK
    ["WARLOCK_destruction"] = 136186, ["WARLOCK_affliction"] = 136145, ["WARLOCK_demonology"] = 136172,
    -- PRIEST
    ["PRIEST_discipline"] = 135976, ["PRIEST_holy"] = 237542, ["PRIEST_shadow"] = 136207,
    -- PALADIN
    ["PALADIN_holy"] = 135920, ["PALADIN_protection"] = 236264, ["PALADIN_retribution"] = 135873,
    -- MAGE
    ["MAGE_arcane"] = 135932, ["MAGE_fire"] = 135810, ["MAGE_frost"] = 135846,
    -- DEATHKNIGHT
    ["DEATHKNIGHT_blood"] = 135770, ["DEATHKNIGHT_frost"] = 135773, ["DEATHKNIGHT_unholy"] = 135775,
    -- SHAMAN
    ["SHAMAN_elemental"] = 136048, ["SHAMAN_enhancement"] = 136051, ["SHAMAN_restoration"] = 136052,
    -- DRUID
    ["DRUID_balance"] = 136096, ["DRUID_feral"] = 136036, ["DRUID_guardian"] = 132115, ["DRUID_restoration"] = 136041,
    -- WARRIOR
    ["WARRIOR_arms"] = 132355, ["WARRIOR_fury"] = 132347, ["WARRIOR_protection"] = 132341,
    -- ROGUE
    ["ROGUE_assassination"] = 132292, ["ROGUE_outlaw"] = 132298, ["ROGUE_subtlety"] = 132320,
    -- MONK
    ["MONK_brewmaster"] = 608951, ["MONK_windwalker"] = 608953, ["MONK_mistweaver"] = 608952,
    -- DEMONHUNTER
    ["DEMONHUNTER_havoc"] = 1247264, ["DEMONHUNTER_vengeance"] = 1247265,
    -- HUNTER
    ["HUNTER_beast mastery"] = 132164, ["HUNTER_marksmanship"] = 132222, ["HUNTER_survival"] = 132215,
    -- EVOKER
    ["EVOKER_devastation"] = 4576180, ["EVOKER_preservation"] = 4576181, ["EVOKER_augmentation"] = 5197072,
}

for key, icon in pairs(fallbackSpecIcons) do
    specCache[key] = icon
end

-- Default ambiguous fallbacks if class token is not provided
specCache["destruction"] = 136186
specCache["affliction"] = 136145
specCache["demonology"] = 136172
specCache["discipline"] = 135976
specCache["shadow"] = 136207
specCache["retribution"] = 135873
specCache["arcane"] = 135932
specCache["fire"] = 135810
specCache["blood"] = 135770
specCache["unholy"] = 135775
specCache["elemental"] = 136048
specCache["enhancement"] = 136051
specCache["balance"] = 136096
specCache["feral"] = 136036
specCache["guardian"] = 132115
specCache["arms"] = 132355
specCache["fury"] = 132347
specCache["assassination"] = 132292
specCache["outlaw"] = 132298
specCache["subtlety"] = 132320
specCache["brewmaster"] = 608951
specCache["windwalker"] = 608953
specCache["mistweaver"] = 608952
specCache["havoc"] = 1247264
specCache["vengeance"] = 1247265
specCache["beast mastery"] = 132164
specCache["marksmanship"] = 132222
specCache["survival"] = 132215
specCache["devastation"] = 4576180
specCache["preservation"] = 4576181
specCache["augmentation"] = 5197072

if GetSpecializationInfoByID then
    for _, id in ipairs(knownSpecIDs) do
        local _, name, _, icon, _, classToken = GetSpecializationInfoByID(id)
        if name and icon then
            specCache[id] = icon
            if classToken then
                local cKey = classToken:upper() .. "_" .. name:lower()
                specCache[cKey] = icon
            end
        end
    end
end

-- Live detected specs for players during active match
local detectedPlayerSpecs = {}

-- Signature spells that conclusively identify a player's spec
local signatureSpells = {
    [116858] = { spec = "Destruction", icon = 136186, class = "WARLOCK" },
    [324536] = { spec = "Affliction", icon = 136145, class = "WARLOCK" },
    [105174] = { spec = "Demonology", icon = 136172, class = "WARLOCK" },
    [47540]  = { spec = "Discipline", icon = 135976, class = "PRIEST" },
    [88625]  = { spec = "Holy", icon = 237542, class = "PRIEST" },
    [2944]   = { spec = "Shadow", icon = 136207, class = "PRIEST" },
    [20473]  = { spec = "Holy", icon = 135920, class = "PALADIN" },
    [31935]  = { spec = "Protection", icon = 236264, class = "PALADIN" },
    [184575] = { spec = "Retribution", icon = 135873, class = "PALADIN" },
    [12042]  = { spec = "Arcane", icon = 135932, class = "MAGE" },
    [190319] = { spec = "Fire", icon = 135810, class = "MAGE" },
    [12472]  = { spec = "Frost", icon = 135846, class = "MAGE" },
    [51505]  = { spec = "Elemental", icon = 136048, class = "SHAMAN" },
    [17364]  = { spec = "Enhancement", icon = 136051, class = "SHAMAN" },
    [61295]  = { spec = "Restoration", icon = 136052, class = "SHAMAN" },
    [78674]  = { spec = "Balance", icon = 136096, class = "DRUID" },
    [1079]   = { spec = "Feral", icon = 136036, class = "DRUID" },
    [22842]  = { spec = "Guardian", icon = 132115, class = "DRUID" },
    [18562]  = { spec = "Restoration", icon = 136041, class = "DRUID" },
    [12294]  = { spec = "Arms", icon = 132355, class = "WARRIOR" },
    [23881]  = { spec = "Fury", icon = 132347, class = "WARRIOR" },
    [23922]  = { spec = "Protection", icon = 132341, class = "WARRIOR" },
    [1329]   = { spec = "Assassination", icon = 132292, class = "ROGUE" },
    [185763] = { spec = "Outlaw", icon = 132298, class = "ROGUE" },
    [185313] = { spec = "Subtlety", icon = 132320, class = "ROGUE" },
    [121253] = { spec = "Brewmaster", icon = 608951, class = "MONK" },
    [107428] = { spec = "Windwalker", icon = 608953, class = "MONK" },
    [124682] = { spec = "Mistweaver", icon = 608952, class = "MONK" },
    [49998]  = { spec = "Blood", icon = 135770, class = "DEATHKNIGHT" },
    [49020]  = { spec = "Frost", icon = 135773, class = "DEATHKNIGHT" },
    [275699] = { spec = "Unholy", icon = 135775, class = "DEATHKNIGHT" },
    [198013] = { spec = "Havoc", icon = 1247264, class = "DEMONHUNTER" },
    [204021] = { spec = "Vengeance", icon = 1247265, class = "DEMONHUNTER" },
    [34026]  = { spec = "Beast Mastery", icon = 132164, class = "HUNTER" },
    [19434]  = { spec = "Marksmanship", icon = 132222, class = "HUNTER" },
    [190925] = { spec = "Survival", icon = 132215, class = "HUNTER" },
    [357208] = { spec = "Devastation", icon = 4576180, class = "EVOKER" },
    [355936] = { spec = "Preservation", icon = 4576181, class = "EVOKER" },
    [403631] = { spec = "Augmentation", icon = 5197072, class = "EVOKER" },
}

function ns.GetSpecIcon(specNameOrID, classFilename)
    if not specNameOrID then return nil end
    if type(specNameOrID) == "number" then
        if specCache[specNameOrID] then return specCache[specNameOrID] end
        if GetSpecializationInfoByID then
            local _, _, _, ic = GetSpecializationInfoByID(specNameOrID)
            if ic then return ic end
        end
    end

    local cToken = classFilename and tostring(classFilename):upper()
    local sName = tostring(specNameOrID):lower()

    if cToken and cToken ~= "" then
        local compoundKey = cToken .. "_" .. sName
        if specCache[compoundKey] then
            return specCache[compoundKey]
        end
    end

    return specCache[sName]
end

local function AmbiguateName(name)
    if not name then return "" end
    if not IsIndexable(name) then return "" end
    if Ambiguate then
        local ok, result = pcall(Ambiguate, name, "none")
        if ok and result then return result end
        return ""
    end
    local ok, result = pcall(string.match, name, "^([^%-]+)")
    if ok and result then return result end
    return ""
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
            m.bracket = "Solo Shuffle"
        end
        if not m.spec then
            m.spec = record.spec or "Destruction"
            m.specIcon = record.specIcon or 136186
        end
        if not m.map or m.map == "" then
            m.map = "Arena"
        end

        -- Solo Shuffle: prefer a full 3-icon team from per-round data so the
        -- history row can show [icon][icon][icon] vs [icon][icon][icon].
        -- Only fall back to "player only" when no round composition exists.
        local isShuffle = (m.bracket == "Solo Shuffle" or m.bracket == "Shuffle")
        if isShuffle then
            local playerName = UnitName("player") or record.name or "Player"
            local playerSpec = record.spec or (m.team and m.team[1] and m.team[1].spec)
            local playerIcon = record.specIcon or (m.team and m.team[1] and m.team[1].icon)
            local _, playerClass = UnitClass("player")
            playerClass = playerClass or record.class or (m.team and m.team[1] and m.team[1].class)

            local bestTeam, bestEnemy = nil, nil
            if m.rounds and #m.rounds > 0 then
                for _, rd in ipairs(m.rounds) do
                    if rd.team and #rd.team >= 2 and (not bestTeam or #rd.team > #bestTeam) then
                        bestTeam = rd.team
                    end
                    if rd.enemy and #rd.enemy >= 1 and (not bestEnemy or #rd.enemy > #bestEnemy) then
                        bestEnemy = rd.enemy
                    end
                end
            end

            if bestTeam and #bestTeam >= 2 then
                local teamMembers = {}
                for _, ic in ipairs(bestTeam) do
                    if type(ic) == "number" then
                        table.insert(teamMembers, { icon = ic })
                    elseif type(ic) == "table" then
                        table.insert(teamMembers, ic)
                    end
                    if #teamMembers >= 3 then break end
                end
                if #teamMembers > 0 then
                    m.team = teamMembers
                end
            elseif not m.team or #m.team == 0 then
                m.team = { { name = playerName, spec = playerSpec, icon = playerIcon, class = playerClass } }
            end

            if bestEnemy and #bestEnemy >= 1 then
                local enemyMembers = {}
                for _, ic in ipairs(bestEnemy) do
                    if type(ic) == "number" then
                        table.insert(enemyMembers, { icon = ic })
                    elseif type(ic) == "table" then
                        table.insert(enemyMembers, ic)
                    end
                    if #enemyMembers >= 3 then break end
                end
                if #enemyMembers > 0 then
                    m.enemyTeam = enemyMembers
                end
            elseif m.enemyTeam and #m.enemyTeam > 0 then
                local cleanEnemy = {}
                local seen = {}
                for _, mem in ipairs(m.enemyTeam) do
                    local memName = mem.name and AmbiguateName(mem.name)
                    local isSelf = (memName and memName:lower() == playerName:lower())
                    if not isSelf then
                        local key = (memName and memName ~= "" and memName:lower()) or (tostring(mem.spec) .. "_" .. tostring(mem.class or ""))
                        if not seen[key] then
                            seen[key] = true
                            local ic = ns.GetSpecIcon(mem.spec, mem.class)
                            if ic then mem.icon = ic end
                            table.insert(cleanEnemy, mem)
                            if #cleanEnemy >= 5 then break end
                        end
                    end
                end
                m.enemyTeam = cleanEnemy
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
local function ExtractRoundsWon(info)
    if not info then return nil end

    if info.stats then
        -- 1. Try to resolve the victory stat ID safely.
        local victoryID = nil
        if C_PvP and C_PvP.GetCustomVictoryStatID then
            local ok, id = pcall(C_PvP.GetCustomVictoryStatID)
            if ok then victoryID = SafeNumber(id) end
        end

        -- 2. Match by victory stat ID (if we could resolve it)
        if victoryID then
            for _, stat in ipairs(info.stats) do
                local statID = SafeNumber(stat and stat.pvpStatID)
                if statID and statID == victoryID then
                    local v = SafeNumber(stat.pvpStatValue)
                    if v then return v end
                end
            end
        end

        -- 3. Match by stat name (Victory / Win / Round)
        for _, stat in ipairs(info.stats) do
            local sname = SafeString(stat and stat.name)
            if sname and sname ~= "" then
                local n = sname:lower()
                if n:find("victory") or n:find("win") or n:find("round") then
                    local v = SafeNumber(stat.pvpStatValue)
                    if v then return v end
                end
            end
        end

        -- 4. Single-stat fallback for shuffle: only one stat per player.
        --    If it exists and isn't secret, use it.
        local firstStat = info.stats[1]
        if firstStat then
            local v = SafeNumber(firstStat.pvpStatValue)
            if v then return v end
        end
    end

    -- Legacy fallback for older clients.
    if info.roundStats then
        local v = SafeNumber(info.roundStats.roundsWon)
        if v then return v end
    end

    return nil
end


-- Per-round scoreboard snapshot. Called at the START of each round.
-- Captures each player's cumulative roundsWon so we can diff it when the
-- round ends. Keys are GUIDs (or names as fallback).
local function SnapshotScoreboard()
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
            local name = SafeString(info.name)
            local key  = name or ("slot_" .. i)

            local roundsWon = ExtractRoundsWon(info) or 0
            snap[key] = {
                name = name or key,
                roundsWon = roundsWon,
            }
        end
    end
    return snap
end

-- True when a snapshot has no players in it (scoreboard hasn't been pushed yet)
local function IsSnapEmpty(snap)
    if not snap then return true end
    return next(snap) == nil
end

-- Diff two scoreboard snapshots and record per-round winners into the round.
-- Called at END of round (when the next PVP_MATCH_ACTIVE fires).
local function ApplyRoundOutcome(round, beforeSnap, afterSnap)
    if not round or not beforeSnap or not afterSnap then return end

    -- Build a set of names whose roundsWon incremented since last snapshot.
    local winners = {}
    for key, after in pairs(afterSnap) do
        local before = beforeSnap[key]
        local beforeWon = before and before.roundsWon or 0
        if after.roundsWon > beforeWon then
            winners[after.name] = true
        end
    end

    -- Was the local player among the winners?
    local playerName = UnitName("player")
    if playerName and winners[playerName] then
        round.won = true
    else
        -- If at least 3 players' counts incremented and ours wasn't among
        -- them, we know we lost. If fewer than 3 incremented, the snapshot
        -- is likely incomplete — either the scoreboard hadn't refreshed, or
        -- the round was abandoned mid-fight (someone left). In that case
        -- mark the round as incomplete rather than recording a fabricated
        -- loss.
        local count = 0
        for _ in pairs(winners) do count = count + 1 end
        if count >= 3 then
            round.won = false
        else
            round.incomplete = true
        end
    end

    ns.DebugPrint("Round", round.round, "outcome resolved:",
                  tostring(round.won), "winners:", (function()
                      local t = {}
                      for n in pairs(winners) do t[#t+1] = n end
                      return table.concat(t, ", ")
                  end)())
end

-- Re-entrant resolver. Safe to call any number of times per round.
-- Uses both the scoreboard delta AND the match state to decide the outcome:
--   - my delta > 0                                    -> win
--   - state >= 4, total delta >= 3, my delta == 0     -> loss
--   - state >= 4, total delta == 0                    -> draw
-- Otherwise the round is still in progress and we wait.
local function TryResolveCurrentRound()
    if not pendingMatch or not pendingMatch.currentRound then return end
    local round = pendingMatch.currentRound
    if round.won ~= nil or round.draw or round.incomplete then return end

    local base = pendingMatch.roundStartSnap
    if IsSnapEmpty(base) then
        -- No baseline yet. Patch 4 keeps retrying it.
        return
    end

    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end
    local after = SnapshotScoreboard()
    if IsSnapEmpty(after) then
        ns.DebugPrint("TryResolve: scoreboard empty, retry later")
        return
    end

    local playerName = UnitName("player")
    local myDelta, totalDelta, winners = 0, 0, {}

    for key, a in pairs(after) do
        local b = base[key]
        local before = (b and b.roundsWon) or 0
        local delta  = (a.roundsWon or 0) - before
        if delta > 0 then
            totalDelta = totalDelta + delta
            winners[a.name] = delta
            if playerName and a.name == playerName then
                myDelta = delta
            end
        end
    end

    if totalDelta == 0 then
        ns.DebugPrint("TryResolve: no delta yet")
        return
    end

    local state = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState() or 0

    if myDelta and myDelta > 0 then
        round.won = true
    elseif state >= 4 and totalDelta >= 3 then
        round.won = false
    elseif state >= 4 and totalDelta == 0 then
        round.draw = true
    else
        ns.DebugPrint("TryResolve: waiting for PostRound (state=", state, ")")
        return
    end

    local names = {}
    for n, d in pairs(winners) do table.insert(names, n .. "=" .. tostring(d)) end
    ns.DebugPrint("Round", round.round, "resolved:",
                  tostring(round.won), "draw:", tostring(round.draw),
                  "myDelta:", myDelta, "totalDelta:", totalDelta,
                  "winners:", table.concat(names, ", "))
end

-- Called right before a round is pushed to pendingMatch.rounds. If the
-- scoreboard never resolved the round, fall back to the BG system chat
-- message that Blizzard announces after each round.
local function CommitChatFallback(round)
    if not round or round.won ~= nil or round.draw or round.incomplete then return end

    local w = round._chatWinner
    if not w or w == "" then return end

    local me = UnitName("player")
    if me and w:find(me, 1, true) then
        round.won = true
    else
        local faction = UnitFactionGroup("player")
        local wl = w:lower()
        if (faction == "Alliance" and wl:find("alliance", 1, true))
        or (faction == "Horde"    and wl:find("horde", 1, true)) then
            round.won = true
        else
            round.won = false
        end
    end

    ns.DebugPrint("Round", round.round, "resolved by chat fallback:",
                  tostring(round.won), "winner:", w)
end

-- Idempotent round finalization. Every rollover signal (state change,
-- PVP_MATCH_ACTIVE, match end) calls this. The `_finalized` flag ensures a
-- single round can only ever land in pendingMatch.rounds once, no matter
-- how many signals fire — this is what fixes the "9 rounds in a 6-round
-- match" bug.
local function FinalizeRound(round, reason)
    if not round or round._finalized then return false end
    round._finalized = true

    local now = time()

    -- Per-round duration only. NOT C_PvP.GetPVPActiveMatchDuration() (that
    -- returns the whole match, which is why every duplicate used to show
    -- the same number).
    round.duration = math.max(1, now - (round.startTime or now))

    TryResolveCurrentRound()
    CommitChatFallback(round)

    -- Reject fully-empty phantom rounds produced by stray signals.
    -- A real round has an outcome, a chat hint, or clearly played (>= 10s).
    -- Exception: the very last round on match end always counts, even if
    -- someone left inside the first 10 seconds.
    local elapsed    = now - (round.startTime or now)
    local hasOutcome = (round.won ~= nil) or round.draw or round.incomplete
    local hasChat    = round._chatWinner ~= nil

    if not (hasOutcome or hasChat or elapsed >= 10 or reason == "match_end") then
        ns.DebugPrint("Discarding empty round", round.round, "elapsed:", elapsed)
        return false
    end

    table.insert(pendingMatch.rounds, round)
    return true
end

local function OnMatchStart()
    ns.DebugPrint("OnMatchStart, pendingMatch =", pendingMatch)
    EnsurePVPInfo()
    local qDur = (ns.GetLastQueueDuration and ns.GetLastQueueDuration()) or ns.lastQueueDuration
    local now = time()
    local currentZone = GetRealZoneText() or "Arena"

    -- Solo Shuffle round transition check:
    -- If already in a pending match in the same zone within the last 40 minutes, treat as next round
    if pendingMatch and pendingMatch.map == currentZone and (now - (pendingMatch.matchStartTime or pendingMatch.startTime or now)) < 2400 then
        -- Finalize previous round (idempotent — see FinalizeRound)
        if pendingMatch.currentRound then
            FinalizeRound(pendingMatch.currentRound, "next_round")
            pendingMatch.currentRound = nil
        end
    else
        -- Brand new match
        pendingMatch = {
            startTime = now,
            matchStartTime = now,
            ratingBefore = CaptureRatingSnapshot(),
            isRated = (C_PvP.IsRatedArena and C_PvP.IsRatedArena()) or false,
            map = currentZone,
            queueDuration = qDur,
            rounds = {},
            roundIndex = 0,
        }
    end

    local rIdx = (pendingMatch.roundIndex or 0) + 1
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

        local snap = SnapshotScoreboard()

        if IsSnapEmpty(snap) and attempt < 5 then
            C_Timer.After(1.0, function() CaptureBaseline(attempt + 1) end)
            return
        end

        if IsSnapEmpty(pendingMatch.roundStartSnap) then
            pendingMatch.roundStartSnap = snap
        end

        local c = 0
        for _ in pairs(pendingMatch.roundStartSnap) do c = c + 1 end
        ns.DebugPrint("Round", rIdx, "baseline ready:", c, "players (attempt", attempt .. ")")
    end

    C_Timer.After(1.0, function() CaptureBaseline(1) end)
    -- Capture enemy arena opponent specs after gate opens
    C_Timer.After(2, function()
        if pendingMatch and pendingMatch.currentRound and pendingMatch.currentRound.round == rIdx then
            if GetNumArenaOpponents then
                local numOpp = GetNumArenaOpponents()
                for i = 1, math.min(numOpp or 3, 3) do
                    local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
                    if specID and specID > 0 then
                        local _, _, _, specIcon = GetSpecializationInfoByID(specID)
                        if specIcon and #pendingMatch.currentRound.enemy < 3 then
                            table.insert(pendingMatch.currentRound.enemy, specIcon)
                        end
                    end
                end
            end
        end
    end)

    -- Capture teammate specs. In Solo Shuffle party1/party2 are your
    -- teammates for the current round. GetInspectSpecialization often
    -- returns 0 until NotifyInspect has completed, so we request inspect
    -- and retry a couple of times.
    local function CaptureTeammates(attempt)
        if not pendingMatch or not pendingMatch.currentRound then return end
        if pendingMatch.currentRound.round ~= rIdx then return end
        local round = pendingMatch.currentRound
        attempt = attempt or 1

        -- Own spec ID: GetSpecializationInfo's FIRST return is the specID.
        local mySpecID = nil
        if GetSpecialization and GetSpecializationInfo then
            local sIdx = GetSpecialization()
            if sIdx then
                local id = GetSpecializationInfo(sIdx)
                if id and id > 0 then mySpecID = id end
            end
        end
        if not mySpecID and GetInspectSpecialization then
            local ok, id = pcall(GetInspectSpecialization, "player")
            if ok and id and id > 0 then mySpecID = id end
        end

        -- Path A (preferred): party1 / party2 are teammates in arena.
        for i = 1, 2 do
            local unit = "party" .. i
            if UnitExists(unit) then
                if NotifyInspect and CanInspect and CanInspect(unit) then
                    pcall(NotifyInspect, unit)
                end
                local specID = nil
                if GetInspectSpecialization then
                    local ok, id = pcall(GetInspectSpecialization, unit)
                    if ok and id and id > 0 then specID = id end
                end
                if specID and specID > 0 then
                    local _, _, _, sIcon = GetSpecializationInfoByID(specID)
                    if sIcon then
                        local already = false
                        for _, existing in ipairs(round.team) do
                            if existing == sIcon then already = true; break end
                        end
                        if not already and #round.team < 3 then
                            table.insert(round.team, sIcon)
                        end
                    end
                end
            end
        end

        -- Path B (fallback): raid-unit arithmetic when party units failed.
        if #round.team < 3 then
            local enemySpecCounts = {}
            local numEnemies = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
            for i = 1, math.min(numEnemies, 3) do
                local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
                if specID and specID > 0 then
                    enemySpecCounts[specID] = (enemySpecCounts[specID] or 0) + 1
                end
            end

            local allRaidSpecs = {}
            local numGroup = (GetNumGroupMembers and GetNumGroupMembers()) or 0
            local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
            for i = 1, numGroup do
                local unit = prefix .. i
                if UnitExists(unit) then
                    if NotifyInspect and CanInspect and CanInspect(unit) then
                        pcall(NotifyInspect, unit)
                    end
                    if GetInspectSpecialization then
                        local ok, specID = pcall(GetInspectSpecialization, unit)
                        if ok and specID and specID > 0 then
                            table.insert(allRaidSpecs, specID)
                        end
                    end
                end
            end

            for specID, count in pairs(enemySpecCounts) do
                for _ = 1, count do
                    for k, v in ipairs(allRaidSpecs) do
                        if v == specID then
                            table.remove(allRaidSpecs, k)
                            break
                        end
                    end
                end
            end
            if mySpecID then
                for k, v in ipairs(allRaidSpecs) do
                    if v == mySpecID then
                        table.remove(allRaidSpecs, k)
                        break
                    end
                end
            end
            for _, specID in ipairs(allRaidSpecs) do
                if #round.team >= 3 then break end
                local _, _, _, sIcon = GetSpecializationInfoByID(specID)
                if sIcon then
                    local already = false
                    for _, existing in ipairs(round.team) do
                        if existing == sIcon then already = true; break end
                    end
                    if not already then
                        table.insert(round.team, sIcon)
                    end
                end
            end
        end

        ns.DebugPrint("Round", rIdx, "team captured (attempt", attempt .. "):",
                      #round.team, "icon(s) — expected 3")

        -- Retry while we still have fewer than 3 icons (inspect lag).
        if #round.team < 3 and attempt < 3 then
            C_Timer.After(2.0, function() CaptureTeammates(attempt + 1) end)
        else
            round.teamCaptured = true
        end
    end

    C_Timer.After(2.5, function() CaptureTeammates(1) end)
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
            local infoName = SafeString(info.name)
            local cleanInfoName = infoName and AmbiguateName(infoName) or nil
            local isPlayer = (infoName and (infoName == playerName
                                            or infoName == playerFullName
                                            or cleanInfoName == playerName)) or false

            local infoTeam = SafeNumber(info.team) or SafeNumber(info.faction)

            if isPlayer then
                foundPlayer = true
                playerTeam = infoTeam

                local rChange = SafeNumber(info.ratingChange)
                if rChange and rChange ~= 0 then
                    matchEntry.ratingChange = rChange
                    if matchEntry.ratingBefore then
                        matchEntry.ratingAfter = matchEntry.ratingBefore + rChange
                    end
                end

                local preMMR  = SafeNumber(info.prematchMMR)
                local postMMR = SafeNumber(info.postmatchMMR)
                local mmrChg  = SafeNumber(info.mmrChange)
                if preMMR and preMMR > 0 then
                    matchEntry.mmrBefore = preMMR
                    matchEntry.mmrAfter  = postMMR or (preMMR + (mmrChg or 0))
                    matchEntry.mmrChange = mmrChg or (matchEntry.mmrAfter - matchEntry.mmrBefore)

                    if record and record.bracketRatings and record.bracketRatings["Shuffle"] then
                        record.bracketRatings["Shuffle"].mmr = matchEntry.mmrAfter
                    end
                end

                local pWins = ExtractRoundsWon(info)
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

            -- Track most wins and most deaths. Both ExtractRoundsWon and
            -- info.deaths may return nil if the underlying values are secret.
            local wins = ExtractRoundsWon(info) or 0
            if wins > mostWinsCount then
                mostWinsCount = wins
                mostWinsName = cleanInfoName or infoName or "Player"
                local cToken = SafeString(info.classToken)
                if cToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cToken] then
                    mostWinsColor = RAID_CLASS_COLORS[cToken].colorStr or "ffffffff"
                end
            end

            local deaths = SafeNumber(info.deaths) or 0
            if deaths > mostDeathsCount then
                mostDeathsCount = deaths
                mostDeathsName = cleanInfoName or infoName or "Player"
                local cToken = SafeString(info.classToken)
                if cToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cToken] then
                    mostDeathsColor = RAID_CLASS_COLORS[cToken].colorStr or "ffffffff"
                end
            end

            local cToken = (SafeString(info.classToken) or ""):upper()
            local sName  = SafeString(info.talentSpec) or SafeString(info.specName)
            local sIcon  = (sName and ns.GetSpecIcon and ns.GetSpecIcon(sName, cToken))

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
                local m = SafeNumber(info.postmatchMMR) or SafeNumber(info.prematchMMR)
                if m and m > 0 then
                    enemyTotal = enemyTotal + m
                    enemyCount = enemyCount + 1
                end
            elseif infoTeam and playerTeam and infoTeam == playerTeam then
                table.insert(teamList, member)
            else
                local eKey = (member.name and member.name:lower()) or (tostring(sName) .. "_" .. tostring(cToken))
                if not enemySeen[eKey] then
                    enemySeen[eKey] = true
                    table.insert(enemyList, member)
                end
                local m = SafeNumber(info.postmatchMMR) or SafeNumber(info.prematchMMR)
                if m and m > 0 then
                    enemyTotal = enemyTotal + m
                    enemyCount = enemyCount + 1
                end
            end
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
    for bracketIndex, before in pairs(pendingRatingBefore or {}) do
        local after = ratingAfter[bracketIndex]
        if after then
            local playedChanged = (after.seasonPlayed ~= before.seasonPlayed)
                              or (after.roundsPlayed ~= before.roundsPlayed)
            local ratingChanged = (after.rating ~= before.rating)
            if playedChanged or ratingChanged then
                matchEntry.bracket = GetBracketName(bracketIndex)
                matchEntry.ratingBefore = before.rating
                matchEntry.ratingAfter = after.rating
                matchEntry.ratingChange = after.rating - before.rating
                if after.roundsPlayed and before.roundsPlayed
                   and after.roundsPlayed > before.roundsPlayed then
                    matchEntry.roundsPlayed = after.roundsPlayed - before.roundsPlayed
                    matchEntry.roundsWon = (after.roundsWon or 0) - (before.roundsWon or 0)
                end
                return true
            end
        end
    end
    return false
end

local function OnMatchComplete()
    if not pendingMatch then
        return
    end

    ns.DebugPrint("OnMatchComplete fired, rounds recorded =", #pendingMatch.rounds)

    -- Final resolve attempt for the last round. Fires before we tear
    -- pendingMatch down.
    TryResolveCurrentRound()

    local record = ns.EnsurePlayerRecord()
    local now = time()

    -- Finalize last active round
    if pendingMatch.currentRound then
        FinalizeRound(pendingMatch.currentRound, "match_end")
        pendingMatch.currentRound = nil
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
    local detectedBracket = "Solo Shuffle"
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

    ns.DebugPrint("snapshotDiffFound =", snapshotDiffFound, "bracket =", detectedBracket, "ratingChange =", ratingChangeVal)

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

    -- Request server scoreboard data
    if RequestBattlefieldScoreData then
        RequestBattlefieldScoreData()
    end
    UpdateFromScoreboard(matchEntry, record)

    -- Determine outcome. Thresholds scale with the actual number of rounds
    -- played so early-termination matches (someone left) resolve correctly.
    --
    -- Full 6-round match:   4+ = Win, 3 = Draw, 0-2 = Loss
    -- 5-round partial:      3+ = Win, 2.5 = n/a, 0-2 = Loss
    -- 4-round partial:      3+ = Win, 2   = Draw, 0-1 = Loss
    -- 3-round partial:      2+ = Win, 1.5 = n/a, 0-1 = Loss
    -- 2-round partial:      2  = Win, 1   = Draw, 0   = Loss
    -- 1-round partial:      1  = Win, n/a = n/a, 0   = Loss
    --
    -- In practice Blizzard counts any partial ≥1 round as valid; the
    -- thresholds below mirror what the client shows on the scoreboard.
    if matchEntry.roundsWon ~= nil then
        local played = matchEntry.roundsPlayed or 6
        local winThreshold = math.floor(played / 2) + 1  -- 4 for 6, 3 for 4, 2 for 3, 1 for 1
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
    else
        matchEntry.won = nil
    end

    table.insert(record.matches, matchEntry)
    ns.DebugPrint("Match recorded — bracket:", matchEntry.bracket, "won:", tostring(matchEntry.won), "ratingChange:", matchEntry.ratingChange)

    -- Setup background poller to ensure rating diff is captured when server updates
    local savedPending = pendingMatch
    local pollCount = 0
    local function PollRating()
        pollCount = pollCount + 1
        if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
        local scoreUpdated = UpdateFromScoreboard(matchEntry, record)
        local snapUpdated = CheckRatingSnapshotDiff(matchEntry, savedPending.ratingBefore)

        ns.DebugPrint("UpdateFromScoreboard done, roundsWon =", matchEntry.roundsWon, "ratingChange =", matchEntry.ratingChange)
        
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
    pendingMatch = nil

    if ns.RefreshUI then
        ns.RefreshUI()
    end
end

function ns.InitMatchTracker()
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

    -- Per-round win/loss detection for Solo Shuffle. Blizzard announces
    -- "Round N won by <name>" on the BG system channel at the end of each
    -- round. All three faction variants are hooked in case the message
    -- routes through a different one on non-standard clients.
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_NEUTRAL")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_ALLIANCE")
    frame:RegisterEvent("CHAT_MSG_BG_SYSTEM_HORDE")

    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "CHAT_MSG_BG_SYSTEM_NEUTRAL"
           or event == "CHAT_MSG_BG_SYSTEM_ALLIANCE"
           or event == "CHAT_MSG_BG_SYSTEM_HORDE" then
            local msg = ...
            -- Format: "Round 1 won by Mogambala" / "Round 1 won by the Horde"
            -- We only care about strings containing "won by" while a match is
            -- in progress.
                        -- Detect early termination.
            if pendingMatch and msg
               and (msg:find("has left", 1, true)
                    or msg:find("has fled", 1, true)
                    or msg:find("abandoned", 1, true)) then
                pendingMatch.earlyTermination = true
                ns.DebugPrint("Early termination detected:", msg)
            end

            if pendingMatch and msg and msg:find("won by", 1, true) then
                local roundNum = tonumber(msg:match("Round%s+(%d+)"))
                local winner   = msg:match("won by%s+(.+)$")

                if pendingMatch.currentRound and winner and winner ~= "" then
                    -- Store the chat hint ONLY. The scoreboard resolver
                    -- runs first and is authoritative. CommitChatFallback
                    -- uses this only if the scoreboard never resolved.
                    pendingMatch.currentRound._chatWinner = winner
                    if roundNum then
                        pendingMatch.currentRound.round = roundNum
                    end
                    ns.DebugPrint("Round", pendingMatch.currentRound.round,
                                  "chat winner stashed:", winner)
                end
            end

        elseif event == "PVP_MATCH_ACTIVE" then
            OnMatchStart()
        elseif event == "PVP_MATCH_STATE_CHANGED" then
            local state = C_PvP and C_PvP.GetActiveMatchState and C_PvP.GetActiveMatchState() or nil
            ns.DebugPrint("PVP_MATCH_STATE_CHANGED ->", state)

            if pendingMatch and state then
                local lastState = pendingMatch.matchState or 0

                -- Engaged (3) -> PostRound (4) / Complete (5): round is over.
                if state >= 4 and lastState < 4 and pendingMatch.currentRound then
                    FinalizeRound(pendingMatch.currentRound, "post_round")

                    -- Carry the live scoreboard forward as the baseline for
                    -- the next round. This is what makes rounds 2+ reliable.
                    pendingMatch.roundStartSnap = SnapshotScoreboard()
                    pendingMatch.currentRound = nil

                    ns.DebugPrint("Round rolled over at PostRound. Total rounds:", #pendingMatch.rounds)
                end

                pendingMatch.matchState = state
            end
        elseif event == "PVP_MATCH_COMPLETE" then
            OnMatchComplete()
        elseif event == "ARENA_OPPONENT_UPDATE" then
            if GetNumArenaOpponents then
                for i = 1, GetNumArenaOpponents() do
                    local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
                    if specID and specID > 0 and GetSpecializationInfoByID then
                        local _, sName, _, sIcon, _, classToken = GetSpecializationInfoByID(specID)
                        local u = "arena" .. i
                        local guid = UnitGUID(u)
                        local name = UnitName(u)
                        local data = { spec = sName, icon = sIcon, class = classToken }
                        if IsIndexable(guid) then
                            detectedPlayerSpecs[guid] = data
                        end
                        if IsIndexable(name) then
                            detectedPlayerSpecs[name] = data
                            local clean = AmbiguateName(name)
                            if IsIndexable(clean) and clean ~= "" and clean ~= name then
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
                    if classToken and IsIndexable(guid) and not detectedPlayerSpecs[guid] then
                        detectedPlayerSpecs[guid] = { class = classToken }
                        if IsIndexable(name) then
                            detectedPlayerSpecs[name] = { class = classToken }
                            local clean = AmbiguateName(name)
                            if IsIndexable(clean) and clean ~= "" and clean ~= name then
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
                TryResolveCurrentRound()
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

