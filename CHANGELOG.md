# Changelog

## [12.1.0 - Season 2]

### Season 2 Loot & Encounters
- Updated for World of Warcraft Patch 12.1.0 and Season 2.
- Replaced Season 1 dungeons and raids with the complete Season 2 rotation, encounters, and item manifests.
- Added accurate upgrade tracks and per-boss difficulty scaling for Season 2 raids and Mythic+ keystones.
- Supported tier tokens and omni-tokens (such as *Slumbering Coil Curio* and *Venomcured Remnant*).
- Filtered out non-equipment bonus loot, including cosmetic weapons/armor (e.g. *Dawnblade's Glaives*), patterns, mounts, pets, and fluff curios.

### Bonus Rolls & Great Vault Tracking
- Added **Bonus Rolls Mode** with a dedicated header checkbox toggle.
- Displays Great Vault / Bonus Roll upgrade tracks and scaled item levels (e.g. M+ 10 displays `1/6 Myth`, Heroic Raid displays `1/6 Myth` .. `4/6 Myth`, Mythic Raid displays `6/6 Myth` / `9/6 Myth`).
- Right-click any item in Bonus Rolls mode to mark it as received / obtained, applying a strikethrough line and desaturating the icon to indicate it is removed from the active bonus roll pool.
- Marking items is scoped per-spec, allowing shared items to be marked in one spec while remaining in rotation for others.
- Bonus roll progress is stored per-character (`SpecLootCharDB`) and persists throughout the season across UI reloads and updates.
- Added `/sl clear` and `/sl reset` commands to reset all marked bonus rolls for the logged-in character.

### Misc UI Tweaks
- Miscellaneous UI tweaks, dropdown alignment, text centering, spacing buffers, and layout adjustments.
