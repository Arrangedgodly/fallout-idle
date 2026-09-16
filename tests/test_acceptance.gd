extends GutTest
## tests/test_acceptance.gd — T13 acceptance suite (Hawkeye lane).
##
## Automates town-hall.md success measures 1–6 headless, against LIVE content
## (res://data through the production ContentLoader — same convention as the
## rest of the battery). Criterion 7 (naming checklist) is T4's manual gate,
## not automatable. Criterion 6's frame-budget MEASUREMENT runs WINDOWED in
## tests/probe_perf.gd (real renderer, 60 s worst-case window); this file
## carries the headless composite signal-budget side of that criterion.
##
## Organization mirrors the criteria:
##   C1  first-session journey: first Scavenging yield within 10 s of engine
##       start, ≤ 3 real UI actions from the dashboard (counted — plate select
##       + card engage), drop-delta accounting vs the engine (the T10b
##       verifier's journey-drill pattern, adopted), first clearance inside
##       the hook window.
##   C2  level gates unlock exactly as data specifies: a full clearance sweep
##       over activities + recipes + shop stock + monsters — every gate flips
##       locked → unlocked at exactly its data level — plus the UI gate-plate
##       flip on the Patrol surface.
##   C3  combat: equipment changes derived stats (engine AND the Patrol stats
##       panel), food auto-eats from the Manifest, death stops with zero loss,
##       and the zone boss falls to gear + food CRAFTED through the slice's own
##       recipe chain (journey 2: process → cook → equip → fight).
##   C4  save round-trips through the real SaveStore file medium on
##       quit/relaunch; offline gains equal elapsed × full rates with zero
##       drift (gathering + processing + survivable combat replay: live twin
##       vs offline twin, EXACT); clock regression loads clean with zero gains
##       and no NaN; plus the adopted T6-verifier oracles (interval boundary +
##       split application; 10k-roll independent stream replay) and the
##       T7-verifier exact recall-ms pin (recalled_at_ms == the live twin's
##       death-blow ms).
##   C5  shop buy/sell updates currency + inventory exactly (engine
##       transactions + the buy>sell spread swept over every stocked line) and
##       the Depot wallet/Manifest ride the batched "inventory" region (T10a
##       verifier carry: crowns ride the inventory bulk region — verified).
##   C6  headless composite signal budget (all five slots + live combat);
##       the measured windowed frame-budget report lives in probe_perf.gd.
##   T9  the swell-tween fix pin (repeated animated selections stay stable —
##       carried from the T10a verification).
##
## Determinism: fresh TickManager twins booted with explicit seeds via
## _boot(), never added to the tree (advance_wall_ms is the only clock input —
## same discipline as test_engine/test_combat/test_patrol).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260915
const NOW := 1_769_000_000_000  ## fixed wall moment; no test reads the real clock
const TICK_MS := 100
const L10_XP := 3_226   ## standard_99 total for Wasteland Combat 10 (Dispenser gate)
const L14_XP := 8_340   ## standard_99 total for Wasteland Combat 14 (boss gate)


# ------------------------------------------------------------------ helpers --

func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (acceptance runs on live data)")
	return result.library


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


## Feed exactly `total_ms` through the public wall funnel in sub-budget chunks.
func _pump(tm: Variant, total_ms: int, chunk_ms := 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


## Set a skill to an exact level through the same re-derivation PlayerState
## .from_dict performs (xp set to the curve's exact total; level re-derived).
func _set_level(tm: Variant, skill_id: String, level: int) -> void:
	var curve = tm.engine.lib.xp_curve(tm.engine.lib.skill(skill_id).xp_curve)
	var xp: int = curve.total_xp_to_reach(level)
	tm.state.skills_xp[skill_id] = xp
	tm.state.skills_level[skill_id] = curve.level_for_total_xp(xp)


## Mark regions + force flush — the harness-side twin of an engine-side
## mutation when a test seeds state directly.
func _flush(tm: Variant, regions: Array = ["inventory"]) -> void:
	for region in regions:
		tm.batcher.mark(region)
	tm.batcher.force_flush(tm.sim_time_ms)


func _make_concourse(tm: Variant) -> Concourse:
	var c := ConcourseScene.instantiate() as Concourse
	assert_not_null(c, "concourse scene instantiates")
	add_child_autofree(c)
	c.bind_engines(tm)
	await wait_frames(2)
	return c


func _tmp_dir(label: String) -> String:
	return OS.get_temp_dir().path_join("t13_%s_%d_%d" % [
		label, int(Time.get_unix_time_from_system() * 1000.0), randi() % 100000])


func _log_lines(log: ItemList) -> Array[String]:
	var out: Array[String] = []
	for i in log.item_count:
		out.append(log.get_item_text(i))
	return out


# ---------------------------------------------------------------------------
# C1 — first session: ≤ 3 UI actions, first yield ≤ 10 s, honest drops
# ---------------------------------------------------------------------------

func test_c1_first_scavenging_yield_within_ten_seconds_and_three_actions() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var levelups: Array = []
	tm.level_up.connect(func(skill_id: String, o: int, n: int) -> void:
		levelups.append([skill_id, o, n]))

	# THE JOURNEY, as real UI actions. Scavenging is the boot-default
	# department (START HERE chalk); a player arriving anywhere else performs
	# exactly this plate press first. Count every press.
	var ui_actions := 0
	(c.plates()["scavenging"] as Button).pressed.emit()
	ui_actions += 1
	assert_eq(c.active_department(), "scavenging", "action 1 (plate select): dashboard shows Scavenging")
	var docket := c.docket_controller("scavenging") as DocketGathering
	assert_not_null(docket, "scavenging docket mounted")
	var cards: Dictionary = docket.get("_cards")

	(cards["sort_scrap_pile"].button as Button).pressed.emit()
	ui_actions += 1
	assert_true(tm.state.active.has("scavenging"), "action 2 (card engage): shift posted through the real card button")
	assert_eq(ui_actions, 2, "the journey takes exactly plate-select + engage")
	assert_true(ui_actions <= 3, "CLICK BUDGET: %d user actions from dashboard (<= 3)" % ui_actions)

	# First yield: the tier-1 interval is 3 s, so the first action lands at
	# sim 3,000 — watch for it with a 10 s ceiling from engine start (boot = 0).
	var first_yield_sim := -1
	var fed := 0
	while fed < 10_000:
		tm.advance_wall_ms(TICK_MS)
		fed += TICK_MS
		if first_yield_sim < 0 and int(tm.state.skills_xp["scavenging"]) > 0:
			first_yield_sim = int(tm.sim_time_ms)
	assert_eq(first_yield_sim, 3_000, "first XP+drop action lands at exactly the first interval (3.0 s)")
	assert_true(first_yield_sim <= 10_000, "first yield within 10 s of engine start")
	assert_eq(int(tm.state.skills_xp["scavenging"]), 30, "3 actions x 10 xp by 10 s")
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "first clearance earned inside the hook window")
	assert_eq(levelups, [["scavenging", 1, 2]], "one immediate level_up crossing (at 6 s)")

	# Drop-delta accounting (T10b verifier's journey-drill pattern, adopted):
	# the stamped log lines must sum to EXACTLY the engine's inventory, and
	# the engine's inventory must be exactly 3 seeded rolls of the table.
	var stamped := {}
	for line in _log_lines(docket.log):
		if " +" in line:
			var parts := line.split(" +")
			stamped[parts[0]] = int(stamped.get(parts[0], 0)) + int(parts[1])
	var units := 0
	for item_id in tm.state.inventory:
		var item: ItemDef = tm.engine.lib.item(item_id)
		assert_eq(int(stamped.get(item.name.to_upper(), -1)), int(tm.state.inventory[item_id]),
			"stamped drop deltas account exactly for %s (log == engine)" % item_id)
		units += int(tm.state.inventory[item_id])
	assert_eq(stamped.size(), tm.state.inventory.size(), "no phantom stamp lines")
	assert_between(units, 3, 6, "3 rolls of the scrap_pile table (1 roll/action, qty 1-2)")
	tm.stop_skill("scavenging")


# ---------------------------------------------------------------------------
# C2 — level gates unlock exactly as data specifies
# ---------------------------------------------------------------------------

func test_c2_activity_and_recipe_gates_flip_at_data_levels() -> void:
	var tm: Variant = _make_tm(SEED)
	var lib: ContentLibrary = tm.engine.lib
	var records: Array = []  # [skill_id, gate_level, content_id]
	for id in lib.activities:
		var a: ActivityDef = lib.activities[id]
		records.append([a.skill, a.level_gate, id])
	for id in lib.recipes:
		var r: RecipeDef = lib.recipes[id]
		records.append([r.skill, r.level_gate, id])
	assert_true(records.size() >= 19, "content set present (8 activities + 11 recipes)")

	# The engine's gate table equals the data records, id for id.
	for rec in records:
		assert_eq(tm.engine.gate_of(rec[2]), {"skill": rec[0], "level": rec[1]},
			"gate_of('%s') matches the data record" % rec[2])

	# The sweep: at every level of every gating skill, the unlock state of
	# every record on that skill equals its data predicate (gate <= level).
	# This checks every flip boundary exactly (locked at gate-1, open at gate).
	var skills := {}
	for rec in records:
		skills[rec[0]] = true
	var max_gate := 1
	for rec in records:
		max_gate = maxi(max_gate, int(rec[1]))
	for skill_id in skills:
		for level in range(1, max_gate + 1):
			_set_level(tm, skill_id, level)
			for rec in records:
				if rec[0] != skill_id:
					continue
				assert_eq(tm.engine.is_unlocked(tm.state, rec[2]), int(rec[1]) <= level,
					"%s at %s level %d: unlocked == (gate %d <= level)" % [rec[2], skill_id, level, rec[1]])
	# One denial wording check on the engine path (CLEARANCE grammar).
	_set_level(tm, "scavenging", 4)
	var refused: Dictionary = tm.start_activity("strip_wreck")
	assert_false(refused["ok"], "gated start refused one level early")
	assert_string_contains(str(refused["reason"]), "CLEARANCE 5", "refusal carries clearance wording")


func test_c2_monster_gates_flip_at_data_levels() -> void:
	var tm: Variant = _make_tm(SEED)
	var lib: ContentLibrary = tm.engine.lib
	var max_gate := 1
	for id in lib.monsters:
		max_gate = maxi(max_gate, int((lib.monsters[id] as MonsterDef).level_gate))
	for level in range(1, max_gate + 1):
		_set_level(tm, "wasteland_combat", level)
		for id in lib.monsters:
			var mdef: MonsterDef = lib.monsters[id]
			var engaged: Dictionary = tm.engage_monster(id)
			assert_eq(bool(engaged["ok"]), level >= mdef.level_gate,
				"%s at combat level %d: engageable == (gate %d <= level)" % [id, level, mdef.level_gate])
			if bool(engaged["ok"]):
				tm.stop_combat()
	_set_level(tm, "wasteland_combat", 13)
	var boss_refusal: Dictionary = tm.engage_monster("sewer_landlord")
	assert_false(boss_refusal["ok"], "boss refuses one level early")
	assert_string_contains(str(boss_refusal["reason"]), "CLEARANCE 14", "boss refusal carries clearance wording")


func test_c2_shop_stock_gates_flip_at_data_levels() -> void:
	var tm: Variant = _make_tm(SEED)
	var lib: ContentLibrary = tm.engine.lib
	var max_gate := 1
	for entry in lib.shop_entries():
		if entry.is_gated():
			max_gate = maxi(max_gate, entry.gate_level)
	for level in range(1, max_gate + 1):
		for skill_id in lib.skills:
			_set_level(tm, skill_id, level)
		tm.state.add_crowns(maxi(0, 100_000 - tm.state.crowns))
		for entry in lib.shop_entries():
			var expected := (not entry.is_gated()) or level >= entry.gate_level
			assert_eq(tm.depot_max_affordable(entry.item) > 0, expected,
				"%s at all-skills %d: stocked == (gate <= level)" % [entry.item, level])
			var bought: Dictionary = tm.depot_buy(entry.item, 1)
			assert_eq(bool(bought["ok"]), expected, "buy flips with the gate")
			if expected:
				assert_eq(int(bought["crowns"]), entry.buy_price, "exact buy price tendered")
				assert_eq(int(tm.state.inventory.get(entry.item, 0)) >= 1, true, "unit stocked")
	_set_level(tm, "scavenging", 2)
	_set_level(tm, "foraging", 1)
	_set_level(tm, "wasteland_combat", 1)
	_set_level(tm, "cooking", 1)
	_set_level(tm, "junksmithing", 1)
	var gated: Dictionary = tm.depot_buy("scrap_metal", 1)
	assert_false(gated["ok"], "gated stock line refuses below its gate")
	assert_string_contains(str(gated["reason"]), "CLEARANCE 3", "shop refusal carries clearance wording")


func test_c2_ui_gate_plate_flips_on_the_patrol_surface() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(1)
	var docket := c.docket_controller("wasteland_patrol") as DocketPatrol
	var boss: DocketPatrol.FaunaCard = docket.get("_cards")["sewer_landlord"]
	assert_true(boss.gate_plate.visible, "boss posts its clearance plate at level 1")
	assert_string_contains(boss.gate_text.text, "CLEARANCE 14 REQUIRED", "plate names the grade")

	_set_level(tm, "wasteland_combat", 13)
	_flush(tm, ["combat"])
	await wait_frames(1)
	assert_true(boss.gate_plate.visible, "still locked one level early (13)")

	_set_level(tm, "wasteland_combat", 14)
	_flush(tm, ["combat"])
	await wait_frames(1)
	assert_false(boss.gate_plate.visible, "CLEARANCE 14 opens at level 14 — UI flips with the engine")
	(boss.button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "boss engages through the card at the open gate")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# C3 — combat criteria
# ---------------------------------------------------------------------------

func test_c3_equipment_changes_derived_stats_engine_and_patrol_panel() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(1)
	var docket := c.docket_controller("wasteland_patrol") as DocketPatrol

	# Engine: derived stats move with equipment, value for value, against an
	# expectation computed FROM the equipment records (not literals).
	var bare: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(bare, {"max_hp": 100, "speed": 3000, "accuracy": 30, "evasion": 10,
		"min_hit": 1, "max_hit": 4}, "bare chassis")

	tm.state.add_item("scrap_shiv", 1)
	tm.state.add_item("hubcap_vest", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "equip mid weapon")
	var one: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(int(one["max_hit"]), 4 + _eq_bonus(tm, "scrap_shiv", "max_hit_bonus"),
		"weapon max-hit bonus applies")
	assert_eq(int(one["speed"]), _eq_speed(tm, "scrap_shiv"), "weapon speed REPLACES the base")
	await wait_frames(1)
	assert_eq(docket.stats_line.text, "ACCURACY %d · EVADE %d · MAX HIT %d-%d · SWING EVERY %s S · CONDITION %d" % [
			int(one["accuracy"]), int(one["evasion"]), int(one["min_hit"]), int(one["max_hit"]),
			SignageFmt.seconds(int(one["speed"])), int(one["max_hp"])],
		"UI stats panel derives from equipped gear through the batched signal")

	assert_true(tm.equip_item("hubcap_vest")["ok"], "equip mid armor")
	var mid: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(int(mid["max_hp"]), 100 + _eq_bonus(tm, "hubcap_vest", "max_hp_bonus"),
		"armor HP bonus applies")
	assert_eq(int(mid["evasion"]), 10 + _eq_bonus(tm, "hubcap_vest", "evasion_bonus"),
		"armor evasion bonus applies")
	await wait_frames(1)
	assert_string_contains(docket.stats_line.text, "CONDITION 120", "panel re-derives on the armor swap")

	assert_true(tm.unequip_slot("weapon")["ok"], "unequip")
	assert_true(tm.unequip_slot("armor")["ok"], "unequip")
	var back: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(back, bare, "slots emptied -> chassis restored exactly")
	assert_eq(tm.state.item_count("scrap_shiv"), 1, "gear returned to the Manifest")
	assert_eq(tm.state.item_count("hubcap_vest"), 1, "gear returned to the Manifest")


func test_c3_patrol_swap_rebaselines_swing_attribution() -> void:
	# T10b verifier corner, fixed at T13: a mid-fight weapon swap must RESET
	# the swing-attribution baseline — the pendings÷speed division is only
	# sound over a constant-speed window. (With today's constants the drifted
	# window could only ever under-count to zero — a swallowed line, never a
	# wrong number — so this pins the structural fix, not a live miscount:
	# the snapshot now records the gear, and any swap re-baselines instead of
	# diffing across the speed change.)
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(1)
	var docket := c.docket_controller("wasteland_patrol") as DocketPatrol

	_set_level(tm, "wasteland_combat", 4)  # Dust Bunny gate (42 HP: survives the window)
	tm.state.add_item("scrap_shiv", 1)
	(docket.get("_cards")["greater_dust_bunny"].button as Button).pressed.emit()
	assert_eq(int(tm.state.combat["p_next_ms"]), 3_000, "bare first swing at 3.0 s")
	_pump(tm, 1_000, 300)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "mid-fight weapon swap (3.0 s -> 2.6 s swing)")
	await wait_frames(1)
	var snap: Dictionary = docket.get("_snap")
	assert_eq(str(snap.get("weapon", "<missing>")), "scrap_shiv",
		"the swap flush re-baselined the snapshot onto the new weapon")
	assert_eq(str(snap.get("phase", "")), "fighting", "same fight keeps diffing after the re-baseline")

	# The post-swap window stamps EXACTLY the swings that resolved in it —
	# counted from the engine's pendings, all at the new constant speed (one
	# line per swing at the 4 Hz flush cadence; ×N when swings batch).
	var lines_before: int = docket.log.item_count
	var p_next0: int = int(tm.state.combat["p_next_ms"])
	_pump(tm, 6_000, 300)
	tm.batcher.force_flush(tm.sim_time_ms)
	await wait_frames(1)
	assert_eq(str(tm.state.combat["phase"]), "fighting", "fauna still standing (window valid)")
	var resolved: int = (int(tm.state.combat["p_next_ms"]) - p_next0) / 2_600
	var stamped := 0
	for i in range(lines_before, docket.log.item_count):
		var line := docket.log.get_item_text(i)
		if not line.begins_with("RESIDENT »"):
			continue
		stamped += 1
		if "×" in line:
			stamped += int(line.split("×")[1].split(" ")[0]) - 1
	assert_between(resolved, 1, 3, "swings resolved in the window (pendings delta / new speed)")
	assert_eq(stamped, resolved,
		"stamped swing lines account for EXACTLY the resolved swings (no drift across the swap)")


func _eq_bonus(tm: Variant, item_id: String, field: String) -> int:
	return int(tm.engine.lib.equipment_for(item_id).get(field))


func _eq_speed(tm: Variant, item_id: String) -> int:
	return int(tm.engine.lib.equipment_for(item_id).attack_speed_ms)


func test_c3_food_auto_eats_from_the_manifest() -> void:
	var tm: Variant = _make_tm(SEED)
	var st: PlayerState = tm.state
	_set_level(tm, "wasteland_combat", 10)
	for pair in [["scrap_shiv", 1], ["hubcap_vest", 1], ["mandatory_grits", 5], ["vintage_snack_cake", 2]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("scrap_shiv")["ok"])
	assert_true(tm.equip_item("hubcap_vest")["ok"], "mid loadout (max condition 120)")
	assert_true(tm.engage_monster("feral_snack_dispenser")["ok"], "engage the Dispenser")

	# Sample the fight: condition never exceeds the derived cap (heals clamp)
	# and eats actually happen while below half.
	var cap := int(tm.combat.derived_stats(st)["max_hp"])
	var ate := false
	var fed := 0
	while fed < 250_000 and str(st.combat["phase"]) == "fighting":
		tm.advance_wall_ms(1_000)
		fed += 1_000
		assert_true(int(st.combat["p_hp"]) <= cap, "condition never exceeds the cap (heals clamp)")
		if int(st.combat["eaten_total"]) > 0:
			ate = true
	assert_true(ate, "auto-eat engaged during the fight")
	assert_ne(str(st.combat["phase"]), "fighting", "the fight resolved within the window")
	var eaten: int = int(st.combat["eaten_total"])
	assert_gt(eaten, 0, "rations consumed")
	assert_eq(int(st.inventory.get("mandatory_grits", 0)) + int(st.inventory.get("vintage_snack_cake", 0)),
		7 - eaten, "Manifest decremented by EXACTLY the rations eaten")


func test_c3_death_stops_combat_with_zero_loss() -> void:
	var tm: Variant = _make_tm(SEED)
	var st: PlayerState = tm.state
	_set_level(tm, "wasteland_combat", 14)
	for pair in [["scrap_shiv", 1], ["hubcap_vest", 1]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("scrap_shiv")["ok"])
	assert_true(tm.equip_item("hubcap_vest")["ok"])
	assert_true(st.inventory.is_empty(), "empty Hands (food-free zero-loss proof)")
	var xp_before := st.skills_xp.duplicate()
	var ends: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss under-geared")
	_pump(tm, 120_000, 2_500)

	assert_eq(str(st.combat["phase"]), "dead", "death stops combat (RETURN TO SHELTER)")
	assert_eq(ends.size(), 1, "combat_ended fired exactly once")
	assert_eq(st.skills_xp, xp_before, "ZERO xp lost")
	assert_true(st.inventory.is_empty(), "ZERO items lost")
	assert_eq(st.crowns, 0, "wallet untouched")
	var m_hp_frozen := int(st.combat["m_hp"])
	_pump(tm, 30_000, 2_500)
	assert_eq(str(st.combat["phase"]), "dead", "the halt is real: still dead")
	assert_eq(int(st.combat["m_hp"]), m_hp_frozen, "fauna HP frozen after death")
	assert_eq(ends.size(), 1, "no second combat_ended")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the resident can go straight back out")


func test_c3_boss_beatable_with_slice_crafted_gear_and_food() -> void:
	# Journey 2 acceptance: the winning kit is produced by the slice's OWN
	# production chain (Junksmithing forges the gear, Cooking simmers the
	# rations), then equips and clears the zone.
	var tm: Variant = _make_tm(SEED)
	var st: PlayerState = tm.state
	_set_level(tm, "junksmithing", 15)
	_set_level(tm, "cooking", 15)
	_set_level(tm, "wasteland_combat", 14)
	var stopped: Array = []
	tm.activity_stopped.connect(func(_s: String, _c: String, reason: String) -> void:
		stopped.append(reason))

	# Exact single-craft input stock (upstream gathering's produce).
	for pair in [["scrap_ingot", 3], ["compliant_wire", 2], ["girderling", 3],
			["patchwork_bolt", 2], ["lint_pelt", 2], ["roach_meat", 20],
			["iodine_root", 10], ["duskcorn", 10]]:
		st.add_item(pair[0], pair[1])
	var smith0: int = int(st.skills_xp["junksmithing"])
	var cook0: int = int(st.skills_xp["cooking"])

	assert_true(tm.start_activity("forge_majority_whip")["ok"], "forge the whip")
	_pump(tm, 16_500, 2_500)  # craft at 8 s; the 16 s action finds no inputs
	assert_eq(st.item_count("majority_whip"), 1, "Majority Whip CRAFTED through the recipe")
	assert_true(not st.active.has("junksmithing"), "dry recipe slot stopped honestly")
	assert_eq(int(st.skills_xp["junksmithing"]), smith0 + 160, "craft xp through the shared pipeline")

	assert_true(tm.start_activity("press_carpool_carapace")["ok"], "press the carapace")
	_pump(tm, 18_500, 2_500)
	assert_eq(st.item_count("carpool_carapace"), 1, "Carpool Carapace CRAFTED")
	assert_eq(int(st.skills_xp["junksmithing"]), smith0 + 160 + 180, "second craft xp")

	assert_true(tm.start_activity("simmer_chefs_regret")["ok"], "simmer the rations")
	_pump(tm, 77_500, 2_500)  # 10 crafts at 7 s; the 11th runs dry
	assert_eq(st.item_count("radstag_stew"), 10, "10 Radstag Stews COOKED")
	assert_eq(int(st.skills_xp["cooking"]), cook0 + 10 * 60, "cooking xp for 10 crafts")
	assert_true(stopped.has("inputs_exhausted"), "dry stops recorded along the chain")
	for leftover in [["scrap_ingot", 0], ["compliant_wire", 0], ["girderling", 0],
			["patchwork_bolt", 0], ["lint_pelt", 0], ["roach_meat", 0],
			["iodine_root", 0], ["duskcorn", 0]]:
		assert_eq(st.item_count(leftover[0]), leftover[1],
			"craft chain consumed its inputs exactly (%s)" % leftover[0])

	# Equip the crafted kit and clear the zone with it.
	assert_true(tm.equip_item("majority_whip")["ok"], "equip the crafted whip")
	assert_true(tm.equip_item("carpool_carapace")["ok"], "equip the crafted carapace")
	var max_row: Dictionary = tm.combat.derived_stats(st)
	assert_eq(int(max_row["max_hit"]), 18, "crafted kit derives the max loadout (max hit 18)")
	assert_eq(int(max_row["speed"]), 2_000, "whip swing 2.0 s")
	assert_eq(int(max_row["max_hp"]), 150, "carapace condition 150")

	var cleared: Array = []
	tm.zone_cleared.connect(func(monster_id: String) -> void: cleared.append(monster_id))
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "engage the boss with the slice kit")
	var guard := 0
	while str(st.combat["phase"]) == "fighting" and guard < 300_000:
		tm.advance_wall_ms(2_500)
		guard += 2_500
	assert_eq(str(st.combat["phase"]), "victory", "ZONE BOSS CLEARED with slice-crafted gear + food")
	assert_eq(cleared, ["sewer_landlord"], "the win moment fired once")
	assert_true(bool(st.combat["zone_clear"]), "zone clear persists in state")
	assert_true(int(st.combat["eaten_total"]) >= 1, "the crafted rations carried the fight (auto-eaten)")
	assert_true(st.item_count("radstag_stew") < 10, "some stews consumed")
	assert_true(not st.inventory.is_empty(), "the boss's claims filed to the Manifest")


# ---------------------------------------------------------------------------
# C4 — save round-trip + offline exactness + clock regression
# ---------------------------------------------------------------------------

func test_c4_quit_relaunch_round_trip_through_the_real_save_file() -> void:
	var dir := _tmp_dir("roundtrip")
	var tm1: Variant = _make_tm(SEED)
	var st1: PlayerState = tm1.state
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"])
	_set_level(tm1, "wasteland_combat", 10)
	for pair in [["scrap_shiv", 1], ["hubcap_vest", 1]]:
		st1.add_item(pair[0], pair[1])
	assert_true(tm1.equip_item("scrap_shiv")["ok"])
	assert_true(tm1.equip_item("hubcap_vest")["ok"])
	assert_true(tm1.engage_monster("feral_snack_dispenser")["ok"], "a live fight at quit time")
	st1.add_crowns(777)
	_pump(tm1, 30_000, 1_000)
	assert_eq(str(st1.combat["phase"]), "fighting", "saved mid-fight")

	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store._boot(dir, tm1, NOW)
	assert_true(store.save_now(NOW + 30_000)["ok"], "CLOCK OUT files the record")

	# RELAUNCH: a fresh engine + store at the same wall moment (zero gap).
	var tm2: Variant = _make_tm(SEED)
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 30_000)
	assert_eq(String(store2.load_report["loaded_from"]), "save.json", "loaded from the primary")
	assert_eq(store2.notice, {}, "clean load, no notice")
	assert_eq(tm2.state.to_dict(), st1.to_dict(),
		"relaunched state deep-equal through the REAL file medium (xp/inventory/wallet/slots/fight)")

	# The resumed fight plays out identically to the never-quit twin.
	var ends1: Array = []
	var ends2: Array = []
	tm1.combat_ended.connect(func(result: Dictionary) -> void: ends1.append(result))
	tm2.combat_ended.connect(func(result: Dictionary) -> void: ends2.append(result))
	_pump(tm1, 200_000, 2_500)
	_pump(tm2, 200_000, 2_500)
	assert_eq(ends2.size(), 1, "relaunched fight ended")
	assert_eq(ends2[0], ends1[0], "identical outcome/payload/duration as the uninterrupted twin")
	assert_eq(tm2.state.to_dict(), tm1.state.to_dict(), "identical final states")


func test_c4_offline_gains_full_rate_zero_drift_all_slots_plus_combat() -> void:
	const GAP := 30_000  # below the 38 s mathematical minimum boss kill: mid-fight for certain

	# Config: gathering + processing (stockpile-fed) + a survivable boss fight.
	var boot_slots := func(tm: Variant) -> void:
		var st: PlayerState = tm.state
		_set_level(tm, "wasteland_combat", 14)
		st.add_item("scrap_metal", 500)  # smelting stockpile (inventory-independent)
		for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", 6]]:
			st.add_item(pair[0], pair[1])
		assert_true(tm.equip_item("majority_whip")["ok"])
		assert_true(tm.equip_item("carpool_carapace")["ok"])
		assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
		assert_true(tm.start_activity("smelt_scrap_ingot")["ok"])
		assert_true(tm.engage_monster("sewer_landlord")["ok"])

	# LIVE twin: every tick played through the funnel.
	var live: Variant = _make_tm(SEED)
	boot_slots.call(live)
	_pump(live, GAP, TICK_MS)

	# OFFLINE twin: the same 30 s as one away gap (closed form + combat replay).
	var off: Variant = _make_tm(SEED)
	boot_slots.call(off)
	var payload: Dictionary = off.apply_offline_elapsed(GAP)

	# Zero drift: FULL-RATE gains equal the live twin exactly.
	assert_eq(off.state.skills_xp, live.state.skills_xp, "xp: offline == live (full rate, zero drift)")
	assert_eq(off.state.inventory, live.state.inventory, "inventory: offline == live")
	var cl: Dictionary = live.state.combat
	var co: Dictionary = off.state.combat
	assert_eq(str(co["phase"]), str(cl["phase"]), "fight resumed mid-fight")
	assert_eq(int(co["p_hp"]), int(cl["p_hp"]), "same condition")
	assert_eq(int(co["m_hp"]), int(cl["m_hp"]), "same fauna HP")
	assert_eq(int(co["eaten_total"]), int(cl["eaten_total"]), "same rations auto-eaten")
	assert_eq(String(co["rng_state"]), String(cl["rng_state"]), "stream at the exact same position")
	assert_eq(int(co["p_next_ms"]) + GAP, int(cl["p_next_ms"]), "wind-up phase preserved (anchor rewind)")

	# Full-rate accounting: payload gains == elapsed x rates, exactly.
	assert_eq(int(payload["actions"]["foraging"]), 10, "30 s / 3 s = 10 foraging actions")
	assert_eq(int(payload["actions"]["junksmithing"]), 7, "30 s / 4 s = 7 crafts")
	assert_eq(int(payload["skills_xp"]["foraging"]), 100, "10 x 10 xp")
	assert_eq(int(payload["skills_xp"]["junksmithing"]), 7 * 14, "7 x 14 xp")
	assert_eq(int(payload["skills_xp"].get("wasteland_combat", 0)), 0, "no combat xp below the kill horizon")
	assert_eq(String(payload["combat"]["outcome"]), "resumed", "combat replayed survivably, still fighting")

	# Live continuation from the replayed state finishes identically.
	var ends_live: Array = []
	var ends_off: Array = []
	live.combat_ended.connect(func(result: Dictionary) -> void: ends_live.append(result))
	off.combat_ended.connect(func(result: Dictionary) -> void: ends_off.append(result))
	_pump(live, 400_000, 2_500)
	_pump(off, 400_000, 2_500)
	assert_eq(ends_off[0]["outcome"], ends_live[0]["outcome"], "same continuation outcome")
	assert_eq(int(ends_off[0]["ms"]) + GAP, int(ends_live[0]["ms"]), "same fight, clocks GAP apart")
	assert_eq(ends_off[0]["drops"], ends_live[0]["drops"], "same claims")


func test_c4_clock_regression_zero_gains_no_nan() -> void:
	var dir := _tmp_dir("backwards")
	var tm1: Variant = _make_tm(SEED)
	var st1: PlayerState = tm1.state
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_set_level(tm1, "wasteland_combat", 10)
	st1.add_item("scrap_shiv", 1)
	assert_true(tm1.equip_item("scrap_shiv")["ok"])
	assert_true(tm1.engage_monster("feral_snack_dispenser")["ok"])
	_pump(tm1, 10_000, 1_000)
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store._boot(dir, tm1, NOW)
	assert_true(store.save_now(NOW + 10_000)["ok"])

	# The wall clock went BACKWARDS past the anchor (sleep/clock skew).
	var tm2: Variant = _make_tm(SEED)
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	var mail_calls := {"n": 0}
	tm2.mail_call_ready.connect(func(_p: Dictionary) -> void: mail_calls["n"] += 1)
	store2._boot(dir, tm2, NOW - 60_000)
	assert_eq(int(tm2.state.last_mail_call.get("elapsed_ms", -1)), 0, "future-dated anchor -> zero elapsed")
	assert_eq(int(mail_calls["n"]), 0, "no MAIL CALL for a backwards clock")
	assert_eq(tm2.state.to_dict(), st1.to_dict(), "state byte-equal — nothing gained, nothing lost")

	# No NaN / no corruption: every numeric field loads as a sane int.
	for skill_id in tm2.state.skills_xp:
		assert_eq(typeof(tm2.state.skills_xp[skill_id]), TYPE_INT, "%s xp is int" % skill_id)
		assert_true(int(tm2.state.skills_xp[skill_id]) >= 0, "%s xp non-negative" % skill_id)
	for item_id in tm2.state.inventory:
		assert_true(int(tm2.state.inventory[item_id]) >= 0, "%s stack non-negative" % item_id)
	var c: Dictionary = tm2.state.combat
	for key in ["p_hp", "m_hp", "engage_ms", "p_next_ms", "m_next_ms", "eaten_total"]:
		assert_eq(typeof(c[key]), TYPE_INT, "combat.%s is int (no float/NaN survived JSON)" % key)
		assert_true(int(c[key]) >= 0, "combat.%s non-negative" % key)
	assert_eq(str(c["phase"]), "fighting", "the mid-fight save loads alive and intact")
	assert_true(int(c["p_hp"]) > 0, "condition positive")
	tm2.advance_wall_ms(2_800)
	assert_eq(str(c["phase"]), "fighting", "the loaded fight keeps ticking normally")


func test_c4_interval_boundary_and_split_offline_exact() -> void:
	# ADOPTED from the T6 verifier's scratch (/tmp/t6v_scratch_kept_copy.gd —
	# evidence in production-log.md T6): interval-minus-1 ms boundary live AND
	# offline, plus a SPLIT offline application (2999 + 1 ms) that must equal
	# one 3000 ms application — catches ceil/round truncation and phase-carry
	# double-count/loss across catch-up calls.
	const INTERVAL_MS := 3000

	# LIVE boundary: 2999 ms -> 0 actions; +1 ms -> exactly 1.
	var live: Variant = _make_tm(SEED)
	assert_true(live.start_activity("sort_scrap_pile")["ok"])
	var fed := 0
	while fed < INTERVAL_MS - 1:
		var step: int = mini(100, INTERVAL_MS - 1 - fed)
		live.advance_wall_ms(step)
		fed += step
	assert_eq(int(live.state.skills_xp["scavenging"]), 0, "LIVE 2999 ms: zero actions (floor, not ceil)")
	live.advance_wall_ms(1)
	assert_eq(int(live.state.skills_xp["scavenging"]), 10, "LIVE +1 ms: the boundary tick fires exactly one action")

	# OFFLINE boundary: 2999 ms gap -> 0 actions, state untouched.
	var off: Variant = _make_tm(SEED)
	assert_true(off.start_activity("sort_scrap_pile")["ok"])
	var p2999: Dictionary = off.apply_offline_elapsed(INTERVAL_MS - 1)
	assert_eq(int(p2999["actions"].get("scavenging", -1)), 0, "OFFLINE 2999 ms: zero actions")
	assert_true(p2999["items"].is_empty(), "no items from a sub-interval gap")
	assert_eq(int(off.state.active["scavenging"].anchor_ms), -(INTERVAL_MS - 1),
		"anchor rewound by exactly the gap")

	# SPLIT application: 2999 + 1 must equal a single 3000 (same twin).
	var p1: Dictionary = off.apply_offline_elapsed(1)
	assert_eq(int(p1["actions"].get("scavenging", -1)), 1, "the +1 ms completes exactly the first action")

	var single: Variant = _make_tm(SEED)
	assert_true(single.start_activity("sort_scrap_pile")["ok"])
	single.apply_offline_elapsed(INTERVAL_MS)
	assert_eq(single.state.inventory, off.state.inventory,
		"split (2999+1) and single (3000) gaps produce IDENTICAL stacks — no truncation, no double-count")
	assert_eq(single.state.skills_xp, off.state.skills_xp, "identical xp")
	assert_eq(int(single.state.active["scavenging"].anchor_ms),
		int(off.state.active["scavenging"].anchor_ms), "identical anchors")


func test_c4_offline_stream_matches_independent_oracle_ten_thousand_rolls() -> void:
	# ADOPTED from the T6 verifier's scratch: a 10,000-action offline catch-up
	# vs an INDEPENDENT oracle that replays the documented RNG contract (FNV
	# stream seed, pick-then-qty draw order, entry order) from scratch — and
	# proves catch-up is closed form (30,000,000 ms gap, ZERO sim ticks).
	const ACTIONS := 10_000
	const GAP_MS := ACTIONS * 3000

	var tm: Variant = _make_tm(SEED)
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
	var slot_seed: int = tm.state.active["foraging"].rng_seed
	assert_false(tm.state.active["foraging"].stream_started, "stream not yet positioned at capture")

	var payload: Dictionary = tm.apply_offline_elapsed(GAP_MS)
	assert_eq(int(payload["actions"].get("foraging", -1)), ACTIONS, "exactly 10,000 actions closed-form")
	assert_eq(int(tm.stats["ticks_executed"]), 0, "CLOSED FORM: a 30,000,000 ms gap runs ZERO sim ticks")

	# Independent oracle: pick <= 80 -> glowshroom qty 1-2; else duskcorn 1.
	var oracle := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = slot_seed
	for i in ACTIONS:
		var pick := rng.randi_range(1, 100)
		var item := "duskcorn"
		var qty := 1
		if pick <= 80:
			item = "glowshroom"
			qty = rng.randi_range(1, 2)
		oracle[item] = int(oracle.get(item, 0)) + qty
	assert_eq(tm.state.inventory, oracle,
		"10,000 seeded rolls land EXACTLY on the independently replayed sums")


func test_c4_offline_recall_ms_equals_live_death_blow() -> void:
	# The T7 ruling's exact pin (carried by the T7 verifier as a scratch-only
	# literal): the offline survivability bound recalls the patrol at EXACTLY
	# the instant the live twin's killing blow landed — same seed, same config.
	var mid_boss := func(seed: int) -> Variant:
		var tm: Variant = _make_tm(seed)
		var st: PlayerState = tm.state
		_set_level(tm, "wasteland_combat", 14)
		st.add_item("scrap_shiv", 1)
		st.add_item("hubcap_vest", 1)
		assert_true(tm.equip_item("scrap_shiv")["ok"])
		assert_true(tm.equip_item("hubcap_vest")["ok"])
		assert_true(tm.engage_monster("sewer_landlord")["ok"], "mid gear, food-free vs the boss")
		return tm

	# LIVE twin: plays to its death and records the blow's sim instant.
	var live: Variant = mid_boss.call(SEED)
	var ends: Array = []
	live.combat_ended.connect(func(result: Dictionary) -> void: ends.append(result))
	_pump(live, 200_000, 2_500)
	assert_eq(str(live.state.combat["phase"]), "dead", "live twin died")
	var death_ms: int = int(ends[0]["ms"])

	# OFFLINE twin: an away gap covering the same instant recalls instead.
	var off: Variant = mid_boss.call(SEED)
	var payload: Dictionary = off.apply_offline_elapsed(death_ms + 60_000)
	assert_eq(str(off.state.combat["phase"]), "recalled", "recalled (never dead) offline")
	assert_true(int(off.state.combat["p_hp"]) > 0, "alive at pre-blow condition")
	assert_eq(int(payload["combat"].get("recalled_at_ms", -1)), death_ms,
		"recalled_at_ms == the LIVE twin's death-blow ms, EXACTLY (seed %d: %d ms)" % [SEED, death_ms])
	assert_eq(int(payload["combat"]["kills"]), 0, "no kills")
	assert_eq(String(payload["combat"]["notice"]), "PATROL RECALLED", "notice posted")


# ---------------------------------------------------------------------------
# C5 — shop integrity
# ---------------------------------------------------------------------------

func test_c5_shop_buy_sell_updates_currency_and_inventory_exactly() -> void:
	var tm: Variant = _make_tm(SEED)
	var lib: ContentLibrary = tm.engine.lib

	# Data sweep: every stocked line prices above its one honest sell value
	# (the Depot never buys back at or above its own sell price).
	for entry in lib.shop_entries():
		assert_gt(entry.buy_price, lib.item(entry.item).value,
			"%s: buy (%d) > sell (%d) — the spread holds" % [entry.item, entry.buy_price, lib.item(entry.item).value])

	var st: PlayerState = tm.state
	st.add_crowns(100)
	var value: int = lib.item("glowshroom").value
	var price: int = lib.shop_entries().filter(func(e: ShopEntryDef) -> bool: return e.item == "glowshroom")[0].buy_price

	var bought: Dictionary = tm.depot_buy("glowshroom", 3)
	assert_true(bought["ok"], "buy 3")
	assert_eq(st.crowns, 100 - 3 * price, "currency decremented by EXACTLY buy_price x qty")
	assert_eq(st.item_count("glowshroom"), 3, "inventory incremented by exactly qty")

	var sold: Dictionary = tm.depot_sell("glowshroom", 2)
	assert_true(sold["ok"], "sell 2")
	assert_eq(int(sold["crowns"]), 2 * value, "paid EXACTLY ItemDef.value per unit")
	assert_eq(st.crowns, 100 - 3 * price + 2 * value, "wallet arithmetic exact")
	assert_eq(st.item_count("glowshroom"), 1, "partial sell leaves the remainder")

	var over: Dictionary = tm.depot_sell("glowshroom", 5)
	assert_eq(int(over["qty"]), 1, "over-sell tenders only the stack on hand")
	assert_eq(st.item_count("glowshroom"), 0, "stack emptied")
	assert_eq(st.crowns, 100 - 3 * price + 3 * value, "final wallet exact")
	assert_false(tm.depot_sell("glowshroom", 1)["ok"], "nothing left to sell")

	assert_false(tm.depot_buy("vintage_snack_cake", 1)["ok"], "not-stocked items refuse")
	assert_false(tm.depot_buy("glowshroom", 0)["ok"], "qty < 1 refuses")
	assert_false(tm.depot_buy("glowshroom", 10_000)["ok"], "over-draft refuses")
	assert_eq(st.crowns, 100 - 3 * price + 3 * value, "refusals move nothing")


func test_c5_depot_ui_wallet_and_manifest_ride_the_batched_region() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("requisition_depot", true)
	await wait_frames(1)
	var docket := c.docket_controller("requisition_depot") as DocketDepot

	tm.state.add_crowns(100)
	_flush(tm)
	await wait_frames(1)
	assert_eq(docket.crowns_read.text, "100", "wallet plate reads the state")

	# T10a verifier carry, verified: crowns ride the INVENTORY bulk region —
	# a Depot transaction flushes exactly that region and the wallet plate
	# updates through it (no per-frame polling, no dedicated crowns signal).
	var regions: Array = []
	tm.bulk_state_changed.connect(func(changes: Dictionary) -> void: regions.append(changes.duplicate()))
	(docket.find_child("Buy1_glowshroom", true, false) as Button).pressed.emit()
	assert_eq(tm.state.crowns, 94, "UI buy tenders through the façade")
	assert_eq(docket.crowns_read.text, "94", "wallet plate updated via the batched signal")
	assert_true(regions.size() >= 1, "a flush arrived")
	assert_true(regions[regions.size() - 1].has("inventory"),
		"the flush carries the inventory region (crowns ride it)")

	# The Manifest surface agrees.
	c.select_department("manifest", true)
	await wait_frames(1)
	var manifest := c.docket_controller("manifest") as DocketManifest
	var glow_name: String = tm.engine.lib.item("glowshroom").name.to_upper()
	var rows := ""
	for i in manifest.list.item_count:
		rows += manifest.list.get_item_text(i) + " | "
	assert_string_contains(rows, "%s ×1" % glow_name, "the bought unit is on the Manifest")

	# Sell it all back through the UI; wallet + row both update.
	c.select_department("requisition_depot", true)
	await wait_frames(1)
	(docket.find_child("SellAll_glowshroom", true, false) as Button).pressed.emit()
	assert_eq(tm.state.crowns, 96, "sell-all pays value x 1")
	assert_eq(docket.crowns_read.text, "96", "wallet plate settles")


# ---------------------------------------------------------------------------
# C6 — headless composite signal budget (windowed frame report: probe_perf.gd)
# ---------------------------------------------------------------------------

func test_c6_headless_composite_signal_budget_worst_case() -> void:
	# All five slots hot at once (both gathering tiers, both processing chains
	# on deep stockpiles, live boss combat) — the same worst case the windowed
	# perf probe measures. Bulk emissions stay under the 4 Hz ceiling.
	var tm: Variant = _make_tm(SEED)
	var st: PlayerState = tm.state
	_set_level(tm, "wasteland_combat", 14)
	st.add_item("scrap_metal", 10_000_000)
	st.add_item("duskcorn", 10_000_000)
	for pair in [["majority_whip", 1], ["carpool_carapace", 1], ["radstag_stew", 50]]:
		st.add_item(pair[0], pair[1])
	assert_true(tm.equip_item("majority_whip")["ok"])
	assert_true(tm.equip_item("carpool_carapace")["ok"])
	for content_id in ["sort_scrap_pile", "walk_the_glow_rows", "smelt_scrap_ingot", "grind_mandatory_grits"]:
		assert_true(tm.start_activity(content_id)["ok"], "slot starts: %s" % content_id)
	var ends: Array = []
	tm.combat_ended.connect(func(_result: Dictionary) -> void: ends.append(1))
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "patrol engaged")

	var bulk := {"n": 0}
	tm.bulk_state_changed.connect(func(_changes: Dictionary) -> void: bulk["n"] += 1)
	var force_flushes := 7  # 2 equips + 4 starts + engage
	_pump(tm, 60_000, 1_000)
	var ceiling := 4 * 60 + force_flushes + ends.size()  # gate-limited 4 Hz + user-action force flushes
	assert_true(int(bulk["n"]) <= ceiling,
		"composite worst case: bulk emissions %d within budget (%d)" % [int(bulk["n"]), ceiling])
	assert_true(int(bulk["n"]) >= 2, "the bulk signal does flow while everything runs")
	assert_eq(int(tm.stats["clamped_stalls"]), 0, "no stall clamps at healthy frame pacing")


# ---------------------------------------------------------------------------
# T9 — swell-tween fix pin (carried from the T10a verification)
# ---------------------------------------------------------------------------

func test_t9_repeated_animated_selections_stay_stable() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var swell_target := Vector2.ONE * Concourse.SWELL

	# Direct plate-state cycling: a VALID running swell tween is killed by the
	# next state change (the fixed is_valid/kill path), and a FINISHED (freed)
	# tween's stale meta is cleared without touching the freed instance.
	var plate: Button = c.plates()["foraging"]
	c._set_plate_state(plate, true, true)
	await get_tree().create_timer(0.05).timeout  # tween still valid
	c._set_plate_state(plate, false, false)
	assert_false(plate.has_meta("swell_tween"), "valid tween killed and meta cleared")
	assert_eq(plate.scale, Vector2.ONE, "scale restored")
	c._set_plate_state(plate, true, true)
	await get_tree().create_timer(0.30).timeout  # tween finished + auto-freed, meta stale
	c._set_plate_state(plate, false, false)
	assert_false(plate.has_meta("swell_tween"), "STALE meta cleared without a freed-instance error")
	assert_eq(plate.scale, Vector2.ONE, "scale restored after the stale path")

	# Selection-level cycling: repeated animated selections, each completing
	# and leaving a stale swell meta, then re-selected — stable every time.
	for i in 5:
		c.select_department("wasteland_patrol", false)  # animated (shutter + swell)
		await get_tree().create_timer(0.75).timeout  # transition (0.58 s) + swell (0.22 s) complete
		c.select_department("scavenging", true)  # instant: de-energize through the stale path
		var active: Button = c.plates()["scavenging"]
		assert_false(active.has_meta("swell_tween"), "cycle %d: no swell meta survives an instant select" % i)
		assert_true((active.scale - swell_target).length() < 0.01, "cycle %d: active plate swelled" % i)
	assert_eq(c.active_department(), "scavenging")
	assert_false(c.is_transitioning(), "no transition left in flight")
	for id in c.plates():
		if id != "scavenging":
			assert_eq((c.plates()[id] as Button).scale, Vector2.ONE,
				"%s rests at 1.0 (no tween leakage)" % id)
