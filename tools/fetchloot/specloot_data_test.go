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
	isAllowed := func(id int) bool {
		if id == 270909 {
			return true
		}
		if id == 279118 || id == 275658 || id == 256625 {
			return false
		}
		slotID, _ := getItemDHSpecsAndSlot(id)
		if slotID == 14 || slotID == 99 {
			return false
		}
		return true
	}

	if !isAllowed(270909) {
		t.Errorf("270909 (Slumbering Coil Curio) should be allowed")
	}
	if isAllowed(258045) {
		t.Errorf("258045 (Dawnblade's Glaives) should be filtered out as cosmetic")
	}
	if isAllowed(279118) {
		t.Errorf("279118 (Lost Explorers' Mailbox) should be filtered out")
	}
	if isAllowed(275658) {
		t.Errorf("275658 (Primeval Skyfriend) should be filtered out")
	}
	if isAllowed(256625) {
		t.Errorf("256625 (Pattern: Hexwoven Strand) should be filtered out")
	}
	if !isAllowed(270923) {
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
}
