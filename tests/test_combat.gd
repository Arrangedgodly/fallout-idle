extends GutTest
## tests/test_combat.gd — T7 combat system validation (Thor lane).
##
## Pins the T7 acceptance matrix headless, against LIVE content (res://data
## through the production ContentLoader — same convention as test_engine.gd):
##   (a) chassis constants + derived loadouts == balance-notes §1.1/§1.3;
##   (b) engage clearance gates, §1.4 HP-reset addendum, fresh RNG stream
##       per engage, scheduled first swings one full interval out;
##   (c) ENGINE == INDEPENDENT ORACLE: the oracle below is a fresh port of
##       the §1 combat spec (structure from tests/probe_balance.gd's sim,
##       hit roll in the spec's integer basis-point form, §1.4 addendum 6) —
##       every fight must agree on outcome, kill/death-blow ms, foods eaten,
##       final HPs, remaining food AND (on victory) the exact drop stacks a
##       seeded replay of the stream predicts;
##   (d) 200-seed boss sweeps == balance-notes §2 expectations (max gear +
##       food wins, mid gear no-food never wins, naked cannot out-eat);
##   (e) death halts with ZERO loss (empty-Hands fight: xp/inventory
##       byte-equal before/after; halting proven by a post-death pump);
##   (f) auto-eat: <= half HP (integer division), best-food-first, repeat
##       while at/below threshold, heal clamped at max_hp, no-eat when bare;
##   (g) victory XP rides the shared grant_xp pipeline (immediate level_up),
##       boss victory sets persistent zone_clear + fires zone_cleared ONCE;
##   (h) save round-trip: PlayerState -> JSON string -> from_dict ->
##       adopt_state -> apply_offline_elapsed(0) resumes a split fight to the
##       SAME outcome/duration/eaten/drops as an uninterrupted twin (exact
##       stream continuation);
##   (i) offline combat (coordinator ruling — §1.4 addendum 2, superseding
##       the no-offline-combat disposition): full-rate survivable replay —
##       survivable prefix == live twin EXACTLY (HP/pendings/rng stream);
##       farming chains (re-engage at kill instants) == a live auto-re-engage
##       twin on kills/XP/Manifest/stream; a would-be killing blow NEVER
##       lands (recall: alive, zero loss, PATROL RECALLED payload line, no
##       signals — no-agency death impossible); food exhaustion recalls;
##       boss farming offline is bounded by the deterministic kill rate;
##       only mid-fight saves replay (idle/victory/dead never auto-start);
##   (j) combat advances ONLY through the tick-manager funnel
##       (advance_wall_ms); same-seed twins are bit-identical;
##   (k) signal budget: bulk <= 4 Hz over a 60 s fighting window;
##       combat_ended/level_up are IMMEDIATE (same advance call as the
##       killing tick), exactly once per fight;
##   (l) equip semantics: consumes from the Manifest, swap returns the old
##       piece, refusals (unknown / non-equipment / unowned), mid-fight equip
##       keeps the pending swing and applies the new speed to the next gap;
##   (m) load hygiene: hydrate re-types JSON floats, sanitize drops fights
##       referencing removed content (never a crash).
##
## Determinism: fresh TickManager instances booted with explicit seeds via
## _boot(), never added to the tree (advance_wall_ms is the only clock input).
## The combat-namespace HP writes in the auto-eat tests are a documented
## test seam (the engine reads state.combat.p_hp at the next tick).

const ObjectiveFreeLib := preload("res://tests/objective_free_lib.gd")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED_A := 424242
const ORACLE_SEEDS := 8
const SWEEP_SEEDS := 200
const SWEEP_BASE_SEED := 1_000
const L8_XP := 1_702    # standard_99 total to reach combat level 8 (Fizzard gate 7)
const L10_XP := 3_226   # Dispenser gate 10
const L14_XP := 8_340   # The Superintendent gate 14
const TICK_MS := 100

var _lib_cache: ContentLibrary = null


func _lib() -> ContentLibrary:
	if _lib_cache == null:
		# T25: exact combat-semantics pins (death zero-loss, wallet untouched)
		# boot on the objective-free fixture — kill-run merit pay from the
		# shipped dossier set no longer perturbs them (T27-safe).
		_lib_cache = ObjectiveFreeLib.load("combat")
	return _lib_cache


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)  # bare Nodes leak without this (GUT orphan discipline)
	tm._boot(_lib(), seed)
	return tm


## Feed exactly `total_ms` through the public wall funnel (chunk <= 2500 ms:
## the 25-tick/frame catch-up budget — bigger chunks clamp, by design).
func _pump(tm: Variant, total_ms: int, chunk_ms: int = 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


# ---------------------------------------------------------------------------
# Independent §1 oracle (structure ported from probe_balance.gd's _simulate;
# int basis-point hit roll per the §1.4 addendum-6 representation)
# ---------------------------------------------------------------------------

func _oracle_bp(attacker_accuracy: int, defender_evasion: int) -> int:
	var denom := attacker_accuracy + defender_evasion
	if denom <= 0:
		return 5000
	return clampi(attacker_accuracy * 10000 / denom, 500, 9500)


## §1.1 chassis values AS WRITTEN IN balance-notes (oracle-local copies — the
## engine's CombatSession.BASE_* must independently agree, which test (a)
## asserts against these same literals).
const ORACLE_BASE_MAX_HP := 100
const ORACLE_BASE_SPEED_MS := 3000
const ORACLE_BASE_ACCURACY := 30
const ORACLE_BASE_EVASION := 10
const ORACLE_BASE_MIN_HIT := 1
const ORACLE_BASE_MAX_HIT := 4


func _oracle_stats(weapon_id: String, armor_id: String) -> Dictionary:
	var speed := ORACLE_BASE_SPEED_MS
	var accuracy := ORACLE_BASE_ACCURACY
	var evasion := ORACLE_BASE_EVASION
	var max_hp := ORACLE_BASE_MAX_HP
	var max_hit := ORACLE_BASE_MAX_HIT
	for id in [weapon_id, armor_id]:
		if id == "":
			continue
		var eq := _lib().equipment_for(id)
		if eq.attack_speed_ms > 0 and eq.is_weapon():
			speed = eq.attack_speed_ms
		accuracy += eq.accuracy_bonus
		evasion += eq.evasion_bonus
		max_hp += eq.max_hp_bonus
		max_hit += eq.max_hit_bonus
	return {"max_hp": max_hp, "speed": speed, "accuracy": accuracy,
		"evasion": evasion, "min_hit": ORACLE_BASE_MIN_HIT, "max_hit": max_hit}


## FNV-1a 64 over "world_seed|wasteland_combat" — independent copy of the
## documented stream formula (must equal the engine's engage-time reseed).
func _oracle_stream_seed(world_seed: int) -> int:
	var h: int = -3750763034362895579
	var bytes := (str(world_seed) + "|wasteland_combat").to_utf8_buffer()
	for b in bytes:
		h = h ^ b
		h = h * 0x100000001b3
	return h


## One seeded §1 fight. `food` is CONSUMED (pass a duplicate). Returns
## {win, ms, eaten, p_hp, m_hp, food, rng_state, timeout} — plus R3 hit
## counters (p_hits/m_hits: swings whose accuracy roll passed; a 0-damage
## roll still counts), mirroring the engine's connect-truth state.
func _oracle_fight(stats: Dictionary, monster: MonsterDef, food: Dictionary, stream_seed: int, cap_ms: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed
	var max_hp: int = stats["max_hp"]
	var p_hp := max_hp
	var m_hp := monster.max_hp
	var p_next: int = stats["speed"]  # first swing after one full interval (§1.2)
	var m_next: int = monster.attack_speed_ms
	var eaten := 0
	var p_hits := 0
	var m_hits := 0
	while p_next <= cap_ms and m_next <= cap_ms:
		if p_next <= m_next:  # player resolves first on ties (§1.2)
			if rng.randi_range(0, 9999) < _oracle_bp(int(stats["accuracy"]), monster.evasion):
				p_hits += 1
				m_hp -= rng.randi_range(int(stats["min_hit"]), int(stats["max_hit"]))
			var p_blow := p_next
			p_next += int(stats["speed"])
			if m_hp <= 0:
				return {"win": true, "ms": p_blow, "eaten": eaten, "p_hp": p_hp,
					"m_hp": 0, "food": food, "rng_state": rng.state, "timeout": false,
					"p_hits": p_hits, "m_hits": m_hits}
		else:
			if rng.randi_range(0, 9999) < _oracle_bp(monster.accuracy, int(stats["evasion"])):
				m_hits += 1
				p_hp -= rng.randi_range(monster.min_hit, monster.max_hit)
			var m_blow := m_next
			m_next += monster.attack_speed_ms
			if p_hp <= 0:
				return {"win": false, "ms": m_blow, "eaten": eaten, "p_hp": 0,
					"m_hp": m_hp, "food": food, "rng_state": rng.state, "timeout": false,
					"p_hits": p_hits, "m_hits": m_hits}
		# Auto-eat §1.2: <= half HP (integer division), highest-heal first, repeat.
		while p_hp <= max_hp / 2 and not food.is_empty():
			var best := ""
			var best_heal := -1
			for item_id in food:
				var def: ItemDef = _lib().item(String(item_id))
				if def != null and def.heal > best_heal:
					best_heal = def.heal
					best = String(item_id)
			if best == "":
				break
			food[best] = int(food[best]) - 1
			if int(food[best]) <= 0:
				food.erase(best)
			p_hp = mini(max_hp, p_hp + best_heal)
			eaten += 1
	return {"win": false, "ms": cap_ms, "eaten": eaten, "p_hp": p_hp,
		"m_hp": m_hp, "food": food, "rng_state": rng.state, "timeout": true,
		"p_hits": p_hits, "m_hits": m_hits}


## Victory drops a stream-state replay predicts (draw order = the engine's:
## pick, then qty, entry order — identical to ActivityEngine._roll_action).
func _oracle_drops(table_id: String, rng_state: int) -> Dictionary:
	var table := _lib().drop_table(table_id)
	var drops := {}
	if table == null:
		return drops
	var rng := RandomNumberGenerator.new()
	rng.state = rng_state
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
				drops[entry.item] = int(drops.get(entry.item, 0)) + qty
				break
	return drops


## Run one isolated engine fight (engage at sim 0, gear equipped before
## engage — the probe's convention). Returns the outcome + payload; the
## caller keeps `tm` for further asserts.
func _run_fight(world_seed: int, weapon_id: String, armor_id: String, monster_id: String,
		food: Dictionary, gate_xp: int, cap_ms: int) -> Dictionary:
	var tm: Variant = _make_tm(world_seed)
	var st: PlayerState = tm.state
	if gate_xp > 0:
		tm.engine.grant_xp(st, "wasteland_combat", gate_xp)
	for item_id in food:
		st.add_item(String(item_id), int(food[item_id]))
	for eq_id in [weapon_id, armor_id]:
		if eq_id != "":
			st.add_item(eq_id, 1)
			var eq_result: Dictionary = tm.equip_item(eq_id)
			assert_true(eq_result["ok"], "equip %s succeeds: %s" % [eq_id, str(eq_result)])
	var ends: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	var engaged: Dictionary = tm.engage_monster(monster_id)
	assert_true(engaged["ok"], "engage %s succeeds: %s" % [monster_id, str(engaged)])
	_pump(tm, cap_ms, 2_500)
	var outcome := String(st.combat["phase"])
	var food_left := {}
	for item_id in food:
		var left := st.item_count(String(item_id))
		if left > 0:
			food_left[String(item_id)] = left
	return {
		"outcome": "timeout" if outcome == "fighting" else outcome,
		"result": ends[0] if not ends.is_empty() else {},
		"food_left": food_left,
		"ends_count": ends.size(),
		"tm": tm,
	}


# ---------------------------------------------------------------------------
# (a) chassis + loadouts
# ---------------------------------------------------------------------------

func test_chassis_constants_and_loadouts() -> void:
	assert_eq(CombatSession.BASE_MAX_HP, 100, "§1.1 BASE_MAX_HP")
	assert_eq(CombatSession.BASE_ATTACK_SPEED_MS, 3000, "§1.1 BASE_ATTACK_SPEED_MS")
	assert_eq(CombatSession.BASE_ACCURACY, 30, "§1.1 BASE_ACCURACY")
	assert_eq(CombatSession.BASE_EVASION, 10, "§1.1 BASE_EVASION")
	assert_eq(CombatSession.BASE_MIN_HIT, 1, "§1.1 BASE_MIN_HIT")
	assert_eq(CombatSession.BASE_MAX_HIT, 4, "§1.1 BASE_MAX_HIT")
	# Harmonic clamp edges: equal stats 50%, one-sided saturates at 5%/95%.
	assert_eq(CombatSession.hit_chance_bp(50, 50), 5000, "equal stats = 50%")
	assert_eq(CombatSession.hit_chance_bp(1, 1_000_000), 500, "one-sided floor = 5%")
	assert_eq(CombatSession.hit_chance_bp(1_000_000, 1), 9500, "one-sided ceiling = 95%")
	assert_eq(CombatSession.hit_chance_bp(30, 4), 30 * 10000 / 34, "int-exact bp of acc/(acc+eva)")

	var tm: Variant = _make_tm(SEED_A)
	var bare: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(bare, {"max_hp": 100, "speed": 3000, "accuracy": 30, "evasion": 10,
		"min_hit": 1, "max_hit": 4}, "bare chassis == §1.3 Bare row")

	tm.state.add_item("scrap_shiv", 1)
	tm.state.add_item("hubcap_vest", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "equip Point of Order")
	assert_true(tm.equip_item("hubcap_vest")["ok"], "equip Pedestrian Plating")
	var mid: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(mid, {"max_hp": 120, "speed": 2600, "accuracy": 40, "evasion": 22,
		"min_hit": 1, "max_hit": 8}, "mid loadout == §1.3 Mid row")

	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	assert_true(tm.equip_item("majority_whip")["ok"], "swap in Majority Whip")
	assert_true(tm.equip_item("carpool_carapace")["ok"], "swap in Carpool Carapace")
	var max: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(max, {"max_hp": 150, "speed": 2000, "accuracy": 75, "evasion": 40,
		"min_hit": 1, "max_hit": 18}, "max loadout == §1.3 Max row")


# ---------------------------------------------------------------------------
# (b) engage gates + HP reset + stream reset
# ---------------------------------------------------------------------------

func test_engage_gates_and_hp_reset() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var st: PlayerState = tm.state

	var blocked: Dictionary = tm.engage_monster("fizzard")
	assert_false(blocked["ok"], "Fizzard refuses at Wasteland Combat 1")
	assert_true(String(blocked["reason"]).contains("CLEARANCE 7"),
		"gate error carries CLEARANCE wording: %s" % str(blocked["reason"]))
	assert_eq(String(st.combat["phase"]), "idle", "refused engage leaves combat idle")

	var ok: Dictionary = tm.engage_monster("junkyard_roach")
	assert_true(ok["ok"], "Litterbug (gate 1) engages at level 1")
	var c: Dictionary = st.combat
	assert_eq(String(c["phase"]), "fighting", "phase fighting")
	assert_eq(String(c["monster_id"]), "junkyard_roach", "target recorded")
	assert_eq(int(c["p_hp"]), 100, "player HP reset to full on engage (§1.4 addendum 1)")
	assert_eq(int(c["m_hp"]), 18, "monster HP at max on selection")
	assert_eq(int(c["engage_ms"]), 0, "engaged at the current sim tick")
	assert_eq(int(c["p_next_ms"]), 3000, "first player swing one full interval out (§1.2)")
	assert_eq(int(c["m_next_ms"]), 2800, "first monster swing one full interval out")
	assert_eq(String(c["rng_seed"]), str(_oracle_stream_seed(SEED_A)),
		"stream reseeded to FNV(world_seed|wasteland_combat)")
	assert_false(bool(c["stream_started"]), "stream positioned fresh")
	assert_eq(int(c["eaten_total"]), 0, "no food eaten yet")

	_pump(tm, 6_000)
	assert_eq(String(c["phase"]), "fighting", "still fighting the Litterbug")
	assert_true(bool(c["stream_started"]), "both sides swung -> stream drew rolls")

	# §1.4 addendum 1: every engage is a full reset for BOTH sides.
	var rengage: Dictionary = tm.engage_monster("junkyard_roach")
	assert_true(rengage["ok"], "re-engage works mid-fight (abandons the old fight)")
	assert_eq(int(c["p_hp"]), 100, "player HP reset on re-engage")
	assert_eq(int(c["m_hp"]), 18, "monster HP reset on re-engage")
	assert_eq(int(c["eaten_total"]), 0, "eaten counter reset")
	assert_false(bool(c["stream_started"]), "stream reset (same fight replays identically)")

	tm.stop_combat()
	assert_eq(String(c["phase"]), "idle", "manual retreat stops the fight")
	assert_eq(int(c["p_next_ms"]), 0, "no pending swings while idle")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engaging again after retreat")


# ---------------------------------------------------------------------------
# (c) engine == oracle, per seed, across the ladder + boss configs
# ---------------------------------------------------------------------------

func test_engine_matches_oracle_across_ladder() -> void:
	# [weapon, armor, monster, food, gate_xp, cap_ms]
	var configs := [
		["", "", "junkyard_roach", {}, 0, 400_000],
		["", "", "fizzard", {}, L8_XP, 600_000],
		["scrap_shiv", "hubcap_vest", "feral_snack_dispenser", {"compliant_casserole": 4}, L10_XP, 600_000],
		["majority_whip", "carpool_carapace", "sewer_landlord", {"radstag_stew": 6}, L14_XP, 600_000],
		["majority_whip", "carpool_carapace", "sewer_landlord", {}, L14_XP, 600_000],
		["scrap_shiv", "hubcap_vest", "sewer_landlord", {}, L14_XP, 400_000],
	]
	for cfg in configs:
		var weapon_id: String = cfg[0]
		var armor_id: String = cfg[1]
		var monster: MonsterDef = _lib().monster(cfg[2])
		var food: Dictionary = (cfg[3] as Dictionary).duplicate()
		var cap: int = cfg[5]
		var label := "%s+%s vs %s food=%s" % [weapon_id if weapon_id != "" else "bare",
			armor_id if armor_id != "" else "bare", monster.id, str(cfg[3])]
		for i in ORACLE_SEEDS:
			var seed := SWEEP_BASE_SEED + i
			var eng := _run_fight(seed, weapon_id, armor_id, monster.id, food.duplicate(), cfg[4], cap)
			var oracle := _oracle_fight(_oracle_stats(weapon_id, armor_id), monster,
				food.duplicate(), _oracle_stream_seed(seed), cap)
			var outcome: String = eng["outcome"]
			assert_ne(outcome, "timeout", "%s seed %d: engine fight decided within cap" % [label, seed])
			assert_false(bool(oracle["timeout"]), "%s seed %d: oracle fight decided within cap" % [label, seed])
			assert_eq(outcome == "victory", bool(oracle["win"]),
				"%s seed %d: outcome matches oracle (engine %s / oracle win=%s)" % [
					label, seed, outcome, str(oracle["win"])])
			var result: Dictionary = eng["result"]
			assert_eq(int(result["ms"]), int(oracle["ms"]),
				"%s seed %d: kill/death blow time matches oracle" % [label, seed])
			assert_eq(int(result["eaten"]), int(oracle["eaten"]),
				"%s seed %d: foods eaten matches oracle" % [label, seed])
			assert_eq(int(eng["tm"].state.combat["p_hp"]), int(oracle["p_hp"]),
				"%s seed %d: final player HP matches oracle" % [label, seed])
			assert_eq(eng["food_left"], oracle["food"],
				"%s seed %d: remaining food matches oracle" % [label, seed])
			# R3 (critique P3#5): landed-swing counters match the oracle's own
			# hit rolls exactly — a 0-damage hit still counts as landed.
			assert_eq(int(eng["tm"].state.combat["p_hits"]), int(oracle["p_hits"]),
				"%s seed %d: player landed swings match oracle" % [label, seed])
			assert_eq(int(eng["tm"].state.combat["m_hits"]), int(oracle["m_hits"]),
				"%s seed %d: monster landed swings match oracle" % [label, seed])
			if outcome == "victory":
				assert_eq(result["drops"], _oracle_drops(monster.drop_table, int(oracle["rng_state"])),
					"%s seed %d: drops match the seeded stream replay" % [label, seed])


## R3 (critique P3#5) — the hit counters that separate a landed 0-damage hit
## from a miss at the diff seam: engage resets them, they count ONLY accuracy
## connects (before the damage roll — a 0-damage hit counts), and they ride
## the save round-trip like every other combat int.
func test_hit_counters_mark_connects_not_damage() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var st: PlayerState = tm.state
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engage the min_hit-0 fauna")
	assert_eq(int(st.combat["p_hits"]), 0, "engage resets p_hits (fresh engagement)")
	assert_eq(int(st.combat["m_hits"]), 0, "engage resets m_hits")
	# Swing-by-swing: every pendings advance is exactly one swing per side;
	# counters may only tick when the roll passed, and a landed swing that
	# drew zero blood STILL ticks (the Litterbug's min_hit 0 case).
	var landed_zero_seen := false
	var mismatch := ""
	for i in 60:
		var before := {
			"p_next": int(st.combat["p_next_ms"]), "m_next": int(st.combat["m_next_ms"]),
			"p_hp": int(st.combat["p_hp"]), "m_hp": int(st.combat["m_hp"]),
			"p_hits": int(st.combat["p_hits"]), "m_hits": int(st.combat["m_hits"])}
		tm.advance_wall_ms(100)
		if str(st.combat["phase"]) != "fighting":
			break
		var p_swung: bool = int(st.combat["p_next_ms"]) > int(before["p_next"])
		var m_swung: bool = int(st.combat["m_next_ms"]) > int(before["m_next"])
		var p_hit: int = int(st.combat["p_hits"]) - before["p_hits"]
		var m_hit: int = int(st.combat["m_hits"]) - before["m_hits"]
		if p_swung and (p_hit < 0 or p_hit > 1):
			mismatch = "player swing ticked p_hits by %d" % p_hit
		if m_swung and (m_hit < 0 or m_hit > 1):
			mismatch = "fauna swing ticked m_hits by %d" % m_hit
		# A landed fauna swing that moved no HP IS the 0-damage connect.
		if m_swung and m_hit == 1 and int(st.combat["p_hp"]) == before["p_hp"]:
			landed_zero_seen = true
		# The player's damage floor is 1: a landed player swing must move
		# the fauna's HP (misses are the only bloodless player swings).
		if p_swung and p_hit == 1 and int(st.combat["m_hp"]) == before["m_hp"]:
			mismatch = "landed player swing drew no blood (min_hit floor violated)"
	assert_eq(mismatch, "", "counters tick exactly on connects: %s" % mismatch)
	assert_gt(int(st.combat["p_hits"]) + int(st.combat["m_hits"]), 0, "some swings landed")
	# Deterministic at this seed: the Litterbug fight's FIRST fauna swing
	# (2,800 ms) connects and rolls 0 damage — the exact case the counters
	# exist to separate from a miss (verified by stream replay).
	assert_true(landed_zero_seen,
		"the seeded fight's first fauna swing connects for 0 damage — counted as landed")

	# Re-engage resets the counters with the rest of the engagement state.
	tm.stop_combat()
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "re-engage")
	assert_eq(int(st.combat["p_hits"]), 0, "re-engage resets p_hits")
	assert_eq(int(st.combat["m_hits"]), 0, "re-engage resets m_hits")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# (d) 200-seed boss sweeps vs balance-notes §2
# ---------------------------------------------------------------------------

func _sweep(label: String, weapon_id: String, armor_id: String, food: Dictionary) -> Dictionary:
	var wins := 0
	var times: Array[int] = []
	var eaten: Array[int] = []
	for i in SWEEP_SEEDS:
		var eng := _run_fight(SWEEP_BASE_SEED + i, weapon_id, armor_id, "sewer_landlord",
			food.duplicate(), L14_XP, 900_000)
		if eng["outcome"] == "victory":
			wins += 1
		var end_ms := 900_000
		if eng["outcome"] != "timeout":
			end_ms = int(eng["result"]["ms"])
		times.append(end_ms)
		eaten.append(int(eng["result"].get("eaten", 0)))
	times.sort()
	eaten.sort()
	var median_ms: int = times[SWEEP_SEEDS / 2]
	var median_eaten: int = eaten[SWEEP_SEEDS / 2]
	print("T7 SWEEP %-32s %d/%d wins  median %d ms  median food %d" % [
		label, wins, SWEEP_SEEDS, median_ms, median_eaten])
	return {"wins": wins, "median_ms": median_ms, "median_eaten": median_eaten}


func test_boss_balance_200_seed_sweeps() -> void:
	# §2 row 1: max gear + 6 stews wins reliably, in a fight, with food mattering.
	var max_food := _sweep("boss vs MAX + 6 stews", "majority_whip", "carpool_carapace", {"radstag_stew": 6})
	assert_true(max_food["wins"] >= SWEEP_SEEDS - 2,
		"BOSS BEATABLE: max gear + best food wins >= %d/%d (got %d)" % [
			SWEEP_SEEDS - 2, SWEEP_SEEDS, max_food["wins"]])
	assert_true(max_food["median_ms"] < 180_000,
		"winning fight stays a fight (< 3 min median, got %d ms)" % max_food["median_ms"])
	assert_true(max_food["median_eaten"] >= 1,
		"food matters in the winning loadout (median %d eaten)" % max_food["median_eaten"])
	# §2 row 3: mid gear without food NEVER wins (T5 acceptance line).
	var mid_nofood := _sweep("boss vs MID, no food", "scrap_shiv", "hubcap_vest", {})
	assert_eq(mid_nofood["wins"], 0, "BOSS NOT TRIVIAL: mid gear no-food wins 0/%d (got %d)" % [
		SWEEP_SEEDS, mid_nofood["wins"]])
	# §2 row 5: the gear floor is real — 20 best meals cannot carry the chassis.
	var bare_food := _sweep("boss vs BARE + 20 stews", "", "", {"radstag_stew": 20})
	assert_eq(bare_food["wins"], 0, "cannot out-eat the boss naked (0/%d expected, got %d)" % [
		SWEEP_SEEDS, bare_food["wins"]])
	# §2 row 2: max gear still mostly needs food (§2's own 200-seed sim: 9/191;
	# the probe's threshold at 25 seeds was <= 5 — equivalent tail allowance).
	var max_nofood := _sweep("boss vs MAX, no food", "majority_whip", "carpool_carapace", {})
	assert_true(max_nofood["wins"] <= 20,
		"max gear without food mostly loses (wins <= 20/%d, got %d)" % [SWEEP_SEEDS, max_nofood["wins"]])


# ---------------------------------------------------------------------------
# (e) death halts with zero loss
# ---------------------------------------------------------------------------

func test_death_stops_with_zero_loss() -> void:
	var tm: Variant = _make_tm(777)
	var st: PlayerState = tm.state
	tm.engine.grant_xp(st, "wasteland_combat", L14_XP)
	st.add_item("scrap_shiv", 1)
	st.add_item("hubcap_vest", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "mid weapon")
	assert_true(tm.equip_item("hubcap_vest")["ok"], "mid armor")
	assert_true(st.inventory.is_empty(), "empty Hands (food-free death proof)")
	var xp_before := st.skills_xp.duplicate()
	var ends: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss under-geared")
	_pump(tm, 400_000, 2_500)

	assert_eq(String(st.combat["phase"]), "dead", "death stops combat (RETURN TO SHELTER state)")
	assert_eq(ends.size(), 1, "combat_ended fired exactly once")
	assert_eq(String(ends[0]["outcome"]), "death", "payload outcome death")
	assert_eq(st.skills_xp, xp_before, "ZERO xp loss on death")
	assert_true(st.inventory.is_empty(), "ZERO item loss on death")
	assert_eq(st.crowns, 0, "wallet untouched")
	assert_eq(ends[0]["drops"], {}, "no drops on death")

	# Halting is real: another minute of ticking changes nothing.
	var m_hp_frozen := int(st.combat["m_hp"])
	_pump(tm, 60_000, 2_500)
	assert_eq(String(st.combat["phase"]), "dead", "still dead after more ticks")
	assert_eq(int(st.combat["m_hp"]), m_hp_frozen, "monster HP frozen after death")
	assert_eq(ends.size(), 1, "no second combat_ended")
	assert_eq(st.skills_xp, xp_before, "still zero xp change")

	# With-food variant: food eaten during the fight is accounted exactly;
	# death itself still removes nothing beyond that.
	var tm2: Variant = _make_tm(778)
	var st2: PlayerState = tm2.state
	tm2.engine.grant_xp(st2, "wasteland_combat", L14_XP)
	st2.add_item("scrap_shiv", 1)
	st2.add_item("hubcap_vest", 1)
	st2.add_item("mandatory_grits", 2)
	assert_true(tm2.equip_item("scrap_shiv")["ok"], "mid weapon (food variant)")
	assert_true(tm2.equip_item("hubcap_vest")["ok"], "mid armor (food variant)")
	var ends2: Array = []
	tm2.combat_ended.connect(func(result: Dictionary) -> void: ends2.append(result))
	assert_true(tm2.engage_monster("sewer_landlord")["ok"], "engage (food variant)")
	_pump(tm2, 400_000, 2_500)
	assert_eq(String(st2.combat["phase"]), "dead", "mid gear + grits still dies to the boss (§2)")
	var eaten: int = ends2[0]["eaten"]
	assert_eq(st2.item_count("mandatory_grits"), 2 - eaten,
		"remaining grits == starting minus auto-eaten (eaten %d)" % eaten)
	for item_id in st2.inventory:
		assert_eq(String(item_id), "mandatory_grits",
			"nothing but remaining grits in the Manifest (got %s)" % str(item_id))


# ---------------------------------------------------------------------------
# (f) auto-eat rules
# ---------------------------------------------------------------------------

func _eat_setup(seed: int, food: Dictionary) -> Variant:
	var tm: Variant = _make_tm(seed)
	var st: PlayerState = tm.state
	st.add_item("hubcap_vest", 1)
	assert_true(tm.equip_item("hubcap_vest")["ok"], "Pedestrian Plating (120 max HP, threshold 60)")
	for item_id in food:
		st.add_item(String(item_id), int(food[item_id]))
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "Litterbug engaged (slow damage)")
	return tm


func test_auto_eat_best_first_at_threshold() -> void:
	var tm: Variant = _eat_setup(55, {"radstag_stew": 2, "mandatory_grits": 5})
	var st: PlayerState = tm.state
	st.combat["p_hp"] = 60  # test seam: exactly AT the integer threshold (120/2)
	_pump(tm, 2_800, TICK_MS)  # Litterbug swings at 2800 (player's first is at 3000)
	assert_eq(int(st.combat["eaten_total"]), 1, "one eat: heal clears the threshold")
	assert_eq(st.item_count("radstag_stew"), 1, "BEST food (stew 80) eaten first")
	assert_eq(st.item_count("mandatory_grits"), 5, "grits untouched while a stew remains")
	assert_eq(int(st.combat["p_hp"]), 120, "heal clamped at max_hp (60..58 + 80 -> 120)")


func test_auto_eat_repeats_while_below_threshold() -> void:
	# Grits heal 15: from 10 HP the loop must chain eats until ABOVE 60.
	# (The Litterbug's 0-2 swing lands first: final HP is 68-70 depending on it.)
	var tm: Variant = _eat_setup(56, {"mandatory_grits": 5})
	var st: PlayerState = tm.state
	st.combat["p_hp"] = 10
	_pump(tm, 2_800, TICK_MS)
	assert_eq(int(st.combat["eaten_total"]), 4, "eats repeat while <= threshold: 10->25->40->55->70")
	assert_eq(st.item_count("mandatory_grits"), 1, "4 of 5 grits consumed")
	assert_between(int(st.combat["p_hp"]), 61, 70, "stops once above half (Litterbug hits 0-2)")


func test_auto_eat_no_food_no_eat() -> void:
	var tm: Variant = _eat_setup(57, {})
	var st: PlayerState = tm.state
	st.combat["p_hp"] = 10
	_pump(tm, 2_800, TICK_MS)
	assert_eq(int(st.combat["eaten_total"]), 0, "no food in the Manifest: no eat, no crash")
	assert_true(int(st.combat["p_hp"]) <= 10, "HP stays low (Litterbug hits 0-2)")


# ---------------------------------------------------------------------------
# (g) victory: XP pipeline, drops, level signal; zone clear
# ---------------------------------------------------------------------------

func test_victory_xp_drops_and_level_signal() -> void:
	var tm: Variant = _make_tm(SWEEP_BASE_SEED)
	var st: PlayerState = tm.state
	var ends: Array = []
	var levelups: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	tm.level_up.connect(func(skill_id: String, old_level: int, new_level: int) -> void:
		levelups.append([skill_id, old_level, new_level]))
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "first blood: bare vs Litterbug")
	_pump(tm, 300_000, 1_000)

	assert_eq(String(st.combat["phase"]), "victory", "Litterbug dies to bare hands (§2)")
	assert_eq(ends.size(), 1, "combat_ended fired once")
	var result: Dictionary = ends[0]
	assert_eq(String(result["outcome"]), "victory", "victory payload")
	assert_eq(String(result["monster_id"]), "junkyard_roach", "monster recorded")
	assert_eq(int(result["xp"]), 25, "xp_reward from content")
	assert_eq(int(st.skills_xp["wasteland_combat"]), 25, "XP lands on Wasteland Combat")
	assert_eq(int(st.skills_level["wasteland_combat"]), 2, "25 xp crosses level 2 (step 1 = 20)")
	assert_eq(levelups, [["wasteland_combat", 1, 2]], "one IMMEDIATE level_up through the shared pipeline")
	for skill_id in ["scavenging", "foraging", "junksmithing", "cooking"]:
		assert_eq(int(st.skills_xp[skill_id]), 0, "%s untouched by combat" % skill_id)
	# Drops: exactly what the seeded stream replay predicts (roach table, 1 roll).
	var oracle := _oracle_fight(_oracle_stats("", ""), _lib().monster("junkyard_roach"),
		{}, _oracle_stream_seed(SWEEP_BASE_SEED), 300_000)
	assert_eq(result["drops"], _oracle_drops("roach_nest", int(oracle["rng_state"])),
		"victory drops match the seeded roll replay")
	assert_eq(st.inventory, result["drops"], "the Manifest holds exactly the drops (no food used)")


func test_boss_victory_sets_persistent_zone_clear() -> void:
	var tm: Variant = _make_tm(SWEEP_BASE_SEED)
	var st: PlayerState = tm.state
	tm.engine.grant_xp(st, "wasteland_combat", L14_XP)
	for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", 6]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("majority_whip")["ok"], "max weapon")
	assert_true(tm.equip_item("carpool_carapace")["ok"], "max armor")
	var cleared: Array = []
	tm.zone_cleared.connect(func(monster_id: String) -> void: cleared.append(monster_id))
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss")
	_pump(tm, 400_000, 2_500)
	assert_eq(String(st.combat["phase"]), "victory", "max gear + stews clears the boss (§2)")
	assert_eq(cleared, ["sewer_landlord"], "zone_cleared fired ONCE, immediately")
	assert_true(bool(st.combat["zone_clear"]), "persistent zone-clear state set")

	# A repeat clear stays a farm loop, not a second win moment.
	st.add_item("radstag_stew", maxi(6 - st.item_count("radstag_stew"), 0))  # restock
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "re-engage the boss")
	_pump(tm, 400_000, 2_500)
	assert_eq(String(st.combat["phase"]), "victory", "second clear also wins")
	assert_eq(cleared.size(), 1, "zone_cleared does NOT fire again")
	assert_true(bool(st.combat["zone_clear"]), "state stays true")

	# Non-boss victories never touch it.
	var tm2: Variant = _make_tm(SWEEP_BASE_SEED)
	var st2: PlayerState = tm2.state
	var cleared2: Array = []
	tm2.zone_cleared.connect(func(monster_id: String) -> void: cleared2.append(monster_id))
	assert_true(tm2.engage_monster("junkyard_roach")["ok"], "roach on a fresh state")
	_pump(tm2, 300_000, 1_000)
	assert_eq(String(st2.combat["phase"]), "victory", "roach dies")
	assert_false(bool(st2.combat["zone_clear"]), "non-boss victory does not clear the zone")
	assert_eq(cleared2.size(), 0, "no zone_cleared signal")


# ---------------------------------------------------------------------------
# (h) save round-trip: split fight == uninterrupted twin
# ---------------------------------------------------------------------------

func _boss_setup(tm: Variant) -> void:
	var st: PlayerState = tm.state
	tm.engine.grant_xp(st, "wasteland_combat", L14_XP)
	for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", 6]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("majority_whip")["ok"], "max weapon")
	assert_true(tm.equip_item("carpool_carapace")["ok"], "max armor")
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss")


func test_save_round_trip_resumes_exactly() -> void:
	const SPLIT_MS := 30_000  # min possible boss kill is 38 s (340/18 swings) — fight MUST be live here

	# Uninterrupted twin.
	var whole: Variant = _make_tm(SWEEP_BASE_SEED)
	_boss_setup(whole)
	var ends_whole: Array = []
	whole.combat_ended.connect(func(result: Dictionary) -> void: ends_whole.append(result))
	_pump(whole, 400_000, 2_500)
	assert_eq(String(whole.state.combat["phase"]), "victory", "twin A wins")

	# Split twin: fight to SPLIT_MS, save through the REAL medium (JSON string),
	# load into a fresh engine, resume with a zero offline gap.
	var split: Variant = _make_tm(SWEEP_BASE_SEED)
	_boss_setup(split)
	_pump(split, SPLIT_MS, 1_000)
	assert_eq(String(split.state.combat["phase"]), "fighting", "split taken mid-fight")
	var saved_sim: int = split.sim_time_ms
	var doc: Dictionary = JSON.parse_string(JSON.stringify(split.state.to_dict()))
	assert_eq(typeof(doc["combat"]["rng_state"]), TYPE_STRING,
		"combat rng state ships as a string (int64-exact past JSON's 2^53 cliff)")

	var resumed_state := PlayerState.from_dict(doc, _lib())
	var resume: Variant = _make_tm(SWEEP_BASE_SEED)
	resume.adopt_state(resumed_state, saved_sim)
	var zero_gap: Dictionary = resume.apply_offline_elapsed(0)
	assert_eq(int(zero_gap["elapsed_ms"]), 0, "zero gap is a no-op")
	assert_eq(String(resume.state.combat["phase"]), "fighting", "fight adopted mid-flight")
	var ends_resume: Array = []
	resume.combat_ended.connect(func(result: Dictionary) -> void: ends_resume.append(result))
	_pump(resume, 400_000, 2_500)

	assert_eq(String(resume.state.combat["phase"]), "victory", "resumed fight finishes")
	assert_eq(ends_resume[0], ends_whole[0],
		"resumed payload == uninterrupted payload (ms/eaten/drops/xp all equal)")
	assert_eq(resume.state.inventory, whole.state.inventory,
		"final Manifest identical (exact stream continuation)")
	assert_eq(resume.state.skills_xp, whole.state.skills_xp, "final XP identical")
	# R3: the hit counters survive the JSON round-trip and finish identical.
	assert_eq(int(resume.state.combat["p_hits"]), int(whole.state.combat["p_hits"]),
		"final p_hits identical (counters ride the save round-trip)")
	assert_eq(int(resume.state.combat["m_hits"]), int(whole.state.combat["m_hits"]),
		"final m_hits identical")


# ---------------------------------------------------------------------------
# (i) offline disposition: no combat progress, pending shifted, others full-rate
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# (i) offline combat: full-rate survivable replay (coordinator ruling)
# ---------------------------------------------------------------------------

func _offline_setup(seed: int, stews: int) -> Variant:
	var tm: Variant = _make_tm(seed)
	tm.engine.grant_xp(tm.state, "wasteland_combat", L14_XP)
	for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", stews]]:
		tm.state.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("majority_whip")["ok"], "max weapon")
	assert_true(tm.equip_item("carpool_carapace")["ok"], "max armor")
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss at sim 0")
	return tm


func test_offline_survivable_prefix_equals_live_exactly() -> void:
	const GAP := 30_000  # below the 38 s mathematical minimum boss kill: mid-fight for certain
	# LIVE twin: play the same 30 s through the funnel.
	var live: Variant = _offline_setup(SWEEP_BASE_SEED, 6)
	_pump(live, GAP, TICK_MS)
	# OFFLINE twin: the same 30 s as an away gap (replay path).
	var off: Variant = _offline_setup(SWEEP_BASE_SEED, 6)
	var payload: Dictionary = off.apply_offline_elapsed(GAP)
	var cl: Dictionary = live.state.combat
	var co: Dictionary = off.state.combat
	assert_eq(String(co["phase"]), "fighting", "replay resumed mid-fight")
	assert_eq(String(co["phase"]), String(cl["phase"]), "same phase as the live twin")
	assert_eq(int(co["p_hp"]), int(cl["p_hp"]), "player HP == live twin after the same elapsed fight")
	assert_eq(int(co["m_hp"]), int(cl["m_hp"]), "monster HP == live twin")
	assert_eq(int(co["eaten_total"]), int(cl["eaten_total"]), "same foods auto-eaten")
	assert_eq(off.state.inventory, live.state.inventory, "same Manifest")
	assert_eq(String(co["rng_state"]), String(cl["rng_state"]), "RNG stream at the exact same position")
	# Pendings: offline times are gap-relative (T6 anchor-rewind parity).
	assert_eq(int(co["p_next_ms"]) + GAP, int(cl["p_next_ms"]), "player wind-up phase preserved")
	assert_eq(int(co["m_next_ms"]) + GAP, int(cl["m_next_ms"]), "monster wind-up phase preserved")
	# Live continuation from the replayed state finishes identically. Absolute
	# ms differs by exactly GAP (the sim clock never lived through the away
	# time — every other field, including fight DURATION, must match).
	var ends_live: Array = []
	live.combat_ended.connect(func(result: Dictionary) -> void: ends_live.append(result))
	var ends_off: Array = []
	off.combat_ended.connect(func(result: Dictionary) -> void: ends_off.append(result))
	_pump(live, 400_000, 2_500)
	_pump(off, 400_000, 2_500)
	assert_eq(String(ends_off[0]["outcome"]), String(ends_live[0]["outcome"]), "same outcome")
	assert_eq(int(ends_off[0]["ms"]) + GAP, int(ends_live[0]["ms"]),
		"kill lands GAP earlier on the resumed sim clock — same live fight")
	assert_eq(int(ends_off[0]["duration_ms"]), int(ends_live[0]["duration_ms"]), "same fight duration")
	assert_eq(int(ends_off[0]["eaten"]), int(ends_live[0]["eaten"]), "same foods eaten")
	assert_eq(ends_off[0]["drops"], ends_live[0]["drops"], "same drops")
	assert_eq(off.state.inventory, live.state.inventory, "identical final Manifest")


func test_offline_farming_chain_equals_live_twin() -> void:
	const GAP := 300_000  # ~3 deterministic boss kills at the seed's pace
	# LIVE twin: plays every tick; on each victory instantly re-engages (the
	# live model of the offline chain, which re-engages at the kill instant).
	var live: Variant = _offline_setup(SWEEP_BASE_SEED, 20)
	var live_kills := 0
	for i in GAP / TICK_MS:
		live.advance_wall_ms(TICK_MS)
		if String(live.state.combat["phase"]) == "victory":
			live_kills += 1
			assert_true(live.engage_monster("sewer_landlord")["ok"], "twin re-engages at the kill tick")
	# OFFLINE twin: the same window as one away gap.
	var off: Variant = _offline_setup(SWEEP_BASE_SEED, 20)
	var payload: Dictionary = off.apply_offline_elapsed(GAP)
	var kills: int = payload["combat"]["kills"]
	assert_gt(kills, 1, "the chain farmed multiple bosses offline (%d kills)" % kills)
	assert_eq(kills, live_kills, "offline kills == live twin kills")
	assert_eq(String(off.state.combat["phase"]), String(live.state.combat["phase"]), "same phase")
	assert_eq(int(off.state.combat["p_hp"]), int(live.state.combat["p_hp"]), "same HP")
	assert_eq(int(off.state.combat["m_hp"]), int(live.state.combat["m_hp"]), "same monster HP")
	assert_eq(off.state.inventory, live.state.inventory, "identical Manifest (drops + eaten food)")
	assert_eq(int(off.state.skills_xp["wasteland_combat"]), int(live.state.skills_xp["wasteland_combat"]),
		"identical XP (%d kills banked)" % kills)
	assert_eq(String(off.state.combat["rng_state"]), String(live.state.combat["rng_state"]),
		"stream positions identical")
	assert_eq(int(off.state.combat["p_next_ms"]) + GAP, int(live.state.combat["p_next_ms"]),
		"wind-up phase preserved across the whole chain")
	assert_eq(int(payload["skills_xp"]["wasteland_combat"]), kills * 1000,
		"MAIL CALL reports the combat XP delta")
	assert_eq(int(payload["actions"]["wasteland_combat"]), kills,
		"MAIL CALL reports kills as the combat action count")


func test_offline_recall_when_death_would_occur() -> void:
	# Mid gear, NO food vs the boss: live play dies at ~48 s (§2). Offline the
	# killing blow NEVER lands — the patrol is recalled alive, zero loss.
	var tm: Variant = _make_tm(SWEEP_BASE_SEED)
	tm.engine.grant_xp(tm.state, "wasteland_combat", L14_XP)
	for pair in [["scrap_shiv", 1], ["hubcap_vest", 1]]:
		tm.state.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("scrap_shiv")["ok"], "mid weapon")
	assert_true(tm.equip_item("hubcap_vest")["ok"], "mid armor")
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage under-geared, food-free")
	var ends: Array = []
	var levelups: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	tm.level_up.connect(func(skill_id: String, o: int, n: int) -> void: levelups.append([skill_id, o, n]))
	var xp_before: int = int(tm.state.skills_xp["wasteland_combat"])

	var payload: Dictionary = tm.apply_offline_elapsed(300_000)
	var c: Dictionary = tm.state.combat
	assert_eq(String(c["phase"]), "recalled", "recalled (not dead) when the blow would kill")
	assert_ne(String(c["phase"]), "dead", "a no-agency DEATH never occurs offline")
	assert_gt(int(c["p_hp"]), 0, "player ALIVE at pre-blow HP (blow never landed): %d" % int(c["p_hp"]))
	assert_eq(int(c["p_next_ms"]), 0, "no pending swings while recalled")
	assert_eq(int(payload["combat"]["kills"]), 0, "no kills")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), xp_before, "zero XP change")
	assert_true(tm.state.inventory.is_empty(), "zero loss (empty Hands stay empty)")
	assert_eq(String(payload["combat"]["notice"]), "PATROL RECALLED", "payload carries the recall notice")
	assert_eq(payload["stopped"][0]["reason"], "patrol_recalled", "PATROL RECALLED stopped-line for T10")
	assert_gt(int(payload["combat"]["recalled_at_ms"]), 0, "recall instant reported")
	assert_eq(ends.size(), 0, "no combat_ended signal offline (payload carries it)")
	assert_eq(levelups.size(), 0, "no level_up signal offline")
	# Alive and able to go back out immediately.
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "re-engage after a recall works")
	assert_eq(int(tm.state.combat["p_hp"]), 120, "fresh fight resets HP to the equipped max (§1.4 addendum 1)")


func test_offline_food_exhaustion_recalls() -> void:
	# Seed 1001 vs the boss with 2 stews: fight 1 wins eating both, fight 2
	# replays foodless, hits its would-be killing blow, and recalls.
	var tm: Variant = _offline_setup(1001, 2)
	var payload: Dictionary = tm.apply_offline_elapsed(900_000)
	var c: Dictionary = tm.state.combat
	assert_eq(String(c["phase"]), "recalled", "food exhaustion leads to recall (ruling b)")
	assert_eq(int(payload["combat"]["kills"]), 1, "exactly the food-funded kill happened (deterministic)")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), L14_XP + 1000, "one kill's XP banked")
	assert_eq(tm.state.item_count("radstag_stew"), 0, "stews exhausted")
	assert_gt(int(c["p_hp"]), 0, "player alive at the recall instant")
	assert_eq(String(payload["combat"]["notice"]), "PATROL RECALLED", "recall notice posted")
	assert_true(tm.state.inventory.size() >= 1, "the first kill's drops were banked: %s" % str(tm.state.inventory))
	# The banked drops equal ONE deterministic boss-table double roll (the
	# re-engaged fight reseeds, so every kill drops the same stack).
	assert_eq(int(tm.state.inventory.get("scrap_metal", 0)) % 4, 0,
		"boss scrap drops come in 4-8 stacks (one kill banked)")


func test_offline_boss_farm_bounded_and_zone_clear() -> void:
	# 50 stews, 15 min away: the boss falls repeatedly at the deterministic
	# farm rate — the win moment is achievable offline, but only with food,
	# and never faster than the fight itself can end.
	var tm: Variant = _offline_setup(SWEEP_BASE_SEED, 50)
	var payload: Dictionary = tm.apply_offline_elapsed(900_000)
	var c: Dictionary = tm.state.combat
	var kills: int = payload["combat"]["kills"]
	assert_gt(kills, 4, "the boss farm chained (%d kills in 15 min)" % kills)
	assert_true(kills <= 900_000 / 38_000,
		"farm rate bounded by the fastest possible kill (38 s min): %d kills" % kills)
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), L14_XP + kills * 1000,
		"XP == kills * xp_reward (no phantom gains)")
	assert_true(bool(c["zone_clear"]), "offline first clear sets the persistent zone-clear state")
	assert_eq(bool(payload["combat"].get("zone_cleared")), true,
		"MAIL CALL carries the offline win moment (signal withheld per offline policy)")
	assert_eq(String(c["phase"]), "fighting", "gap ended mid-next-fight")
	assert_between(int(c["p_next_ms"]), 1, 2000,
		"resume wind-up is one weapon interval out (anchor-rewind parity)")
	assert_gt(tm.state.item_count("radstag_stew"), 0, "well-stocked food survives the gap")
	# A mid-fight gap end still LIVE-CONTINUES identically: pump to the next
	# kill and it matches the deterministic fight's payload shape.
	var ends: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	_pump(tm, 400_000, 2_500)
	assert_eq(String(tm.state.combat["phase"]), "victory", "live continuation completes the fight")
	assert_eq(int(ends[0]["xp"]), 1000, "victory chain intact after the offline farm")


func test_offline_combat_requires_a_live_fight() -> void:
	# Only a mid-fight save replays: idle/victory/dead saves never auto-start.
	var idle: Variant = _make_tm(SWEEP_BASE_SEED)
	var idle_payload: Dictionary = idle.apply_offline_elapsed(3_600_000)
	assert_false(idle_payload.has("combat"), "idle save: no combat section (nothing started)")
	assert_eq(String(idle.state.combat["phase"]), "idle", "still idle")

	var victor: Variant = _offline_setup(SWEEP_BASE_SEED, 6)
	_pump(victor, 400_000, 2_500)
	assert_eq(String(victor.state.combat["phase"]), "victory", "fight won live")
	var xp_after_kill: int = int(victor.state.skills_xp["wasteland_combat"])
	var inv_after_kill: Dictionary = victor.state.inventory.duplicate()
	var v_payload: Dictionary = victor.apply_offline_elapsed(3_600_000)
	assert_false(v_payload.has("combat"), "victory-phase save does not auto-farm offline")
	assert_eq(int(victor.state.skills_xp["wasteland_combat"]), xp_after_kill, "no offline XP")
	assert_eq(victor.state.inventory, inv_after_kill, "no offline drops/food")


# ---------------------------------------------------------------------------
# (j) tick-funnel exclusivity + determinism
# ---------------------------------------------------------------------------

func test_combat_advances_only_via_tick_funnel() -> void:
	var tm: Variant = _make_tm(555)
	var st: PlayerState = tm.state
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engage")
	var m_hp0 := int(st.combat["m_hp"])
	var p_next0 := int(st.combat["p_next_ms"])

	# Driving the ACTIVITY engine directly (its public tick) moves nothing.
	tm.engine.tick(st, tm.sim_time_ms + 100_000)
	assert_eq(int(st.combat["m_hp"]), m_hp0, "ActivityEngine.tick does not touch combat")
	assert_eq(int(st.combat["p_next_ms"]), p_next0, "no swings resolved out-of-band")
	assert_false(bool(st.combat["stream_started"]), "no rolls drawn out-of-band")

	# The wall funnel is what advances combat: bare first swing at 3000 ms.
	# (The Litterbug's own first swing is at 2800 — monster interval.)
	_pump(tm, 2_900, TICK_MS)
	assert_eq(int(st.combat["p_next_ms"]), 3000, "player swing still pending before 3000 ms")
	_pump(tm, TICK_MS, TICK_MS)  # sim 3000 exactly
	assert_eq(int(st.combat["p_next_ms"]), 6000, "player's first swing resolved at 3000 ms")
	assert_true(bool(st.combat["stream_started"]), "rolls were drawn by the funnel only")


func test_same_seed_fights_are_bit_identical() -> void:
	var a: Variant = _make_tm(999)
	var b: Variant = _make_tm(999)
	for tm in [a, b]:
		_boss_setup(tm)
	_pump(a, 120_000, 2_500)
	_pump(b, 120_000, 1_000)  # different chunking must not matter (int sim clock)
	assert_eq(a.state.combat, b.state.combat,
		"same world seed + gear + monster -> identical combat state (deterministic stream)")


# ---------------------------------------------------------------------------
# (k) signal budget + immediacy
# ---------------------------------------------------------------------------

func test_signal_budget_over_60s_fight() -> void:
	var tm: Variant = _make_tm(SWEEP_BASE_SEED)
	var st: PlayerState = tm.state
	tm.engine.grant_xp(st, "wasteland_combat", L10_XP)
	for pair in [["scrap_shiv", 1], ["hubcap_vest", 1], ["compliant_casserole", 4]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("scrap_shiv")["ok"], "mid weapon")
	assert_true(tm.equip_item("hubcap_vest")["ok"], "mid armor")
	var bulk := {"n": 0}
	tm.bulk_state_changed.connect(func(_changes: Dictionary) -> void: bulk["n"] = int(bulk["n"]) + 1)
	assert_true(tm.engage_monster("feral_snack_dispenser")["ok"], "a fight that outlasts the window")
	_pump(tm, 60_000, 1_000)
	var budget := 4 * 60
	assert_true(int(bulk["n"]) <= budget,
		"bulk emissions %d within the 4 Hz budget (%d) while fighting" % [int(bulk["n"]), budget])
	assert_true(int(bulk["n"]) >= 2, "bulk signal does flow while fighting")


func test_combat_ended_is_immediate_and_once() -> void:
	var tm: Variant = _make_tm(SWEEP_BASE_SEED)
	var st: PlayerState = tm.state
	var ends: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engage")
	var signal_at := {"step": -1}
	var phase_at := {"step": -1}
	var step := 0
	while step < 4_000 and String(st.combat["phase"]) == "fighting":  # <= 400 s
		tm.advance_wall_ms(TICK_MS)
		step += 1
		if not ends.is_empty() and signal_at["step"] < 0:
			signal_at["step"] = step
		if String(st.combat["phase"]) != "fighting" and phase_at["step"] < 0:
			phase_at["step"] = step
	assert_ne(String(st.combat["phase"]), "fighting", "fight ended within the window")
	assert_eq(int(signal_at["step"]), int(phase_at["step"]),
		"combat_ended arrives within the SAME advance call as the killing tick (not rate-limited)")
	assert_eq(ends.size(), 1, "exactly one combat_ended per fight")


# ---------------------------------------------------------------------------
# (l) equip semantics
# ---------------------------------------------------------------------------

func test_equip_consumes_and_returns_gear() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var st: PlayerState = tm.state
	assert_false(tm.equip_item("majority_whip")["ok"], "unowned equipment refused")
	assert_false(tm.equip_item("scrap_metal")["ok"], "non-equipment refused")
	assert_false(tm.equip_item("phantom_gizmo")["ok"], "unknown id refused")

	st.add_item("majority_whip", 1)
	assert_true(tm.equip_item("majority_whip")["ok"], "equip the whip")
	assert_eq(String(st.combat["weapon"]), "majority_whip", "weapon slot filled")
	assert_eq(st.item_count("majority_whip"), 0, "equipped unit CONSUMED from the Manifest (§1.4 addendum 3)")

	st.add_item("hubcap_vest", 1)
	assert_true(tm.equip_item("hubcap_vest")["ok"], "equip the vest")
	assert_eq(String(st.combat["armor"]), "hubcap_vest", "armor slot filled")

	st.add_item("carpool_carapace", 1)
	assert_true(tm.equip_item("carpool_carapace")["ok"], "swap armor")
	assert_eq(st.item_count("carpool_carapace"), 0, "new armor consumed")
	assert_eq(st.item_count("hubcap_vest"), 1, "previous armor returned to the Manifest")

	assert_true(tm.unequip_slot("weapon")["ok"], "unequip weapon")
	assert_eq(String(st.combat["weapon"]), "", "weapon slot empty")
	assert_eq(st.item_count("majority_whip"), 1, "whip returned")
	assert_false(tm.unequip_slot("weapon")["ok"], "empty slot refuses")
	assert_false(tm.unequip_slot("hat")["ok"], "unknown slot refuses")


func test_midfight_equip_keeps_pending_swings() -> void:
	var tm: Variant = _make_tm(555)
	var st: PlayerState = tm.state
	st.add_item("scrap_shiv", 1)
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engage bare (first swing 3000)")
	_pump(tm, 1_000, TICK_MS)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "equip Point of Order mid-fight (2600 ms)")
	assert_eq(int(st.combat["p_next_ms"]), 3000,
		"pending swing keeps its scheduled time (§1.4 addendum 5)")
	_pump(tm, 2_000, TICK_MS)  # sim 3000: first swing resolves
	assert_eq(int(st.combat["p_next_ms"]), 5600,
		"the NEXT interval uses the new speed (3000 + 2600)")


# ---------------------------------------------------------------------------
# (m) load hygiene: hydrate + sanitize
# ---------------------------------------------------------------------------

func test_hydrate_and_sanitize_repair_hostile_state() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var st: PlayerState = tm.state
	st.combat = {
		"phase": "fighting",
		"monster_id": "ghost_monster",
		"weapon": "phaser",
		"p_hp": 5.0,  # JSON parses numbers as floats
		"rng_seed": 12345,
		"rng_state": "6789",
	}
	tm.adopt_state(st, 0)
	assert_eq(String(st.combat["phase"]), "idle", "unknown monster mid-fight -> fight dropped honestly")
	assert_eq(String(st.combat["weapon"]), "", "unknown equipment -> slot cleared")
	assert_eq(typeof(st.combat["p_hp"]), TYPE_INT, "floats re-typed to int")
	assert_eq(str(st.combat["rng_seed"]), "12345", "rng seed normalized to string form")
	for key in ["armor", "monster_id", "m_hp", "engage_ms", "p_next_ms", "m_next_ms",
			"stream_started", "eaten_total", "zone_clear"]:
		assert_true(st.combat.has(key), "default '%s' filled" % key)

	st.combat = {"phase": "bananas"}
	tm.adopt_state(st, 0)
	assert_eq(String(st.combat["phase"]), "idle", "unknown phase resets to idle")

	st.combat = {}
	tm.adopt_state(st, 0)
	assert_eq(String(st.combat["phase"]), "idle", "empty namespace -> defaults")
	assert_false(bool(st.combat["zone_clear"]), "zone clear defaults false")
