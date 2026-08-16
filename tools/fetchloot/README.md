# SpecLoot Data Fetcher

Go program that pulls Mythic+ dungeon and raid loot tables from the Blizzard Game Data API and emits the data files consumed by the SpecLoot WoW addon.

Run occasionally (once per season, or whenever loot tables change) to refresh `Data.lua`.

## Prerequisites

1. Go 1.22+.
2. A Battle.net API client from <https://develop.battle.net/access/clients>.
3. Provide your Battle.net credentials when running API-dependent commands, via environment variables:
   ```sh
   export BLIZZARD_CLIENT_SECRET="..."
   # Optional: defaults to built-in app Client ID if not provided
   export BLIZZARD_CLIENT_ID="..."
   ```
   Or pass them directly via CLI flags:
   ```sh
   go run . --client-secret="..." --client-id="..." ...
   ```

## Test mode (single instance)

Validates one instance against the existing `Data.lua` before running the full pipeline.

```sh
cd tools/fetchloot
go run . --test 1315     # Blinding Vale (or 1041 for Kings' Rest)
```

Output prints the instance name, encounters, deduped item IDs (in the same shape as `Data.lua`'s `lootTable`), and per-item slot/class info.

## Running tests

The test suite includes both offline validation of `Data.lua` and live-API tests against the Blizzard Game Data API:

```sh
cd tools/fetchloot
go test ./... -v
```

- **Offline tests** (`specloot_data_test.go`): Validates item filtering (cosmetics, patterns, non-equipment curios), Demon Hunter spec restrictions, omni-token support, and Bonus Rolls / Great Vault track mappings against `SpecLoot/Data.lua` without needing API credentials.
- **Live-API tests** (`fetchloot_test.go`): Verifies metadata and loot table consistency against the live Blizzard API. Automatically skips if `BLIZZARD_CLIENT_SECRET` is not set.

## Inspecting raw API responses

When investigating item or encounter drift, dump the raw JSON from the Blizzard Game Data API:

```sh
go run . --inspect-instance 1315        # journal-instance for "Blinding Vale"
go run . --inspect-encounter 12345      # encounter ID from the instance response
go run . --inspect-item 270909          # an item in the current rotation (e.g. Slumbering Coil Curio)
go run . --inspect-item 258045          # cosmetic/filtered item (e.g. Dawnblade's Glaives)
```

Pretty-prints the full response body.

## Looking up journal-instance IDs

The Blizzard REST API uses **journal-instance IDs**, which are *not* the same as the in-game map IDs (e.g. Blinding Vale's map ID is 2859, but its journal-instance ID is 1315).

**Batch-resolve every entry in the manifest:**
```sh
go run . --resolve-all              # writes journalInstanceId fields back into manifest.json
go run . --resolve-all --dry-run    # prints the resolved manifest without writing
```

This is the one-shot command run once per season after adding new raids/dungeons by name to `manifest.json`. It fills in entries whose `journalInstanceId` is currently 0.

**Ad-hoc lookup by partial name:**
```sh
go run . --find "blinding vale"     # case-insensitive substring
go run . --find "toxic abyss"
```

**List every raid in the index:**
```sh
go run . --list-raids
```

## Generating Data.lua

Fetch encounter loot tables and item classifications for all Season 2 manifest entries and write directly to `SpecLoot/Data.lua`:

```sh
go run . --generate-data
```

Optionally specify a custom output path:
```sh
go run . --generate-data --output ../../SpecLoot/Data.lua
```
