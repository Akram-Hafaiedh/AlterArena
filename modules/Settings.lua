-- =========================================================================
-- Settings.lua — standalone settings panel (not a main-window tab)
-- =========================================================================

local ADDON_NAME, ns = ...

local settingsFrame = nil

local SETTINGS_W = 460
local CARD_GAP = 10

local function CreateStyledButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
    btn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetPoint("CENTER")
    btn.text:SetText(text)

    function btn:SetText(t)
        if self.text then self.text:SetText(t) end
    end
    function btn:GetText()
        return (self.text and self.text:GetText()) or ""
    end

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1)
        self:SetBackdropBorderColor(0.4, 0.45, 0.55, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.13, 0.16, 0.9)
        self:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
    end)
    return btn
end

local function NotifyMainGear()
    if ns.UpdateMainSettingsButtonState then
        ns.UpdateMainSettingsButtonState()
    end
end

local function MakeSettingsCard(parent, title, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height)
    card:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    card:SetBackdropBorderColor(0.18, 0.19, 0.24, 0.9)

    local t = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 14, -12)
    t:SetText("|cffffd100" .. title .. "|r")
    card.title = t
    return card
end

local function MakeCheckRow(parent, label, y)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", 14, y)
    btn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.13, 0.14, 0.18, 0.95)
    btn:SetBackdropBorderColor(0.30, 0.32, 0.40, 0.95)

    local check = btn:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetSize(22, 22)
    check:SetPoint("CENTER", 1, 0)
    btn.checkTex = check

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    lbl:SetText(label)
    btn.label = lbl
    return btn
end

local function BuildSoundDropdownItems(currentId, onSelect)
    local items = {}
    local lastCat = nil
    for _, snd in ipairs(ns.SOUNDS or {}) do
        if snd.category ~= lastCat then
            table.insert(items, { type = "title", label = snd.category or "Other" })
            lastCat = snd.category
        end
        local sid = snd.id
        table.insert(items, {
            type = "radio",
            label = snd.label,
            keepOpen = true,
            checked = function() return currentId() == sid end,
            onClick = function()
                onSelect(sid)
                if sid ~= "none" and ns.PlaySoundById then
                    ns.PlaySoundById(sid)
                end
            end,
        })
    end
    return items
end

local function CreateSettingsFrame()
    local f = CreateFrame("Frame", "AlterArenaSettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(SETTINGS_W, 560)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if AlterArenaDB then
            AlterArenaDB.settingsWindowPos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)
    f:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.07, 0.07, 0.09, 0.97)
    f:SetBackdropBorderColor(0.20, 0.21, 0.25, 0.95)

    if AlterArenaDB and AlterArenaDB.settingsWindowPos then
        local p = AlterArenaDB.settingsWindowPos
        f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 280, 20)
    end

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(36)
    titleBar:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    titleBar:SetBackdropColor(0.09, 0.09, 0.12, 0.95)
    titleBar:SetBackdropBorderColor(0.16, 0.16, 0.20, 0.8)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2")
    title:SetPoint("LEFT", 14, 0)
    title:SetText("|cffffd100AlterArena Settings|r")

    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
    closeBtn:SetBackdropBorderColor(0.25, 0.25, 0.30, 0.8)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeBtn.text:SetPoint("CENTER", 0, 1)
    closeBtn.text:SetText("|cffaaaaaa×|r")
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.2, 0.9)
        self.text:SetText("|cffffffff×|r")
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.18, 0.8)
        self.text:SetText("|cffaaaaaa×|r")
    end)
    closeBtn:SetScript("OnClick", function()
        if ns.CloseDropdowns then ns.CloseDropdowns() end
        f:Hide()
        NotifyMainGear()
    end)

    -- Scrollable body
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -42)
    scroll:SetPoint("BOTTOMRIGHT", -28, 10)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(SETTINGS_W - 44)
    content:SetHeight(10)
    scroll:SetScrollChild(content)
    f.content = content

    local cardW = SETTINGS_W - 44
    local y = 0

    -- ── 1. Queue Timer ──────────────────────────────────────────────────
    local qCard = MakeSettingsCard(content, "Queue Timer HUD", 168)
    qCard:SetWidth(cardW)
    qCard:SetPoint("TOPLEFT", 0, y)
    y = y - 168 - CARD_GAP

    local qCb = MakeCheckRow(qCard, "Show floating HUD while queued", -40)
    f.timerCheckbox = qCb
    qCb:SetScript("OnClick", function()
        local on = not (ns.IsQueueTimerEnabled and ns.IsQueueTimerEnabled())
        if ns.SetQueueTimerEnabled then ns.SetQueueTimerEnabled(on) end
        f.UpdateStatus()
    end)

    local qDesc = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qDesc:SetPoint("TOPLEFT", 44, -66)
    qDesc:SetWidth(cardW - 58)
    qDesc:SetJustifyH("LEFT")
    qDesc:SetText("|cff888899Wait time, estimated duration, and recent rating while in queue.|r")

    local qStatus = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qStatus:SetPoint("TOPLEFT", 44, -86)
    f.qStatus = qStatus

    local qtSoundBtn = CreateStyledButton(qCard, "Pop Sound: —", 160, 24)
    qtSoundBtn:SetPoint("TOPLEFT", 14, -112)
    f.qtSoundBtn = qtSoundBtn
    qtSoundBtn:SetScript("OnClick", function(self)
        local items = BuildSoundDropdownItems(
            function()
                return AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.queueTimerSound or "pvpqueue"
            end,
            function(sid)
                AlterArenaDB = AlterArenaDB or {}
                AlterArenaDB.settings = AlterArenaDB.settings or {}
                AlterArenaDB.settings.queueTimerSound = sid
                f.UpdateStatus()
            end
        )
        ns.OpenDropdown(self, items)
    end)

    local qtPlay = CreateStyledButton(qCard, "Play", 50, 24)
    qtPlay:SetPoint("LEFT", qtSoundBtn, "RIGHT", 6, 0)
    qtPlay:SetScript("OnClick", function()
        local id = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.queueTimerSound or "pvpqueue"
        if ns.PlaySoundById then ns.PlaySoundById(id) end
    end)

    local testBtn = CreateStyledButton(qCard, "Test HUD", 90, 24)
    testBtn:SetPoint("LEFT", qtPlay, "RIGHT", 6, 0)
    f.testBtn = testBtn
    testBtn:SetScript("OnClick", function()
        if ns.ToggleTestQueueTimer then ns.ToggleTestQueueTimer() end
        f.UpdateStatus()
    end)

    local resetPosBtn = CreateStyledButton(qCard, "Reset Pos", 90, 24)
    resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 6, 0)
    resetPosBtn:SetScript("OnClick", function()
        if ns.ResetQueueTimerPosition then ns.ResetQueueTimerPosition() end
    end)

    -- ── 2. Currency Cap Alerts ──────────────────────────────────────────
    local aCard = MakeSettingsCard(content, "Currency Cap Alerts", 210)
    aCard:SetWidth(cardW)
    aCard:SetPoint("TOPLEFT", 0, y)
    y = y - 210 - CARD_GAP

    local aDesc = aCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    aDesc:SetPoint("TOPLEFT", 14, -34)
    aDesc:SetWidth(cardW - 28)
    aDesc:SetJustifyH("LEFT")
    aDesc:SetText("|cff888899Toast when Honor or Bloody Tokens cross their warning threshold.|r")

    local currencyMeta = {
        { key = "honor",    label = "Honor" },
        { key = "tokens",   label = "Bloody Tokens" },
        { key = "conquest", label = "Conquest" },
    }
    local cy = -58
    f.currencyToggles = {}
    for _, meta in ipairs(currencyMeta) do
        local row = CreateFrame("Button", nil, aCard, "BackdropTemplate")
        row:SetSize(cardW - 28, 22)
        row:SetPoint("TOPLEFT", 14, cy)
        row:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropColor(0.12, 0.13, 0.16, 0.95)
        row:SetBackdropBorderColor(0.28, 0.30, 0.36, 0.9)

        local chk = row:CreateTexture(nil, "OVERLAY")
        chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        chk:SetSize(18, 18)
        chk:SetPoint("LEFT", 4, 0)
        row.chk = chk

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", 28, 0)
        lbl:SetText(meta.label)

        local val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("RIGHT", -10, 0)
        val:SetJustifyH("RIGHT")
        row.val = val

        local key = meta.key
        row:SetScript("OnClick", function()
            local cfg = ns.GetCurrencyAlertConfig and ns.GetCurrencyAlertConfig()
            if not cfg or not cfg.perCurrency or not cfg.perCurrency[key] then return end
            cfg.perCurrency[key].enabled = not cfg.perCurrency[key].enabled
            f.UpdateStatus()
        end)
        f.currencyToggles[key] = row
        cy = cy - 26
    end

    local aSoundBtn = CreateStyledButton(aCard, "Sound: —", 160, 24)
    aSoundBtn:SetPoint("TOPLEFT", 14, cy - 6)
    f.alertSoundBtn = aSoundBtn
    aSoundBtn:SetScript("OnClick", function(self)
        local items = BuildSoundDropdownItems(
            function()
                local cfg = ns.GetCurrencyAlertConfig and ns.GetCurrencyAlertConfig()
                return (cfg and cfg.sound) or "readycheck"
            end,
            function(sid)
                local cfg = ns.GetCurrencyAlertConfig and ns.GetCurrencyAlertConfig()
                if cfg then cfg.sound = sid end
                f.UpdateStatus()
            end
        )
        ns.OpenDropdown(self, items)
    end)

    local aPlay = CreateStyledButton(aCard, "Play", 50, 24)
    aPlay:SetPoint("LEFT", aSoundBtn, "RIGHT", 6, 0)
    aPlay:SetScript("OnClick", function()
        local cfg = ns.GetCurrencyAlertConfig and ns.GetCurrencyAlertConfig()
        if ns.PlaySoundById then ns.PlaySoundById((cfg and cfg.sound) or "readycheck") end
    end)

    local aTest = CreateStyledButton(aCard, "Test Alert", 90, 24)
    aTest:SetPoint("LEFT", aPlay, "RIGHT", 6, 0)
    aTest:SetScript("OnClick", function()
        if ns.TestCurrencyAlert then ns.TestCurrencyAlert() end
    end)

    local aReset = CreateStyledButton(aCard, "Reset Pos", 90, 24)
    aReset:SetPoint("LEFT", aTest, "RIGHT", 6, 0)
    aReset:SetScript("OnClick", function()
        if ns.ResetCurrencyAlertPosition then ns.ResetCurrencyAlertPosition() end
    end)

    -- ── 3. Debug ────────────────────────────────────────────────────────
    local dCard = MakeSettingsCard(content, "Debug Logging", 96)
    dCard:SetWidth(cardW)
    dCard:SetPoint("TOPLEFT", 0, y)
    y = y - 96 - CARD_GAP

    local dCb = MakeCheckRow(dCard, "Verbose [AA-DEBUG] chat logging", -40)
    f.debugCheckbox = dCb
    dCb:SetScript("OnClick", function()
        AlterArenaDB = AlterArenaDB or {}
        AlterArenaDB.settings = AlterArenaDB.settings or {}
        AlterArenaDB.settings.debugMode = not AlterArenaDB.settings.debugMode
        local s = AlterArenaDB.settings.debugMode and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
        print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.", s))
        f.UpdateStatus()
    end)

    local dStatus = dCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dStatus:SetPoint("TOPLEFT", 44, -68)
    f.debugStatusText = dStatus

    -- ── 4. Database ─────────────────────────────────────────────────────
    local iCard = MakeSettingsCard(content, "Database", 88)
    iCard:SetWidth(cardW)
    iCard:SetPoint("TOPLEFT", 0, y)
    y = y - 88 - CARD_GAP

    local iDesc = iCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    iDesc:SetPoint("TOPLEFT", 14, -36)
    iDesc:SetWidth(cardW - 28)
    iDesc:SetJustifyH("LEFT")
    f.infoDesc = iDesc

    content:SetHeight(math.abs(y) + 8)

    f.UpdateStatus = function()
        local qtOn = ns.IsQueueTimerEnabled and ns.IsQueueTimerEnabled()
        if f.timerCheckbox and f.timerCheckbox.checkTex then
            f.timerCheckbox.checkTex:SetShown(qtOn)
        end
        if f.qStatus then
            f.qStatus:SetText(qtOn
                and "|cff888899Status:|r |cff22c55eActive|r"
                or  "|cff888899Status:|r |cffef4444Disabled|r")
        end
        if f.testBtn then
            local testing = ns.IsTestQueueTimerActive and ns.IsTestQueueTimerActive()
            f.testBtn:SetText(testing and "|cffff4444Hide HUD|r" or "Test HUD")
        end
        if f.qtSoundBtn then
            local id = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.queueTimerSound or "pvpqueue"
            local entry = ns.SOUND_BY_ID and ns.SOUND_BY_ID[id]
            f.qtSoundBtn.text:SetText("Pop Sound: " .. (entry and entry.label or id))
        end

        if f.currencyToggles and ns.GetCurrencyAlertConfig then
            local cfg = ns.GetCurrencyAlertConfig()
            for key, row in pairs(f.currencyToggles) do
                local per = cfg.perCurrency and cfg.perCurrency[key]
                if per then
                    row.chk:SetShown(per.enabled)
                    if per.threshold and per.threshold > 0 then
                        row.val:SetText(string.format("|cff888899≥ %d|r", per.threshold))
                    else
                        row.val:SetText("|cff888899no cap|r")
                    end
                end
            end
            if f.alertSoundBtn then
                local entry = ns.SOUND_BY_ID and ns.SOUND_BY_ID[cfg.sound]
                f.alertSoundBtn.text:SetText("Sound: " .. (entry and entry.label or (cfg.sound or "—")))
            end
        end

        local dbg = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode
        if f.debugCheckbox and f.debugCheckbox.checkTex then
            f.debugCheckbox.checkTex:SetShown(dbg)
        end
        if f.debugStatusText then
            f.debugStatusText:SetText(dbg
                and "|cff888899Status:|r |cff22c55eOn|r — match/rating diagnostics in chat"
                or  "|cff888899Status:|r |cff888899Off|r")
        end

        local chars, matches = 0, 0
        if AlterArenaDB and AlterArenaDB.players then
            for _, p in pairs(AlterArenaDB.players) do
                chars = chars + 1
                if p.matches then matches = matches + #p.matches end
            end
        end
        if f.infoDesc then
            f.infoDesc:SetText(string.format(
                "|cff888899Tracking|r |cffffffff%d|r |cff888899character(s),|r |cffffd100%d|r |cff888899match(es).\nStored in WTF SavedVariables.  Shortcuts:|r |cffffd100/aa debug|r  |  |cffffd100/aa timer|r  |  |cffffd100/aa test|r",
                chars, matches
            ))
        end
    end

    ns.UpdateSettingsUI = function()
        if f and f.UpdateStatus and f:IsShown() then
            f.UpdateStatus()
        end
    end

    f:Hide()
    return f
end

function ns.IsSettingsPanelOpen()
    return settingsFrame and settingsFrame:IsShown()
end

function ns.OpenSettings()
    if not settingsFrame then
        settingsFrame = CreateSettingsFrame()
    end
    settingsFrame.UpdateStatus()
    settingsFrame:Show()
    settingsFrame:Raise()
    NotifyMainGear()
end

function ns.ToggleSettingsPanel()
    if settingsFrame and settingsFrame:IsShown() then
        if ns.CloseDropdowns then ns.CloseDropdowns() end
        settingsFrame:Hide()
        NotifyMainGear()
    else
        ns.OpenSettings()
    end
end