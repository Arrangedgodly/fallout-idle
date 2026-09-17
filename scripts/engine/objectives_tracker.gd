class_name ObjectivesTracker
extends RefCounted
## ObjectivesTracker — T23 the DEPARTMENTAL DOSSIER engine (Iron Man
## architecture + Hulk resilience lens; the OrientationTracker two-tier
## pattern generalized).
##
## Tier 1 — LIFETIME COUNTERS (`engine.objectives.counters`, save v3): pure
## integer counts maintained from the EXISTING engine seams, never inferred
## by the UI:
##   activity:<id>         completed gathering actions of one activity
##   item_gathered:<id>    units of one item gained from activity drop rolls
##   recipe:<id>           completed crafts of one recipe
##   monster:<id>          victories over one monster
##   zone:<id>             times one zone's boss was defeated
##   item_sold:<id>        units tendered at the Depot
##   item_equipped:<id>    times one equipment item was equipped
##   level:<skill>         max clearance grade reached in one skill
##   crowns                Crowns earned LIFETIME (posted, never spent)
##   stamped:<skill>       objectives stamped in one skill (DERIVED cache —
##                         rebuilt from the stamped set by ensure_objectives)
## Gather/craft counters update INSIDE ActivityEngine._execute_action — the
## exactness keystone shared by the live tick and the closed-form offline
## catch-up — so counters are identical between a live twin and an offline
## twin of the same window BY CONSTRUCTION (no settlement math for them).
##
## Tier 2 — EVALUATION (stamping + auto-grant): whenever a counter changes on
## a LIVE seam, every unstamped objective whose condition holds STAMPS exactly
## once (`objectives.stamped` + `objectives.rewards_granted`, both in file
## order = the canonical posted order), rewards post themselves through the
## existing wallet/XP paths (state.add_crowns / ActivityEngine.grant_xp —
## MERIT PAY counts toward the lifetime-crowns counter, honest recursion),
## and one `objective_stamped` notice fires immediately (the O-1 "· N CROWNS
## POSTED" idiom; kind string per naming-bible §15). Set-completion
## (`stamped_count`) re-arms the scan so cascades stamp in the same pass.
## OFFLINE, per-action counter updates skip evaluation (the emit_levels=false
## discipline); settle_offline() evaluates ONCE from the mail-call payload's
## deltas (levels crossed, kills landed) and folds the stamps + reward legs
## into the payload's `objectives` section for the MAIL CALL notice — XP legs
## grant with emit_levels=false and their crossings merge into payload.levels.
##
## MIGRATION POLICY (v2 -> v3, documented decision): counters whose lifetime
## truth is DERIVABLE from the loaded record sync at adopt (per-skill max
## level from skills_level); everything with no derivable evidence (per-
## activity/recipe/monster/item counts, lifetime crowns earned, stamps) starts
## at ZERO — the O-1 back-fill precedent stamps only what state can prove,
## and per-item lifetime totals are not provable from a v2 record. A veteran
## re-earns count objectives from the migration session onward (zone clears
## stay live: the condition counts boss defeats, which remain repeatable);
## level-ladder objectives stamp instantly from the synced grades. Honest
## and simple beats a guessed reconstruction.
##
## Signals (re-emitted by TickManager — T26 binds there; T23 ships no UI):
##   objective_stamped(payload)   immediate, once per objective, ever:
##       {kind: "objective_stamped", id, skill, description, crowns,
##        xp_skill, xp_amount, reward_line, notice_line}
##   dossier_completed(payload)   immediate, when a skill's LAST objective
##       stamps: {skill, total, stamp_line} — "ALL N STAMPED · FORM R-1"
##       (N from data, never hardcoded). Re-arms if content later adds
##       objectives to a completed dossier.
##
## Bulk regions: every stamp marks "objectives"; reward legs additionally
## mark "inventory" (wallet-class, Depot precedent) and "xp" (XP legs).

signal objective_stamped(payload: Dictionary)
signal dossier_completed(payload: Dictionary)

const NOTICE_KIND := "objective_stamped"  ## naming-bible §15 binding kind string

var lib: ContentLibrary
var batcher: UpdateBatcher
var xp_engine: ActivityEngine  ## shared XP/level pipeline (grant_xp), may be null in bare use


func _init(p_lib: ContentLibrary, p_batcher: UpdateBatcher = null, p_xp_engine: ActivityEngine = null) -> void:
	lib = p_lib
	batcher = p_batcher if p_batcher != null else UpdateBatcher.new()
	xp_engine = p_xp_engine
	_build_counter_index()


## T25 performance index: counter key -> the objective ids that read it, in
## canonical posted order. A live seam bumps a handful of counters per event;
## before the index every bump re-walked ALL objectives (a 115-line set cost
## ~0.5 ms per action through the worst-case 4-posting window). The live seams
## now evaluate only what they touched (evaluate_touching); the full fixpoint
## evaluate() still runs at boot/adopt/settlement and after any stamp (the
## cascade path: MERIT PAY feeds the lifetime-crowns counter, stamped_count
## re-arms) — behavior-identical by construction, proven by the T23 matrix.
var _by_counter: Dictionary = {}


func _build_counter_index() -> void:
	_by_counter = {}
	var ids: Array = lib.objectives.keys()  # file order == insertion order
	ids.sort_custom(_posted_order)
	for obj_id in ids:
		var obj: ObjectiveDef = lib.objectives[obj_id]
		if obj.counter_key == "":
			continue  # hand-built defs (tests) fall back to the full walk
		if not _by_counter.has(obj.counter_key):
			_by_counter[obj.counter_key] = [] as Array[String]
		(_by_counter[obj.counter_key] as Array[String]).append(String(obj_id))


# ---------------------------------------------------------------- namespace --

## Repair/seed the objectives namespace in place (idempotent, Hulk lens: a
## mangled field never crashes a save that holds real progress). Counters
## re-type to ints, unknown counter keys and unknown objective ids DROP
## (saves are engine-owned — the save-schema's unknown-key rule), both id
## arrays re-sort into the canonical posted (file) order, and the derived
## stamped:<skill> counters rebuild from the stamped set.
func ensure_objectives(state: PlayerState) -> void:
	if not (state.objectives is Dictionary):
		state.objectives = {}
	if not (state.objectives.get("counters") is Dictionary):
		state.objectives["counters"] = {}
	var counters: Dictionary = state.objectives["counters"]
	var clean_counters := {}
	for key in counters:
		var k := String(key)
		if _is_valid_counter_key(k):
			clean_counters[k] = maxi(int(counters[key]), 0)
	state.objectives["counters"] = clean_counters
	state.objectives["stamped"] = _clean_id_array(state.objectives.get("stamped", []))
	state.objectives["rewards_granted"] = _clean_id_array(state.objectives.get("rewards_granted", []))
	_rebuild_stamped_counters(state)


func is_stamped(state: PlayerState, objective_id: String) -> bool:
	var stamped: Array = state.objectives.get("stamped", [])
	return stamped is Array and stamped.has(objective_id)


## Stamps-vs-total for one dossier (the "12/24 STAMPED" readout).
func skill_summary(state: PlayerState, skill_id: String) -> Dictionary:
	var total := lib.objectives_for_skill(skill_id).size()
	return {"skill": skill_id, "stamped": stamped_count_for_skill(state, skill_id), "total": total}


func stamped_count_for_skill(state: PlayerState, skill_id: String) -> int:
	var n := 0
	for obj_id in lib.objectives:
		if (lib.objectives[obj_id] as ObjectiveDef).skill == skill_id and is_stamped(state, String(obj_id)):
			n += 1
	return n


## One register row's progress readout: {"current": int, "target": int,
## "stamped": bool} — current reads the LIVE counter (clamped for display).
func progress(state: PlayerState, objective_id: String) -> Dictionary:
	var obj: ObjectiveDef = lib.objective(objective_id)
	if obj == null:
		return {"current": 0, "target": 0, "stamped": false}
	return {"current": mini(count_for(state, obj), obj.target), "target": obj.target,
		"stamped": is_stamped(state, objective_id)}


func _clean_id_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for entry in raw:
			var oid := String(entry)
			if lib.objectives.has(oid) and not out.has(oid):
				out.append(oid)
	out.sort_custom(_posted_order)
	return out


func _posted_order(a, b) -> bool:
	return lib.objective_order_index(String(a)) < lib.objective_order_index(String(b))


func _is_valid_counter_key(key: String) -> bool:
	if key == "crowns":
		return true
	var parts := key.split(":", true, 1)
	if parts.size() != 2:
		return false
	match parts[0]:
		"level", "stamped": return lib.skills.has(parts[1])
		"activity": return lib.activities.has(parts[1])
		"recipe": return lib.recipes.has(parts[1])
		"monster": return lib.monsters.has(parts[1])
		"zone": return lib.zones.has(parts[1])
		"item_sold", "item_gathered", "item_equipped": return lib.items.has(parts[1])
		_: return false


func _rebuild_stamped_counters(state: PlayerState) -> void:
	var counters: Dictionary = state.objectives["counters"]
	for key in counters.keys():
		if String(key).begins_with("stamped:"):
			counters.erase(key)
	var per_skill := {}
	for oid in state.objectives["stamped"]:
		var obj: ObjectiveDef = lib.objectives.get(String(oid))
		if obj != null:
			per_skill[obj.skill] = int(per_skill.get(obj.skill, 0)) + 1
	for skill_id in per_skill:
		counters["stamped:%s" % skill_id] = per_skill[skill_id]


# ------------------------------------------------------------- tier-1 seams --

## One completed GATHERING action (ActivityEngine._execute_action — live AND
## offline: counters always update through the shared keystone; `evaluate_now`
## is the emit_levels discipline — live stamps immediately, offline defers to
## settle_offline). `drops` is the action's per-item yield.
## T25 seam discipline: new_game / adopt_state / evaluate own
## ensure_objectives (the repair contract — every live state is ensured before
## any seam can run); the seams seed the counters dict only if it is missing
## (a ~free guard for bare tracker use) and evaluate through the counter
## index (evaluate_touching) instead of walking the whole set per action.
func _counters(state: PlayerState) -> Dictionary:
	if not (state.objectives.get("counters") is Dictionary):
		ensure_objectives(state)
	return state.objectives["counters"]


func note_gather_action(state: PlayerState, adef: ActivityDef, drops: Dictionary, evaluate_now: bool) -> void:
	if adef == null:
		return
	var counters := _counters(state)
	var touched: Array[String] = ["activity:%s" % adef.id]
	_bump(counters, "activity:%s" % adef.id, 1)
	for item_id in drops:
		var key := "item_gathered:%s" % item_id
		_bump(counters, key, int(drops[item_id]))
		touched.append(key)
	if evaluate_now:
		evaluate_touching(state, touched)


## One completed CRAFT action (same seam contract as note_gather_action).
func note_craft_action(state: PlayerState, rdef: RecipeDef, evaluate_now: bool) -> void:
	if rdef == null:
		return
	var key := "recipe:%s" % rdef.id
	_bump(_counters(state), key, 1)
	if evaluate_now:
		evaluate_touching(state, [key])


## One Depot tender (TickManager.depot_sell): units sold + Crowns posted.
func note_sale(state: PlayerState, item_id: String, qty: int, crowns: int) -> void:
	var counters := _counters(state)
	_bump(counters, "item_sold:%s" % item_id, maxi(qty, 0))
	_bump(counters, "crowns", maxi(crowns, 0))
	evaluate_touching(state, ["item_sold:%s" % item_id, "crowns"])


## One equip through the Manifest (TickManager.equip_item).
func note_equip(state: PlayerState, item_id: String) -> void:
	var key := "item_equipped:%s" % item_id
	_bump(_counters(state), key, 1)
	evaluate_touching(state, [key])


## One combat victory (TickManager's combat_ended hook). A boss defeat also
## counts as one clear of the boss's zone (repeatable — re-kills re-secure).
func note_victory(state: PlayerState, monster_id: String) -> void:
	var counters := _counters(state)
	var touched: Array[String] = ["monster:%s" % monster_id]
	_bump(counters, "monster:%s" % monster_id, 1)
	var mdef: MonsterDef = lib.monster(monster_id)
	if mdef != null and mdef.is_boss:
		var zkey := "zone:%s" % mdef.zone
		_bump(counters, zkey, 1)
		touched.append(zkey)
	evaluate_touching(state, touched)


## A live level crossing (TickManager's engine.level_up hook).
func note_level_up(state: PlayerState, skill_id: String, new_level: int) -> void:
	var key := "level:%s" % skill_id
	var counters := _counters(state)
	counters[key] = maxi(int(counters.get(key, 0)), new_level)
	evaluate_touching(state, [key])


## Crowns posted outside a Depot tender (the O-1 stipend; the tracker's own
## MERIT PAY grants bump the counter directly inside _stamp instead).
func note_crowns_posted(state: PlayerState, amount: int) -> void:
	if amount <= 0:
		return
	_bump(_counters(state), "crowns", amount)
	evaluate_touching(state, ["crowns"])


# ------------------------------------------------------------- adopt + sync --

## Load-time derivation sync (the documented migration policy): per-skill max
## grades are PROVABLE from the record (skills_level re-derives from xp), so
## they sync into the counters; nothing else is derivable — see the header.
## Runs on every adopt; monotone (max), so a genuine v3 record is unchanged
## and live/reloaded twin dicts stay byte-equal.
func sync_derivable(state: PlayerState) -> void:
	ensure_objectives(state)
	var counters: Dictionary = state.objectives["counters"]
	for skill_id in state.skills_level:
		var key := "level:%s" % skill_id
		var lvl := int(state.skills_level[skill_id])
		counters[key] = maxi(int(counters.get(key, 0)), lvl)


# ------------------------------------------------------------ tier-2 evaluate --

## The condition's current count against the counters (public read path for
## progress(); unstamped stamped_count reads the OTHER objectives of the
## skill — the open objective never counts itself). Precondition: the state
## passed a seam/adopt/new_game (all of which ensure_objectives first).
func count_for(state: PlayerState, obj: ObjectiveDef) -> int:
	if obj == null:
		return 0
	var counters: Dictionary = state.objectives.get("counters", {})
	if obj.counter_key != "":
		return int(counters.get(obj.counter_key, 0))
	match obj.kind:
		ObjectiveDef.KIND_LEVEL_REACH:
			return int(counters.get("level:%s" % obj.skill, 0))
		ObjectiveDef.KIND_GATHER_COUNT:
			var key := ("activity:%s" if obj.gather_ref_is_activity else "item_gathered:%s") % obj.ref
			return int(counters.get(key, 0))
		ObjectiveDef.KIND_CRAFT_COUNT:
			return int(counters.get("recipe:%s" % obj.ref, 0))
		ObjectiveDef.KIND_KILL_COUNT:
			return int(counters.get("monster:%s" % obj.ref, 0))
		ObjectiveDef.KIND_SELL_COUNT:
			return int(counters.get("item_sold:%s" % obj.ref, 0))
		ObjectiveDef.KIND_EQUIP_ITEM:
			return int(counters.get("item_equipped:%s" % obj.ref, 0))
		ObjectiveDef.KIND_ZONE_CLEAR:
			return int(counters.get("zone:%s" % obj.ref, 0))
		ObjectiveDef.KIND_STAMPED_COUNT:
			return int(counters.get("stamped:%s" % obj.skill, 0))
		ObjectiveDef.KIND_CROWNS_TOTAL:
			return int(counters.get("crowns", 0))
	return 0


## Scan every unstamped objective; stamp each whose condition holds, to a
## fixpoint (set-completion cascades). Returns the stamp payloads of THIS
## call (empty when nothing crossed — settle_offline folds them into the
## mail-call payload). `emit_levels` follows the shared grant_xp discipline:
## live calls pass true (XP legs may cross levels + emit level_up, whose hook
## can re-enter evaluate — idempotent by the stamped-set guard, safe);
## settle_offline passes false and folds crossings into the payload instead.
func evaluate(state: PlayerState, emit_levels := true) -> Array[Dictionary]:
	ensure_objectives(state)
	var stamps: Array[Dictionary] = []
	var guard := 0
	var changed := true
	while changed and guard <= lib.objectives.size():
		changed = false
		guard += 1
		for obj_id in lib.objectives:
			var obj: ObjectiveDef = lib.objectives[obj_id]
			if is_stamped(state, obj.id):
				continue
			if count_for(state, obj) >= obj.target:
				stamps.append(_stamp(state, obj, emit_levels))
				changed = true
	return stamps


## LIVE-SEAM evaluation (T25): only the objectives that read one of the
## just-bumped `keys` can newly hold (counters are monotone — nothing else
## changed), so the per-action cost is a handful of checks instead of a walk
## of the whole set. Candidates merge + dedup + sort into the canonical
## posted order first, so a multi-key event (a gather action bumps its
## activity counter AND item-yield counters) stamps in exactly the order the
## full evaluate() would. ANY stamp falls back to the full fixpoint evaluate()
## — the cascade path (MERIT PAY feeds lifetime crowns; stamped_count re-arms)
## is unchanged. Offline keeps the deferred discipline (evaluate_now=false
## seams never call this; settle_offline runs the full evaluate).
func evaluate_touching(state: PlayerState, keys: Array) -> Array[Dictionary]:
	if keys.is_empty():
		return []
	var candidates := {}
	for key in keys:
		for obj_id in (_by_counter.get(String(key), []) as Array):
			candidates[obj_id] = true
	if candidates.is_empty():
		return []
	var ordered: Array = candidates.keys()
	ordered.sort_custom(_posted_order)
	var stamps: Array[Dictionary] = []
	for obj_id in ordered:
		var obj: ObjectiveDef = lib.objective(String(obj_id))
		if obj == null or is_stamped(state, obj.id):
			continue
		if count_for(state, obj) >= obj.target:
			stamps.append(_stamp(state, obj, true))
	if not stamps.is_empty():
		stamps.append_array(evaluate(state))
	return stamps


## Stamp one objective EXACTLY once: file-order sets first (the guards),
## counters + rewards next, notice last. Rewards: MERIT PAY posts through the
## wallet and counts toward lifetime crowns; COMMENDATION posts through the
## shared XP pipeline.
func _stamp(state: PlayerState, obj: ObjectiveDef, emit_levels: bool) -> Dictionary:
	var stamped: Array = state.objectives["stamped"]
	var granted: Array = state.objectives["rewards_granted"]
	stamped.append(obj.id)
	granted.append(obj.id)
	stamped.sort_custom(_posted_order)
	granted.sort_custom(_posted_order)
	var counters: Dictionary = state.objectives["counters"]
	_bump(counters, "stamped:%s" % obj.skill, 1)
	var payload := {
		"kind": NOTICE_KIND,
		"id": obj.id,
		"skill": obj.skill,
		"description": obj.description,
		"crowns": obj.reward_crowns,
		"xp_skill": obj.reward_xp_skill,
		"xp_amount": obj.reward_xp_amount,
		"reward_line": reward_line(obj),
		"notice_line": notice_line(obj),
	}
	if obj.reward_crowns > 0:
		state.add_crowns(obj.reward_crowns)
		_bump(counters, "crowns", obj.reward_crowns)  # merit pay is earned crowns
		if batcher != null:
			batcher.mark("inventory")
	if obj.has_xp_reward() and xp_engine != null:
		xp_engine.grant_xp(state, obj.reward_xp_skill, obj.reward_xp_amount, emit_levels)
		if batcher != null:
			batcher.mark("xp")
	if batcher != null:
		batcher.mark("objectives")
	objective_stamped.emit(payload)
	# The dossier's full stamp: last objective of the skill, in this pass.
	var skill_total := lib.objectives_for_skill(obj.skill).size()
	if stamped_count_for_skill(state, obj.skill) >= skill_total and skill_total > 0:
		dossier_completed.emit({
			"skill": obj.skill,
			"total": skill_total,
			"stamp_line": "ALL %s STAMPED · FORM R-1" % SignageFmt.num(skill_total),
		})
	return payload


static func reward_line(obj: ObjectiveDef) -> String:
	var parts: Array[String] = []
	if obj.reward_crowns > 0:
		parts.append("MERIT PAY · %s CROWNS" % SignageFmt.num(obj.reward_crowns))
	if obj.has_xp_reward():
		parts.append("COMMENDATION · %s XP" % SignageFmt.num(obj.reward_xp_amount))
	return " · ".join(parts)


static func notice_line(obj: ObjectiveDef) -> String:
	var legs: Array[String] = []
	if obj.reward_crowns > 0:
		legs.append("%s CROWNS" % SignageFmt.num(obj.reward_crowns))
	if obj.has_xp_reward():
		legs.append("%s XP" % SignageFmt.num(obj.reward_xp_amount))
	return "FORM R-1 STAMPED · %s POSTED" % " · ".join(legs)


# ------------------------------------------------------------ offline settle --

## OFFLINE settlement — DELTA evidence from the MAIL CALL payload (what the
## away window actually did): levels crossed + kills landed fold into the
## counters, then one deferred evaluation stamps what crossed. Gather/craft
## counters need NO settlement (the shared _execute_action maintained them).
## Reward legs fold back into the payload (XP into skills_xp/levels, stamps +
## Crowns into payload.objectives) so the MAIL CALL notice carries them —
## the offline twin of the live immediate notices.
func settle_offline(state: PlayerState, payload: Dictionary) -> void:
	ensure_objectives(state)
	var counters: Dictionary = state.objectives["counters"]
	var levels: Dictionary = payload.get("levels", {})
	for skill_id in levels:
		var cross: Dictionary = levels[skill_id]
		var key := "level:%s" % skill_id
		counters[key] = maxi(int(counters.get(key, 0)), int(cross.get("to", 0)))
	var combat: Dictionary = payload.get("combat", {})
	var kills := int(combat.get("kills", 0))
	var monster_id := str(combat.get("monster_id", ""))
	if kills > 0 and monster_id != "":
		_bump(counters, "monster:%s" % monster_id, kills)
		var mdef: MonsterDef = lib.monster(monster_id)
		if mdef != null and mdef.is_boss:
			_bump(counters, "zone:%s" % mdef.zone, kills)
	# Snapshot, evaluate, fold the reward legs into the payload.
	var xp0 := state.skills_xp.duplicate()
	var lvl0 := state.skills_level.duplicate()
	var crowns0 := state.crowns
	var stamps := evaluate(state, false)
	if stamps.is_empty():
		return
	for skill_id in state.skills_xp:
		var gained := int(state.skills_xp[skill_id]) - int(xp0.get(skill_id, 0))
		if gained > 0:
			payload["skills_xp"][skill_id] = int(payload["skills_xp"].get(skill_id, 0)) + gained
		var to_l := int(state.skills_level.get(skill_id, 1))
		if to_l > int(lvl0.get(skill_id, 1)):
			var from_l := int(lvl0.get(skill_id, 1))
			if payload["levels"].has(skill_id):
				from_l = mini(from_l, int(payload["levels"][skill_id]["from"]))
			payload["levels"][skill_id] = {"from": from_l, "to": to_l}
	var crowns_gain := state.crowns - crowns0
	payload["objectives"] = {"stamps": stamps, "crowns": maxi(crowns_gain, 0)}
	# Levels crossed by reward XP also count toward the max-grade counters
	# (the live twin gets them through the level_up hook).
	sync_derivable(state)


func _bump(counters: Dictionary, key: String, by: int) -> void:
	counters[key] = int(counters.get(key, 0)) + by
