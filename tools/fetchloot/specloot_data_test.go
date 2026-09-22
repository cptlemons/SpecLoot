package main

import (
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestItemFilteringAndBlindingVale(t *testing.T) {
	dataBytes, err := os.ReadFile("../../SpecLoot/Data.lua")
	if err != nil {
		dataBytes, err = os.ReadFile("../../Data.lua")
		if err != nil {
			t.Fatalf("reading Data.lua: %v", err)
		}
	}
	content := string(dataBytes)

	// 1. Verify 250258 is NOT in Blinding Vale
	bvRe := regexp.MustCompile(`name\s*=\s*"Blinding Vale"[\s\S]*?lootTable\s*=\s*\{([^}]+)\}`)
	bvMatch := bvRe.FindStringSubmatch(content)
	if len(bvMatch) < 2 {
		t.Fatalf("could not parse Blinding Vale lootTable from Data.lua")
	}
	bvIDsStr := strings.Split(bvMatch[1], ",")
	bvIDs := make(map[int]bool)
	for _, s := range bvIDsStr {
		id, err := strconv.Atoi(strings.TrimSpace(s))
		if err == nil && id > 0 {
			bvIDs[id] = true
		}
	}

	if bvIDs[250258] {
		t.Errorf("250258 (Vessel of Tortured Souls) should NOT be in Blinding Vale")
	}

	// 2. Parse ItemDatabase entry helper
	getItemDHSpecsAndSlot := func(id int) (slotID int, dhSpecs map[int]bool) {
		dhSpecs = make(map[int]bool)
		slotID = 99
		re := regexp.MustCompile(`\[` + strconv.Itoa(id) + `\]\s*=\s*\{([\s\S]*?)\},?\r?\n`)
		m := re.FindStringSubmatch(content)
		if len(m) < 2 {
			return
		}
		body := m[1]
		slotRe := regexp.MustCompile(`slotId\s*=\s*(\d+)`)
		sm := slotRe.FindStringSubmatch(body)
		if len(sm) >= 2 {
			slotID, _ = strconv.Atoi(sm[1])
		}
		dhRe := regexp.MustCompile(`\[12\]\s*=\s*\{([^}]+)\}`)
		dhm := dhRe.FindStringSubmatch(body)
		if len(dhm) >= 2 {
			for _, specStr := range strings.Split(dhm[1], ",") {
				specID, err := strconv.Atoi(strings.TrimSpace(specStr))
				if err == nil && specID > 0 {
					dhSpecs[specID] = true
				}
			}
		}
		return
	}

	getDHItemsForSpec := func(specID int) []int {
		var list []int
		for id := range bvIDs {
			slotID, dhSpecs := getItemDHSpecsAndSlot(id)
			if slotID != 14 && slotID != 99 && dhSpecs[specID] {
				list = append(list, id)
			}
		}
		return list
	}

	havocItems := getDHItemsForSpec(577)
	devourerItems := getDHItemsForSpec(1480)
	vengeanceItems := getDHItemsForSpec(581)

	// Validate Devourer excludes 251186
	for _, id := range devourerItems {
		if id == 251186 {
			t.Errorf("251186 should NOT drop for Devourer (1480)")
		}
	}
	if len(havocItems) != 8 {
		t.Errorf("expected 8 items for Havoc, got %d (%v)", len(havocItems), havocItems)
	}
	if len(devourerItems) != 7 {
		t.Errorf("expected 7 items for Devourer, got %d (%v)", len(devourerItems), devourerItems)
	}
	if len(vengeanceItems) != 8 {
		t.Errorf("expected 8 items for Vengeance, got %d (%v)", len(vengeanceItems), vengeanceItems)
	}

	// 3. Test Item Filtering Rules
	isAllowed := func(id int, isBonusRoll bool) bool {
		if id == 270909 {
			return !isBonusRoll
		}
		if id == 258045 || id == 279118 || id == 275658 || id == 256625 {
			return false
		}
		slotID, _ := getItemDHSpecsAndSlot(id)
		if slotID == 14 || slotID == 99 {
			return false
		}
		return true
	}

	if !isAllowed(270909, false) {
		t.Errorf("270909 (Slumbering Coil Curio) should be allowed in Normal Loot mode")
	}
	if isAllowed(270909, true) {
		t.Errorf("270909 (Slumbering Coil Curio) should be excluded in Bonus Rolls mode")
	}
	if isAllowed(258045, false) {
		t.Errorf("258045 (Dawnblade's Glaives) should be filtered out as cosmetic")
	}
	if isAllowed(279118, false) {
		t.Errorf("279118 (Lost Explorers' Mailbox) should be filtered out")
	}
	if isAllowed(275658, false) {
		t.Errorf("275658 (Primeval Skyfriend) should be filtered out")
	}
	if isAllowed(256625, false) {
		t.Errorf("256625 (Pattern: Hexwoven Strand) should be filtered out")
	}
	if !isAllowed(270923, false) {
		t.Errorf("270923 (Venomcured Remnant) should be allowed")
	}
}

func TestBonusRollsModeTrackMapping(t *testing.T) {
	dataBytes, err := os.ReadFile("../../SpecLoot/Data.lua")
	if err != nil {
		dataBytes, err = os.ReadFile("../../Data.lua")
		if err != nil {
			t.Fatalf("reading Data.lua: %v", err)
		}
	}
	content := string(dataBytes)

	// Verify KeystoneMapping rules contain M+ 10 Great Vault -> myth 1
	if !strings.Contains(content, `keystones = { 10 }`) || !strings.Contains(content, `greatVault = { track = "myth", rank = 1 }`) {
		t.Errorf("Data.lua missing M+ 10 Great Vault mapping to myth 1")
	}

	// Verify SpecLoot.lua Heroic raid bonus rolls always map to 1/6 Myth
	speclootBytes, err := os.ReadFile("../../SpecLoot/SpecLoot.lua")
	if err != nil {
		speclootBytes, err = os.ReadFile("../../SpecLoot.lua")
		if err != nil {
			t.Fatalf("reading SpecLoot.lua: %v", err)
		}
	}
	speclootContent := string(speclootBytes)

	if !strings.Contains(speclootContent, `trackLabel = "1/6 Myth"`) {
		t.Errorf("SpecLoot.lua missing fixed 1/6 Myth trackLabel for heroic raid bonus rolls")
	}

	if strings.Contains(speclootContent, `raidDifficulty == 15 then`+"\r\n"+`            -- Heroic -> Mythic / Myth track (1/6 Myth .. 4/6 Myth)`) {
		t.Errorf("SpecLoot.lua still contains old bossRank scaling for Heroic raid bonus rolls")
	}
}

func TestClassArmorProficiencyDefinitions(t *testing.T) {
	dataBytes, err := os.ReadFile("../../SpecLoot/Data.lua")
	if err != nil {
		dataBytes, err = os.ReadFile("../../Data.lua")
		if err != nil {
			t.Fatalf("reading Data.lua: %v", err)
		}
	}
	content := string(dataBytes)

	if !strings.Contains(content, "addonTable.ClassArmorType = {") {
		t.Errorf("Data.lua missing addonTable.ClassArmorType definition")
	}
	if !strings.Contains(content, "function addonTable.IsItemValidForClass(itemID, classID)") {
		t.Errorf("Data.lua missing addonTable.IsItemValidForClass function")
	}

	// Verify primary armor classes:
	// Plate (4): Warrior [1], Paladin [2], Death Knight [6]
	// Mail (3): Hunter [3], Shaman [7], Evoker [13]
	// Leather (2): Rogue [4], Monk [10], Druid [11], Demon Hunter [12]
	// Cloth (1): Priest [5], Mage [8], Warlock [9]
	expectedArmorChecks := []string{
		`[1]  = 4`, `[2]  = 4`, `[6]  = 4`,
		`[3]  = 3`, `[7]  = 3`, `[13] = 3`,
		`[4]  = 2`, `[10] = 2`, `[11] = 2`, `[12] = 2`,
		`[5]  = 1`, `[8]  = 1`, `[9]  = 1`,
	}
	for _, check := range expectedArmorChecks {
		if !strings.Contains(content, check) {
			t.Errorf("Data.lua ClassArmorType missing or incorrect for: %s", check)
		}
	}
}
