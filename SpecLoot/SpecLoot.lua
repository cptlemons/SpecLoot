local addonName, addonTable = ...

local dungeons = addonTable.DungeonDatabase
local raids = addonTable.RaidDatabase or {}
local raidDifficulties = addonTable.RaidDifficulties or {}
local viewMode = "dungeon" -- "dungeon" or "raid"
local currentDungeonIndex = 1
local currentBossEncID -- nil until first raid scrape completes
local selectedKeystoneLevel = 10
local selectedRaidDifficulty = raidDifficulties[3] and raidDifficulties[3].id or 15 -- default Heroic
local selectedClassID = select(3, UnitClass("player"))

-- Main Frame
local mainFrame = CreateFrame("Frame", "SpecLootMainFrame", UIParent, "BasicFrameTemplateWithInset")
mainFrame:SetSize(800, 630)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame.TitleText:SetText("SpecLoot")

local titleIcon = mainFrame:CreateTexture(nil, "ARTWORK")
titleIcon:SetSize(16, 16)
titleIcon:SetPoint("RIGHT", mainFrame.TitleText, "LEFT", -4, 0)
titleIcon:SetTexture("Interface\\AddOns\\SpecLoot\\icon.png")

mainFrame:Hide()

tinsert(UISpecialFrames, "SpecLootMainFrame")

function SpecLoot_OnAddonCompartmentClick(addonName, button)
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

function SpecLoot_OnAddonCompartmentEnter(addonName, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffa335eeSpecLoot|r")
    GameTooltip:AddLine("Click to toggle the SpecLoot window.", 1, 1, 1)
    GameTooltip:Show()
end

function SpecLoot_OnAddonCompartmentLeave(addonName, button)
    GameTooltip:Hide()
end

local function InitCharDB()
    SpecLootCharDB = SpecLootCharDB or {}
    SpecLootCharDB.receivedItems = SpecLootCharDB.receivedItems or {}
end

local function GetReceivedItemKey(vMode, raidDiff, specID, itemID)
    if vMode == "raid" then
        local diff = raidDiff or selectedRaidDifficulty or 15
        return "raid:" .. diff .. ":" .. (specID or 0) .. ":" .. itemID
    else
        return "dungeon:" .. (specID or 0) .. ":" .. itemID
    end
end

local function IsItemReceived(vMode, raidDiff, specID, itemID)
    if not SpecLootCharDB or not SpecLootCharDB.receivedItems then
        return false
    end
    local key = GetReceivedItemKey(vMode, raidDiff, specID, itemID)
    if SpecLootCharDB.receivedItems[key] then
        return true
    end
    -- Fallback for legacy key format (for dungeons)
    if vMode ~= "raid" and SpecLootCharDB.receivedItems[(specID or 0) .. ":" .. itemID] then
        return true
    end
    return false
end

local function SetItemReceived(vMode, raidDiff, specID, itemID, isReceived)
    InitCharDB()
    local key = GetReceivedItemKey(vMode, raidDiff, specID, itemID)
    SpecLootCharDB.receivedItems[key] = isReceived and true or nil
    if not isReceived and vMode ~= "raid" then
        SpecLootCharDB.receivedItems[(specID or 0) .. ":" .. itemID] = nil
    end
end

-- Forward declarations for test commands
local HandleBonusRollResult
local HandleTestKill
local HandleTestKey
local ListReceivedBonusRolls

SLASH_SPECLOOT1 = "/specloot"
SLASH_SPECLOOT2 = "/sl"
SlashCmdList["SPECLOOT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "rescan" or msg == "scrape" then
        addonTable.Scraper:Scrape(false)
        addonTable.Scraper:EnsureClassClassified(selectedClassID)
    elseif msg == "debug" then
        addonTable.Scraper:Scrape(true)
        addonTable.Scraper:EnsureClassClassified(selectedClassID)
    elseif msg == "list" or msg == "rolls" or msg == "listrolls" or msg == "history" then
        if ListReceivedBonusRolls then
            ListReceivedBonusRolls()
        end
    elseif msg == "clear" or msg == "reset" or msg == "clearrolls" or msg == "resetrolls" then
        InitCharDB()
        SpecLootCharDB.receivedItems = {}
        if mainFrame:IsShown() then
            UpdateLootDisplay()
        end
        print("|cffa335eeSpecLoot|r: Cleared all marked bonus roll items for this character.")
    elseif msg:match("^testkey") or msg:match("^simkey") then
        local args = {}
        for w in msg:gmatch("%S+") do table.insert(args, w) end
        local keyLvl = tonumber(args[2]) or 10
        if HandleTestKey then
            HandleTestKey(keyLvl)
        end
    elseif msg:match("^testkill") or msg:match("^simkill") then
        local args = {}
        for w in msg:gmatch("%S+") do table.insert(args, w) end
        local bossID = tonumber(args[2]) or 2849
        local diffID = tonumber(args[3]) or 15
        if HandleTestKill then
            HandleTestKill(bossID, diffID)
        end
    elseif msg:match("^testroll") or msg:match("^simroll") then
        local args = {}
        for w in msg:gmatch("%S+") do table.insert(args, w) end
        local testItemID = tonumber(args[2])
        local testSpecID = tonumber(args[3]) or 0
        if testItemID and HandleBonusRollResult then
            local link = select(2, C_Item.GetItemInfo(testItemID)) or ("|cffa335ee|Hitem:" .. testItemID .. ":0:0:0:0:0:0:0:0|h[" .. testItemID .. "]|h|r")
            HandleBonusRollResult("item", link, 1, testSpecID)
        else
            print("|cffa335eeSpecLoot|r usage: /sl testroll <itemID> [specID]")
        end
    elseif msg:match("^probe") then
        local args = {}
        for w in msg:gmatch("%S+") do table.insert(args, w) end
        local instID = tonumber(args[2])
        local encID  = tonumber(args[3])
        if instID and encID then
            addonTable.Scraper:Probe(instID, encID)
        else
            print("|cffa335eeSpecLoot|r usage: /sl probe <instanceID> <encounterID>")
            print("  e.g. /sl probe 278 608   (Pit of Saron, Forgemaster Garfrost)")
        end
    elseif msg == "status" then
        print("|cffa335eeSpecLoot|r " .. addonTable.Scraper:GetSummary())
    elseif msg == "help" or msg == "?" then
        print("|cffa335eeSpecLoot|r commands:")
        print("  /sl                  toggle the main window")
        print("  /sl list             list all marked bonus rolls for this character")
        print("  /sl clear            reset marked bonus rolls for this character")
        print("  /sl testroll <id>    simulate receiving a bonus roll item")
        print("  /sl testkill <boss>  simulate a raid boss kill (e.g. /sl testkill 2849)")
        print("  /sl testkey <lvl>    simulate an active keystone level (e.g. /sl testkey 10)")
        print("  /sl rescan           force a fresh scrape (quiet)")
        print("  /sl debug            re-scrape with per-encounter verbose output")
        print("  /sl probe <i> <e>    try every difficulty ID against one (instance, encounter)")
        print("  /sl status           print scrape cache summary")
    else
        if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
    end
end

-----------------------------------------
-- ITEM PRELOADING
-----------------------------------------

local itemsLoaded = false
local pendingRefresh = false

local function PreloadAllItems()
    -- Walk every itemID currently cached by the scraper (dungeons + raids).
    if not SpecLootDB then return end
    local seen = {}
    local function preload(byInstance)
        for _, instance in pairs(byInstance or {}) do
            for _, enc in pairs(instance.encounters or {}) do
                for _, itemID in ipairs(enc.items or {}) do
                    if not seen[itemID] then
                        seen[itemID] = true
                        C_Item.RequestLoadItemDataByID(itemID)
                    end
                end
            end
        end
    end
    preload(SpecLootDB.dungeons)
    preload(SpecLootDB.raids)
end

-- Throttled refresh: when items finish loading, refresh the display
local refreshTimer = nil
local function ScheduleRefresh()
    if not mainFrame:IsShown() then return end
    if refreshTimer then return end
    pendingRefresh = true
    refreshTimer = C_Timer.NewTimer(0.1, function()
        refreshTimer = nil
        if pendingRefresh and mainFrame:IsShown() then
            pendingRefresh = false
            UpdateLootDisplay()
        end
    end)
end

-----------------------------------------
-- HELPERS
-----------------------------------------

local function GetEndOfRunInfo(keystoneLevel)
    for _, rule in ipairs(addonTable.KeystoneMapping.rules) do
        for _, ks in ipairs(rule.keystones) do
            if ks == keystoneLevel then
                local track = rule.endOfRun.track
                local rank = rule.endOfRun.rank
                local trackData = addonTable.UpgradeTracks[track]
                if trackData and trackData[rank] then
                    return trackData[rank].ilvl, trackData[rank].bonusId, track, rank
                end
            end
        end
    end
    return 311, 12843, "hero", 3
end

local function GetRaidDifficultyInfo(difficultyID)
    for _, d in ipairs(raidDifficulties) do
        if d.id == difficultyID then return d end
    end
    return raidDifficulties[1]
end

local function GetRaidBonusId(difficultyID, bossEncID)
    local diffKey = "heroic"
    for _, d in ipairs(raidDifficulties) do
        if d.id == difficultyID then diffKey = d.key; break end
    end

    local bossIndex = 1
    if bossEncID and addonTable.RaidDatabase then
        for _, raid in ipairs(addonTable.RaidDatabase) do
            for idx, enc in ipairs(raid.encounters or {}) do
                if enc.id == bossEncID then
                    bossIndex = enc.index or idx
                    break
                end
            end
        end
    end

    local rank = math.min(4, math.max(1, math.ceil(bossIndex / 2)))
    local track = addonTable.RaidTracks and addonTable.RaidTracks[diffKey]
    if track and track[rank] then
        return track[rank].bonusId
    end
    return 12841
end

local function GetTrackLabel(track, rank)
    local trackData = addonTable.UpgradeTracks[track]
    local maxRank = trackData and #trackData or 6
    return track:sub(1, 1):upper() .. track:sub(2) .. " " .. rank .. "/" .. maxRank
end

local function GetBonusRollTrackInfo(vMode, keystoneLevel, raidDifficulty, bossEncID)
    if vMode == "dungeon" then
        local rule
        for _, r in ipairs(addonTable.KeystoneMapping and addonTable.KeystoneMapping.rules or {}) do
            for _, k in ipairs(r.keystones) do
                if k == keystoneLevel then rule = r; break end
            end
            if rule then break end
        end
        if not rule then
            rule = addonTable.KeystoneMapping and addonTable.KeystoneMapping.rules and addonTable.KeystoneMapping.rules[#addonTable.KeystoneMapping.rules]
        end
        local gv = rule and rule.greatVault or { track = "myth", rank = 1 }
        local trackName = gv.track
        local rank = gv.rank
        local trackData = addonTable.UpgradeTracks and addonTable.UpgradeTracks[trackName]
        local maxRank = trackData and #trackData or 6
        local ilvl = trackData and trackData[rank] and trackData[rank].ilvl or 318
        local bonusId = trackData and trackData[rank] and trackData[rank].bonusId or 12849

        local shortTrack = trackName:sub(1, 1):upper() .. trackName:sub(2)
        local trackLabel = rank .. "/" .. maxRank .. " " .. shortTrack
        return ilvl, bonusId, trackLabel
    else
        local bossIndex = 1
        if bossEncID and addonTable.RaidDatabase then
            for _, raid in ipairs(addonTable.RaidDatabase) do
                for idx, enc in ipairs(raid.encounters or {}) do
                    if enc.id == bossEncID then
                        bossIndex = enc.index or idx
                        break
                    end
                end
            end
        end
        local bossRank = math.min(4, math.max(1, math.ceil(bossIndex / 2)))

        local ilvl, bonusId, trackLabel
        if raidDifficulty == 17 then
            -- LFR -> Normal / Champ track
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["normal"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 292
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12833
            trackLabel = bossRank .. "/6 Champ"
        elseif raidDifficulty == 14 then
            -- Normal -> Heroic / Hero track
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["heroic"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 305
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12841
            trackLabel = bossRank .. "/6 Hero"
        elseif raidDifficulty == 15 then
            -- Heroic -> Mythic / Myth track (1/6 Myth .. 4/6 Myth)
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["mythic"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 318
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12849
            trackLabel = bossRank .. "/6 Myth"
        else
            -- Mythic (16) -> 6/6 Myth or 9/6 Myth
            if bossRank >= 3 then
                ilvl = 334
                bonusId = 12854
                trackLabel = "9/6 Myth"
            else
                ilvl = 334
                bonusId = 12854
                trackLabel = "6/6 Myth"
            end
        end

        return ilvl, bonusId, trackLabel
    end
end

local function GetClassSpecs(classID)
    local classInfo = addonTable.ClassInfo[classID]
    return classInfo and classInfo.specs or {}
end

local function GetItemData(itemID)
    return addonTable.Scraper:GetItemData(itemID)
end

local function IsItemAllowed(itemID)
    if itemID == 270909 then
        return true -- Omni token Slumbering Coil Curio
    end
    if itemID == 258045 or itemID == 279118 or itemID == 275658 or itemID == 256625 then
        return false -- Filter out Dawnblade's Glaives (cosmetic weapon), Lost Explorers' Mailbox, Primeval Skyfriend, Hexwoven Strand
    end
    local itemData = GetItemData(itemID)
    if not itemData then return false end
    if itemData.slotId == 14 or itemData.slotId == 99 or itemData.isCosmetic or itemData.isBonusLoot or itemData.filterType == 5 then
        return false -- Filter out mounts, recipes, toys, fluff curios, cosmetics, bonus loot
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
        if equipLoc == "INVTYPE_COSMETIC" or equipLoc == "INVTYPE_NON_EQUIP" then
            return false
        end
        if classID == 4 and subclassID == 5 then -- Armor class 4, Cosmetic subclass 5
            return false
        end
    end
    return true
end

local function DoesItemDropForSpec(itemID, classID, specID)
    local itemData = GetItemData(itemID)
    if not itemData or not itemData.classes then return false end
    local specsForClass = itemData.classes[classID]
    if not specsForClass then return false end
    for _, sid in ipairs(specsForClass) do
        if sid == specID then return true end
    end
    return false
end

local function GetSlotId(itemID)
    local itemData = GetItemData(itemID)
    return itemData and itemData.slotId or 99
end

local function GetSlotName(itemID)
    local slotId = GetSlotId(itemID)
    return addonTable.SlotNames[slotId] or ""
end

local function SortBySlotId(a, b)
    return GetSlotId(a) < GetSlotId(b)
end

-- Build a proper item link for tooltip display at correct ilvl. With a bonus id
-- we get a scaled tooltip; without one (raids haven't been mapped yet), fall back
-- to the bare item which shows base ilvl.
local function BuildItemLink(itemID, bonusId)
    if bonusId and bonusId > 0 then
        -- item:id:enchant:gem1:gem2:gem3:gem4:suffix:unique:level:specId:modifiers:context:numBonus:bonus1:bonus2
        return "item:" .. itemID .. "::::::::80::::2:1674:" .. bonusId
    end
    return "item:" .. itemID
end

local function BuildItemHyperlink(itemID, bonusId)
    local rawString = BuildItemLink(itemID, bonusId)
    local itemName = C_Item.GetItemNameByID(itemID)
    if not itemName or itemName == "" then
        itemName = select(1, C_Item.GetItemInfo(itemID))
    end
    if not itemName or itemName == "" then
        itemName = select(1, C_Item.GetItemInfoInstant(itemID))
    end
    if not itemName or itemName == "" then
        itemName = "Item " .. itemID
    end

    local _, _, itemQuality = C_Item.GetItemInfoInstant(itemID)
    local hexColor = (itemQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[itemQuality] and ITEM_QUALITY_COLORS[itemQuality].hex) or "|cffa335ee"
    return hexColor .. "|H" .. rawString .. "|h[" .. itemName .. "]|h|r"
end

ListReceivedBonusRolls = function()
    InitCharDB()
    if not SpecLootCharDB or not SpecLootCharDB.receivedItems or not next(SpecLootCharDB.receivedItems) then
        print("|cffa335eeSpecLoot|r: No bonus roll items marked as received for this character.")
        return
    end

    local entries = {}
    for key, isRec in pairs(SpecLootCharDB.receivedItems) do
        if isRec then
            local raidDiff, specID, itemID
            local vMode = "dungeon"

            if key:match("^raid:") then
                vMode = "raid"
                local d, s, i = key:match("^raid:(%d+):(%d+):(%d+)")
                raidDiff = tonumber(d)
                specID = tonumber(s)
                itemID = tonumber(i)
            elseif key:match("^dungeon:") then
                local s, i = key:match("^dungeon:(%d+):(%d+)")
                specID = tonumber(s)
                itemID = tonumber(i)
            else
                local s, i = key:match("^(%d+):(%d+)")
                specID = tonumber(s)
                itemID = tonumber(i)
            end

            if itemID then
                local sourceName = "Unknown Source"
                local difficultyText = "Mythic+ (10+)"
                local scaledBonusId = nil

                if vMode == "raid" then
                    local bossName = "Raid Boss"
                    local raidName = "Raid"
                    local encID = nil
                    if raids then
                        for _, r in ipairs(raids) do
                            for _, enc in ipairs(r.encounters or {}) do
                                for _, id in ipairs(enc.items or {}) do
                                    if id == itemID then
                                        bossName = enc.name
                                        raidName = r.name
                                        encID = enc.id
                                        break
                                    end
                                end
                                if encID then break end
                            end
                            if encID then break end
                        end
                    end
                    sourceName = string.format("%s in %s", bossName, raidName)
                    local diffInfo = GetRaidDifficultyInfo(raidDiff or 15)
                    difficultyText = diffInfo and diffInfo.name or "Heroic"
                    local _, bId = GetBonusRollTrackInfo("raid", 10, raidDiff or 15, encID)
                    scaledBonusId = bId
                else
                    local dungeonName = nil
                    if dungeons then
                        for _, d in ipairs(dungeons) do
                            for _, id in ipairs(d.lootTable or {}) do
                                if id == itemID then
                                    dungeonName = d.name
                                    break
                                end
                            end
                            if dungeonName then break end
                        end
                    end
                    sourceName = dungeonName or "Mythic+ Dungeon"
                    difficultyText = "Mythic+ (10+)"
                    local _, bId = GetBonusRollTrackInfo("dungeon", 10)
                    scaledBonusId = bId
                end

                local specName = "All Specs"
                if specID and specID > 0 then
                    local _, sName = GetSpecializationInfoByID(specID)
                    specName = sName or tostring(specID)
                end

                local itemLink = BuildItemHyperlink(itemID, scaledBonusId)
                entries[#entries + 1] = {
                    itemLink = itemLink,
                    sourceName = sourceName,
                    difficultyText = difficultyText,
                    specName = specName,
                }
            end
        end
    end

    if #entries == 0 then
        print("|cffa335eeSpecLoot|r: No bonus roll items marked as received for this character.")
        return
    end

    print(string.format("|cffa335eeSpecLoot|r: Marked Bonus Roll Items for %s (%d):", UnitName("player") or "Character", #entries))
    for idx, e in ipairs(entries) do
        print(string.format("  |cffaaaaaa%d.|r %s from |cffffffff%s|r on |cff55ff55%s|r (Loot Spec: |cffffd100%s|r)",
            idx, e.itemLink, e.sourceName, e.difficultyText, e.specName))
    end
end

-----------------------------------------
-- BONUS ROLL AUTO TRACKING
-----------------------------------------

local cachedKeyLevel = nil
local cachedRaidMapID = nil
local cachedRaidDifficultyID = nil
local cachedRaidName = nil
local lastKilledBossEncID = nil
local lastKilledBossName = nil

local function CacheActiveKeystoneLevel()
    if not C_ChallengeMode then return end
    local level = C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()
    if level and level > 0 then
        cachedKeyLevel = level
        InitCharDB()
        SpecLootCharDB.cachedKeyLevel = level
    end
end

local function GetEffectiveLootSpecID(eventSpecID)
    if eventSpecID and eventSpecID > 0 then
        return eventSpecID
    end
    local lootSpecID = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpecID and lootSpecID > 0 then
        return lootSpecID
    end
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex and specIndex > 0 then
        local specID = GetSpecializationInfo and GetSpecializationInfo(specIndex)
        if specID and specID > 0 then
            return specID
        end
    end
    return 0
end

HandleTestKey = function(keyLevel)
    lastKilledBossEncID = nil
    lastKilledBossName = nil
    cachedRaidMapID = nil
    cachedRaidDifficultyID = nil
    cachedRaidName = nil
    cachedKeyLevel = keyLevel
    InitCharDB()
    SpecLootCharDB.cachedKeyLevel = keyLevel
    print(string.format("|cffa335eeSpecLoot|r: Simulated active keystone level +%d.", keyLevel))
end

HandleTestKill = function(bossEncID, diffID)
    cachedKeyLevel = nil
    if SpecLootCharDB then
        SpecLootCharDB.cachedKeyLevel = nil
    end
    lastKilledBossEncID = bossEncID
    cachedRaidDifficultyID = diffID or 15
    local bossName = "Unknown Boss"
    local raidName = "Raid"
    if raids then
        for _, r in ipairs(raids) do
            for _, enc in ipairs(r.encounters or {}) do
                if enc.id == bossEncID then
                    bossName = enc.name
                    raidName = r.name
                    break
                end
            end
        end
    end
    lastKilledBossName = bossName
    cachedRaidName = raidName
    local diffInfo = GetRaidDifficultyInfo(cachedRaidDifficultyID)
    local diffName = diffInfo and diffInfo.name or tostring(cachedRaidDifficultyID)
    print(string.format("|cffa335eeSpecLoot|r: Simulated boss kill: %s in %s (%s).", bossName, raidName, diffName))
end

HandleBonusRollResult = function(typeIdentifier, itemLink, quantity, specID)
    if typeIdentifier and typeIdentifier ~= "item" then
        return
    end
    if not itemLink or type(itemLink) ~= "string" then
        return
    end

    local itemIDStr = itemLink:match("|Hitem:(%d+):")
    local itemID = itemIDStr and tonumber(itemIDStr) or tonumber(itemLink)
    if not itemID then
        return
    end

    local effectiveSpecID = GetEffectiveLootSpecID(specID)
    local specName
    if effectiveSpecID and effectiveSpecID > 0 then
        specName = select(2, GetSpecializationInfoByID(effectiveSpecID))
    end
    if not specName or specName == "" then
        specName = "your specialization"
    end

    local name, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()

    local currentKeyLevel = (C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()) or cachedKeyLevel
    if (not currentKeyLevel or currentKeyLevel == 0) and SpecLootCharDB then
        currentKeyLevel = SpecLootCharDB.cachedKeyLevel
    end

    -- Check if item belongs to a raid encounter
    local raidMatch = nil
    if raids then
        for _, r in ipairs(raids) do
            for _, enc in ipairs(r.encounters or {}) do
                if lastKilledBossEncID and enc.id == lastKilledBossEncID then
                    raidMatch = { raid = r, enc = enc }
                    break
                end
                for _, id in ipairs(enc.items or {}) do
                    if id == itemID then
                        raidMatch = { raid = r, enc = enc }
                        break
                    end
                end
                if raidMatch then break end
            end
            if raidMatch then break end
        end
    end

    -- Check if item belongs to a dungeon
    local dungeonMatch = nil
    if dungeons then
        for _, d in ipairs(dungeons) do
            if d.instanceId == instanceID or d.name == name then
                dungeonMatch = d
                break
            end
            for _, id in ipairs(d.lootTable or {}) do
                if id == itemID then
                    dungeonMatch = d
                    break
                end
            end
            if dungeonMatch then break end
        end
    end

    local sourceName = nil
    local difficultyText = nil
    local scaledBonusId = nil
    local shouldTrack = false

    local isInsideRaid = (instanceType == "raid")
    local isInsideParty = (instanceType == "party")

    if isInsideRaid or (raidMatch and not isInsideParty) then
        local bossName = lastKilledBossName or (raidMatch and raidMatch.enc and raidMatch.enc.name)
        local raidName = cachedRaidName or (raidMatch and raidMatch.raid and raidMatch.raid.name) or (name ~= "" and name) or "Raid"
        local encID = lastKilledBossEncID or (raidMatch and raidMatch.enc and raidMatch.enc.id)

        if bossName and bossName ~= "" then
            sourceName = string.format("%s in %s", bossName, raidName)
        else
            sourceName = raidName
        end

        local diffID = (difficultyID and difficultyID > 0 and isInsideRaid) and difficultyID or cachedRaidDifficultyID or selectedRaidDifficulty or 15
        local diffInfo = GetRaidDifficultyInfo(diffID)
        difficultyText = diffInfo and diffInfo.name or difficultyName or "Heroic"

        local _, bId = GetBonusRollTrackInfo("raid", 10, diffID, encID)
        scaledBonusId = bId
        shouldTrack = true

    elseif isInsideParty or dungeonMatch then
        -- M+ Threshold rule: do not auto track if keystone is < 10
        if currentKeyLevel and currentKeyLevel < 10 then
            return -- Ignore M+ bonus rolls below +10
        end

        local dungeonName = (dungeonMatch and dungeonMatch.name) or (name ~= "" and name) or "Mythic+ Dungeon"
        sourceName = dungeonName
        difficultyText = (currentKeyLevel and currentKeyLevel >= 10) and string.format("Mythic+ (+%d)", currentKeyLevel) or "Mythic+ (10+)"

        local _, bId = GetBonusRollTrackInfo("dungeon", currentKeyLevel or 10)
        scaledBonusId = bId
        shouldTrack = true
    end

    if shouldTrack and sourceName and difficultyText then
        local function executeTrack()
            local vMode = (isInsideRaid or (raidMatch and not isInsideParty)) and "raid" or "dungeon"
            local diffForDB = (vMode == "raid") and ((difficultyID and difficultyID > 0 and isInsideRaid) and difficultyID or cachedRaidDifficultyID or selectedRaidDifficulty or 15) or nil

            local alreadyReceived = IsItemReceived(vMode, diffForDB, effectiveSpecID, itemID)
            local displayLink = BuildItemHyperlink(itemID, scaledBonusId)

            if alreadyReceived then
                print(string.format("|cffa335eeSpecLoot|r: Detected %s from %s on %s (Loot Spec: %s), but it was already marked as received.",
                    displayLink, sourceName, difficultyText, specName))
            else
                SetItemReceived(vMode, diffForDB, effectiveSpecID, itemID, true)

                if mainFrame:IsShown() then
                    UpdateLootDisplay()
                end

                print(string.format("|cffa335eeSpecLoot|r: Detected %s from %s on %s (Loot Spec: %s). Marked as received.",
                    displayLink, sourceName, difficultyText, specName))
            end
        end

        if Item and Item.CreateFromItemID then
            local itemObj = Item:CreateFromItemID(itemID)
            itemObj:ContinueOnItemLoad(executeTrack)
        else
            executeTrack()
        end
    end
end

-- Global Event Listener
mainFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
mainFrame:RegisterEvent("BONUS_ROLL_RESULT")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("CHALLENGE_MODE_START")
mainFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
mainFrame:RegisterEvent("ENCOUNTER_END")
mainFrame:RegisterEvent("BOSS_KILL")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = ...
        addonTable.Scraper:OnItemInfoReceived(itemID)
        ScheduleRefresh()
    elseif event == "BONUS_ROLL_RESULT" then
        local typeIdentifier, itemLink, quantity, specID = ...
        HandleBonusRollResult(typeIdentifier, itemLink, quantity, specID)
    elseif event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" then
        CacheActiveKeystoneLevel()
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInInstance and IsInInstance() then
            local name, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
            if instanceType == "party" then
                CacheActiveKeystoneLevel()
                cachedRaidMapID = nil
                cachedRaidDifficultyID = nil
                cachedRaidName = nil
            elseif instanceType == "raid" then
                cachedRaidMapID = instanceID
                cachedRaidDifficultyID = difficultyID
                cachedRaidName = name
            end
        end
    elseif event == "ENCOUNTER_END" then
        local encounterID, encounterName, difficultyID, groupSize, success = ...
        if success == 1 then
            lastKilledBossEncID = encounterID
            lastKilledBossName = encounterName
            if difficultyID and difficultyID > 0 then
                cachedRaidDifficultyID = difficultyID
            end
        end
    elseif event == "BOSS_KILL" then
        local encounterID, name = ...
        lastKilledBossEncID = encounterID
        lastKilledBossName = name
    end
end)

-----------------------------------------
-- CROSS-SPEC HIGHLIGHT REGISTRY
-----------------------------------------

local itemFrameRegistry = {}

local function RegisterItemFrame(itemID, frame)
    if not itemFrameRegistry[itemID] then
        itemFrameRegistry[itemID] = {}
    end
    itemFrameRegistry[itemID][#itemFrameRegistry[itemID] + 1] = frame
end

local function HighlightDuplicates(itemID)
    local frames = itemFrameRegistry[itemID]
    if not frames or #frames < 2 then return end
    for _, f in ipairs(frames) do
        f.dupHighlight:Show()
    end
end

local function UnhighlightDuplicates(itemID)
    local frames = itemFrameRegistry[itemID]
    if not frames then return end
    for _, f in ipairs(frames) do
        f.dupHighlight:Hide()
    end
end

local function ClearRegistry()
    itemFrameRegistry = {}
end

-----------------------------------------
-- TOP ROW: DROPDOWNS
-----------------------------------------

local function AdjustDropdownText(dropdown)
    local text = _G[dropdown:GetName() .. "Text"] or dropdown.Text
    if text then
        local point, relTo, relPoint, x, y = text:GetPoint(1)
        if point then
            text:ClearAllPoints()
            text:SetPoint(point, relTo, relPoint, x, (y or 2) - 2)
        end
    end
end

local keystoneDropdown = CreateFrame("Frame", "SpecLootKeystoneDropdown", mainFrame, "UIDropDownMenuTemplate")
keystoneDropdown:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -12, -20)
UIDropDownMenu_SetWidth(keystoneDropdown, 75)
UIDropDownMenu_JustifyText(keystoneDropdown, "CENTER")
AdjustDropdownText(keystoneDropdown)

UIDropDownMenu_Initialize(keystoneDropdown, function(self, level, menuList)
    for ks = 2, 10 do
        local info = UIDropDownMenu_CreateInfo()
        local ilvl, _, track, rank = GetEndOfRunInfo(ks)
        info.text = "+" .. ks .. "  (" .. ilvl .. ")"
        info.arg1 = ks
        info.notCheckable = true
        info.func = function(_, arg1)
            selectedKeystoneLevel = arg1
            local newIlvl = GetEndOfRunInfo(arg1)
            UIDropDownMenu_SetText(keystoneDropdown, "+" .. arg1 .. " (" .. newIlvl .. ")")
            UpdateLootDisplay()
        end
        UIDropDownMenu_AddButton(info)
    end
end)

local defaultIlvl = GetEndOfRunInfo(10)
UIDropDownMenu_SetText(keystoneDropdown, "+10 (" .. defaultIlvl .. ")")

-- Difficulty dropdown — replaces keystone in raid mode, same screen position.
local difficultyDropdown = CreateFrame("Frame", "SpecLootDifficultyDropdown", mainFrame, "UIDropDownMenuTemplate")
difficultyDropdown:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -12, -20)
UIDropDownMenu_SetWidth(difficultyDropdown, 75)
UIDropDownMenu_JustifyText(difficultyDropdown, "CENTER")
AdjustDropdownText(difficultyDropdown)
difficultyDropdown:Hide()

UIDropDownMenu_Initialize(difficultyDropdown, function(self, level, menuList)
    for _, d in ipairs(raidDifficulties) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = d.name
        info.arg1 = d.id
        info.notCheckable = true
        info.func = function(_, arg1)
            selectedRaidDifficulty = arg1
            UIDropDownMenu_SetText(difficultyDropdown, GetRaidDifficultyInfo(arg1).name)
            UpdateLootDisplay()
        end
        UIDropDownMenu_AddButton(info)
    end
end)
UIDropDownMenu_SetText(difficultyDropdown, GetRaidDifficultyInfo(selectedRaidDifficulty).name)

-- Class dropdown (top-right)
local classDropdown = CreateFrame("Frame", "SpecLootClassDropdown", mainFrame, "UIDropDownMenuTemplate")
classDropdown:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 2, -20)
UIDropDownMenu_SetWidth(classDropdown, 120)
UIDropDownMenu_JustifyText(classDropdown, "CENTER")
AdjustDropdownText(classDropdown)

local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.25, 0.78, 0.92 },
    WARLOCK     = { 0.53, 0.53, 0.93 },
    MONK        = { 0.00, 1.00, 0.60 },
    DRUID       = { 1.00, 0.49, 0.04 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}

-- Helper function to generate an inline icon string for the class text
local function GetClassTextWithIcon(classInfo)
    if not classInfo then return "Unknown" end
    -- Embeds the Atlas class icon inline before the name
    return "|A:classicon-" .. string.lower(classInfo.file) .. ":16:16|a " .. classInfo.name
end

UIDropDownMenu_Initialize(classDropdown, function(self, level, menuList)
    for cid = 1, 13 do
        local classInfo = addonTable.ClassInfo[cid]
        if classInfo then
            local info = UIDropDownMenu_CreateInfo()
            local cc = CLASS_COLORS[classInfo.file] or { 1, 1, 1 }
            
            -- We set the text to include the icon inline, and remove info.icon
            info.text = GetClassTextWithIcon(classInfo)
            info.colorCode = string.format("|cff%02x%02x%02x", cc[1] * 255, cc[2] * 255, cc[3] * 255)
            info.arg1 = cid
            info.notCheckable = true
            info.func = function(_, arg1)
                selectedClassID = arg1
                -- Lazily classify other classes the first time they're picked.
                addonTable.Scraper:EnsureClassClassified(arg1)
                local ci = addonTable.ClassInfo[arg1]
                UIDropDownMenu_SetText(classDropdown, GetClassTextWithIcon(ci))
                UpdateLootDisplay()
            end
            UIDropDownMenu_AddButton(info)
        end
    end
end)

local playerClassInfo = addonTable.ClassInfo[selectedClassID]
UIDropDownMenu_SetText(classDropdown, GetClassTextWithIcon(playerClassInfo))

-----------------------------------------
-- DUNGEON ICONS (larger, with abbreviation text)
-----------------------------------------

local dungeonButtons = {}
local iconSize = 64
local iconGap = 4
local totalIconsWidth = (#dungeons * iconSize) + ((#dungeons - 1) * iconGap)
local dungeonRowY = -57

-- Anchor container for centering: first icon offset from TOP center
local firstIconX = -totalIconsWidth / 2

for i, dungeon in ipairs(dungeons) do
    local btn = CreateFrame("Button", nil, mainFrame, "SecureActionButtonTemplate")
    btn:SetSize(iconSize, iconSize)
    btn:SetPoint("TOP", mainFrame, "TOP", firstIconX + (iconSize / 2) + ((i - 1) * (iconSize + iconGap)), dungeonRowY)
    -- Register for BOTH up and down so the secure cast fires regardless of the
    -- player's "Cast on Key Down" setting (default in modern retail).
    btn:RegisterForClicks("AnyUp", "AnyDown")
    if dungeon.teleportSpellId then
        btn:SetAttribute("type2", "spell")
        btn:SetAttribute("spell2", dungeon.teleportSpellId)
    end

    -- Thick gold selection border (3px) placed securely behind the artwork
    btn.selected = btn:CreateTexture(nil, "BACKGROUND")
    btn.selected:SetPoint("TOPLEFT", -3, 3)
    btn.selected:SetPoint("BOTTOMRIGHT", 3, -3)
    btn.selected:SetColorTexture(1, 0.82, 0, 1)
    btn.selected:Hide()

    -- Dungeon icon filling the full button
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexture(dungeon.bgTexture)
    -- Crop a perfect 256x256 pixel square from the center of the artwork
    -- Left: 0.20, Right: 0.45 (Width = 0.25 of 1024 canvas = 256px)
    -- Top: 0.0, Bottom: 0.5 (Height = 0.5 of 512 canvas = 256px)
    btn.icon:SetTexCoord(0.20, 0.45, 0.0, 0.5)

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.3)

    -- Abbreviation text on topmost layer
    btn.abbrevTop = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.abbrevTop:SetPoint("BOTTOM", 0, 5)
    btn.abbrevTop:SetText(dungeon.abbrev or "")
    btn.abbrevTop:SetTextColor(1, 1, 1, 1)
    btn.abbrevTop:SetShadowOffset(1, -1)
    btn.abbrevTop:SetShadowColor(0, 0, 0, 1)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(dungeon.name)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Run our selection logic in PreClick, NOT OnClick. SecureActionButtonTemplate
    -- inherits an OnClick handler (SecureActionButton_OnClick) that reads the
    -- type/type2 attributes and dispatches the spell cast — overriding it with
    -- SetScript("OnClick", ...) silently kills the right-click cast. PreClick
    -- runs before the secure dispatch and leaves it intact.
    btn:SetScript("PreClick", function(self, button, isDown)
        -- We register for both up and down to support either "Cast on Key Down"
        -- setting; ignore the down half so selection only fires once per click.
        if isDown then return end
        if button == "LeftButton" then
            currentDungeonIndex = i
            UpdateLootDisplay()
        end
    end)
    dungeonButtons[i] = btn
end

dungeonButtons[1].selected:Show()

-----------------------------------------
-- BOSS TILES (raid view)
-----------------------------------------

-- Built lazily once the scraper has populated SpecLootDB.raids — the boss list
-- and creature display IDs only exist after scrape completes.
local bossButtons = {}
local bossButtonsBuilt = false

local function BuildBossButtons()
    if bossButtonsBuilt then return end
    if not SpecLootDB or not SpecLootDB.raids then return end

    -- Flatten across raids in RaidDatabase order, encounters in journal order.
    local allBosses = {}
    for _, raid in ipairs(raids) do
        local encounters = addonTable.Scraper:GetRaidEncounters(raid.journalInstanceId)
        for _, enc in ipairs(encounters) do
            allBosses[#allBosses + 1] = { raid = raid, enc = enc }
        end
    end
    if #allBosses == 0 then return end

    local totalWidth = (#allBosses * iconSize) + ((#allBosses - 1) * iconGap)
    local firstX = -totalWidth / 2

    for i, info in ipairs(allBosses) do
        local btn = CreateFrame("Button", nil, mainFrame)
        btn:SetSize(iconSize, iconSize)
        btn:SetPoint("TOP", mainFrame, "TOP",
            firstX + (iconSize / 2) + ((i - 1) * (iconSize + iconGap)), dungeonRowY)
        btn:Hide()

        btn.encID    = info.enc.id
        btn.raid     = info.raid
        btn.encName  = info.enc.name

        btn.selected = btn:CreateTexture(nil, "BACKGROUND")
        btn.selected:SetPoint("TOPLEFT", -3, 3)
        btn.selected:SetPoint("BOTTOMRIGHT", 3, -3)
        btn.selected:SetColorTexture(1, 0.82, 0, 1)
        btn.selected:Hide()

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        local displayID = info.enc.creatureDisplayID
        if type(displayID) == "number" and displayID > 0 then
            SetPortraitTextureFromCreatureDisplayID(btn.icon, displayID)
        else
            btn.icon:SetTexture(134400)
        end

        btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.highlight:SetAllPoints()
        btn.highlight:SetColorTexture(1, 1, 1, 0.3)

        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.label:SetPoint("BOTTOM", 0, 5)
        btn.label:SetText(info.raid.abbrev or "")
        btn.label:SetTextColor(1, 1, 1, 1)
        btn.label:SetShadowOffset(1, -1)
        btn.label:SetShadowColor(0, 0, 0, 1)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.encName)
            GameTooltip:AddLine(self.raid.name, 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:SetScript("OnClick", function(self)
            currentBossEncID = self.encID
            UpdateLootDisplay()
        end)

        bossButtons[i] = btn
    end

    if not currentBossEncID then
        currentBossEncID = allBosses[1].enc.id
    end
    bossButtonsBuilt = true
end

-----------------------------------------
-- VIEW MODE: M+ / Raid TABS
-----------------------------------------

local isBonusRollMode = false

local mythicTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
mythicTab:SetSize(80, 22)
mythicTab:SetText("Mythic+")
mythicTab:SetPoint("TOP", mainFrame, "TOP", -42, -26)

local raidTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
raidTab:SetSize(80, 22)
raidTab:SetText("Raids")
raidTab:SetPoint("TOP", mainFrame, "TOP", 42, -26)

local bonusRollCheckbox = CreateFrame("CheckButton", "SpecLootBonusRollCheckbox", mainFrame, "UICheckButtonTemplate")
bonusRollCheckbox:SetPoint("RIGHT", classDropdown, "LEFT", -75, 0)
bonusRollCheckbox:SetSize(24, 24)

bonusRollCheckbox.text = bonusRollCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bonusRollCheckbox.text:SetPoint("LEFT", bonusRollCheckbox, "RIGHT", 4, 0)
bonusRollCheckbox.text:SetText("Bonus Rolls")

local function UpdateTabHighlight()
    mythicTab:SetAlpha(viewMode == "dungeon" and 1.0 or 0.55)
    raidTab:SetAlpha(viewMode == "raid"    and 1.0 or 0.55)
end

bonusRollCheckbox:SetScript("OnClick", function(self)
    isBonusRollMode = self:GetChecked() and true or false
    UpdateLootDisplay()
end)

bonusRollCheckbox:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Bonus Rolls Mode")
    GameTooltip:AddLine("Show Great Vault / Bonus Roll tracks for each spec.", 1, 1, 1)
    GameTooltip:AddLine("Right-click items to mark as received / obtained.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
bonusRollCheckbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function SetViewMode(mode)
    viewMode = mode
    if mode == "dungeon" then
        keystoneDropdown:Show()
        difficultyDropdown:Hide()
        for _, btn in ipairs(dungeonButtons) do btn:Show() end
        for _, btn in ipairs(bossButtons)    do btn:Hide() end
    else
        BuildBossButtons() -- safe to call multiple times
        keystoneDropdown:Hide()
        difficultyDropdown:Show()
        for _, btn in ipairs(dungeonButtons) do btn:Hide() end
        for _, btn in ipairs(bossButtons)    do btn:Show() end
    end
    UpdateTabHighlight()
    UpdateLootDisplay()
end

mythicTab:SetScript("OnClick", function() SetViewMode("dungeon") end)
raidTab:SetScript("OnClick",   function() SetViewMode("raid")    end)
UpdateTabHighlight()

-- Called from Scraper.Scrape() after fresh data lands. Rebuilds the raid tile
-- row if the user is already on the Raids tab waiting for the scrape.
addonTable.OnScrapeComplete = function()
    if viewMode == "raid" then
        BuildBossButtons()
        for _, btn in ipairs(bossButtons) do btn:Show() end
    end
    if mainFrame:IsShown() then UpdateLootDisplay() end
end

-----------------------------------------
-- SHARED LOOT FRAME
-----------------------------------------

local sharedFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
sharedFrame:SetSize(780, 150)
sharedFrame:SetPoint("TOP", mainFrame, "TOP", 0, dungeonRowY - iconSize - 6)
sharedFrame.bg = sharedFrame:CreateTexture(nil, "BACKGROUND")
sharedFrame.bg:SetAllPoints()
sharedFrame.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)

local sharedTitle = sharedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
sharedTitle:SetPoint("TOP", 0, -5)
sharedTitle:SetText("Shared Loot")

-----------------------------------------
-- SPEC FRAMES (bottom section, up to 4)
-----------------------------------------

local specFrames = {}
local specDisplayFrames = {}
local MAX_SPECS = 4

local specBgColors = {
    { 0.20, 0.10, 0.10, 0.5 },
    { 0.10, 0.10, 0.20, 0.5 },
    { 0.10, 0.20, 0.10, 0.5 },
    { 0.18, 0.12, 0.18, 0.5 },
}

for i = 1, MAX_SPECS do
    local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    f:SetSize(256, 230)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    local c = specBgColors[i]
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4])

    -- Spec icon and title at BOTTOM, centered, 30x30
    f.specIcon = f:CreateTexture(nil, "OVERLAY")
    f.specIcon:SetSize(30, 30)
    f.specIcon:SetPoint("BOTTOM", f, "BOTTOM", -40, 8)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f.specIcon, "RIGHT", 6, 0)

    f:Hide()
    specFrames[i] = f
    specDisplayFrames[i] = {}
end

-----------------------------------------
-- DISPLAY FRAME MANAGEMENT
-----------------------------------------

local sharedDisplayFrames = {}

local function ClearAllDisplayFrames()
    for _, f in ipairs(sharedDisplayFrames) do
        f:Hide()
        if f.strikeLine then f.strikeLine:Hide() end
    end
    for si = 1, MAX_SPECS do
        for _, f in ipairs(specDisplayFrames[si]) do
            f:Hide()
            if f.strikeLine then f.strikeLine:Hide() end
        end
    end
    ClearRegistry()
end

local function UpdateItemReceivedVisuals(itemFrame, isReceived)
    itemFrame.isReceived = isReceived
    if isBonusRollMode and isReceived then
        itemFrame.icon:SetDesaturated(true)
        itemFrame.icon:SetAlpha(0.35)
        itemFrame.text:SetAlpha(0.40)
        if itemFrame.strikeLine then
            local textWidth = itemFrame.text:GetStringWidth() or 100
            itemFrame.strikeLine:SetWidth(math.min(textWidth + 4, 215))
            itemFrame.strikeLine:Show()
        end
    else
        itemFrame.icon:SetDesaturated(false)
        itemFrame.icon:SetAlpha(1.0)
        itemFrame.text:SetAlpha(1.0)
        if itemFrame.strikeLine then
            itemFrame.strikeLine:Hide()
        end
    end
end

local function CreateOrReuseItemFrame(pool, index, parent)
    local itemFrame = pool[index]
    if not itemFrame then
        itemFrame = CreateFrame("Button", nil, parent)
        itemFrame:SetSize(240, 20)
        itemFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        itemFrame.icon = itemFrame:CreateTexture(nil, "ARTWORK")
        itemFrame.icon:SetSize(18, 18)
        itemFrame.icon:SetPoint("LEFT")

        itemFrame.text = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemFrame.text:SetPoint("LEFT", itemFrame.icon, "RIGHT", 4, 0)
        itemFrame.text:SetWidth(215)
        itemFrame.text:SetWordWrap(false)
        itemFrame.text:SetJustifyH("LEFT")

        itemFrame.strikeLine = itemFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        itemFrame.strikeLine:SetHeight(1.5)
        itemFrame.strikeLine:SetPoint("LEFT", itemFrame.text, "LEFT", -1, 0)
        itemFrame.strikeLine:SetColorTexture(0.75, 0.75, 0.75, 0.85)
        itemFrame.strikeLine:Hide()

        itemFrame.dupHighlight = itemFrame:CreateTexture(nil, "BACKGROUND")
        itemFrame.dupHighlight:SetPoint("TOPLEFT", -2, 1)
        itemFrame.dupHighlight:SetPoint("BOTTOMRIGHT", 2, -1)
        itemFrame.dupHighlight:SetColorTexture(1, 1, 1, 0.15)
        itemFrame.dupHighlight:Hide()

        itemFrame:SetScript("OnClick", function(self, button)
            if button == "RightButton" and isBonusRollMode then
                local isReceived = not IsItemReceived(self.viewMode, self.raidDifficulty, self.specID, self.itemID)
                SetItemReceived(self.viewMode, self.raidDifficulty, self.specID, self.itemID, isReceived)

                local itemName = C_Item.GetItemInfo(self.itemID) or "Loading..."
                local slotName = GetSlotName(self.itemID)
                local labelStr = self.trackLabel and ("|cff55ff55" .. self.trackLabel .. "|r") or ""
                if isReceived then
                    self.text:SetText("|cff888888" .. itemName .. "|r |cff666666" .. slotName .. "|r " .. labelStr)
                else
                    self.text:SetText("|cffa335ee" .. itemName .. "|r |cff888888" .. slotName .. "|r " .. labelStr)
                end
                UpdateItemReceivedVisuals(self, isReceived)
            end
        end)

        itemFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = self.itemLink or BuildItemLink(self.itemID, self.bonusId)
            GameTooltip:SetHyperlink(link)
            if isBonusRollMode then
                local isRec = IsItemReceived(self.viewMode, self.raidDifficulty, self.specID, self.itemID)
                GameTooltip:AddLine(" ")
                if isRec then
                    GameTooltip:AddLine("|cff777777Status: OBTAINED / RECEIVED|r")
                    GameTooltip:AddLine("|cffaaaaaaRight-click to return to Bonus Roll rotation|r")
                else
                    GameTooltip:AddLine("|cff00ff00Status: IN ROTATION|r")
                    GameTooltip:AddLine("|cffffd100Right-click to mark as RECEIVED|r")
                end
            end
            GameTooltip:Show()
            HighlightDuplicates(self.itemID)
        end)
        itemFrame:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            UnhighlightDuplicates(self.itemID)
        end)

        pool[index] = itemFrame
    end

    if itemFrame:GetParent() ~= parent then
        itemFrame:SetParent(parent)
    end

    return itemFrame
end

local function AddItemToPool(pool, parent, index, itemID, bonusId, itemLink, singleColumn, itemsPerCol, trackLabel, specID)
    local itemFrame = CreateOrReuseItemFrame(pool, index, parent)

    itemFrame.itemID = itemID
    itemFrame.specID = specID
    itemFrame.bonusId = bonusId
    itemFrame.itemLink = itemLink
    itemFrame.trackLabel = trackLabel
    itemFrame.viewMode = viewMode
    itemFrame.raidDifficulty = selectedRaidDifficulty

    local itemName = C_Item.GetItemInfo(itemID)
    local itemData = GetItemData(itemID)
    local dbIcon = (itemData and itemData.icon) or C_Item.GetItemIconByID(itemID)
    local slotName = GetSlotName(itemID)

    local isReceived = IsItemReceived(viewMode, selectedRaidDifficulty, specID, itemID)

    if isBonusRollMode then
        local labelStr = trackLabel and ("|cff55ff55" .. trackLabel .. "|r") or ""
        if isReceived then
            itemFrame.text:SetText("|cff888888" .. (itemName or "Loading...") .. "|r |cff666666" .. slotName .. "|r " .. labelStr)
        else
            itemFrame.text:SetText("|cffa335ee" .. (itemName or "Loading...") .. "|r |cff888888" .. slotName .. "|r " .. labelStr)
        end
    else
        if itemName then
            itemFrame.text:SetText("|cffa335ee" .. itemName .. "|r |cff888888" .. slotName .. "|r")
        else
            itemFrame.text:SetText("|cffa335eeLoading...|r |cff888888" .. slotName .. "|r")
        end
    end
    itemFrame.icon:SetTexture(dbIcon or 134400)
    itemFrame.dupHighlight:Hide()

    UpdateItemReceivedVisuals(itemFrame, isReceived)

    if singleColumn then
        itemFrame:ClearAllPoints()
        itemFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -10 - ((index - 1) * 22))
    else
        local maxRows = itemsPerCol or 5
        local row = (index - 1) % maxRows
        local col = math.floor((index - 1) / maxRows)
        itemFrame:ClearAllPoints()
        itemFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10 + (col * 250), -30 - (row * 22))
    end

    itemFrame:Show()
    RegisterItemFrame(itemID, itemFrame)
end

-----------------------------------------
-- LAYOUT SPEC FRAMES
-----------------------------------------

local function LayoutSpecFrames(numSpecs)
    local totalWidth = 780
    local gap = 4
    local panelWidth
    if numSpecs == 4 then
        panelWidth = (totalWidth - (gap * 3)) / 4
    else
        panelWidth = (totalWidth - (gap * 2)) / 3
    end

    local startX = (mainFrame:GetWidth() - totalWidth) / 2
    if startX <= 0 then startX = 10 end

    for i = 1, MAX_SPECS do
        if i <= numSpecs then
            local f = specFrames[i]
            f:ClearAllPoints()
            local offsetX = (i - 1) * (panelWidth + gap)

            if isBonusRollMode then
                f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + offsetX, dungeonRowY - iconSize - 12)
                f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", startX + offsetX, 8)
                f:SetWidth(panelWidth)
            else
                f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + offsetX, (dungeonRowY - iconSize - 6) - sharedFrame:GetHeight() - 6)
                f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", startX + offsetX, 8)
                f:SetWidth(panelWidth)
            end
            f:Show()
        else
            specFrames[i]:Hide()
        end
    end
end

-----------------------------------------
-- MAIN UPDATE
-----------------------------------------

function UpdateLootDisplay()
    ClearAllDisplayFrames()

    -- Update tile highlights for whichever row is active.
    if viewMode == "dungeon" then
        for i, btn in ipairs(dungeonButtons) do
            if i == currentDungeonIndex then btn.selected:Show() else btn.selected:Hide() end
        end
    else
        for _, btn in ipairs(bossButtons) do
            if btn.encID == currentBossEncID then btn.selected:Show() else btn.selected:Hide() end
        end
    end

    local classID = selectedClassID
    local specs = GetClassSpecs(classID)
    local numSpecs = #specs

    if numSpecs == 0 then return end

    local lootTable, bonusId
    if viewMode == "dungeon" then
        local dungeonData = dungeons[currentDungeonIndex]
        _, bonusId = GetEndOfRunInfo(selectedKeystoneLevel)
        lootTable = dungeonData and dungeonData.lootTable or addonTable.Scraper:GetDungeonLootTable(dungeonData.journalInstanceId)
    else
        lootTable = {}
        if currentBossEncID then
            if SpecLootDB and SpecLootDB.raids then
                for _, raid in ipairs(raids) do
                    local instance = SpecLootDB.raids[raid.journalInstanceId]
                    if instance and instance.encounters and instance.encounters[currentBossEncID] then
                        lootTable = instance.encounters[currentBossEncID].items or {}
                        break
                    end
                end
            end
            if #lootTable == 0 then
                for _, raid in ipairs(raids) do
                    for _, enc in ipairs(raid.encounters or {}) do
                        if enc.id == currentBossEncID then
                            lootTable = enc.items or {}
                            break
                        end
                    end
                    if #lootTable > 0 then break end
                end
            end
        end
    end

    local sharedItems = {}
    local specItems = {}
    for i = 1, numSpecs do specItems[i] = {} end

    local bonusIdToUse = bonusId
    local trackLabelToUse = nil

    if isBonusRollMode then
        local _, gvBonusId, gvLabel = GetBonusRollTrackInfo(viewMode, selectedKeystoneLevel, selectedRaidDifficulty, currentBossEncID)
        bonusIdToUse = gvBonusId
        trackLabelToUse = gvLabel
    end

    local normalSharedCount = 0
    for _, itemID in ipairs(lootTable) do
        if IsItemAllowed(itemID) then
            local dropsFor = {}
            for si, spec in ipairs(specs) do
                if DoesItemDropForSpec(itemID, classID, spec.id) then
                    dropsFor[#dropsFor + 1] = si
                end
            end

            if #dropsFor == numSpecs then
                normalSharedCount = normalSharedCount + 1
                if not isBonusRollMode then
                    sharedItems[#sharedItems + 1] = itemID
                end
            end

            if isBonusRollMode then
                for _, si in ipairs(dropsFor) do
                    specItems[si][#specItems[si] + 1] = itemID
                end
            else
                if #dropsFor > 0 and #dropsFor < numSpecs then
                    for _, si in ipairs(dropsFor) do
                        specItems[si][#specItems[si] + 1] = itemID
                    end
                end
            end
        end
    end

    table.sort(sharedItems, SortBySlotId)
    for i = 1, numSpecs do
        table.sort(specItems[i], SortBySlotId)
    end

    local totalShared = #sharedItems
    local numCols = math.max(1, math.ceil(normalSharedCount / 5))
    local sharedItemsPerCol = normalSharedCount > 0 and math.ceil(normalSharedCount / numCols) or 1
    local dynamicHeight = math.max(150, 40 + (sharedItemsPerCol * 22))

    -- Keep consistent window size across modes with 5px compensation
    mainFrame:SetHeight(370 + dynamicHeight)

    if isBonusRollMode or totalShared == 0 then
        sharedFrame:Hide()
        sharedFrame:SetHeight(0)
    else
        sharedFrame:Show()
        sharedFrame:SetHeight(dynamicHeight)
    end

    LayoutSpecFrames(numSpecs)

    for i, spec in ipairs(specs) do
        specFrames[i].title:SetText(spec.name)
        specFrames[i].specIcon:SetTexture(spec.icon)
    end

    local function linkFor(itemID)
        if isBonusRollMode then
            return BuildItemLink(itemID, bonusIdToUse)
        end
        if viewMode ~= "raid" then return nil end
        local d = GetItemData(itemID)
        if d and d.links and d.links[selectedRaidDifficulty] then
            return d.links[selectedRaidDifficulty]
        end
        local raidBonusId = GetRaidBonusId(selectedRaidDifficulty, currentBossEncID)
        return BuildItemLink(itemID, raidBonusId)
    end

    if not isBonusRollMode and totalShared > 0 then
        for i, itemID in ipairs(sharedItems) do
            AddItemToPool(sharedDisplayFrames, sharedFrame, i, itemID, bonusIdToUse, linkFor(itemID), false, sharedItemsPerCol, trackLabelToUse, 0)
        end
    end

    for si = 1, numSpecs do
        local specID = specs[si].id
        for i, itemID in ipairs(specItems[si]) do
            AddItemToPool(specDisplayFrames[si], specFrames[si], i, itemID, bonusIdToUse, linkFor(itemID), true, nil, trackLabelToUse, specID)
        end
    end
end

-- All heavy init happens lazily on first show: run a scrape if the cache is
-- stale, classify the player's class if it hasn't been yet, and warm the item
-- cache. Subsequent opens are instant.
mainFrame:SetScript("OnShow", function()
    if not addonTable.Scraper:IsCacheFresh() then
        addonTable.Scraper:Scrape(false)
    end
    addonTable.Scraper:EnsureClassClassified(selectedClassID)
    PreloadAllItems()
    UpdateLootDisplay()
end)
