const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const fengari = require('fengari');
const lua = fengari.lua;
const lauxlib = fengari.lauxlib;
const lualib = fengari.lualib;
const interop = fengari.interop;

console.log('====================================================');
console.log('       AlterArena Lua Test & Verification Suite     ');
console.log('====================================================\n');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function pass(msg) {
    totalTests++;
    passedTests++;
    console.log(`  \x1b[32m✔\x1b[0m ${msg}`);
}

function fail(msg, err) {
    totalTests++;
    failedTests++;
    console.error(`  \x1b[31m✖\x1b[0m ${msg}`);
    if (err) console.error(`    ${err}`);
}

// 1. Parse AlterArena.toc to get ordered file list
console.log('[1/3] Reading TOC and Checking Lua File Syntax...');
const tocPath = path.join(__dirname, 'AlterArena.toc');
if (!fs.existsSync(tocPath)) {
    fail('AlterArena.toc not found');
    process.exit(1);
}
const tocContent = fs.readFileSync(tocPath, 'utf8');
const luaFiles = tocContent
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('#') && line.endsWith('.lua'));

console.log(`  Found ${luaFiles.length} files in AlterArena.toc: ${luaFiles.join(', ')}`);

const FORBIDDEN_PATTERNS = [
    { pattern: /COMBAT_LOG_EVENT_UNFILTERED/, reason: 'Protected event in Retail WoW 11.0+/Midnight (causes ADDON_ACTION_FORBIDDEN)' },
    { pattern: /RegisterEvent\s*\(\s*["']UNIT_SPELLCAST_SUCCEEDED["']\s*\)/, reason: 'Protected/restricted global event registration in Retail WoW (causes ADDON_ACTION_FORBIDDEN)' },
    { pattern: /CombatLogGetCurrentEventInfo\s*\(/, reason: 'Restricted/deprecated combat log API' },
];

for (const file of luaFiles) {
    const filePath = path.join(__dirname, file);
    if (!fs.existsSync(filePath)) {
        fail(`File missing: ${file}`);
        continue;
    }
    const code = fs.readFileSync(filePath, 'utf8');

    // Syntax check
    try {
        luaparse.parse(code, { luaVersion: '5.1' });
        pass(`${file} syntax is valid (Lua 5.1 / WoW Lua)`);
    } catch (e) {
        fail(`${file} syntax error at line ${e.line}:${e.column}: ${e.message}`);
    }

    // Forbidden patterns check
    for (const item of FORBIDDEN_PATTERNS) {
        if (item.pattern.test(code)) {
            fail(`${file} contains forbidden pattern: ${item.pattern} (${item.reason})`);
        }
    }
}

// 3. Mock World of Warcraft Environment & Runtime Execution Test
console.log('\n[2/3] Simulating WoW Addon Runtime (Fengari VM)...');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// Lua helper to run Lua strings and assert no error
function runLua(code, desc) {
    const status = lauxlib.luaL_dostring(L, fengari.to_luastring(code));
    if (status !== lua.LUA_OK) {
        const err = lua.lua_tojsstring(L, -1);
        lua.lua_pop(L, 1);
        fail(desc || 'Lua execution error', err);
        return false;
    }
    if (desc) pass(desc);
    return true;
}

// Initialize Mock WoW Environment in Lua
const mockWoW = `
-- Mock WoW Global Environment
_G = _G or {}
AlterArenaDB = {}

-- Standard WoW table utils
function wipe(t)
    if type(t) == "table" then
        for k in pairs(t) do t[k] = nil end
    end
    return t
end

function strtrim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

-- Mock Math & String
math.floor = math.floor
math.max = math.max
math.min = math.min
time = os.time
GetTime = function() return os.clock() end

-- Mock Player and Realm info
function UnitName(unit)
    if unit == "player" then return "TestPlayer" end
    if string.find(unit or "", "arena") then return "Opponent_" .. tostring(unit) end
    if string.find(unit or "", "party") then return "Teammate_" .. tostring(unit) end
    return "MockUnit"
end

function UnitGUID(unit)
    return "Player-1234-" .. tostring(unit)
end

function UnitClass(unit)
    return "Warlock", "WARLOCK"
end

function UnitFactionGroup(unit)
    return "Horde"
end

function UnitExists(unit)
    return true
end

function GetRealmName()
    return "TwistingNether"
end

function GetRealZoneText()
    return "Nagrand Arena"
end

function Ambiguate(name, context)
    if not name then return "" end
    return name:match("^([^%-]+)") or name
end

-- Mock Specialization Info
function GetSpecialization()
    return 1
end

function GetSpecializationInfo(specIndex)
    return 267, "Destruction", "A master of chaos", 136186, "Interface/Icons/Spell_Shadow_RainOfFire", "WARLOCK"
end

function GetSpecializationInfoByID(specID)
    return specID, "Destruction", "A master of chaos", 136186, "Interface/Icons/Spell_Shadow_RainOfFire", "WARLOCK"
end

function GetNumArenaOpponents()
    return 3
end

function GetArenaOpponentSpec(i)
    return 267
end

function IsActiveBattlefieldArena()
    return false
end

-- Mock PvP Info
C_PvP = {
    IsRatedArena = function() return true end,
    GetScoreInfo = function(i)
        return {
            guid = "Player-1234-player",
            name = "TestPlayer-TwistingNether",
            faction = 0,
            team = 0,
            damage = 1500000,
            healing = 500000,
            killingBlows = 3,
            deaths = 0,
            honorableKills = 3,
            ratingChange = 15,
            prematchMMR = 1800,
            postmatchMMR = 1815,
            mmrChange = 15,
            roundStats = { roundsWon = 4, roundsPlayed = 6 },
            talentSpec = "Destruction",
            classToken = "WARLOCK"
        }
    end
}

function GetNumBattlefieldScores()
    return 6
end

function RequestBattlefieldScoreData()
end

function GetPersonalRatedInfo(idx)
    -- idx 1: 2v2, idx 2: 3v3, idx 7: Solo Shuffle, idx 9: Blitz
    if idx == 1 then return 1750, 0, 0, 10, 6, 0, 0, 0, 0, 0, 0, 0, 0 end
    if idx == 2 then return 1820, 0, 0, 20, 12, 0, 0, 0, 0, 0, 0, 0, 0 end
    if idx == 7 or idx == 4 then return 1950, 0, 0, 5, 4, 0, 0, 0, 0, 0, 0, 30, 18 end
    if idx == 9 or idx == 8 then return 1600, 0, 0, 8, 5, 0, 0, 0, 0, 0, 0, 0, 0 end
    return 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
end

function RequestRatedInfo() end

function GetBattlefieldStatus(slot)
    if slot == 1 then
        return "queued", "Nagrand Arena", 3, nil, nil, "RATEDSHUFFLE", nil, nil, nil, nil, nil, true
    end
    return "none"
end

function GetBattlefieldTimeWaited(slot)
    return 45000
end

function GetBattlefieldEstimatedWaitTime(slot)
    return 120000
end

function GetMaxBattlefieldID()
    return 2
end

function PlaySound(id) return true end
function PlaySoundFile(f) return true end

C_AddOns = {
    LoadAddOn = function(name) return true, "Loaded" end
}

C_Timer = {
    After = function(delay, callback)
        -- Can execute immediately or store
        if callback then
            local ok, err = pcall(callback)
            if not ok then error("C_Timer.After callback error: " .. tostring(err)) end
        end
    end
}

-- Mock UI Hierarchy
UIParent = {
    GetName = function() return "UIParent" end,
    GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
    GetWidth = function() return 1920 end,
    GetHeight = function() return 1080 end,
}

RAID_CLASS_COLORS = {
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    MAGE = { r = 0.41, g = 0.80, b = 0.94, colorStr = "ff69ccf0" },
    PRIEST = { r = 1.0, g = 1.0, b = 1.0, colorStr = "ffffffff" },
}

-- Mock Frame Factory
registeredEventFrames = {}

local function createMockFontString()
    local fs = { shown = true, text = "", width = 100, height = 20 }
    function fs:SetPoint(...) end
    function fs:SetJustifyH(...) end
    function fs:SetJustifyV(...) end
    function fs:SetSpacing(...) end
    function fs:SetText(t) self.text = tostring(t or "") end
    function fs:GetText() return self.text or "" end
    function fs:GetStringWidth() return 120 end
    function fs:GetStringHeight() return 20 end
    function fs:SetWidth(w) self.width = w end
    function fs:SetHeight(h) self.height = h end
    function fs:SetSize(w, h) self.width = w; self.height = h end
    function fs:GetWidth() return self.width or 100 end
    function fs:GetHeight() return self.height or 20 end
    function fs:SetTextColor(...) end
    function fs:SetShadowOffset(...) end
    function fs:SetFont(...) end
    function fs:GetFont() return "Fonts/FRIZQT__.TTF", 12, "" end
    function fs:SetWordWrap(...) end
    function fs:SetAlpha(...) end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:IsShown() return self.shown end
    function fs:SetShown(s) self.shown = (s == true) end
    return fs
end

local function createMockTexture()
    local tex = { shown = true, width = 20, height = 20 }
    function tex:SetPoint(...) end
    function tex:SetSize(w, h) self.width = w; self.height = h end
    function tex:SetWidth(w) self.width = w end
    function tex:SetHeight(h) self.height = h end
    function tex:GetWidth() return self.width or 20 end
    function tex:GetHeight() return self.height or 20 end
    function tex:SetTexture(...) end
    function tex:SetTexCoord(...) end
    function tex:SetColorTexture(...) end
    function tex:SetVertexColor(...) end
    function tex:SetAlpha(...) end
    function tex:Show() self.shown = true end
    function tex:Hide() self.shown = false end
    function tex:IsShown() return self.shown end
    function tex:SetShown(s) self.shown = (s == true) end
    return tex
end

function CreateFrame(frameType, name, parent, template)
    local f = {
        name = name,
        scripts = {},
        events = {},
        children = {},
        shown = true
    }
    table.insert(registeredEventFrames, f)

    function f:SetSize(w, h) self.width = w; self.height = h end
    function f:SetWidth(w) self.width = w end
    function f:SetHeight(h) self.height = h end
    function f:GetWidth() return self.width or 100 end
    function f:GetHeight() return self.height or 100 end
    function f:GetName() return self.name or "" end
    function f:SetPoint(...) end
    function f:ClearAllPoints() end
    function f:GetPoint() return "TOPLEFT", nil, "TOPLEFT", 0, 0 end
    function f:SetFrameStrata(...) end
    function f:SetFrameLevel(...) end
    function f:SetClampedToScreen(...) end
    function f:SetMovable(...) end
    function f:EnableMouse(...) end
    function f:RegisterForDrag(...) end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:SetBackdrop(...) end
    function f:SetBackdropColor(...) end
    function f:SetBackdropBorderColor(...) end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetShown(s) self.shown = (s == true) end
    function f:Raise() end
    function f:SetAlpha(a) self.alpha = a end
    function f:GetAlpha() return self.alpha or 1 end
    function f:SetScrollChild(child) self.scrollChild = child end
    function f:GetVerticalScroll() return 0 end
    function f:SetVerticalScroll(v) end
    function f:GetVerticalScrollRange() return 0 end
    function f:HookScript(handler, fn) end
    
    function f:SetScript(handler, fn)
        self.scripts[handler] = fn
    end
    function f:GetScript(handler)
        return self.scripts[handler]
    end

    function f:RegisterEvent(event)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
            error("ADDON_ACTION_FORBIDDEN: protected function Frame:RegisterEvent() called with " .. tostring(event))
        end
        self.events[event] = true
    end
    function f:UnregisterEvent(event)
        self.events[event] = nil
    end

    function f:CreateFontString(name, layer, inherits)
        local fs = createMockFontString()
        if name then _G[name] = fs end
        return fs
    end
    function f:CreateTexture(name, layer, inherits)
        local tex = createMockTexture()
        if name then _G[name] = tex end
        return tex
    end

    if name then
        _G[name] = f
        if template and string.find(template, "ScrollFrame") then
            local sb = CreateFrame("Slider", name .. "ScrollBar", f)
            _G[name .. "ScrollBar"] = sb
        end
    end

    return f
end

SLASH_ALTERARENA1 = nil
SLASH_ALTERARENA2 = nil
SlashCmdList = {}

-- Event dispatcher simulation helper
function FireWoWEvent(event, ...)
    for _, frame in ipairs(registeredEventFrames) do
        if frame.events[event] and frame.scripts["OnEvent"] then
            frame.scripts["OnEvent"](frame, event, ...)
        end
    end
end
`;

runLua(mockWoW, 'Initialized WoW API mock framework');

// Shared Addon Namespace table
runLua(`
    ADDON_NAME = "AlterArena"
    ns = {}
`, 'Created AlterArena addon namespace');

// Load and execute each Lua file sequentially as WoW does
for (const file of luaFiles) {
    const filePath = path.join(__dirname, file);
    const code = fs.readFileSync(filePath, 'utf8');

    // In WoW, each file runs as a chunk with varargs: local ADDON_NAME, ns = ...
    const wrapper = `
        local fileFunc = function(...)
            ${code}
        end
        fileFunc(ADDON_NAME, ns)
    `;

    const ok = runLua(wrapper, `Executed ${file} in mock WoW runtime`);
    if (!ok) {
        console.error(`Execution halted on ${file}`);
        process.exit(1);
    }
}

// 4. Test Event Lifecycle & Feature Triggers
console.log('\n[3/3] Simulating In-Game Events & User Interactions...');

runLua(`
    -- 1. ADDON_LOADED
    FireWoWEvent("ADDON_LOADED", "AlterArena")
`, 'Triggered ADDON_LOADED event');

runLua(`
    -- 2. PLAYER_ENTERING_WORLD
    FireWoWEvent("PLAYER_ENTERING_WORLD")
`, 'Triggered PLAYER_ENTERING_WORLD event');

runLua(`
    -- 3. UPDATE_BATTLEFIELD_STATUS (Queue timer check)
    FireWoWEvent("UPDATE_BATTLEFIELD_STATUS")
`, 'Triggered UPDATE_BATTLEFIELD_STATUS event');

runLua(`
    -- 4. PVP_MATCH_ACTIVE (Match starts)
    FireWoWEvent("PVP_MATCH_ACTIVE")
`, 'Triggered PVP_MATCH_ACTIVE event');

runLua(`
    -- 5. ARENA_OPPONENT_UPDATE (Spec detection)
    FireWoWEvent("ARENA_OPPONENT_UPDATE")
`, 'Triggered ARENA_OPPONENT_UPDATE event');

runLua(`
    -- 6. PVP_MATCH_COMPLETE (Match finishes, scoreboard processing)
    FireWoWEvent("PVP_MATCH_COMPLETE")
    FireWoWEvent("UPDATE_BATTLEFIELD_SCORE")
`, 'Triggered PVP_MATCH_COMPLETE & UPDATE_BATTLEFIELD_SCORE');

runLua(`
    -- 7. Test Slash Commands
    if SlashCmdList["ALTERARENA"] then
        SlashCmdList["ALTERARENA"]("")
        SlashCmdList["ALTERARENA"]("test")
        SlashCmdList["ALTERARENA"]("ratings")
        SlashCmdList["ALTERARENA"]("timer")
        SlashCmdList["ALTERARENA"]("debug")
        SlashCmdList["ALTERARENA"]("settings")
    end
`, 'Executed Slash Commands (/aa, /aa test, /aa ratings, /aa timer, /aa debug, /aa settings)');

runLua(`
    -- 8. Test Cogwheel Settings Button & Debug Toggle
    if ns.OpenSettings then
        ns.OpenSettings()
    end
    local mf = _G["AlterArenaMainFrame"]
    if mf and mf.settingsBtn and mf.settingsBtn:GetScript("OnClick") then
        mf.settingsBtn:GetScript("OnClick")(mf.settingsBtn)
    end
    if mf and mf.settingsPanel and mf.settingsPanel.toggleDebugBtn and mf.settingsPanel.toggleDebugBtn:GetScript("OnClick") then
        mf.settingsPanel.toggleDebugBtn:GetScript("OnClick")(mf.settingsPanel.toggleDebugBtn)
    end
`, 'Tested Cogwheel Settings button and Settings Debug Mode toggle');

console.log('\n====================================================');
if (failedTests === 0) {
    console.log(`\x1b[32mSUCCESS: All ${passedTests}/${totalTests} tests passed with zero Lua errors!\x1b[0m`);
    console.log('====================================================\n');
    process.exit(0);
} else {
    console.error(`\x1b[31mFAILURE: ${failedTests}/${totalTests} tests failed!\x1b[0m`);
    console.log('====================================================\n');
    process.exit(1);
}
