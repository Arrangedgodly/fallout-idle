extends Node
## TickManager — T6 idle engine autoload: budgeted fixed-rate sim clock, the
## activity engine's driver, and the UI's ONLY update surface.
##
## ─────────────────────────────────────────────────────────────────────────
## UI UPDATE CONTRACT (T10a/T10b bind here — never poll, never per-frame set)
##
## Signals:
##   bulk_state_changed(changes: Dictionary)   — RATE-LIMITED to <= 4 Hz.
##       `changes` maps dirty region -> true; regions today: "xp",
##       "inventory", "activity" (crowns/equipment reserved). Re-read what you
##       render from TickManager.state (PlayerState) when a region you show is
##       in `changes`; ignore flushes for regions you don't show. Connect
##       labels, gauges, Manifest lists, drop-line stamps here. There are NO
##       per-frame updates of anything.
##   level_up(skill_id: String, old_level: int, new_level: int) — IMMEDIATE,
##       discrete, emitted once per level crossed during LIVE play (offline
##       crossings ride the mail-call payload instead). Fanfare plates bind
##       here.
##   activity_stopped(skill_id, content_id, reason) — IMMEDIATE, discrete.
##       Reasons: "inputs_exhausted" (recipe ran dry), "replaced" (player
##       switched that skill's slot), "stopped" (manual stop).
##   mail_call_ready(payload: Dictionary) — IMMEDIATE, once per load with a
##       positive offline gap. Payload shape (also cached in
##       state.last_mail_call): elapsed_ms, skills_xp {skill: gained},
##       items {item: gained}, levels {skill: {from, to}}, actions {skill:
##       count}, stopped [...]. T10a renders the MAIL CALL notice from this.
##
## Interaction rules:
##   • User-initiated actions (start/stop activity) force an immediate bulk
##     flush so clicks feel instant; everything else waits for the 4 Hz gate.
##   • Sim clock is int milliseconds (Time.get_ticks_msec deltas); no float
##     drift is possible. Render frames only FEED the accumulator.
## ─────────────────────────────────────────────────────────────────────────
##
## Catch-up discipline: at most MAX_CATCHUP_TICKS_PER_FRAME sim ticks run per
## frame; a longer stall is CLAMPED (excess dropped, recorded in `stats`) and
## the clock resyncs — no spiral of death, offline math owns long gaps.
##
## Debug output is OFF by default (set `verbose = true` to enable tracing).

signal bulk_state_changed(changes: Dictionary)
signal level_up(skill_id: String, old_level: int, new_level: int)
signal activity_stopped(skill_id: String, content_id: String, reason: String)
signal mail_call_ready(payload: Dictionary)

const TICK_MS := 100  ## 10 Hz sim (decoupled from render frames).
const MAX_CATCHUP_TICKS_PER_FRAME := 25  ## 2.5 s of sim max per frame, then clamp.
const BULK_MIN_INTERVAL_MS := UpdateBatcher.DEFAULT_MIN_INTERVAL_MS  ## 4 Hz.

var verbose: bool = false
var state: PlayerState
var engine: ActivityEngine
var batcher: UpdateBatcher
var sim_time_ms: int = 0  ## absolute sim clock (int ms; the engine's anchors live on it)
var stats := {
	"ticks_executed": 0,
	"clamped_stalls": 0,
	"last_clamp_dropped_ms": 0,
	"total_dropped_ms": 0,
	"max_ticks_in_one_advance": 0,
}

var _accum_ms := 0
var _last_wall_ms := -1


func _ready() -> void:
	_boot(ContentDB.library, _default_seed())


## Builds the whole engine stack. Tests call this directly on a bare
## TickManager.new() (never added to the tree → _process never fires → fully
## deterministic manual advance through advance_wall_ms()).
func _boot(p_lib: ContentLibrary, world_seed: int) -> void:
	batcher = UpdateBatcher.new()
	batcher.min_interval_ms = BULK_MIN_INTERVAL_MS
	engine = ActivityEngine.new(p_lib, batcher)
	engine.level_up.connect(_on_level_up)
	engine.activity_stopped.connect(_on_activity_stopped)
	batcher.flushed.connect(func(changes: Dictionary) -> void:
		bulk_state_changed.emit(changes))
	new_game(world_seed)


func new_game(world_seed: int = -1) -> void:
	state = engine.new_state(world_seed if world_seed >= 0 else _default_seed())
	sim_time_ms = 0
	_accum_ms = 0
	_last_wall_ms = -1
	for key in stats:
		stats[key] = 0
	_debug("booted: seed=%d skills=%d" % [state.world_seed, state.skills_xp.size()])


# -- T3 save-system hand-off --

## Adopt a PlayerState hydrated from a save (levels already re-derived from xp
## by PlayerState.from_dict) and resume the saved sim clock so the loaded slot
## anchors stay consistent with the engine's closed-form math. SaveStore calls
## this then immediately applies the offline gap via apply_offline_from_save()
## — the away time rewinds anchors by exactly the elapsed ms (T6 contract), so
## live ticking resumes with the phase remainder the save left off with.
## Clock stats reset: a loaded session starts a fresh stall/clamp budget.
func adopt_state(st: PlayerState, resume_sim_ms: int = 0) -> void:
	state = st
	sim_time_ms = maxi(resume_sim_ms, 0)
	_accum_ms = 0
	_last_wall_ms = -1
	for key in stats:
		stats[key] = 0


# -- Clock funnel: _process feeds wall time; advance_wall_ms is THE entrypoint --

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _last_wall_ms < 0:
		_last_wall_ms = now
		return
	var delta := now - _last_wall_ms
	_last_wall_ms = now
	if delta > 0:
		advance_wall_ms(delta)


## Feed elapsed wall ms (int). Runs 0..MAX_CATCHUP_TICKS_PER_FRAME sim ticks;
## a larger backlog is clamped + recorded (dropped ms never come back — the
## offline path is the recovery mechanism for long gaps). Public so tests and
## T7 drive the identical path.
func advance_wall_ms(delta_ms: int) -> void:
	if delta_ms <= 0:
		return
	_accum_ms += delta_ms
	var ran := 0
	while _accum_ms >= TICK_MS and ran < MAX_CATCHUP_TICKS_PER_FRAME:
		_sim_tick()
		_accum_ms -= TICK_MS
		ran += 1
	if _accum_ms >= TICK_MS:
		# Frame stalled past the budget: clamp, record, resync to wall clock.
		var dropped := _accum_ms
		_accum_ms = 0
		stats["clamped_stalls"] = int(stats["clamped_stalls"]) + 1
		stats["last_clamp_dropped_ms"] = dropped
		stats["total_dropped_ms"] = int(stats["total_dropped_ms"]) + dropped
		_debug("clamped stall: dropped %d ms (%d total)" % [dropped, stats["total_dropped_ms"]])
	stats["max_ticks_in_one_advance"] = maxi(int(stats["max_ticks_in_one_advance"]), ran)


func _sim_tick() -> void:
	sim_time_ms += TICK_MS
	stats["ticks_executed"] = int(stats["ticks_executed"]) + 1
	engine.tick(state, sim_time_ms)
	batcher.flush_due(sim_time_ms)


# -- Player-facing façade (UI calls these; each force-flushes for snappy UI) --

## Start/switch a skill's activity (activity or recipe id). Returns
## {"ok": bool, "reason": String} — CLEARANCE wording on gate failure.
func start_activity(content_id: String) -> Dictionary:
	var result: Dictionary = engine.start(state, content_id, sim_time_ms)
	batcher.force_flush(sim_time_ms)
	return result


func stop_skill(skill_id: String) -> void:
	engine.stop(state, skill_id)
	batcher.force_flush(sim_time_ms)


# -- Offline catch-up --

## Wall-clock unix ms as an exact int (double precision is exact far past the
## 2^53 cliff at current epoch ms magnitudes ~1.8e12).
static func now_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Elapsed ms between save timestamp and now, clamped at 0 — a clock that ran
## backwards (future-dated save) yields exactly 0, never a negative gain.
static func compute_offline_elapsed_ms(saved_unix_ms: int, now_unix_ms: int = -1) -> int:
	var now := now_unix_ms if now_unix_ms >= 0 else now_unix_ms()
	return maxi(now - saved_unix_ms, 0)


## Offline catch-up from a save timestamp: closed-form math (zero sim ticks),
## emits mail_call_ready when anything was gained. Returns the payload.
func apply_offline_from_save(saved_unix_ms: int, now_unix_ms: int = -1) -> Dictionary:
	return apply_offline_elapsed(compute_offline_elapsed_ms(saved_unix_ms, now_unix_ms))


## Core offline entry: `elapsed_ms` of wall gap applied via closed-form
## arithmetic on the persisted per-slot RNG streams.
func apply_offline_elapsed(elapsed_ms: int) -> Dictionary:
	var payload: Dictionary = engine.apply_offline(state, sim_time_ms, elapsed_ms)
	if int(payload["elapsed_ms"]) > 0:
		mail_call_ready.emit(payload)
		batcher.force_flush(sim_time_ms)
	state.last_mail_call = payload
	return payload


# -- Signal re-emits (engine → autoload surface) --

func _on_level_up(skill_id: String, old_level: int, new_level: int) -> void:
	level_up.emit(skill_id, old_level, new_level)


func _on_activity_stopped(skill_id: String, content_id: String, reason: String) -> void:
	activity_stopped.emit(skill_id, content_id, reason)


func _default_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF


func _debug(message: String) -> void:
	if verbose:
		print("[T6] ", message)
