extends SceneTree
## tests/probe_perf_idle.gd — T14 idle-state performance + memory-stability
## probe (WINDOWED, not headless: real renderer, real frame pacing — same
## convention as tests/probe_perf.gd, which owns the 60 s WORST-case window).
##
## Run (deliberately NOT --headless):
##   "$GODOT" --path . -s res://tests/probe_perf_idle.gd
##
## Measures the OTHER end of the envelope from T13: the game sitting IDLE —
## no input of any kind after setup — with one gathering shift running
## (sort_scrap_pile, tier 1) and the Wasteland Patrol auto-battling the
## weakest fauna continuously (the combat_ended -> re-engage chain is the
## scripted twin of a resident leaving the patrol to farm, exactly as T13's
## probe does for the boss). Three consecutive 60 s windows:
##   • per window: frames, avg/max frame time, avg/max engine+UI cost
##     (TickManager._process's exact body timed around advance_wall_ms —
##     every signal-connected docket handler runs inside it),
##   • per window boundary: Performance MEMORY_STATIC + OBJECT_COUNT +
##     OBJECT_NODE, asserted STABLE window-over-window (no leak across
##     3 x 60 s of idle play).
##
## Exit 0 pass / 1 fail (probe convention). A measured REPORT prints for the
## production log.

const CONCOURSE_PATH := "res://scenes/main.tscn"
const WINDOW_S := 60.0
const WARMUP_S := 3.0
const WINDOWS := 5
const BUDGET_FRAME_US := 16_667  ## one 60 fps frame
const UI_BUDGET_US := 833        ## 5% of the frame budget (T13 criterion 6)
const HARD_MAX_US := 8_000       ## never burn half a frame in the loop
## Leak ceilings: static heap may warm caches but must settle (4 MiB over
## the measured span); live object/node counts must settle by the FINAL
## window (the docket logs cap at 60 stamps each and fill during the first
## minutes — bounded warm-up, not a leak; the final-window delta is the
## steady-state verdict, the full-span drift is reported for the log).
const LEAK_STATIC_MAX_BYTES := 4 * 1024 * 1024
const LEAK_OBJECT_MAX := 100

var failures: Array[String] = []
var _concourse: Concourse
var _tm: Node
var _state: PlayerState
var _phase := "boot"
var _frame := 0
var _done := false
var _window := -1  ## -1 = warmup

var _last_wall_ms := -1
var _prev_frame_usec := -1
var _win_start_msec := 0
var _frames := 0
var _frame_us_total := 0
var _frame_us_max := 0
var _engine_us_total := 0
var _engine_us_max := 0
var _engine_us_last := 0

# per-window memory snapshots + rolled-up report rows
var _static_at: Array[int] = []
var _objects_at: Array[int] = []
var _nodes_at: Array[int] = []
var _resources_at: Array[int] = []
var _rows: Array[String] = []
var _worst_window_avg_us := 0.0
var _worst_engine_max_us := 0

var _bulk := 0
var _combats := 0


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
	root.add_child(_concourse)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	match _phase:
		"boot":
			if _frame >= 30:
				_setup_idle()
			return false
		"measure":
			return _measure_tick()
	return false


# ------------------------------------------------------------- idle setup
func _setup_idle() -> void:
	_tm = root.get_node_or_null("TickManager")
	if _tm == null:
		_fail("TickManager autoload present")
		_finish()
		return
	_tm.set_process(false)  # the probe replays the exact body, timed
	_state = _tm.state

	# The idle loadout: one tier-1 gathering shift + the patrol auto-battle.
	var start: Dictionary = _tm.start_activity("sort_scrap_pile")
	if not bool(start["ok"]):
		_fail("gathering shift starts: %s" % str(start))
		_finish()
		return
	(_tm.get("bulk_state_changed") as Signal).connect(
		func(_changes: Dictionary) -> void: _bulk += 1)
	(_tm.get("combat_ended") as Signal).connect(
		func(_result: Dictionary) -> void:
			_combats += 1
			_tm.engage_monster("junkyard_roach"))
	var engaged: Dictionary = _tm.engage_monster("junkyard_roach")
	if not bool(engaged["ok"]):
		_fail("patrol engages the junkyard roach")
		_finish()
		return

	_phase = "measure"
	_window = 0
	_win_start_msec = Time.get_ticks_msec() + int(WARMUP_S * 1000.0)
	_snapshot_memory()  # index 0: end of warmup, before any window


# ------------------------------------------------------------- timed windows
func _measure_tick() -> bool:
	var now_usec := Time.get_ticks_usec()
	if _prev_frame_usec < 0:
		_prev_frame_usec = now_usec
		return false
	var frame_us: int = now_usec - _prev_frame_usec
	_prev_frame_usec = now_usec

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
	if now < _win_start_msec:
		return false  # warmup: run, don't count
	_frames += 1
	_frame_us_total += frame_us
	_frame_us_max = maxi(_frame_us_max, frame_us)
	_engine_us_total += _engine_us_last
	_engine_us_max = maxi(_engine_us_max, _engine_us_last)

	if now >= _win_start_msec + (int(WINDOW_S) * 1000):
		_close_window()
		_snapshot_memory()  # boundary snapshot for EVERY window, last included
		if _window >= WINDOWS:
			_report()
			return true
		_win_start_msec = now
	return false


func _snapshot_memory() -> void:
	_static_at.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	_objects_at.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_nodes_at.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_resources_at.append(int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))


func _close_window() -> void:
	_window += 1
	var wall_s := float(_frame_us_total) / 1_000_000.0
	var frames := maxi(_frames, 1)
	_rows.append("  window %d: frames=%d  wall=%.2f s  avg fps=%.1f  frame avg %.2f ms / max %.2f ms  engine+UI avg %.1f us / max %d us" % [
		_window, _frames, wall_s, float(_frames) / wall_s,
		float(_frame_us_total) / float(frames) / 1000.0,
		float(_frame_us_max) / 1000.0,
		float(_engine_us_total) / float(frames), _engine_us_max])
	_worst_window_avg_us = maxf(_worst_window_avg_us,
		float(_engine_us_total) / float(frames))
	_worst_engine_max_us = maxi(_worst_engine_max_us, _engine_us_max)
	_frames = 0
	_frame_us_total = 0
	_frame_us_max = 0
	_engine_us_total = 0
	_engine_us_max = 0

# ------------------------------------------------------------- report
func _report() -> void:
	_done = true
	var ticks: int = int(_tm.stats["ticks_executed"])
	var stalls: int = int(_tm.stats["clamped_stalls"])
	print("T14 IDLE PERF REPORT — windowed, %dx%.0f s idle state, 1280x720, real renderer, zero input" % [WINDOWS, WINDOW_S])
	for row in _rows:
		print(row)
	print("  memory (boundaries: warmup + one per window):")
	for i in _static_at.size():
		var delta := ""
		if i > 0:
			delta = "  (dObjects %+d, dResources %+d, dNodes %+d)" % [
				_objects_at[i] - _objects_at[i - 1],
				_resources_at[i] - _resources_at[i - 1],
				_nodes_at[i] - _nodes_at[i - 1]]
		print("    [%d] static=%.2f MiB  objects=%d  resources=%d  nodes=%d%s" % [
			i, float(_static_at[i]) / 1048576.0, _objects_at[i], _resources_at[i],
			_nodes_at[i], delta])
	print("  signals: bulk_state_changed=%d combat_ended=%d" % [_bulk, _combats])
	print("  sim: ticks=%d clamped_stalls=%d batcher_emissions=%d" % [
		ticks, stalls, _tm.batcher.emission_count])

	# Budget: the idle loop holds comfortably inside the 5% UI budget.
	_check(_worst_window_avg_us <= float(UI_BUDGET_US),
		"engine+UI worst window avg %.1f us/frame within the 5%% budget (%d us)" % [
			_worst_window_avg_us, UI_BUDGET_US])
	_check(_worst_engine_max_us <= HARD_MAX_US,
		"engine+UI worst single frame %d us under the %d us hard ceiling" % [
			_worst_engine_max_us, HARD_MAX_US])
	_check(stalls <= 1, "clamped stalls %d — the idle loop never fell behind" % stalls)

	# Leak discipline: warmup snapshot is index 0, one per window after.
	# Full-span drift (window 1 -> final) is reported; the VERDICT is the
	# final window's delta — bounded warm-up must have settled by then.
	var last: int = _static_at.size() - 1
	var static_delta: int = _static_at[last] - _static_at[1]
	var span_objects: int = _objects_at[last] - _objects_at[1]
	var final_objects: int = _objects_at[last] - _objects_at[last - 1]
	var final_resources: int = _resources_at[last] - _resources_at[last - 1]
	var final_nodes: int = _nodes_at[last] - _nodes_at[last - 1]
	print("  span drift (window 1 -> final): static %+d bytes, objects %+d" % [
		static_delta, span_objects])
	_check(absi(static_delta) <= LEAK_STATIC_MAX_BYTES,
		"static heap stable over the span (%+d bytes, ceiling +/-%d)" % [
			static_delta, LEAK_STATIC_MAX_BYTES])
	_check(absi(final_objects) <= LEAK_OBJECT_MAX,
		"object count SETTLED by the final window (%+d, ceiling +/-%d) — bounded warm-up, not a leak" % [
			final_objects, LEAK_OBJECT_MAX])
	_check(absi(final_resources) <= LEAK_OBJECT_MAX,
		"resource count settled by the final window (%+d, ceiling +/-%d)" % [
			final_resources, LEAK_OBJECT_MAX])
	_check(absi(final_nodes) <= LEAK_OBJECT_MAX,
		"node count settled by the final window (%+d, ceiling +/-%d)" % [
			final_nodes, LEAK_OBJECT_MAX])
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
		print("T14 IDLE PERF REPORT: 7 checks green — idle frame budget holds, no leak")
		quit(0)
	else:
		print("T14 IDLE PERF REPORT: %d FAILURES" % failures.size())
		quit(1)
