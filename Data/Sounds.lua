-- Sound library: stable string ids → SoundKit name and/or numeric id.
-- Prefer resolving via global SOUNDKIT at play time (survives renumbering).
-- Numeric ids are fallbacks only.
local ADDON_NAME, ns = ...

ns.SOUNDS = {
    { id = "none",          category = "PvP", label = "None" },

    -- PvP / queue (names match FrameXML SOUNDKIT keys when present)
    { id = "pvpqueue",      category = "PvP", label = "PvP Queue Ready",
      soundKitName = "PVP_THROUGH_QUEUE",           soundKit = 8459 },
    { id = "pvpenter",      category = "PvP", label = "PvP Enter Queue",
      soundKitName = "PVP_ENTER_QUEUE",             soundKit = 8458 },
    { id = "raidwarning",   category = "PvP", label = "Raid Warning",
      soundKitName = "RAID_WARNING",                soundKit = 8959 },
    { id = "readycheck",    category = "PvP", label = "Ready Check",
      soundKitName = "READY_CHECK",                 soundKit = 8960 },
    { id = "lfgrolecheck",  category = "PvP", label = "LFG Role Check",
      soundKitName = "UI_LFG_ROLE_CHECK",           soundKit = 17317 },
    { id = "bgcountdown",   category = "PvP", label = "BG Countdown",
      soundKitName = "UI_BATTLEGROUND_COUNTDOWN_FINISHED", soundKit = 25478 },
    { id = "alarm1",        category = "PvP", label = "Alarm Clock 1",
      soundKitName = "ALARM_CLOCK_WARNING_1",       soundKit = 18871 },
    { id = "alarm2",        category = "PvP", label = "Alarm Clock 2",
      soundKitName = "ALARM_CLOCK_WARNING_2",       soundKit = 12867 },
    { id = "alarm3",        category = "PvP", label = "Alarm Clock 3",
      soundKitName = "ALARM_CLOCK_WARNING_3",       soundKit = 12889 },
    { id = "bossemote",     category = "PvP", label = "Boss Emote",
      soundKitName = "RAID_BOSS_EMOTE_WARNING",     soundKit = 12197 },
    { id = "raidwhisper",   category = "PvP", label = "Raid Whisper",
      soundKitName = "UI_RAID_BOSS_WHISPER_WARNING", soundKit = 37666 },
    { id = "ig_pvp_update", category = "PvP", label = "PvP Update",
      soundKitName = "IG_PVP_UPDATE",               soundKit = 4574 },

    -- UI feedback
    { id = "achievement",   category = "UI",  label = "Achievement",
      soundKitName = "UI_ACHIEVEMENT_MENU_OPEN",    soundKit = 13832 },
    { id = "bnettoast",     category = "UI",  label = "Battle.net Toast",
      soundKitName = "UI_BNET_TOAST",               soundKit = 18019 },
    { id = "questcomplete", category = "UI",  label = "Quest Complete",
      soundKitName = "UI_AUTO_QUEST_COMPLETE",      soundKit = 23404 },
    { id = "map_ping",      category = "UI",  label = "Map Ping",
      soundKitName = "MAP_PING",                    soundKit = 3175 },
    { id = "tell_message",  category = "UI",  label = "Whisper",
      soundKitName = "TELL_MESSAGE",                soundKit = 3081 },
    { id = "auction_open",  category = "UI",  label = "Auction Open",
      soundKitName = "AUCTION_WINDOW_OPEN",         soundKit = 5274 },
    { id = "gs_login",      category = "UI",  label = "Login",
      soundKitName = "GS_LOGIN",                    soundKit = 719 },
}

ns.SOUND_BY_ID = {}
for _, s in ipairs(ns.SOUNDS) do
    ns.SOUND_BY_ID[s.id] = s
end

--- Resolve a sound entry to a numeric SoundKit id (runtime, prefers SOUNDKIT table).
function ns.ResolveSoundKit(entry)
    if not entry or entry.id == "none" then return nil end

    local name = entry.soundKitName
    if type(name) == "string" then
        if SOUNDKIT and SOUNDKIT[name] then
            return SOUNDKIT[name], "SOUNDKIT." .. name
        end
        if Enum and Enum.SoundKitID and Enum.SoundKitID[name] then
            return Enum.SoundKitID[name], "Enum." .. name
        end
        -- Some clients expose lowercase/mixed keys — scan once
        if SOUNDKIT then
            local upper = name:upper()
            for k, v in pairs(SOUNDKIT) do
                if type(k) == "string" and k:upper() == upper and type(v) == "number" then
                    return v, "SOUNDKIT~" .. k
                end
            end
        end
    end

    if type(entry.soundKit) == "number" then
        return entry.soundKit, "numeric"
    end
    return nil, "unresolved"
end