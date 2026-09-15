# RADLANDS Content Schema

Contract for every content record in `data/*.json` (T2, Iron Man lane).
Implements research decision R1 (`docs/ultron/research/r1-content-storage.md`):
**JSON files under `res://data/` are the source of truth; a validating loader
(`scripts/content/content_loader.gd`) hydrates typed in-memory GDScript classes
(`scripts/content/*_def.gd`). No `.tres` for balance content.**

## The golden set is EXAMPLES

The records currently in `data/*.json` are a **golden set**: a minimal,
internally consistent example slice (3 of 5 skills, 2 monsters, 2 equipment
pieces) that exists to prove the loader end-to-end. **T4 (naming) and T5
(balance) replace and extend them.** Placeholder names here ("Junkyard Roach",
"Radstag Stew", …) have NOT passed the trademark checklist. Balance numbers are
placeholders, not tuned.

## File layout

One JSON file per domain, each an object with exactly `schema_version` plus one
records array (any other top-level key is an error):

| File | Array key | Typed class | Primary consumers |
|---|---|---|---|
| `data/items.json` | `items` | `ItemDef` | T6 inventory, T10a Manifest/Depot |
| `data/skills.json` | `skills` | `SkillDef` | T6 XP, T8/T9 plates |
| `data/activities.json` | `activities` | `ActivityDef` | T6 idle engine |
| `data/recipes.json` | `recipes` | `RecipeDef` | T6 idle engine |
| `data/drop_tables.json` | `drop_tables` | `DropTableDef` | T6 rolls, T10 renders visible rates |
| `data/monsters.json` | `monsters` | `MonsterDef` | T7 combat, T10b patrol |
| `data/equipment.json` | `equipment` | `EquipmentDef` | T7 stat application, T10b slots |
| `data/shop_stock.json` | `shop_stock` | `ShopEntryDef` | T10a Depot |
| `data/xp_curves.json` | `xp_curves` | `XpCurveDef` | T6 XP math, T10 gauges |

`schema_version` is currently **1** and is namespaced to *content only* — it
never collides with the save format's `save_version` (see
`docs/save-schema.md`).

## Validation + error format

The loader validates every record at boot:

- **Exact key sets** — missing required fields and unknown fields (typos,
  stale keys) are errors. Nothing is silently dropped (the failure mode that
  killed `.tres`, per R1's spikes).
- **Types + ranges on every field** — JSON numbers arrive as `float`; whole
  floats are coerced to `int`, fractional or wrong-typed values are rejected,
  and every field is bounds-checked far below the 2^53 float-precision cliff.
- **Cross-field rules** — e.g. `heal` only on food; `attack_speed_ms` only on
  weapons; `min_hit <= max_hit`; `qty_min <= qty_max`; `gate.skill` +
  `gate.level` both-or-neither.
- **Cross-domain references** — every `skill`/`item`/`drop_table`/`xp_curve`
  id must exist; equipment items and their `EquipmentDef` records must pair
  1:1 in both directions; a skill's `max_level` must equal its curve's.
- **Duplicates** — ids unique per domain; one shop line and one equipment
  record per item.
- **Orphans (warnings, not errors)** — items nothing can produce; drop tables
  nothing rolls. T5's "no orphan items/sinks" acceptance reads
  `ContentDB.library.orphan_item_ids()` / `unused_drop_table_ids()`.

Every error is a single actionable line:

```
[content] data/<file>.json · <records>[<index>] (id=<record id>) · <field>: <reason>
```

record id + field + reason, always. On any error, the `ContentDB` autoload
prints all errors and quits the game (fail loud, per R1). Load the library from
code via `ContentLoader.load_all()` (returns `Result` with `library`, `errors`,
`warnings`); the autoload exposes typed lookups (`ContentDB.item(id)`,
`ContentDB.monster(id)`, …) that gameplay code should prefer.

## Field reference

Ranges below are the loader's enforced contract (source of truth:
`scripts/content/content_loader.gd` consts — keep this table in sync).

### Common conventions

- **id fields** (`id`, `item`, `skill`, `zone`, `icon`, refs): snake_case
  `[a-z][a-z0-9_]{0,63}`.
- `name`: non-empty display string (T4 owns final names; validated non-empty
  and unique-by-id today; T4 may add checklist verdicts via validator
  extension, not format change).
- `icon`: icon asset **id** — T11 resolves it to `res://assets/icons/<icon>.svg`
  and its acceptance gate is that every one resolves. Loader validates format
  only for now (existence check flips on at T11).
- `level_gate`: clearance level 1–99 ("CLEARANCE N REQUIRED" plates, T9/T10).
- All rates/intervals are integer milliseconds so T6's tick math and
  closed-form offline math stay int-exact.

### items.json

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | inventory id |
| `name` | string | non-empty | y | |
| `category` | enum | `resource` \| `material` \| `food` \| `equipment` | y | |
| `value` | int | 0–1,000,000 | y | caps the Depot pays per unit (sell price) |
| `heal` | int | 1–10,000 | food only | required iff `category == "food"`; eaten by T7 auto-eat |
| `icon` | string | snake_case | y | |

### skills.json

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | |
| `name` | string | non-empty | y | |
| `kind` | enum | `gathering` \| `processing` \| `combat` | y | exactly one combat skill must exist |
| `max_level` | int | 2–99 | y | must equal the referenced curve's `max_level` |
| `xp_curve` | string | ref | y | `xp_curves.json` id |
| `icon` | string | snake_case | y | |

### activities.json (gathering)

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | |
| `name` | string | non-empty | y | |
| `skill` | string | ref | y | skill this trains |
| `level_gate` | int | 1–99 | y | clearance in `skill` |
| `interval_ms` | int | 100–600,000 | y | time per action |
| `xp_per_action` | int | 1–1,000,000 | y | |
| `drop_table` | string | ref | y | rolled `rolls` times per action |
| `icon` | string | snake_case | y | |

### recipes.json (processing)

Same header fields as activities (`id`, `name`, `skill`, `level_gate`,
`interval_ms`, `xp_per_action`; `icon` optional — empty = render output item's
icon), plus:

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `inputs` | array | 1–4 of `{item, qty}` | y | consumed atomically per craft; `qty` 1–999 |
| `output` | object | `{item, qty}` | y | produced per craft; `qty` 1–999 |

### drop_tables.json (visible rates)

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | |
| `name` | string | non-empty | y | drop-line header shown to players |
| `rolls` | int | 1–10 | y | independent picks per action/kill |
| `entries` | array | 1–64 | y | see below |

Entry: `{ "item": ref, "weight": 1–100000, "qty_min": 1–999, "qty_max": 1–999 }`.
One roll = one weighted pick; chance of an entry = `weight / total_weight`
(`DropTableDef.total_weight()`), exact and player-visible (honest-math
principle; T10 renders these fractions, never percentages with hidden
rounding).

### monsters.json

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | |
| `name` | string | non-empty | y | |
| `zone` | string | snake_case | y | slice ships one zone id |
| `is_boss` | bool | | y | |
| `level_gate` | int | 1–99 | y | clearance in the combat skill |
| `max_hp` | int | 1–100,000 | y | |
| `attack_speed_ms` | int | 100–600,000 | y | |
| `accuracy` | int | 1–100,000 | y | vs defender evasion (T7 roll) |
| `evasion` | int | 0–100,000 | y | |
| `min_hit` | int | 0–10,000 | y | damage bounds; `min_hit <= max_hit` |
| `max_hit` | int | 1–10,000 | y | |
| `xp_reward` | int | 1–1,000,000 | y | combat XP on kill |
| `drop_table` | string | ref | y | rolled on victory |
| `icon` | string | snake_case | y | |

### equipment.json

Keyed by `item` (must be an `items.json` record with `category ==
"equipment"`; 1:1 both directions). Bonuses are additive onto player base
stats; `attack_speed_ms` **replaces** base attack interval.

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `item` | string | ref | y | this record's identity |
| `slot` | enum | `weapon` \| `armor` | y | |
| `attack_speed_ms` | int | 100–600,000 | weapon only | omit/-1 = keep base |
| `accuracy_bonus` | int | 0–10,000 | n | default 0 |
| `max_hit_bonus` | int | 0–10,000 | n | default 0 |
| `evasion_bonus` | int | 0–10,000 | n | default 0 |
| `max_hp_bonus` | int | 0–10,000 | n | default 0 |

Player *base* combat stats are engine-side constants owned by T7 (not content)
— content governs monsters and gear, not the player chassis.

### shop_stock.json

File order = Depot display order. Selling always pays `ItemDef.value` (single
honest sell price lives on the item); entries only set buy terms.

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `item` | string | ref | y | identity of the line |
| `buy_price` | int | 1–1,000,000 | y | caps charged per unit |
| `gate` | object | `{skill, level}` | n | both keys or neither; hides line behind clearance |

### xp_curves.json

| Field | Type | Range | Req | Notes |
|---|---|---|---|---|
| `id` | string | snake_case | y | |
| `name` | string | non-empty | y | |
| `max_level` | int | 2–99 | y | |
| `xp_per_level` | int array | length == `max_level - 1`; each 1–100,000,000 | y | `xp_per_level[i]` = XP to advance from level i+1 to i+2; hand-tunable per entry, no formula imposed |

`XpCurveDef` provides `total_xp_to_reach(level)`, `level_for_total_xp(xp)`,
`xp_to_next(level)` — int-exact helpers T6/T13 reuse.

## Versioning

`schema_version` bumps when a file's *shape* changes (field added/removed,
range change). Procedure: bump `ContentLoader.SCHEMA_VERSION` + this doc +
all nine files in one commit, and update T5's authored content in the same
change — content and code move together or boot fails by design.
