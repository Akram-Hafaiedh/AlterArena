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

        -- In Solo Shuffle, ensure team contains ONLY the player, and enemyTeam is clean & deduplicated (max 5)
        local isShuffle = (m.bracket == "Solo Shuffle" or m.bracket == "Shuffle")
        if isShuffle then
            local playerName = UnitName("player") or record.name or "Player"
            local playerSpec = record.spec or (m.team and m.team[1] and m.team[1].spec)
            local playerIcon = record.specIcon or (m.team and m.team[1] and m.team[1].icon)
            local _, playerClass = UnitClass("player")
            playerClass = playerClass or record.class or (m.team and m.team[1] and m.team[1].class)

            m.team = { { name = playerName, spec = playerSpec, icon = playerIcon, class = playerClass } }

            if m.enemyTeam and #m.enemyTeam > 0 then
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

    -- Ensure won flag matches rounds or rating change
    for _, m in ipairs(record.matches) do
        if m.roundsWon ~= nil then
            if m.roundsWon >= 4 then
                m.won = true
            elseif m.roundsWon == 3 then
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

local function OnMatchStart()
    ns.DebugPrint("OnMatchStart, pendingMatch =", pendingMatch)
    EnsurePVPInfo()
    local qDur = (ns.GetLastQueueDuration and ns.GetLastQueueDuration()) or ns.lastQueueDuration
    local now = time()
    local currentZone = GetRealZoneText() or "Arena"

    -- Solo Shuffle round transition check:
    -- If already in a pending match in the same zone within the last 40 minutes, treat as next round
    if pendingMatch and pendingMatch.map == currentZone and (now - (pendingMatch.matchStartTime or pendingMatch.startTime or now)) < 2400 then
        -- Finalize previous round
        if pendingMatch.currentRound then
            local rApi = C_PvP and C_PvP.GetPVPActiveMatchDuration and C_PvP.GetPVPActiveMatchDuration()
            local rDur = (rApi and rApi > 0 and math.floor(rApi + 0.5)) or math.max(1, now - (pendingMatch.currentRound.startTime or now))
            pendingMatch.currentRound.duration = rDur
            table.insert(pendingMatch.rounds, pendingMatch.currentRound)
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

    -- Capture teammate specs a bit later than the enemy capture, so the
    -- inspect cache has time to populate. Only runs in Solo Shuffle —
    -- in 2v2/3v3 the team is set once at match start and doesn't rotate.
    C_Timer.After(3.5, function()
        if not pendingMatch or not pendingMatch.currentRound then return end
        if pendingMatch.currentRound.round ~= rIdx then return end
        if pendingMatch.currentRound.teamCaptured then return end
        pendingMatch.currentRound.teamCaptured = true

        local round = pendingMatch.currentRound

        -- Helpers: is a unit the player, or one of the enemies this round?
        local function IsSelf(u)
            return UnitIsUnit(u, "player")
        end
        local function IsEnemy(u)
            local n = (GetNumArenaOpponents and GetNumArenaOpponents()) or 0
            for j = 1, n do
                if UnitIsUnit(u, "arena" .. j) then return true end
            end
            return false
        end

        -- Scan every possible group-unit token. Solo Shuffle puts you in a
        -- raid of 6, but party tokens can appear on some builds, so we
        -- check both. UnitIsUnit is the only identity check that works
        -- with Midnight's secret unit values.
        local function ScanTeam(prefix, maxIndex)
            for i = 1, maxIndex do
                local unit = prefix .. i
                if UnitExists(unit) then
                    if not IsSelf(unit) and not IsEnemy(unit) then
                        local icon = nil
                        if GetInspectSpecialization and GetSpecializationInfoByID then
                            local ok, specID = pcall(GetInspectSpecialization, unit)
                            if ok and specID and specID > 0 then
                                local _, _, _, sIcon = GetSpecializationInfoByID(specID)
                                icon = sIcon
                            end
                        end
                        if icon then
                            table.insert(round.team, icon)
                        end
                    end
                end
            end
        end

        local numGroup = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        if IsInRaid and IsInRaid() then
            ScanTeam("raid", numGroup)
        else
            -- Party path (rare in shuffle, but here for safety)
            ScanTeam("party", math.max(1, numGroup - 1))
        end
    end)
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
            local cleanInfoName = info.name and AmbiguateName(info.name)
            local isPlayer = (info.guid and playerGUID and info.guid == playerGUID)
                          or (info.name and (info.name == playerName or info.name == playerFullName or cleanInfoName == playerName))

            if isPlayer then
                foundPlayer = true
                playerTeam = info.team or info.faction

                if info.ratingChange and info.ratingChange ~= 0 then
                    matchEntry.ratingChange = info.ratingChange
                    if matchEntry.ratingBefore then
                        matchEntry.ratingAfter = matchEntry.ratingBefore + info.ratingChange
                    end
                end

                if info.prematchMMR and info.prematchMMR > 0 then
                    matchEntry.mmrBefore = info.prematchMMR
                    matchEntry.mmrAfter = info.postmatchMMR or (info.prematchMMR + (info.mmrChange or 0))
                    matchEntry.mmrChange = info.mmrChange or (matchEntry.mmrAfter - matchEntry.mmrBefore)

                    if record and record.bracketRatings and record.bracketRatings["Shuffle"] then
                        record.bracketRatings["Shuffle"].mmr = matchEntry.mmrAfter
                    end
                end

                local pWins = info.roundStats and (info.roundStats.roundsWon or info.roundStats.wins)
                if pWins then
                    matchEntry.roundsWon = pWins
                    matchEntry.roundsPlayed = (info.roundStats.roundsPlayed or 6)
                end
            end

            -- Track most wins and most deaths
            local wins = info.roundStats and (info.roundStats.roundsWon or info.roundStats.wins) or 0
            if wins > mostWinsCount then
                mostWinsCount = wins
                mostWinsName = cleanInfoName or info.name or "Player"
                if info.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classToken] then
                    mostWinsColor = RAID_CLASS_COLORS[info.classToken].colorStr or "ffffffff"
                end
            end

            local deaths = info.deaths or 0
            if deaths > mostDeathsCount then
                mostDeathsCount = deaths
                mostDeathsName = cleanInfoName or info.name or "Player"
                if info.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classToken] then
                    mostDeathsColor = RAID_CLASS_COLORS[info.classToken].colorStr or "ffffffff"
                end
            end

            local cToken = (info.classToken or ""):upper()
            local sName = info.talentSpec or info.specName
            local sIcon = (sName and ns.GetSpecIcon and ns.GetSpecIcon(sName, cToken))

            if not sIcon or not sName then
                local d = nil
                if IsIndexable(info.guid) then d = detectedPlayerSpecs[info.guid] end
                if not d and IsIndexable(info.name) then d = detectedPlayerSpecs[info.name] end
                if not d and IsIndexable(cleanInfoName) then d = detectedPlayerSpecs[cleanInfoName] end
                if d then
                    sName = sName or d.spec
                    sIcon = sIcon or d.icon
                    if cToken == "" and d.class then cToken = d.class end
                end
            end

            local member = {
                name = cleanInfoName or info.name,
                spec = sName,
                icon = sIcon,
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
                local m = info.postmatchMMR or info.prematchMMR
                if m and m > 0 then
                    enemyTotal = enemyTotal + m
                    enemyCount = enemyCount + 1
                end
            elseif info.team and playerTeam and info.team == playerTeam then
                table.insert(teamList, member)
            else
                local eKey = (member.name and member.name:lower()) or (tostring(sName) .. "_" .. tostring(cToken))
                if not enemySeen[eKey] then
                    enemySeen[eKey] = true
                    table.insert(enemyList, member)
                end
                local m = info.postmatchMMR or info.prematchMMR
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

    local record = ns.EnsurePlayerRecord()
    local now = time()

    -- Finalize last active round
    if pendingMatch.currentRound then
        local rApi = C_PvP and C_PvP.GetPVPActiveMatchDuration and C_PvP.GetPVPActiveMatchDuration()
        local rDur = (rApi and rApi > 0 and math.floor(rApi + 0.5)) or math.max(1, now - (pendingMatch.currentRound.startTime or now))
        pendingMatch.currentRound.duration = rDur
        table.insert(pendingMatch.rounds, pendingMatch.currentRound)
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
    }

    -- Request server scoreboard data
    if RequestBattlefieldScoreData then
        RequestBattlefieldScoreData()
    end
    UpdateFromScoreboard(matchEntry, record)

    -- Determine outcome
    if matchEntry.roundsWon ~= nil then
        if matchEntry.roundsWon >= 4 then
            matchEntry.won = true
        elseif matchEntry.roundsWon == 3 then
            matchEntry.won = nil
        else
            matchEntry.won = false
        end
    elseif matchEntry.ratingChange and matchEntry.ratingChange ~= 0 then
        matchEntry.won = (matchEntry.ratingChange > 0)
    else
        matchEntry.won = true
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
        
        if matchEntry.roundsWon ~= nil then
            if matchEntry.roundsWon >= 4 then
                matchEntry.won = true
            elseif matchEntry.roundsWon == 3 then
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

        if (not snapUpdated or not scoreUpdated) and pollCount < 4 then
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
    frame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")

    frame:RegisterEvent("ARENA_OPPONENT_UPDATE")

    frame:SetScript("OnEvent", function(self, event, ...)
        if event == "PVP_MATCH_ACTIVE" then
            OnMatchStart()
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


-- TEMP: Track arena unit deaths per round
local f = CreateFrame("Frame")
f:RegisterEvent("UNIT_HEALTH")
f:SetScript("OnEvent", function(self, event, unit)
    -- Filter to only relevant units
    if not unit or not unit:match("^arena%d") and not unit:match("^raid%d") and not unit:match("^party%d") and unit ~= "player" then
        return
    end

    local name = UnitName(unit) or "?"
    local hp   = UnitHealth(unit) or 0
    local maxHp= UnitHealthMax(unit) or 1
    local dead = UnitIsDeadOrGhost(unit)
    
    -- Print all events for units that are at 0 HP or dead
    if hp == 0 or dead then
        print(string.format("|cffff8800[AA-DEATH]|r %s %s hp=%d/%d dead=%s",
            event, unit, hp, maxHp, tostring(dead)))
    end
end)