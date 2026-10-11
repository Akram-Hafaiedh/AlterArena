local ADDON_NAME, ns = ...

-- MatchOutcome: bracket detect, team index, ally icons (shared by all queues).
-- Shared live state: ns.MatchTrackerPrivate

local MT = ns.MatchTrackerPrivate or {}
ns.MatchTrackerPrivate = MT
MT.detectedPlayerSpecs = MT.detectedPlayerSpecs or {}

function MT.GetMyShuffleTeamIndex()
    -- Prefer scoreboard faction (works for Shuffle + Arena).
    if C_PvP and C_PvP.GetScoreInfo and GetNumBattlefieldScores then
        local playerName = UnitName("player")
        if playerName then
            local n = GetNumBattlefieldScores() or 0
            for i = 1, n do
                local info = C_PvP.GetScoreInfo(i)
                if info then
                    local name = ns.SafeString(info.name)
                    if name then
                        local clean = ns.AmbiguateName(name)
                        if name == playerName or clean == playerName
                           or name:find(playerName, 1, true) then
                            local t = ns.SafeNumber(info.faction) or ns.SafeNumber(info.team)
                            if t ~= nil then return t end
                        end
                    end
                end
            end
        end
    end
    -- Arena/BG fallback when scoreboard is still empty at resolve time.
    if GetBattlefieldArenaFaction then
        local ok, fac = pcall(GetBattlefieldArenaFaction)
        if ok and fac ~= nil and not (issecretvalue and issecretvalue(fac)) then
            return tonumber(fac)
        end
    end
    return nil
end

-- Detect rated queue at match start (do not default to Shuffle).
function MT.DetectBracketAtStart(ratingBefore)
    -- Blitz / RBG MUST be before Solo Shuffle: IsRatedSoloShuffle can be true
    -- while still in a city or after a previous shuffle session.
    if C_PvP and C_PvP.IsBlitz and C_PvP.IsBlitz() then
        return "Blitz"
    end
    if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
        if ratingBefore then
            local b8 = ratingBefore[8]
            local b9 = ratingBefore[9]
            if (b8 and (b8.rating or 0) > 0) or (b9 and (b9.rating or 0) > 0) then
                return "Blitz"
            end
        end
        return "10v10"
    end
    if C_PvP and C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
        return "Solo Shuffle"
    end
    -- Arena: group size is the most reliable 2v2 vs 3v3 signal.
    local members = GetNumGroupMembers and GetNumGroupMembers() or 0
    if C_PvP and C_PvP.IsRatedArena and C_PvP.IsRatedArena() then
        if members >= 3 then return "3v3" end
        if members == 2 then return "2v2" end
        if ratingBefore and ratingBefore[2] and (ratingBefore[2].seasonPlayed or 0) > 0 then
            return "3v3"
        end
        if ratingBefore and ratingBefore[1] and (ratingBefore[1].seasonPlayed or 0) > 0 then
            return "2v2"
        end
        return "3v3"
    end
    if members >= 3 then return "3v3" end
    if members == 2 then return "2v2" end
    -- Still in city / unknown — rating snapshot at end will fix it.
    return nil
end

function MT.IsSingleMatchBracket(bracket)
    if not bracket then return false end
    return bracket == "Blitz" or bracket == "10v10"
        or bracket == "2v2" or bracket == "3v3"
        or bracket == "Arena"
end

local CLASS_ICON_FILE = {
    WARRIOR = 626008, PALADIN = 626003, HUNTER = 626000, ROGUE = 626005,
    PRIEST = 626004, DEATHKNIGHT = 135771, SHAMAN = 626006, MAGE = 626001,
    WARLOCK = 626007, MONK = 626002, DRUID = 625999, DEMONHUNTER = 1260827,
    EVOKER = 4574311,
}

function MT.IconFromTalentSpecOrClass(talentSpec, classToken)
    local id = ns.SafeNumber(talentSpec)
    if (not id or id <= 0) and type(talentSpec) == "number" then id = talentSpec end
    if id and id > 0 and GetSpecializationInfoByID then
        local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, id)
        if ok and icon then return icon end
    end
    local ct = ns.SafeString(classToken)
    if ct and CLASS_ICON_FILE[ct] then return CLASS_ICON_FILE[ct] end
    return nil
end

-- Fill round.team with up to 3 ally icons (player already seeded).
-- Used by the history TOOLTIP only (row enemyTeam column is separate / untouched).
-- RatedStats-style: party/raid allies + scoreboard same teamIndex at PostRound.
function MT.FillRoundAllies(round)
    if not round or type(round.team) ~= "table" then return end

    local function addIcon(icon)
        if not icon or #round.team >= 3 then return end
        for _, existing in ipairs(round.team) do
            if existing == icon then return end
        end
        table.insert(round.team, icon)
    end

    -- 12.x: UnitExists / UnitIsUnit / UnitCanAttack can return secret booleans.
    -- Never use them in `if` directly — unwrap via pcall + issecretvalue.
    local function SafeUnitBool(fn, ...)
        if not fn then return false end
        local ok, result = pcall(fn, ...)
        if not ok or result == nil then return false end
        if issecretvalue and issecretvalue(result) then return false end
        return result and true or false
    end

    local function tryUnit(unit)
        if not SafeUnitBool(UnitExists, unit) then return end
        if SafeUnitBool(UnitIsUnit, unit, "player") then return end
        -- Skip arena opponents (enemies this round)
        for i = 1, 3 do
            if SafeUnitBool(UnitIsUnit, unit, "arena" .. i) then return end
        end
        if UnitCanAttack and SafeUnitBool(UnitCanAttack, "player", unit) then return end

        if NotifyInspect and CanInspect and SafeUnitBool(CanInspect, unit) then
            pcall(NotifyInspect, unit)
        end

        local specID = nil
        if GetInspectSpecialization then
            local ok, id = pcall(GetInspectSpecialization, unit)
            if ok and id and not (issecretvalue and issecretvalue(id)) and id > 0 then
                specID = id
            end
        end
        if specID and GetSpecializationInfoByID then
            local ok, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
            if ok and icon and not (issecretvalue and issecretvalue(icon)) then
                addIcon(icon)
                return
            end
        end
        -- Class icon fallback (always available without inspect)
        local okClass, _, classToken = pcall(UnitClass, unit)
        if okClass then
            addIcon(MT.IconFromTalentSpecOrClass(nil, classToken))
        end
    end

    if RequestBattlefieldScoreData then pcall(RequestBattlefieldScoreData) end

    -- 1) Direct party slots (shuffle round grouping)
    tryUnit("party1")
    tryUnit("party2")

    -- 2) Raid roster — shuffle lobby is often raid-of-6; filter out enemies
    if #round.team < 3 then
        local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, math.min(n, 6) do
            if #round.team >= 3 then break end
            tryUnit("raid" .. i)
        end
    end

    -- 3) Scoreboard: same team index as the player (faction = Gold/Purple team)
    if #round.team < 3 and C_PvP and C_PvP.GetScoreInfo and GetNumBattlefieldScores then
        local myTeam = nil
        if type(MT.GetMyShuffleTeamIndex) == "function" then
            local ok, t = pcall(MT.GetMyShuffleTeamIndex)
            if ok then myTeam = t end
        elseif GetBattlefieldArenaFaction then
            local ok, fac = pcall(GetBattlefieldArenaFaction)
            if ok and fac ~= nil and not (issecretvalue and issecretvalue(fac)) then
                myTeam = tonumber(fac)
            end
        end
        local playerName = UnitName("player")
        local n = GetNumBattlefieldScores() or 0
        for i = 1, n do
            if #round.team >= 3 then break end
            local info = C_PvP.GetScoreInfo(i)
            if info and myTeam ~= nil then
                local name = (ns.SafeString and ns.SafeString(info.name)) or nil
                if name and playerName then
                    local clean = (ns.AmbiguateName and ns.AmbiguateName(name)) or name
                    local isMe = (clean == playerName or name == playerName
                        or (type(name) == "string" and name:find(playerName, 1, true)))
                    if not isMe then
                        local team = ns.SafeNumber and ns.SafeNumber(info.faction)
                        if team == myTeam then
                            local classToken = ns.SafeString and ns.SafeString(info.classToken)
                            local talentSpec = ns.SafeNumber and (ns.SafeNumber(info.talentSpec)
                                or ns.SafeNumber(info.specID))
                            local iconFn = MT.IconFromTalentSpecOrClass
                            if type(iconFn) == "function" then
                                addIcon(iconFn(talentSpec, classToken))
                            end
                        end
                    end
                end
            end
        end
    end

    if MT.MatchProbe then MT.MatchProbe("TeamSpecs", string.format("n=%d filled", #round.team)) end
end

-- Chat last-resort only (primary W/L is GetActiveMatchWinner).