# RADLANDS Save Schema — versioned structure (T2 definition, T3 implements)

The save format is a **separate namespace** from content: saves are JSON at
`user://` written by T3 (SaveManager: atomic temp+rename write, 3-slot backup
rotation, load-with-fallback, autosave); content is read-only under `res://`
with its own `schema_version` (see `docs/content-schema.md`). The two version
counters never interact — content migrations and save migrations are different
code paths (R1's separation rule, Doctor Strange's versioning-from-day-1
claim).

## Versioning rules (binding on T3)

- Top-level `save_version: 1` today. Bump on any shape change.
- Every migration is a named, ordered function (e.g.
  `_migrate_1_to_2(dict) -> dict`); a save loads only after being migrated up
  to the current `save_version`.
- `save_version > CURRENT` (from a newer build) → refuse with the
  corruption/fallback notice state, never write garbage back over it.
- All integers exact; big-number fields follow T14's int-math policy (no
  float round-trips).
- Unknown keys inside known objects are *dropped on next save* (saves are
  engine-owned, unlike content where unknown keys are errors) — but never a
  load failure.

## Shape (save_version 1)

Structure only — values illustrative:

```jsonc
{
	"save_version": 1,
	"meta": {
		"created_unix": 1760000000,   // first-boot stamp, never rewritten
		"updated_unix": 1760100000,   // last successful save
		"playtime_s": 5400
	},
	"wallet": {
		"caps": 250                   // single currency; int
	},
	"skills": {
		// one entry per SkillDef id; ids absent = untouched (level 1, 0 xp)
		"scavenging":      { "level": 4, "xp": 120 },
		"wasteland_combat": { "level": 2, "xp": 15 }
	},
	"inventory": [
		// one stack per item id; qty 1–999 per design-brief ranges
		{ "item": "scrap_metal", "qty": 34 },
		{ "item": "radstag_stew", "qty": 3 }
	],
	"equipment": {
		"weapon": "scrap_shiv",       // item id or null
		"armor": null
	},
	"activity_state": {
		// what was running when the save was written; null = idle
		// (offline catch-up computes from `since_unix` at load, T6)
		"gathering":   { "activity_id": "sort_scrap_pile", "since_unix": 1760099990 },
		"combat":      { "monster_id": "junkyard_roach", "since_unix": null }
	},
	"settings": {
		"font_scale": 1.0,            // 0.75–2.0, T8/T15 contract
		"fullscreen": false
	}
}
```

## Field notes

- **No content duplication.** Saves reference content ids (`item`, `skill`,
  `monster_id`, `activity_id`); they never copy stats/names. T3's load pass
  validates every id against `ContentDB` and drops unknown ones to the
  corruption-fallback path (a save referencing content that no longer exists
  is a broken save, surfaced not guessed at).
- **XP stored as total per skill**, not level+xp: `skills[id].xp` is lifetime
  XP and `level` is its derived level (kept for cheap reads; T3 re-derives and
  repairs drift via `XpCurveDef.level_for_total_xp`). If T5 prefers
  level+progress-xp instead, that is a `save_version` bump decided before T3
  ships — recorded here so it is a one-time decision.
- **`activity_state.*.since_unix`** is the offline anchor; uncapped full-rate
  catch-up (user decision) is closed-form math from it (T6), with T14's
  clock-regression guard clamping nonsense values.
- **Combat death state is not saved** — death stops combat (town-hall rule),
  so a save written during combat either resumes it or is the pre-combat
  state; T3/T7 settle the exact serialization when T7 lands.

T3 owns everything below this line: file names, backup slots, atomicity
mechanics, migration implementations, and the corruption-notice UI state.
