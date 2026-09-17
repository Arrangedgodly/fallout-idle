extends Node
## TickManager — T6 idle engine autoload: budgeted fixed-rate sim clock, the
## activity + combat (T7) engines' driver, and the UI's ONLY update surface.
##
## ─────────────────────────────────────────────────────────────────────────
## UI UPDATE CONTRACT (T10a/T10b bind here — never poll, never per-frame set)
##
## Signals:
##   bulk_state_changed(changes: Dictionary)   — RATE-LIMITED to <= 4 Hz.
##       `changes` maps dirty region -> true; regions today: "xp",
##       "inventory", "activity", "combat" (crowns reserved). Re-read what you
##       render from TickManager.state (PlayerState) when a region you show is
##       in `changes`; ignore flushes for regions you don't show. Connect
##       labels, gauges, Manifest lists, drop-line stamps here. There are NO
##       per-frame updates of anything.
##   level_up(skill_id: String, old_level: int, new_level: int) — IMMEDIATE,
##       discrete, emitted once per level crossed during LIVE play (offline
##       crossings ride the mail-call payload instead). Fanfare plates bind
##       here. Victory combat XP rides this too (shared grant_xp pipeline).
##   activity_stopped(skill_id, content_id, reason) — IMMEDIATE, discrete.
##       Reasons: "inputs_exhausted" (recipe ran dry), "replaced" (player
##       switched that skill's slot), "stopped" (manual stop).
##   combat_ended(result: Dictionary) — IMMEDIATE, discrete (T7). Fires once
##       when a fight ends: result.outcome "victory" (result.drops, result.xp,
##       result.leveled_to) or "death" (RETURN TO SHELTER plate — zero loss).
##       T10b's battle log + death/victory plates bind here.
##   zone_cleared(monster_id: String) — IMMEDIATE, once ever (T7): the boss's
##       first defeat (the slice's win moment). Persistent in
##       state.combat.zone_clear.
##   mail_call_ready(payload: Dictionary) — IMMEDIATE, once per load with a
##       positive offline gap. Payload shape (also cached in
##       state.last_mail_call): elapsed_ms, skills_xp {skill: gained},
##       items {item: gained}, levels {skill: {from, to}}, actions {skill:
##       count}, stopped [...]. T10a renders the MAIL CALL notice from this.
##       COMBAT PROGRESSES OFFLINE at full rate, bounded by survivability
##       (§1.4 addendum 2): a mid-fight save replays live-identically —
##       kills chain (drops + XP + boss zone-clear while a monster is
##       selected) — and a would-be killing blow NEVER lands: the patrol is
##       recalled alive (zero loss). Combat gains fold into the same payload
##       (skills_xp/items/levels/actions) plus payload.combat
##       ({kills, monster_id, outcome, notice: "PATROL RECALLED" on recall,
##       zone_cleared on an offline first boss clear}) and a PATROL RECALLED
##       entry in `stopped`. Idle/victory/dead/recalled saves never
##       auto-start fights offline.
##       T17 STAFFING MIGRATION NOTICE: a v1 save (or any over-subscribed
##       record) that arrived with more running postings than the
##       establishment holds carries payload.staffing = {notice:
##       "POSTINGS SUSPENDED — PERSONNEL SHORTAGE", suspended: [{skill_id,
##       content_id, kind}]} plus one stopped line per suspended posting
##       (reason "posting_suspended") — the mail call posts even when the
##       offline gap is zero, because the notice is the point.
##   bulk_state_changed regions: "xp", "inventory", "activity", "combat" —
##       and since T17 "staffing" (deputize purchases, posting enforcement).
##       Crowns ride "inventory" (Depot precedent: wallet-class changes).
##       Since T18 "orientation" (every O-1 form stamp; the stipend grant
##       also marks "inventory"). Since T23 "objectives" (every dossier
##       stamp; reward legs additionally mark "inventory"/"xp").
##   orientation_step_done(step_id: String) — IMMEDIATE, discrete, once per
##       step (T18). The ORIENTATION FORM O-1's row stamps bind here.
##   orientation_completed(payload: Dictionary) — IMMEDIATE, once ever (T18):
##       the seventh stamp. payload {"stipend": int} (Crowns posted by the
##       DULY ORIENTED reward line; 0 when the stipend was already claimed —
##       a reload never re-rewards).
##   objective_stamped(payload: Dictionary) — IMMEDIATE, discrete, once per
##       objective ever (T23, kind "objective_stamped" per naming-bible §15):
##       a DEPARTMENTAL DOSSIER line crossed its condition and MERIT PAY /
##       COMMENDATION posted itself (no claim buttons anywhere). payload
##       {id, skill, description, crowns, xp_skill, xp_amount, reward_line,
##       notice_line} — the lines carry the T22 formats ("MERIT PAY · 40
##       CROWNS" / "COMMENDATION · 250 XP"; notice "FORM R-1 STAMPED · 40
##       CROWNS POSTED"). Offline completions fire here too (the T18
##       offline-seam precedent) AND ride the MAIL CALL payload's
##       `objectives` section ({stamps: [the same payloads], crowns: int})
##       plus the folded skills_xp/levels legs — the mail call is their
##       presentation.
##   dossier_completed(payload: Dictionary) — IMMEDIATE, when one skill's
##       LAST objective stamps (T23): payload {skill, total, stamp_line =
##       "ALL N STAMPED · FORM R-1"} (N from data, never hardcoded). Re-arms
##       if content later adds objectives to a completed dossier.
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
signal combat_ended(result: Dictionary)
signal zone_cleared(monster_id: String)
signal mail_call_ready(payload: Dictionary)
signal orientation_step_done(step_id: String)
signal orientation_completed(payload: Dictionary)
signal objective_stamped(payload: Dictionary)
signal dossier_completed(payload: Dictionary)

const TICK_MS := 100  ## 10 Hz sim (decoupled from render frames).
const MAX_CATCHUP_TICKS_PER_FRAME := 25  ## 2.5 s of sim max per frame, then clamp.
const BULK_MIN_INTERVAL_MS := UpdateBatcher.DEFAULT_MIN_INTERVAL_MS  ## 4 Hz.

var verbose: bool = false
var state: PlayerState
var engine: ActivityEngine
var combat: CombatSession
var orientation: OrientationTracker
var objectives: ObjectivesTracker
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
## T17: postings suspended by the load-time staffing enforcement, waiting for
## the next apply_offline_elapsed to ride the MAIL CALL payload (cleared once
## presented). Empty on every normal load.
var _staffing_notice: Array = []


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
	# T18: the ORIENTATION FORM O-1 tracker — engine-side event seams only
	# (the UI re-renders from signals/state, never infers step completion).
	orientation = OrientationTracker.new(p_lib, batcher)
	engine.orientation = orientation
	orientation.step_done.connect(func(step_id: String) -> void:
		orientation_step_done.emit(step_id))
	orientation.orientation_completed.connect(func(payload: Dictionary) -> void:
		orientation_completed.emit(payload))
	engine.level_up.connect(func(skill_id: String, _old: int, _new: int) -> void:
		orientation.note_level_up(state, skill_id))
	# T23: the DEPARTMENTAL DOSSIER tracker — the orientation two-tier pattern
	# generalized (lifetime counters from the engine seams, evaluation stamps
	# + auto-grants exactly once). Gather/craft counters live INSIDE
	# ActivityEngine._execute_action (engine.objectives, wired above the
	# combat session so the shared XP pipeline exists for reward legs).
	objectives = ObjectivesTracker.new(p_lib, batcher, engine)
	engine.objectives = objectives
	objectives.objective_stamped.connect(func(payload: Dictionary) -> void:
		objective_stamped.emit(payload))
	objectives.dossier_completed.connect(func(payload: Dictionary) -> void:
		dossier_completed.emit(payload))
	engine.level_up.connect(func(skill_id: String, _old: int, new_level: int) -> void:
		objectives.note_level_up(state, skill_id, new_level))
	# The O-1 stipend posts through the wallet — it counts as lifetime Crowns
	# earned (the crowns_total counters read every earn path).
	orientation.orientation_completed.connect(func(payload: Dictionary) -> void:
		objectives.note_crowns_posted(state, int(payload.get("stipend", 0))))
	combat = CombatSession.new(p_lib, batcher, engine)
	combat.combat_ended.connect(func(result: Dictionary) -> void:
		if str(result.get("outcome", "")) == "victory":
			orientation.note_victory(state)
			objectives.note_victory(state, str(result.get("monster_id", "")))
		combat_ended.emit(result))
	combat.zone_cleared.connect(func(monster_id: String) -> void:
		zone_cleared.emit(monster_id))
	batcher.flushed.connect(func(changes: Dictionary) -> void:
		bulk_state_changed.emit(changes))
	new_game(world_seed)


func new_game(world_seed: int = -1) -> void:
	state = engine.new_state(world_seed if world_seed >= 0 else _default_seed())
	combat.ensure_defaults(state)
	orientation.ensure_orientation(state)
	orientation.evaluate(state)  # no-op on a fresh record; the seam stays one
	batcher.mark("orientation")  # a reset re-posts the form from engine truth
	objectives.ensure_objectives(state)
	objectives.sync_derivable(state)
	objectives.evaluate(state)  # no-op on a fresh record (counters zero)
	batcher.mark("objectives")  # a reset re-posts the dossier from engine truth
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
## Combat (T7): hydrate re-types the combat namespace after JSON, sanitize
## drops fights referencing removed content (never a crash).
## T17: staffing enforcement — an over-subscribed save (v1 migration, or a
## hand-edited record) suspends its oldest postings beyond the establishment
## with zero loss; the descriptions queue for the MAIL CALL notice.
## Clock stats reset: a loaded session starts a fresh stall/clamp budget.
func adopt_state(st: PlayerState, resume_sim_ms: int = 0) -> void:
	state = st
	combat.hydrate(state)
	combat.sanitize(state)
	engine.ensure_staffing(state)
	_staffing_notice = engine.enforce_staffing(state)
	# T18: hydrate/repair the orientation namespace. NO evaluation here — a
	# genuine v2 record is its own truth (the veteran lifetime back-fill runs
	# only for records that arrived without a namespace, SaveStore-side; the
	# acceptance suite pins live/reloaded twin dicts byte-equal).
	orientation.ensure_orientation(state)
	# T23: hydrate/repair the objectives namespace the same way — a genuine
	# v3 record IS its own truth (counters + stamps). The migration-time
	# derivable sync (per-skill max grades) + evaluation run SaveStore-side,
	# only for records that arrived without their own namespace (the
	# orientation back-fill precedent, verbatim).
	objectives.ensure_objectives(state)
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
	combat.tick(state, sim_time_ms)  # T7: combat advances ONLY through this funnel
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


# -- T17 staffing façade (the PERSONNEL docket calls these) --

## Posting-board readouts for the UI (single source: the engine).
func posting_slots() -> int:
	return engine.posting_slots(state)


func occupied_postings() -> int:
	return engine.occupied_postings(state)


func free_postings() -> int:
	return engine.free_postings(state)


## Crowns the next DEPUTIZE RESIDENT purchase costs at the current rung
## (-1 at the full establishment — the board hides the purchase row there).
func next_deputy_price() -> int:
	return engine.deputy_price(state)


## Postings suspended by a staffing shortage, as skill-id -> slot dict (the
## parked v1-migration state; cleared per-skill on a successful re-post).
func suspended_postings() -> Dictionary:
	return state.staffing.get("suspended", {})


## DEPUTIZE RESIDENT (naming-bible §10 label): buy the next deputy, opening
## one posting. Refuses without funds (in-voice Depot wording) and at the
## full establishment (4 deputies = 5 postings). Prices come from the
## staffing ladder in content — never hardcoded here.
func deputize_resident() -> Dictionary:
	var current := clampi(int(state.staffing.get("deputies", 0)), 0, engine.MAX_DEPUTIES)
	if current >= engine.MAX_DEPUTIES:
		return {"ok": false, "reason": "FULL ESTABLISHMENT — ALL FIVE POSTINGS STAFFED",
			"deputies": current, "price": 0}
	var price := engine.deputy_price(state)
	if price <= 0:
		return {"ok": false, "reason": "no deputy posting is stocked at this counter",
			"deputies": current, "price": 0}
	if not state.try_spend_crowns(price):
		return {"ok": false, "reason": "INSUFFICIENT CROWNS (%d REQUIRED)" % price,
			"deputies": current, "price": price}
	state.staffing["deputies"] = current + 1
	orientation.note_deputize(state)  # T18: DEPUTIZE A RESIDENT stamps
	batcher.mark("staffing")
	batcher.mark("inventory")  # wallet-class change (Depot precedent)
	batcher.force_flush(sim_time_ms)
	return {"ok": true, "reason": "", "deputies": current + 1,
		"price": price, "posting_opened": current + 2}

# -- T18 orientation façade (the O-1 form + concourse cue read these) --

## One read for the form's whole render: {"done": {step_id: bool}, "count":
## int, "total": int, "complete": bool, "current": String ("" at completion),
## "target": String (department plate id the cue points at), "steps": the
## ordered step ids, "stipend": int (the data/staffing.json amount)}.
func orientation_progress() -> Dictionary:
	var done := {}
	for step_id in OrientationTracker.STEPS:
		done[step_id] = orientation.is_step_done(state, step_id)
	return {
		"done": done,
		"count": orientation.steps_done_count(state),
		"total": OrientationTracker.STEPS.size(),
		"complete": orientation.is_complete(state),
		"current": orientation.current_step(state),
		"target": orientation.current_target(state),
		"steps": OrientationTracker.STEPS.duplicate(),
		"stipend": maxi(int(engine.lib.orientation_stipend), 0),
	}


func orientation_step_done_bool(step_id: String) -> bool:
	return orientation.is_step_done(state, step_id)


# -- T23 objectives façade (the T26 dossier registers read these) --

## One read for a whole dossier: {"skill", "stamped", "total", "rows":
## [{id, description, stamped, current, target, reward_line, reward_crowns,
## reward_xp}] in posted order, "stamp_line": "ALL N STAMPED · FORM R-1"
## once complete ("" while open)}. All numbers engine truth — the UI never
## infers progress. T26 added the two reward legs so the register renders
## MERIT PAY / COMMENDATION segments without parsing the joined line.
func dossier_summary(skill_id: String) -> Dictionary:
	var summary := objectives.skill_summary(state, skill_id)
	var rows: Array[Dictionary] = []
	for obj in engine.lib.objectives_for_skill(skill_id):
		var prog := objectives.progress(state, obj.id)
		rows.append({
			"id": obj.id,
			"description": obj.description,
			"stamped": bool(prog["stamped"]),
			"current": int(prog["current"]),
			"target": int(prog["target"]),
			"reward_line": ObjectivesTracker.reward_line(obj),
			"reward_crowns": obj.reward_crowns,
			"reward_xp": obj.reward_xp_amount,
		})
	summary["rows"] = rows
	summary["stamp_line"] = "ALL %s STAMPED · FORM R-1" % SignageFmt.num(int(summary["total"])) \
		if int(summary["stamped"]) >= int(summary["total"]) and int(summary["total"]) > 0 else ""
	return summary


func is_objective_stamped(objective_id: String) -> bool:
	return objectives.is_stamped(state, objective_id)


# -- Combat façade (T7; Wasteland Patrol calls these, never ActivityEngine) --

## Engage (or switch to) a monster — the auto-battle starts. Returns
## {"ok": bool, "reason": String} — CLEARANCE wording on gate failure.
func engage_monster(monster_id: String) -> Dictionary:
	var result: Dictionary = combat.engage(state, monster_id, sim_time_ms)
	batcher.force_flush(sim_time_ms)
	return result


## Manual retreat: stop the fight (phase idle). Death needs no stop — combat
## halts itself (phase "dead", RETURN TO SHELTER, zero loss).
func stop_combat() -> void:
	combat.retreat(state)
	batcher.force_flush(sim_time_ms)


## Equip one owned equipment item (Consumes a Manifest unit; EquipmentDef
## decides the slot; the previous item returns to the Manifest).
func equip_item(item_id: String) -> Dictionary:
	var result: Dictionary = combat.equip(state, item_id)
	if bool(result.get("ok", false)):
		orientation.note_equip(state)  # T18: PROVISION THE PATROL (equip leg)
		objectives.note_equip(state, item_id)  # T23: equip lifetime counter
	batcher.force_flush(sim_time_ms)
	return result


## Empty "weapon" | "armor"; the item returns to the Manifest.
func unequip_slot(slot_key: String) -> Dictionary:
	var result := combat.unequip(state, slot_key)
	batcher.force_flush(sim_time_ms)
	return result


# -- Depot façade (T10a; the wallet lives in PlayerState, the terms in the
#    ShopEntryDef records — the UI never mutates state itself) --

## Buy `qty` units of a stocked item at the posted buy_price. Gate failures
## carry CLEARANCE wording, matching start_activity/engage_monster.
func depot_buy(item_id: String, qty: int = 1) -> Dictionary:
	if qty < 1:
		return {"ok": false, "reason": "quantity must be at least 1", "qty": 0, "crowns": 0}
	var entry := _shop_entry(item_id)
	if entry == null:
		return {"ok": false, "reason": "not stocked at this counter", "qty": 0, "crowns": 0}
	if entry.is_gated():
		var level := int(state.skills_level.get(entry.gate_skill, 1))
		if level < entry.gate_level:
			return {"ok": false, "reason": "CLEARANCE %d REQUIRED (%s)" % [
				entry.gate_level, String(engine.lib.skill(entry.gate_skill).name)],
				"qty": 0, "crowns": 0}
	var cost := entry.buy_price * qty
	if not state.try_spend_crowns(cost):
		return {"ok": false, "reason": "INSUFFICIENT CROWNS (%s REQUIRED)" % cost, "qty": 0, "crowns": 0}
	state.add_item(item_id, qty)
	batcher.mark("inventory")
	batcher.force_flush(sim_time_ms)
	return {"ok": true, "reason": "", "qty": qty, "crowns": cost}


## Sell `qty` units (qty <= 0 tenders the whole stack) at ItemDef.value —
## the one honest sell price. Returns the settled count + Crowns paid.
func depot_sell(item_id: String, qty: int = 0) -> Dictionary:
	var def := engine.lib.item(item_id)
	if def == null:
		return {"ok": false, "reason": "unknown item", "qty": 0, "crowns": 0}
	var have := state.item_count(item_id)
	var n := have if qty <= 0 else mini(qty, have)
	if n < 1:
		return {"ok": false, "reason": "NOTHING TO SELL", "qty": 0, "crowns": 0}
	state.take_item(item_id, n)
	state.add_crowns(def.value * n)
	orientation.note_sale(state)  # T18: FILE A CROWNS CLAIM (first tender)
	# T23: sell + lifetime-crowns counters (tender = the one earn path).
	objectives.note_sale(state, item_id, n, def.value * n)
	batcher.mark("inventory")
	batcher.force_flush(sim_time_ms)
	return {"ok": true, "reason": "", "qty": n, "crowns": def.value * n}


## Units the current wallet affords (0 when gated or broke).
func depot_max_affordable(item_id: String) -> int:
	var entry := _shop_entry(item_id)
	if entry == null:
		return 0
	if entry.is_gated():
		var level := int(state.skills_level.get(entry.gate_skill, 1))
		if level < entry.gate_level:
			return 0
	return state.crowns / entry.buy_price


func _shop_entry(item_id: String) -> ShopEntryDef:
	for entry in engine.lib.shop_entries():
		if entry.item == item_id:
			return entry
	return null


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
## arithmetic on the persisted per-slot RNG streams. COMBAT PROGRESSES
## OFFLINE at full rate, bounded by survivability (coordinator ruling —
## balance-notes §1.4 addendum 2): combat.apply_offline runs the seeded
## event-ordered replay over the same gap and folds kills/drops/XP deltas
## plus a PATROL RECALLED notice (when the patrol hit its survivability
## bound) into the same MAIL CALL payload.
func apply_offline_elapsed(elapsed_ms: int) -> Dictionary:
	var payload: Dictionary = engine.apply_offline(state, sim_time_ms, elapsed_ms)
	combat.apply_offline(state, sim_time_ms, elapsed_ms, payload)
	# T17: the staffing-migration notice rides the same MAIL CALL (posted even
	# with a zero gap — see the UI UPDATE CONTRACT above), then clears: it is
	# a one-time load event, never a standing deduction.
	if not _staffing_notice.is_empty():
		payload["staffing"] = {
			"notice": engine.SUSPENDED_NOTICE,
			"suspended": _staffing_notice.duplicate(true),
		}
		for s in _staffing_notice:
			payload["stopped"].append({
				"skill_id": String(s.get("skill_id", "")),
				"content_id": String(s.get("content_id", "")),
				"reason": engine.STOP_POSTING_SUSPENDED,
			})
		_staffing_notice = []
	# T23: settle the dossiers from the away window's DELTA evidence (levels
	# crossed, kills landed — gather/craft counters were already maintained
	# inside the shared _execute_action). Runs BEFORE the mail call posts so
	# the payload carries the offline stamps ({objectives: {stamps, crowns}}
	# + the folded skills_xp/levels reward legs) — the same stamps a live
	# twin of the window earns through its event hooks.
	objectives.settle_offline(state, payload)
	if int(payload["elapsed_ms"]) > 0 or payload.has("staffing") or payload.has("objectives"):
		mail_call_ready.emit(payload)
		batcher.force_flush(sim_time_ms)
	state.last_mail_call = payload
	# T18: settle the form from the away window's DELTA evidence (levels,
	# processing actions, kills) — the same stamps a live twin of the window
	# earns through its event hooks.
	orientation.settle_offline(state, payload)
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
