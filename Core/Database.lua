-- =========================================================================
-- AlterArena database layer
-- =========================================================================
-- Owns: AlterArenaDB layout, defaults, migrations, player records, peaks,
--       currency cache on the current character.
-- Does NOT own: live rating API rebuild (Core.lua), match capture (MatchTracker).
-- =========================================================================

local ADDON_NAME, ns = ...

-- AlterArenaDB layout:
-- AlterArenaDB.players["Name-Realm"] = {
--   name, realm, class, faction, spec, specIcon,
--   matches = { ... },          -- append-only event log
--   bracketRatings = { ... },   -- disposable cache
--   peaks = { ... },            -- survives /aa reset
--   currency = { ... },
-- }
-- AlterArenaDB.settings = { ... }
-- AlterArenaDB.schemaVersion = number

AlterArenaDB = AlterArenaDB or {}

local DEFAULTS = {
    players = {},
    settings = {
        enableQueueTimer = true,
        debugMode = false,
        mirrorDebugChat = false,
        minimapHide = false,
        minimapAngle = 220,
        disableCurrencyAlerts = false,
        columns = {},
        queueTimerSound = "pvpqueue",
        windowSize = "normal",   -- compact | normal | large | xl
        colorScheme = "cyan",    -- cyan | violet | emerald | amber | rose
        bgScheme = "slate",      -- slate | charcoal | midnight | graphite | warm
        uiFont = "default",      -- default | friz | arialn | morpheus | skurri
    },
    schemaVersion = 2,
}

function ns.EnsureDBDefaults()
    for key, value in pairs(DEFAULTS) do
        if AlterArenaDB[key] == nil then
            AlterArenaDB[key] = value
        end
    end
    if AlterArenaDB.schemaVersion == nil then
        AlterArenaDB.schemaVersion = 1
    end
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    local s = AlterArenaDB.settings
    if s.enableQueueTimer == nil then s.enableQueueTimer = true end
    if s.debugMode == nil then s.debugMode = false end
    if s.mirrorDebugChat == nil then s.mirrorDebugChat = false end
    if s.minimapHide == nil then s.minimapHide = false end
    if s.minimapAngle == nil then s.minimapAngle = 220 end
    if s.disableCurrencyAlerts == nil then s.disableCurrencyAlerts = false end
    if s.queueTimerSound == nil then s.queueTimerSound = "pvpqueue" end
    if s.windowSize == nil then s.windowSize = "normal" end
    if s.colorScheme == nil then s.colorScheme = "cyan" end
    if s.bgScheme == nil then s.bgScheme = "slate" end
    if s.uiFont == nil then s.uiFont = "default" end
end

function ns.GetPlayerKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return string.format("%s-%s", name, realm)
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
            peaks = {},
            currency = {},
        }
    end

    local rec = players[key]
    rec.bracketRatings = rec.bracketRatings or {}
    rec.peaks = rec.peaks or {}

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

function ns.UpdatePeak(rec, key, rating)
    if not rec or not key or not rating or rating <= 0 then return end
    rec.peaks = rec.peaks or {}
    local p = rec.peaks[key]
    if not p or rating > (p.rating or 0) then
        rec.peaks[key] = { rating = rating, timestamp = time() }
    end
end

function ns.GetPeak(rec, key)
    if not rec or not rec.peaks or not key then return nil end
    local p = rec.peaks[key]
    return p and p.rating or nil
end

function ns.GetCurrencySnapshot()
    if not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return nil end
    local snap = {}
    for key, id in pairs(ns.CURRENCY or {}) do
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and info and (info.quantity ~= nil or info.iconFileID) then
            snap[key] = {
                amount = info.quantity or 0,
                max    = info.maxQuantity or 0,
                totalEarned = info.totalEarned or 0,
                name   = info.name,
                icon   = info.iconFileID,
            }
        end
    end
    return snap
end

function ns.RefreshPlayerCurrency()
    local rec = ns.EnsurePlayerRecord()
    local snap = ns.GetCurrencySnapshot()
    if not snap or not next(snap) then return end
    rec.currency = rec.currency or {}
    local now = time()
    for key, data in pairs(snap) do
        rec.currency[key] = {
            amount  = data.amount,
            max     = data.max,
            totalEarned = data.totalEarned,
            updated = now,
        }
    end
end

-- Wipe disposable rating caches. Match history is never touched.
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
    end
    return cleared
end