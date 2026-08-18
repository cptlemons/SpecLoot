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
mainFrame:SetSize(840, 600)
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

local function NormalizeKeystoneTier(keyLevel)
    local lvl = tonumber(keyLevel) or 10
    if lvl >= 10 then
        return 10 -- 10+ is all one shared pool
    elseif lvl >= 2 then
        return lvl -- 2, 3, 4, 5, 6, 7, 8, 9 are all individual
    else
        return 10 -- default
    end
end

local function GetReceivedItemKey(vMode, diffOrKeyTier, specID, itemID)
    if vMode == "raid" then
        local diff = diffOrKeyTier or selectedRaidDifficulty or 15
        return "raid:" .. diff .. ":" .. (specID or 0) .. ":" .. itemID
    else
        local tier = NormalizeKeystoneTier(diffOrKeyTier or selectedKeystoneLevel or 10)
        return "dungeon:" .. tier .. ":" .. (specID or 0) .. ":" .. itemID
    end
end

local function IsItemReceived(vMode, diffOrKeyTier, specID, itemID)
    if not SpecLootCharDB or not SpecLootCharDB.receivedItems then
        return false
    end
    local key = GetReceivedItemKey(vMode, diffOrKeyTier, specID, itemID)
    if SpecLootCharDB.receivedItems[key] then
        return true
    end
    -- Fallback for legacy key format (for dungeons when checking 10+ tier)
    if vMode ~= "raid" then
        local tier = NormalizeKeystoneTier(diffOrKeyTier or selectedKeystoneLevel or 10)
        if tier == 10 then
            if SpecLootCharDB.receivedItems["dungeon:" .. (specID or 0) .. ":" .. itemID] then
                return true
            end
            if SpecLootCharDB.receivedItems[(specID or 0) .. ":" .. itemID] then
                return true
            end
        end
    end
    return false
end

local function SetItemReceived(vMode, diffOrKeyTier, specID, itemID, isReceived)
    InitCharDB()
    local key = GetReceivedItemKey(vMode, diffOrKeyTier, specID, itemID)
    SpecLootCharDB.receivedItems[key] = isReceived and true or nil
    if not isReceived and vMode ~= "raid" then
        local tier = NormalizeKeystoneTier(diffOrKeyTier or selectedKeystoneLevel or 10)
        if tier == 10 then
            SpecLootCharDB.receivedItems["dungeon:" .. (specID or 0) .. ":" .. itemID] = nil
            SpecLootCharDB.receivedItems[(specID or 0) .. ":" .. itemID] = nil
        end
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
    elseif msg:match("^bonus%s+list") or msg:match("^bonus%s+rolls") or msg == "bonus list" or msg == "bonus rolls" or msg == "list" or msg == "rolls" or msg == "listrolls" or msg == "history" then
        if ListReceivedBonusRolls then
            ListReceivedBonusRolls()
        end
    elseif msg:match("^bonus%s+clear") or msg:match("^bonus%s+reset") or msg == "clear" or msg == "reset" or msg == "clearrolls" or msg == "resetrolls" then
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
        print("  /sl bonus list       list all marked bonus rolls for this character")
        print("  /sl bonus clear      reset marked bonus rolls for this character")
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

local function GetNormalLootTrackInfo(vMode, keystoneLevel, raidDifficulty, bossEncID)
    if vMode == "dungeon" then
        local ilvl, bonusId, track, rank = GetEndOfRunInfo(keystoneLevel)
        local trackData = addonTable.UpgradeTracks and addonTable.UpgradeTracks[track]
        local maxRank = trackData and #trackData or 6
        local shortTrack = track:sub(1, 1):upper() .. track:sub(2)
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
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["lfr"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 279
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12825
            trackLabel = bossRank .. "/8 Vet"
        elseif raidDifficulty == 14 then
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["normal"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 292
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12833
            trackLabel = bossRank .. "/8 Champ"
        elseif raidDifficulty == 15 then
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["heroic"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 305
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12841
            trackLabel = bossRank .. "/6 Hero"
        else
            local trackData = addonTable.RaidTracks and addonTable.RaidTracks["mythic"]
            ilvl = trackData and trackData[bossRank] and trackData[bossRank].ilvl or 318
            bonusId = trackData and trackData[bossRank] and trackData[bossRank].bonusId or 12849
            trackLabel = bossRank .. "/6 Myth"
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
            local raidDiff, dungeonTier, specID, itemID
            local vMode = "dungeon"

            if key:match("^raid:") then
                vMode = "raid"
                local d, s, i = key:match("^raid:(%d+):(%d+):(%d+)")
                raidDiff = tonumber(d)
                specID = tonumber(s)
                itemID = tonumber(i)
            elseif key:match("^dungeon:%d+:%d+:%d+") then
                local t, s, i = key:match("^dungeon:(%d+):(%d+):(%d+)")
                dungeonTier = tonumber(t)
                specID = tonumber(s)
                itemID = tonumber(i)
            elseif key:match("^dungeon:") then
                local s, i = key:match("^dungeon:(%d+):(%d+)")
                dungeonTier = 10
                specID = tonumber(s)
                itemID = tonumber(i)
            else
                local s, i = key:match("^(%d+):(%d+)")
                dungeonTier = 10
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
                    local dTier = dungeonTier or 10
                    if dTier >= 10 then
                        difficultyText = "Mythic+ (10+)"
                    else
                        difficultyText = string.format("Mythic+ (+%d)", dTier)
                    end
                    local _, bId = GetBonusRollTrackInfo("dungeon", dTier)
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
        local rawKeyLvl = currentKeyLevel or selectedKeystoneLevel or 10
        local dungeonName = (dungeonMatch and dungeonMatch.name) or (name ~= "" and name) or "Mythic+ Dungeon"
        sourceName = dungeonName
        difficultyText = string.format("Mythic+ (+%d)", rawKeyLvl)

        local _, bId = GetBonusRollTrackInfo("dungeon", rawKeyLvl)
        scaledBonusId = bId
        shouldTrack = true
    end

    if shouldTrack and sourceName and difficultyText then
        local function executeTrack()
            local vMode = (isInsideRaid or (raidMatch and not isInsideParty)) and "raid" or "dungeon"
            local diffOrKeyTier
            if vMode == "raid" then
                diffOrKeyTier = (difficultyID and difficultyID > 0 and isInsideRaid) and difficultyID or cachedRaidDifficultyID or selectedRaidDifficulty or 15
            else
                local rawKeyLvl = currentKeyLevel or selectedKeystoneLevel or 10
                diffOrKeyTier = NormalizeKeystoneTier(rawKeyLvl)
            end

            local alreadyReceived = IsItemReceived(vMode, diffOrKeyTier, effectiveSpecID, itemID)
            local displayLink = BuildItemHyperlink(itemID, scaledBonusId)

            if alreadyReceived then
                print(string.format("|cffa335eeSpecLoot|r: Detected %s from %s on %s (Loot Spec: %s), but it was already marked as received.",
                    displayLink, sourceName, difficultyText, specName))
            else
                SetItemReceived(vMode, diffOrKeyTier, effectiveSpecID, itemID, true)

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
-- SHARED LOOT FRAME & BONUS ROLL BANNER
-----------------------------------------

local SLOT_ORDER = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 20, 99 }
local currentLootTable = {}

local bonusRollBanner = CreateFrame("Frame", "SpecLootBonusRollBanner", mainFrame, "BackdropTemplate")
bonusRollBanner:SetSize(816, 24)
bonusRollBanner:SetPoint("TOP", mainFrame, "TOP", 0, dungeonRowY - iconSize - 8)
bonusRollBanner.bg = bonusRollBanner:CreateTexture(nil, "BACKGROUND")
bonusRollBanner.bg:SetAllPoints()
bonusRollBanner.bg:SetColorTexture(0.08, 0.08, 0.08, 0.8)

bonusRollBanner.borderTop = bonusRollBanner:CreateTexture(nil, "ARTWORK")
bonusRollBanner.borderTop:SetHeight(1)
bonusRollBanner.borderTop:SetPoint("TOPLEFT", 0, 0)
bonusRollBanner.borderTop:SetPoint("TOPRIGHT", 0, 0)
bonusRollBanner.borderTop:SetColorTexture(1, 0.82, 0, 0.35)

bonusRollBanner.borderBottom = bonusRollBanner:CreateTexture(nil, "ARTWORK")
bonusRollBanner.borderBottom:SetHeight(1)
bonusRollBanner.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
bonusRollBanner.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
bonusRollBanner.borderBottom:SetColorTexture(1, 0.82, 0, 0.35)

bonusRollBanner.text = bonusRollBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bonusRollBanner.text:SetPoint("CENTER", 0, 0)
bonusRollBanner:Hide()

local sharedFrame = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
sharedFrame:SetSize(816, 0)
sharedFrame:Hide()

-----------------------------------------
-- SPEC FRAMES (bottom section, up to 4)
-----------------------------------------

local specFrames = {}
local specDisplayFrames = {}
local specHeaderFrames = {}
local MAX_SPECS = 4

local specBgColors = {
    { 0.20, 0.10, 0.10, 0.5 },
    { 0.10, 0.10, 0.20, 0.5 },
    { 0.10, 0.20, 0.10, 0.5 },
    { 0.18, 0.12, 0.18, 0.5 },
}

for i = 1, MAX_SPECS do
    local f = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    f:SetSize(200, 230)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    local c = specBgColors[i]
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4])

    -- Spec icon and title at BOTTOM, centered, 28x28
    f.specIcon = f:CreateTexture(nil, "OVERLAY")
    f.specIcon:SetSize(28, 28)
    f.specIcon:SetPoint("BOTTOM", f, "BOTTOM", -36, 8)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.specIcon, "RIGHT", 6, 0)

    if i == 1 then
        f.extraIcons = {}
        for extraIdx = 2, 3 do
            local icon = f:CreateTexture(nil, "OVERLAY")
            icon:SetSize(24, 24)
            if extraIdx == 2 then
                icon:SetPoint("LEFT", f.specIcon, "RIGHT", 4, 0)
            else
                icon:SetPoint("LEFT", f.extraIcons[2], "RIGHT", 4, 0)
            end
            icon:Hide()
            f.extraIcons[extraIdx] = icon
        end
    end

    f:Hide()
    specFrames[i] = f
    specDisplayFrames[i] = {}
    specHeaderFrames[i] = {}
end

-----------------------------------------
-- DISPLAY FRAME MANAGEMENT
-----------------------------------------

local sharedDisplayFrames = {}

local function ClearAllDisplayFrames()
    for _, f in ipairs(sharedDisplayFrames) do
        f:Hide()
        if f.strikeLine then f.strikeLine:Hide() end
        if f.exclusiveHighlight then f.exclusiveHighlight:Hide() end
        if f.exclusiveBar then f.exclusiveBar:Hide() end
    end
    for si = 1, MAX_SPECS do
        for _, f in ipairs(specDisplayFrames[si]) do
            f:Hide()
            if f.strikeLine then f.strikeLine:Hide() end
            if f.exclusiveHighlight then f.exclusiveHighlight:Hide() end
            if f.exclusiveBar then f.exclusiveBar:Hide() end
        end
        for _, f in ipairs(specHeaderFrames[si]) do
            f:Hide()
        end
    end
    ClearRegistry()
end

local function IsItemExclusiveToSpec(itemID, classID, specs)
    local count = 0
    for _, spec in ipairs(specs) do
        if DoesItemDropForSpec(itemID, classID, spec.id) then
            count = count + 1
        end
    end
    return (count == 1)
end

local function UpdateSpecFooterCounts()
    local classID = selectedClassID
    local specs = GetClassSpecs(classID)
    local numSpecs = #specs
    if numSpecs == 0 then return end

    local isUnified = (not isBonusRollMode) and (classID == 8 or classID == 9)
    local diffOrTier = (viewMode == "raid") and selectedRaidDifficulty or selectedKeystoneLevel

    if isUnified then
        local totalCount = 0
        for _, itemID in ipairs(currentLootTable or {}) do
            if IsItemAllowed(itemID) and DoesItemDropForSpec(itemID, classID, specs[1].id) then
                totalCount = totalCount + 1
            end
        end
        specFrames[1].title:SetText(string.format("All Specializations (%d)", totalCount))
    else
        for si = 1, numSpecs do
            local spec = specs[si]
            local totalCount = 0
            local receivedCount = 0
            for _, itemID in ipairs(currentLootTable or {}) do
                if IsItemAllowed(itemID) and DoesItemDropForSpec(itemID, classID, spec.id) then
                    totalCount = totalCount + 1
                    if IsItemReceived(viewMode, diffOrTier, spec.id, itemID) then
                        receivedCount = receivedCount + 1
                    end
                end
            end
            if isBonusRollMode then
                local remaining = totalCount - receivedCount
                specFrames[si].title:SetText(string.format("%s (%d)", spec.name, remaining))
            else
                specFrames[si].title:SetText(string.format("%s (%d)", spec.name, totalCount))
            end
        end
    end
end

local function UpdateItemReceivedVisuals(itemFrame, isReceived)
    itemFrame.isReceived = isReceived
    if isBonusRollMode and isReceived then
        itemFrame.icon:SetDesaturated(true)
        itemFrame.icon:SetAlpha(0.35)
        itemFrame.text:SetAlpha(0.40)
        if itemFrame.strikeLine then
            local textWidth = itemFrame.text:GetStringWidth() or 100
            local maxStrike = (itemFrame:GetWidth() > 22 and itemFrame:GetWidth() - 22) or 200
            itemFrame.strikeLine:SetWidth(math.min(textWidth + 4, maxStrike))
            itemFrame.strikeLine:Show()
        end
        if itemFrame.isExclusive then
            if itemFrame.exclusiveHighlight then itemFrame.exclusiveHighlight:SetAlpha(0.35) end
            if itemFrame.exclusiveBar then itemFrame.exclusiveBar:SetAlpha(0.35) end
        end
    else
        itemFrame.icon:SetDesaturated(false)
        itemFrame.icon:SetAlpha(1.0)
        itemFrame.text:SetAlpha(1.0)
        if itemFrame.strikeLine then
            itemFrame.strikeLine:Hide()
        end
        if itemFrame.isExclusive then
            if itemFrame.exclusiveHighlight then itemFrame.exclusiveHighlight:SetAlpha(1.0) end
            if itemFrame.exclusiveBar then itemFrame.exclusiveBar:SetAlpha(1.0) end
        end
    end
end

local function CreateOrReuseHeaderFrame(pool, index, parent)
    local headerFrame = pool[index]
    if not headerFrame then
        headerFrame = CreateFrame("Frame", nil, parent)
        headerFrame:SetHeight(18)

        headerFrame.text = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerFrame.text:SetPoint("LEFT", headerFrame, "LEFT", 2, 0)
        headerFrame.text:SetJustifyH("LEFT")

        headerFrame.line = headerFrame:CreateTexture(nil, "ARTWORK")
        headerFrame.line:SetHeight(1)
        headerFrame.line:SetPoint("LEFT", headerFrame.text, "RIGHT", 6, 0)
        headerFrame.line:SetPoint("RIGHT", headerFrame, "RIGHT", -2, 0)
        headerFrame.line:SetColorTexture(1, 0.82, 0, 0.25)

        pool[index] = headerFrame
    end

    if headerFrame:GetParent() ~= parent then
        headerFrame:SetParent(parent)
    end

    return headerFrame
end

local STAT_NAMES = {
    [0] = "Crit",
    [1] = "Haste",
    [2] = "Mast",
    [3] = "Vers",
}

local STAT_PRIORITY = {
    ["Crit"] = 1,
    ["Haste"] = 2,
    ["Vers"] = 3,
    ["Mast"] = 4,
}

local SPEC_PRIMARY_STAT = {
    -- Strength
    [71] = "Str", [72] = "Str", [73] = "Str",
    [66] = "Str", [70] = "Str",
    [250] = "Str", [251] = "Str", [252] = "Str",
    -- Agility
    [253] = "Agi", [254] = "Agi", [255] = "Agi",
    [259] = "Agi", [260] = "Agi", [261] = "Agi",
    [263] = "Agi",
    [268] = "Agi", [269] = "Agi",
    [103] = "Agi", [104] = "Agi",
    [577] = "Agi", [581] = "Agi",
    -- Intellect
    [65] = "Int",
    [256] = "Int", [257] = "Int", [258] = "Int",
    [262] = "Int", [264] = "Int",
    [62] = "Int", [63] = "Int", [64] = "Int",
    [265] = "Int", [266] = "Int", [267] = "Int",
    [270] = "Int",
    [102] = "Int", [105] = "Int",
    [1467] = "Int", [1468] = "Int", [1473] = "Int",
    [1480] = "Int",
}

local function GetItemStatString(itemID)
    local itemData = GetItemData(itemID)
    local dbItem = addonTable.ItemDatabase and addonTable.ItemDatabase[itemID]
    local slotId = (itemData and itemData.slotId) or (dbItem and dbItem.slotId) or GetSlotId(itemID)

    -- Trinkets, tokens, curios do not display stats
    if slotId == 13 or slotId == 14 or slotId == 20 or slotId == 99 then
        return ""
    end

    local rawStats = (dbItem and dbItem.stats) or (itemData and itemData.stats)
    local secondaries = {}

    if rawStats and #rawStats > 0 then
        for _, s in ipairs(rawStats) do
            local name = STAT_NAMES[s]
            if name then
                table.insert(secondaries, name)
            end
        end
    end

    -- If no raw stats found in database, try C_Item.GetItemStats if available
    if #secondaries == 0 then
        local link = select(2, C_Item.GetItemInfo(itemID)) or ("item:" .. itemID)
        local statsTable = C_Item.GetItemStats(link)
        if statsTable then
            if statsTable["ITEM_MOD_CRIT_RATING_SHORT"] or statsTable["ITEM_MOD_CRIT_RATING"] then
                table.insert(secondaries, "Crit")
            end
            if statsTable["ITEM_MOD_HASTE_RATING_SHORT"] or statsTable["ITEM_MOD_HASTE_RATING"] then
                table.insert(secondaries, "Haste")
            end
            if statsTable["ITEM_MOD_VERSATILITY"] or statsTable["ITEM_MOD_VERSATILITY_RATING"] then
                table.insert(secondaries, "Vers")
            end
            if statsTable["ITEM_MOD_MASTERY_RATING_SHORT"] or statsTable["ITEM_MOD_MASTERY_RATING"] then
                table.insert(secondaries, "Mast")
            end
        end
    end

    -- Sort secondaries by priority: Crit > Haste > Vers > Mast
    table.sort(secondaries, function(a, b)
        return (STAT_PRIORITY[a] or 99) < (STAT_PRIORITY[b] or 99)
    end)

    local secString = table.concat(secondaries, "/")

    -- Check for Cantrip effect
    local hasCantrip = false
    if rawStats and #rawStats == 1 then
        hasCantrip = true
    else
        local spellName = C_Item.GetItemSpell(itemID)
        if spellName and spellName ~= "" then
            hasCantrip = true
        end
    end

    -- Primary stats for weapons & off-hands (slot 10, 11)
    local isWeapon = (slotId == 10 or slotId == 11)
    local primString = ""

    if isWeapon then
        local classes = (dbItem and dbItem.classes) or (itemData and itemData.classes)
        local hasStr, hasAgi, hasInt = false, false, false
        if classes then
            for _, specList in pairs(classes) do
                for _, specID in ipairs(specList) do
                    local prim = SPEC_PRIMARY_STAT[specID]
                    if prim == "Str" then hasStr = true
                    elseif prim == "Agi" then hasAgi = true
                    elseif prim == "Int" then hasInt = true end
                end
            end
        end

        local primaries = {}
        if hasStr then table.insert(primaries, "Str") end
        if hasAgi then table.insert(primaries, "Agi") end
        if hasInt then table.insert(primaries, "Int") end

        if #primaries > 0 then
            primString = table.concat(primaries, "/")
        end
    end

    -- Build final stat tag
    local parts = {}
    if primString ~= "" then
        table.insert(parts, primString)
    end
    if secString ~= "" then
        table.insert(parts, secString)
    end
    if hasCantrip then
        table.insert(parts, "Cantrip")
    end

    return table.concat(parts, " ")
end

local function CreateOrReuseItemFrame(pool, index, parent)
    local itemFrame = pool[index]
    if not itemFrame then
        itemFrame = CreateFrame("Button", nil, parent)
        itemFrame:SetSize(200, 20)
        itemFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        itemFrame.icon = itemFrame:CreateTexture(nil, "ARTWORK")
        itemFrame.icon:SetSize(18, 18)
        itemFrame.icon:SetPoint("LEFT", 0, 0)

        itemFrame.text = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemFrame.text:SetPoint("LEFT", itemFrame.icon, "RIGHT", 4, 0)
        itemFrame.text:SetWidth(170)
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

        itemFrame.exclusiveHighlight = itemFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        itemFrame.exclusiveHighlight:SetPoint("TOPLEFT", -2, 1)
        itemFrame.exclusiveHighlight:SetPoint("BOTTOMRIGHT", 2, -1)
        itemFrame.exclusiveHighlight:SetColorTexture(1, 0.82, 0, 0.14)
        itemFrame.exclusiveHighlight:Hide()

        itemFrame.exclusiveBar = itemFrame:CreateTexture(nil, "ARTWORK", nil, 6)
        itemFrame.exclusiveBar:SetSize(2, 16)
        itemFrame.exclusiveBar:SetPoint("LEFT", itemFrame, "LEFT", -2, 0)
        itemFrame.exclusiveBar:SetColorTexture(1, 0.82, 0, 0.90)
        itemFrame.exclusiveBar:Hide()

        itemFrame:SetScript("OnClick", function(self, button)
            if button == "RightButton" and isBonusRollMode then
                local diffOrTier = (self.viewMode == "raid") and self.raidDifficulty or self.keystoneLevel
                local isReceived = not IsItemReceived(self.viewMode, diffOrTier, self.specID, self.itemID)
                SetItemReceived(self.viewMode, diffOrTier, self.specID, self.itemID, isReceived)

                local itemName = C_Item.GetItemInfo(self.itemID) or "Loading..."
                local statText = GetItemStatString(self.itemID)
                local statSuffix = (statText and statText ~= "") and (" |cff888888" .. statText .. "|r") or ""
                if isReceived then
                    self.text:SetText("|cff888888" .. itemName .. "|r" .. statSuffix)
                else
                    self.text:SetText("|cffa335ee" .. itemName .. "|r" .. statSuffix)
                end
                UpdateItemReceivedVisuals(self, isReceived)
                UpdateSpecFooterCounts()
            end
        end)

        itemFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local link = self.itemLink or BuildItemLink(self.itemID, self.bonusId)
            GameTooltip:SetHyperlink(link)
            if self.isExclusive then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffffd100★ Spec-Exclusive Item (Drops only for this spec)|r")
            end
            if isBonusRollMode then
                local diffOrTier = (self.viewMode == "raid") and self.raidDifficulty or self.keystoneLevel
                local isRec = IsItemReceived(self.viewMode, diffOrTier, self.specID, self.itemID)
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

-----------------------------------------
-- LAYOUT SPEC FRAMES
-----------------------------------------

local function LayoutSpecFrames(numSpecs, isUnified)
    local totalWidth = 816
    local gap = 4
    local specTopY = (dungeonRowY - iconSize - 8) - 24 - 6

    if isUnified then
        local f = specFrames[1]
        f:ClearAllPoints()
        local startX = (mainFrame:GetWidth() - totalWidth) / 2
        f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX, specTopY)
        f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", startX, 8)
        f:SetWidth(totalWidth)
        f:Show()
        for i = 2, MAX_SPECS do
            specFrames[i]:Hide()
        end
        return
    end

    local panelWidth = (totalWidth - (gap * (numSpecs - 1))) / numSpecs
    local startX = (mainFrame:GetWidth() - totalWidth) / 2
    if startX <= 0 then startX = 12 end

    for i = 1, MAX_SPECS do
        if i <= numSpecs then
            local f = specFrames[i]
            f:ClearAllPoints()
            local offsetX = (i - 1) * (panelWidth + gap)

            f:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", startX + offsetX, specTopY)
            f:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", startX + offsetX, 8)
            f:SetWidth(panelWidth)
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

    currentLootTable = lootTable
    local bonusIdToUse = bonusId
    local isUnified = (not isBonusRollMode) and (classID == 8 or classID == 9)

    local function linkFor(itemID, scaledBonusId)
        if isBonusRollMode then
            return BuildItemLink(itemID, scaledBonusId)
        end
        if viewMode == "raid" then
            local d = GetItemData(itemID)
            if d and d.links and d.links[selectedRaidDifficulty] then
                return d.links[selectedRaidDifficulty]
            end
            local raidBonusId = GetRaidBonusId(selectedRaidDifficulty, currentBossEncID)
            return BuildItemLink(itemID, raidBonusId)
        else
            return BuildItemLink(itemID, scaledBonusId)
        end
    end

    if isBonusRollMode then
        local _, gvBonusId, gvLabel = GetBonusRollTrackInfo(viewMode, selectedKeystoneLevel, selectedRaidDifficulty, currentBossEncID)
        bonusIdToUse = gvBonusId

        bonusRollBanner:Show()
        bonusRollBanner:SetWidth(816)
        bonusRollBanner.text:SetText(string.format("Bonus rolls give |cff55ff55%s|r loot", gvLabel or "Myth"))

        sharedFrame:Hide()
        sharedFrame:SetHeight(0)

        local specItemsBySlot = {}
        for si = 1, numSpecs do
            specItemsBySlot[si] = {}
        end

        for _, itemID in ipairs(lootTable) do
            if IsItemAllowed(itemID) then
                local slotId = GetSlotId(itemID)
                for si, spec in ipairs(specs) do
                    if DoesItemDropForSpec(itemID, classID, spec.id) then
                        specItemsBySlot[si][slotId] = specItemsBySlot[si][slotId] or {}
                        table.insert(specItemsBySlot[si][slotId], itemID)
                    end
                end
            end
        end

        local activeSlots = {}
        for _, slotId in ipairs(SLOT_ORDER) do
            local maxCount = 0
            for si = 1, numSpecs do
                local items = specItemsBySlot[si][slotId]
                local count = items and #items or 0
                if count > maxCount then maxCount = count end
            end
            if maxCount > 0 then
                table.insert(activeSlots, {
                    slotId = slotId,
                    slotName = addonTable.SlotNames[slotId] or "Other",
                    maxCount = maxCount
                })
            end
        end

        local totalSlotRows = 0
        for _, slot in ipairs(activeSlots) do
            totalSlotRows = totalSlotRows + 1 + slot.maxCount
        end
        local contentHeight = 10 + (totalSlotRows * 21) + (#activeSlots * 4) + 40
        local calculatedHeight = math.max(580, 160 + contentHeight + 12)
        mainFrame:SetHeight(calculatedHeight)

        LayoutSpecFrames(numSpecs, false)

        if specFrames[1].extraIcons then
            specFrames[1].extraIcons[2]:Hide()
            specFrames[1].extraIcons[3]:Hide()
        end

        for i, spec in ipairs(specs) do
            specFrames[i].specIcon:SetSize(28, 28)
            specFrames[i].specIcon:ClearAllPoints()
            specFrames[i].specIcon:SetPoint("BOTTOM", specFrames[i], "BOTTOM", -36, 8)
            specFrames[i].specIcon:SetTexture(spec.icon)
            specFrames[i].title:ClearAllPoints()
            specFrames[i].title:SetPoint("LEFT", specFrames[i].specIcon, "RIGHT", 6, 0)
        end

        local panelWidth = (816 - (4 * (numSpecs - 1))) / numSpecs

        for si = 1, numSpecs do
            local spec = specs[si]
            local parent = specFrames[si]
            local currentY = -10
            local itemPoolIdx = 1
            local headerPoolIdx = 1

            for _, slot in ipairs(activeSlots) do
                local slotId = slot.slotId
                local items = specItemsBySlot[si][slotId] or {}
                local hasItems = #items > 0

                -- Slot Header
                local headerFrame = CreateOrReuseHeaderFrame(specHeaderFrames[si], headerPoolIdx, parent)
                headerFrame:ClearAllPoints()
                headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, currentY)
                headerFrame:SetWidth(panelWidth - 12)

                if hasItems then
                    headerFrame.text:SetText("|cffffd100" .. slot.slotName .. "|r")
                    headerFrame.line:SetColorTexture(1, 0.82, 0, 0.25)
                else
                    headerFrame.text:SetText("|cff666666" .. slot.slotName .. "|r")
                    headerFrame.line:SetColorTexture(1, 1, 1, 0.08)
                end
                headerFrame:Show()
                headerPoolIdx = headerPoolIdx + 1
                currentY = currentY - 18

                -- Items under this slot
                for rowIdx = 1, slot.maxCount do
                    local itemID = items[rowIdx]
                    if itemID then
                        local itemFrame = CreateOrReuseItemFrame(specDisplayFrames[si], itemPoolIdx, parent)
                        itemFrame:ClearAllPoints()
                        itemFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, currentY)
                        itemFrame:SetSize(panelWidth - 12, 20)
                        itemFrame.text:SetWidth(panelWidth - 12 - 22)

                        itemFrame.itemID = itemID
                        itemFrame.specID = spec.id
                        itemFrame.bonusId = bonusIdToUse
                        itemFrame.itemLink = linkFor(itemID, bonusIdToUse)
                        itemFrame.trackLabel = nil
                        itemFrame.viewMode = viewMode
                        itemFrame.raidDifficulty = selectedRaidDifficulty
                        itemFrame.keystoneLevel = selectedKeystoneLevel

                        local isExclusive = IsItemExclusiveToSpec(itemID, classID, specs)
                        itemFrame.isExclusive = isExclusive
                        if isExclusive then
                            itemFrame.exclusiveHighlight:Show()
                            itemFrame.exclusiveBar:Show()
                        else
                            itemFrame.exclusiveHighlight:Hide()
                            itemFrame.exclusiveBar:Hide()
                        end

                        local itemName = C_Item.GetItemInfo(itemID)
                        local itemData = GetItemData(itemID)
                        local dbIcon = (itemData and itemData.icon) or C_Item.GetItemIconByID(itemID)

                        local diffOrTier = (viewMode == "raid") and selectedRaidDifficulty or selectedKeystoneLevel
                        local isReceived = IsItemReceived(viewMode, diffOrTier, spec.id, itemID)

                        local statText = GetItemStatString(itemID)
                        local statSuffix = (statText and statText ~= "") and (" |cff888888" .. statText .. "|r") or ""

                        if isReceived then
                            itemFrame.text:SetText("|cff888888" .. (itemName or "Loading...") .. "|r" .. statSuffix)
                        else
                            itemFrame.text:SetText("|cffa335ee" .. (itemName or "Loading...") .. "|r" .. statSuffix)
                        end
                        itemFrame.icon:SetTexture(dbIcon or 134400)
                        itemFrame.dupHighlight:Hide()

                        UpdateItemReceivedVisuals(itemFrame, isReceived)
                        itemFrame:Show()
                        RegisterItemFrame(itemID, itemFrame)
                        itemPoolIdx = itemPoolIdx + 1
                    end
                    currentY = currentY - 21
                end
                currentY = currentY - 4
            end
        end

        UpdateSpecFooterCounts()
    else
        local _, _, normalTrackLabel = GetNormalLootTrackInfo(viewMode, selectedKeystoneLevel, selectedRaidDifficulty, currentBossEncID)

        bonusRollBanner:Show()
        bonusRollBanner:SetWidth(816)
        bonusRollBanner.text:SetText(string.format("Loot drops at |cff55ff55%s|r", normalTrackLabel or "1/6 Myth"))

        sharedFrame:Hide()
        sharedFrame:SetHeight(0)

        local specItemsBySlot = {}
        for si = 1, numSpecs do
            specItemsBySlot[si] = {}
        end

        for _, itemID in ipairs(lootTable) do
            if IsItemAllowed(itemID) then
                local slotId = GetSlotId(itemID)
                for si, spec in ipairs(specs) do
                    if DoesItemDropForSpec(itemID, classID, spec.id) then
                        specItemsBySlot[si][slotId] = specItemsBySlot[si][slotId] or {}
                        table.insert(specItemsBySlot[si][slotId], itemID)
                    end
                end
            end
        end

        local activeSlots = {}
        for _, slotId in ipairs(SLOT_ORDER) do
            local maxCount = 0
            for si = 1, numSpecs do
                local items = specItemsBySlot[si][slotId]
                local count = items and #items or 0
                if count > maxCount then maxCount = count end
            end
            if maxCount > 0 then
                table.insert(activeSlots, {
                    slotId = slotId,
                    slotName = addonTable.SlotNames[slotId] or "Other",
                    maxCount = maxCount
                })
            end
        end

        local totalSlotRows = 0
        for _, slot in ipairs(activeSlots) do
            totalSlotRows = totalSlotRows + 1 + slot.maxCount
        end
        local contentHeight = 10 + (totalSlotRows * 21) + (#activeSlots * 4) + 40
        local calculatedHeight = math.max(580, 160 + contentHeight + 12)
        mainFrame:SetHeight(calculatedHeight)

        if isUnified then
            LayoutSpecFrames(numSpecs, true)

            -- Footer on specFrames[1] with all 3 spec icons
            local f = specFrames[1]
            f.specIcon:SetSize(24, 24)
            f.specIcon:ClearAllPoints()
            f.specIcon:SetPoint("BOTTOM", f, "BOTTOM", -110, 8)
            f.specIcon:SetTexture(specs[1].icon)

            if f.extraIcons then
                f.extraIcons[2]:SetTexture(specs[2].icon)
                f.extraIcons[2]:Show()
                f.extraIcons[3]:SetTexture(specs[3].icon)
                f.extraIcons[3]:Show()
                f.title:ClearAllPoints()
                f.title:SetPoint("LEFT", f.extraIcons[3], "RIGHT", 8, 0)
            end

            local parent = specFrames[1]
            local currentY = -10
            local itemPoolIdx = 1
            local headerPoolIdx = 1
            local colWidth = 480
            local colOffset = (816 - colWidth) / 2

            for _, slot in ipairs(activeSlots) do
                local slotId = slot.slotId
                local items = specItemsBySlot[1][slotId] or {}

                if #items > 0 then
                    -- Slot Header
                    local headerFrame = CreateOrReuseHeaderFrame(specHeaderFrames[1], headerPoolIdx, parent)
                    headerFrame:ClearAllPoints()
                    headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", colOffset, currentY)
                    headerFrame:SetWidth(colWidth)
                    headerFrame.text:SetText("|cffffd100" .. slot.slotName .. "|r")
                    headerFrame.line:SetColorTexture(1, 0.82, 0, 0.25)
                    headerFrame:Show()
                    headerPoolIdx = headerPoolIdx + 1
                    currentY = currentY - 18

                    -- Items under this slot
                    for _, itemID in ipairs(items) do
                        local itemFrame = CreateOrReuseItemFrame(specDisplayFrames[1], itemPoolIdx, parent)
                        itemFrame:ClearAllPoints()
                        itemFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", colOffset, currentY)
                        itemFrame:SetSize(colWidth, 20)
                        itemFrame.text:SetWidth(colWidth - 22)

                        itemFrame.itemID = itemID
                        itemFrame.specID = specs[1].id
                        itemFrame.bonusId = bonusIdToUse
                        itemFrame.itemLink = linkFor(itemID, bonusIdToUse)
                        itemFrame.trackLabel = nil
                        itemFrame.viewMode = viewMode
                        itemFrame.raidDifficulty = selectedRaidDifficulty
                        itemFrame.keystoneLevel = selectedKeystoneLevel

                        itemFrame.isExclusive = false
                        itemFrame.exclusiveHighlight:Hide()
                        itemFrame.exclusiveBar:Hide()

                        local itemName = C_Item.GetItemInfo(itemID)
                        local itemData = GetItemData(itemID)
                        local dbIcon = (itemData and itemData.icon) or C_Item.GetItemIconByID(itemID)

                        local statText = GetItemStatString(itemID)
                        local statSuffix = (statText and statText ~= "") and (" |cff888888" .. statText .. "|r") or ""

                        itemFrame.text:SetText("|cffa335ee" .. (itemName or "Loading...") .. "|r" .. statSuffix)
                        itemFrame.icon:SetTexture(dbIcon or 134400)
                        itemFrame.dupHighlight:Hide()

                        UpdateItemReceivedVisuals(itemFrame, false)
                        itemFrame:Show()
                        RegisterItemFrame(itemID, itemFrame)
                        itemPoolIdx = itemPoolIdx + 1
                        currentY = currentY - 21
                    end
                    currentY = currentY - 4
                end
            end
        else
            LayoutSpecFrames(numSpecs, false)

            if specFrames[1].extraIcons then
                specFrames[1].extraIcons[2]:Hide()
                specFrames[1].extraIcons[3]:Hide()
            end

            for i, spec in ipairs(specs) do
                specFrames[i].specIcon:SetSize(28, 28)
                specFrames[i].specIcon:ClearAllPoints()
                specFrames[i].specIcon:SetPoint("BOTTOM", specFrames[i], "BOTTOM", -36, 8)
                specFrames[i].specIcon:SetTexture(spec.icon)
                specFrames[i].title:ClearAllPoints()
                specFrames[i].title:SetPoint("LEFT", specFrames[i].specIcon, "RIGHT", 6, 0)
            end

            local panelWidth = (816 - (4 * (numSpecs - 1))) / numSpecs

            for si = 1, numSpecs do
                local spec = specs[si]
                local parent = specFrames[si]
                local currentY = -10
                local itemPoolIdx = 1
                local headerPoolIdx = 1

                for _, slot in ipairs(activeSlots) do
                    local slotId = slot.slotId
                    local items = specItemsBySlot[si][slotId] or {}
                    local hasItems = #items > 0

                    -- Slot Header
                    local headerFrame = CreateOrReuseHeaderFrame(specHeaderFrames[si], headerPoolIdx, parent)
                    headerFrame:ClearAllPoints()
                    headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, currentY)
                    headerFrame:SetWidth(panelWidth - 12)

                    if hasItems then
                        headerFrame.text:SetText("|cffffd100" .. slot.slotName .. "|r")
                        headerFrame.line:SetColorTexture(1, 0.82, 0, 0.25)
                    else
                        headerFrame.text:SetText("|cff666666" .. slot.slotName .. "|r")
                        headerFrame.line:SetColorTexture(1, 1, 1, 0.08)
                    end
                    headerFrame:Show()
                    headerPoolIdx = headerPoolIdx + 1
                    currentY = currentY - 18

                    -- Items under this slot
                    for rowIdx = 1, slot.maxCount do
                        local itemID = items[rowIdx]
                        if itemID then
                            local itemFrame = CreateOrReuseItemFrame(specDisplayFrames[si], itemPoolIdx, parent)
                            itemFrame:ClearAllPoints()
                            itemFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, currentY)
                            itemFrame:SetSize(panelWidth - 12, 20)
                            itemFrame.text:SetWidth(panelWidth - 12 - 22)

                            itemFrame.itemID = itemID
                            itemFrame.specID = spec.id
                            itemFrame.bonusId = bonusIdToUse
                            itemFrame.itemLink = linkFor(itemID, bonusIdToUse)
                            itemFrame.trackLabel = nil
                            itemFrame.viewMode = viewMode
                            itemFrame.raidDifficulty = selectedRaidDifficulty
                            itemFrame.keystoneLevel = selectedKeystoneLevel

                            local isExclusive = IsItemExclusiveToSpec(itemID, classID, specs)
                            itemFrame.isExclusive = isExclusive
                            if isExclusive then
                                itemFrame.exclusiveHighlight:Show()
                                itemFrame.exclusiveBar:Show()
                            else
                                itemFrame.exclusiveHighlight:Hide()
                                itemFrame.exclusiveBar:Hide()
                            end

                            local itemName = C_Item.GetItemInfo(itemID)
                            local itemData = GetItemData(itemID)
                            local dbIcon = (itemData and itemData.icon) or C_Item.GetItemIconByID(itemID)

                            local statText = GetItemStatString(itemID)
                            local statSuffix = (statText and statText ~= "") and (" |cff888888" .. statText .. "|r") or ""

                            itemFrame.text:SetText("|cffa335ee" .. (itemName or "Loading...") .. "|r" .. statSuffix)
                            itemFrame.icon:SetTexture(dbIcon or 134400)
                            itemFrame.dupHighlight:Hide()

                            UpdateItemReceivedVisuals(itemFrame, false)
                            itemFrame:Show()
                            RegisterItemFrame(itemID, itemFrame)
                            itemPoolIdx = itemPoolIdx + 1
                        end
                        currentY = currentY - 21
                    end
                    currentY = currentY - 4
                end
            end
        end

        UpdateSpecFooterCounts()
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
