# SpecLoot

**SpecLoot** is a lightweight World of Warcraft addon designed to help you optimize your loot specialization. It compares Mythic+ and Raid loot side-by-side across every spec of your class, making it easy to see where your Best-in-Slot (BiS) items are hiding.

Useful for picking which loot spec to set before pushing a key or pulling a boss, and for identifying which spec has the highest density of unique upgrades in a specific encounter.

---

## Key Features

* **Side-by-Side Comparison:** View loot for all specs of a class simultaneously.
* **Shared Loot Panel:** Quickly identify items that drop for *every* spec (e.g., necks, rings, cloaks).
* **Smart Highlighting:** Hover over an item to see it light up in every spec panel where it appears.
* **Difficulty-Aware Tooltips:** Real-time item level previews based on Keystone level (+2 to +10) or Raid difficulty (LFR through Mythic).
* **Zero Manual Data Maintenance:** Uses an intelligent in-game scraper to pull live data from the Encounter Journal, ensuring item stats and drops are always accurate to the current patch.
* **Teleport Shortcuts:** Right-click dungeon icons to cast that dungeon's teleport portal (if known).

---

## Usage

### Slash Commands

| Command | Action |
| :--- | :--- |
| `/sl` or `/specloot` | Toggle the main interface |
| `/sl status` | Check the health of your local loot cache |
| `/sl rescan` | Force a fresh scrape of the Encounter Journal |
| `/sl help` | Show all available commands |
| **Esc** | Close the window |

### Navigation

* **Mythic+ View:** Select your Keystone level to see the exact end-of-run item levels. Left-click a dungeon tile to see loot; right-click to teleport.
* **Raid View:** Switch via the top tabs. Select difficulty (LFR/N/H/M) and click a boss portrait to see their specific loot table broken down by spec.
* **Class Browsing:** Use the top-right dropdown to view loot for other classes. Spec data is lazily loaded and cached on the fly.

---

## Technical Details

### Repo Layout
* `SpecLoot/`: The WoW Addon files.
    * `SpecLoot.lua`: Core logic, UI frames, and slash commands.
    * `Data.lua`: Manifests for the current season's dungeons and raids.
    * `Scraper.lua`: Handles the heavy lifting of querying the Encounter Journal.
    * `Output.lua`: Copy/paste utility for debug logs.
* `tools/fetchloot/`: A Go-based utility for developers to resolve new Instance IDs when a new WoW season begins.

### Developer Diagnostics
If you are contributing or debugging content-patch breakage:
* `/sl debug`: Performs a verbose scrape and dumps the output into a copyable text window.
* `/sl probe <instID> <bossID>`: Diagnoses how many items the API returns for a specific encounter across all difficulties.

---

## Maintenance
SpecLoot is designed to be "set and forget." Because it scrapes the game client directly, loot table changes by Blizzard are reflected automatically. Developers only need to update `Data.lua` when the dungeon rotation changes (typically once per season). See the [fetchloot README](tools/fetchloot/README.md) for the automation workflow.