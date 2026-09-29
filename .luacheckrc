-- AlterArena — luacheck configuration
-- Run locally:  luacheck . --config .luacheckrc
-- CI:           .github/workflows/luacheck.yml
--
-- WoW client Lua is a 5.1 dialect. std=lua51 is the closest match.
-- We list addon globals + Blizzard APIs explicitly so real typos still fail.

std = "lua51"
self = false

max_line_length = 160
max_cyclomatic_complexity = false
unused_args = false
unused_secondaries = false
codes = true

-- ---------------------------------------------------------------------------
-- Globals this addon writes (SavedVariables, named frames, slash cmds)
-- ---------------------------------------------------------------------------
globals = {
    "AlterArenaDB",

    -- Named frames (CreateFrame name argument)
    "AlterArenaMainFrame",
    "AlterArenaDebugFrame",
    "AlterArenaDebugCopyPanel",
    "AlterArenaSettingsFrame",
    "AlterArenaQueueTimer",
    "AlterArenaMinimapButton",
    "AlterArenaCurrencyAlert",

    -- Slash commands
    "SLASH_ALTERARENA1",
    "SLASH_ALTERARENA2",
    "SlashCmdList",
}

-- ---------------------------------------------------------------------------
-- Read-only Blizzard / engine APIs used across the addon
-- ---------------------------------------------------------------------------
read_globals = {
    -- Frame / widget
    "CreateFrame",
    "UIParent",
    "Minimap",
    "GameTooltip",
    "UISpecialFrames",
    "BackdropTemplate",
    "UIPanelScrollFrameTemplate",
    "UIPanelButtonTemplate",
    "UIPanelCloseButton",
    "UICheckButtonTemplate",
    "InputBoxTemplate",

    -- Fonts
    "GameFontNormal",
    "GameFontNormalLarge",
    "GameFontNormalSmall",
    "GameFontHighlight",
    "GameFontHighlightSmall",
    "GameFontDisable",
    "GameFontDisableSmall",

    -- C_* namespaces
    "C_AddOns",
    "C_Timer",
    "C_PvP",
    "C_CurrencyInfo",
    "C_Seasons",
    "C_ChatInfo",

    -- Units / player
    "UnitName",
    "UnitClass",
    "UnitFactionGroup",
    "UnitExists",
    "UnitGUID",
    "UnitIsUnit",
    "GetRealmName",
    "Ambiguate",

    -- Specs / inspect
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetSpecializationInfoByID",
    "GetInspectSpecialization",
    "NotifyInspect",
    "CanInspect",
    "GetNumGroupMembers",
    "IsInRaid",

    -- Arena / PvP
    "GetPersonalRatedInfo",
    "GetNumArenaOpponents",
    "GetArenaOpponentSpec",
    "GetNumBattlefieldScores",
    "RequestBattlefieldScoreData",
    "GetMaxBattlefieldID",
    "GetBattlefieldStatus",
    "GetBattlefieldTimeWaited",
    "GetBattlefieldEstimatedWaitTime",
    "IsActiveBattlefieldArena",
    "GetCurrentArenaSeason",
    "CONQUEST_BRACKET_INDEXES",
    "CONQUEST_SIZE_STRINGS",
    "RAID_CLASS_COLORS",
    "SOUNDKIT",
    "Enum",

    -- Zone / time
    "GetRealZoneText",
    "GetTime",
    "time",
    "date",

    -- Sound
    "PlaySound",
    "PlaySoundFile",

    -- Addon load
    "LoadAddOn",
    "hooksecurefunc",

    -- Table / string helpers (WoW env)
    "wipe",
    "tinsert",
    "tremove",
    "CopyTable",
    "strsplit",
    "strjoin",
    "strtrim",
    "strlower",
    "strupper",

    -- Secret values (Midnight / 12.x)
    "issecretvalue",
    "canaccessvalue",
    "canaccesstable",

    -- Chat / UI misc
    "DEFAULT_CHAT_FRAME",
    "print",
    "ReloadUI",
    "InCombatLockdown",
    "IsShiftKeyDown",
    "GetCursorPosition",
    "CopyToClipboard",

    -- Class colors helper used by some clients
    "GetClassColor",
}

-- ---------------------------------------------------------------------------
-- Noise we intentionally allow
-- ---------------------------------------------------------------------------
ignore = {
    "211", -- unused variable (locals kept for readability / future use)
    "212", -- unused argument (WoW callbacks: self, event, ...)
    "213", -- unused loop variable
    "311", -- value assigned to variable is unused
    "512", -- loop can be executed at most once (rare false positive)
    "631", -- line too long (we set max_line_length but allow occasional overflow via 631 if needed)
}

-- Don't fail on long lines if someone sets a tighter editor rule; 160 is soft.
-- Comment out 631 above if you want hard line-length enforcement in CI.

exclude_files = {
    ".git",
    ".github",
    "Libs",
    ".vscode"
}