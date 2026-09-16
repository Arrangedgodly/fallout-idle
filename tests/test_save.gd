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


# ---------------------------------------------------------------------------
# (a) round-trip
# ---------------------------------------------------------------------------

func test_round_trip_deep_equal() -> void:
	var dir := _tmp_dir("roundtrip")
	var tm1: Variant = _make_tm()
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
	assert_eq(int(doc["save_version"]), 1, "save_version 1 on disk")
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

	func _migrate_1_to_2(doc: Dictionary) -> Dictionary:
		doc["save_version"] = 2
		doc["engine"]["stamped_by"] = "1_to_2"
		return doc


func test_migration_hook_walks_ordered_named_functions() -> void:
	var doc := {"save_version": 1, "engine": {"crowns": 5}}
	# Base class: no 1→2 step registered → hard refusal, never a guess.
	var base_store: Variant = SaveStoreScript.new()
	autofree(base_store)
	var missing: Dictionary = base_store._apply_migrations(doc.duplicate(true), 2)
	assert_false(missing["ok"], "unregistered migration step refuses")
	assert_true(String(missing["reason"]).contains("_migrate_1_to_2"), "refusal names the missing step")
	# Subclass: the named, ordered chain runs and stamps.
	var store: Variant = MigratingStore.new()
	autofree(store)
	var walked: Dictionary = store._apply_migrations(doc.duplicate(true), 2)
	assert_true(walked["ok"], "registered migration chain applies")
	var out: Dictionary = walked["doc"]
	assert_eq(int(out["save_version"]), 2, "chain stamps the new version")
	assert_eq(String(out["engine"]["stamped_by"]), "1_to_2", "the named ordered function ran")


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

	assert_true(concourse.chalk_mark.visible, "fresh dir: START HERE chalk shown (SaveStore owns first-run)")
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
