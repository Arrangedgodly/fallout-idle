# Valued Resident Save Schema — versioned structure (T2 defined, T3 ships)

The save format is a **separate namespace** from content: saves are JSON at
`user://` written by T3's SaveStore autoload (`scripts/autoload/save_store.gd`;
atomic temp+rename write, 3-slot backup ring, load-with-fallback, 60 s
autosave); content is read-only under `res://` with its own `schema_version`
(see `docs/content-schema.md`). The two version counters never interact —
content migrations and save migrations are different code paths (R1's
separation rule, Doctor Strange's versioning-from-day-1 claim).

## Versioning rules (binding, unchanged since T2)

- Top-level `save_version: 1` today. Bump on any shape change.
- Every migration is a named, ordered function (e.g.
  `_migrate_1_to_2(dict) -> dict`); a save loads only after being migrated up
  to the current `save_version`. The chain hook lives in SaveStore
  (`_apply_migrations`) and is exercised by `tests/test_save.gd`.
- `save_version > CURRENT` (from a newer build) → refuse with the
  corruption/fallback notice state, never write garbage back over it — and
  while refused, ALL writes are blocked (`SaveStore.save_blocked`).
- All integers exact; big-number fields follow T14's int-math policy (no
  float round-trips). The one int64 pair that matters today — per-slot RNG
  `rng_seed`/`rng_state` — ships as STRINGS because Godot's JSON loses
  precision past 2^53 (verified: 9007199254740993 parses back as ...992.0);
  the string↔int64 round-trip is exact and pinned by tests.
- Unknown keys inside known objects are *dropped on next save* (saves are
  engine-owned, unlike content where unknown keys are errors) — but never a
  load failure.
- Content ids in a save (skills, items, activity/recipe ids) are validated
  against `ContentLibrary` at load; a save referencing content that no longer
  exists is a BROKEN save — it falls to the corruption-fallback path
  (surfaced, not guessed at).
- The content `schema_version` the save was written against is recorded as
  `content_schema_version` and compared on load: a mismatch is a diagnostic
  (warned, exposed in `SaveStore.content_drift`), never a load failure.

## Shape (save_version 1 — AS SHIPPED by T3)

T6's per-skill slot model replaced the T2 sketch's single `activity_state`
line (T3 owned the final layout per the T2 hand-off note); `save_version`
stays 1 because no v1 record predates this layout. `engine` is
`PlayerState.to_dict()` verbatim except the RNG stringification.

```jsonc
{
	"save_version": 1,
	"content_schema_version": 1,     // ContentLoader.SCHEMA_VERSION at write time
	"meta": {
		"created_unix": 1760000000,  // first-boot stamp, never rewritten
		"updated_unix": 1760100000,  // last successful save (unix seconds)
		"playtime_s": 5400           // accumulated across sessions
	},
	"anchor_unix_ms": 1760100000123, // offline anchor (wall ms; T6 catch-up base)
	"engine_sim_time_ms": 5400000,   // sim clock the slot anchors live on
	"engine": {                      // PlayerState: xp truth, levels re-derived on load
		"world_seed": 424242,
		"crowns": 250,
		"skills_xp": { "scavenging": 120, "cooking": 15 },  // lifetime totals
		"inventory": { "scrap_metal": 34, "radstag_stew": 3 },
		"active": {                   // one slot per non-combat skill (T6 model)
			"scavenging": {
				"skill_id": "scavenging", "content_id": "sort_scrap_pile",
				"is_recipe": false, "interval_ms": 3000,
				"anchor_ms": 5380000, "completed": 6,
				"rng_seed": "-3750763034362895579",   // STRINGS: exact int64s
				"rng_state": "4822112345678901234",   // (exact offline continuation)
				"stream_started": true
			}
		},
		"combat": {}                  // reserved namespace, passed through for T7
	},
	"settings": { "font_scale": 1.0, "fullscreen": false }  // steps 1.0/1.5/2.0
}
```

## File mechanics (T3-owned, as shipped)

- **Names** under the base dir: `save.json` (primary), `save.json.bak1..bak3`
  (ring; bak1 = newest last-good), `save.json.tmp` (write scratch, never
  read), `save.json.corrupt-<unix-seconds>` (quarantined primaries, kept
  forever for forensics).
- **Atomic write:** serialize → write tmp → `flush()` → `close()` → rotate
  ring → rename tmp over the primary. Godot's FileAccess exposes no `fsync()`
  (ClassDB-verified on 4.7.2), so durability tops out at fflush-to-OS plus an
  atomic same-directory rename: a killed process can never observe a torn
  primary, and power loss degrades to the previous last-good file.
- **Rotation:** chain-rename (bak3 evicted, bak2→bak3, bak1→bak2,
  primary→bak1) — renames preserve mtimes, so ring order equals write order;
  the load walk sorts backups newest-first by mtime with slot-number
  tie-breaks for same-second saves.
- **Load path:** primary → on hard failure (parse/shape/version/content-id)
  rename the primary to `.corrupt-<ts>` (never delete) → walk the ring
  newest-first → all fail → fresh state + `all_saves_corrupt_fresh_state`
  notice. A successful load never writes; the next autosave re-primes the
  primary. Only the primary is ever quarantined; corrupt ring members stay.
- **Offline hand-off:** on load, `TickManager.adopt_state(state,
  engine_sim_time_ms)` then `apply_offline_from_save(anchor_unix_ms)` —
  future-dated anchors yield exactly zero elapsed (T6's clock-regression
  guard). `adopt_state` is the one small T6 API addition T3 made for the
  hand-off (noted in the T3 production-log entry).
- **Cadence:** autosave every 60 s + on the concourse's CLOCK OUT + on
  window close (`Window.close_requested`, the signal form of
  `NOTIFICATION_WM_CLOSE_REQUEST`). Never on crash/teardown — the ring is
  the crash story.
- **First run:** SaveStore owns first-run detection (no record of any kind
  on disk) and drives the concourse's START HERE chalk from it.

## Notice states (T10 renders these — a signal + a flag, never a crash)

`SaveStore.notice == {}` is clean; otherwise `kind` is one of
`primary_corrupt_backup_loaded`, `all_saves_corrupt_fresh_state`,
`refused_newer_save_version` (also sets `save_blocked` — all writes refused
so the newer record is never clobbered), or `save_write_failed`. The
`notice_raised(kind, detail)` signal fires once per raised notice.

## Test isolation (binding)

`SaveStore.base_dir` defaults to `user://` in production and is injectable —
tests boot bare `SaveStore.new()` twins against an OS temp dir and never
enter the tree. The production autoload is additionally DORMANT whenever
`-s` appears in the command line (GUT suites, probes): it loads nothing,
saves nothing, refuses manual writes — the harness can never touch a
player's real record (proven by `tests/test_save.gd`).

## Field notes (carried from T2, still true)

- **No content duplication.** Saves reference content ids; they never copy
  stats/names.
- **XP stored as total per skill**; levels are re-derived on load via
  `XpCurveDef.level_for_total_xp` and never trusted from the file.
- **Combat death state is not saved** — death stops combat (town-hall rule);
  T3/T7 settle the `engine.combat` serialization when T7 lands.
