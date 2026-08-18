# Changelog

## [12.1.0 - Season 2]

### UI & Layout Modernization
- **Equipment Slot Headers**: Grouped loot by equipment slot (Head, Neck, Shoulder, Back, Chest, Wrist, Hands, Waist, Legs, Feet, Weapon, Off-hand, Ring, Trinket, Curio, Token) with horizontally aligned rows across all spec columns in both Normal Loot mode and Bonus Rolls mode.
- **Unified Mage & Warlock View**: In Normal Loot mode, pure caster DPS classes (Mage and Warlock) automatically collapse into a single unified wide panel with centered slot headers and all 3 spec icons displayed side-by-side at the bottom (`[Arcane] [Fire] [Frost] All Specializations (<total>)`). In Bonus Rolls mode, they remain 3 distinct columns for independent spec tracking.
- **Druid 4-Spec Overrun Fix**: Resized window width to 840px and implemented dynamic column width calculations (`201px` for 4 specs, `269px` for 3 specs), ensuring item frame text, hover highlights, and dividers never bleed into adjacent columns.

### Item Stats, Weapons & Cantrip Identifiers
- **Secondary Stats Tagging**: Displays secondary stat pairs in grey text next to item names, strictly prioritized in order: **Crit** > **Haste** > **Vers** > **Mast** (e.g. `Crit/Mast`, `Haste/Vers`, `Vers/Mast`, `Crit/Haste`).
- **Weapon Primary Stats**: Prepends primary stats (`Str`, `Agi`, `Int`) before secondary stats for weapons and off-hands (e.g. `Str/Agi Haste/Mast`, `Agi/Int Crit/Haste`, `Int Crit/Mast`, `Str Crit/Vers`).
- **Cantrip Effects**: Appends `Cantrip` to non-trinket armor and weapons with on-equip or on-use proc effects (e.g. `Str Haste Cantrip`, `Crit Cantrip`, `Mast Cantrip`). Trinkets remain clean without stat tags.

### Visual Highlighting & Track Banners
- **Spec-Exclusive Highlighting**: Highlights items that only drop for a single spec within that class (e.g. Guardian tank trinkets, Retribution 2H weapons, Holy shields) with a warm gold background tint, a left-edge accent bar, and a `★ Spec-Exclusive Item` tooltip note in both Normal and Bonus Rolls modes.
- **Upgrade Track Banners**: Added top banners across all columns in both modes:
  - **Normal Mode**: Displays drop track levels (e.g. `"Loot drops at 1/6 Myth"`, `"Loot drops at 3/6 Hero"`).
  - **Bonus Rolls Mode**: Displays reward track levels (e.g. `"Bonus rolls give 1/6 Myth loot"`).
- **Dynamic Spec Footer Counts**:
  - **Bonus Rolls Mode**: Shows remaining unobtained items in rotation (`SpecName (<remaining>)`), updating in real time when marking items.
  - **Normal Mode**: Shows total items in that spec's loot table (`SpecName (<total>)`).

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
