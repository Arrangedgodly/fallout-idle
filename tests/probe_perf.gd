extends SceneTree
## tests/probe_perf.gd — T13 criterion-6 performance probe (WINDOWED, not
## headless: real renderer, real frame pacing, real UI layout/draw).
##
## Run (deliberately NOT --headless — frame-budget measurement needs the real
## loop; everything else in the battery runs headless):
##   "$GODOT" --path . -s res://tests/probe_perf.gd
##
## Measures a 60 s WORST-CASE window: all five skill slots hot at once (both
## gathering tiers feeding two processing chains on deep stockpiles, nothing
## running dry) + Wasteland Patrol in continuous boss combat with the battle
## log stamping — through the REAL concourse bound to the REAL TickManager
## autoload, in a real 1280x720 OS window.
##
## Cost attribution: TickManager._process is disabled for the window and its
## exact body (now -> delta -> advance_wall_ms) is replayed from this probe's
## main-loop callback with Time.get_ticks_usec() around the call. That timing
## is the ENGINE+UI portion of the frame: sim ticks, the batcher, AND every
## signal-connected docket handler run synchronously inside advance_wall_ms
## (the T6 UI update contract has no other update surface — there are no
## per-frame label writes anywhere). Frame time = wall delta between probe
## callbacks. The criterion under test: engine+UI <= 5% of the 60 fps frame
## budget (16,667 us -> <= 833 us per frame).
##
## This is a measured REPORT, not just pass/fail: average + max frame time,
## average + max engine+UI cost, budget share, signal counts and sim stats all
## print for the production log (exit 0 pass / 1 fail, probe convention).

const CONCOURSE_PATH := "res://scenes/main.tscn"
const WINDOW_S := 60.0
const WARMUP_S := 2.0
const BUDGET_FRAME_US := 16_667  ## one 60 fps frame
const UI_BUDGET_US := 833        ## 5% of the frame budget
const HARD_MAX_US := 8_000       ## never burn half a frame in the loop
const L14_XP := 8_340            ## combat clearance 14 (boss gate)

var failures: Array[String] = []
var _concourse: Concourse
var _tm: Node
var _state: PlayerState
var _phase := "boot"
var _frame := 0
var _done := false

# measurement accumulators
var _last_wall_ms := -1
var _prev_frame_usec := -1
var _collect_from_msec := 0
var _collect_until_msec := 0
var _frames := 0
var _frame_us_total := 0
var _frame_us_max := 0
var _engine_us_total := 0
var _engine_us_max := 0
var _engine_us_last := 0

# signal + sim counters
var _bulk := 0
var _levelups := 0
var _combats := 0
var _zone_clears := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(CONCOURSE_PATH) as PackedScene
	if packed == null:
		_fail("concourse scene loads from %s" % CONCOURSE_PATH)
		_finish()
		return
	_concourse = packed.instantiate() as Concourse
	if _concourse == null:
		_fail("concourse root is the Concourse script")
		_finish()
		return
	root.add_child(_concourse)  # the real window, the production arrangement


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	match _phase:
		"boot":
			if _frame >= 30:  # _ready + first layout passes settled
				_setup_worst_case()
			return false
		"measure":
			return _measure_tick()
	return false


# ------------------------------------------------------------ worst-case setup
func _setup_worst_case() -> void:
	_tm = root.get_node_or_null("TickManager")
	if _tm == null:
		_fail("TickManager autoload present")
		_finish()
		return
	# The probe replays the exact _process body, timed (see header). Disabling
	# the node's own callback only removes the trivial now/delta wrapper —
	# advance_wall_ms remains the one and only funnel, fed real frame deltas.
	_tm.set_process(false)
	_state = _tm.state

	# Worst case loadout + stockpiles through the real façade (the same calls
	# the UI makes).
	_tm.engine.grant_xp(_state, "wasteland_combat", L14_XP)
	_state.add_item("scrap_metal", 1_000_000_000)  # smelting never runs dry
	_state.add_item("duskcorn", 1_000_000_000)     # grits never run dry
	for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", 400]]:
		_state.add_item(pair[0], pair[1])
	var eq1: Dictionary = _tm.equip_item("majority_whip")
	var eq2: Dictionary = _tm.equip_item("carpool_carapace")
	if not (bool(eq1["ok"]) and bool(eq2["ok"])):
		_fail("worst-case gear equips")
		_finish()
		return
	for content_id in ["sort_scrap_pile", "walk_the_glow_rows",
			"smelt_scrap_ingot", "grind_mandatory_grits"]:
		var r: Dictionary = _tm.start_activity(content_id)
		if not bool(r["ok"]):
			_fail("slot starts: %s (%s)" % [content_id, str(r)])
			_finish()
			return

	# Signal counters + continuous combat churn: on every fight end the probe
	# re-engages (the live mirror of the offline farm chain), so the combat
	# engine, the auto-eater and the battle log stay hot for the whole window.
	(_tm.get("bulk_state_changed") as Signal).connect(
		func(_changes: Dictionary) -> void: _bulk += 1)
	(_tm.get("level_up") as Signal).connect(
		func(_s: String, _o: int, _n: int) -> void: _levelups += 1)
	(_tm.get("zone_cleared") as Signal).connect(
		func(_m: String) -> void: _zone_clears += 1)
	(_tm.get("combat_ended") as Signal).connect(
		func(_result: Dictionary) -> void:
			_combats += 1
			_tm.engage_monster("sewer_landlord"))
	var engaged: Dictionary = _tm.engage_monster("sewer_landlord")
	if not bool(engaged["ok"]):
		_fail("boss engages at clearance 14")
		_finish()
		return

	var now := Time.get_ticks_msec()
	_collect_from_msec = now + int(WARMUP_S * 1000.0)
	_collect_until_msec = _collect_from_msec + int(WINDOW_S * 1000.0)
	_phase = "measure"


# ------------------------------------------------------------ timed window
func _measure_tick() -> bool:
	var now_usec := Time.get_ticks_usec()
	if _prev_frame_usec < 0:
		_prev_frame_usec = now_usec
		return false
	var frame_us: int = now_usec - _prev_frame_usec
	_prev_frame_usec = now_usec

	# TickManager._process's exact body, timed (engine + UI signal handlers).
	_engine_us_last = 0
	var now_ms := Time.get_ticks_msec()
	if _last_wall_ms < 0:
		_last_wall_ms = now_ms
	else:
		var delta: int = now_ms - _last_wall_ms
		_last_wall_ms = now_ms
		if delta > 0:
			var t0 := Time.get_ticks_usec()
			_tm.advance_wall_ms(delta)
			_engine_us_last = Time.get_ticks_usec() - t0

	var now := Time.get_ticks_msec()
	if now >= _collect_from_msec and now < _collect_until_msec:
		_frames += 1
		_frame_us_total += frame_us
		_frame_us_max = maxi(_frame_us_max, frame_us)
		_engine_us_total += _engine_us_last
		_engine_us_max = maxi(_engine_us_max, _engine_us_last)
	elif now >= _collect_until_msec:
		_report()
		return true
	return false


# ------------------------------------------------------------ report
func _report() -> void:
	_done = true
	if _frames < 60 * 30:
		_fail("measurement collected %d frames — the window ran unexpectedly short" % _frames)
		_finish()
		return
	var wall_s := float(_frame_us_total) / 1_000_000.0
	var avg_frame_us := float(_frame_us_total) / float(_frames)
	var avg_engine_us := float(_engine_us_total) / float(_frames)
	var share_pct := 100.0 * avg_engine_us / float(BUDGET_FRAME_US)
	var ticks: int = int(_tm.stats["ticks_executed"])
	var stalls: int = int(_tm.stats["clamped_stalls"])
	var max_ticks: int = int(_tm.stats["max_ticks_in_one_advance"])

	print("T13 PERF REPORT — windowed %.0f s worst-case, 1280x720, real renderer" % WINDOW_S)
	print("  frames=%d  wall=%.2f s  avg fps=%.1f" % [_frames, wall_s, float(_frames) / wall_s])
	print("  frame time: avg %.2f ms  max %.2f ms" % [
		avg_frame_us / 1000.0, float(_frame_us_max) / 1000.0])
	print("  ENGINE+UI loop cost: avg %.1f us/frame  max %d us  (share of the 16.67 ms 60 fps budget: %.2f%%)" % [
		avg_engine_us, _engine_us_max, share_pct])
	print("  signals: bulk_state_changed=%d level_up=%d combat_ended=%d zone_cleared=%d" % [
		_bulk, _levelups, _combats, _zone_clears])
	print("  sim: ticks=%d clamped_stalls=%d max_ticks_in_one_advance=%d batcher_emissions=%d" % [
		ticks, stalls, max_ticks, _tm.batcher.emission_count])

	# Criterion 6: the game loop holds <= 5% of the frame budget for UI at 60 fps.
	_check(avg_engine_us <= float(UI_BUDGET_US),
		"engine+UI avg %.1f us/frame within the 5%% budget (%d us)" % [avg_engine_us, UI_BUDGET_US])
	_check(_engine_us_max <= HARD_MAX_US,
		"engine+UI worst frame %d us under the %d us hard ceiling" % [_engine_us_max, HARD_MAX_US])
	# The 4 Hz bulk ceiling over the window (gate-limited flushes; the count
	# excludes the handful of user-action force flushes from the setup and any
	# re-engages — each of those is a discrete click-equivalent).
	_check(_bulk <= 4 * int(WINDOW_S) + 8 + _combats,
		"bulk emissions %d within the 4 Hz ceiling (+ discrete force flushes)" % _bulk)
	_check(stalls <= 1,
		"clamped stalls %d — the loop never fell behind its catch-up budget" % stalls)
	_finish()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	failures.append(label)
	print("  FAIL  %s" % label)


func _finish() -> void:
	_done = true
	if failures.is_empty():
		print("T13 PERF REPORT: %d checks green — UI frame budget holds" % 4)
		quit(0)
	else:
		print("T13 PERF REPORT: %d FAILURES" % failures.size())
		quit(1)
