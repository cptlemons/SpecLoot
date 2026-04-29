# SpecLoot Data Fetcher

Go program that pulls Mythic+ dungeon and raid loot tables from the Blizzard Game Data API and emits the data files consumed by the SpecLoot WoW addon.

Run occasionally (once per season, or whenever loot tables change) to refresh `Data.lua`.

## Prerequisites

1. Go 1.22+.
2. A Battle.net API client at <https://develop.battle.net/access/clients>. See the addon root README for setup steps.
3. The Battle.net **client ID** is hardcoded in `blizzard.go` (it's not a secret). Only the **client secret** needs to come from the environment:
   ```sh
   export BLIZZARD_CLIENT_SECRET="..."
   ```

## Test mode (single instance)

Validates one instance against the existing `Data.lua` before running the full pipeline.

```sh
cd tools/fetchloot
go run . --test 658     # Pit of Saron
```

Output prints the instance name, encounters, deduped item IDs (in the same shape as `Data.lua`'s `lootTable`), and per-item slot/class info. Compare this against the relevant dungeon row in `Data.lua` to confirm the API and our manifest agree before generalizing.

## Running tests

Live-API tests that diff Pit of Saron's loot table against `Data.lua`:

```sh
cd tools/fetchloot
go test ./... -v
# or just the PoS suite:
go test ./... -run TestPitOfSaron -v
```

Tests fail (rather than skip) when `BLIZZARD_CLIENT_SECRET` is unset, so a misconfigured environment can't quietly pass `go test`. They hit the live Blizzard API; expect a few seconds of runtime per run.

## Inspecting raw API responses

When the test reports drift you don't understand (e.g., extras that look like legacy / timewalking versions of an instance), dump the raw JSON to find a filtering field:

```sh
go run . --inspect-instance 278         # journal-instance for "Pit of Saron"
go run . --inspect-encounter 12345      # one encounter id from the instance response
go run . --inspect-item 49802           # an item known to be in current rotation
go run . --inspect-item 49801           # an adjacent item NOT in current rotation
```

Pretty-prints the full response body. Comparing the two item dumps is usually how we figure out which field distinguishes "current season" from "legacy".

## Looking up journal-instance IDs

The Blizzard REST API uses **journal-instance IDs**, which are *not* the same as the in-game map IDs that appear in older addon data (e.g. Pit of Saron's map ID is 658, but its journal-instance ID is 278).

**Batch-resolve every entry in the manifest:**
```sh
go run . --resolve-all              # writes journalInstanceId fields back into manifest.json
go run . --resolve-all --dry-run    # prints the resolved manifest, doesn't modify the file
```

This is the one-shot you run once per season after you've added new raids/dungeons by name. It only fills in entries whose `journalInstanceId` is currently 0, so re-running is safe.

**Ad-hoc lookup by partial name:**
```sh
go run . --find "pit of saron"      # case-insensitive substring
go run . --find voidspire
```

**Or list every raid in the index:**
```sh
go run . --list-raids
```

## Full generation

(Not yet implemented — coming after PoS validation passes.)

```sh
go run . --manifest manifest.json
```

Will write a freshly-generated `Data.lua` to the addon root.
