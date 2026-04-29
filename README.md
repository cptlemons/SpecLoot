# SpecLoot

A World of Warcraft addon that compares Mythic+ dungeon and raid loot drops side-by-side across every spec of any class.

## What it shows

For the selected dungeon (or boss), class, and difficulty, you get:

- A **Shared Loot** panel listing items that drop for *every* spec of the class.
- One panel per spec listing items that drop only for that spec.
- A per-item, difficulty-aware tooltip with the correct item level. Items that drop for more than one spec light up in every panel they appear in.

Useful for picking which loot spec to set before pushing a key or queuing a raid, and for figuring out which spec gets the most unique gear from a given encounter.

---

## Repo layout

```
SpecLoot/
├── SpecLoot/            # the WoW addon — drop this folder into Interface/AddOns/
│   ├── SpecLoot.toc
│   ├── SpecLoot.lua     # frame, view-mode tabs, slash commands
│   ├── Data.lua         # dungeon/raid manifest + class/spec reference
│   ├── Scraper.lua      # in-game loot/spec scraper (writes to SpecLootDB)
│   └── Output.lua       # copyable popup window for /sl debug + /sl probe
└── tools/fetchloot/     # offline Go tool that resolves journal-instance IDs (run once per season)
```

## Install

1. Copy the inner `SpecLoot/` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Restart WoW or `/reload`.

The first time you run `/sl` after a fresh install (or after a content patch that bumps `SCRAPE_VERSION`), the addon scrapes the in-game Encounter Journal once to populate its data — takes a second or two and persists in `SpecLootDB` (per-account SavedVariable). Subsequent opens are instant.

## Usage

### Slash commands

| Command | What it does |
|---|---|
| `/specloot` or `/sl` | Toggle the main window |
| `/sl rescan` | Force a fresh scrape (quiet) |
| `/sl debug` | Re-scrape with verbose per-encounter output, dumped to a copyable popup |
| `/sl probe <instanceID> <encounterID>` | Show how many items each difficulty ID returns for one encounter — diagnostic for content-patch breakage |
| `/sl status` | Print a one-line summary of the cache contents |
| `/sl help` | List the commands above |
| **Esc** | Close the main window when it's open |

### Mythic+ view

- **Keystone dropdown** (top-left) — pick the key level (+2 through +10); end-of-run item-level preview updates accordingly.
- **Dungeon icons** (top row, 8 tiles) — **left-click** to select a dungeon; **right-click** to cast that dungeon's teleport portal (if your character knows it).

### Raid view

Click the **Raids** tab at the top to switch.

- **Difficulty dropdown** (top-left) — LFR / Normal / Heroic / Mythic. Replaces the keystone dropdown.
- **Boss tiles** (top row, 9 tiles for current Midnight Season 1) — show every boss across all 3 raids in one row, with the raid abbreviation labeled below each portrait. Click any boss to view its loot.
- Tooltips show the actual per-item ilvl at the selected difficulty (a trinket from a Mythic boss correctly shows the trinket's bonus over a regular drop, etc.) — these are pulled directly from the journal's per-difficulty links rather than averaged into a single number.

### Class browsing

The class dropdown (top-right) defaults to your current class. Switching to another class lazily classifies that class's spec data via the Encounter Journal (one-time, ~80 ms) and then renders.

---

## Keeping the dungeon/raid manifest current

Every season Blizzard adds new instances; their journal-instance IDs need to be resolved before the addon can scrape them. The `tools/fetchloot/` Go program handles that — see [its README](tools/fetchloot/README.md) for setup and the `--resolve-all` workflow. You only need to run it when the dungeon/raid lineup changes.

The actual loot tables, item slots, icons, and per-class spec mapping all come from the in-game scraper at runtime — there's no hand-curated item data anywhere in the codebase.
