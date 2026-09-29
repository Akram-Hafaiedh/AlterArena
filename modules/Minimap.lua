-- =========================================================================
-- AlterArena minimap button (no external libs — same pattern as CraftBell)
-- Left-click  → toggle main window
-- Right-click → open settings
-- Shift+click → toggle debug window
-- Drag        → reposition around minimap
-- =========================================================================

local ADDON_NAME, ns = ...

local minimapBtn

local DEFAULT_ANGLE = 220
local ICON_PATH = "Interface\\Icons\\Achievement_Arena_2v2_7"

local function GetAngle()
    if AlterArenaDB and AlterArenaDB.settings and AlterArenaDB.settings.minimapAngle then
        return AlterArenaDB.settings.minimapAngle
    end
    return DEFAULT_ANGLE
end

local function SetAngle(angle)
    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    AlterArenaDB.settings.minimapAngle = angle
end

local function IsHidden()
    return AlterArenaDB
        and AlterArenaDB.settings
        and AlterArenaDB.settings.minimapHide
end

local function UpdatePosition(btn)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    local angle = math.rad(GetAngle())
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
    if minimapBtn then return minimapBtn end

    local btn = CreateFrame("Button", "AlterArenaMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(ICON_PATH)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER", 11, -11)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local isDragging = false

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        isDragging = true
        btn:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if angle < 0 then angle = angle + 360 end
            SetAngle(angle)
            UpdatePosition(btn)
        end)
    end)
    btn:SetScript("OnDragStop", function()
        isDragging = false
        btn:SetScript("OnUpdate", nil)
    end)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(_, button)
        if isDragging then return end
        if IsShiftKeyDown() then
            if ns.ToggleDebugWindow then ns.ToggleDebugWindow() end
            return
        end
        if button == "RightButton" then
            if ns.OpenSettings then
                ns.OpenSettings()
            elseif ns.ToggleUI then
                ns.ToggleUI()
            end
        else
            if ns.ToggleUI then ns.ToggleUI() end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff40c0ffAlterArena|r")
        GameTooltip:AddLine("Cross-character PvP tracker", 0.75, 0.75, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffffLeft-click|r  Open / close", 0.6, 0.6, 0.65)
        GameTooltip:AddLine("|cffffffffRight-click|r  Settings", 0.6, 0.6, 0.65)
        GameTooltip:AddLine("|cffffffffShift-click|r  Debug window", 0.6, 0.6, 0.65)
        GameTooltip:AddLine("|cffffffffDrag|r  Move button", 0.6, 0.6, 0.65)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition(btn)
    if IsHidden() then
        btn:Hide()
    else
        btn:Show()
    end

    minimapBtn = btn
    return btn
end

function ns.InitMinimap()
    if not Minimap then return end
    CreateMinimapButton()
end

function ns.SetMinimapShown(shown)
    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    AlterArenaDB.settings.minimapHide = not shown
    if not minimapBtn then
        CreateMinimapButton()
    end
    if minimapBtn then
        if shown then minimapBtn:Show() else minimapBtn:Hide() end
    end
end

function ns.IsMinimapShown()
    return not IsHidden()
end

function ns.ToggleMinimap()
    local show = IsHidden()
    ns.SetMinimapShown(show)
    return show
end