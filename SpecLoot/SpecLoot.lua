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
mainFrame:SetSize(800, 625)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame.TitleText:SetText("SpecLoot")
mainFrame:Hide()

tinsert(UISpecialFrames, "SpecLootMainFrame")

SLASH_SPECLOOT1 = "/specloot"
SLASH_SPECLOOT2 = "/sl"
SlashCmdList["SPECLOOT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "rescan" or msg == "scrape" then
        addonTable.Scraper:Scrape(false)
    elseif msg == "debug" then
        addonTable.Scraper:Scrape(true)
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

-- Only watch for item-info refreshes at the global level. The expensive setup
-- (scrape + preload) is deferred to OnShow so login is effectively free.
mainFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "GET_ITEM_INFO_RECEIVED" then
        addonTable.Scraper:OnItemInfoReceived(arg1)
        ScheduleRefresh()
    end
end)

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
    return 266, 12795, "hero", 3
end

local function GetRaidDifficultyInfo(difficultyID)
    for _, d in ipairs(raidDifficulties) do
        if d.id == difficultyID then return d end
    end
    return raidDifficulties[1]
end

local function GetTrackLabel(track, rank)
    local trackData = addonTable.UpgradeTracks[track]
    local maxRank = trackData and #trackData or 6
    return track:sub(1, 1):upper() .. track:sub(2) .. " " .. rank .. "/" .. maxRank
end

local function GetClassSpecs(classID)
    local classInfo = addonTable.ClassInfo[classID]
    return classInfo and classInfo.specs or {}
end

local function GetItemData(itemID)
    return addonTable.Scraper:GetItemData(itemID)
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

local keystoneDropdown = CreateFrame("Frame", "SpecLootKeystoneDropdown", mainFrame, "UIDropDownMenuTemplate")
keystoneDropdown:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -8, -24)
UIDropDownMenu_SetWidth(keystoneDropdown, 70)

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
difficultyDropdown:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -8, -24)
UIDropDownMenu_SetWidth(difficultyDropdown, 100)
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
classDropdown:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 8, -24)
UIDropDownMenu_SetWidth(classDropdown, 120) -- Slightly wider to fit the icon nicely

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
local dungeonRowY = -52

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

local mythicTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
mythicTab:SetSize(80, 22)
mythicTab:SetText("Mythic+")
mythicTab:SetPoint("TOP", mainFrame, "TOP", -42, -24)

local raidTab = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
raidTab:SetSize(80, 22)
raidTab:SetText("Raids")
raidTab:SetPoint("TOP", mainFrame, "TOP", 42, -24)

local function UpdateTabHighlight()
    mythicTab:SetAlpha(viewMode == "dungeon" and 1.0 or 0.55)
    raidTab:SetAlpha(viewMode == "raid"    and 1.0 or 0.55)
end

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
    for _, f in ipairs(sharedDisplayFrames) do f:Hide() end
    for si = 1, MAX_SPECS do
        for _, f in ipairs(specDisplayFrames[si]) do f:Hide() end
    end
    ClearRegistry()
end

local function CreateOrReuseItemFrame(pool, index, parent)
    local itemFrame = pool[index]
    if not itemFrame then
        itemFrame = CreateFrame("Button", nil, parent)
        itemFrame:SetSize(240, 20)

        itemFrame.icon = itemFrame:CreateTexture(nil, "ARTWORK")
        itemFrame.icon:SetSize(18, 18)
        itemFrame.icon:SetPoint("LEFT")

        itemFrame.text = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemFrame.text:SetPoint("LEFT", itemFrame.icon, "RIGHT", 4, 0)
        itemFrame.text:SetWidth(215)
        itemFrame.text:SetWordWrap(false)
        itemFrame.text:SetJustifyH("LEFT")

        itemFrame.dupHighlight = itemFrame:CreateTexture(nil, "BACKGROUND")
        itemFrame.dupHighlight:SetPoint("TOPLEFT", -2, 1)
        itemFrame.dupHighlight:SetPoint("BOTTOMRIGHT", 2, -1)
        itemFrame.dupHighlight:SetColorTexture(1, 1, 1, 0.15)
        itemFrame.dupHighlight:Hide()

        itemFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            -- Prefer the precomputed link (raids: encodes per-difficulty ilvl).
            -- Fall back to BuildItemLink with the dungeon's keystone bonus ID.
            local link = self.itemLink or BuildItemLink(self.itemID, self.bonusId)
            GameTooltip:SetHyperlink(link)
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

local function AddItemToPool(pool, parent, index, itemID, bonusId, itemLink, singleColumn, itemsPerCol)
    local itemFrame = CreateOrReuseItemFrame(pool, index, parent)

    itemFrame.itemID = itemID
    itemFrame.bonusId = bonusId
    itemFrame.itemLink = itemLink -- nil for dungeons; raid links are pre-scaled to the chosen difficulty

    local itemName = C_Item.GetItemInfo(itemID)
    local itemData = GetItemData(itemID)
    -- Try cache first, then fresh lookup, then questionmark placeholder.
    local dbIcon = (itemData and itemData.icon) or C_Item.GetItemIconByID(itemID)
    local slotName = GetSlotName(itemID)

    -- Use epic purple color (|cffa335ee|) instead of the base item link color
    if itemName then
        itemFrame.text:SetText("|cffa335ee" .. itemName .. "|r |cff888888" .. slotName .. "|r")
    else
        itemFrame.text:SetText("|cffa335eeLoading...|r |cff888888" .. slotName .. "|r")
        C_Item.RequestLoadItemDataByID(itemID)
    end
    itemFrame.icon:SetTexture(dbIcon or 134400)
    itemFrame.dupHighlight:Hide()

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

    for i = 1, MAX_SPECS do
        if i <= numSpecs then
            local f = specFrames[i]
            f:ClearAllPoints()
            f:SetSize(panelWidth, 230)
            f:SetPoint("TOPLEFT", sharedFrame, "BOTTOMLEFT", (i - 1) * (panelWidth + gap), -6)
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

    LayoutSpecFrames(numSpecs)

    for i, spec in ipairs(specs) do
        specFrames[i].title:SetText(spec.name)
        specFrames[i].specIcon:SetTexture(spec.icon)
    end

    -- Resolve the loot table + bonusId based on the active view.
    -- Dungeons: bonusId comes from the M+ keystone level, applied via BuildItemLink.
    -- Raids:    each item has its own per-difficulty link captured at scrape time;
    --           bonusId is unused (handled per-item via linkFor below).
    local lootTable, bonusId
    if viewMode == "dungeon" then
        local dungeonData = dungeons[currentDungeonIndex]
        _, bonusId = GetEndOfRunInfo(selectedKeystoneLevel)
        lootTable = addonTable.Scraper:GetDungeonLootTable(dungeonData.journalInstanceId)
    else
        lootTable = {}
        if currentBossEncID and SpecLootDB and SpecLootDB.raids then
            for _, raid in ipairs(raids) do
                local instance = SpecLootDB.raids[raid.journalInstanceId]
                if instance and instance.encounters and instance.encounters[currentBossEncID] then
                    lootTable = instance.encounters[currentBossEncID].items or {}
                    break
                end
            end
        end
    end

    local sharedItems = {}
    local specItems = {}
    for i = 1, numSpecs do specItems[i] = {} end

    for _, itemID in ipairs(lootTable) do
        local itemData = GetItemData(itemID)
        if not itemData or itemData.slotId == 14 then
            -- skip mounts/decor or items the scraper hasn't resolved yet
        else
            local dropsFor = {}
            for si, spec in ipairs(specs) do
                if DoesItemDropForSpec(itemID, classID, spec.id) then
                    dropsFor[#dropsFor + 1] = si
                end
            end

            if #dropsFor == numSpecs then
                sharedItems[#sharedItems + 1] = itemID
            elseif #dropsFor > 0 then
                for _, si in ipairs(dropsFor) do
                    specItems[si][#specItems[si] + 1] = itemID
                end
            end
        end
    end

    table.sort(sharedItems, SortBySlotId)
    for i = 1, numSpecs do
        table.sort(specItems[i], SortBySlotId)
    end

    -- ==========================================
    -- BEGIN NEW DYNAMIC DISTRIBUTION LOGIC
    -- ==========================================
    
    local totalShared = #sharedItems
    -- Figure out the minimum columns needed (still assuming a ~5 item soft cap per column)
    local numCols = math.max(1, math.ceil(totalShared / 5))

    -- Distribute the items evenly across those columns
    local sharedItemsPerCol = totalShared > 0 and math.ceil(totalShared / numCols) or 1

    -- Calculate height based on the actual number of rows we'll use
    local dynamicHeight = math.max(150, 40 + (sharedItemsPerCol * 22))
    sharedFrame:SetHeight(dynamicHeight)

    -- Shift the main frame height to accommodate
    local mainHeight = 365 + dynamicHeight
    mainFrame:SetHeight(mainHeight)

    -- ==========================================
    -- END NEW DYNAMIC DISTRIBUTION LOGIC
    -- ==========================================

    -- For raid mode, prefer the per-(item, difficulty) link captured by the
    -- scraper so each item's tooltip shows its actual ilvl at that difficulty.
    -- Dungeons keep using bonusId (varies by keystone level).
    local function linkFor(itemID)
        if viewMode ~= "raid" then return nil end
        local d = GetItemData(itemID)
        return d and d.links and d.links[selectedRaidDifficulty]
    end

    for i, itemID in ipairs(sharedItems) do
        AddItemToPool(sharedDisplayFrames, sharedFrame, i, itemID, bonusId, linkFor(itemID), false, sharedItemsPerCol)
    end

    for si = 1, numSpecs do
        for i, itemID in ipairs(specItems[si]) do
            AddItemToPool(specDisplayFrames[si], specFrames[si], i, itemID, bonusId, linkFor(itemID), true)
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