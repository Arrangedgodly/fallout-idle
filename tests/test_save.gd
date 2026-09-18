extends GutTest
## tests/test_save.gd — T3 save system validation (Resilience lane, Hulk's
## lens: everything fails eventually).
##
## Isolation contract (binding, documented in save_store.gd): user:// resolves
## to appdata, NOT the project dir, so every SaveStore here is a bare .new()
## twin booted against an injected OS temp dir and never added to the tree —
## the real user:// is unreachable from this suite. The production autoload
## itself proves DORMANT under the GUT harness (-s script mode) below. Temp
## dirs are deliberately left behind (OS-disposable; recursive DirAccess
## removal hung during T3 fact-checks on this engine build).
##
## Coverage:
##   (a) round-trip: state -> save -> load -> deep-equal (xp/levels/inventory/
##       currency/selections/anchor incl. int64-exact rng streams)
##   (b) kill-mid-write drill: garbage/truncated primary -> backup restores
##       last-good, notice raised, corrupt bytes preserved as .corrupt-<ts>
##   (c) ring consumption: three successive corruptions walk bak1/bak2/bak3;
##       the 4th all-corrupt case -> fresh state + notice; nothing deleted
##   (d) unknown NEWER save_version -> refuse + notice, file byte-untouched,
##       writes blocked (even explicit save-now)
##   (e) offline anchor hand-off: 6 h forward == uninterrupted twin EXACTLY;
##       future-dated (clock-backwards) anchor -> zero elapsed, no MAIL CALL
##   (f) autosave cadence: 3 sim minutes -> one filing per 60 s, spacing >= 55 s
##   (g) atomic write: no scratch leftovers, ring capped at 3, ordered by recency
##   (h) migration hook: ordered named functions, refuses unregistered steps
##   (i) concourse wiring: FILE RECORD -> save + stamped confirmation;
##       CLOCK OUT -> save (quit suppressed by the documented test seam)
##   (j) P0 regression battery (suspended-slot rng serialization — the
##       stringify loop once covered engine.active ONLY, so any record with
##       a posting parked in staffing.suspended bricked on save->reload):
##       parked round-trips deep-equal at v2 AND v3; legacy bare-number
##       fixtures (<2^53 exact, >=2^53 clamped + one-line notice, then a
##       clean re-file cycle); the verifier's exact brick chain
##       v1 -> migrate/park -> re-file -> reload; and the REAL user chain
##       loaded from read-only temp COPIES of the actual user:// records.

const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const ConcourseScene := preload("res://scenes/main.tscn")

const SEED := 20260915
const NOW := 1_769_000_000_000  ## fixed wall moment; no test ever reads the real clock
const SIX_HOURS_MS := 21_600_000
const TICK_MS := 100


# ------------------------------------------------------------------ helpers --

func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (save tests run on live data)")
	return result.library


func _make_tm() -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), SEED)
	return tm


func _make_store(dir: String, tm: Variant, now := NOW) -> Variant:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store._boot(dir, tm, now)
	return store


func _boot_listening(dir: String, tm: Variant, now := NOW) -> Variant:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store.notice_raised.connect(func(kind: String, _detail: Dictionary) -> void:
		noticed.append(kind))
	noticed.clear()
	store._boot(dir, tm, now)
	return store


var noticed: Array = []  ## notices captured by _boot_listening (set pre-boot)


func _pump(tm: Variant, total_ms: int, chunk_ms: int) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _tmp_dir(label: String) -> String:
	return OS.get_temp_dir().path_join("t3_%s_%d_%d" % [
		label, int(Time.get_unix_time_from_system() * 1000.0), randi() % 100000])


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.flush()
	f.close()


## The kill-mid-write simulator: truncated/garbage bytes where a save should be.
const GARBAGE := "{\"save_version\": 1, \"engine\": {\"cr"


func _corrupt(dir: String, file_name: String) -> void:
	_write(dir.path_join(file_name), GARBAGE)


func _files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir():
			out.append(String(fname))
		fname = d.get_next()
	d.list_dir_end()
	return out


func _count_files(dir: String, prefix: String) -> int:
	var n := 0
	for fname in _files(dir):
		if String(fname).begins_with(prefix):
			n += 1
	return n


func _assert_states_equal(a: PlayerState, b: PlayerState, label: String) -> void:
	assert_eq(a.world_seed, b.world_seed, "%s: world seed" % label)
	assert_eq(a.crowns, b.crowns, "%s: crowns" % label)
	assert_eq(a.skills_xp, b.skills_xp, "%s: lifetime xp per skill" % label)
	assert_eq(a.skills_level, b.skills_level, "%s: levels (re-derived, drift-repaired)" % label)
	assert_eq(a.inventory, b.inventory, "%s: inventory" % label)
	assert_eq(a.active.keys().size(), b.active.keys().size(), "%s: same slot count" % label)
	for skill_id in a.active:
		var sa: PlayerState.ActiveSlot = a.active[skill_id]
		var sb: PlayerState.ActiveSlot = b.active.get(skill_id)
		assert_not_null(sb, "%s: slot '%s' restored" % [label, skill_id])
		if sb == null:
			continue
		assert_eq(sa.content_id, sb.content_id, "%s: '%s' content selection" % [label, skill_id])
		assert_eq(sa.is_recipe, sb.is_recipe, "%s: '%s' kind" % [label, skill_id])
		assert_eq(sa.interval_ms, sb.interval_ms, "%s: '%s' interval" % [label, skill_id])
		assert_eq(sa.anchor_ms, sb.anchor_ms, "%s: '%s' anchor (phase remainder)" % [label, skill_id])
		assert_eq(sa.completed, sb.completed, "%s: '%s' completed actions" % [label, skill_id])
		assert_eq(sa.rng_seed, sb.rng_seed, "%s: '%s' rng seed exact (int64 via string)" % [label, skill_id])
		assert_eq(sa.rng_state, sb.rng_state, "%s: '%s' rng state exact (int64 via string)" % [label, skill_id])
		assert_eq(sa.stream_started, sb.stream_started, "%s: '%s' stream positioned" % [label, skill_id])
	assert_eq(int(a.staffing.get("deputies", -1)), int(b.staffing.get("deputies", -1)),
		"%s: staffing deputies (T17 namespace)" % label)
	assert_eq(a.staffing.get("suspended", {}), b.staffing.get("suspended", {}),
		"%s: suspended postings — full parked slots incl. int64-exact rng (T17/P0)" % label)


# ---------------------------------------------------------------------------
# (a) round-trip
# ---------------------------------------------------------------------------

func test_round_trip_deep_equal() -> void:
	var dir := _tmp_dir("roundtrip")
	var tm1: Variant = _make_tm()
	# T17: two concurrent slots need a deputy — staff through the seam.
	tm1.engine.ensure_staffing(tm1.state)
	tm1.state.staffing["deputies"] = 1
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"], "scavenging slot running")
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"], "foraging slot running")
	_pump(tm1, 30_000, 1_000)
	tm1.state.add_item("vintage_snack_cake", 7)
	tm1.state.add_crowns(1234)
	tm1.engine.grant_xp(tm1.state, "cooking", 321)
	var slot_before: PlayerState.ActiveSlot = tm1.state.active["scavenging"]
	assert_true(slot_before.stream_started, "drops rolled → stream positioned (rng state is live)")

	var store: Variant = _make_store(dir, tm1, NOW)
	var res: Dictionary = store.save_now(NOW + 1_000)
	assert_true(res["ok"], "filing succeeds: %s" % str(res))

	# Envelope sanity, straight off the disk.
	var doc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	assert_eq(int(doc["save_version"]), 3, "save_version 3 on disk (T23 objectives format)")
	assert_true(doc["engine"].has("staffing"), "the staffing namespace ships in the engine record")
	assert_true(doc["engine"].has("objectives"), "the objectives namespace ships in the engine record (T23)")
	assert_eq(int(doc["content_schema_version"]), ContentLoader.SCHEMA_VERSION,
		"content schema recorded for drift diagnostics")
	assert_eq(int(doc["anchor_unix_ms"]), NOW + 1_000, "offline anchor is the filing wall moment")
	assert_eq(int(doc["engine_sim_time_ms"]), 30_000, "sim clock continuation stamp persisted")
	assert_true(typeof(doc["engine"]["active"]["scavenging"]["rng_state"]) == TYPE_STRING,
		"rng state ships as a string (int64-exact past the 2^53 JSON cliff)")
	assert_true(doc["meta"].has("created_unix") and int(doc["meta"]["playtime_s"]) >= 0,
		"meta stamps present")

	# Reload into a fresh engine at the SAME wall moment → zero offline gap.
	var tm2: Variant = _make_tm()
	var store2: Variant = _make_store(dir, tm2, NOW + 1_000)
	assert_eq(String(store2.load_report["loaded_from"]), "save.json", "loaded from the primary")
	assert_eq(int(tm2.state.last_mail_call.get("elapsed_ms", -1)), 0, "zero-gap load applies no offline math")
	_assert_states_equal(tm1.state, tm2.state, "round-trip")
	assert_false(store2.first_run, "existing record ⇒ not first run")
	assert_eq(store2.notice, {}, "clean load raises no notice")


# ---------------------------------------------------------------------------
# (b) kill-mid-write drill
# ---------------------------------------------------------------------------

func test_kill_mid_write_restores_from_backup() -> void:
	var dir := _tmp_dir("killmidwrite")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	tm1.state.add_crowns(10)
	assert_true(store.save_now(NOW + 1_000)["ok"], "first record filed (bak1 material)")
	tm1.state.add_crowns(5)  # crowns 15
	assert_true(store.save_now(NOW + 2_000)["ok"], "second record filed (primary material)")
	assert_true(FileAccess.file_exists(dir.path_join("save.json.bak1")), "ring holds the first record")

	_corrupt(dir, "save.json")  # what a torn write leaves behind

	var tm2: Variant = _make_tm()
	var store2: Variant = _boot_listening(dir, tm2, NOW + 2_000)
	# The torn write was record 2; the ring's newest last-good is record 1 (crowns 10).
	assert_eq(int(tm2.state.crowns), 10, "backup ring restored the LAST-GOOD record (crowns 10)")
	assert_eq(String(store2.notice["kind"]), "primary_corrupt_backup_loaded",
		"corruption notice state raised (flag)")
	assert_eq(noticed, ["primary_corrupt_backup_loaded"], "notice signal emitted during load (T10 surface)")
	var detail: Dictionary = store2.notice["detail"]
	assert_eq(String(detail["restored_from"]), "save.json.bak1", "restored from the newest backup")
	var kept_name := String(detail["quarantined"])
	assert_true(kept_name.begins_with("save.json.corrupt-"),
		"corrupt primary preserved as .corrupt-<timestamp>: %s" % kept_name)
	assert_eq(_read(dir.path_join(kept_name)), GARBAGE, "corrupt bytes kept verbatim (forensics, never deleted)")
	assert_true(FileAccess.file_exists(dir.path_join("save.json.bak1")),
		"the backup that saved us is still in place")


# ---------------------------------------------------------------------------
# (c) ring consumption — three corruptions, then all-corrupt fresh
# ---------------------------------------------------------------------------

func test_backup_ring_consumed_by_successive_corruptions() -> void:
	var dir := _tmp_dir("ring")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	# Four filings → full ring: primary=record4 (crowns 400), bak1=300, bak2=200, bak3=100.
	for i in range(4):
		tm1.state.add_crowns(100)
		assert_true(store.save_now(NOW + (i + 1) * 1_000)["ok"], "record %d filed" % (i + 1))
	assert_eq(_count_files(dir, "save.json.bak"), 3, "ring full at three backups")

	# Corruption 1: primary → bak1 (record 3).
	_corrupt(dir, "save.json")
	var tm2: Variant = _make_tm()
	_boot_listening(dir, tm2, NOW + 4_000)
	assert_eq(int(tm2.state.crowns), 300, "1st corruption: newest backup (record 3) restored")

	# Corruption 2: bak1 too → bak2 (record 2).
	_corrupt(dir, "save.json.bak1")
	var tm3: Variant = _make_tm()
	_boot_listening(dir, tm3, NOW + 4_000)
	assert_eq(int(tm3.state.crowns), 200, "2nd corruption: next-newest backup (record 2)")

	# Corruption 3: bak2 too → bak3 (record 1) — the ring's last word.
	_corrupt(dir, "save.json.bak2")
	var tm4: Variant = _make_tm()
	_boot_listening(dir, tm4, NOW + 4_000)
	assert_eq(int(tm4.state.crowns), 100, "3rd corruption: oldest backup (record 1)")

	# Corruption 4: everything → fresh state + corruption notice (a state, not a crash).
	_corrupt(dir, "save.json.bak3")
	var tm5: Variant = _make_tm()
	var store5: Variant = _boot_listening(dir, tm5, NOW + 4_000)
	assert_eq(int(tm5.state.crowns), 0, "4th (all-corrupt): fresh wallet")
	assert_eq(int(tm5.state.skills_xp.size()), 5, "fresh state is a real fresh boot (all skills present)")
	assert_eq(int(tm5.state.skills_xp["scavenging"]), 0, "fresh xp")
	assert_eq(String(store5.notice["kind"]), "all_saves_corrupt_fresh_state",
		"all-corrupt raises the corruption notice state")
	assert_eq(noticed, ["all_saves_corrupt_fresh_state"], "notice emitted once")
	assert_eq(_count_files(dir, "save.json.bak"), 3,
		"corrupt backups are never deleted (forensics — only the primary is quarantined)")


# ---------------------------------------------------------------------------
# (d) unknown newer save_version
# ---------------------------------------------------------------------------

func test_unknown_newer_save_version_refused_and_untouched() -> void:
	var dir := _tmp_dir("newer")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	tm1.state.add_crowns(777)
	assert_true(store.save_now(NOW + 1_000)["ok"], "v1 record filed")
	tm1.state.add_crowns(1)
	assert_true(store.save_now(NOW + 2_000)["ok"], "second filing fills bak1")

	# Rewrite the primary as a well-formed save from a NEWER build.
	var doc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	doc["save_version"] = 99
	_write(dir.path_join("save.json"), JSON.stringify(doc, "\t"))
	var before := _read(dir.path_join("save.json"))
	var bak_before := _read(dir.path_join("save.json.bak1"))

	var tm2: Variant = _make_tm()
	var store2: Variant = _boot_listening(dir, tm2, NOW + 1_000)
	assert_eq(String(store2.notice["kind"]), "refused_newer_save_version", "newer save refuses to load")
	assert_eq(noticed, ["refused_newer_save_version"], "refusal notice emitted")
	assert_true(store2.save_blocked, "writing is blocked — the newer record must never be clobbered")
	assert_eq(int(tm2.state.crowns), 0, "engine continues on fresh state (never the newer data)")
	assert_eq(_read(dir.path_join("save.json")), before, "file untouched, byte for byte")

	# Even an explicit save-now must not overwrite it.
	var res: Dictionary = store2.save_now(NOW + 5_000)
	assert_false(res["ok"], "explicit save refused while blocked")
	assert_eq(_read(dir.path_join("save.json")), before, "still untouched after the refused attempt")
	assert_eq(_count_files(dir, "save.json.corrupt-"), 0,
		"a newer-version save is never quarantined — it is not corrupt")
	assert_eq(_count_files(dir, "save.json.bak"), 1, "backups untouched by the refusal")
	assert_eq(_read(dir.path_join("save.json.bak1")), bak_before, "backup bytes untouched too")


# ---------------------------------------------------------------------------
# (e) offline anchor hand-off (T6 integration)
# ---------------------------------------------------------------------------

func test_offline_anchor_forward_exact_and_backwards_zero() -> void:
	# FORWARDS: save mid-run, 6 h away, load — must equal an uninterrupted twin.
	var dir := _tmp_dir("anchor")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 30_000, 1_000)
	var xp_at_save: int = tm1.state.skills_xp["scavenging"]
	assert_true(xp_at_save > 0, "live progress before the save")
	assert_true(store.save_now(NOW + 1_000)["ok"])

	var tm2: Variant = _make_tm()
	_make_store(dir, tm2, NOW + 1_000 + SIX_HOURS_MS)
	assert_eq(int(tm2.state.last_mail_call.get("elapsed_ms", -1)), SIX_HOURS_MS,
		"the full away gap was handed to the engine from the saved anchor")
	assert_true(int(tm2.state.skills_xp["scavenging"]) > xp_at_save, "offline xp granted through the anchor")

	# The uninterrupted twin: same seed, same start, 30 s live + 6 h closed form.
	var twin: Variant = _make_tm()
	assert_true(twin.start_activity("sort_scrap_pile")["ok"])
	_pump(twin, 30_000, 1_000)
	twin.apply_offline_elapsed(SIX_HOURS_MS)
	assert_eq(tm2.state.skills_xp, twin.state.skills_xp,
		"save/load/offline continuation == uninterrupted twin (xp)")
	assert_eq(tm2.state.inventory, twin.state.inventory, "... inventory")
	assert_eq(tm2.state.active["scavenging"].completed, twin.state.active["scavenging"].completed,
		"... completed action count")
	assert_eq(tm2.state.active["scavenging"].anchor_ms, twin.state.active["scavenging"].anchor_ms,
		"... anchor phase remainder")

	# BACKWARDS: a future-dated anchor loads fine with exactly zero elapsed.
	var dir2 := _tmp_dir("anchorback")
	var tm3: Variant = _make_tm()
	var store3: Variant = _make_store(dir2, tm3, NOW + 1_000)
	assert_true(tm3.start_activity("sort_scrap_pile")["ok"])
	_pump(tm3, 30_000, 1_000)
	assert_true(store3.save_now(NOW + 1_000)["ok"])
	var tm4: Variant = _make_tm()
	var mail_calls: Array = []
	tm4.mail_call_ready.connect(func(_payload: Dictionary) -> void: mail_calls.append(1))
	_make_store(dir2, tm4, NOW - 60_000)  # the wall clock went BACKWARDS past the anchor
	assert_eq(int(tm4.state.last_mail_call.get("elapsed_ms", -1)), 0, "future-dated anchor → zero elapsed")
	assert_eq(mail_calls.size(), 0, "no MAIL CALL for a backwards clock")
	_assert_states_equal(tm3.state, tm4.state, "clock-backwards")


# ---------------------------------------------------------------------------
# (f) autosave cadence
# ---------------------------------------------------------------------------

func test_autosave_cadence_no_spam() -> void:
	var dir := _tmp_dir("cadence")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	var stamps: Array = []
	store.save_completed.connect(func(result: Dictionary) -> void: stamps.append(int(result["unix_ms"])))
	# Three simulated minutes, one cadence check per second.
	var t := NOW
	while t < NOW + 3 * 60_000:
		t += 1_000
		store._autosave_tick(t)
	assert_true(stamps.size() >= 2, "at least 2 autosaves within 3 sim minutes (got %d)" % stamps.size())
	assert_eq(stamps.size(), 3, "exactly one filing per 60 s cadence")
	for i in range(1, stamps.size()):
		var gap: int = int(stamps[i]) - int(stamps[i - 1])
		assert_true(gap >= 55_000, "autosave spacing %d ms ≥ 55 s (no spam)" % gap)
	assert_eq(_count_files(dir, "save.json.bak"), 2, "ring grew by exactly the autosaves (primary + 2 backups)")


# ---------------------------------------------------------------------------
# (g) atomic write discipline
# ---------------------------------------------------------------------------

func test_atomic_write_rotates_without_temp_leftovers() -> void:
	var dir := _tmp_dir("atomic")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	for i in range(5):
		tm1.state.add_crowns(100)
		assert_true(store.save_now(NOW + (i + 1) * 1_000)["ok"], "filing %d ok" % (i + 1))
	assert_false(FileAccess.file_exists(dir.path_join("save.json.tmp")),
		"no scratch file left behind (tmp is renamed into place, never abandoned)")
	assert_eq(_count_files(dir, "save.json.bak"), 3, "ring capped at three backups after five filings")
	# Recency order: primary = record 5, bak1 = 4, bak2 = 3, bak3 = 2.
	assert_eq(int(JSON.parse_string(_read(dir.path_join("save.json")))["engine"]["crowns"]), 500, "primary holds the newest")
	assert_eq(int(JSON.parse_string(_read(dir.path_join("save.json.bak1")))["engine"]["crowns"]), 400, "bak1 = previous")
	assert_eq(int(JSON.parse_string(_read(dir.path_join("save.json.bak2")))["engine"]["crowns"]), 300, "bak2 = before that")
	assert_eq(int(JSON.parse_string(_read(dir.path_join("save.json.bak3")))["engine"]["crowns"]), 200, "bak3 = oldest kept")


# ---------------------------------------------------------------------------
# (h) migration hook
# ---------------------------------------------------------------------------

class MigratingStore:
	extends "res://scripts/autoload/save_store.gd"

	# T17 registered 1→2 and T23 registered 2→3, so the hook drill walks the
	# NEXT hypothetical step (3→4) — same proof, live edge moved forward.
	func _migrate_3_to_4(doc: Dictionary) -> Dictionary:
		doc["save_version"] = 4
		doc["engine"]["stamped_by"] = "3_to_4"
		return doc


func test_migration_hook_walks_ordered_named_functions() -> void:
	var doc := {"save_version": 3, "engine": {"crowns": 5}}
	# Base class: no 3→4 step registered → hard refusal, never a guess.
	var base_store: Variant = SaveStoreScript.new()
	autofree(base_store)
	var missing: Dictionary = base_store._apply_migrations(doc.duplicate(true), 4)
	assert_false(missing["ok"], "unregistered migration step refuses")
	assert_true(String(missing["reason"]).contains("_migrate_3_to_4"), "refusal names the missing step")
	# Subclass: the named, ordered chain runs and stamps.
	var store: Variant = MigratingStore.new()
	autofree(store)
	var walked: Dictionary = store._apply_migrations(doc.duplicate(true), 4)
	assert_true(walked["ok"], "registered migration chain applies")
	var out: Dictionary = walked["doc"]
	assert_eq(int(out["save_version"]), 4, "chain stamps the new version")
	assert_eq(String(out["engine"]["stamped_by"]), "3_to_4", "the named ordered function ran")


## T17: the PRODUCTION v1→v2 step — pure transform, seeds staffing, stamps 2.
func test_production_migration_1_to_2_seeds_staffing() -> void:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	var v1 := {
		"save_version": 1,
		"engine": {"crowns": 5, "active": {"scavenging": {"skill_id": "scavenging"}}},
	}
	var walked: Dictionary = store._apply_migrations(v1.duplicate(true), 2)
	assert_true(walked["ok"], "production 1→2 chain applies")
	var out: Dictionary = walked["doc"]
	assert_eq(int(out["save_version"]), 2, "stamps save_version 2")
	var staffing: Dictionary = out["engine"]["staffing"]
	assert_eq(int(staffing["deputies"]), 0, "v1 players gain 0 deputies (one posting)")
	assert_eq(staffing["suspended"], {}, "no suspended postings at migration time")
	# Untouched pass-throughs: the migration changes shape, never progress.
	assert_eq(int(out["engine"]["crowns"]), 5, "crowns untouched")
	assert_true(out["engine"]["active"].has("scavenging"), "active slots untouched (enforcement is load-time engine state)")


# ---------------------------------------------------------------------------
# (j) P0 regression — suspended-slot rng serialization + legacy repair
# ---------------------------------------------------------------------------

## The brick-scenario prologue: a v1 record carrying TWO running postings
## (written with a deputy so both start legally, then rewritten as an honest
## v1 — no staffing namespace, exactly the pre-T17 player's file).
func _write_v1_two_posting_record(dir: String, tm: Variant) -> void:
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = 1
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"], "foraging posted first (will park)")
	_pump(tm, 15_000, 1_000)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "scavenging posted last (newest — survives)")
	_pump(tm, 15_000, 1_000)
	var stream: PlayerState.ActiveSlot = tm.state.active["foraging"]
	assert_true(stream.stream_started, "the foraging rng stream is positioned (live int64 state)")
	assert_true(maxi(absi(stream.rng_seed), absi(stream.rng_state)) >= 9007199254740992,
		"the parked rng magnitudes cross the 2^53 JSON cliff (deterministic under the fixed SEED)")
	var store: Variant = _make_store(dir, tm, NOW)
	assert_true(store.save_now(NOW)["ok"], "v3 record filed (rewrite material)")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(_read(path))
	doc["save_version"] = 1
	doc["engine"].erase("staffing")
	_write(path, JSON.stringify(doc, "\t"))


## (c) The verifier's exact brick scenario, reproduced then green: v1 record
## with two postings -> migration parks the older -> re-file -> RELOAD. At
## HEAD the re-filed primary shipped parked rng as bare >= 2^53 numbers and
## its own next boot rejected primary AND ring (all_saves_corrupt_fresh_state).
func test_p0_verifier_brick_scenario_parked_record_reloads_green() -> void:
	var dir := _tmp_dir("p0brick")
	var tm1: Variant = _make_tm()
	_write_v1_two_posting_record(dir, tm1)

	# Boot 1: the v1 record migrates up; enforce_staffing parks foraging with
	# its full slot state (parking was never the bug — the FORM was).
	var tm2: Variant = _make_tm()
	var store2: Variant = _make_store(dir, tm2, NOW)
	assert_eq(String(store2.load_report["loaded_from"]), "save.json", "v1 record loads (migrated)")
	assert_eq(tm2.state.active.keys(), ["scavenging"], "the newest posting survives")
	assert_eq((tm2.state.staffing["suspended"] as Dictionary).keys(), ["foraging"],
		"the older posting parks")
	assert_true(store2.save_now(NOW + 1_000)["ok"], "the parked record re-files")

	# The P0 fix itself: the re-filed primary ships parked rng as STRINGS.
	var redoc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	var reparked: Dictionary = redoc["engine"]["staffing"]["suspended"]["foraging"]
	assert_true(typeof(reparked["rng_seed"]) == TYPE_STRING and typeof(reparked["rng_state"]) == TYPE_STRING,
		"parked rng ships as strings (bare >= 2^53 numbers are what bricked the chain)")

	# Boot 2 — THE BRICK: at HEAD this reload rejected everything; green now.
	var tm3: Variant = _make_tm()
	var store3: Variant = _make_store(dir, tm3, NOW + 1_000)
	assert_eq(String(store3.load_report["loaded_from"]), "save.json",
		"the parked record's own next load succeeds (the exact brick scenario)")
	assert_eq(store3.notice, {}, "no rejection, no notice")
	assert_eq(_count_files(dir, "save.json.corrupt-"), 0, "nothing quarantined")
	assert_eq(tm2.state.staffing["suspended"], tm3.state.staffing["suspended"],
		"the parked posting round-trips bit-exact (int64s via strings)")


## (a) A record carrying a parked posting round-trips deep-equal at v3 AND
## at v2 (the same engine payload stamped as an honest v2 — no objectives
## namespace — loaded through the registered 2->3 migration).
func test_p0_parked_posting_round_trip_v3_and_v2_deep_equal() -> void:
	var dir := _tmp_dir("p0rt")
	var tm1: Variant = _make_tm()
	_write_v1_two_posting_record(dir, tm1)
	var tm2: Variant = _make_tm()
	var store2: Variant = _make_store(dir, tm2, NOW)
	assert_true(store2.save_now(NOW + 1_000)["ok"], "genuine v3 record with a parked posting filed")

	# v3 round-trip: deep-equal, no rejection.
	var tm3: Variant = _make_tm()
	var store3: Variant = _make_store(dir, tm3, NOW + 1_000)
	assert_eq(String(store3.load_report["loaded_from"]), "save.json", "v3 parked record loads from the primary")
	assert_eq(store3.notice, {}, "clean v3 round-trip")
	_assert_states_equal(tm2.state, tm3.state, "parked v3 round-trip")

	# v2 round-trip: same parked payload through the v2 form.
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(_read(path))
	doc["save_version"] = 2
	doc["engine"].erase("objectives")
	_write(path, JSON.stringify(doc, "\t"))
	var tm4: Variant = _make_tm()
	var store4: Variant = _make_store(dir, tm4, NOW + 1_000)
	assert_eq(String(store4.load_report["loaded_from"]), "save.json", "v2 parked record loads (migrated 2->3)")
	assert_eq(store4.notice, {}, "clean v2 round-trip")
	assert_eq(tm2.state.staffing["suspended"], tm4.state.staffing["suspended"],
		"parked slot deep-equal through the v2 form (rng strings)")
	assert_eq(tm2.state.active.keys(), tm4.state.active.keys(), "active selections survive the v2 form")
	assert_eq(_count_files(dir, "save.json.corrupt-"), 0, "no quarantine in either direction")


## A parked-slot dict in the LEGACY bare-number shape — int Variants, which
## JSON.stringify writes as bare JSON integers (the pre-fix writer's exact
## output; magnitudes mirror the user's real chain: FNV seed ~-5.4e17, PCG
## state ~4.0e18).
func _parked_slot(skill_id: String, content_id: String, rng_seed: int, rng_state: int) -> Dictionary:
	return {
		"skill_id": skill_id, "content_id": content_id, "is_recipe": false,
		"interval_ms": 3000, "anchor_ms": 614400, "completed": 28,
		"rng_seed": rng_seed, "rng_state": rng_state, "stream_started": true,
	}


## (b) Legacy bare-number fixtures: < 2^53 coerces EXACTLY, >= 2^53 clamps
## to the exact-representable bound with a one-line notice in the loaded
## state, and the repaired state re-files clean (notice drops after one
## cycle). No other leniency — nothing here is treated as corrupt.
func test_p0_legacy_bare_number_rng_exact_clamped_and_notice() -> void:
	var dir := _tmp_dir("p0legacy")
	var tm: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm, NOW)
	assert_true(store.save_now(NOW)["ok"], "clean v3 record filed (fixture material)")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(_read(path))
	doc["engine"]["staffing"] = {
		"deputies": 0,
		"suspended": {
			"foraging": _parked_slot("foraging", "walk_the_glow_rows", 987654321, 3954541915971306884),
			"scavenging": _parked_slot("scavenging", "sort_scrap_pile", -544270122476930938, 12345678901),
		},
	}
	_write(path, JSON.stringify(doc, "\t"))
	var text := _read(path)
	assert_true(text.contains("\"rng_state\": 3954541915971306884")
			and not text.contains("\"rng_state\": \"3954541915971306884\""),
		"the fixture truly ships parked rng as bare JSON numbers (the legacy shape)")

	var tm2: Variant = _make_tm()
	var store2: Variant = _make_store(dir, tm2, NOW + 1_000)
	assert_eq(String(store2.load_report["loaded_from"]), "save.json",
		"legacy bare-number record LOADS (repair, not rejection — at HEAD this was the brick)")
	assert_eq(store2.notice, {}, "the repair is a state field, not a corruption notice")
	var suspended: Dictionary = tm2.state.staffing["suspended"]
	assert_eq(int(suspended["foraging"]["rng_seed"]), 987654321, "< 2^53 bare number coerces EXACTLY")
	assert_eq(int(suspended["foraging"]["rng_state"]), 9007199254740991,
		">= 2^53 clamps to the exact-representable bound (the true int64 is unrecoverable post-parse)")
	assert_eq(int(suspended["scavenging"]["rng_seed"]), -9007199254740991,
		"negative past the cliff clamps to the negative bound")
	assert_eq(int(suspended["scavenging"]["rng_state"]), 12345678901, "state under the cliff exact")
	assert_true(tm2.state.staffing.has("rng_legacy_clamped"), "the one-line repair notice rides the loaded state")
	var notice_line := String(tm2.state.staffing["rng_legacy_clamped"])
	assert_true(notice_line.contains("foraging.rng_state") and notice_line.contains("scavenging.rng_seed"),
		"the notice names exactly the clamped fields: %s" % notice_line)
	assert_false(notice_line.contains("foraging.rng_seed") or notice_line.contains("scavenging.rng_state"),
		"exact-coerced fields are NOT flagged (no overclaiming)")

	# The repair cycle: re-file writes clean strings; the transient notice
	# drops out of the hydrated namespace on the next load.
	assert_true(store2.save_now(NOW + 2_000)["ok"], "the repaired state re-files")
	var redoc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	assert_true(typeof(redoc["engine"]["staffing"]["suspended"]["foraging"]["rng_state"]) == TYPE_STRING,
		"the re-filed parked rng is a string now")
	assert_eq(str(redoc["engine"]["staffing"]["suspended"]["foraging"]["rng_state"]), "9007199254740991",
		"the clamped position re-files exactly")
	var tm3: Variant = _make_tm()
	var store3: Variant = _make_store(dir, tm3, NOW + 2_000)
	assert_eq(String(store3.load_report["loaded_from"]), "save.json", "the repaired record reloads clean")
	assert_false(tm3.state.staffing.has("rng_legacy_clamped"),
		"the transient notice drops once the record re-files as strings")
	assert_eq(int(tm3.state.staffing["suspended"]["foraging"]["rng_state"]), 9007199254740991,
		"the clamped position is stable across the repair cycle")


## (d) The REAL user chain: read-only COPIES of the actual user:// records
## (the live primary + the 3-slot ring + the quarantined predecessor) load
## green through the tolerant loader. T31 RE-PIN (run 5): the assertions are
## STRUCTURAL, keyed to each record's OWN parsed contents — identity (the
## loaded active/suspended/xp state equals the file's), load mechanics
## (newest-good wins, ring walk lands on bak1, repair cycle), and shape
## sanity (orientation/suspended/active well-typed) — never stale literals.
## The user's save advances every session; a pinned action count or a pinned
## legacy-rng shape would fail the day after it was written (proven
## environmental at T30: bak1 completed=58865 vs the T28-era 10237 pin).
## Binding discipline: no store EVER points at the real user:// — every load
## runs against an OS temp copy — and the test pins byte-equality of the
## real files before/after as the read-only proof. The chain is
## machine-local evidence; where it is absent the test passes with an
## explicit marker (nothing to pin elsewhere).
func test_p0_real_user_chain_loads_from_read_only_temp_copy() -> void:
	var user_dir := ProjectSettings.globalize_path("user://")
	var chain := [
		"save.json",                     # the live primary (the newest record)
		"save.json.bak1", "save.json.bak2", "save.json.bak3",
		"save.json.corrupt-1789605304",  # the quarantined P0-era primary
	]
	for fname in chain:
		if not FileAccess.file_exists(user_dir.path_join(String(fname))):
			assert_true(true, "real user chain absent on this machine — the copy proof only runs where it exists")
			return
	var bytes_before := {}
	var docs := {}
	for fname in chain:
		bytes_before[String(fname)] = _read(user_dir.path_join(String(fname)))
		docs[String(fname)] = JSON.parse_string(bytes_before[String(fname)])
		assert_true(docs[String(fname)] is Dictionary, "%s parses (the chain is loadable evidence)" % fname)

	# Each record alone, as the primary of its own temp base dir: the loaded
	# state equals THE FILE'S OWN contents (identity, not literals).
	for fname in chain:
		var doc: Dictionary = docs[String(fname)]
		var solo := _tmp_dir("p0usersolo")
		DirAccess.make_dir_recursive_absolute(solo)
		DirAccess.copy_absolute(user_dir.path_join(String(fname)), solo.path_join("save.json"))
		var tm: Variant = _make_tm()
		var store: Variant = _make_store(solo, tm, NOW)
		assert_eq(String(store.load_report["loaded_from"]), "save.json",
			"%s loads as its own primary through the tolerant loader" % fname)
		assert_eq(store.notice, {}, "%s: clean load — repair, not a corruption event" % fname)
		# Active identity: every skill the file runs, loaded with its own
		# content id and its own completed count (a zero-gap load never moves
		# completed).
		var doc_active: Dictionary = doc["engine"]["active"]
		assert_eq(tm.state.active.keys().size(), doc_active.keys().size(),
			"%s: the file's own active slots landed" % fname)
		for skill_id in doc_active:
			assert_true(tm.state.active.has(String(skill_id)),
				"%s: active %s landed" % [fname, skill_id])
			assert_eq(str(tm.state.active[String(skill_id)].get("content_id")),
				str(doc_active[skill_id]["content_id"]),
				"%s: %s runs its own posting" % [fname, skill_id])
			assert_eq(int(tm.state.active[String(skill_id)].get("completed")),
				int(doc_active[skill_id]["completed"]),
				"%s: %s keeps its own completed count (identity, %d)" % [
					fname, skill_id, int(doc_active[skill_id]["completed"])])
		# XP: file value + exactly the mail payload's settle legs (a zero-gap
		# load still settles pending objective stamps — reward legs ride the
		# payload, so the sum pins attribution without pinning amounts).
		var doc_xp: Dictionary = doc["engine"]["skills_xp"]
		for skill_id in doc_xp:
			var gain := int((tm.state.last_mail_call.get("skills_xp", {}) as Dictionary).get(String(skill_id), 0))
			assert_eq(int(tm.state.skills_xp[String(skill_id)]), int(doc_xp[skill_id]) + gain,
				"%s: %s xp == file xp + exactly the settle leg" % [fname, skill_id])
		assert_eq(int(tm.state.last_mail_call.get("elapsed_ms", -1)), 0,
			"%s: zero away gap — nothing but the settle ran" % fname)
		# Orientation shape: the file's own step list, valid ids, sane bounds.
		var doc_steps: Array = doc["engine"].get("orientation", {}).get("steps_done", [])
		var loaded_steps: Array = tm.state.orientation.get("steps_done", [])
		assert_eq(loaded_steps, doc_steps, "%s: the form carries its own stamps" % fname)
		assert_true(loaded_steps.size() <= 7, "%s: step count within the form's 7 rows" % fname)
		for sid in loaded_steps:
			assert_true(OrientationTracker.STEPS.has(str(sid)),
				"%s: step id '%s' is a real form row" % [fname, sid])
		# Suspended shape + rng form: parked postings keep their own record;
		# string rng loads EXACTLY, legacy bare numbers (the pre-P0 shape)
		# clamp to the exact-representable bound with the one-line repair
		# notice — and the notice appears IFF the record actually shipped
		# legacy fields.
		var doc_susp: Dictionary = doc["engine"]["staffing"]["suspended"]
		var loaded_susp: Dictionary = tm.state.staffing["suspended"]
		assert_eq(loaded_susp.keys().size(), doc_susp.keys().size(),
			"%s: parked postings exactly as the file holds" % fname)
		var legacy := false
		for skill_id in doc_susp:
			assert_true(loaded_susp.has(String(skill_id)),
				"%s: %s stays parked" % [fname, skill_id])
			var parked: Dictionary = loaded_susp[String(skill_id)]
			var doc_slot: Dictionary = doc_susp[skill_id]
			assert_eq(str(parked.get("content_id")), str(doc_slot.get("content_id")),
				"%s: parked %s keeps its selection" % [fname, skill_id])
			assert_eq(int(parked.get("completed")), int(doc_slot.get("completed")),
				"%s: parked %s keeps its own completed" % [fname, skill_id])
			for rng_key in ["rng_seed", "rng_state"]:
				var rv: Variant = doc_slot.get(rng_key)
				if rv is String:
					assert_eq(int(parked[rng_key]), int(str(rv)),
						"%s: parked %s.%s loads EXACTLY through the string form" % [fname, skill_id, rng_key])
				else:
					legacy = true
					var f := float(rv)
					# INT arithmetic for the bound: the FLOAT literal
					# 9007199254740991.0 rounds to ...990 in GDScript — the
					# loader clamps to the int bound ±(2^53−1) exactly.
					var expected := int(f) if absf(f) < 9007199254740992.0 \
						else int(signf(f)) * 9007199254740991
					assert_eq(int(parked[rng_key]), expected,
						"%s: parked %s.%s coerces (clamped past the 2^53 cliff)" % [fname, skill_id, rng_key])
		assert_eq(tm.state.staffing.has("rng_legacy_clamped"), legacy,
			"%s: the repair notice posts exactly when legacy bare rng shipped" % fname)
		assert_eq(int(tm.state.staffing["deputies"]), int(doc["engine"]["staffing"]["deputies"]),
			"%s: the establishment size is the file's own" % fname)

	# The whole chain in one base dir (primary + ring): newest-good wins —
	# the live primary IS the newest record, and the walk takes it.
	var together := _tmp_dir("p0userchain")
	DirAccess.make_dir_recursive_absolute(together)
	for bak in ["save.json.bak3", "save.json.bak2", "save.json.bak1"]:  # oldest first: copy order == mtime order
		DirAccess.copy_absolute(user_dir.path_join(bak), together.path_join(bak))
	DirAccess.copy_absolute(user_dir.path_join("save.json"), together.path_join("save.json"))
	var tm_c: Variant = _make_tm()
	var store_c: Variant = _make_store(together, tm_c, NOW)
	assert_eq(String(store_c.load_report["loaded_from"]), "save.json",
		"newest-good wins: the live primary loads, not a ring fallback")
	var primary_doc: Dictionary = docs["save.json"]
	for skill_id in primary_doc["engine"]["active"]:
		assert_eq(int(tm_c.state.active[String(skill_id)].get("completed")),
			int(primary_doc["engine"]["active"][skill_id]["completed"]),
			"the primary's OWN record landed (identity, not a ring member)")
	assert_eq(_count_files(together, "save.json.corrupt-"), 0, "no new quarantine in the temp copy")

	# Ring-only (primary removed from the TEMP copy): bak1 is the newest
	# last-good and wins the walk — carrying ITS OWN record.
	DirAccess.remove_absolute(together.path_join("save.json"))
	var tm_b: Variant = _make_tm()
	var store_b: Variant = _make_store(together, tm_b, NOW)
	assert_eq(String(store_b.load_report["loaded_from"]), "save.json.bak1",
		"ring walk lands on bak1 (newest last-good)")
	var bak1_doc: Dictionary = docs["save.json.bak1"]
	for skill_id in bak1_doc["engine"]["active"]:
		assert_eq(int(tm_b.state.active[String(skill_id)].get("completed")),
			int(bak1_doc["engine"]["active"][skill_id]["completed"]),
			"bak1's OWN record landed (identity, not the primary's)")

	# The repair cycle on a solo copy of the quarantined P0-era record:
	# load -> re-file -> reload clean; a legacy bare-number record re-files
	# as clean strings (the transient notice drops after one cycle).
	var repaired := _tmp_dir("p0userrepair")
	DirAccess.make_dir_recursive_absolute(repaired)
	DirAccess.copy_absolute(user_dir.path_join("save.json.corrupt-1789605304"), repaired.path_join("save.json"))
	var tm_x: Variant = _make_tm()
	var store_x: Variant = _make_store(repaired, tm_x, NOW)
	assert_true(store_x.save_now(NOW + 1_000)["ok"], "the loaded record re-files (in the temp copy)")
	var corrupt_doc: Dictionary = docs["save.json.corrupt-1789605304"]
	var corrupt_legacy := false
	for skill_id in corrupt_doc["engine"]["staffing"]["suspended"]:
		for rng_key in ["rng_seed", "rng_state"]:
			if not (corrupt_doc["engine"]["staffing"]["suspended"][skill_id][rng_key] is String):
				corrupt_legacy = true
	var refiled_doc: Dictionary = JSON.parse_string(_read(repaired.path_join("save.json")))
	if corrupt_legacy:
		assert_true(typeof(refiled_doc["engine"]["staffing"]["suspended"]["foraging"]["rng_state"]) == TYPE_STRING,
			"the re-filed parked rng is a clean string (legacy shape repaired)")
	var tm_y: Variant = _make_tm()
	var store_y: Variant = _make_store(repaired, tm_y, NOW + 1_000)
	assert_eq(String(store_y.load_report["loaded_from"]), "save.json", "the re-filed record reloads clean")
	assert_false(tm_y.state.staffing.has("rng_legacy_clamped"),
		"the transient notice is gone after one clean re-file")

	# The read-only proof: the real dir is byte-identical after everything
	# (copies only; the .corrupt quarantine itself is deliberately left as-is).
	for fname in chain:
		assert_eq(_read(user_dir.path_join(String(fname))), bytes_before[String(fname)],
			"real file %s untouched — copy, never move" % fname)


# ---------------------------------------------------------------------------
# (i) concourse wiring (T9 stubs → SaveStore)
# ---------------------------------------------------------------------------

func test_concourse_save_and_quit_controls_wired() -> void:
	var dir := _tmp_dir("concourse")
	var tm: Variant = _make_tm()
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store.quit_after_save = false  # documented test seam: verify the filing, don't kill the runner
	store._boot(dir, tm, NOW)

	var concourse: Control = ConcourseScene.instantiate()
	autofree(concourse)
	add_child(concourse)
	store.connect_concourse(concourse)
	await get_tree().process_frame  # first-run application is deferred past _ready

	assert_true(concourse.orientation_form != null and concourse.orientation_form.visible
			and concourse.orientation_form.is_expanded(),
		"fresh dir: ORIENTATION FORM O-1 posted expanded (SaveStore owns first-run)")
	var saves: Array = []
	store.save_completed.connect(func(_result: Dictionary) -> void: saves.append(1))

	# FILE RECORD → SaveStore.save_now() + stamped confirmation.
	concourse.save_button.pressed.emit()
	assert_eq(saves.size(), 1, "FILE RECORD files a record through SaveStore")
	assert_true(FileAccess.file_exists(dir.path_join("save.json")), "record on disk in the injected dir")
	assert_true(concourse.console_serial.text.begins_with("RECORD FILED"),
		"stamped confirmation on the console serial: %s" % concourse.console_serial.text)

	# CLOCK OUT → save, then quit (quit suppressed by the seam here).
	concourse.quit_button.pressed.emit()
	assert_eq(saves.size(), 2, "CLOCK OUT files the record before departure")
	assert_eq(int(JSON.parse_string(_read(dir.path_join("save.json")))["engine"]["crowns"]), 0,
		"the departed record round-trips the engine state")

	await get_tree().create_timer(2.1).timeout  # let the serial flash revert before teardown


# ---------------------------------------------------------------------------
# isolation + dormancy
# ---------------------------------------------------------------------------

func test_temp_base_dir_isolation_and_autoload_dormancy() -> void:
	var dir := _tmp_dir("isolation")
	var tm1: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm1, NOW)
	assert_true(store.save_now(NOW + 1_000)["ok"])
	assert_true(FileAccess.file_exists(dir.path_join("save.json")), "record lives in the injected dir")
	assert_eq(String(store.base_dir), dir, "base dir is the injected one (default user:// is production-only)")

	# The REAL autoload is dormant under the GUT harness (-s in cmdline args).
	assert_true(SaveStore.is_dormant(), "production SaveStore autoload dormant under -s (never touches user://)")
	assert_eq(String(SaveStore.base_dir), "user://", "production default base dir unchanged")
	var blocked: Dictionary = SaveStore.save_now(NOW)
	assert_false(blocked["ok"], "dormant autoload refuses to write (belt to the brace)")
