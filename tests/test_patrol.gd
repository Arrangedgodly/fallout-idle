extends GutTest
## tests/test_patrol.gd — T10b Wasteland Patrol docket wiring (Theme/UI lane).
##
## Instantiates the real concourse bound to a fresh TickManager twin (never in
## the tree; advance_wall_ms is the only clock input — same discipline as
## test_dockets.gd) and drives the REAL combat engine through the real façade
## and card/button presses, then asserts the rendered widgets agree with
## engine state: HP gauges equal state.combat after signal-driven flushes,
## stamped battle lines account exactly for damage/meals/claims, phase plates
## render distinctly per phase (fighting / deceased / victory / recalled), the
## ZONE SECURED plate appears once and persists through a save round-trip,
## the stats panel derives from equipped gear, and keyboard traversal covers
## the new focusables. No polling anywhere — updates flow only through the
## batched/discrete signal contract (the freeze-when-unbound test pins it).


const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260915


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (patrol tests run on live data)")
	return result.library


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


## Feed exactly `total_ms` through the public wall funnel in sub-budget chunks.
func _pump(tm: Variant, total_ms: int, chunk_ms := 500) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


## Pump until state.combat.phase equals `phase` (or the budget runs out).
func _pump_until_phase(tm: Variant, phase: String, budget_ms: int, chunk_ms := 500) -> bool:
	var fed := 0
	while fed < budget_ms:
		if str(tm.state.combat.get("phase", "")) == phase:
			return true
		var step := mini(chunk_ms, budget_ms - fed)
		tm.advance_wall_ms(step)
		fed += step
	return str(tm.state.combat.get("phase", "")) == phase


## Mark a region + force flush (twin of an engine-side mutation when a test
## seeds inventory/XP directly through state).
func _flush(tm: Variant, region := "inventory") -> void:
	tm.batcher.mark(region)
	tm.batcher.force_flush(tm.sim_time_ms)


func _make_concourse(tm: Variant) -> Concourse:
	var c := ConcourseScene.instantiate() as Concourse
	assert_not_null(c, "concourse scene instantiates")
	add_child_autofree(c)
	c.bind_engines(tm)
	await wait_frames(2)
	return c


func _make_patrol(tm: Variant) -> Array:
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(1)
	var docket := c.docket_controller("wasteland_patrol") as DocketPatrol
	assert_not_null(docket, "patrol controller mounted")
	return [c, docket]


func _cards(docket: DocketPatrol) -> Dictionary:
	return docket.get("_cards")


func _log_has(docket: DocketPatrol, needle: String) -> bool:
	for i in docket.log.item_count:
		if needle in docket.log.get_item_text(i):
			return true
	return false


func _log_count(docket: DocketPatrol, needle: String) -> int:
	var n := 0
	for i in docket.log.item_count:
		if needle in docket.log.get_item_text(i):
			n += 1
	return n


## Sum the DAMAGE numbers on lines beginning with `attacker` (mono, grouped).
func _sum_logged_damage(docket: DocketPatrol, attacker: String) -> int:
	var total := 0
	for i in docket.log.item_count:
		var t := docket.log.get_item_text(i)
		if not t.begins_with(attacker):
			continue
		var dmg_part := t.get_slice(" · ", t.get_slice_count(" · ") - 1)
		if dmg_part.ends_with(" DAMAGE"):
			total += int(dmg_part.trim_suffix(" DAMAGE").replace(",", ""))
	return total


## Sum the ×n units on RATION CONSUMED stamps for one food's display name.
func _sum_logged_rations(docket: DocketPatrol, display: String) -> int:
	var total := 0
	for i in docket.log.item_count:
		var t := docket.log.get_item_text(i)
		if not t.begins_with("RATION CONSUMED · " + display):
			continue
		for token in t.split(" "):
			if token.begins_with("×"):
				total += int(token.trim_prefix("×"))
				break
	return total


# ---------------------------------------------------------------------------
# fauna posting cards (honest math from data)
# ---------------------------------------------------------------------------

func test_patrol_cards_match_content() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]
	var cards := _cards(docket)
	assert_eq(cards.size(), 5, "five fauna cards from data (4 monsters + boss)")

	# Stats visible and exact: the engine's own numbers, in mono.
	var litter: DocketPatrol.FaunaCard = cards["junkyard_roach"]
	assert_string_contains(litter.stats_line.text, "HP 18")
	assert_string_contains(litter.stats_line.text, "ACC 15")
	assert_string_contains(litter.stats_line.text, "EVA 4")
	assert_string_contains(litter.stats_line.text, "HIT 0-2")
	assert_string_contains(litter.stats_line.text, "EVERY 2.8 S")
	assert_string_contains(litter.stats_line.text, "25 XP ON KILL")

	# Drop table with exact rates (one decimal only when needed).
	assert_string_contains(litter.drops_line.text, "CLAIMS: GRADE-D BUGMEAT 65% ×1-2")
	assert_string_contains(litter.drops_line.text, "TATTERCLOTH 35% ×1")

	# Clearance gates where leveled: level-1 fauna open, the ladder locks.
	assert_false(litter.gate_plate.visible, "Litterbug posts at clearance 1 (no gate)")
	var bunny: DocketPatrol.FaunaCard = cards["greater_dust_bunny"]
	assert_true(bunny.gate_plate.visible, "Dust Bunny gate plate visible at level 1")
	assert_string_contains(bunny.gate_text.text, "CLEARANCE 4 REQUIRED")
	assert_string_contains(bunny.gate_text.text, "EARNED BY PATROLLING THIS ZONE",
		"fauna gate teaches the earning path (kills raise combat clearance)")
	var boss: DocketPatrol.FaunaCard = cards["sewer_landlord"]
	assert_true(boss.gate_plate.visible, "boss gate plate visible at level 1")
	assert_string_contains(boss.gate_text.text, "CLEARANCE 14 REQUIRED")
	assert_string_contains(boss.tag_line.text, "SENIOR FAUNA", "boss posts as senior fauna")
	assert_string_contains(boss.stats_line.text, "HP 340")
	assert_string_contains(boss.stats_line.text, "EVERY 2.4 S")
	assert_string_contains(boss.stats_line.text, "1,000 XP ON KILL")
	assert_string_contains(boss.drops_line.text, "ROLLED 2 TIMES", "boss table rolls twice, posted")
	# Ascending ladder order.
	var order: Array = docket.get("_content_order")
	assert_eq(order[0], "junkyard_roach")
	assert_eq(order[4], "sewer_landlord")


# ---------------------------------------------------------------------------
# engage: gauges + log follow the engine
# ---------------------------------------------------------------------------

func test_engage_gauges_and_log_match_engine() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var c: Concourse = packed[0]
	var docket: DocketPatrol = packed[1]
	var cards := _cards(docket)

	(cards["junkyard_roach"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "card press engages through the façade")
	assert_true(_log_has(docket, "PATROL ENGAGED — LITTERBUG"))
	assert_eq(docket.p_read.text, "RESIDENT · 100/100 CONDITION", "resident gauge reads full at engage")
	assert_eq(docket.m_read.text, "LITTERBUG · 18/18 HP", "fauna gauge reads max HP at engage")
	assert_true(docket.phase_plate.visible, "phase plate posted while fighting")
	assert_eq(docket.phase_line.text, ">> PATROL ENGAGED — LITTERBUG")
	assert_false(docket.phase_directive.visible, "recovery directive is the death plate's alone")
	assert_eq((cards["junkyard_roach"].title as Label).text, ">> LITTERBUG", "engaged card carries the non-color cue")
	assert_eq((cards["junkyard_roach"].button as Button).theme_type_variation, "Energized")
	assert_eq(c.begin_button_for("wasteland_patrol").text, "WITHDRAW PATROL", "primary retexts while fighting")

	# Advance ticks in sub-interval chunks; after every chunk the gauges must
	# EQUAL engine state (flush-driven, never per-frame).
	var dealt := 0
	for i in 30:  # 9 s — mid-fight, resolution still pending
		_pump(tm, 300, 300)
		tm.batcher.force_flush(tm.sim_time_ms)
		var cc: Dictionary = tm.state.combat
		if str(cc["phase"]) != "fighting":
			break
		assert_eq(docket.p_gauge.value, float(clampi(int(cc["p_hp"]), 0, 100)),
			"resident gauge equals engine p_hp (chunk %d)" % i)
		assert_eq(docket.m_gauge.value, float(clampi(int(cc["m_hp"]), 0, 18)),
			"fauna gauge equals engine m_hp (chunk %d)" % i)
	assert_gt(docket.log.item_count, 1, "battle lines stamped from the batched signals")
	dealt = _sum_logged_damage(docket, "RESIDENT »")
	assert_gt(dealt, 0, "resident damage lines logged")
	assert_true(dealt <= 18, "logged damage never exceeds the fauna's actual HP pool")

	# Withdraw through the big stencled button.
	(c.begin_button_for("wasteland_patrol") as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "idle", "primary press withdraws the patrol")
	assert_true(_log_has(docket, "PATROL WITHDRAWN BY RESIDENT."))
	assert_eq(c.begin_button_for("wasteland_patrol").text, "ENGAGE PATROL")
	assert_false(docket.phase_plate.visible, "phase plate clears when idle")
	assert_eq(docket.p_read.text, "RESIDENT · 100/100 CONDITION",
		"idle board shows the posting condition (full reset on engage)")

	# Re-engage through the primary button (designated target retained).
	(c.begin_button_for("wasteland_patrol") as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "primary re-engages the designated fauna")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# victory: drops + XP stamps, gauges settle at the kill
# ---------------------------------------------------------------------------

func test_victory_stamps_claims_and_xp() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]
	var results: Array = []
	(tm.combat_ended as Signal).connect(func(result: Dictionary) -> void: results.append(result))

	(_cards(docket)["junkyard_roach"].button as Button).pressed.emit()
	assert_true(_pump_until_phase(tm, "victory", 60_000), "Litterbug dies within 60 s sim (got %s)" % str(tm.state.combat["phase"]))
	await wait_frames(1)
	assert_eq(results.size(), 1, "combat_ended fired once")
	var result: Dictionary = results[0]
	assert_eq(str(result["outcome"]), "victory")
	assert_eq(int(result["xp"]), 25)
	assert_true(_log_has(docket, "VICTORY — LITTERBUG DECEASED · +25 XP"))
	for item_id in (result["drops"] as Dictionary):
		var item: ItemDef = tm.engine.lib.item(str(item_id))
		assert_true(_log_has(docket, "CLAIM · %s ×%s" % [
			item.name.to_upper(), SignageFmt.num(int(result["drops"][item_id]))]),
			"claim stamp matches the engine's drop roll exactly")
	assert_eq(docket.m_read.text, "LITTERBUG · 0/18 HP", "fauna gauge settles at the kill")
	assert_true(docket.phase_plate.visible, "victory plate posted")
	assert_string_contains(docket.phase_line.text, "VICTORY POSTED — LITTERBUG DECEASED")
	assert_eq((packed[0] as Concourse).begin_button_for("wasteland_patrol").text, "ENGAGE PATROL")

	# The clearance gauge re-reads the shared XP pipeline.
	var curve = tm.engine.lib.xp_curve(tm.engine.lib.skill("wasteland_combat").xp_curve)
	var level := int(tm.state.skills_level["wasteland_combat"])
	var into: int = int(tm.state.skills_xp["wasteland_combat"]) - curve.total_xp_to_reach(level)
	assert_eq(docket.gauge_read.text, "CLEARANCE %02d · %s/%s XP TO NEXT" % [
		level, SignageFmt.num(into), SignageFmt.num(curve.xp_to_next(level))],
		"clearance gauge equals engine xp state exactly")

	# Re-engage after victory: fresh HP both sides (addendum 1).
	(_cards(docket)["junkyard_roach"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting")
	assert_eq(int(tm.state.combat["m_hp"]), 18, "fauna HP reset on re-engage")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# live death: halts, renders RETURN TO SHELTER, zero loss
# ---------------------------------------------------------------------------

func test_live_death_halts_and_renders_return_to_shelter() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var c: Concourse = packed[0]
	var docket: DocketPatrol = packed[1]

	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # clearance 14
	_flush(tm, "xp")
	await wait_frames(1)
	(_cards(docket)["sewer_landlord"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "boss engages at clearance 14")
	var inv_before: Dictionary = tm.state.inventory.duplicate()
	var xp_before := int(tm.state.skills_xp["wasteland_combat"])

	assert_true(_pump_until_phase(tm, "dead", 90_000), "ungearred boss fight ends in death (got %s)" % str(tm.state.combat["phase"]))
	await wait_frames(1)
	assert_eq(str(tm.state.combat["phase"]), "dead")
	assert_eq(docket.phase_plate.theme_type_variation, "DangerPlate", "death renders the red plate")
	assert_eq(docket.phase_line.text, "DECEASED — RETURN TO SHELTER")
	assert_string_contains(docket.phase_serial.text, "NOTHING WAS LOST", "zero loss displayed on the plate")
	# Refinement 2 (critique P1#2): the death plate posts the recovery
	# directive — re-engagement named, the no-loss fact kept on the plate,
	# and the full-condition reset the engine actually performs on engage.
	assert_true(docket.phase_directive.visible, "recovery directive posted on the death plate")
	assert_string_contains(docket.phase_directive.text, "RE-ENGAGE WHEN READY",
		"directive names the next step: re-engage")
	assert_string_contains(docket.phase_directive.text, "DESIGNATION IS PRESERVED",
		"directive keeps the designation fact (state.combat.monster_id persists)")
	assert_string_contains(docket.phase_directive.text, "FULL CONDITION",
		"directive states the full-condition reset of a fresh engagement")
	assert_true(_log_has(docket, "DECEASED — RETURN TO SHELTER · ZERO LOSS POSTED"))
	assert_eq(docket.p_read.text, "RESIDENT · 0/100 CONDITION", "resident gauge reads the death honestly")
	assert_eq(tm.state.inventory.duplicate(), inv_before, "death removed nothing from the Manifest")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), xp_before, "death granted no XP")
	assert_eq(c.begin_button_for("wasteland_patrol").text, "ENGAGE PATROL", "re-engage offered after death")

	# The fight STAYS stopped.
	_pump(tm, 5_000)
	assert_eq(str(tm.state.combat["phase"]), "dead", "combat halted after death")
	assert_eq(int(tm.state.combat["p_hp"]), 0)

	# Re-engage after death: full reset, no loss carried.
	(_cards(docket)["sewer_landlord"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting")
	assert_eq(int(tm.state.combat["p_hp"]), 100)
	assert_false(docket.phase_directive.visible, "directive clears the moment the patrol re-engages")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# auto-eat: ration queue renders best-first; meals stamped and counted
# ---------------------------------------------------------------------------

func test_auto_eat_consumption_visible() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]

	tm.engine.grant_xp(tm.state, "wasteland_combat", 3_226)  # clearance 10
	tm.state.add_item("vintage_snack_cake", 2)
	tm.state.add_item("mandatory_grits", 5)
	_flush(tm)
	await wait_frames(1)

	# The queue posts the engine's best-first order with live counts.
	var lines: Array[Label] = docket.get("_food_lines")
	assert_eq(lines[0].text, "1. MANDATORY GRITS ×5 · MENDS 15", "highest mend first (engine order)")
	assert_eq(lines[1].text, "2. VINTAGE SNACK CAKE ×2 · MENDS 10")
	assert_eq(docket.food_rule.text, "ONE RATION IS CONSUMED AT OR BELOW 50 CONDITION (HALF).")

	(_cards(docket)["feral_snack_dispenser"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting")
	_pump_until_phase(tm, "dead", 130_000)  # eats long before the end either way
	var eaten: int = int(tm.state.combat["eaten_total"])
	assert_gt(eaten, 0, "auto-eat engaged below half condition")
	var grits_eaten := _sum_logged_rations(docket, "MANDATORY GRITS")
	var cakes_eaten := _sum_logged_rations(docket, "VINTAGE SNACK CAKE")
	assert_eq(grits_eaten + cakes_eaten, eaten,
		"ration stamps account for every unit the engine ate (grits %d + cakes %d = %d)" % [
			grits_eaten, cakes_eaten, eaten])
	assert_eq(int(tm.state.inventory.get("mandatory_grits", 0)) + int(tm.state.inventory.get("vintage_snack_cake", 0)),
		7 - eaten, "Manifest counts the consumed rations")
	assert_eq(docket.ration_read.text, "RATIONS CONSUMED THIS ENGAGEMENT · %d" % eaten)
	# Damage accounting stays exact alongside heals: every resident-damage line
	# matches the HP the engine actually lost (heals included).
	assert_true(_sum_logged_damage(docket, "FERAL SNACK DISPENSER »") > 0)


# ---------------------------------------------------------------------------
# offline recall: rendered here AND via mail-call; alive; zero loss
# ---------------------------------------------------------------------------

func test_recalled_phase_renders_and_reengages() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var c: Concourse = packed[0]
	var docket: DocketPatrol = packed[1]

	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)
	_flush(tm, "xp")
	await wait_frames(1)
	(_cards(docket)["sewer_landlord"].button as Button).pressed.emit()
	_pump(tm, 6_000)  # fight underway, damage taken
	assert_eq(str(tm.state.combat["phase"]), "fighting")
	var inv_before: Dictionary = tm.state.inventory.duplicate()
	var xp_before := int(tm.state.skills_xp["wasteland_combat"])

	tm.apply_offline_elapsed(3_600_000)  # 1 h away, no rations -> survivability bound
	await wait_frames(2)
	assert_eq(str(tm.state.combat["phase"]), "recalled", "offline replay recalls at the killing blow")
	assert_gt(int(tm.state.combat["p_hp"]), 0, "recalled patrol is ALIVE at pre-blow HP")
	assert_eq(docket.phase_plate.theme_type_variation, "DangerPlate", "recall renders the RETURN TO SHELTER family")
	assert_eq(docket.phase_line.text, "PATROL RECALLED — RETURN TO SHELTER")
	assert_string_contains(docket.phase_serial.text, "ZERO LOSS")
	assert_true(_log_has(docket, "PATROL RECALLED · WITHDRAWN ALIVE AT THE LIMIT · ZERO LOSS"),
		"recall stamped on the docket log")
	assert_true(c.mail_call.is_presenting(), "recall also surfaced via MAIL CALL")
	var mail_texts: Array[String] = []
	for l in c.mail_call.find_children("*", "Label", true, false):
		mail_texts.append((l as Label).text)
	assert_true(mail_texts.any(func(t: String) -> bool: return "PATROL RECALLED" in t),
		"mail call carries the recall notice")
	c.mail_call.acknowledge()
	assert_eq(tm.state.inventory.duplicate(), inv_before, "recall removed nothing")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), xp_before, "recall granted nothing")
	assert_eq(c.begin_button_for("wasteland_patrol").text, "ENGAGE PATROL", "re-engage offered after recall")

	(_cards(docket)["sewer_landlord"].button as Button).pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "recalled patrol re-engages at will")
	assert_eq(int(tm.state.combat["p_hp"]), 100, "fresh condition on re-engage")
	tm.stop_combat()


# ---------------------------------------------------------------------------
# ZONE SECURED: appears once, persists through save/load
# ---------------------------------------------------------------------------

func test_zone_clear_plate_appears_once_and_persists() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]

	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # clearance 14
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 10)
	_flush(tm)
	await wait_frames(1)
	assert_true(bool((tm.equip_item("majority_whip") as Dictionary)["ok"]))
	assert_true(bool((tm.equip_item("carpool_carapace") as Dictionary)["ok"]))
	var clears := {"n": 0}
	(tm.zone_cleared as Signal).connect(func(_mid: String) -> void: clears["n"] += 1)

	assert_false(docket.zone_plate.visible, "zone plate hidden before the first boss clear")
	(_cards(docket)["sewer_landlord"].button as Button).pressed.emit()
	assert_true(_pump_until_phase(tm, "victory", 300_000),
		"max gear + rations clears the boss (got %s)" % str(tm.state.combat["phase"]))
	await wait_frames(1)
	assert_eq(clears["n"], 1, "zone_cleared emitted exactly once")
	assert_true(bool(tm.state.combat["zone_clear"]), "persistent zone_clear state set")
	assert_true(docket.zone_plate.visible, "ZONE SECURED plate posted on first clear")
	assert_eq(_log_count(docket, "ZONE SECURED"), 1, "one win-moment stamp")

	# Save/load round-trip (JSON parse included — the float-coercion path the
	# real save takes): the plate renders from STATE, no signal required.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(tm.state.to_dict()))
	assert_not_null(saved, "save payload round-trips JSON")
	var tm2: Variant = _make_tm(SEED)
	tm2.adopt_state(PlayerState.from_dict(saved, tm2.engine.lib), int(tm.sim_time_ms))
	var packed2 := await _make_patrol(tm2)
	var docket2: DocketPatrol = packed2[1]
	assert_true(bool(tm2.state.combat["zone_clear"]), "zone_clear survived the round-trip")
	assert_true(docket2.zone_plate.visible, "ZONE SECURED plate persists through save/load")
	var clears2 := {"n": 0}
	(tm2.zone_cleared as Signal).connect(func(_mid: String) -> void: clears2["n"] += 1)

	# A repeat clear does not re-celebrate (the state is once-ever).
	(_cards(docket2)["sewer_landlord"].button as Button).pressed.emit()
	assert_true(_pump_until_phase(tm2, "victory", 300_000), "repeat clear still wins")
	await wait_frames(1)
	assert_eq(clears2["n"], 0, "no second zone_cleared emission")
	assert_eq(_log_count(docket2, "ZONE SECURED"), 0, "no duplicate win-moment stamp")
	assert_true(docket2.zone_plate.visible, "plate stays posted (persistent, not re-fired)")


# ---------------------------------------------------------------------------
# stats panel derives from equipment
# ---------------------------------------------------------------------------

func test_stats_panel_derives_from_equipment() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]
	await wait_frames(1)

	assert_eq(docket.stats_line.text,
		"ACCURACY 30 · EVADE 10 · MAX HIT 1-4 · SWING EVERY 3.0 S · CONDITION 100",
		"bare chassis stats posted (engine-derived)")
	assert_eq(docket.weapon_name.text, "— VACANT —")
	assert_eq(docket.armor_name.text, "— VACANT —")

	tm.state.add_item("scrap_shiv", 1)
	tm.state.add_item("hubcap_vest", 1)
	_flush(tm)
	await wait_frames(1)
	tm.equip_item("scrap_shiv")
	assert_eq(docket.weapon_name.text, "POINT OF ORDER", "weapon slot names the equipped gear")
	assert_eq(docket.weapon_serial.text, "SWING 2.6 S · ACC +10 · MAX HIT +4")
	assert_eq(docket.stats_line.text,
		"ACCURACY 40 · EVADE 10 · MAX HIT 1-8 · SWING EVERY 2.6 S · CONDITION 100",
		"stats re-derive on equip via the batched signal")

	tm.equip_item("hubcap_vest")
	assert_eq(docket.armor_name.text, "PEDESTRIAN PLATING")
	assert_eq(docket.armor_serial.text, "EVA +12 · HP +20")
	assert_eq(docket.stats_line.text,
		"ACCURACY 40 · EVADE 22 · MAX HIT 1-8 · SWING EVERY 2.6 S · CONDITION 120",
		"armor bonus applied (additive, weapon speed replaces)")
	# Agreement with the engine's own derivation, value by value.
	var stats: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(int(stats["max_hp"]), 120)
	assert_eq(int(stats["accuracy"]), 40)
	assert_eq(int(stats["evasion"]), 22)
	assert_eq(int(stats["max_hit"]), 8)
	assert_eq(int(stats["speed"]), 2_600)


# ---------------------------------------------------------------------------
# resumed mid-fight state renders on load
# ---------------------------------------------------------------------------

func test_resumed_midfight_renders_on_load() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]
	(_cards(docket)["junkyard_roach"].button as Button).pressed.emit()
	_pump(tm, 8_000)  # mid-fight: damage dealt, no resolution yet
	assert_eq(str(tm.state.combat["phase"]), "fighting")
	var p_hp := int(tm.state.combat["p_hp"])
	var m_hp := int(tm.state.combat["m_hp"])

	# Load path: to_dict -> JSON -> from_dict -> adopt_state -> fresh UI.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(tm.state.to_dict()))
	var tm2: Variant = _make_tm(SEED)
	tm2.adopt_state(PlayerState.from_dict(saved, tm2.engine.lib), int(tm.sim_time_ms))
	var packed2 := await _make_patrol(tm2)
	var docket2: DocketPatrol = packed2[1]
	assert_eq(str(tm2.state.combat["phase"]), "fighting", "fight resumed by adopt_state")
	assert_eq(docket2.p_read.text, "RESIDENT · %s/100 CONDITION" % SignageFmt.num(p_hp),
		"resident gauge renders the saved mid-fight HP")
	assert_eq(docket2.m_read.text, "LITTERBUG · %s/18 HP" % SignageFmt.num(m_hp),
		"fauna gauge renders the saved mid-fight HP")
	assert_eq(docket2.phase_line.text, ">> PATROL ENGAGED — LITTERBUG")
	assert_eq((packed2[0] as Concourse).begin_button_for("wasteland_patrol").text, "WITHDRAW PATROL")
	assert_true(_log_has(docket2, "PATROL RESUMED — ENGAGEMENT IN PROGRESS."),
		"resume state stamped once on load")
	tm2.stop_combat()
	tm.stop_combat()


# ---------------------------------------------------------------------------
# keyboard traversal + signal discipline
# ---------------------------------------------------------------------------

func test_patrol_keyboard_traversal_covers_focusables() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var c: Concourse = packed[0]
	var docket: DocketPatrol = packed[1]

	var focusables := c.focusable_controls()
	var docket_focus: Array[Control] = []
	_collect_focusable(c.docket_for("wasteland_patrol"), docket_focus)
	assert_eq(focusables.size(), 7 + 4 + docket_focus.size(),
		"focusables = 7 plates + 4 console + %d patrol controls (got %d)" % [
			docket_focus.size(), focusables.size()])
	for control in docket_focus:
		assert_ne(control.name, "", "patrol control named")
	assert_true(docket_focus.any(func(f: Control) -> bool: return f.name == "Fauna_junkyard_roach"),
		"fauna card is focusable")
	assert_true(docket_focus.any(func(f: Control) -> bool: return f.name == "LogLines"),
		"battle log is focusable")

	# Tab chain from the initial focus reaches every focusable control.
	var visited := {}
	var cur: Control = c.initial_focus()
	var guard := 0
	while guard < 128 and not visited.has(cur):
		visited[cur] = true
		cur = cur.find_next_valid_focus()
		guard += 1
	for f in focusables:
		assert_true(visited.has(f), "focusable %s reachable via tab chain" % f.name)
	assert_eq(visited.size(), focusables.size(), "tab chain covers exactly the focusable set")

	# Keyboard activation: focus + ui_accept on a fauna card engages.
	var card := (_cards(docket)["junkyard_roach"].button as Button)
	card.grab_focus()
	await wait_frames(1)
	assert_true(card.has_focus(), "fauna card holds focus")
	card.pressed.emit()
	assert_eq(str(tm.state.combat["phase"]), "fighting", "accept on a focused fauna card engages")
	tm.stop_combat()


func test_patrol_labels_freeze_when_unbound() -> void:
	var tm: Variant = _make_tm(SEED)
	var packed := await _make_patrol(tm)
	var docket: DocketPatrol = packed[1]
	(_cards(docket)["junkyard_roach"].button as Button).pressed.emit()
	_pump(tm, 3_100)
	var frozen := docket.p_read.text
	var frozen_log := docket.log.item_count
	docket.unbind()
	_pump(tm, 6_100)
	assert_eq(docket.p_read.text, frozen, "gauges frozen after unbind (no polling)")
	assert_eq(docket.log.item_count, frozen_log, "log frozen after unbind")
	assert_gt(int(tm.stats["ticks_executed"]), 0, "engine advanced on without the UI")
	tm.stop_combat()


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		var blocked := control is BaseButton and (control as BaseButton).disabled
		if control.focus_mode != Control.FOCUS_NONE and not blocked \
				and control.is_visible_in_tree():
			out.append(control)
	for child in node.get_children():
		_collect_focusable(child, out)
