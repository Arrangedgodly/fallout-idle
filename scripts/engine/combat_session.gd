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
##     9500) vs a d10000 (randi_range(0, 9999) < hit_bp). This is the
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
## HIT COUNTERS (refinement 3, critique P3#5): per-engagement `p_hits` /
## `m_hits` count the swings whose ACCURACY ROLL PASSED, incremented inside
## the shared swing helpers at the exact connect — before the damage roll, so
## a hit that then rolls 0 damage (Litterbug-class min_hit 0) still counts as
## landed. They exist so the T10b diff seam can word a bloodless window by its
## truth (MISS vs NO DAMAGE); they draw no RNG and change no outcome, draw
## order, or save shape beyond the two defaulted ints (old saves hydrate 0).
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
##   • OFFLINE COMBAT PROGRESSES AT FULL RATE (coordinator ruling 2026-09-15,
##     superseding this file's original no-offline-combat disposition): a
##     seeded, event-ordered survivable replay through the SAME swing/eat
##     helpers as the live tick — see apply_offline below for the full
##     contract. A would-be killing blow NEVER lands: the patrol is recalled
##     (phase "recalled", player alive, zero loss) — no-agency death can
##     never occur offline.
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
## LIVE only. Offline outcomes (kills, recalls, level crossings) ride the
## MAIL CALL payload instead — the same policy T6 applies to level_up.

signal zone_cleared(monster_id: String)
## Immediate, discrete, emitted ONCE ever — the boss's false→true transition
## (the slice's win moment). Persistent via combat.zone_clear. A first boss
## clear that happens OFFLINE sets the state but does not emit (the MAIL CALL
## payload's combat section carries it for T10 to present).

const PHASE_IDLE := "idle"          ## no fight (initial / after retreat)
const PHASE_FIGHTING := "fighting"  ## auto-battle running
const PHASE_DEAD := "dead"          ## player died: stopped, RETURN TO SHELTER
const PHASE_VICTORY := "victory"    ## monster died: stopped, drops granted
const PHASE_RECALLED := "recalled"  ## offline survivability stop: the patrol was recalled mid-blow — player ALIVE (T10b renders the RETURN TO SHELTER plate family), zero loss, re-engage anytime
const PHASES := [PHASE_IDLE, PHASE_FIGHTING, PHASE_DEAD, PHASE_VICTORY, PHASE_RECALLED]

# Player chassis — balance-notes §1.1 (T7 engine constants; content never
# overrides these; tests/test_combat.gd + T13 assert them).
const BASE_MAX_HP := 100
const BASE_ATTACK_SPEED_MS := 3000
const BASE_ACCURACY := 30
const BASE_EVASION := 10
const BASE_MIN_HIT := 1  ## player damage floor (not equipment-bonusable)
const BASE_MAX_HIT := 4

## Replay budget: ~145 days of continuous combat at content intervals. Beyond
## it the replay truncates honestly at that instant (fight resumes live,
## payload flags `truncated` — surfaced by MailCallModal as a stamped line;
## pinned by tests/test_resilience.gd): an O(events) catch-all for absurd
## gaps.
const MAX_OFFLINE_EVENTS := 5_000_000

## T14 test seam: the replay budget as an overridable var (production default
## = the constant; tests shrink it to reach the truncation path without
## replaying five million events).
var offline_event_budget: int = MAX_OFFLINE_EVENTS

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
	_default(c, "p_hits", 0)
	_default(c, "m_hits", 0)
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
	for key in ["p_hp", "m_hp", "engage_ms", "p_next_ms", "m_next_ms", "eaten_total", "p_hits", "m_hits"]:
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
	var key := "%s|%s" % [str(state.combat.get("weapon", "")), str(state.combat.get("armor", ""))]
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
	# §1.4 addendum 1: fresh HP on every engage; re-engaging abandons any fight.
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
	c["p_hits"] = 0
	c["m_hits"] = 0
	batcher.mark("combat")
	return {"ok": true, "reason": ""}


## Manual retreat: the fight stops (phase idle). HP is not persisted across
## fights (§1.4 addendum 1) — re-engaging starts both sides at full HP.
func retreat(state: PlayerState) -> void:
	if str(state.combat.get("phase", PHASE_IDLE)) != PHASE_FIGHTING:
		return
	state.combat["phase"] = PHASE_IDLE
	state.combat["p_next_ms"] = 0
	state.combat["m_next_ms"] = 0
	batcher.mark("combat")


# --------------------------------------------------- shared §1.2 primitives --
# The live tick and the offline replay BOTH resolve swings and auto-eat
# through these helpers, so roll order and outcomes are live-identical by
# construction (pinned by the replay-vs-live-twin test).

## One player swing → damage dealt (0 on miss). Draw order: hit roll, then a
## damage roll ONLY on hit (the determinism contract — the counter write in
## between draws nothing). R3: the hit roll's verdict is recorded in c.p_hits
## BEFORE the damage roll, so a landed 0-damage hit stays distinguishable from
## a miss for the T10b diff seam.
func _player_swing(rng: RandomNumberGenerator, stats: Dictionary, mdef: MonsterDef, c: Dictionary) -> int:
	if rng.randi_range(0, 9999) < hit_chance_bp(int(stats["accuracy"]), mdef.evasion):
		c["p_hits"] = int(c["p_hits"]) + 1
		return rng.randi_range(int(stats["min_hit"]), int(stats["max_hit"]))
	return 0


## One monster swing → damage dealt (0 on miss). Same contract as the player
## swing; c.m_hits counts landed swings (a 0-damage roll still landed).
func _monster_swing(rng: RandomNumberGenerator, stats: Dictionary, mdef: MonsterDef, c: Dictionary) -> int:
	if rng.randi_range(0, 9999) < hit_chance_bp(mdef.accuracy, int(stats["evasion"])):
		c["m_hits"] = int(c["m_hits"]) + 1
		return rng.randi_range(mdef.min_hit, mdef.max_hit)
	return 0


## §1.2 auto-eat: while at/below half HP (integer division) and edible food
## remains, eat one unit of the highest-heal food. Returns the new HP.
func _auto_eat(state: PlayerState, c: Dictionary, p_hp: int, p_hp_cap: int) -> int:
	while p_hp <= p_hp_cap / 2:
		var food_id := _best_food(state)
		if food_id == "":
			break
		var heal: int = (lib.item(food_id) as ItemDef).heal
		state.take_item(food_id, 1)
		p_hp = mini(p_hp_cap, p_hp + heal)
		c["eaten_total"] = int(c["eaten_total"]) + 1
		batcher.mark("inventory")
	return p_hp


# -------------------------------------------------------------- live ticks --

## Advance the fight to absolute sim time `now_ms` (TickManager._sim_tick is
## the ONLY production driver). Resolves every due attack in schedule order,
## player-first on same-time collisions (§1.2), checking victory/death after
## each attack, auto-eating per §1.2 after each surviving attack. A fighting
## tick with nothing due marks nothing dirty (no idle signal churn).
func tick(state: PlayerState, now_ms: int) -> void:
	var c: Dictionary = state.combat
	if str(c.get("phase", PHASE_IDLE)) != PHASE_FIGHTING:
		return
	var mdef: MonsterDef = lib.monster(str(c["monster_id"]))
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
			m_hp -= _player_swing(rng, stats, mdef, c)
			c["p_next_ms"] = p_next + int(stats["speed"])
			if m_hp <= 0:
				c["p_hp"] = p_hp
				c["m_hp"] = 0
				_store_rng(c, rng)
				_victory(state, mdef, p_next)
				return
		else:
			p_hp -= _monster_swing(rng, stats, mdef, c)
			c["m_next_ms"] = m_next + mdef.attack_speed_ms
			if p_hp <= 0:
				c["p_hp"] = 0
				c["m_hp"] = m_hp
				_store_rng(c, rng)
				_death(state, mdef, m_next)
				return
		p_hp = _auto_eat(state, c, p_hp, p_hp_cap)
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
	return str(foods[0].id) if not foods.is_empty() else ""


## Victory drops, drawn in ActivityEngine's exact order (pick, then qty,
## entry order) on the given stream — shared by the live and offline paths.
func _roll_drops(state: PlayerState, mdef: MonsterDef, rng: RandomNumberGenerator) -> Dictionary:
	var drops := {}
	var table := lib.drop_table(mdef.drop_table)
	if table == null:
		return drops
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
	return drops


func _victory(state: PlayerState, mdef: MonsterDef, kill_time_ms: int) -> void:
	var c: Dictionary = state.combat
	var rng := _session_rng(c)
	var drops := _roll_drops(state, mdef, rng)
	_store_rng(c, rng)
	var level_before := int(state.skills_level.get(combat_skill_id, 1))
	xp_engine.grant_xp(state, combat_skill_id, mdef.xp_reward)  # shared pipeline (immediate level_up)
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
	var previous := str(c[slot_key])
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
	var id := str(c[slot_key])
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
	rng.seed = int(str(c["rng_seed"]))
	if bool(c["stream_started"]):
		rng.state = int(str(c["rng_state"]))
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

## OFFLINE COMBAT (coordinator ruling 2026-09-15 — balance-notes §1.4
## addendum 2, superseding the original no-offline-combat disposition):
## combat PROGRESSES at full rate, bounded by survivability. A seeded,
## event-ordered replay advances the saved fight exactly as the live tick
## would (same swing/eat helpers, same roll order, same stream) until:
##   (a) the monster dies → the normal victory chain: drops rolled, XP
##       granted (level crossings ride the payload — no immediate signals,
##       T6's offline policy), first boss clear sets zone_clear; while a
##       monster is selected the patrol RE-ENGAGES it at the kill instant and
##       keeps farming (each engage reseeds the combat stream — the same
##       deterministic farm loop live play produces);
##   (b) a monster blow WOULD reduce player HP to <= 0 → the blow NEVER
##       LANDS: the patrol is recalled at that instant (phase "recalled",
##       player alive at pre-blow HP, zero loss, pendings cleared) — a
##       no-agency death can never occur offline. Food exhaustion is the
##       usual path here: auto-eat extends survival exactly as live until
##       the stack runs dry, then the next killing-blow-in-waiting recalls.
## The replay runs ONLY when the save left a fight in progress (idle /
## victory / dead / recalled saves never auto-start fights), is bounded by
## the gap's elapsed ms and the food stack (plus the event budget as an
## O(events) catch-all), and is bit-deterministic. A still-fighting resume
## mirrors T6's anchor rewind: pending attack times shift back by exactly
## the gap, preserving the wind-up phase for live continuation.
## Ordering note: activities replay FIRST (T6), so combat fights against the
## post-catch-up Manifest — combat can eat food a Cooking slot banked during
## the same gap (the honest live-concurrency interplay).
## Mutates `payload` (the MAIL CALL dictionary): merged skills_xp/items
## deltas, levels from/to, an actions entry (kills), a "combat" section
## ({kills, monster_id, outcome, notice: "PATROL RECALLED" on recall, ...})
## and — on recall — a PATROL RECALLED stopped-line for T10 to render.
func apply_offline(state: PlayerState, now_ms: int, elapsed_ms: int, payload: Dictionary) -> void:
	if elapsed_ms <= 0:
		return
	var c: Dictionary = state.combat
	if str(c.get("phase", PHASE_IDLE)) != PHASE_FIGHTING:
		return  # no fight in progress at the save — offline combat is a no-op
	var xp0 := int(state.skills_xp.get(combat_skill_id, 0))
	var lvl0 := int(state.skills_level.get(combat_skill_id, 1))
	var inv0 := state.inventory.duplicate()
	var zone_clear_before := bool(c["zone_clear"])
	var horizon := now_ms + elapsed_ms
	var kills := 0
	var recalled := false
	var recalled_at := 0
	var events_used := 0
	while not recalled and events_used < offline_event_budget:
		var mdef: MonsterDef = lib.monster(str(c["monster_id"]))
		if mdef == null:
			c["phase"] = PHASE_IDLE
			break
		var stats := derived_stats(state)
		var rng := _session_rng(c)
		var r := _replay_fight(state, c, mdef, rng, stats, horizon, offline_event_budget - events_used)
		events_used += int(r["events"])
		if str(r["outcome"]) == "victory":
			_roll_drops(state, mdef, rng)
			_store_rng(c, rng)
			xp_engine.grant_xp(state, combat_skill_id, mdef.xp_reward, false)  # crossings ride the payload
			kills += 1
			if mdef.is_boss and not bool(c["zone_clear"]):
				c["zone_clear"] = true
			_reengage_at(state, c, int(r["blow_ms"]))  # keep farming (ruling a)
			continue
		_store_rng(c, rng)
		if str(r["outcome"]) == "recall":
			recalled = true
			recalled_at = int(r["blow_ms"])
			c["phase"] = PHASE_RECALLED  # alive, zero loss (ruling b)
			c["p_hp"] = int(r["p_hp"])  # pre-blow HP: the killing blow never landed
			c["m_hp"] = int(r["m_hp"])
			c["p_next_ms"] = 0
			c["m_next_ms"] = 0
		break  # horizon (or budget) reached mid-fight
	# Still fighting: mirror T6's anchor rewind so live ticking resumes with
	# the wind-up phase the gap ended on (pending times are gap-relative now).
	if str(c["phase"]) == PHASE_FIGHTING:
		c["p_next_ms"] = int(c["p_next_ms"]) - elapsed_ms
		c["m_next_ms"] = int(c["m_next_ms"]) - elapsed_ms
		c["engage_ms"] = int(c["engage_ms"]) - elapsed_ms
	_merge_offline_payload(state, payload, xp0, inv0, lvl0, kills, recalled,
		recalled_at, zone_clear_before, events_used >= offline_event_budget)


## One fight of the offline replay, up to `horizon` (absolute virtual ms) or
## the event budget. Mutates c (pendings/HP/eaten) and the Manifest (eats).
## Returns {"outcome": "horizon"|"victory"|"recall", "blow_ms": int,
## "p_hp": int, "m_hp": int, "events": int used}. On "recall" the killing
## blow has NOT been applied and the monster's pending time is NOT advanced —
## the caller stops the fight at that instant.
func _replay_fight(state: PlayerState, c: Dictionary, mdef: MonsterDef, rng: RandomNumberGenerator,
		stats: Dictionary, horizon: int, event_budget: int) -> Dictionary:
	var p_hp_cap := int(stats["max_hp"])
	var p_hp := mini(int(c["p_hp"]), p_hp_cap)
	var m_hp := mini(int(c["m_hp"]), mdef.max_hp)
	var used := 0
	while used < event_budget:
		var p_next := int(c["p_next_ms"])
		var m_next := int(c["m_next_ms"])
		if p_next > horizon and m_next > horizon:
			break  # gap exhausted mid-fight
		used += 1
		if p_next <= m_next:  # player resolves first on ties (§1.2)
			m_hp -= _player_swing(rng, stats, mdef, c)
			c["p_next_ms"] = p_next + int(stats["speed"])
			if m_hp <= 0:
				c["p_hp"] = p_hp
				c["m_hp"] = 0
				return {"outcome": "victory", "blow_ms": p_next, "p_hp": p_hp, "m_hp": 0, "events": used}
		else:
			var dmg := _monster_swing(rng, stats, mdef, c)
			if p_hp - dmg <= 0:
				# The blow never lands — no-agency death can not occur (ruling b).
				return {"outcome": "recall", "blow_ms": m_next, "p_hp": p_hp, "m_hp": m_hp, "events": used}
			p_hp -= dmg
			c["m_next_ms"] = m_next + mdef.attack_speed_ms
		p_hp = _auto_eat(state, c, p_hp, p_hp_cap)
		c["p_hp"] = p_hp
		c["m_hp"] = m_hp
	return {"outcome": "horizon", "blow_ms": 0, "p_hp": p_hp, "m_hp": m_hp, "events": used}


## Chain re-engage at the kill instant (ruling a: keep farming while a
## monster is selected). Identical reset semantics to engage(): both sides
## full HP, stream reseeded (the deterministic live farm loop), fresh eater.
func _reengage_at(state: PlayerState, c: Dictionary, at_ms: int) -> void:
	var mdef: MonsterDef = lib.monster(str(c["monster_id"]))
	var stats := derived_stats(state)
	c["phase"] = PHASE_FIGHTING
	c["p_hp"] = int(stats["max_hp"])
	c["m_hp"] = mdef.max_hp
	c["engage_ms"] = at_ms
	c["p_next_ms"] = at_ms + int(stats["speed"])
	c["m_next_ms"] = at_ms + mdef.attack_speed_ms
	c["rng_seed"] = str(_stream_seed(state.world_seed, combat_skill_id))
	c["rng_state"] = "0"
	c["stream_started"] = false
	c["eaten_total"] = 0
	c["p_hits"] = 0
	c["m_hits"] = 0


## Fold the replay's deltas into the MAIL CALL payload (additive merges over
## whatever the activity catch-up already banked — disjoint skills/items, so
## plain addition is exact) and describe the combat outcome for T10.
func _merge_offline_payload(state: PlayerState, payload: Dictionary, xp0: int, inv0: Dictionary,
		lvl0: int, kills: int, recalled: bool, recalled_at: int, zone_clear_before: bool,
		truncated: bool) -> void:
	var c: Dictionary = state.combat
	var gained_xp := int(state.skills_xp.get(combat_skill_id, 0)) - xp0
	if gained_xp != 0:
		payload["skills_xp"][combat_skill_id] = int(payload["skills_xp"].get(combat_skill_id, 0)) + gained_xp
	var level := int(state.skills_level.get(combat_skill_id, 1))
	if level > lvl0:
		payload["levels"][combat_skill_id] = {"from": lvl0, "to": level}
	if kills > 0:
		payload["actions"][combat_skill_id] = kills
	for item_id in state.inventory:
		var delta := int(state.inventory[item_id]) - int(inv0.get(item_id, 0))
		if delta != 0:
			payload["items"][item_id] = int(payload["items"].get(item_id, 0)) + delta
	var section := {
		"kills": kills,
		"monster_id": str(c["monster_id"]),
		"outcome": "recalled" if recalled else ("farming" if kills > 0 else "resumed"),
	}
	if recalled:
		section["notice"] = "PATROL RECALLED"
		section["recalled_at_ms"] = recalled_at
		payload["stopped"].append({
			"skill_id": combat_skill_id,
			"content_id": str(c["monster_id"]),
			"reason": "patrol_recalled",
		})
	if bool(c["zone_clear"]) and not zone_clear_before:
		section["zone_cleared"] = true  # offline first clear: state set, signal withheld (payload carries it)
	if truncated:
		section["truncated"] = true
	payload["combat"] = section
	batcher.mark("xp")
	batcher.mark("inventory")
	batcher.mark("combat")
