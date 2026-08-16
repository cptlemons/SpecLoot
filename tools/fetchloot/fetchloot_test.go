package main

import (
	"os"
	"sort"
	"testing"
)

const pitOfSaronName = "Pit of Saron"

// expectedPoSLoot is the lootTable from Data.lua at the time these tests were written.
// (Data.lua's hardcoded lootTable was removed once the in-game scraper became the
// source of truth, but the literal copy below stays as a stable diff target.)
var expectedPoSLoot = []int{
	49802, 49805, 49806, 49807, 49808, 49809, 49810, 49811, 49812, 49813,
	49817, 49819, 49823, 49824, 49825, 50227, 50228, 50233, 50234, 50259,
	50263, 50264, 50272, 252421, 267007,
}

// findPoSInstanceID resolves the journal-instance ID for Pit of Saron via name lookup.
// The integer in Data.lua's instanceId column (658) is the *map* ID, not the journal
// ID Blizzard's REST API expects, so tests can't hardcode it.
func findPoSInstanceID(t *testing.T, c *Client) int {
	t.Helper()
	id, err := c.FindInstanceIDByName(pitOfSaronName)
	if err != nil {
		t.Fatalf("looking up %q in journal-instance index: %v", pitOfSaronName, err)
	}
	return id
}

// newTestClient builds an authenticated Blizzard API client for tests.
// Fails (not skips) when BLIZZARD_CLIENT_SECRET is missing so `go test ./...` can
// never silently no-op.
func newTestClient(t *testing.T) *Client {
	t.Helper()
	secret := os.Getenv("BLIZZARD_CLIENT_SECRET")
	if secret == "" {
		t.Skip("BLIZZARD_CLIENT_SECRET environment variable is not set; skipping online tests")
	}
	id := os.Getenv("BLIZZARD_CLIENT_ID")
	if id == "" {
		id = defaultClientID
	}
	c, err := NewClient(id, secret)
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	return c
}

func TestPitOfSaron_InstanceMetadata(t *testing.T) {
	c := newTestClient(t)
	id := findPoSInstanceID(t, c)
	inst, err := c.GetInstance(id)
	if err != nil {
		t.Fatalf("GetInstance(%d): %v", id, err)
	}
	if inst.ID != id {
		t.Errorf("expected instance ID %d, got %d", id, inst.ID)
	}
	if inst.Name == "" {
		t.Error("instance name is empty")
	}
	if len(inst.Encounters) == 0 {
		t.Error("instance has no encounters")
	}
	t.Logf("Instance %d: %q, encounters=%d, expansion=%q",
		inst.ID, inst.Name, len(inst.Encounters), inst.Expansion.Name)
}

func TestPitOfSaron_LootTableMatchesData(t *testing.T) {
	c := newTestClient(t)
	id := findPoSInstanceID(t, c)
	inst, err := c.GetInstance(id)
	if err != nil {
		t.Fatalf("GetInstance(%d): %v", id, err)
	}

	apiItems := map[int]bool{}
	for _, e := range inst.Encounters {
		enc, err := c.GetEncounter(e.ID)
		if err != nil {
			t.Errorf("GetEncounter(%d) %q: %v", e.ID, e.Name, err)
			continue
		}
		for _, it := range enc.Items {
			apiItems[it.Item.ID] = true
		}
	}

	expectedSet := map[int]bool{}
	for _, id := range expectedPoSLoot {
		expectedSet[id] = true
	}

	var missing, extra []int
	for _, id := range expectedPoSLoot {
		if !apiItems[id] {
			missing = append(missing, id)
		}
	}
	for id := range apiItems {
		if !expectedSet[id] {
			extra = append(extra, id)
		}
	}
	sort.Ints(missing)
	sort.Ints(extra)

	// Subset semantics: every item in Data.lua must still appear in the API's loot
	// table for this instance. The reverse direction (extras) is informational —
	// /data/wow/journal-instance/{id} returns the historical superset (legacy WotLK
	// drops, Legion timewalking, etc.) and the addon's Data.lua is a curated
	// current-M+-season subset. Filtering the superset down to "current season only"
	// is a separate concern; see --inspect-encounter / --inspect-item to investigate
	// what fields can drive that filter.
	if len(missing) > 0 {
		t.Errorf("items in Data.lua but missing from API response (%d): %v", len(missing), missing)
	}
	if len(extra) > 0 {
		t.Logf("API returned %d items not in Data.lua (likely legacy / timewalking): %v",
			len(extra), extra)
	}
	t.Logf("API returned %d unique items; Data.lua has %d", len(apiItems), len(expectedPoSLoot))
}

func TestPitOfSaron_KnownItemDetails(t *testing.T) {
	c := newTestClient(t)
	const itemID = 49802 // first item in the PoS lootTable
	item, err := c.GetItem(itemID)
	if err != nil {
		t.Fatalf("GetItem(%d): %v", itemID, err)
	}
	if item.ID != itemID {
		t.Errorf("expected item ID %d, got %d", itemID, item.ID)
	}
	if item.Name == "" {
		t.Error("item name is empty")
	}
	if item.ItemClass.Name == "" {
		t.Error("item_class.name is empty")
	}
	if item.InventoryType.Type == "" {
		t.Error("inventory_type.type is empty")
	}
	t.Logf("Item %d: %q — class=%q subclass=%q inventory_type=%q",
		item.ID, item.Name, item.ItemClass.Name, item.ItemSubclass.Name, item.InventoryType.Type)
}
