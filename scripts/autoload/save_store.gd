extends Node
## SaveStore — T3 autoload: atomic, versioned, ring-backed JSON saves.
## (Resilience lane, Hulk's lens: every disk assumption here is assumed
## breakable and handled; Iron Man's architecture: one owner, clear seams.)
##
## WHAT THIS OWNS (docs/save-schema.md — everything below its T2 line):
##   • files under base_dir (default user://):
##       save.json                  primary slot (the live record)
##       save.json.bak1..bak3       backup ring (bak1 = most recent last-good)
##       save.json.tmp              write scratch (renamed into place, never read)
##       save.json.corrupt-<unix>   quarantined primaries (forensics, kept)
##   • atomic write: serialize -> write tmp -> flush -> close -> rotate ring ->
##     rename tmp over the primary. Godot's FileAccess exposes flush() but NO
##     fsync() (ClassDB-verified this build), so the durability ceiling is
##     fflush-to-OS + atomic same-directory rename: a killed process can never
##     observe a torn primary (the rename is atomic), and a machine power loss
##     degrades to the previous last-good file — never garbage.
##   • save_version migrations: ordered, named `_migrate_<n>_to_<n+1>` chain
##     (v1 is current; a save loads only after reaching SAVE_VERSION).
##   • load path: primary -> quarantine on hard failure -> backup ring
##     newest-first by mtime -> fresh state + corruption NOTICE (a signal + a
##     flag — never a crash). Corrupt files are NEVER deleted: the primary is
##     renamed to save.json.corrupt-<unix-timestamp> for forensics; corrupt
##     ring members are left in place.
##   • content-drift diagnostics: the content schema_version the save was
##     written against is recorded in the save and compared on load (warned +
##     exposed in `content_drift`, non-fatal — the load-time CONTENT-ID
##     VALIDATION is what actually protects the player).
##   • cadence: autosave every 60 s, save on window close and on the
##     concourse's CLOCK OUT. NO save on crash/teardown — the ring is the
##     crash story, and a half-dead process must never touch the disk.
##
## OFFLINE HAND-OFF (T6 contract): every save stamps `anchor_unix_ms` (the
## wall moment the record was filed) plus `engine_sim_time_ms` (the sim clock
## the slot anchors live on). On load, TickManager.adopt_state() resumes the
## state + clock, then apply_offline_from_save(anchor) runs T6's closed-form
## catch-up — future-dated anchors yield exactly zero (T6's guard, pinned by
## tests/test_save.gd).
##
## RNG PRECISION (binding T6 note): slot rng_seed/rng_state are exact int64s;
## Godot's JSON silently loses precision past 2^53 (verified: 9007199254740993
## parses back as ...992.0), so both ship as STRINGS. int() accepts the string
## form on the way back in; the round-trip is bit-exact (pinned by tests).
##
## INJECTABILITY (test isolation — binding): base_dir defaults to user:// for
## production; tests inject an absolute OS temp dir and call _boot() on a bare
## SaveStore.new() that never enters the tree (so _ready/dormancy never run).
## The production autoload additionally stays DORMANT under script mode
## (`-s` in cmdline args — GUT suites and probes) so the real user:// is never
## read or written by the harness; user:// resolves to appdata, NOT the
## project dir, which is exactly why the injection seam exists.
##
## NOTICE STATES (T10 renders these; flags + one signal, never crashes):
##   notice == {}                       — nothing to report
##   "primary_corrupt_backup_loaded"    — primary quarantined, a backup loaded
##   "all_saves_corrupt_fresh_state"    — primary + whole ring unusable
##   "refused_newer_save_version"       — save from a NEWER build: load
##                                        refused, ALL writing blocked, the
##                                        file never touched; fresh state so
##                                        play can continue
##   "save_write_failed"                — a filing attempt failed (disk etc.)

signal save_completed(result: Dictionary)
## result: {"ok": bool, "reason": String, "unix_ms": int}
signal notice_raised(kind: String, detail: Dictionary)

const SAVE_VERSION := 1
const SAVE_NAME := "save.json"
const TMP_NAME := "save.json.tmp"
const BACKUP_SLOTS := 3
const AUTOSAVE_INTERVAL_MS := 60_000
const FONT_SCALE_STEPS := [1.0, 1.5, 2.0]  # mirrors UiTheme (T8/T15 contract)
## Content schema at write time — separate namespace from save_version (R1).

var base_dir := "user://"
var first_run := true  ## true only when NO save file of any kind exists
var notice: Dictionary = {}  ## {} = clean; else {"kind": ..., "detail": ...}
var save_blocked := false  ## true while an on-disk newer-version save must not be clobbered
var content_drift: Dictionary = {}  ## {"saved": n, "current": n} when mismatched
var load_report: Dictionary = {}  ## last load's audit trail (attempts, slot)
var last_save_unix_ms := 0
var quit_after_save := true  ## CLOCK OUT test seam: verify the save, skip the quit

var _tm = null  ## TickManager (autoload in production, fresh twin in tests)
var _dormant := false
var _created_unix := 0  ## meta stamp, never rewritten after the first save
var _playtime_s := 0
var _session_boot_unix_ms := 0
var _last_autosave_ms := 0


func _ready() -> void:
	# Script mode (-s: GUT suites, probes) must never touch the real user:// —
	# the harness drives the autoloads for minutes and a test-started activity
	# must never be autosaved over a player's real record. Dormant = inert.
	if OS.get_cmdline_args().has("-s"):
		_dormant = true
		return
	_boot("user://")


func is_dormant() -> bool:
	return _dormant


## Full boot: dir, load-or-fresh (engine hand-off included), runtime settings,
## concourse wiring and the autosave timer — the latter two only when actually
## inside the tree (test twins drive the cadence via _autosave_tick()).
func _boot(p_base_dir: String, p_tm = null, p_now_ms := -1) -> void:
	base_dir = p_base_dir
	if p_tm != null:
		_tm = p_tm
	elif _tm == null:
		_tm = get_node_or_null("/root/TickManager")
	var now := p_now_ms if p_now_ms >= 0 else _now_ms()
	_session_boot_unix_ms = now
	_last_autosave_ms = now
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	load_or_fresh(now)
	if is_inside_tree():
		get_tree().node_added.connect(_on_node_added)
		for child in get_tree().root.get_children():
			connect_concourse(child)
		var timer := Timer.new()
		timer.name = "AutosaveTimer"
		timer.wait_time = AUTOSAVE_INTERVAL_MS / 1000.0
		timer.autostart = true
		timer.timeout.connect(func() -> void: _autosave_tick())
		add_child(timer)
		# Window close = the OS X button / Cmd-Q path (Window.close_requested is
		# the signal form of NOTIFICATION_WM_CLOSE_REQUEST). Saving here is
		# synchronous and completes before the tree tears down.
		get_tree().root.close_requested.connect(func() -> void: save_now())


# ------------------------------------------------------------------ saving --

## File the record now (manual button, autosave tick, quit, window close).
## Never raises on failure — a failed save is a result + a notice, not a crash.
func save_now(now_ms := -1) -> Dictionary:
	var now := now_ms if now_ms >= 0 else _now_ms()
	if _dormant:
		return {"ok": false, "reason": "dormant (script mode)", "unix_ms": now}
	if save_blocked:
		return _fail_save(now, "filing refused: the on-disk record is from a newer build (refused-load protection)")
	if _tm == null or _tm.state == null:
		return _fail_save(now, "no engine bound to the recorder")
	var doc := _build_doc(now)
	var written := _atomic_write(JSON.stringify(doc, "\t"))
	if not written["ok"]:
		_raise_notice("save_write_failed", {"reason": str(written["reason"]), "path": _path(SAVE_NAME)})
		return _fail_save(now, str(written["reason"]))
	# Meta bookkeeping AFTER a confirmed write (a failed save must not move stamps).
	if _created_unix == 0:
		_created_unix = int(now / 1000)
	_playtime_s += maxi(int((now - _session_boot_unix_ms) / 1000), 0)
	_session_boot_unix_ms = now
	last_save_unix_ms = now
	_last_autosave_ms = now  # a manual filing resets the autosave cadence
	var result := {"ok": true, "reason": "", "unix_ms": now}
	save_completed.emit(result)
	return result


func _fail_save(now: int, reason: String) -> Dictionary:
	var result := {"ok": false, "reason": reason, "unix_ms": now}
	save_completed.emit(result)
	return result


## The envelope (docs/save-schema.md, as-shipped v1). PlayerState.to_dict()
## supplies the engine namespace; the two int64 RNG fields are stringified.
func _build_doc(now: int) -> Dictionary:
	var engine: Dictionary = _tm.state.to_dict()
	for skill_id in engine["active"]:
		var slot: Dictionary = engine["active"][skill_id]
		slot["rng_seed"] = str(int(slot["rng_seed"]))
		slot["rng_state"] = str(int(slot["rng_state"]))
	return {
		"save_version": SAVE_VERSION,
		"content_schema_version": ContentLoader.SCHEMA_VERSION,
		"meta": {
			"created_unix": _created_unix if _created_unix > 0 else int(now / 1000),
			"updated_unix": int(now / 1000),
			"playtime_s": _playtime_s + maxi(int((now - _session_boot_unix_ms) / 1000), 0),
		},
		"anchor_unix_ms": now,
		"engine_sim_time_ms": maxi(int(_tm.sim_time_ms), 0),
		"engine": engine,
		"settings": _settings_snapshot(),
	}


func _settings_snapshot() -> Dictionary:
	var font_scale := 1.0
	var fullscreen := false
	if is_inside_tree():
		var ui := get_node_or_null("/root/UiTheme")
		if ui != null:
			font_scale = float(ui.font_scale)
		fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return {"font_scale": font_scale, "fullscreen": fullscreen}


## tmp -> flush -> close -> rotate -> rename. The primary is only ever
## replaced by an atomic rename of a fully-written file within the same
## directory; readers can observe the old or the new record, never a mix.
func _atomic_write(text: String) -> Dictionary:
	var tmp_path := _path(TMP_NAME)
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "cannot open scratch file (error %d)" % FileAccess.get_open_error()}
	f.store_string(text)
	f.flush()  # userland -> OS (no fsync in Godot's FileAccess — see header)
	f.close()
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return {"ok": false, "reason": "cannot open save directory"}
	_rotate_ring(dir)
	var err := dir.rename(TMP_NAME, SAVE_NAME)
	if err != OK:
		return {"ok": false, "reason": "rename into place failed (error %d)" % err}
	return {"ok": true}


## Chain rotation, oldest out: bak3 evicted, bak2->bak3, bak1->bak2,
## primary->bak1. Renames never rewrite file bytes, so each backup keeps the
## mtime of the moment it was written — the ring order is the write order and
## bak1 is always the newest last-good record.
func _rotate_ring(dir: DirAccess) -> void:
	if dir.file_exists(_bak_name(BACKUP_SLOTS)):
		dir.remove(_bak_name(BACKUP_SLOTS))
	var i := BACKUP_SLOTS - 1
	while i >= 1:
		if dir.file_exists(_bak_name(i)):
			dir.rename(_bak_name(i), _bak_name(i + 1))
		i -= 1
	if dir.file_exists(SAVE_NAME):
		dir.rename(SAVE_NAME, _bak_name(1))


# ------------------------------------------------------------------ loading --

## Load-or-fresh: primary (version gate -> shape/content validation), then on
## hard failure the backup ring newest-first, then fresh state + notice.
## Side effects: adopts into the TickManager, applies offline catch-up, applies
## runtime settings. Read-only on disk EXCEPT the primary quarantine rename —
## a successful load never writes (the next autosave re-primes the primary).
func load_or_fresh(now_ms := -1) -> Dictionary:
	var now := now_ms if now_ms >= 0 else _now_ms()
	notice = {}
	save_blocked = false
	content_drift = {}
	first_run = false
	load_report = {"now_ms": now, "loaded_from": "fresh", "attempts": [], "first_run": true}
	var has_primary := FileAccess.file_exists(_path(SAVE_NAME))
	var baks := _backups_newest_first()
	if not has_primary and baks.is_empty():
		first_run = true  # SaveStore owns first-run detection (no record anywhere)
		load_report["first_run"] = true
		return load_report
	# -- primary --
	var pr := _read_save(_path(SAVE_NAME))
	if pr["refused"]:
		# Well-formed but from a NEWER build: refuse the load AND every future
		# write; never quarantine (it is not corrupt); never touch its bytes.
		save_blocked = true
		load_report["loaded_from"] = "blocked"
		_raise_notice("refused_newer_save_version", {
			"found_save_version": int(pr["save_version"]),
			"supported_save_version": SAVE_VERSION,
			"path": _path(SAVE_NAME),
		})
		return load_report
	if pr["ok"]:
		return _finish_load(pr["doc"], SAVE_NAME, "", now, load_report)
	load_report["attempts"].append({"slot": SAVE_NAME, "why": str(pr["reason"])})
	var quarantined := ""
	if has_primary:
		quarantined = _quarantine(now)  # forensics: keep the bytes, then ring
		if quarantined == "":
			push_error("[save] could not quarantine the corrupt primary — walking the ring")
	# -- backup ring, newest-first --
	for bak in baks:
		var cand := _read_save(_path(bak))
		if cand["refused"]:
			load_report["attempts"].append({"slot": bak, "why": "newer save_version %d — skipped" % int(cand["save_version"])})
			continue
		if cand["ok"]:
			return _finish_load(cand["doc"], bak, str(pr["reason"]), now, load_report)
		load_report["attempts"].append({"slot": bak, "why": str(cand["reason"])})
	# -- nothing loadable: fresh state + corruption notice (a state, not a crash) --
	load_report["loaded_from"] = "fresh-corrupt"
	_raise_notice("all_saves_corrupt_fresh_state", {
		"attempts": load_report["attempts"],
		"quarantined": quarantined,
	})
	return load_report


## Adopt a validated document into the engine + run the offline hand-off.
func _finish_load(doc: Dictionary, slot: String, primary_why: String, now: int, report: Dictionary) -> Dictionary:
	_record_drift(doc)
	var meta: Dictionary = doc["meta"]
	_created_unix = int(meta.get("created_unix", 0))
	_playtime_s = int(meta.get("playtime_s", 0))
	var anchor := int(doc["anchor_unix_ms"])
	last_save_unix_ms = anchor
	var st := PlayerState.from_dict(doc["engine"], _lib())
	_tm.adopt_state(st, int(doc.get("engine_sim_time_ms", 0)))
	var mail: Dictionary = _tm.apply_offline_from_save(anchor, now)
	report["loaded_from"] = slot
	report["anchor_unix_ms"] = anchor
	report["mail_call"] = mail
	report["settings"] = doc.get("settings", {})
	_apply_runtime_settings(report["settings"])
	if primary_why != "":
		_raise_notice("primary_corrupt_backup_loaded", {
			"why": primary_why,
			"restored_from": slot,
			"quarantined": _last_quarantine_name,
		})
	return report


## Read + parse + version-gate + validate one candidate file.
## {"ok": bool, "reason": String, "doc": Dictionary, "refused": bool, "save_version": int}
func _read_save(path: String) -> Dictionary:
	var out := {"ok": false, "reason": "missing", "doc": {}, "refused": false, "save_version": 0}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["reason"] = "unreadable (open error %d)" % FileAccess.get_open_error()
		return out
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		out["reason"] = "JSON parse error (line %d): %s" % [parser.get_error_line() + 1, parser.get_error_message()]
		return out
	var parsed: Variant = parser.data
	if parsed is not Dictionary:
		out["reason"] = "top level is not a JSON object"
		return out
	var doc: Dictionary = parsed
	if not _is_number(doc.get("save_version")):
		out["reason"] = "save_version missing or not an integer"
		return out
	var v := int(doc["save_version"])
	out["save_version"] = v
	if v < 1:
		out["reason"] = "save_version %d is below 1" % v
		return out
	if v > SAVE_VERSION:
		out["refused"] = true  # newer build's save — the caller decides policy
		out["ok"] = true
		out["doc"] = doc
		return out
	if v < SAVE_VERSION:
		var mig := _apply_migrations(doc, SAVE_VERSION)
		if not mig["ok"]:
			out["reason"] = str(mig["reason"])
			return out
		doc = mig["doc"]
	var why := _validate_doc(doc)
	if why != "":
		out["reason"] = why
		return out
	out["ok"] = true
	out["doc"] = doc
	return out


# -------------------------------------------------------------- migrations --

## Ordered migration chain hook. To grow the format: bump SAVE_VERSION, write
## `func _migrate_<n>_to_<n+1>(doc) -> Dictionary` stamping the new version.
## A missing step is a hard refusal (never guess a transformation); the chain
## is exercised by tests/test_save.gd via a subclass.
func _apply_migrations(doc: Dictionary, current_version: int) -> Dictionary:
	var v := int(doc.get("save_version", 0))
	while v < current_version:
		var next := v + 1
		var fname := "_migrate_%d_to_%d" % [v, next]
		if not has_method(fname):
			return {"ok": false, "doc": doc, "reason": "no migration %s (save v%d, build v%d)" % [fname, v, current_version]}
		doc = call(fname, doc)
		if int(doc.get("save_version", 0)) != next:
			return {"ok": false, "doc": doc, "reason": "migration %s did not stamp save_version %d" % [fname, next]}
		v = next
	return {"ok": true, "doc": doc, "reason": ""}


# ------------------------------------------------------------- validation --

## Shape + content-id validation (docs/save-schema.md: a save referencing
## content that no longer exists is a BROKEN save — surfaced, not guessed at;
## unknown KEYS are fine and simply drop on the next save). Returns "" or why.
func _validate_doc(d: Dictionary) -> String:
	var meta: Variant = d.get("meta")
	if meta is not Dictionary:
		return "meta missing or not an object"
	for key in ["created_unix", "updated_unix", "playtime_s"]:
		if not _is_number((meta as Dictionary).get(key)) or int((meta as Dictionary)[key]) < 0:
			return "meta.%s missing or not a non-negative integer" % key
	if not _is_number(d.get("anchor_unix_ms")) or int(d["anchor_unix_ms"]) < 0:
		return "anchor_unix_ms missing or not a non-negative integer"
	if d.has("engine_sim_time_ms") and (not _is_number(d["engine_sim_time_ms"]) or int(d["engine_sim_time_ms"]) < 0):
		return "engine_sim_time_ms present but not a non-negative integer"
	if d.has("content_schema_version") and not _is_number(d["content_schema_version"]):
		return "content_schema_version present but not an integer"
	var settings: Variant = d.get("settings", {})
	if settings is not Dictionary:
		return "settings is not an object"
	if (settings as Dictionary).has("font_scale"):
		var scale: Variant = (settings as Dictionary)["font_scale"]
		if (scale is not float and scale is not int) or not FONT_SCALE_STEPS.has(float(scale)):
			return "settings.font_scale %s is not a supported step" % str(scale)
	if (settings as Dictionary).has("fullscreen") and (settings as Dictionary)["fullscreen"] is not bool:
		return "settings.fullscreen is not a boolean"
	var eng: Variant = d.get("engine")
	if eng is not Dictionary:
		return "engine missing or not an object"
	var e: Dictionary = eng
	if not _is_number(e.get("world_seed")) or int(e["world_seed"]) < 0:
		return "engine.world_seed invalid"
	if not _is_number(e.get("crowns")) or int(e["crowns"]) < 0:
		return "engine.crowns invalid"
	var lib := _lib()
	if lib == null:
		return "no content library available to validate against"
	# skills (lifetime xp totals; levels are re-derived, never read)
	var xp: Variant = e.get("skills_xp")
	if xp is not Dictionary:
		return "engine.skills_xp missing or not an object"
	for skill_id in (xp as Dictionary):
		if not lib.skills.has(skill_id):
			return "skills_xp references unknown skill '%s'" % skill_id
		if not _is_number((xp as Dictionary)[skill_id]) or int((xp as Dictionary)[skill_id]) < 0:
			return "skills_xp['%s'] is not a non-negative integer" % skill_id
	# inventory (int stacks against known items)
	var inv: Variant = e.get("inventory")
	if inv is not Dictionary:
		return "engine.inventory missing or not an object"
	for item_id in (inv as Dictionary):
		if not lib.items.has(item_id):
			return "inventory references unknown item '%s'" % item_id
		if not _is_number((inv as Dictionary)[item_id]) or int((inv as Dictionary)[item_id]) < 0:
			return "inventory['%s'] is not a non-negative integer" % item_id
	# active slots (one per non-combat skill; ids must resolve in content)
	var act: Variant = e.get("active")
	if act is not Dictionary:
		return "engine.active missing or not an object"
	for skill_id in (act as Dictionary):
		var skill: SkillDef = lib.skills.get(skill_id)
		if skill == null:
			return "active references unknown skill '%s'" % skill_id
		if skill.is_combat():
			return "active places a slot on combat skill '%s' (combat lives in engine.combat, T7)" % skill_id
		var slot: Variant = (act as Dictionary)[skill_id]
		if slot is not Dictionary:
			return "active['%s'] is not an object" % skill_id
		var why := _validate_slot(slot, String(skill_id), lib)
		if why != "":
			return why
	var combat: Variant = e.get("combat", {})
	if combat is not Dictionary:
		return "engine.combat is not an object (reserved T7 namespace)"
	return ""


func _validate_slot(slot: Dictionary, skill_id: String, lib: ContentLibrary) -> String:
	if String(slot.get("skill_id", "")) != skill_id:
		return "active['%s'].skill_id mismatch" % skill_id
	var cid := String(slot.get("content_id", ""))
	var adef: ActivityDef = lib.activities.get(cid)
	var rdef: RecipeDef = lib.recipes.get(cid)
	if adef == null and rdef == null:
		return "active['%s'] references unknown content '%s'" % [skill_id, cid]
	var is_recipe := bool(slot.get("is_recipe", false))
	if adef != null and is_recipe:
		return "active['%s'] marks an activity as a recipe" % skill_id
	if rdef != null and not is_recipe:
		return "active['%s'] marks a recipe as an activity" % skill_id
	if adef != null and adef.skill != skill_id:
		return "active['%s'] runs content owned by skill '%s'" % [skill_id, adef.skill]
	if rdef != null and rdef.skill != skill_id:
		return "active['%s'] runs content owned by skill '%s'" % [skill_id, rdef.skill]
	if not _is_number(slot.get("interval_ms")) or int(slot["interval_ms"]) <= 0:
		return "active['%s'].interval_ms invalid" % skill_id
	if not _is_number(slot.get("anchor_ms")):
		return "active['%s'].anchor_ms missing or not an integer" % skill_id
	if not _is_number(slot.get("completed")) or int(slot["completed"]) < 0:
		return "active['%s'].completed invalid" % skill_id
	for rng_key in ["rng_seed", "rng_state"]:
		var rv: Variant = slot.get(rng_key)
		if rv is String:
			if not (rv as String).is_valid_int():
				return "active['%s'].%s is not an integer string" % [skill_id, rng_key]
		elif not _is_number(rv):
			return "active['%s'].%s missing or not an integer/string" % [skill_id, rng_key]
	if slot.get("stream_started", false) is not bool:
		return "active['%s'].stream_started is not a boolean" % skill_id
	return ""


func _record_drift(doc: Dictionary) -> void:
	if not doc.has("content_schema_version"):
		return
	var saved := int(doc["content_schema_version"])
	if saved != ContentLoader.SCHEMA_VERSION:
		content_drift = {"saved": saved, "current": ContentLoader.SCHEMA_VERSION}
		push_warning("[save] content schema drift: record written against content v%d, build ships v%d (every id was re-validated at load; diagnostic only)" % [saved, ContentLoader.SCHEMA_VERSION])


# ------------------------------------------------------------------ notices --

func clear_notice() -> void:
	notice = {}


func _raise_notice(kind: String, detail: Dictionary) -> void:
	notice = {"kind": kind, "detail": detail}
	push_warning("[save] notice raised: %s — %s" % [kind, str(detail)])
	notice_raised.emit(kind, detail)


# --------------------------------------------------------------- concourse --

## Wire the T9 shell's stubbed save controls: FILE RECORD files a record now
## (the stamped confirmation rides save_completed -> Concourse.mark_record),
## CLOCK OUT files then quits. Idempotent per concourse.
func connect_concourse(concourse) -> void:
	if _dormant or concourse == null or not (concourse is Concourse):
		return
	if concourse.has_meta("save_store_wired"):
		return
	concourse.set_meta("save_store_wired", true)
	concourse.save_requested.connect(func() -> void: save_now())
	concourse.quit_requested.connect(_on_concourse_quit_requested)
	save_completed.connect(concourse.mark_record)
	# First-run detection is SaveStore's — deferred past the concourse's own
	# _ready (which unconditionally chalks START HERE on first boot).
	concourse.set_first_run.call_deferred(first_run)


func _on_concourse_quit_requested() -> void:
	save_now()
	if quit_after_save and is_inside_tree():
		get_tree().quit()


func _on_node_added(node: Node) -> void:
	connect_concourse(node)


# ------------------------------------------------------------------ helpers --

## Autosave cadence check — driven by the tree Timer in production, by tests
## with synthetic clocks. One filing per elapsed AUTOSAVE_INTERVAL_MS, never
## more (manual filings reset the cadence, so no double-write after a click).
func _autosave_tick(now_ms := -1) -> void:
	var now := now_ms if now_ms >= 0 else _now_ms()
	if now - _last_autosave_ms >= AUTOSAVE_INTERVAL_MS:
		save_now(now)


func _apply_runtime_settings(settings: Dictionary) -> void:
	if not is_inside_tree() or not settings.has("font_scale"):
		return
	var ui := get_node_or_null("/root/UiTheme")
	if ui != null:
		ui.apply_font_scale(float(settings["font_scale"]))
	if bool(settings.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


var _last_quarantine_name := ""


## Preserve a corrupt primary for forensics: rename (never delete) to
## save.json.corrupt-<unix-seconds> (with a .n suffix on same-second collisions).
func _quarantine(now_ms: int) -> String:
	var dir := DirAccess.open(base_dir)
	if dir == null or not dir.file_exists(SAVE_NAME):
		return ""
	var base := "%s.corrupt-%d" % [SAVE_NAME, int(now_ms / 1000)]
	var target := base
	var n := 0
	while dir.file_exists(target):
		n += 1
		target = "%s.%d" % [base, n]
	if dir.rename(SAVE_NAME, target) != OK:
		return ""
	_last_quarantine_name = target
	return target


## Existing ring members, newest-first by mtime; ties broken by slot number
## (chain rotation guarantees bak1 is the newest last-good record, and equal
## mtimes happen whenever two saves land inside one filesystem timestamp).
func _backups_newest_first() -> Array[String]:
	var found: Array = []
	var dir := DirAccess.open(base_dir)
	if dir == null:
		return []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with(SAVE_NAME + ".bak"):
			found.append(String(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	found.sort_custom(func(a: String, b: String) -> bool:
		var ma := FileAccess.get_modified_time(_path(a))
		var mb := FileAccess.get_modified_time(_path(b))
		if ma != mb:
			return ma > mb
		return _bak_slot(a) < _bak_slot(b))
	var out: Array[String] = []
	for f in found:
		out.append(String(f))
	return out


func _bak_slot(name: String) -> int:
	return int(name.trim_prefix(SAVE_NAME + ".bak"))


func _bak_name(slot: int) -> String:
	return "%s.bak%d" % [SAVE_NAME, slot]


func _path(file_name: String) -> String:
	return base_dir.path_join(file_name)


func _lib() -> ContentLibrary:
	if _tm != null and _tm.engine != null:
		return _tm.engine.lib
	return ContentDB.library


## The T6 timestamp contract — identical formula to TickManager.now_unix_ms().
func _now_ms() -> int:
	if _tm != null:
		return _tm.now_unix_ms()
	return int(Time.get_unix_time_from_system() * 1000.0)


## JSON numbers arrive as float; in-memory dicts hold int. Both are fine as
## long as the magnitude is exactly representable (the 2^53 JSON cliff).
func _is_number(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		return absf(v) < 9007199254740992.0
	return false
