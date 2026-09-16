class_name ActivityEngine
extends RefCounted
## ActivityEngine — T6 activity execution core; the single source of action
## semantics for gathering activities AND processing recipes.
##
## EXACTNESS RULE (T6 acceptance a/d): the live tick loop and the closed-form
## offline catch-up both run the SAME _execute_action() once per completed
## action, in the same per-slot stream order, on the same per-slot seeded
## RandomNumberGenerator (state persisted on the slot). For the same elapsed
## milliseconds they therefore produce EXACTLY equal item/xp totals — integer
## action-count arithmetic (elapsed // interval), no float anywhere.
##
## Action timing: a slot started at anchor A with interval I completes action
## k (0-based) at sim time A + (k+1)*I. Due actions at sim time T:
## floor((T - A) / I) - completed. All int math.
##
## Concurrency semantics (Melvor-style per-skill selection, posting-limited
## since T17): ONE active activity per skill, and every active skill slot —
## plus an engaged patrol — occupies one POSTING out of the establishment's
## 1 + staffing.deputies (run-2 personnel system; starting with no free
## posting is refused with kind `posting_refused`, no preemption). Combat is
## not startable here — CombatSession.engage applies the same posting rule.
##
## OFFLINE SEMANTICS (documented T6 decision, see production-log): catch-up is
## closed-form per slot — gathering: elapsed // interval actions; recipes: the
## same count CAPPED at the save-time stockpile's affordable action count.
## Concurrent gathering does NOT feed processing recipes during offline (live
## play cross-feeds through the Manifest); the sim==closed-form equality
## guarantee therefore covers slot sets that are inventory-independent over
## the window. Per-action drop rolls ARE rolled offline (content semantics
## demand it): exactly N rolls on the slot's persisted stream, no tick sim.
##
## RNG determinism: per-slot stream seed = FNV-1a(world_seed + "|" + skill_id)
## (own implementation — stable across runs and engine versions). Rolls always
## draw (rolls-per-action in table order, then qty), so re-seeding + replaying
## the same action count reproduces totals bit-for-bit.

signal level_up(skill_id: String, old_level: int, new_level: int)
signal activity_stopped(skill_id: String, content_id: String, reason: String)

const STOP_INPUTS := "inputs_exhausted"
const STOP_REPLACED := "replaced"
const STOP_MANUAL := "stopped"

## T17 staffing (naming-bible §14 machine ids — binding).
const REFUSAL_KIND := "posting_refused"  ## refusal payload kind string
const STOP_POSTING_SUSPENDED := "posting_suspended"  ## mail-call stopped reason
const SUSPENDED_NOTICE := "POSTINGS SUSPENDED — PERSONNEL SHORTAGE"
const MAX_DEPUTIES := 4  ## 1 resident + 4 deputies = 5 postings (all skills)
## CombatSession.PHASE_FIGHTING's value, spelled here because ActivityEngine
## and CombatSession statically type each other (a literal avoids the parse
## cycle); pinned equal by tests/test_staffing.gd.
const COMBAT_FIGHTING_PHASE := "fighting"

var lib: ContentLibrary
var batcher: UpdateBatcher
## T18 orientation hook (TickManager wires its tracker here; null under bare
## ActivityEngine use). Engine-side event seam so the UI never infers step
## completion: gathering starts stamp WORK A POSTED SHIFT, completed recipe
## actions stamp PROCESS A PRODUCT (+ PROVISION THE PATROL on food output).
var orientation: OrientationTracker = null


func _init(p_lib: ContentLibrary, p_batcher: UpdateBatcher = null) -> void:
	lib = p_lib
	batcher = p_batcher if p_batcher != null else UpdateBatcher.new()


# ---------------------------------------------------------------- setup --

## Fresh state: every content skill at level 1 / 0 xp, empty Manifest, no
## currency, no active slots. `world_seed` drives every drop stream.
func new_state(world_seed: int) -> PlayerState:
	var st := PlayerState.new()
	st.world_seed = world_seed
	for skill_id: String in lib.skills:
		st.skills_xp[skill_id] = 0
		st.skills_level[skill_id] = 1
	ensure_staffing(st)
	return st


# ------------------------------------------------------------ T17 staffing --

## Repair/seed the staffing namespace in place (idempotent, allocation-free
## on a healthy state). deputies clamps into [0, MAX_DEPUTIES]; suspended is
## re-typed to a Dictionary when hydration went wrong (Hulk lens: never let a
## mangled field crash a save that holds real progress).
func ensure_staffing(state: PlayerState) -> void:
	if not (state.staffing is Dictionary):
		state.staffing = {}
	state.staffing["deputies"] = clampi(int(state.staffing.get("deputies", 0)), 0, MAX_DEPUTIES)
	if not (state.staffing.get("suspended") is Dictionary):
		state.staffing["suspended"] = {}


## The establishment's posting count: the resident's own hands + deputies.
func posting_slots(state: PlayerState) -> int:
	return 1 + clampi(int(state.staffing.get("deputies", 0)), 0, MAX_DEPUTIES)


## Postings currently held: one per active skill slot, plus one while the
## patrol is engaged (combat occupies a posting — coordinator decision, see
## the design-brief addendum).
func occupied_postings(state: PlayerState) -> int:
	var n := state.active.size()
	if str(state.combat.get("phase", "idle")) == COMBAT_FIGHTING_PHASE:
		n += 1
	return n


func free_postings(state: PlayerState) -> int:
	return maxi(posting_slots(state) - occupied_postings(state), 0)


## Refusal payload for a start/engage with no free posting (naming-bible §14:
## kind `posting_refused`, payload carries the requested content id). NO state
## change accompanies a refusal — refusal, never preemption.
func posting_refused(content_id: String) -> Dictionary:
	return {
		"ok": false,
		"reason": "POSTING REFUSED",
		"kind": REFUSAL_KIND,
		"content_id": content_id,
	}


## Crowns the NEXT deputy costs at the current establishment size (-1 at the
## full establishment / missing ladder).
func deputy_price(state: PlayerState) -> int:
	return lib.deputy_price_at(int(state.staffing.get("deputies", 0)))


## Migration-time over-subscription resolution (T17 decision, documented):
## a v1 save may carry more running skills than the v2 establishment's 1
## posting. Keep the MOST-RECENTLY-STARTED posting active (combat competes
## on its engage_ms); park the losers in staffing.suspended with their full
## slot state (anchors, completed counts, RNG positions — never silently
## dropped), withdraw a losing patrol to idle (designation preserved, zero
## loss by construction), and return one description per suspended posting
## for the MAIL CALL notice (SUSPENDED_NOTICE + STOP_POSTING_SUSPENDED lines).
## Normal v2 saves never over-subscribe — start()/engage() refuse first — so
## this is empty unless a save arrived pre-rule (or was hand-edited).
func enforce_staffing(state: PlayerState) -> Array:
	ensure_staffing(state)
	var cap := posting_slots(state)
	var entries: Array = []
	for skill_id in state.active:
		var slot: PlayerState.ActiveSlot = state.active[skill_id]
		entries.append({"ms": slot.anchor_ms, "skill_id": String(skill_id), "slot": slot})
	if str(state.combat.get("phase", "idle")) == COMBAT_FIGHTING_PHASE:
		entries.append({"ms": int(state.combat.get("engage_ms", 0)), "combat": true})
	if entries.size() <= cap:
		return []
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["ms"]) < int(b["ms"]))
	var notices: Array = []
	for e in entries.slice(0, entries.size() - cap):
		if bool(e.get("combat", false)):
			state.combat["phase"] = "idle"
			state.combat["p_next_ms"] = 0
			state.combat["m_next_ms"] = 0
			notices.append({"skill_id": _combat_skill_id(), "content_id": str(state.combat.get("monster_id", "")), "kind": "combat"})
			batcher.mark("combat")
		else:
			var skill_id := String(e["skill_id"])
			var slot: PlayerState.ActiveSlot = e["slot"]
			state.staffing["suspended"][skill_id] = slot.to_dict()
			_stop_slot(state, slot, STOP_POSTING_SUSPENDED)
			notices.append({"skill_id": skill_id, "content_id": slot.content_id, "kind": "skill"})
			batcher.mark("activity")
	return notices


func _combat_skill_id() -> String:
	for skill_id: String in lib.skills:
		if (lib.skills[skill_id] as SkillDef).is_combat():
			return skill_id
	return ""


# ------------------------------------------------- selection + gates --

## Content record lookup by id across activities + recipes (null if unknown).
func def_of(content_id: String) -> RefCounted:
	if lib.activities.has(content_id):
		return lib.activity(content_id)
	if lib.recipes.has(content_id):
		return lib.recipe(content_id)
	return null


## Clearance gate of an activity/recipe: {"skill": id, "level": n} ({} if the
## id is unknown). T10 renders locked entries as CLEARANCE plates from this.
func gate_of(content_id: String) -> Dictionary:
	var def := def_of(content_id)
	if def == null:
		return {}
	if def is ActivityDef:
		return {"skill": (def as ActivityDef).skill, "level": (def as ActivityDef).level_gate}
	return {"skill": (def as RecipeDef).skill, "level": (def as RecipeDef).level_gate}


func is_unlocked(state: PlayerState, content_id: String) -> bool:
	var gate := gate_of(content_id)
	if gate.is_empty():
		return false
	return int(state.skills_level.get(gate["skill"], 1)) >= int(gate["level"])


## Start (or switch) the skill's active slot. Replaces any current slot on
## that skill (emits activity_stopped STOP_REPLACED). Returns
## {"ok": bool, "reason": ""} — gate failures carry CLEARANCE wording for T10;
## a full posting board returns kind "posting_refused" (naming-bible §14)
## with NO state change.
func start(state: PlayerState, content_id: String, now_ms: int) -> Dictionary:
	var def := def_of(content_id)
	if def == null:
		return {"ok": false, "reason": "unknown activity '%s'" % content_id}
	var skill_id: String
	var interval: int
	if def is ActivityDef:
		var a := def as ActivityDef
		skill_id = a.skill
		interval = a.interval_ms
	else:
		var r := def as RecipeDef
		skill_id = r.skill
		interval = r.interval_ms
	var skill := lib.skill(skill_id)
	if skill == null:
		return {"ok": false, "reason": "activity '%s' references unknown skill '%s'" % [content_id, skill_id]}
	if skill.is_combat():
		return {"ok": false, "reason": "combat is engaged from the Wasteland, not started here"}
	var gate_level := _gate_level_of(def)
	if int(state.skills_level.get(skill_id, 1)) < gate_level:
		return {"ok": false, "reason": "CLEARANCE %d REQUIRED (%s)" % [gate_level, skill.name]}
	# T17 posting board: switching THIS skill's own slot keeps its posting
	# (occupied count unchanged); opening a posting on a new skill with none
	# free is REFUSED — no state change, never silent preemption.
	if not state.active.has(skill_id) and free_postings(state) <= 0:
		return posting_refused(content_id)
	if state.active.has(skill_id):
		_stop_slot(state, state.active[skill_id], STOP_REPLACED)
	var slot := PlayerState.ActiveSlot.new()
	slot.skill_id = skill_id
	slot.content_id = content_id
	slot.is_recipe = not (def is ActivityDef)
	slot.interval_ms = interval
	slot.anchor_ms = now_ms
	slot.rng_seed = _stream_seed(state.world_seed, skill_id)
	state.active[skill_id] = slot
	# A fresh posting on this skill supersedes any paused (suspended) one —
	# the parked entry is remembered state, not a reservation.
	if state.staffing.get("suspended", {}).has(skill_id):
		state.staffing["suspended"].erase(skill_id)
	# T18: a started gathering shift stamps WORK A POSTED SHIFT (the recipe
	# path stamps through _execute_action instead).
	if orientation != null:
		orientation.note_activity_started(state, slot)
	batcher.mark("activity")
	return {"ok": true, "reason": ""}


func stop(state: PlayerState, skill_id: String) -> void:
	if state.active.has(skill_id):
		_stop_slot(state, state.active[skill_id], STOP_MANUAL)


func active_slot(state: PlayerState, skill_id: String) -> PlayerState.ActiveSlot:
	return state.active.get(skill_id)


## Canonical slot order (sorted skill ids) — both the tick loop and offline
## catch-up process slots in this order so action order is reproducible.
func _slot_order(state: PlayerState) -> Array[String]:
	var keys: Array[String] = []
	for skill_id in state.active:
		keys.append(String(skill_id))
	keys.sort()
	return keys


func _gate_level_of(def: RefCounted) -> int:
	if def is ActivityDef:
		return (def as ActivityDef).level_gate
	return (def as RecipeDef).level_gate


# ------------------------------------------------------------- live sim --

## Advance every active slot to absolute sim time `now_ms`. Batches all due
## actions per slot (a stalled frame that owes several intervals executes the
## exact owed count — no per-100 ms replay). Cheap when nothing is due.
func tick(state: PlayerState, now_ms: int) -> void:
	for skill_id in _slot_order(state):
		var slot: PlayerState.ActiveSlot = state.active.get(skill_id)
		if slot == null:
			continue
		var due := _due_count(slot, now_ms)
		for i in due:
			if not _execute_action(state, slot, true):
				break


## Actions owed by `now_ms` under the anchor model (int floor arithmetic).
func _due_count(slot: PlayerState.ActiveSlot, now_ms: int) -> int:
	var due := (now_ms - slot.anchor_ms) / slot.interval_ms - slot.completed
	return maxi(due, 0)


## ONE completed action — the exactness keystone shared by live sim and
## offline catch-up. Returns false when the slot stopped itself (recipe ran
## out of inputs). `emit_levels` is false during offline batches (the MAIL
## CALL payload carries level crossings instead; see contract in TickManager).
func _execute_action(state: PlayerState, slot: PlayerState.ActiveSlot, emit_levels: bool) -> bool:
	if slot.is_recipe:
		var rdef: RecipeDef = lib.recipe(slot.content_id)
		if rdef == null:
			_stop_slot(state, slot, "content_missing")
			return false
		for input in rdef.inputs:
			if state.item_count(input.item) < input.qty:
				_stop_slot(state, slot, STOP_INPUTS)
				return false
		for input in rdef.inputs:
			state.take_item(input.item, input.qty)
		state.add_item(rdef.output.item, rdef.output.qty)
		slot.completed += 1
		_grant_xp(state, rdef.skill, rdef.xp_per_action, emit_levels)
		# T18: one completed craft stamps the orientation form's product step
		# (and the patrol's provisions when the output is food).
		if orientation != null:
			orientation.note_recipe_completed(state, rdef)
	else:
		var adef: ActivityDef = lib.activity(slot.content_id)
		if adef == null:
			_stop_slot(state, slot, "content_missing")
			return false
		var rng := _slot_rng(slot)
		_roll_action(lib.drop_table(adef.drop_table), rng, state)
		_store_rng(slot, rng)
		slot.completed += 1
		_grant_xp(state, adef.skill, adef.xp_per_action, emit_levels)
	batcher.mark("inventory")
	batcher.mark("xp")
	return true


## XP + level derivation. Emits level_up once per level crossed (immediate,
## discrete) when `emit_levels` — offline passes false and diffs levels into
## the payload instead.
func _grant_xp(state: PlayerState, skill_id: String, amount: int, emit_levels: bool) -> void:
	var skill := lib.skill(skill_id)
	var curve := lib.xp_curve(skill.xp_curve)
	var xp := int(state.skills_xp.get(skill_id, 0)) + amount
	state.skills_xp[skill_id] = xp
	var old_level := int(state.skills_level.get(skill_id, 1))
	var new_level := curve.level_for_total_xp(xp)
	state.skills_level[skill_id] = new_level
	if emit_levels:
		var level := old_level
		while level < new_level:
			level += 1
			level_up.emit(skill_id, level - 1, level)
	batcher.mark("xp")


## Debug/cheat + T7 hook: raw xp grant through the same level pipeline.
## `emit_levels = false` is T7's offline-combat path (crossings ride the MAIL
## CALL payload instead of immediate signals — the same policy T6 applies to
## offline activity level-ups; the one small ActivityEngine API extension of
## T7, default-preserving).
func grant_xp(state: PlayerState, skill_id: String, amount: int, emit_levels: bool = true) -> void:
	_grant_xp(state, skill_id, amount, emit_levels)


func _stop_slot(state: PlayerState, slot: PlayerState.ActiveSlot, reason: String) -> void:
	state.active.erase(slot.skill_id)
	batcher.mark("activity")
	activity_stopped.emit(slot.skill_id, slot.content_id, reason)


# ---------------------------------------------------------- drop rolls --

## One action's drop: `table.rolls` independent weighted picks, qty drawn
## uniformly in [qty_min, qty_max]. Draw order is fixed (pick then qty, entry
## order) — it IS the determinism contract; do not reorder.
func _roll_action(table: DropTableDef, rng: RandomNumberGenerator, state: PlayerState) -> void:
	var total := table.total_weight()
	for r in table.rolls:
		var pick := rng.randi_range(1, total)
		var acc := 0
		for entry in table.entries:
			acc += entry.weight
			if pick <= acc:
				var qty := entry.qty_min
				if entry.qty_max > entry.qty_min:
					qty = rng.randi_range(entry.qty_min, entry.qty_max)
				state.add_item(entry.item, qty)
				break


func _slot_rng(slot: PlayerState.ActiveSlot) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = slot.rng_seed
	if slot.stream_started:
		rng.state = slot.rng_state
	return rng


func _store_rng(slot: PlayerState.ActiveSlot, rng: RandomNumberGenerator) -> void:
	slot.rng_state = rng.state
	slot.stream_started = true


## FNV-1a 64-bit over UTF-8 bytes — our own stable hash (Godot's String.hash()
## is stable today; this removes any doubt for save replay). The offset basis
## is written as its two's-complement int64 (GDScript ints are signed; the
## hex literal 0xcbf29ce484222325 would overflow and error).
func _stream_seed(world_seed: int, skill_id: String) -> int:
	var h: int = -3750763034362895579  # 0xcbf29ce484222325 - 2^64 (FNV basis)
	var bytes := (str(world_seed) + "|" + skill_id).to_utf8_buffer()
	for b in bytes:
		h = (h ^ b)
		h = h * 0x100000001b3  # FNV 64-bit prime (fits int64)
	return h


# ----------------------------------------------------- offline catch-up --

## Closed-form offline catch-up. `now_ms` is the sim clock at save/quit (the
## slot anchors live on it); `elapsed_ms` is the wall gap since the save
## timestamp. ZERO simulation: per slot, owed = floor((now + elapsed - anchor)
## / interval) - completed (recipes capped at the affordable stockpile count),
## those actions execute through the same _execute_action on the persisted
## per-slot RNG stream, then the anchor rewinds by exactly `elapsed_ms` (the
## phase remainder carries; proof: anchor' = anchor - E keeps
## floor((now - anchor')/I) == completed'). Returns the MAIL CALL payload:
##
##   {
##     "elapsed_ms": int,             # 0 when the clock ran backwards
##     "skills_xp":  {skill: gained}, # per-skill xp gained
##     "items":      {item: gained},  # per-item stack delta (recipes may net negative inputs)
##     "levels":     {skill: {"from": int, "to": int}},
##     "actions":    {skill: completed_action_count},
##     "stopped":    [{"skill_id", "content_id", "reason"}]  # recipes that ran dry
##   }
##
## elapsed_ms <= 0 (clock backwards / same instant) is a zero-gain no-op —
## never an error, never negative gains (T6 acceptance d, T14 guard).
func apply_offline(state: PlayerState, now_ms: int, elapsed_ms: int) -> Dictionary:
	var payload := {
		"elapsed_ms": 0,
		"skills_xp": {},
		"items": {},
		"levels": {},
		"actions": {},
		"stopped": [],
	}
	if elapsed_ms <= 0:
		state.last_mail_call = payload
		return payload
	payload["elapsed_ms"] = elapsed_ms
	var xp0 := state.skills_xp.duplicate()
	var inv0 := state.inventory.duplicate()
	var lvl0 := state.skills_level.duplicate()
	for skill_id in _slot_order(state):
		var slot: PlayerState.ActiveSlot = state.active.get(skill_id)
		if slot == null:
			continue
		var time_due := _due_count(slot, now_ms + elapsed_ms)
		var n := time_due
		if slot.is_recipe:
			var affordable := _affordable_actions(state, slot)
			if time_due > affordable:
				n = affordable
		var done := 0
		for i in n:
			if not _execute_action(state, slot, false):
				break
			done += 1
		slot.anchor_ms -= elapsed_ms
		payload["actions"][skill_id] = done
		if slot.is_recipe and time_due > n:
			payload["stopped"].append({
				"skill_id": slot.skill_id,
				"content_id": slot.content_id,
				"reason": STOP_INPUTS,
			})
			_stop_slot(state, slot, STOP_INPUTS)
	# Diffs (ints only; omit zeros).
	for skill_id in state.skills_xp:
		var gained := int(state.skills_xp[skill_id]) - int(xp0.get(skill_id, 0))
		if gained != 0:
			payload["skills_xp"][skill_id] = gained
		var from_l := int(lvl0.get(skill_id, 1))
		var to_l := int(state.skills_level.get(skill_id, 1))
		if to_l > from_l:
			payload["levels"][skill_id] = {"from": from_l, "to": to_l}
	for item_id in state.inventory:
		var delta := int(state.inventory[item_id]) - int(inv0.get(item_id, 0))
		if delta != 0:
			payload["items"][item_id] = delta
	state.last_mail_call = payload
	batcher.mark("xp")
	batcher.mark("inventory")
	return payload


## Max crafts the CURRENT inventory affords (multi-input min, int division).
func _affordable_actions(state: PlayerState, slot: PlayerState.ActiveSlot) -> int:
	var rdef: RecipeDef = lib.recipe(slot.content_id)
	if rdef == null or rdef.inputs.is_empty():
		return 0
	var affordable := -1
	for input in rdef.inputs:
		var can := state.item_count(input.item) / input.qty
		affordable = can if affordable < 0 else mini(affordable, can)
	return maxi(affordable, 0)


# -------------------------------------------------- T10 gauge helpers --

## Ms elapsed into the slot's current action at `now_ms` (0..interval-1).
func slot_phase_ms(state: PlayerState, skill_id: String, now_ms: int) -> int:
	var slot := active_slot(state, skill_id)
	if slot == null:
		return 0
	var phase := maxi(now_ms - slot.anchor_ms, 0) - slot.completed * slot.interval_ms
	return clampi(phase, 0, slot.interval_ms - 1)
