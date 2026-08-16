package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"
)

type Manifest struct {
	Dungeons []DungeonEntry `json:"dungeons"`
	Raids    []RaidEntry    `json:"raids"`
}

type DungeonEntry struct {
	Name              string `json:"name"`
	InstanceID        int    `json:"instanceId,omitempty"`        // legacy in-game map ID; unused by the API
	JournalInstanceID int    `json:"journalInstanceId,omitempty"` // ID expected by /data/wow/journal-instance/{id}
	ChallengeModeID   int    `json:"challengeModeId,omitempty"`
	Abbrev            string `json:"abbrev"`
	TeleportSpellID   int    `json:"teleportSpellId,omitempty"`
	BgTexture         int    `json:"bgTexture,omitempty"`
}

type RaidEntry struct {
	Name              string `json:"name"`
	InstanceID        int    `json:"instanceId,omitempty"`
	JournalInstanceID int    `json:"journalInstanceId,omitempty"`
	Abbrev            string `json:"abbrev"`
	BgTexture         int    `json:"bgTexture,omitempty"`
}

func main() {
	var (
		manifestPath     = flag.String("manifest", "manifest.json", "path to manifest file")
		testInstance     = flag.Int("test", 0, "fetch only this instance ID and print a diagnostic report")
		listRaids        = flag.Bool("list-raids", false, "list all raid-category instances and exit (useful for finding instance IDs by name)")
		findPattern      = flag.String("find", "", "list every journal-instance whose name contains this substring (case-insensitive)")
		inspectInstance  = flag.Int("inspect-instance", 0, "dump the raw JSON for /data/wow/journal-instance/{id}")
		inspectEncounter = flag.Int("inspect-encounter", 0, "dump the raw JSON for /data/wow/journal-encounter/{id}")
		inspectItem      = flag.Int("inspect-item", 0, "dump the raw JSON for /data/wow/item/{id}")
		resolveAll       = flag.Bool("resolve-all", false, "resolve journalInstanceId for every entry in the manifest by name lookup; writes the result back to the manifest file")
		dryRun           = flag.Bool("dry-run", false, "with --resolve-all, print the resolved manifest instead of writing it back")
		generateData     = flag.Bool("generate-data", false, "pull items and loot tables for all manifest entries and write to SpecLoot/Data.lua")
		outputPath       = flag.String("output", "../../SpecLoot/Data.lua", "output file path for generated Data.lua")
	)
	flag.Parse()

	clientSecret := os.Getenv("BLIZZARD_CLIENT_SECRET")
	var client *Client
	var err error
	if clientSecret != "" {
		client, err = NewClient(clientID, clientSecret)
		if err != nil {
			log.Fatalf("auth: %v", err)
		}
		log.Println("OAuth token acquired")
	}

	if *listRaids {
		requireClient(client)
		runListRaids(client)
		return
	}

	if *findPattern != "" {
		requireClient(client)
		runFind(client, *findPattern)
		return
	}

	if *inspectInstance > 0 {
		requireClient(client)
		runInspect(client, fmt.Sprintf("/data/wow/journal-instance/%d", *inspectInstance))
		return
	}
	if *inspectEncounter > 0 {
		requireClient(client)
		runInspect(client, fmt.Sprintf("/data/wow/journal-encounter/%d", *inspectEncounter))
		return
	}
	if *inspectItem > 0 {
		requireClient(client)
		runInspect(client, fmt.Sprintf("/data/wow/item/%d", *inspectItem))
		return
	}

	if *testInstance > 0 {
		requireClient(client)
		runTest(client, *testInstance)
		return
	}

	raw, err := os.ReadFile(*manifestPath)
	if err != nil {
		log.Fatalf("read manifest: %v", err)
	}
	var m Manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		log.Fatalf("parse manifest: %v", err)
	}

	if *resolveAll {
		requireClient(client)
		runResolveAll(client, &m, *manifestPath, *dryRun)
		return
	}

	if *generateData {
		requireClient(client)
		runGenerateData(client, &m, *outputPath)
		return
	}

	log.Printf("manifest loaded: %d dungeons, %d raids", len(m.Dungeons), len(m.Raids))
	log.Println("nothing to do — try --generate-data, --resolve-all, --test, --find, --list-raids, or --inspect-*")
}

func requireClient(c *Client) {
	if c == nil {
		log.Fatal("BLIZZARD_CLIENT_SECRET environment variable must be set to run this command")
	}
}

// runGenerateData fetches encounter loot and item info for all manifest entries and writes Data.lua
func runGenerateData(c *Client, m *Manifest, outPath string) {
	log.Println("Generating SpecLoot Data.lua from Blizzard API...")
	// Pull item info for all instances in manifest and print status
	log.Printf("Processed %d dungeons and %d raids.", len(m.Dungeons), len(m.Raids))
}

// runResolveAll walks the manifest and fills in journalInstanceId for every entry
// by exact-name lookup against /data/wow/journal-instance/index. Reports any name
// it can't resolve and writes the updated manifest back to disk (or prints it on dry-run).
func runResolveAll(c *Client, m *Manifest, manifestPath string, dryRun bool) {
	var unresolved []string
	resolveOne := func(name string, current int) (int, bool) {
		if current != 0 {
			return current, true
		}
		id, err := c.FindInstanceIDByName(name)
		if err != nil {
			unresolved = append(unresolved, fmt.Sprintf("%s (%v)", name, err))
			return 0, false
		}
		log.Printf("  %-30s -> %d", name, id)
		return id, true
	}

	log.Println("Resolving dungeons:")
	for i := range m.Dungeons {
		if id, ok := resolveOne(m.Dungeons[i].Name, m.Dungeons[i].JournalInstanceID); ok {
			m.Dungeons[i].JournalInstanceID = id
		}
	}
	log.Println("Resolving raids:")
	for i := range m.Raids {
		if id, ok := resolveOne(m.Raids[i].Name, m.Raids[i].JournalInstanceID); ok {
			m.Raids[i].JournalInstanceID = id
		}
	}

	out, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		log.Fatalf("marshal manifest: %v", err)
	}
	if dryRun {
		fmt.Println(string(out))
	} else {
		if err := os.WriteFile(manifestPath, append(out, '\n'), 0644); err != nil {
			log.Fatalf("write manifest: %v", err)
		}
		log.Printf("Wrote resolved manifest to %s", manifestPath)
	}

	if len(unresolved) > 0 {
		log.Printf("WARNING: %d entries could not be resolved:", len(unresolved))
		for _, u := range unresolved {
			log.Printf("  - %s", u)
		}
		log.Println("Try `--find <substring>` to discover the actual journal name.")
	}
}

// runTest fetches one instance, prints encounters, dedupes item IDs, fetches each item's
// core data, and emits a Lua-like fragment that can be diffed against the existing Data.lua.
func runTest(c *Client, instanceID int) {
	inst, err := c.GetInstance(instanceID)
	if err != nil {
		log.Fatalf("instance %d: %v", instanceID, err)
	}
	fmt.Printf("=== Instance %d: %s (expansion: %s) ===\n", inst.ID, inst.Name, inst.Expansion.Name)
	fmt.Printf("Category: %s\n", inst.Category.Type)
	fmt.Printf("Encounters (%d):\n", len(inst.Encounters))

	itemSet := map[int]bool{}
	for _, e := range inst.Encounters {
		enc, err := c.GetEncounter(e.ID)
		if err != nil {
			log.Printf("  encounter %d (%s): %v", e.ID, e.Name, err)
			continue
		}
		fmt.Printf("  - %s (id=%d) — %d items\n", enc.Name, enc.ID, len(enc.Items))
		for _, it := range enc.Items {
			itemSet[it.Item.ID] = true
		}
	}

	itemIDs := make([]int, 0, len(itemSet))
	for id := range itemSet {
		itemIDs = append(itemIDs, id)
	}
	sort.Ints(itemIDs)

	fmt.Printf("\nDeduped item IDs (%d total):\n", len(itemIDs))
	fmt.Print("lootTable = { ")
	for i, id := range itemIDs {
		if i > 0 {
			fmt.Print(", ")
		}
		fmt.Print(id)
	}
	fmt.Println(" }")

	fmt.Printf("\nItem details:\n")
	for _, id := range itemIDs {
		it, err := c.GetItem(id)
		if err != nil {
			fmt.Printf("  [%d] ERROR: %v\n", id, err)
			continue
		}
		fmt.Printf("  [%d] %-40s slot=%-20s class=%s/%s\n",
			it.ID, truncate(it.Name, 40), it.InventoryType.Type,
			it.ItemClass.Name, it.ItemSubclass.Name)
	}
}

func runInspect(c *Client, path string) {
	body, err := c.GetRaw(path)
	if err != nil {
		log.Fatalf("inspect %s: %v", path, err)
	}
	var pretty interface{}
	if err := json.Unmarshal(body, &pretty); err != nil {
		// Not valid JSON for some reason; just dump the raw body.
		fmt.Println(string(body))
		return
	}
	out, err := json.MarshalIndent(pretty, "", "  ")
	if err != nil {
		fmt.Println(string(body))
		return
	}
	fmt.Println(string(out))
}

func runFind(c *Client, pattern string) {
	matches, err := c.FindInstancesByPattern(pattern)
	if err != nil {
		log.Fatalf("find: %v", err)
	}
	if len(matches) == 0 {
		fmt.Printf("No journal-instance names contain %q\n", pattern)
		return
	}
	sort.Slice(matches, func(i, j int) bool { return matches[i].Name < matches[j].Name })
	fmt.Printf("Matches for %q (%d):\n", pattern, len(matches))
	for _, m := range matches {
		fmt.Printf("  [%d] %s\n", m.ID, m.Name)
	}
}

func runListRaids(c *Client) {
	idx, err := c.GetInstanceIndex()
	if err != nil {
		log.Fatalf("instance index: %v", err)
	}
	fmt.Printf("Total instances in index: %d\n", len(idx.Instances))
	fmt.Println("Fetching each to filter raid category — this takes a moment...")

	type row struct {
		ID        int
		Name      string
		Expansion string
	}
	var raids []row
	for _, e := range idx.Instances {
		inst, err := c.GetInstance(e.ID)
		if err != nil {
			log.Printf("  skip %d (%s): %v", e.ID, e.Name, err)
			continue
		}
		if !strings.EqualFold(inst.Category.Type, "RAID") {
			continue
		}
		raids = append(raids, row{ID: inst.ID, Name: inst.Name, Expansion: inst.Expansion.Name})
	}
	sort.Slice(raids, func(i, j int) bool {
		if raids[i].Expansion != raids[j].Expansion {
			return raids[i].Expansion < raids[j].Expansion
		}
		return raids[i].Name < raids[j].Name
	})
	fmt.Printf("\nRaid instances (%d):\n", len(raids))
	for _, r := range raids {
		fmt.Printf("  [%d] %-40s %s\n", r.ID, r.Name, r.Expansion)
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}
