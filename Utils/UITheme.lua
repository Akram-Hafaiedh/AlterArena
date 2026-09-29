-- =========================================================================
-- AlterArena UI theme kit (adapted from CraftBell)
-- Window size, accent color, background, font + custom toggle checkboxes.
-- =========================================================================

local ADDON_NAME, ns = ...

ns.UI = ns.UI or {}

ns.UI.colors = {
    bg          = { 0.06, 0.07, 0.09, 0.97 },
    bgRaised    = { 0.10, 0.11, 0.14, 1 },
    bgHover     = { 0.14, 0.16, 0.20, 1 },
    bgInput     = { 0.04, 0.05, 0.07, 1 },
    border      = { 0.22, 0.24, 0.28, 1 },
    borderSoft  = { 0.18, 0.20, 0.24, 0.9 },
    accent      = { 0.25, 0.75, 1.0, 1 },
    accentDim   = { 0.12, 0.45, 0.65, 1 },
    accentGlow  = { 0.25, 0.75, 1.0, 0.25 },
    text        = { 0.92, 0.93, 0.95, 1 },
    textMuted   = { 0.55, 0.58, 0.62, 1 },
    textDim     = { 0.40, 0.42, 0.46, 1 },
    danger      = { 0.85, 0.30, 0.32, 1 },
    success     = { 0.30, 0.80, 0.50, 1 },
    warning     = { 0.95, 0.70, 0.25, 1 },
}

ns.UI.C = ns.UI.colors
ns.UI.bgColor = ns.UI.colors.bg
ns.UI.borderColor = ns.UI.colors.border
ns.UI.accentColor = ns.UI.colors.accent

ns.UI.WINDOW_SIZES = {
    compact = { w = 860,  h = 480 },
    normal  = { w = 960,  h = 540 },
    large   = { w = 1100, h = 640 },
    xl      = { w = 1240, h = 720 },
}

ns.UI.COLOR_SCHEMES = {
    cyan = {
        accent     = { 0.25, 0.75, 1.0, 1 },
        accentDim  = { 0.12, 0.45, 0.65, 1 },
        accentGlow = { 0.25, 0.75, 1.0, 0.25 },
    },
    violet = {
        accent     = { 0.62, 0.42, 0.95, 1 },
        accentDim  = { 0.40, 0.28, 0.65, 1 },
        accentGlow = { 0.62, 0.42, 0.95, 0.25 },
    },
    emerald = {
        accent     = { 0.20, 0.82, 0.55, 1 },
        accentDim  = { 0.12, 0.50, 0.35, 1 },
        accentGlow = { 0.20, 0.82, 0.55, 0.25 },
    },
    amber = {
        accent     = { 0.95, 0.72, 0.25, 1 },
        accentDim  = { 0.65, 0.48, 0.15, 1 },
        accentGlow = { 0.95, 0.72, 0.25, 0.25 },
    },
    rose = {
        accent     = { 0.95, 0.40, 0.55, 1 },
        accentDim  = { 0.60, 0.25, 0.35, 1 },
        accentGlow = { 0.95, 0.40, 0.55, 0.25 },
    },
}

ns.UI.BG_SCHEMES = {
    slate = {
        bg         = { 0.06, 0.07, 0.09, 0.97 },
        bgRaised   = { 0.10, 0.11, 0.14, 1 },
        bgHover    = { 0.14, 0.16, 0.20, 1 },
        bgInput    = { 0.04, 0.05, 0.07, 1 },
        border     = { 0.22, 0.24, 0.28, 1 },
        borderSoft = { 0.18, 0.20, 0.24, 0.9 },
    },
    charcoal = {
        bg         = { 0.04, 0.04, 0.05, 0.98 },
        bgRaised   = { 0.08, 0.08, 0.10, 1 },
        bgHover    = { 0.12, 0.12, 0.14, 1 },
        bgInput    = { 0.03, 0.03, 0.04, 1 },
        border     = { 0.18, 0.18, 0.20, 1 },
        borderSoft = { 0.14, 0.14, 0.16, 0.9 },
    },
    midnight = {
        bg         = { 0.05, 0.07, 0.12, 0.97 },
        bgRaised   = { 0.08, 0.11, 0.18, 1 },
        bgHover    = { 0.12, 0.16, 0.24, 1 },
        bgInput    = { 0.03, 0.05, 0.09, 1 },
        border     = { 0.18, 0.24, 0.34, 1 },
        borderSoft = { 0.14, 0.18, 0.28, 0.9 },
    },
    graphite = {
        bg         = { 0.09, 0.09, 0.10, 0.97 },
        bgRaised   = { 0.13, 0.13, 0.14, 1 },
        bgHover    = { 0.18, 0.18, 0.19, 1 },
        bgInput    = { 0.06, 0.06, 0.07, 1 },
        border     = { 0.28, 0.28, 0.30, 1 },
        borderSoft = { 0.22, 0.22, 0.24, 0.9 },
    },
    warm = {
        bg         = { 0.08, 0.07, 0.06, 0.97 },
        bgRaised   = { 0.12, 0.10, 0.09, 1 },
        bgHover    = { 0.17, 0.14, 0.12, 1 },
        bgInput    = { 0.05, 0.04, 0.04, 1 },
        border     = { 0.28, 0.24, 0.20, 1 },
        borderSoft = { 0.22, 0.18, 0.16, 0.9 },
    },
}

ns.UI.FONTS = {
    default  = nil,
    friz     = "Fonts\\FRIZQT__.TTF",
    arialn   = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF",
    skurri   = "Fonts\\skurri.TTF",
}

ns.UI.backdrop = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

ns.UI._themedWidgets = ns.UI._themedWidgets or {}

local function Settings()
    return AlterArenaDB and AlterArenaDB.settings
end

local function CopyColorInto(dst, src)
    if not dst or not src then return end
    dst[1], dst[2], dst[3], dst[4] = src[1], src[2], src[3], src[4] or 1
end

function ns.UI.RegisterThemed(widget, refreshFn)
    if not widget then return end
    widget._aaRefreshTheme = refreshFn
    for _, w in ipairs(ns.UI._themedWidgets) do
        if w == widget then return end
    end
    table.insert(ns.UI._themedWidgets, widget)
end

function ns.UI.RefreshAllThemed()
    local list = ns.UI._themedWidgets
    for i = #list, 1, -1 do
        local w = list[i]
        if not w or (w.IsForbidden and w:IsForbidden()) then
            table.remove(list, i)
        elseif w._aaRefreshTheme then
            pcall(w._aaRefreshTheme, w)
        else
            table.remove(list, i)
        end
    end
end

function ns.UI.GetFontPath()
    local s = Settings()
    local key = (s and s.uiFont) or "default"
    return ns.UI.FONTS[key]
end

function ns.UI.ApplyColorScheme(schemeKey)
    local s = Settings()
    schemeKey = schemeKey or (s and s.colorScheme) or "cyan"
    local scheme = ns.UI.COLOR_SCHEMES[schemeKey] or ns.UI.COLOR_SCHEMES.cyan
    local c = ns.UI.colors
    CopyColorInto(c.accent, scheme.accent)
    CopyColorInto(c.accentDim, scheme.accentDim)
    CopyColorInto(c.accentGlow, scheme.accentGlow)
    ns.UI.accentColor = c.accent
    if s then s.colorScheme = schemeKey end
end

function ns.UI.ApplyBgScheme(bgKey)
    local s = Settings()
    bgKey = bgKey or (s and s.bgScheme) or "slate"
    local scheme = ns.UI.BG_SCHEMES[bgKey] or ns.UI.BG_SCHEMES.slate
    local c = ns.UI.colors
    CopyColorInto(c.bg, scheme.bg)
    CopyColorInto(c.bgRaised, scheme.bgRaised)
    CopyColorInto(c.bgHover, scheme.bgHover)
    CopyColorInto(c.bgInput, scheme.bgInput)
    CopyColorInto(c.border, scheme.border)
    CopyColorInto(c.borderSoft, scheme.borderSoft)
    ns.UI.bgColor = c.bg
    ns.UI.borderColor = c.border
    if s then s.bgScheme = bgKey end
end

function ns.UI.GetWindowSize()
    local s = Settings()
    local key = (s and s.windowSize) or "normal"
    return ns.UI.WINDOW_SIZES[key] or ns.UI.WINDOW_SIZES.normal, key
end

function ns.UI.ApplyMainWindowAppearance()
    local frame = ns.GetMainFrame and ns.GetMainFrame()
    if not frame then return end

    local size = ns.UI.GetWindowSize()
    if size then
        local ui = ns.ui
        if ui then
            ui.FRAME_WIDTH = size.w
            ui.FRAME_HEIGHT = size.h
        end
        frame:SetSize(size.w, size.h)
    end

    local c = ns.UI.colors
    if frame.SetBackdropColor then
        frame:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4] or 1)
        frame:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], c.border[4] or 1)
    end
end

function ns.UI.ApplyAppearance()
    local s = Settings()
    ns.UI.ApplyColorScheme(s and s.colorScheme or "cyan")
    ns.UI.ApplyBgScheme(s and s.bgScheme or "slate")
    ns.UI.RefreshAllThemed()
    ns.UI.ApplyMainWindowAppearance()
    if ns.RefreshUI then
        pcall(ns.RefreshUI)
    end
end

----------------------------------------------------------------------
-- Custom toggle (CraftBell-style track + knob)
----------------------------------------------------------------------
function ns.CreateUIToggle(parent, opts)
    opts = opts or {}
    local label = opts.label or ""
    local labelOnRight = opts.labelOnRight ~= false
    local checked = opts.checked and true or false
    local onChange = opts.onChange

    local trackW, trackH = 36, 18
    local knobSize, knobPad = 14, 2

    local root = CreateFrame("Button", nil, parent)
    root:SetHeight(math.max(trackH + 4, 22))
    root:EnableMouse(true)

    local track = CreateFrame("Frame", nil, root, "BackdropTemplate")
    track:SetSize(trackW, trackH)
    track:SetBackdrop(ns.UI.backdrop)
    root.track = track

    local knob = track:CreateTexture(nil, "OVERLAY")
    knob:SetSize(knobSize, knobSize)
    knob:SetTexture("Interface\\Buttons\\WHITE8x8")
    root.knob = knob

    local labelFS = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    labelFS:SetText(label)
    root.label = labelFS

    if labelOnRight then
        track:SetPoint("LEFT", root, "LEFT", 0, 0)
        labelFS:SetPoint("LEFT", track, "RIGHT", 10, 0)
        root:SetWidth(trackW + 10 + (labelFS:GetStringWidth() or 80) + 4)
    else
        labelFS:SetPoint("LEFT", root, "LEFT", 0, 0)
        track:SetPoint("LEFT", labelFS, "RIGHT", 10, 0)
        root:SetWidth((labelFS:GetStringWidth() or 80) + 10 + trackW + 4)
    end

    local function ApplyVisual()
        local a = ns.UI.colors.accent
        local bg = ns.UI.colors.bgRaised
        local border = ns.UI.colors.border
        local text = ns.UI.colors.text
        if checked then
            track:SetBackdropColor(a[1], a[2], a[3], 0.85)
            track:SetBackdropBorderColor(a[1], a[2], a[3], 1)
            knob:SetVertexColor(0.95, 0.97, 1, 1)
            knob:ClearAllPoints()
            knob:SetPoint("RIGHT", track, "RIGHT", -knobPad, 0)
        else
            track:SetBackdropColor(bg[1], bg[2], bg[3], 1)
            track:SetBackdropBorderColor(border[1], border[2], border[3], 1)
            knob:SetVertexColor(0.55, 0.58, 0.62, 1)
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", track, "LEFT", knobPad, 0)
        end
        labelFS:SetTextColor(text[1], text[2], text[3], text[4] or 1)
    end

    local function SetChecked(value, silent)
        checked = value and true or false
        ApplyVisual()
        if not silent and onChange then
            onChange(checked)
        end
    end

    root:SetScript("OnClick", function()
        if root._disabled then return end
        SetChecked(not checked, false)
    end)
    root:SetScript("OnEnter", function()
        if root._disabled then return end
        local a = ns.UI.colors.accent
        local hover = ns.UI.colors.bgHover
        if checked then
            track:SetBackdropColor(
                math.min(1, a[1] + 0.08),
                math.min(1, a[2] + 0.08),
                math.min(1, a[3] + 0.08),
                0.95
            )
        else
            track:SetBackdropColor(hover[1], hover[2], hover[3], 1)
        end
    end)
    root:SetScript("OnLeave", function()
        ApplyVisual()
    end)

    function root:SetChecked(v, silent) SetChecked(v, silent) end
    function root:GetChecked() return checked end
    function root:SetEnabled(enabled)
        root._disabled = not enabled
        root:SetAlpha(enabled and 1 or 0.45)
    end
    function root:SetLabel(text)
        labelFS:SetText(text or "")
        if labelOnRight then
            root:SetWidth(trackW + 10 + (labelFS:GetStringWidth() or 80) + 4)
        else
            root:SetWidth((labelFS:GetStringWidth() or 80) + 10 + trackW + 4)
        end
    end

    -- Compat with old MakeCheckRow checkTex:Show/Hide pattern used by UpdateStatus
    root.checkTex = {
        SetShown = function(_, shown) SetChecked(shown, true) end,
        Show = function() SetChecked(true, true) end,
        Hide = function() SetChecked(false, true) end,
        IsShown = function() return checked end,
    }

    ApplyVisual()
    ns.UI.RegisterThemed(root, ApplyVisual)
    return root
end

function ns.UI.Init()
    local s = Settings()
    if s then
        ns.UI.ApplyColorScheme(s.colorScheme or "cyan")
        ns.UI.ApplyBgScheme(s.bgScheme or "slate")
    end
end