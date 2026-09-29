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

local function MakeCheckRow(parent, label, y, onChange)
    if ns.CreateUIToggle then
        local toggle = ns.CreateUIToggle(parent, {
            label = label,
            labelOnRight = true,
            onChange = onChange,
        })
        toggle:SetPoint("TOPLEFT", 14, y)
        return toggle
    end

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
    if onChange then
        btn:SetScript("OnClick", function()
            local now = not (btn.checkTex and btn.checkTex:IsShown())
            if btn.checkTex then btn.checkTex:SetShown(now) end
            onChange(now)
        end)
    end
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

    -- Scrollable body (custom scrollbar)
    local scroll, content
    if ns.CreateScrollFrame then
        scroll, content = ns.CreateScrollFrame(f)
    else
        scroll = CreateFrame("ScrollFrame", nil, f)
        content = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(content)
        scroll:EnableMouseWheel(true)
    end
    scroll:SetPoint("TOPLEFT", 8, -42)
    scroll:SetPoint("BOTTOMRIGHT", -14, 10)
    content:SetWidth(SETTINGS_W - 36)
    content:SetHeight(10)
    f.content = content
    f.scroll = scroll

    local cardW = SETTINGS_W - 44
    local y = 0

    -- ── 1. Queue Timer ──────────────────────────────────────────────────
    local qCard = MakeSettingsCard(content, "Queue Timer HUD", 168)
    qCard:SetWidth(cardW)
    qCard:SetPoint("TOPLEFT", 0, y)
    y = y - 168 - CARD_GAP

    local qCb = MakeCheckRow(qCard, "Show floating HUD while queued", -40, function(on)
        if ns.SetQueueTimerEnabled then ns.SetQueueTimerEnabled(on) end
        f.UpdateStatus()
    end)
    f.timerCheckbox = qCb

    local qDesc = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qDesc:SetPoint("TOPLEFT", 44, -66)
    qDesc:SetWidth(cardW - 58)
    qDesc:SetJustifyH("LEFT")
    qDesc:SetText("|cff888899Wait time, estimated duration, and recent rating while in queue.|r")

    local qStatus = qCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qStatus:SetPoint("TOPLEFT", 44, -86)
    f.qStatus = qStatus

    local qtSoundBtn = CreateStyledButton(qCard, "Sound: —", 200, 24)
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

    local aSoundBtn = CreateStyledButton(aCard, "Sound: —", 200, 24)
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
    local dCard = MakeSettingsCard(content, "Debug", 168)
    dCard:SetWidth(cardW)
    dCard:SetPoint("TOPLEFT", 0, y)
    y = y - 168 - CARD_GAP

    local dCb = MakeCheckRow(dCard, "Enable debug logging (window only)", -40, function(on)
        AlterArenaDB = AlterArenaDB or {}
        AlterArenaDB.settings = AlterArenaDB.settings or {}
        AlterArenaDB.settings.debugMode = on
        local st = on and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"
        print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.", st))
        f.UpdateStatus()
    end)
    f.debugCheckbox = dCb

    local dMirror = MakeCheckRow(dCard, "Also mirror debug lines to chat", -66, function(on)
        AlterArenaDB = AlterArenaDB or {}
        AlterArenaDB.settings = AlterArenaDB.settings or {}
        AlterArenaDB.settings.mirrorDebugChat = on
        local st = on and "|cff22c55eON|r" or "|cffef4444OFF|r"
        print(string.format("|cff40c0ffAlterArena|r: Mirror debug to chat %s.", st))
        f.UpdateStatus()
    end)
    f.mirrorCheckbox = dMirror

    local dStatus = dCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dStatus:SetPoint("TOPLEFT", 44, -96)
    f.debugStatusText = dStatus

    local dOpen = CreateStyledButton(dCard, "Open Debug Window", 140, 24)
    dOpen:SetPoint("TOPLEFT", 14, -122)
    dOpen:SetScript("OnClick", function()
        if ns.ToggleDebugWindow then
            ns.ToggleDebugWindow(true)
        else
            print("|cff40c0ffAlterArena|r: Debug module not loaded.")
        end
    end)


    -- ── Appearance (CraftBell-style) ────────────────────────────────────
    local appCard = MakeSettingsCard(content, "Appearance", 200)
    appCard:SetWidth(cardW)
    appCard:SetPoint("TOPLEFT", 0, y)
    y = y - 200 - CARD_GAP

    local function AppearanceDropdown(parent, yOff, label, options, getValue, setValue)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 14, yOff)
        lbl:SetText("|cff888899" .. label .. "|r")

        local btn = CreateStyledButton(parent, "—", 150, 24)
        btn:SetPoint("TOPLEFT", 140, yOff + 2)
        local function RefreshLabel()
            local cur = getValue()
            local text = cur
            for _, opt in ipairs(options) do
                if opt.value == cur then text = opt.label break end
            end
            btn.text:SetText(text)
        end
        btn:SetScript("OnClick", function(self)
            local items = {}
            for _, opt in ipairs(options) do
                local v, lab = opt.value, opt.label
                table.insert(items, {
                    type = "radio",
                    label = lab,
                    checked = function() return getValue() == v end,
                    onClick = function()
                        setValue(v)
                        RefreshLabel()
                        if ns.UI and ns.UI.ApplyAppearance then
                            ns.UI.ApplyAppearance()
                        end
                    end,
                })
            end
            if ns.OpenDropdown then ns.OpenDropdown(self, items) end
        end)
        RefreshLabel()
        return btn
    end

    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    local sett = AlterArenaDB.settings

    f.sizeBtn = AppearanceDropdown(appCard, -40, "Window size", {
        { value = "compact", label = "Compact" },
        { value = "normal",  label = "Normal" },
        { value = "large",   label = "Large" },
        { value = "xl",      label = "Extra Large" },
    }, function() return sett.windowSize or "normal" end,
       function(v) sett.windowSize = v end)

    f.accentBtn = AppearanceDropdown(appCard, -72, "Accent color", {
        { value = "cyan",    label = "Cyan" },
        { value = "violet",  label = "Violet" },
        { value = "emerald", label = "Emerald" },
        { value = "amber",   label = "Amber" },
        { value = "rose",    label = "Rose" },
    }, function() return sett.colorScheme or "cyan" end,
       function(v) sett.colorScheme = v end)

    f.bgBtn = AppearanceDropdown(appCard, -104, "Background", {
        { value = "slate",    label = "Slate" },
        { value = "charcoal", label = "Charcoal" },
        { value = "midnight", label = "Midnight" },
        { value = "graphite", label = "Graphite" },
        { value = "warm",     label = "Warm" },
    }, function() return sett.bgScheme or "slate" end,
       function(v) sett.bgScheme = v end)

    f.fontBtn = AppearanceDropdown(appCard, -136, "UI font", {
        { value = "default",  label = "Default" },
        { value = "friz",     label = "Friz Quadrata" },
        { value = "arialn",   label = "Arial Narrow" },
        { value = "morpheus", label = "Morpheus" },
        { value = "skurri",   label = "Skurri" },
    }, function() return sett.uiFont or "default" end,
       function(v) sett.uiFont = v end)

    local appHint = appCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    appHint:SetPoint("TOPLEFT", 14, -170)
    appHint:SetText("Size applies immediately. Theme updates open windows.")


    -- ── 4. Interface ────────────────────────────────────────────────────
    local mCard = MakeSettingsCard(content, "Interface", 88)
    mCard:SetWidth(cardW)
    mCard:SetPoint("TOPLEFT", 0, y)
    y = y - 88 - CARD_GAP

    local mCb = MakeCheckRow(mCard, "Show minimap button", -40, function(on)
        if ns.SetMinimapShown then ns.SetMinimapShown(on) end
        local st = on and "|cff22c55eSHOWN|r" or "|cffef4444HIDDEN|r"
        print(string.format("|cff40c0ffAlterArena|r: Minimap button %s.", st))
        f.UpdateStatus()
    end)
    f.minimapCheckbox = mCb

    local mHint = mCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mHint:SetPoint("TOPLEFT", 44, -68)
    mHint:SetTextColor(0.55, 0.55, 0.6)
    mHint:SetText("Left-click open  ·  Right-click settings  ·  Shift-click debug")

    -- ── 5. Database ─────────────────────────────────────────────────────
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
    if f.scroll and f.scroll.UpdateThumb then
        f.scroll:UpdateThumb()
    end

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
            f.qtSoundBtn.text:SetText(entry and entry.label or id)
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
                f.alertSoundBtn.text:SetText(entry and entry.label or (cfg.sound or "—"))
            end
        end

        local dbg = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode
        local mirror = AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.mirrorDebugChat
        if f.debugCheckbox and f.debugCheckbox.checkTex then
            f.debugCheckbox.checkTex:SetShown(dbg)
        end
        if f.mirrorCheckbox and f.mirrorCheckbox.checkTex then
            f.mirrorCheckbox.checkTex:SetShown(mirror)
        end
        if f.debugStatusText then
            if dbg and mirror then
                f.debugStatusText:SetText("|cff888899Status:|r |cff22c55eOn|r  |cff888899(window + chat)|r")
            elseif dbg then
                f.debugStatusText:SetText("|cff888899Status:|r |cff22c55eOn|r  |cff888899(window only)|r")
            else
                f.debugStatusText:SetText("|cff888899Status:|r |cff888899Off|r")
            end
        end
        if f.minimapCheckbox and f.minimapCheckbox.checkTex then
            local shown = ns.IsMinimapShown and ns.IsMinimapShown()
            f.minimapCheckbox.checkTex:SetShown(shown)
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