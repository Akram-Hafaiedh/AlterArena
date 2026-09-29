-- =========================================================================
-- AlterArena Debug subsystem
-- Ring-buffer log + debug window (checklist + log), patterned after
-- RealmDisplay / CraftBell / ArtisansCodex.
-- =========================================================================

local ADDON_NAME, ns = ...

local MAX_LOG = 300
local logBuffer = {} -- { { t = "HH:MM:SS", text = "..." }, ... } newest last
local debugFrame -- forward-declared for closures

ns.debugLastRun = nil
ns.debugCurrentRun = nil

-- Optional step order for pipeline self-tests (extend as needed)
local STEP_ORDER = {
    { key = "db",       label = "Database ready" },
    { key = "player",   label = "Player record present" },
    { key = "ratings",  label = "Live ratings fetched" },
    { key = "matches",  label = "Match history loaded" },
    { key = "ui",       label = "Main UI built" },
    { key = "refresh",  label = "UI refresh completed" },
}

----------------------------------------------------------------------
-- Log buffer
----------------------------------------------------------------------

function ns.DebugIsEnabled()
    return AlterArenaDB
        and AlterArenaDB.settings
        and AlterArenaDB.settings.debugMode
end

--- Append to ring buffer. Always stores; only mirrors to chat when debug is on
--- (unless opts.forceChat). opts.silent skips chat entirely.
function ns.DebugLog(msg, opts)
    opts = opts or {}
    local text = tostring(msg)
    local entry = {
        t = date("%H:%M:%S"),
        text = text,
    }
    logBuffer[#logBuffer + 1] = entry
    while #logBuffer > MAX_LOG do
        table.remove(logBuffer, 1)
    end

    -- Log always goes to the debug window buffer.
    -- Chat mirror is opt-in (settings.mirrorDebugChat or opts.forceChat).
    local mirror = opts.forceChat
        or (not opts.silent and AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.mirrorDebugChat)
    if mirror then
        print("|cff40c0ff[AA-DEBUG]|r", text)
    end

    if debugFrame and debugFrame:IsShown() and debugFrame.RefreshLog then
        debugFrame:RefreshLog()
    end
end

-- Keep existing call sites working; also feed the ring buffer
function ns.DebugPrint(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    ns.DebugLog(table.concat(parts, " "))
end

function ns.DebugClearLog()
    wipe(logBuffer)
    if debugFrame and debugFrame.RefreshLog then
        debugFrame:RefreshLog()
    end
end

function ns.GetDebugLog()
    return logBuffer
end

--- Plain-text log (no color codes) for clipboard export
function ns.GetDebugLogText()
    local lines = {}
    for i = 1, #logBuffer do
        local e = logBuffer[i]
        local plain = e.text
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|r", "")
            :gsub("|T.-|t", "")
        lines[#lines + 1] = string.format("[%s] %s", e.t, plain)
    end
    return table.concat(lines, "\n")
end

--- ArtisansCodex-style copy panel: selectable EditBox so Ctrl+C works
--- (system clipboard is restricted / in-game only on many clients).
function ns.ShowDebugCopyPanel(text, parent)
    parent = parent or UIParent

    if ns._debugCopyPanel then
        ns._debugCopyPanel:Hide()
        ns._debugCopyPanel:SetParent(nil)
        ns._debugCopyPanel = nil
    end

    local box = CreateFrame("Frame", "AlterArenaDebugCopyPanel", parent, "BackdropTemplate")
    box:SetSize(560, 320)
    box:SetPoint("CENTER")
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)
    box:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.06, 0.07, 0.10, 0.98)
    box:SetBackdropBorderColor(0.25, 0.75, 1.0, 0.7)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)

    local titleFS = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT", 12, -10)
    titleFS:SetText("|cff40c0ffCopy log|r  -  Select all, then Ctrl+C")

    local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        box:Hide()
        box:SetParent(nil)
        if ns._debugCopyPanel == box then ns._debugCopyPanel = nil end
    end)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetWidth(500)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function()
        box:Hide()
        edit:ClearFocus()
    end)
    scroll:SetScrollChild(edit)

    local body = text or ""
    edit:SetText(body)
    local lineCount = 1
    for _ in body:gmatch("\n") do lineCount = lineCount + 1 end
    edit:SetHeight(math.max(240, lineCount * 14))

    local selectBtn = CreateFrame("Button", nil, box, "BackdropTemplate")
    selectBtn:SetSize(100, 24)
    selectBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    selectBtn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    selectBtn:SetBackdropColor(0.12, 0.13, 0.16, 0.95)
    selectBtn:SetBackdropBorderColor(0.25, 0.75, 1.0, 0.7)
    selectBtn.text = selectBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selectBtn.text:SetPoint("CENTER")
    selectBtn.text:SetText("Select all")
    selectBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.22, 0.28, 1)
    end)
    selectBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.13, 0.16, 0.95)
    end)
    selectBtn:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 14)
    hint:SetTextColor(0.65, 0.65, 0.65)
    hint:SetText("Ctrl+A / Ctrl+C to copy, Esc or X to close.")

    ns._debugCopyPanel = box
    box:Show()
    box:Raise()
    edit:SetFocus()
    edit:HighlightText()
end


----------------------------------------------------------------------
-- Step checklist (pipeline runs)
----------------------------------------------------------------------

function ns.DebugStartRun(mode)
    mode = mode or "selftest"
    local run = {
        mode = mode,
        started = time(),
        steps = {},
        byKey = {},
    }
    ns.debugCurrentRun = run
    ns.DebugLog(string.format("-- run started (%s)", mode), { silent = not ns.DebugIsEnabled() })
    return run
end

function ns.DebugStep(key, ok, detail)
    local run = ns.debugCurrentRun
    if not run then return end
    local step = { key = key, ok = ok and true or false, detail = detail }
    -- replace if same key already recorded
    if run.byKey[key] then
        for i, s in ipairs(run.steps) do
            if s.key == key then
                run.steps[i] = step
                break
            end
        end
    else
        run.steps[#run.steps + 1] = step
    end
    run.byKey[key] = step

    local label = key
    for _, def in ipairs(STEP_ORDER) do
        if def.key == key then label = def.label break end
    end
    ns.DebugLog(string.format("  %s %s%s",
        ok and "|cff22c55eOK|r" or "|cffef4444FAIL|r",
        label,
        detail and (" - " .. tostring(detail)) or ""),
        { silent = not ns.DebugIsEnabled() })

    if debugFrame and debugFrame:IsShown() and debugFrame.RefreshChecklist then
        debugFrame:RefreshChecklist()
    end
end

function ns.DebugEndRun()
    local run = ns.debugCurrentRun
    if not run then return end
    ns.debugLastRun = run
    ns.debugCurrentRun = nil

    local pass, fail = 0, 0
    for _, s in ipairs(run.steps) do
        if s.ok then pass = pass + 1 else fail = fail + 1 end
    end
    ns.DebugLog(string.format("-- done - %d ok, %d fail", pass, fail),
        { silent = not ns.DebugIsEnabled() })

    if debugFrame and debugFrame:IsShown() then
        if debugFrame.RefreshChecklist then debugFrame:RefreshChecklist() end
        if debugFrame.RefreshLog then debugFrame:RefreshLog() end
    end
    return run
end

function ns.GetDebugRunForDisplay()
    return ns.debugCurrentRun or ns.debugLastRun
end

local function OrderedSteps(run)
    if not run then return {} end
    local out, seen = {}, {}
    for _, def in ipairs(STEP_ORDER) do
        local s = run.byKey[def.key]
        if s then
            out[#out + 1] = { key = def.key, label = def.label, ok = s.ok, detail = s.detail }
            seen[def.key] = true
        else
            out[#out + 1] = { key = def.key, label = def.label, ok = nil, detail = "not run" }
        end
    end
    for _, s in ipairs(run.steps) do
        if not seen[s.key] then
            out[#out + 1] = { key = s.key, label = s.key, ok = s.ok, detail = s.detail }
        end
    end
    return out
end

----------------------------------------------------------------------
-- Built-in self-test
----------------------------------------------------------------------

function ns.RunDebugSelfTest()
    ns.DebugStartRun("selftest")

    local dbOk = type(AlterArenaDB) == "table"
        and type(AlterArenaDB.players) == "table"
        and type(AlterArenaDB.settings) == "table"
    ns.DebugStep("db", dbOk, dbOk and "AlterArenaDB OK" or "missing tables")

    local key = ns.GetPlayerKey and ns.GetPlayerKey()
    local rec = key and AlterArenaDB.players and AlterArenaDB.players[key]
    ns.DebugStep("player", rec ~= nil,
        rec and string.format("%s (%s)", tostring(rec.name), tostring(rec.class))
            or ("no record for " .. tostring(key)))

    local hasRatings = rec and type(rec.bracketRatings) == "table" and next(rec.bracketRatings) ~= nil
    ns.DebugStep("ratings", hasRatings ~= nil,
        hasRatings and "bracketRatings present" or "empty / not yet fetched")

    local matchCount = (rec and rec.matches and #rec.matches) or 0
    local totalMatches = 0
    if AlterArenaDB.players then
        for _, p in pairs(AlterArenaDB.players) do
            totalMatches = totalMatches + ((p.matches and #p.matches) or 0)
        end
    end
    ns.DebugStep("matches", true,
        string.format("this char %d / all chars %d", matchCount, totalMatches))

    -- Main UI is built lazily on first /aa. Force-create for the self-test.
    local frame = ns.GetMainFrame and ns.GetMainFrame()
    if not frame and ns.EnsureMainFrame then
        local okBuild, errBuild = pcall(ns.EnsureMainFrame)
        frame = ns.GetMainFrame and ns.GetMainFrame()
        if not okBuild then
            ns.DebugLog("EnsureMainFrame error: " .. tostring(errBuild))
        end
    end
    ns.DebugStep("ui", frame ~= nil,
        frame and "main frame exists" or "not built yet")

    if frame and ns.RefreshUI then
        local ok, err = pcall(ns.RefreshUI)
        ns.DebugStep("refresh", ok, ok and "RefreshUI OK" or tostring(err))
    else
        ns.DebugStep("refresh", false, "RefreshUI unavailable")
    end

    ns.DebugEndRun()
end

----------------------------------------------------------------------
-- Debug window UI
----------------------------------------------------------------------


local function EnsureDebugFrame()
    if debugFrame then return debugFrame end

    local f = CreateFrame("Frame", "AlterArenaDebugFrame", UIParent, "BackdropTemplate")
    f:SetSize(720, 420)
    f:SetPoint("CENTER", 0, 20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.07, 0.07, 0.09, 0.97)
    f:SetBackdropBorderColor(0.20, 0.21, 0.25, 0.95)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cff40c0ffAlterArena|r Debug")

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", title, "RIGHT", 12, 0)
    f.statusText = status

    -- Close
    local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -10, -8)
    closeBtn:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    closeBtn:SetBackdropColor(0.12, 0.13, 0.16, 1)
    closeBtn:SetBackdropBorderColor(0.22, 0.23, 0.28, 1)
    local x = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    x:SetPoint("CENTER", 0, 1)
    x:SetText("×")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.25, 0.75, 1, 0.25)
        self:SetBackdropBorderColor(0.25, 0.75, 1, 0.8)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.13, 0.16, 1)
        self:SetBackdropBorderColor(0.22, 0.23, 0.28, 1)
    end)

    -- Checklist header
    local checkHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkHeader:SetPoint("TOPLEFT", 14, -42)
    checkHeader:SetText("|cff888899Checklist|r")

    local checkScroll, checkChild
    if ns.CreateScrollFrame then
        checkScroll, checkChild = ns.CreateScrollFrame(f)
    else
        checkScroll = CreateFrame("ScrollFrame", nil, f)
        checkChild = CreateFrame("Frame", nil, checkScroll)
        checkScroll:SetScrollChild(checkChild)
        checkScroll:EnableMouseWheel(true)
    end
    checkScroll:SetPoint("TOPLEFT", 12, -60)
    checkScroll:SetPoint("BOTTOMLEFT", 12, 52)
    checkScroll:SetWidth(240)
    checkChild:SetWidth(220)
    f.checkScroll = checkScroll
    f.checkChild = checkChild

    -- Log header
    local logHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logHeader:SetPoint("TOPLEFT", checkScroll, "TOPRIGHT", 28, 18)
    logHeader:SetText("|cff888899Log|r")

    local logScroll, logChild
    if ns.CreateScrollFrame then
        logScroll, logChild = ns.CreateScrollFrame(f)
    else
        logScroll = CreateFrame("ScrollFrame", nil, f)
        logChild = CreateFrame("Frame", nil, logScroll)
        logScroll:SetScrollChild(logChild)
        logScroll:EnableMouseWheel(true)
    end
    logScroll:SetPoint("TOPLEFT", checkScroll, "TOPRIGHT", 24, 0)
    logScroll:SetPoint("BOTTOMRIGHT", -18, 52)
    logChild:SetWidth(400)
    f.logScroll = logScroll
    f.logChild = logChild

    local logText = logChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logText:SetPoint("TOPLEFT", 4, -4)
    logText:SetJustifyH("LEFT")
    logText:SetJustifyV("TOP")
    logText:SetWordWrap(true)
    logText:SetNonSpaceWrap(true)
    f.logText = logText

    function f:RefreshLog()
        local lines = {}
        for i = 1, #logBuffer do
            local e = logBuffer[i]
            lines[#lines + 1] = string.format("|cff666677%s|r  %s", e.t, e.text)
        end
        local body = #lines > 0 and table.concat(lines, "\n") or "|cff666677(empty - enable debug and use the addon)|r"
        logText:SetWidth(math.max((logScroll:GetWidth() or 260) - 14, 100))
        logText:SetText(body)

        local h = math.max(logText:GetStringHeight() + 12, logScroll:GetHeight() or 100)
        logChild:SetHeight(h)
        logChild:SetWidth(math.max((logScroll:GetWidth() or 260) - 10, 100))

        if logScroll.UpdateThumb then logScroll:UpdateThumb() end

        -- Auto-scroll to bottom
        local viewH = logScroll:GetHeight() or 1
        local childH = logChild:GetHeight() or 1
        local maxScroll = math.max(childH - viewH, 0)
        logScroll:SetVerticalScroll(maxScroll)
        if logScroll.UpdateThumb then logScroll:UpdateThumb() end
    end

    logScroll:SetScript("OnSizeChanged", function()
        if f.RefreshLog then f:RefreshLog() end
    end)

    function f:RefreshChecklist()
        -- wipe previous rows
        if checkChild.rows then
            for _, row in ipairs(checkChild.rows) do
                row:Hide()
                row:SetParent(nil)
            end
        end
        checkChild.rows = {}

        local run = ns.GetDebugRunForDisplay()
        local y = 4
        local steps = OrderedSteps(run)
        if #steps == 0 then
            local empty = checkChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", 4, -y)
            empty:SetWidth(210)
            empty:SetJustifyH("LEFT")
            empty:SetText("Run self-test or enable Debug\nand use the addon.")
            checkChild.rows[1] = empty
            y = y + 40
        else
            for _, s in ipairs(steps) do
                local row = CreateFrame("Frame", nil, checkChild)
                row:SetSize(210, 28)
                row:SetPoint("TOPLEFT", 0, -y)

                local mark = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                mark:SetPoint("LEFT", 2, 0)
                if s.ok == true then
                    mark:SetText("|cff22c55eOK|r")
                elseif s.ok == false then
                    mark:SetText("|cffef4444FAIL|r")
                else
                    mark:SetText("|cff888888-|r")
                end

                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", 36, 6)
                label:SetPoint("RIGHT", -4, 6)
                label:SetJustifyH("LEFT")
                label:SetText(s.label or s.key)

                if s.detail then
                    local det = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                    det:SetPoint("LEFT", 36, -8)
                    det:SetPoint("RIGHT", -4, -8)
                    det:SetJustifyH("LEFT")
                    det:SetText(s.detail)
                end

                checkChild.rows[#checkChild.rows + 1] = row
                y = y + 30
            end
        end
        checkChild:SetHeight(math.max(y + 8, 1))
        if checkScroll.UpdateThumb then checkScroll:UpdateThumb() end
    end

    local function RefreshToggleLabel()
        local on = ns.DebugIsEnabled()
        f.statusText:SetText(on and "|cff22c55eDEBUG ON|r" or "|cff888888debug off|r")
    end

    function f:RefreshAll()
        RefreshToggleLabel()
        self:RefreshChecklist()
        self:RefreshLog()
    end

    f:SetScript("OnShow", function(self) self:RefreshAll() end)

    -- Bottom buttons
    local function MakeBtn(label, width)
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(width, 26)
        btn:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.12, 0.13, 0.16, 0.95)
        btn:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(label)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.20, 0.22, 0.28, 1)
            self:SetBackdropBorderColor(0.4, 0.45, 0.55, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.12, 0.13, 0.16, 0.95)
            self:SetBackdropBorderColor(0.22, 0.23, 0.28, 0.9)
        end)
        return btn
    end

    local toggleBtn = MakeBtn("Toggle Debug", 100)
    toggleBtn:SetPoint("BOTTOMLEFT", 12, 14)
    toggleBtn:SetScript("OnClick", function()
        if AlterArenaDB and AlterArenaDB.settings then
            AlterArenaDB.settings.debugMode = not AlterArenaDB.settings.debugMode
            local on = AlterArenaDB.settings.debugMode
            print(string.format("|cff40c0ffAlterArena|r: Debug mode %s.",
                on and "|cff22c55eENABLED|r" or "|cffef4444DISABLED|r"))
            RefreshToggleLabel()
        end
    end)

    local testBtn = MakeBtn("Run Self-Test", 110)
    testBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 8, 0)
    testBtn:SetScript("OnClick", function()
        ns.RunDebugSelfTest()
        f:RefreshAll()
    end)

    local clearBtn = MakeBtn("Clear Log", 90)
    clearBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)
    clearBtn:SetScript("OnClick", function()
        ns.DebugClearLog()
    end)

    local copyBtn = MakeBtn("Copy Log", 90)
    copyBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    copyBtn:SetScript("OnClick", function()
        local parts = { "=== AlterArena Debug ===", "" }
        local run = ns.GetDebugRunForDisplay and ns.GetDebugRunForDisplay()
        if run then
            parts[#parts + 1] = string.format("Mode: %s  Started: %s",
                tostring(run.mode), date("%H:%M:%S", run.started or time()))
            parts[#parts + 1] = ""
            parts[#parts + 1] = "-- Steps --"
            for _, s in ipairs(OrderedSteps(run)) do
                local mark = s.ok == true and "OK" or (s.ok == false and "FAIL" or "-")
                parts[#parts + 1] = string.format("[%s] %s%s",
                    mark, s.label or s.key,
                    s.detail and (" - " .. tostring(s.detail)) or "")
            end
            parts[#parts + 1] = ""
        end
        parts[#parts + 1] = "-- Log --"
        parts[#parts + 1] = ns.GetDebugLogText and ns.GetDebugLogText() or ""
        local text = table.concat(parts, "\n")
        ns.ShowDebugCopyPanel(text, f)
    end)

    debugFrame = f
    return f
end

function ns.ToggleDebugWindow(forceShow)
    local f = EnsureDebugFrame()
    if forceShow then
        f:Show()
        f:Raise()
        f:RefreshAll()
        return
    end
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        f:Raise()
        f:RefreshAll()
    end
end

function ns.InitDebug()
    if AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.debugMode then
        -- keep flag; window stays lazy
    end
    ns.DebugLog("Debug module loaded", { silent = true })
end