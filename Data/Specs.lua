-- Spec ID / icon static maps + ns.GetSpecIcon resolver.
local ADDON_NAME, ns = ...

-- Comprehensive Spec ID, Class, and Icon Mapping
local specCache = {}
local knownSpecIDs = {
    62, 63, 64, 65, 66, 70, 71, 72, 73, 102, 103, 104, 105,
    250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260,
    261, 262, 263, 264, 265, 266, 267, 268, 269, 270,
    577, 581, 1467, 1468, 1473
}

local fallbackSpecIcons = {
    -- WARLOCK
    ["WARLOCK_destruction"] = 136186, ["WARLOCK_affliction"] = 136145, ["WARLOCK_demonology"] = 136172,
    -- PRIEST
    ["PRIEST_discipline"] = 135976, ["PRIEST_holy"] = 237542, ["PRIEST_shadow"] = 136207,
    -- PALADIN
    ["PALADIN_holy"] = 135920, ["PALADIN_protection"] = 236264, ["PALADIN_retribution"] = 135873,
    -- MAGE
    ["MAGE_arcane"] = 135932, ["MAGE_fire"] = 135810, ["MAGE_frost"] = 135846,
    -- DEATHKNIGHT
    ["DEATHKNIGHT_blood"] = 135770, ["DEATHKNIGHT_frost"] = 135773, ["DEATHKNIGHT_unholy"] = 135775,
    -- SHAMAN
    ["SHAMAN_elemental"] = 136048, ["SHAMAN_enhancement"] = 136051, ["SHAMAN_restoration"] = 136052,
    -- DRUID
    ["DRUID_balance"] = 136096, ["DRUID_feral"] = 136036, ["DRUID_guardian"] = 132115, ["DRUID_restoration"] = 136041,
    -- WARRIOR
    ["WARRIOR_arms"] = 132355, ["WARRIOR_fury"] = 132347, ["WARRIOR_protection"] = 132341,
    -- ROGUE
    ["ROGUE_assassination"] = 132292, ["ROGUE_outlaw"] = 132298, ["ROGUE_subtlety"] = 132320,
    -- MONK
    ["MONK_brewmaster"] = 608951, ["MONK_windwalker"] = 608953, ["MONK_mistweaver"] = 608952,
    -- DEMONHUNTER
    ["DEMONHUNTER_havoc"] = 1247264, ["DEMONHUNTER_vengeance"] = 1247265,
    -- HUNTER
    ["HUNTER_beast mastery"] = 132164, ["HUNTER_marksmanship"] = 132222, ["HUNTER_survival"] = 132215,
    -- EVOKER
    ["EVOKER_devastation"] = 4576180, ["EVOKER_preservation"] = 4576181, ["EVOKER_augmentation"] = 5197072,
}

for key, icon in pairs(fallbackSpecIcons) do
    specCache[key] = icon
end

-- Default ambiguous fallbacks if class token is not provided
specCache["destruction"] = 136186
specCache["affliction"] = 136145
specCache["demonology"] = 136172
specCache["discipline"] = 135976
specCache["shadow"] = 136207
specCache["retribution"] = 135873
specCache["arcane"] = 135932
specCache["fire"] = 135810
specCache["blood"] = 135770
specCache["unholy"] = 135775
specCache["elemental"] = 136048
specCache["enhancement"] = 136051
specCache["balance"] = 136096
specCache["feral"] = 136036
specCache["guardian"] = 132115
specCache["arms"] = 132355
specCache["fury"] = 132347
specCache["assassination"] = 132292
specCache["outlaw"] = 132298
specCache["subtlety"] = 132320
specCache["brewmaster"] = 608951
specCache["windwalker"] = 608953
specCache["mistweaver"] = 608952
specCache["havoc"] = 1247264
specCache["vengeance"] = 1247265
specCache["beast mastery"] = 132164
specCache["marksmanship"] = 132222
specCache["survival"] = 132215
specCache["devastation"] = 4576180
specCache["preservation"] = 4576181
specCache["augmentation"] = 5197072

if GetSpecializationInfoByID then
    for _, id in ipairs(knownSpecIDs) do
        local _, name, _, icon, _, classToken = GetSpecializationInfoByID(id)
        if name and icon then
            specCache[id] = icon
            if classToken then
                local cKey = classToken:upper() .. "_" .. name:lower()
                specCache[cKey] = icon
            end
        end
    end
end

-- Live detected specs for players during active match
local detectedPlayerSpecs = {}

-- Signature spells that conclusively identify a player's spec
local signatureSpells = {
    [116858] = { spec = "Destruction", icon = 136186, class = "WARLOCK" },
    [324536] = { spec = "Affliction", icon = 136145, class = "WARLOCK" },
    [105174] = { spec = "Demonology", icon = 136172, class = "WARLOCK" },
    [47540]  = { spec = "Discipline", icon = 135976, class = "PRIEST" },
    [88625]  = { spec = "Holy", icon = 237542, class = "PRIEST" },
    [2944]   = { spec = "Shadow", icon = 136207, class = "PRIEST" },
    [20473]  = { spec = "Holy", icon = 135920, class = "PALADIN" },
    [31935]  = { spec = "Protection", icon = 236264, class = "PALADIN" },
    [184575] = { spec = "Retribution", icon = 135873, class = "PALADIN" },
    [12042]  = { spec = "Arcane", icon = 135932, class = "MAGE" },
    [190319] = { spec = "Fire", icon = 135810, class = "MAGE" },
    [12472]  = { spec = "Frost", icon = 135846, class = "MAGE" },
    [51505]  = { spec = "Elemental", icon = 136048, class = "SHAMAN" },
    [17364]  = { spec = "Enhancement", icon = 136051, class = "SHAMAN" },
    [61295]  = { spec = "Restoration", icon = 136052, class = "SHAMAN" },
    [78674]  = { spec = "Balance", icon = 136096, class = "DRUID" },
    [1079]   = { spec = "Feral", icon = 136036, class = "DRUID" },
    [22842]  = { spec = "Guardian", icon = 132115, class = "DRUID" },
    [18562]  = { spec = "Restoration", icon = 136041, class = "DRUID" },
    [12294]  = { spec = "Arms", icon = 132355, class = "WARRIOR" },
    [23881]  = { spec = "Fury", icon = 132347, class = "WARRIOR" },
    [23922]  = { spec = "Protection", icon = 132341, class = "WARRIOR" },
    [1329]   = { spec = "Assassination", icon = 132292, class = "ROGUE" },
    [185763] = { spec = "Outlaw", icon = 132298, class = "ROGUE" },
    [185313] = { spec = "Subtlety", icon = 132320, class = "ROGUE" },
    [121253] = { spec = "Brewmaster", icon = 608951, class = "MONK" },
    [107428] = { spec = "Windwalker", icon = 608953, class = "MONK" },
    [124682] = { spec = "Mistweaver", icon = 608952, class = "MONK" },
    [49998]  = { spec = "Blood", icon = 135770, class = "DEATHKNIGHT" },
    [49020]  = { spec = "Frost", icon = 135773, class = "DEATHKNIGHT" },
    [275699] = { spec = "Unholy", icon = 135775, class = "DEATHKNIGHT" },
    [198013] = { spec = "Havoc", icon = 1247264, class = "DEMONHUNTER" },
    [204021] = { spec = "Vengeance", icon = 1247265, class = "DEMONHUNTER" },
    [34026]  = { spec = "Beast Mastery", icon = 132164, class = "HUNTER" },
    [19434]  = { spec = "Marksmanship", icon = 132222, class = "HUNTER" },
    [190925] = { spec = "Survival", icon = 132215, class = "HUNTER" },
    [357208] = { spec = "Devastation", icon = 4576180, class = "EVOKER" },
    [355936] = { spec = "Preservation", icon = 4576181, class = "EVOKER" },
    [403631] = { spec = "Augmentation", icon = 5197072, class = "EVOKER" },
}

function ns.GetSpecIcon(specNameOrID, classFilename)
    if not specNameOrID then return nil end
    if type(specNameOrID) == "number" then
        if specCache[specNameOrID] then return specCache[specNameOrID] end
        if GetSpecializationInfoByID then
            local _, _, _, ic = GetSpecializationInfoByID(specNameOrID)
            if ic then return ic end
        end
    end

    local cToken = classFilename and tostring(classFilename):upper()
    local sName = tostring(specNameOrID):lower()

    if cToken and cToken ~= "" then
        local compoundKey = cToken .. "_" .. sName
        if specCache[compoundKey] then
            return specCache[compoundKey]
        end
    end

    return specCache[sName]
end
