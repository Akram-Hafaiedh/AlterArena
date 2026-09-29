-- =========================================================================
-- CurrencyAlert.lua — on-screen warning when a PvP currency nears its cap
-- =========================================================================
-- Only Honor and Bloody Tokens are enabled by default because Conquest's
-- cap is a rolling weekly that resets, so "wallet near cap" isn't a
-- permanent "spend it or lose it" state the way Honor is.
-- =========================================================================

local ADDON_NAME, ns = ...

local alertFrame
local alertTimer = nil

local DEFAULTS = {
    honor    = { enabled = true,  threshold = 14500 },
    conquest = { enabled = false, threshold = 0     },
    tokens   = { enabled = true,  threshold = 45000 },
}

local lastKnownAmount = {}

-- Legacy id → current ns.SOUNDS id (old CurrencyAlert used short names / file paths)
local LEGACY_SOUND_IDS = {
    alarm = "alarm3",
}

-- -------------------------------------------------------------------------
-- Config helpers
-- -------------------------------------------------------------------------

local function GetConfig()
    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    local cfg = AlterArenaDB.settings.currencyAlerts
    if not cfg then
        cfg = { sound = "readycheck", perCurrency = {} }
        AlterArenaDB.settings.currencyAlerts = cfg
    end
    cfg.perCurrency = cfg.perCurrency or {}
    for key, def in pairs(DEFAULTS) do
        if not cfg.perCurrency[key] then
            cfg.perCurrency[key] = { enabled = def.enabled, threshold = def.threshold }
        end
    end
    -- Migrate legacy sound ids once
    if cfg.sound and LEGACY_SOUND_IDS[cfg.sound] then
        cfg.sound = LEGACY_SOUND_IDS[cfg.sound]
    end
    return cfg
end

local function PlayAlertSound()
    local cfg = GetConfig()
    local soundId = cfg.sound or "readycheck"
    if ns.PlaySoundById then
        ns.PlaySoundById(soundId)
    else
        -- Minimal fallback if Core hasn't loaded the sound system yet
        pcall(PlaySound, 8960) -- READY_CHECK
    end
end

-- -------------------------------------------------------------------------
-- The toast frame
-- -------------------------------------------------------------------------

local function CreateAlertFrame()
    local f = CreateFrame("Frame", "AlterArenaCurrencyAlert", UIParent, "BackdropTemplate")
    f:SetSize(340, 78)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        GetConfig().position = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    f:SetBackdrop({
        bgFile   = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.10, 0.08, 0.05, 0.96)
    f:SetBackdropBorderColor(0.85, 0.65, 0.15, 1)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", 12, -12)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -2)
    f.title:SetPoint("RIGHT", -12, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetText("|cffffd100Currency Cap Warning|r")

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", f.icon, "BOTTOMLEFT", -2, -2)
    f.text:SetPoint("RIGHT", -12, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetText("")

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("BOTTOMRIGHT", -10, 6)
    f.hint:SetText("|cff666677Click to dismiss|r")

    f:SetScript("OnMouseDown", function()
        ns.HideCurrencyAlert()
    end)

    f:Hide()
    return f
end

-- -------------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------------

function ns.ShowCurrencyAlert(key, label, wallet, cap)
    if not alertFrame then alertFrame = CreateAlertFrame() end

    local cfg = GetConfig()
    if cfg.position and cfg.position.point then
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint(cfg.position.point, UIParent,
            cfg.position.relPoint or cfg.position.point,
            cfg.position.x or 0, cfg.position.y or 0)
    else
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end

    -- Icon
    local id = ns.CURRENCY and ns.CURRENCY[key]
    if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and info and info.iconFileID then
            alertFrame.icon:SetTexture(info.iconFileID)
            alertFrame.icon:Show()
        else
            alertFrame.icon:Hide()
        end
    else
        alertFrame.icon:Hide()
    end

    local capStr = (cap and cap > 0) and string.format(" / %d", cap) or ""
    alertFrame.text:SetText(string.format(
        "|cffffffff%s|r is at |cffffd100%d%s|r.\n|cffccccccSpend it before you waste future gains.|r",
        label, wallet, capStr))

    alertFrame:Show()
    PlayAlertSound()

    if alertTimer then alertTimer:Cancel() end
    alertTimer = C_Timer.NewTimer(20, function()
        if alertFrame then alertFrame:Hide() end
        alertTimer = nil
    end)
end

function ns.HideCurrencyAlert()
    if alertFrame then alertFrame:Hide() end
    if alertTimer then alertTimer:Cancel(); alertTimer = nil end
end

function ns.TestCurrencyAlert()
    local id = ns.CURRENCY and ns.CURRENCY.honor
    local cap, wallet = 15000, 14500
    if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and info then
            cap = info.maxQuantity or cap
            wallet = math.min(cap, (info.quantity or 0) + 1)
        end
    end
    ns.ShowCurrencyAlert("honor", "Honor", wallet, cap)
end

function ns.ResetCurrencyAlertPosition()
    GetConfig().position = nil
    if alertFrame then
        alertFrame:ClearAllPoints()
        alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end
    print("|cff40c0ffAlterArena|r: Currency alert position reset.")
end

-- -------------------------------------------------------------------------
-- Threshold check — called from Core.lua after RefreshPlayerCurrency()
-- -------------------------------------------------------------------------

function ns.CheckCurrencyAlerts()
    local cfg = GetConfig()
    local rec = AlterArenaDB.players[ns.GetPlayerKey()]
    if not rec or not rec.currency then return end

    for key, perCfg in pairs(cfg.perCurrency) do
        if perCfg.enabled and perCfg.threshold > 0 then
            local c = rec.currency[key]
            if c then
                local wallet = c.amount or 0
                local prev = lastKnownAmount[key]
                -- Trigger only when crossing upward (avoids nagging).
                if wallet >= perCfg.threshold and (not prev or prev < perCfg.threshold) then
                    local label = key:sub(1,1):upper() .. key:sub(2)
                    if key == "tokens" then label = "Bloody Tokens" end
                    ns.ShowCurrencyAlert(key, label, wallet, c.max or 0)
                end
                lastKnownAmount[key] = wallet
            end
        end
    end
end