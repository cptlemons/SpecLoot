local addonName, addonTable = ...

local Scraper = {}
addonTable.Scraper = Scraper

-- Bump this to force a full re-scrape on next login (e.g. after content patches).
local SCRAPE_VERSION = 13

-- Blizzard_EncounterJournal is load-on-demand. Until it's been initialized, the
-- EJ_* APIs only return items the player has personally encountered, not the
-- full journal entries we want. Always force-load before scraping/probing.
-- Also clear the class/spec loot filter — once the journal is open it remembers
-- the last filter the player used (often their current spec), and EJ_GetNumLoot
-- silently honors it. EJ_ResetLootFilter alone has been observed to leave the
-- class/spec filter applied, so we explicitly set it to (0, 0) too.
local function ClearLootFilter()
    if EJ_ResetLootFilter then EJ_ResetLootFilter() end
    if EJ_SetLootFilter then EJ_SetLootFilter(0, 0) end
end

local function RestoreCurrentLootFilter()
    local specIndex = GetSpecialization and GetSpecialization()
    local specID = specIndex and GetSpecializationInfo and GetSpecializationInfo(specIndex) or 0
    local _, _, classID = UnitClass("player")
    if EJ_SetLootFilter and classID then
        EJ_SetLootFilter(classID, specID)
    end
end

local function EnsureEJReady()
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
        LoadAddOn("Blizzard_EncounterJournal")
    end
    ClearLootFilter()
end

local oldEJOnEvent
local function SuppressEJUI()
    if EncounterJournal and not oldEJOnEvent then
        oldEJOnEvent = EncounterJournal:GetScript("OnEvent")
        if oldEJOnEvent then
            EncounterJournal:SetScript("OnEvent", nil)
        end
    end
end

local function RestoreEJUI()
    if EncounterJournal and oldEJOnEvent then
        EncounterJournal:SetScript("OnEvent", oldEJOnEvent)
        oldEJOnEvent = nil
    end
end

local instanceToTier = {}
local function SelectInstanceSafely(instanceID)
    if not next(instanceToTier) then
        local numTiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
        for t = 1, numTiers do
            if EJ_SelectTier then EJ_SelectTier(t) end
            local i = 1
            while true do
                local id = EJ_GetInstanceByIndex(i, false)
                if not id then break end
                instanceToTier[id] = t
                i = i + 1
            end
            i = 1
            while true do
                local id = EJ_GetInstanceByIndex(i, true)
                if not id then break end
                instanceToTier[id] = t
                i = i + 1
            end
        end
    end
    local tier = instanceToTier[instanceID]
    if tier and EJ_SelectTier then
        EJ_SelectTier(tier)
    end
    EJ_SelectInstance(instanceID)
end

-- Blizzard difficulty IDs. Modern retail merged "5-player Mythic" and "Mythic+
-- Keystone" filtering under difficulty 23 in the Encounter Journal. The legacy
-- value 8 (Challenge Mode) returns zero loot in current builds.
local DIFF_DUNGEON_MYTHIC = 23
local DIFF_RAID_LFR       = 17
local DIFF_RAID_NORMAL    = 14
local DIFF_RAID_HEROIC    = 15
local DIFF_RAID_MYTHIC    = 16

local RAID_DIFFICULTIES = {
    { id = DIFF_RAID_LFR,    key = "lfr"    },
    { id = DIFF_RAID_NORMAL, key = "normal" },
    { id = DIFF_RAID_HEROIC, key = "heroic" },
    { id = DIFF_RAID_MYTHIC, key = "mythic" },
}

-- Map Blizzard's INVTYPE_* equip-loc strings to the addon's 0-13 slot scheme.
local INVTYPE_TO_SLOTID = {
    INVTYPE_HEAD            = 0,
    INVTYPE_NECK            = 1,
    INVTYPE_SHOULDER        = 2,
    INVTYPE_CLOAK           = 3,
    INVTYPE_CHEST           = 4,
    INVTYPE_ROBE            = 4,
    INVTYPE_WRIST           = 5,
    INVTYPE_HAND            = 6,
    INVTYPE_WAIST           = 7,
    INVTYPE_LEGS            = 8,
    INVTYPE_FEET            = 9,
    INVTYPE_WEAPON          = 10,
    INVTYPE_2HWEAPON        = 10,
    INVTYPE_WEAPONMAINHAND  = 10,
    INVTYPE_RANGED          = 10,
    INVTYPE_RANGEDRIGHT     = 10,
    INVTYPE_THROWN          = 10,
    INVTYPE_WEAPONOFFHAND   = 11,
    INVTYPE_SHIELD          = 11,
    INVTYPE_HOLDABLE        = 11,
    INVTYPE_FINGER          = 12,
    INVTYPE_TRINKET         = 13,
}

local function GetSlotId(itemID)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return nil end
    return INVTYPE_TO_SLOTID[equipLoc]
end

-- C_Item.GetItemSpecInfo returns a flat array of spec IDs (e.g. { 1480, 581, 577 }).
-- We need a specID -> classID reverse lookup off ClassInfo to repack into the
-- addon's existing { [classID] = { specID, ... } } shape so the UI can keep its
-- existing lookup logic unchanged.
local SPEC_TO_CLASS
local function BuildSpecToClass()
    SPEC_TO_CLASS = {}
    for classID, info in pairs(addonTable.ClassInfo or {}) do
        for _, spec in ipairs(info.specs or {}) do
            SPEC_TO_CLASS[spec.id] = classID
        end
    end
end

local function PackSpecsByClass(specs)
    if not SPEC_TO_CLASS then BuildSpecToClass() end
    local byClass = {}
    if specs then
        for _, specID in ipairs(specs) do
            local classID = SPEC_TO_CLASS[specID]
            if classID then
                byClass[classID] = byClass[classID] or {}
                table.insert(byClass[classID], specID)
            end
        end
    end
    return byClass
end

-- Phase 1: enumerate loot. EJ_GetNumLoot after just EJ_SelectInstance returns counts
-- for whichever encounter was last selected (often nothing or one item), so we must
-- iterate every encounter explicitly: select it, then ask for loot at the chosen
-- difficulty.
-- `buf` is an optional table; lines are appended to it for later display in the
-- copyable popup. Pass nil for no diagnostic output.
local function EnumerateLoot(instanceID, difficultyID, instanceBucket, itemSeen, itemLinks, buf, label)
    ClearLootFilter()
    SelectInstanceSafely(instanceID)
    EJ_SetDifficulty(difficultyID) -- pre-set so encounter discovery uses this filter

    local total = 0
    local encIndex = 1
    while true do
        local encInfo = { EJ_GetEncounterInfoByIndex(encIndex) }
        local encName, encID = encInfo[1], encInfo[3]
        if not encID then break end

        -- IMPORTANT: EJ_SelectEncounter resets the difficulty filter to the
        -- journal's default (typically Normal). Re-apply it before reading loot.
        -- Also re-clear the class/spec filter, which various journal interactions
        -- can implicitly set — including just opening the journal in-game.
        EJ_SelectEncounter(encID)
        EJ_SetDifficulty(difficultyID)
        ClearLootFilter()
        local count = EJ_GetNumLoot() or 0

        instanceBucket.encounters[encID] = instanceBucket.encounters[encID] or {
            name = encName, items = {}, _seen = {}, index = encIndex
        }
        local enc = instanceBucket.encounters[encID]

        local addedThisEncounter = 0
        local sampleIDs = {}
        for i = 1, count do
            local info = C_EncounterJournal.GetLootInfoByIndex(i)
            if info and info.itemID and info.itemID > 0 then
                if not enc._seen[info.itemID] then
                    enc._seen[info.itemID] = true
                    table.insert(enc.items, info.itemID)
                    addedThisEncounter = addedThisEncounter + 1
                    if #sampleIDs < 5 then
                        table.insert(sampleIDs, tostring(info.itemID))
                    end
                end
                -- info.icon may be nil for some entries; never write nil here, or
                -- Lua's `t[k] = nil` semantics would *delete* the entry from itemSeen.
                itemSeen[info.itemID] = info.icon or 134400 -- 134400 = inv_misc_questionmark

                -- info.link is the journal's pre-scaled item link for the current
                -- difficulty (encodes the appropriate bonus IDs). Save it per
                -- (itemID, difficultyID) so the tooltip shows the correct ilvl
                -- for each item at each raid difficulty.
                if itemLinks and info.link then
                    itemLinks[info.itemID] = itemLinks[info.itemID] or {}
                    itemLinks[info.itemID][difficultyID] = info.link
                end
            end
        end
        total = total + addedThisEncounter

        if buf then
            table.insert(buf, string.format("    %s [enc=%d %s] diff=%d -> %d new (count=%d)  sample: %s",
                label or "?", encID, encName or "?", difficultyID,
                addedThisEncounter, count, table.concat(sampleIDs, ", ")))
        end

        encIndex = encIndex + 1
    end
    return total
end

-- Phase 2: enrich the item cache for every itemID we collected. Items not yet loaded
-- are queued and resolved when GET_ITEM_INFO_RECEIVED fires.
local pendingItems
local function ResolveItem(itemID, fallbackIcon, itemCache)
    local slotId = GetSlotId(itemID)
    if not slotId then
        return false -- item not yet loaded; try again later
    end
    -- C_Item.GetItemIconByID is the proper item icon; the journal's info.icon is
    -- often stale or nil. Fall back through three layers so we never end up with
    -- a blank texture.
    local icon = C_Item.GetItemIconByID(itemID) or fallbackIcon or 134400
    -- GetItemSpecInfo only returns the player's own class' specs. Cross-class
    -- spec data is filled in by ClassifyItemsBySpec; we still call this so
    -- player-class data is available immediately, before Phase 3 runs.
    local specs = C_Item.GetItemSpecInfo(itemID)
    itemCache[itemID] = {
        slotId  = slotId,
        icon    = icon,
        classes = PackSpecsByClass(specs),
    }
    return true
end

local function StripSeenSets(byInstance)
    for _, inst in pairs(byInstance) do
        for _, enc in pairs(inst.encounters) do
            enc._seen = nil
        end
    end
end

-- Phase 3: per-class spec data.
-- C_Item.GetItemSpecInfo only returns specs of the player's own class, so the
-- cache is missing class info for every other class after Phases 1-2. We lean on
-- the Encounter Journal's spec filter: setting EJ_SetLootFilter(classID, specID)
-- makes EJ_GetNumLoot return only items that drop for that spec. We do this
-- ONE CLASS AT A TIME — initial scrape covers just the player's class, and
-- other classes are classified lazily when the user picks them in the dropdown.
local function ClassifyOneClass(results, classID, buf)
    local classInfo = addonTable.ClassInfo and addonTable.ClassInfo[classID]
    if not classInfo then return end

    local function recordSpec(itemID, specID)
        local itemData = results.itemCache and results.itemCache[itemID]
        if not itemData then return end
        itemData.classes = itemData.classes or {}
        itemData.classes[classID] = itemData.classes[classID] or {}
        for _, sid in ipairs(itemData.classes[classID]) do
            if sid == specID then return end -- already recorded
        end
        table.insert(itemData.classes[classID], specID)
    end

    local function walkInstance(journalID, encounters, difficultyID, specID)
        SelectInstanceSafely(journalID)
        for encID in pairs(encounters) do
            EJ_SelectEncounter(encID)
            EJ_SetDifficulty(difficultyID)
            EJ_SetLootFilter(classID, specID)
            local count = EJ_GetNumLoot() or 0
            for i = 1, count do
                local lootInfo = C_EncounterJournal.GetLootInfoByIndex(i)
                if lootInfo and lootInfo.itemID and lootInfo.itemID > 0 then
                    recordSpec(lootInfo.itemID, specID)
                end
            end
        end
    end

    for _, spec in ipairs(classInfo.specs or {}) do
        EJ_SetLootFilter(classID, spec.id)
        for journalID, bucket in pairs(results.dungeons or {}) do
            walkInstance(journalID, bucket.encounters, DIFF_DUNGEON_MYTHIC, spec.id)
        end
        for journalID, bucket in pairs(results.raids or {}) do
            for _, diff in ipairs(RAID_DIFFICULTIES) do
                walkInstance(journalID, bucket.encounters, diff.id, spec.id)
            end
        end
        if buf then
            local hits = 0
            for _, itemData in pairs(results.itemCache or {}) do
                local cspecs = itemData.classes and itemData.classes[classID]
                if cspecs then
                    for _, sid in ipairs(cspecs) do
                        if sid == spec.id then hits = hits + 1; break end
                    end
                end
            end
            table.insert(buf, string.format("    classify [class=%d spec=%d %s]: %d items",
                classID, spec.id, spec.name, hits))
        end
    end

    results.classifiedClasses = results.classifiedClasses or {}
    results.classifiedClasses[classID] = true
    RestoreCurrentLootFilter()
end

-- Public: ensure the spec data for `classID` has been built. No-op if already
-- classified. Called by the UI from OnShow and from the class dropdown.
--
-- Runs deferred via C_Timer.After(0) — running the filter walk synchronously
-- right after a heavy Phase 1 (which iterates ~20 instance/difficulty combos)
-- causes EJ_SetLootFilter to silently no-op on EJ_GetNumLoot, which would
-- attribute every item to every spec of the player's class and flood the
-- loot panels with the wrong items. A single-frame delay lets the journal
-- settle, and the filter then applies as expected.
function Scraper:EnsureClassClassified(classID)
    if not SpecLootDB or not SpecLootDB.itemCache then return false end
    SpecLootDB.classifiedClasses = SpecLootDB.classifiedClasses or {}
    if SpecLootDB.classifiedClasses[classID] then
        return false -- already classified or in-flight
    end

    -- Mark up-front so re-entrant calls don't queue duplicate work.
    SpecLootDB.classifiedClasses[classID] = true

    C_Timer.After(0, function()
        EnsureEJReady()
        SuppressEJUI()
        ClassifyOneClass(SpecLootDB, classID, nil)
        RestoreEJUI()
        -- Notify the UI so the freshly-classified data gets rendered.
        if type(addonTable.OnScrapeComplete) == "function" then
            pcall(addonTable.OnScrapeComplete)
        end
    end)
    return true
end

function Scraper:IsCacheFresh()
    return SpecLootDB
        and SpecLootDB.scrapeVersion == SCRAPE_VERSION
        and SpecLootDB.dungeons
        and SpecLootDB.raids
end

-- Public entrypoint. Runs the full scrape and stores everything in SpecLootDB.
-- Returns immediately; phase-2 enrichment runs asynchronously as item data arrives.
function Scraper:Scrape(verbose)
    EnsureEJReady()
    SuppressEJUI()

    local results = {
        scrapeVersion = SCRAPE_VERSION,
        scrapedAt     = time(),
        dungeons      = {},
        raids         = {},
        itemCache     = {},
    }

    local itemSeen  = {} -- itemID -> icon from journal
    local itemLinks = {} -- itemID -> { [difficultyID] = link }
    local buf = verbose and {} or nil

    if buf then
        table.insert(buf, string.format("=== SpecLoot scrape (verbose) — %s ===",
            date("%Y-%m-%d %H:%M:%S")))
    end

    for _, dungeon in ipairs(addonTable.DungeonDatabase or {}) do
        if dungeon.journalInstanceId then
            local bucket = { encounters = {} }
            local n = EnumerateLoot(dungeon.journalInstanceId, DIFF_DUNGEON_MYTHIC, bucket, itemSeen, itemLinks,
                buf, dungeon.name)
            if buf then
                table.insert(buf, string.format("  dungeon %s (id=%d): %d items total",
                    dungeon.name, dungeon.journalInstanceId, n))
            end
            results.dungeons[dungeon.journalInstanceId] = bucket
        end
    end

    for _, raid in ipairs(addonTable.RaidDatabase or {}) do
        if raid.journalInstanceId then
            local bucket = { encounters = {} }
            local n = 0
            for _, diff in ipairs(RAID_DIFFICULTIES) do
                n = n + EnumerateLoot(raid.journalInstanceId, diff.id, bucket, itemSeen, itemLinks,
                    buf, raid.name .. " " .. diff.key)
            end
            -- After loot enumeration, fill in each encounter's first-creature
            -- display ID so the UI can render boss portrait tiles.
            -- EJ_GetCreatureInfo's return-tuple shape has shifted across patches
            -- (it sometimes leads with name/description strings), so we scan every
            -- return value and pick the first plausibly-sized number — display IDs
            -- are >100000, which excludes IDs of encounters/icons/etc.
            SelectInstanceSafely(raid.journalInstanceId)
            for encID, enc in pairs(bucket.encounters) do
                EJ_SelectEncounter(encID)
                local returns = { EJ_GetCreatureInfo(1, encID) }
                for _, v in ipairs(returns) do
                    if type(v) == "number" and v > 100000 then
                        enc.creatureDisplayID = v
                        break
                    end
                end
            end
            if buf then
                table.insert(buf, string.format("  raid %s (id=%d): %d items total",
                    raid.name, raid.journalInstanceId, n))
            end
            results.raids[raid.journalInstanceId] = bucket
        end
    end

    StripSeenSets(results.dungeons)
    StripSeenSets(results.raids)

    -- Resolve as many items as we can synchronously; queue the rest.
    pendingItems = {}
    local resolved, total = 0, 0
    for itemID, icon in pairs(itemSeen) do
        total = total + 1
        if ResolveItem(itemID, icon, results.itemCache) then
            resolved = resolved + 1
        else
            pendingItems[itemID] = icon
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end

    -- Attach the per-difficulty journal links to each cache entry so tooltips
    -- can render the correct ilvl per (item, difficulty) without recomputing.
    for itemID, linksByDiff in pairs(itemLinks) do
        if results.itemCache[itemID] then
            results.itemCache[itemID].links = linksByDiff
        end
    end

    SpecLootDB = results

    -- Let the UI know fresh data has landed (e.g. so the Raids view can build
    -- its boss tiles now that SpecLootDB.raids is populated).
    if type(addonTable.OnScrapeComplete) == "function" then
        pcall(addonTable.OnScrapeComplete)
    end

    -- NOTE: Phase 3 (per-class classify) intentionally does NOT run here.
    -- When ClassifyOneClass executes immediately after Phase 1, EJ_SetLootFilter
    -- doesn't always take effect on the very next EJ_GetNumLoot — the journal
    -- needs time to settle after the heavy Phase 1 walk. The filter then silently
    -- no-ops, attributing every item to every player-class spec and flooding
    -- the player's loot panels with wrong items.
    --
    -- Instead, every class (including the player's) is classified lazily by
    -- Scraper:EnsureClassClassified, called from OnShow and from the class
    -- dropdown. By that point the journal is stable and filters work.
    if buf then
        table.insert(buf, "")
        table.insert(buf, "=== Phase 3 deferred to lazy EnsureClassClassified ===")
    end

    local pendingCount = 0
    for _ in pairs(pendingItems) do pendingCount = pendingCount + 1 end
    local summary = string.format("scrape complete: %d items resolved, %d pending (%d total)",
        resolved, pendingCount, total)
    print("|cffa335eeSpecLoot|r " .. summary)

    if buf then
        table.insert(buf, "")
        table.insert(buf, summary)
        addonTable.Output:Show("Scrape Debug", table.concat(buf, "\n"))
    end
    RestoreCurrentLootFilter()
    RestoreEJUI()
    return true
end

-- Drains the pending-item queue as GET_ITEM_INFO_RECEIVED events arrive.
function Scraper:OnItemInfoReceived(itemID)
    if not pendingItems then return end
    local icon = pendingItems[itemID]
    if icon == nil then return end
    if SpecLootDB and ResolveItem(itemID, icon, SpecLootDB.itemCache) then
        pendingItems[itemID] = nil
    end
end

-- Probe runs every plausible difficulty ID against one (instance, encounter) pair
-- and reports how many loot items each returns. Use this to figure out which
-- difficulty constant actually corresponds to the current-season rotation.
function Scraper:Probe(instanceID, encounterID)
    EnsureEJReady()
    SuppressEJUI()
    SelectInstanceSafely(instanceID)
    EJ_SelectEncounter(encounterID)
    local lines = {}
    table.insert(lines, string.format("probe: instance=%d encounter=%d", instanceID, encounterID))
    table.insert(lines, "")
    local difficulties = {
        { 1,  "Dungeon Normal" },
        { 2,  "Dungeon Heroic" },
        { 8,  "Dungeon Challenge / M+ keystone (legacy)" },
        { 23, "Dungeon Mythic" },
        { 14, "Raid Normal" },
        { 15, "Raid Heroic" },
        { 16, "Raid Mythic" },
        { 17, "Raid LFR" },
    }
    for _, d in ipairs(difficulties) do
        EJ_SetDifficulty(d[1])
        local count = EJ_GetNumLoot() or 0
        local sample = {}
        for i = 1, math.min(count, 6) do
            local info = C_EncounterJournal.GetLootInfoByIndex(i)
            if info and info.itemID then
                table.insert(sample, tostring(info.itemID))
            end
        end
        table.insert(lines, string.format("  diff=%-3d (%-40s): %d items   sample: %s",
            d[1], d[2], count, table.concat(sample, ", ")))
    end
    RestoreEJUI()
    addonTable.Output:Show("Probe", table.concat(lines, "\n"))
end

-- Flatten an instance's per-encounter item lists into a single deduped itemID array.
local function flattenLootTable(instance)
    if not instance or not instance.encounters then return {} end
    local seen, result = {}, {}
    for _, enc in pairs(instance.encounters) do
        for _, itemID in ipairs(enc.items or {}) do
            if not seen[itemID] then
                seen[itemID] = true
                table.insert(result, itemID)
            end
        end
    end
    return result
end

-- Returns a flat array of itemIDs for the dungeon (M+ rotation) at this journal-instance ID,
-- deduped across encounters. Empty table if the cache hasn't been built yet.
function Scraper:GetDungeonLootTable(journalInstanceID)
    if not SpecLootDB or not SpecLootDB.dungeons then return {} end
    return flattenLootTable(SpecLootDB.dungeons[journalInstanceID])
end

-- Same for raids — the table unions items across all four raid difficulties.
function Scraper:GetRaidLootTable(journalInstanceID)
    if not SpecLootDB or not SpecLootDB.raids then return {} end
    return flattenLootTable(SpecLootDB.raids[journalInstanceID])
end

-- Returns an ordered list of encounters for a raid, in journal display order.
-- Each entry: { id, name, creatureDisplayID, items = {...} }.
function Scraper:GetRaidEncounters(journalInstanceID)
    if not SpecLootDB or not SpecLootDB.raids then return {} end
    local instance = SpecLootDB.raids[journalInstanceID]
    if not instance or not instance.encounters then return {} end
    local list = {}
    for encID, enc in pairs(instance.encounters) do
        list[#list + 1] = {
            id = encID,
            name = enc.name,
            creatureDisplayID = enc.creatureDisplayID,
            items = enc.items,
            index = enc.index,
        }
    end
    table.sort(list, function(a, b) return (a.index or 9999) < (b.index or 9999) end)
    return list
end

-- Item metadata: { slotId, icon, classes = { [classID] = { specID, ... } } } or nil.
function Scraper:GetItemData(itemID)
    if not SpecLootDB or not SpecLootDB.itemCache then return nil end
    return SpecLootDB.itemCache[itemID]
end

function Scraper:GetSummary()
    if not SpecLootDB then return "no scrape on record" end
    local d, r, items = 0, 0, 0
    for _ in pairs(SpecLootDB.dungeons or {}) do d = d + 1 end
    for _ in pairs(SpecLootDB.raids    or {}) do r = r + 1 end
    for _ in pairs(SpecLootDB.itemCache or {}) do items = items + 1 end
    return string.format("v%d, scraped %s — %d dungeons, %d raids, %d items",
        SpecLootDB.scrapeVersion or 0,
        date("%Y-%m-%d %H:%M", SpecLootDB.scrapedAt or 0),
        d, r, items)
end
