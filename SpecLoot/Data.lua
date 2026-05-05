local AddonName, addonTable = ...;

-- Source 1: Keystone Mapping
addonTable.KeystoneMapping = {
    rules = {
        { keystones = { 2, 3 }, endOfRun = { track = "champion", rank = 2 }, greatVault = { track = "hero", rank = 1 } },
        { keystones = { 4 }, endOfRun = { track = "champion", rank = 3 }, greatVault = { track = "hero", rank = 2 } },
        { keystones = { 5 }, endOfRun = { track = "champion", rank = 4 }, greatVault = { track = "hero", rank = 2 } },
        { keystones = { 6 }, endOfRun = { track = "hero", rank = 1 }, greatVault = { track = "hero", rank = 3 } },
        { keystones = { 7 }, endOfRun = { track = "hero", rank = 1 }, greatVault = { track = "hero", rank = 4 } },
        { keystones = { 8, 9 }, endOfRun = { track = "hero", rank = 2 }, greatVault = { track = "hero", rank = 4 } },
        { keystones = { 10 }, endOfRun = { track = "hero", rank = 3 }, greatVault = { track = "myth", rank = 1 } }
    }
}

-- Source 1b: Upgrade Tracks (track/rank -> ilvl and bonusId)
addonTable.UpgradeTracks = {
    champion = {
        { ilvl = 246, bonusId = 12785 },
        { ilvl = 250, bonusId = 12786 },
        { ilvl = 253, bonusId = 12787 },
        { ilvl = 256, bonusId = 12788 },
        { ilvl = 259, bonusId = 12789 },
        { ilvl = 263, bonusId = 12790 },
    },
    hero = {
        { ilvl = 259, bonusId = 12793 },
        { ilvl = 263, bonusId = 12794 },
        { ilvl = 266, bonusId = 12795 },
        { ilvl = 269, bonusId = 12796 },
        { ilvl = 272, bonusId = 12797 },
        { ilvl = 276, bonusId = 12798 },
    },
    myth = {
        { ilvl = 272, bonusId = 12801 },
        { ilvl = 276, bonusId = 12802 },
        { ilvl = 279, bonusId = 12803 },
        { ilvl = 282, bonusId = 12804 },
        { ilvl = 285, bonusId = 12805 },
        { ilvl = 289, bonusId = 12806 },
    },
}

-- Source 1c: Class and Spec Reference (for browsing any class without being logged in as that class)
addonTable.ClassInfo = {
    [1]  = { name = "Warrior",       file = "WARRIOR",       classIcon = "Interface\\Icons\\ClassIcon_Warrior",       specs = { { id = 71,   name = "Arms",          icon = 132355 }, { id = 72,   name = "Fury",          icon = 132347 }, { id = 73,   name = "Protection",    icon = 132341 } } },
    [2]  = { name = "Paladin",       file = "PALADIN",       classIcon = "Interface\\Icons\\ClassIcon_Paladin",       specs = { { id = 65,   name = "Holy",          icon = 135920 }, { id = 66,   name = "Protection",    icon = 236264 }, { id = 70,   name = "Retribution",   icon = 135873 } } },
    [3]  = { name = "Hunter",        file = "HUNTER",        classIcon = "Interface\\Icons\\ClassIcon_Hunter",        specs = { { id = 253,  name = "Beast Mastery", icon = 461112 }, { id = 254,  name = "Marksmanship",  icon = 236179 }, { id = 255,  name = "Survival",      icon = 461113 } } },
    [4]  = { name = "Rogue",         file = "ROGUE",         classIcon = "Interface\\Icons\\ClassIcon_Rogue",         specs = { { id = 259,  name = "Assassination", icon = 236270 }, { id = 260,  name = "Outlaw",        icon = 236286 }, { id = 261,  name = "Subtlety",      icon = 132320 } } },
    [5]  = { name = "Priest",        file = "PRIEST",        classIcon = "Interface\\Icons\\ClassIcon_Priest",        specs = { { id = 256,  name = "Discipline",    icon = 135940 }, { id = 257,  name = "Holy",          icon = 237542 }, { id = 258,  name = "Shadow",        icon = 136207 } } },
    [6]  = { name = "Death Knight",  file = "DEATHKNIGHT",   classIcon = "Interface\\Icons\\ClassIcon_DeathKnight",   specs = { { id = 250,  name = "Blood",         icon = 135770 }, { id = 251,  name = "Frost",         icon = 135773 }, { id = 252,  name = "Unholy",        icon = 135775 } } },
    [7]  = { name = "Shaman",        file = "SHAMAN",        classIcon = "Interface\\Icons\\ClassIcon_Shaman",        specs = { { id = 262,  name = "Elemental",     icon = 136048 }, { id = 263,  name = "Enhancement",   icon = 136051 }, { id = 264,  name = "Restoration",   icon = 136052 } } },
    [8]  = { name = "Mage",          file = "MAGE",          classIcon = "Interface\\Icons\\ClassIcon_Mage",          specs = { { id = 62,   name = "Arcane",        icon = 135932 }, { id = 63,   name = "Fire",          icon = 135810 }, { id = 64,   name = "Frost",         icon = 135846 } } },
    [9]  = { name = "Warlock",       file = "WARLOCK",       classIcon = "Interface\\Icons\\ClassIcon_Warlock",       specs = { { id = 265,  name = "Affliction",    icon = 136145 }, { id = 266,  name = "Demonology",    icon = 136172 }, { id = 267,  name = "Destruction",   icon = 136186 } } },
    [10] = { name = "Monk",          file = "MONK",          classIcon = "Interface\\Icons\\ClassIcon_Monk",          specs = { { id = 268,  name = "Brewmaster",    icon = 608951 }, { id = 269,  name = "Windwalker",    icon = 608953 }, { id = 270,  name = "Mistweaver",    icon = 608952 } } },
    [11] = { name = "Druid",         file = "DRUID",         classIcon = "Interface\\Icons\\ClassIcon_Druid",         specs = { { id = 102,  name = "Balance",       icon = 136096 }, { id = 103,  name = "Feral",         icon = 132115 }, { id = 104,  name = "Guardian",      icon = 132276 }, { id = 105,  name = "Restoration",  icon = 136041 } } },
    [12] = { name = "Demon Hunter",  file = "DEMONHUNTER",   classIcon = "Interface\\Icons\\ClassIcon_DemonHunter",   specs = { { id = 577,  name = "Havoc",         icon = 1247264 }, { id = 581, name = "Vengeance",     icon = 1247265 }, { id = 1480, name = "Devourer",      icon = 7455385 } } },
    [13] = { name = "Evoker",        file = "EVOKER",        classIcon = "Interface\\Icons\\ClassIcon_Evoker",        specs = { { id = 1467, name = "Devastation",   icon = 4511811 }, { id = 1468, name = "Preservation", icon = 4511812 }, { id = 1473, name = "Augmentation",  icon = 5198700 } } },
}

-- Source 1d: Slot ID to slot name mapping
addonTable.SlotNames = {
    [0]  = "Head",
    [1]  = "Neck",
    [2]  = "Shoulder",
    [3]  = "Back",
    [4]  = "Chest",
    [5]  = "Wrist",
    [6]  = "Hands",
    [7]  = "Waist",
    [8]  = "Legs",
    [9]  = "Feet",
    [10] = "Weapon",
    [11] = "Off-hand",
    [12] = "Ring",
    [13] = "Trinket",
    [20] = "Token",
}
-- Source 3: Dungeon Database
-- journalInstanceId is the ID Scraper.lua passes to EJ_SelectInstance — also what
-- /data/wow/journal-instance/{id} expects on the REST API side.
-- instanceId is the legacy in-game map ID (kept for reference; not used by the scraper).
-- Loot tables live entirely in SpecLootDB now (populated by Scraper.lua).
addonTable.DungeonDatabase = {
    { name = "Skyreach",                abbrev = "SKY",  journalInstanceId = 476,  challengeModeId = 161, teleportSpellId = 159898,  bgTexture = 1041999, instanceId = 1209 },
    { name = "Seat of the Triumvirate", abbrev = "SEAT", journalInstanceId = 945,  challengeModeId = 239, teleportSpellId = 1254551, bgTexture = 1718213, instanceId = 1753 },
    { name = "Algeth'ar Academy",       abbrev = "AA",   journalInstanceId = 1201, challengeModeId = 402, teleportSpellId = 393273,  bgTexture = 4742929, instanceId = 2526 },
    { name = "Pit of Saron",            abbrev = "POS",  journalInstanceId = 278,  challengeModeId = 556, teleportSpellId = 1254555, bgTexture = 608210,  instanceId = 658 },
    { name = "Windrunner Spire",        abbrev = "WRS",  journalInstanceId = 1299, challengeModeId = 557, teleportSpellId = 1254400, bgTexture = 7464937, instanceId = 2805 },
    { name = "Magisters' Terrace",      abbrev = "MT",   journalInstanceId = 1300, challengeModeId = 558, teleportSpellId = 1254572, bgTexture = 7467174, instanceId = 2811 },
    { name = "Nexus-Point Xenas",       abbrev = "NPX",  journalInstanceId = 1316, challengeModeId = 559, teleportSpellId = 1254563, bgTexture = 7570501, instanceId = 2915 },
    { name = "Maisara Caverns",         abbrev = "MC",   journalInstanceId = 1315, challengeModeId = 560, teleportSpellId = 1254559, bgTexture = 7478529, instanceId = 2874 },
}

-- Source 3b: Raid Difficulty mapping
-- Order is the order shown in the UI dropdown. The dropdown shows just the name —
-- per-item ilvl comes from the per-difficulty journal link captured by Scraper.lua.
addonTable.RaidDifficulties = {
    { id = 17, key = "lfr",    name = "LFR"    },
    { id = 14, key = "normal", name = "Normal" },
    { id = 15, key = "heroic", name = "Heroic" },
    { id = 16, key = "mythic", name = "Mythic" },
}

-- Source 4: Raid Database (Midnight Season 1)
-- bgTexture left at 0 — populate when we have the textures; the UI can fall back to a default.
addonTable.RaidDatabase = {
    { name = "The Voidspire",       abbrev = "VS",  journalInstanceId = 1307, bgTexture = 0 },
    { name = "The Dreamrift",       abbrev = "DR",  journalInstanceId = 1314, bgTexture = 0 },
    { name = "March on Quel'Danas", abbrev = "MQD", journalInstanceId = 1308, bgTexture = 0 },
}