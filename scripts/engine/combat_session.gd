class_name CombatSession
extends RefCounted
## CombatSession — T7 tick auto-battle core; the single source of Wasteland
## Patrol semantics. NO UI (T10b renders from signals + state).
##
## Spec: docs/balance-notes.md §1 (BINDING — probe_balance sims the same
## arithmetic; tests/test_combat.gd pins the engine to an independent oracle):
##   • Chassis constants §1.1 live HERE (content governs monsters + gear only).
##   • Engage §1.2: first attack lands one full interval after engage; every
##     subsequent interval after that. All integer ms on the T6 sim clock.
##   • Hit roll §1.2: harmonic accuracy clamped to [5%, 95%], computed INTEGER-
##     EXACT as basis points — hit_bp = clamp(acc * 10000 / (acc + eva), 500,
##     9500) vs one d10000 (randi_range(0, 9999) < hit_bp). This is the
##     spec's prescribed int-math form of clamp(acc/(acc+eva), 0.05, 0.95)
##     (T14's int-math rule; no float anywhere in the hot path).
##   • Damage §1.2: on hit, randi_range(attacker_min_hit, attacker_max_hit).
##     A miss draws exactly one number (the hit roll); a hit draws two (roll +
##     damage). Draw order is the determinism contract — do not reorder.
##   • Ordering §1.2: on same-tick collisions the player's attack resolves
##     first; victory/death checked after EACH attack.
##   • Auto-eat §1.2: after any attack, while hp <= max_hp / 2 (integer
##     division) and edible food remains: eat ONE unit of the highest-heal
##     food in the Manifest, instantly, hp = min(max_hp, hp + heal). Eating is
##     not an attack and costs no time (and no RNG draw).
##   • Death §1.2: player HP <= 0 → combat STOPS, phase "dead" (RETURN TO
##     SHELTER for T10b), ZERO item/XP loss (nothing is removed by death;
##     food auto-eaten during the fight was eaten, per spec).
##   • Victory §1.2: monster HP <= 0 → drop_table rolled + xp_reward granted
##     through the shared level pipeline (ActivityEngine.grant_xp → level_up).
##
## STATE MODEL: all mutable state lives in PlayerState's reserved `combat`
## Dictionary (T6 reserved it for exactly this). CombatSession is stateless
## logic over (state, lib) — the same architecture as ActivityEngine — so
## serialization is trivial: PlayerState.to_dict()/from_dict() pass the dict
## through and the fight resumes bit-exact. RNG int64s ship as STRINGS inside
## the dict (T3's JSON 2^53-cliff convention; int() parses them back exactly).
##
## RNG STREAMS (T6-consistent): one stream per combat skill, seeded
## FNV-1a(world_seed + "|" + skill_id) — engaging RESEEDS the stream (mirrors
## T6: restarting a slot replays its skill's stream), so the same world seed +
## gear + monster reproduces the same fight bit-for-bit. Mid-fight saves
## persist rng_state for exact continuation. Victory drops roll on the same
## stream, draw order identical to ActivityEngine._roll_action (pick then qty,
## entry order).
##
## SPEC ADDENDA (§1.4 in balance-notes.md — T7 choices where §1 was silent):
##   • HP reset: player HP resets to full (derived max_hp) and monster HP to
##     its max_hp on every engage.
##   • Offline: combat does NOT progress offline (uncapped offline gains apply
##     to non-combat skills only). Combat times are ABSOLUTE sim-ms and the
##     sim clock resumes at its saved value — a mid-fight save therefore
##     resumes with its pending wind-ups exactly as saved: nothing resolves
##     while away, nothing re-waits the gap (see the offline note at the
##     bottom of this file).
##   • Equipment: equipping CONSUMES one unit from the Manifest; unequipping
##     returns it (no phantom-gear duplication through the Depot).
##   • Concurrency: combat runs alongside all non-combat skill slots
##     (Melvor-style; T6 already ships per-skill concurrency).
##   • Mid-fight equip: stats recompute next tick; a pending attack keeps its
##     scheduled time, and the NEXT interval uses the new speed.

signal combat_ended(result: Dictionary)
## Immediate, discrete. result = {
##   "outcome": "victory" | "death", "monster_id": String,
##   "ms": int (kill/death blow time, absolute sim ms), "duration_ms": int,
##   "eaten": int (foods auto-eaten this fight), "xp": int (victory only),
##   "drops": {item_id: qty} (victory only), "leveled_to": int (0 if no cross),
## }

signal zone_cleared(monster_id: String)
## Immediate, discrete, emitted ONCE ever — the boss's false→true transition
## (the slice's win moment). Persistent via combat.zone_clear.

const PHASE_IDLE := "idle"          ## no fight (initial / after retreat)
const PHASE_FIGHTING := "fighting"  ## auto-battle running
const PHASE_DEAD := "dead"          ## player died: stopped, RETURN TO SHELTER
const PHASE_VICTORY := "victory"    ## monster died: stopped, drops granted
const PHASES := [PHASE_IDLE, PHASE_FIGHTING, PHASE_DEAD, PHASE_VICTORY]

# Player chassis — balance-notes §1.1 (T7 engine constants; content never
# overrides these; tests/test_combat.gd + T13 assert them).
const BASE_MAX_HP := 100
const BASE_ATTACK_SPEED_MS := 3000
const BASE_ACCURACY := 30
const BASE_EVASION := 10
const BASE_MIN_HIT := 1  ## player damage floor (not equipment-bonusable)
const BASE_MAX_HIT := 4

var lib: ContentLibrary
var batcher: UpdateBatcher
var xp_engine: ActivityEngine  ## shared XP/level pipeline (grant_xp)
var combat_skill_id: String = ""  ## the one kind == "combat" skill (cached)


func _init(p_lib: ContentLibrary, p_batcher: UpdateBatcher = null, p_xp_engine: ActivityEngine = null) -> void:
	lib = p_lib
	batcher = p_batcher if p_batcher != null else UpdateBatcher.new()
	xp_engine = p_xp_engine
	for skill_id: String in lib.skills:
		if (lib.skills[skill_id] as SkillDef).is_combat():
			combat_skill_id = skill_id
			break


# ------------------------------------------------------------- state shape --

## Fill the combat namespace's defaults (fresh games / pre-T7 saves: {}).
func ensure_defaults(state: PlayerState) -> void:
	var c: Dictionary = state.combat
	_default(c, "weapon", "")
	_default(c, "armor", "")
	_default(c, "monster_id", "")
	_default(c, "phase", PHASE_IDLE)
	_default(c, "p_hp", 0)
	_default(c, "m_hp", 0)
	_default(c, "engage_ms", 0)
	_default(c, "p_next_ms", 0)
	_default(c, "m_next_ms", 0)
	_default(c, "rng_seed", "0")
	_default(c, "rng_state", "0")
	_default(c, "stream_started", false)
	_default(c, "eaten_total", 0)
	_default(c, "zone_clear", false)


## Re-typed hydration after PlayerState.from_dict (JSON parses numbers as
## floats; live code wants ints — mirror of T6's int() coercion in from_dict).
## str() everywhere: Godot 4.7's String() constructor rejects non-String
## Variants at runtime (str() accepts every type).
func hydrate(state: PlayerState) -> void:
	ensure_defaults(state)
	var c: Dictionary = state.combat
	c["weapon"] = str(c["weapon"])
	c["armor"] = str(c["armor"])
	c["monster_id"] = str(c["monster_id"])
	c["phase"] = str(c["phase"])
	c["rng_seed"] = str(int(str(c["rng_seed"])))
	c["rng_state"] = str(int(str(c["rng_state"])))
	for key in ["p_hp", "m_hp", "engage_ms", "p_next_ms", "m_next_ms", "eaten_total"]:
		c[key] = int(c[key])
	c["stream_started"] = bool(c["stream_started"])
	c["zone_clear"] = bool(c["zone_clear"])


## Content validation on load: a fight referencing content that no longer
## exists stops honestly (phase → idle, gear kept, warning pushed) — never a
## crash, never a guessed monster. Equipment ids that vanished just unequip.
func sanitize(state: PlayerState) -> void:
	ensure_defaults(state)
	var c: Dictionary = state.combat
	for slot in ["weapon", "armor"]:
		var id := str(c[slot])
		if id != "" and lib.equipment_for(id) == null:
			push_warning("[combat] equipped '%s' no longer exists in content — slot cleared" % id)
			c[slot] = ""
	var mid := str(c["monster_id"])
	if mid != "" and lib.monster(mid) == null:
		push_warning("[combat] saved fight referenced unknown monster '%s' — fight dropped" % mid)
	if str(c["phase"]) == PHASE_FIGHTING and (mid == "" or lib.monster(mid) == null):
		c["phase"] = PHASE_IDLE
	if not PHASES.has(str(c["phase"])):
		push_warning("[combat] unknown phase '%s' — reset to idle" % str(c["phase"]))
		c["phase"] = PHASE_IDLE


func _default(c: Dictionary, key: String, value: Variant) -> void:
	if not c.has(key) or c[key] == null:
		c[key] = value


# ------------------------------------------------------------ derived stats --

## Player combat stats from chassis + equipped gear (§1.1 + §1.3): bonuses are
## additive from BOTH slots; a weapon's attack_speed_ms REPLACES the base.
## Memoized on the equipped pair (pure function of (weapon, armor, lib)) —
## read-only result; callers must not mutate the returned Dictionary.
var _stats_cache_key := ""
var _stats_cache: Dictionary = {}


func derived_stats(state: PlayerState) -> Dictionary:
	var key := "%s|%s" % [String(state.combat.get("weapon", "")), String(state.combat.get("armor", ""))]
	if key == _stats_cache_key and not _stats_cache.is_empty():
		return _stats_cache
	var speed := BASE_ATTACK_SPEED_MS
	var accuracy := BASE_ACCURACY
	var evasion := BASE_EVASION
	var max_hp := BASE_MAX_HP
	var max_hit := BASE_MAX_HIT
	for id in key.split("|"):
		if id == "":
			continue
		var eq := lib.equipment_for(id)
		if eq == null:
			continue
		if eq.is_weapon() and eq.attack_speed_ms > 0:
			speed = eq.attack_speed_ms
		accuracy += eq.accuracy_bonus
		evasion += eq.evasion_bonus
		max_hp += eq.max_hp_bonus
		max_hit += eq.max_hit_bonus
	_stats_cache_key = key
	_stats_cache = {
		"max_hp": max_hp, "speed": speed, "accuracy": accuracy,
		"evasion": evasion, "min_hit": BASE_MIN_HIT, "max_hit": max_hit,
	}
	return _stats_cache


## §1.2 harmonic accuracy in integer basis points, clamped to [5%, 95%].
static func hit_chance_bp(attacker_accuracy: int, defender_evasion: int) -> int:
	var denom := attacker_accuracy + defender_evasion
	if denom <= 0:
		return 5000  # equal-stats center; unreachable with content bounds (>0)
	return clampi(attacker_accuracy * 10000 / denom, 500, 9500)


# ------------------------------------------------------------- engage/stop --

## Engage (or switch to) a monster. Gate: Wasteland Combat clearance.
## Returns {"ok": bool, "reason": String} — CLEARANCE wording on gate failure.
func engage(state: PlayerState, monster_id: String, now_ms: int) -> Dictionary:
	var mdef := lib.monster(monster_id)
	if mdef == null:
		return {"ok": false, "reason": "unknown monster '%s'" % monster_id}
	var gate_level := int(state.skills_level.get(combat_skill_id, 1))
	if gate_level < mdef.level_gate:
		return {"ok": false, "reason": "CLEARANCE %d REQUIRED (%s)" % [
			mdef.level_gate, lib.skill(combat_skill_id).name]}
	var c: Dictionary = state.combat
	ensure_defaults(state)
	# §1.4 addendum: fresh HP on every engage; re-engaging abandons any fight.
	var stats := derived_stats(state)
	c["monster_id"] = monster_id
	c["phase"] = PHASE_FIGHTING
	c["p_hp"] = stats["max_hp"]
	c["m_hp"] = mdef.max_hp
	c["engage_ms"] = now_ms
	c["p_next_ms"] = now_ms + int(stats["speed"])  # first swing: one full interval
	c["m_next_ms"] = now_ms + mdef.attack_speed_ms
	c["rng_seed"] = str(_stream_seed(state.world_seed, combat_skill_id))
	c["rng_state"] = "0"
	c["stream_started"] = false
	c["eaten_total"] = 0
	batcher.mark("combat")
	return {"ok": true, "reason": ""}


## Manual retreat: the fight stops (phase idle). HP is not persisted across
## fights (§1.4 addendum) — re-engaging starts both sides at full HP.
func retreat(state: PlayerState) -> void:
	if String(state.combat.get("phase", PHASE_IDLE)) != PHASE_FIGHTING:
		return
	state.combat["phase"] = PHASE_IDLE
	state.combat["p_next_ms"] = 0
	state.combat["m_next_ms"] = 0
	batcher.mark("combat")


# -------------------------------------------------------------- live ticks --

## Advance the fight to absolute sim time `now_ms` (TickManager._sim_tick is
## the ONLY production driver). Resolves every due attack in schedule order,
## player-first on same-time collisions (§1.2), checking victory/death after
## each attack, auto-eating per §1.2 after each surviving attack. A fighting
## tick with nothing due marks nothing dirty (no idle signal churn).
func tick(state: PlayerState, now_ms: int) -> void:
	var c: Dictionary = state.combat
	if String(c.get("phase", PHASE_IDLE)) != PHASE_FIGHTING:
		return
	var mdef: MonsterDef = lib.monster(String(c["monster_id"]))
	if mdef == null:  # content vanished mid-session: stop honestly
		c["phase"] = PHASE_IDLE
		return
	var stats := derived_stats(state)  # mid-fight equip: recompute per tick
	var p_hp_cap := int(stats["max_hp"])
	if int(c["p_hp"]) > p_hp_cap:  # armor swap can lower max_hp: clamp into range
		c["p_hp"] = p_hp_cap
	if int(c["m_hp"]) > mdef.max_hp:  # content HP nerf mid-fight: clamp honest
		c["m_hp"] = mdef.max_hp
	var p_hp := int(c["p_hp"])
	var m_hp := int(c["m_hp"])
	var rng := _session_rng(c)
	var resolved := false
	# Paranoia bound: a corrupted/absurd save cannot spin here forever
	# (intervals are content-bounded >= 100 ms; one tick owes at most a few).
	var guard := 0
	while guard < 100_000:
		var p_next := int(c["p_next_ms"])
		var m_next := int(c["m_next_ms"])
		if p_next > now_ms and m_next > now_ms:
			break
		if p_next <= m_next:  # player resolves first on ties (§1.2)
			if rng.randi_range(0, 9999) < hit_chance_bp(int(stats["accuracy"]), mdef.evasion):
				m_hp -= rng.randi_range(int(stats["min_hit"]), int(stats["max_hit"]))
			c["p_next_ms"] = p_next + int(stats["speed"])
			if m_hp <= 0:
				c["p_hp"] = p_hp
				c["m_hp"] = 0
				_store_rng(c, rng)
				_victory(state, mdef, p_next)
				return
		else:
			if rng.randi_range(0, 9999) < hit_chance_bp(mdef.accuracy, int(stats["evasion"])):
				p_hp -= rng.randi_range(mdef.min_hit, mdef.max_hit)
			c["m_next_ms"] = m_next + mdef.attack_speed_ms
			if p_hp <= 0:
				c["p_hp"] = 0
				c["m_hp"] = m_hp
				_store_rng(c, rng)
				_death(state, mdef, m_next)
				return
		# Auto-eat §1.2 (after any attack; only monster damage moves HP down).
		while p_hp <= p_hp_cap / 2:
			var food_id := _best_food(state)
			if food_id == "":
				break
			var heal: int = (lib.item(food_id) as ItemDef).heal
			state.take_item(food_id, 1)
			p_hp = mini(p_hp_cap, p_hp + heal)
			c["eaten_total"] = int(c["eaten_total"]) + 1
			batcher.mark("inventory")
		c["p_hp"] = p_hp
		c["m_hp"] = m_hp
		resolved = true
		guard += 1
	if resolved:
		_store_rng(c, rng)
		batcher.mark("combat")


## Highest-heal edible item currently in the Manifest ("" when none).
## Deterministic: iterates the CONTENT food list sorted by (heal desc, id
## asc) — never inventory insertion order. Content has no heal ties today;
## the tie-break keeps the choice reproducible if one ever ships.
func _best_food(state: PlayerState) -> String:
	var foods: Array = []
	for item_id: String in lib.items:
		var def: ItemDef = lib.items[item_id]
		if def.is_food() and def.heal > 0 and state.item_count(item_id) > 0:
			foods.append(def)
	foods.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.heal != b.heal:
			return a.heal > b.heal
		return a.id < b.id)
	return String(foods[0].id) if not foods.is_empty() else ""


func _victory(state: PlayerState, mdef: MonsterDef, kill_time_ms: int) -> void:
	var c: Dictionary = state.combat
	var rng := _session_rng(c)
	# Drop roll: identical draw order to ActivityEngine._roll_action (pick
	# then qty, entry order) on the fight's own stream — oracle-replayable.
	var drops := {}
	var table := lib.drop_table(mdef.drop_table)
	if table != null:
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
					drops[entry.item] = int(drops.get(entry.item, 0)) + qty
					break
	_store_rng(c, rng)
	var level_before := int(state.skills_level.get(combat_skill_id, 1))
	xp_engine.grant_xp(state, combat_skill_id, mdef.xp_reward)  # shared pipeline
	c["phase"] = PHASE_VICTORY
	c["p_next_ms"] = 0
	c["m_next_ms"] = 0
	var first_clear := false
	if mdef.is_boss and not bool(c["zone_clear"]):
		c["zone_clear"] = true
		first_clear = true
	batcher.mark("inventory")
	batcher.mark("xp")
	batcher.mark("combat")
	var level_after := int(state.skills_level.get(combat_skill_id, 1))
	combat_ended.emit({
		"outcome": "victory",
		"monster_id": mdef.id,
		"ms": kill_time_ms,
		"duration_ms": kill_time_ms - int(c["engage_ms"]),
		"eaten": int(c["eaten_total"]),
		"xp": mdef.xp_reward,
		"drops": drops,
		"leveled_to": level_after if level_after > level_before else 0,
	})
	if first_clear:
		zone_cleared.emit(mdef.id)


func _death(state: PlayerState, mdef: MonsterDef, death_time_ms: int) -> void:
	var c: Dictionary = state.combat
	c["phase"] = PHASE_DEAD  # RETURN TO SHELTER (T10b renders the plate)
	c["p_next_ms"] = 0
	c["m_next_ms"] = 0
	batcher.mark("combat")
	combat_ended.emit({
		"outcome": "death",
		"monster_id": mdef.id,
		"ms": death_time_ms,
		"duration_ms": death_time_ms - int(c["engage_ms"]),
		"eaten": int(c["eaten_total"]),
		"xp": 0,
		"drops": {},
		"leveled_to": 0,
	})


# ------------------------------------------------------------- equipment --

## Equip one owned equipment item (its EquipmentDef.slot decides the slot).
## Consumes one unit from the Manifest (§1.4 addendum); the previously
## equipped item (if any) returns to the Manifest.
func equip(state: PlayerState, item_id: String) -> Dictionary:
	var eq := lib.equipment_for(item_id)
	if eq == null:
		return {"ok": false, "reason": "'%s' is not equipment" % item_id}
	if state.item_count(item_id) < 1:
		return {"ok": false, "reason": "not in the Manifest"}
	var c: Dictionary = state.combat
	ensure_defaults(state)
	state.take_item(item_id, 1)
	var slot_key := "weapon" if eq.is_weapon() else "armor"
	var previous := String(c[slot_key])
	if previous != "":
		state.add_item(previous, 1)
	c[slot_key] = item_id
	# Mid-fight: stats recompute next tick; pending attacks keep their times.
	if int(c.get("p_hp", 0)) > int(derived_stats(state)["max_hp"]):
		c["p_hp"] = derived_stats(state)["max_hp"]
	batcher.mark("combat")
	batcher.mark("inventory")
	return {"ok": true, "reason": ""}


## Empty a slot ("weapon" | "armor"); the item returns to the Manifest.
func unequip(state: PlayerState, slot_key: String) -> Dictionary:
	if slot_key != "weapon" and slot_key != "armor":
		return {"ok": false, "reason": "unknown slot '%s'" % slot_key}
	var c: Dictionary = state.combat
	ensure_defaults(state)
	var id := String(c[slot_key])
	if id == "":
		return {"ok": false, "reason": "slot already empty"}
	state.add_item(id, 1)
	c[slot_key] = ""
	if int(c.get("p_hp", 0)) > int(derived_stats(state)["max_hp"]):
		c["p_hp"] = derived_stats(state)["max_hp"]
	batcher.mark("combat")
	batcher.mark("inventory")
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------- streams --

func _session_rng(c: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(c["rng_seed"]))
	if bool(c["stream_started"]):
		rng.state = int(String(c["rng_state"]))
	return rng


func _store_rng(c: Dictionary, rng: RandomNumberGenerator) -> void:
	c["rng_state"] = str(rng.state)
	c["stream_started"] = true


## FNV-1a 64-bit over UTF-8 bytes — identical to ActivityEngine._stream_seed
## (same constant/prime; combat's stream id is the combat skill id).
func _stream_seed(world_seed: int, stream_id: String) -> int:
	var h: int = -3750763034362895579  # 0xcbf29ce484222325 - 2^64 (FNV basis)
	var bytes := (str(world_seed) + "|" + stream_id).to_utf8_buffer()
	for b in bytes:
		h = (h ^ b)
		h = h * 0x100000001b3  # FNV 64-bit prime (fits int64)
	return h


# --------------------------------------------------------------- offline --

## Offline disposition (§1.4 addendum 2): combat does NOT progress offline.
## Intentionally does NOTHING to the fight — offline catch-up never calls
## combat.tick, and combat's p_next_ms/m_next_ms are ABSOLUTE sim-ms while
## the sim clock resumes at exactly its saved value (TickManager.adopt_state).
## The saved wind-up remainder therefore fires that many live ms after load:
## zero resolutions during the gap, zero re-waiting of the gap, exact stream
## continuation. A seam rather than an omission (tests pin the behavior; a
## future "combat progresses offline" mode would implement an event-ordered
## replay here, mirroring T6's anchor rewind).
func apply_offline(_state: PlayerState, _elapsed_ms: int) -> void:
	pass
