extends GutTest
## tests/test_acceptance_run3.gd — T28 run-3 acceptance suite (Hawkeye lane).
##
## Automates the Scope Amendment 2 acceptance criteria (town-hall.md, run 3)
## headless against LIVE content, JOURNEY style — each test walks one resident
## from a fresh save through the real engines, the real facades, and where the
## criterion is visible, the real concourse. The per-system batteries stay in
## their run-3 homes (tests/test_objectives.gd, tests/test_dossier.gd); this
## file certifies the AMENDMENT end to end:
##
##   R0  the amendment floor, asserted IN THE ACCEPTANCE SUITE — the shipped
##       dossier set carries >= 20 objectives per skill (>= 100 total), every
##       one of the 9 condition kinds is present in the shipped set, and both
##       run-3 zones ship (the "hard acceptance: probe-asserted count" clause,
##       suite-side).
##   R1  every-condition-kind journey — one resident stamps at least one
##       objective of 8 kinds through the real engine event that earns it
##       (level crossing, gather action, completed craft, Depot tender,
##       lifetime Crowns, combat victory, equip, boss zone-clear), with the
##       wallet tracked EXACTLY as sale income + the auto-granted MERIT PAY of
##       every stamped line (the rewards-integrate-with-the-wallet criterion).
##   R2  dossier-UI journey — five real stamps in one skill (EARN CLEARANCE
##       2/5/10 + SORT 25/250, all through live duty), then the concourse's
##       DossierRegister is swept row by row against the ENGINE's own reads:
##       stamp state, mono progress readouts, posted order, summary count.
##   R3  full-dossier completion — the same 23-objective scavenging set driven
##       to ALL 23 STAMPED through real seams (the level ladder, offline duty
##       windows, the 1,000-unit tender), certifying the 9th kind
##       (stamped_count) by the real cascade, then the completion plate is
##       asserted in-tree on a freshly bound concourse.
##   R4  both-zones journey — one resident clears The Superintendent with the
##       intended slice-max gear + stews, then The Regional Manager with the
##       T4 ladder (Cloture + Turnpike Aegis + Court Feast) at clearance 40;
##       the zone rungs + boss kill counters stamp on the real victories.
##   R5  depth journey — a gathering skill TRAINED tier by tier (live duty +
##       real offline windows, every gate crossed) into its NEW tier-7
##       activity (Deconstruct the Signal Tower, clearance 41), whose windows
##       bank the deep materials; then a T4 weapon crafted END TO END through
##       real crafting windows (Scrapnel -> Almost Bullion -> Quorum Alloy ->
##       Unanimous Steel -> Line-Item Veto), equipped, with derived stats
##       asserted from equipment data.
##   R6  migration journey — a played record hand-degraded to the honest v2
##       shape loads through the real SaveStore: derivable clearance rungs
##       stamp at adopt with rewards posted once, per-activity counters start
##       honestly at zero (the documented policy), the record re-files v3.
##   R7  onboarding cascade — a fresh save's FIRST FIFTEEN MINUTES as one
##       rotation of real duty: >= 8 dossier rungs stamped by minute 7 (the
##       T27 §6.4 model), the ORIENTATION FORM O-1 completing at the real
##       deputize (stipend once), and merit pay >= 35 cr by minute 15 (the
##       §6.4 early-feel pin).
##
## Determinism: fresh TickManager twins booted with explicit seeds via _boot()
## (live content), never added to the tree — advance_wall_ms and
## apply_offline_elapsed are the only clock inputs (the same discipline as
## test_acceptance / test_objectives / test_dossier). The heavy R3 windows and
## R5 tier ladder reuse the offline-window seam the T25 cascade test proved;
## guard loops make every crossing self-sizing so drop variance cannot wedge
## a journey.

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260928          ## this suite's own seed (R3's cascade uses T25's proven 20260923)
const CASCADE_SEED := 20260923  ## inherited from the T25 full-dossier cascade determinism
const NOW := 1_768_000_000_000
const TICK_MS := 100
const MIN_MS := 60_000


# ------------------------------------------------------------------ helpers --

func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (run-3 acceptance runs on live data)")
	return result.library


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _pump(tm: Variant, total_ms: int, chunk_ms := 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


## Pump until `cond` holds, in small slices, with an iteration guard — the
## journeys' crossings are self-sizing (never a hand-tuned window).
func _pump_until(tm: Variant, cond: Callable, slice_ms := 5_000, guard := 400) -> int:
	var slices := 0
	while not cond.call() and slices < guard:
		_pump(tm, slice_ms, TICK_MS if slice_ms <= 1_000 else 1_000)
		slices += 1
	return slices


func _flush(tm: Variant, regions: Array = ["inventory"]) -> void:
	for region in regions:
		tm.batcher.mark(region)
	tm.batcher.force_flush(tm.sim_time_ms)


func _make_concourse(tm: Variant) -> Concourse:
	var c := ConcourseScene.instantiate() as Concourse
	assert_not_null(c, "concourse scene instantiates")
	add_child_autofree(c)
	c.auto_reveal = false  # T33 seam: this suite pins pre-deep-link shell behavior
	c.bind_engines(tm)
	await wait_frames(2)
	return c


func _tmp_dir(label: String) -> String:
	var dir := OS.get_user_data_dir().path_join("t28_run3/%s_%d" % [label, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## The exact MERIT PAY posted so far: the sum of the data reward crowns of
## every stamped objective (rewards post exactly once, so the final set is the
## truth regardless of cascade order). The wallet-integration anchor.
func _merit_posted(tm: Variant) -> int:
	var total := 0
	for obj_id in tm.engine.lib.objectives:
		var obj: ObjectiveDef = tm.engine.lib.objectives[obj_id]
		if tm.is_objective_stamped(obj_id):
			total += obj.reward_crowns
	return total


func _stamped_count(tm: Variant) -> int:
	return (tm.state.objectives["stamped"] as Array).size()


# ---------------------------------------------------------------------------
# R0 — the amendment floor, asserted in the acceptance suite
# ---------------------------------------------------------------------------

func test_r0_amendment_floor_twenty_per_skill_and_every_kind() -> void:
	var lib := _lib()
	# THE Scope Amendment 2 hard acceptance, suite-side (probe_content pins it
	# on the shipped file; the acceptance suite carries its own assertion).
	assert_gte(lib.objectives.size(), 100,
		"the shipped dossier set carries >= 100 objectives (got %d)" % lib.objectives.size())
	for skill in lib.skills.values():
		var n: int = lib.objectives_for_skill(skill.id).size()
		assert_gte(n, 20, "dossier '%s' carries >= 20 objectives (got %d)" % [skill.id, n])
	# Every one of the 9 condition kinds is exercised by the shipped set —
	# the R1/R3 journeys certify each kind on real engine events; this asserts
	# the data actually ships all of them.
	var kinds := {}
	for obj_id in lib.objectives:
		kinds[lib.objectives[obj_id].kind] = true
	for kind in ObjectiveDef.KINDS:
		assert_true(kinds.has(kind), "the shipped set exercises condition kind '%s'" % kind)
	# The run-3 zone pair ships (the second zone is this amendment's supersession).
	assert_eq(lib.zones.size(), 2, "both run-3 zone ids ship in zones.json")
	assert_not_null(lib.zone("dusty_flats"), "dusty_flats resolves")
	assert_not_null(lib.zone("gift_court"), "gift_court resolves with T24 fauna + boss")


# ---------------------------------------------------------------------------
# R1 — every condition kind through the real engine event that earns it
# ---------------------------------------------------------------------------

func test_r1_every_condition_kind_stamps_through_real_events() -> void:
	var tm: Variant = _make_tm()
	var units_sold := 0  ## glowshroom tendered at the Depot (the journey's only sale income)

	# ---- level_reach: a real gathering shift crosses the first clearance.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the resident's own hands take the posting")
	var slices: int = _pump_until(tm, func() -> bool: return tm.is_objective_stamped("scav_clearance_2"))
	assert_true(tm.is_objective_stamped("scav_clearance_2"),
		"level_reach: EARN CLEARANCE 2 stamped by the real level-up path (%d slices)" % slices)
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "the crossing was a real level-up")

	# ---- gather_count: 25 completed actions of one activity.
	slices = _pump_until(tm, func() -> bool: return tm.is_objective_stamped("scav_sort_25"))
	assert_true(tm.is_objective_stamped("scav_sort_25"),
		"gather_count: SORT THE SCRAP PILE 25 stamped by real actions (%d slices)" % slices)
	assert_eq(int(tm.state.objectives["counters"].get("activity:sort_scrap_pile", 0)), 25,
		"the activity counter counts completed actions exactly")

	# ---- craft_count: keep sorting until the smelter can run 25 real crafts,
	# then run them LIVE (input-capped by the banked Scrapnel).
	slices = _pump_until(tm, func() -> bool: return tm.state.item_count("scrap_metal") >= 90)
	assert_gte(tm.state.item_count("scrap_metal"), 90,
		"the shift banked enough Scrapnel for 25 smelts (got %d)" % tm.state.item_count("scrap_metal"))
	tm.stop_skill("scavenging")
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"], "the smithy takes the posting")
	slices = _pump_until(tm, func() -> bool: return tm.is_objective_stamped("junk_smelt_25"))
	assert_true(tm.is_objective_stamped("junk_smelt_25"),
		"craft_count: SMELT 25 ALMOST BULLION stamped by completed crafts (%d slices)" % slices)
	assert_eq(int(tm.state.objectives["counters"].get("recipe:smelt_scrap_ingot", 0)), 25,
		"the craft counter counts completed crafts exactly")
	tm.stop_skill("junksmithing")

	# ---- kill_count: ten real Litterbug victories (bare-handed — the fight
	# is honest duty, not a gear check).
	var kills := 0
	var guard := 0
	while kills < 10 and guard < 240:
		if String(tm.state.combat["phase"]) != "fighting":
			assert_true(tm.engage_monster("junkyard_roach")["ok"], "ENGAGE the Litterbug")
		_pump(tm, 20_000, 2_000)
		guard += 1
		if String(tm.state.combat["phase"]) == "victory":
			kills += 1
	assert_eq(kills, 10, "ten real victories landed (guard %d)" % guard)
	assert_true(tm.is_objective_stamped("combat_litterbug_10"),
		"kill_count: CLEAR 10 LITTERBUGS stamped by real victories")
	assert_eq(int(tm.state.objectives["counters"].get("monster:junkyard_roach", 0)), 10,
		"the kill counter counts victories exactly")

	# ---- equip_item: the Manifest equip seam (the whip itself is staged —
	# R5 certifies the crafted path to a weapon; here the EQUIP seam is the
	# subject, the T23 zone-test precedent).
	tm.stop_combat()
	tm.state.add_item("majority_whip", 1)
	assert_true(tm.equip_item("majority_whip")["ok"], "EQUIP the Majority Whip from the Manifest")
	assert_true(tm.is_objective_stamped("combat_equip_whip"),
		"equip_item: EQUIP MAJORITY WHIP stamped by the real equip")
	assert_eq(int(tm.state.objectives["counters"].get("item_equipped:majority_whip", 0)), 1,
		"the equip counter counted the real equip")

	# ---- zone_clear: the Superintendent with the intended slice-max gear
	# (balance-notes §2: max gear + food clears reliably) at clearance 14 via
	# the shared XP pipeline — the same seam every kill's XP flows through.
	tm.engine.grant_xp(tm.state, "wasteland_combat",
		tm.engine.lib.xp_curve("standard_99").total_xp_to_reach(14), true)
	tm.state.add_item("carpool_carapace", 1)
	assert_true(tm.equip_item("carpool_carapace")["ok"])
	tm.state.add_item("radstag_stew", 20)
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "the boss engages at clearance 14")
	guard = 0
	while String(tm.state.combat["phase"]) == "fighting" and guard < 700:
		_pump(tm, 2_000)
		guard += 1
	assert_eq(String(tm.state.combat["phase"]), "victory", "the Superintendent cleared (guard %d)" % guard)
	assert_true(bool(tm.state.combat["zone_clear"]), "the persisted zone_clear flag set")
	assert_true(tm.is_objective_stamped("combat_secure_flats"),
		"zone_clear: SECURE THE SUNNY ZONE stamped by the real boss kill")
	assert_eq(int(tm.state.objectives["counters"].get("zone:dusty_flats", 0)), 1,
		"the zone counter counts boss defeats")

	# ---- sell_count + crowns_total: an away window of the glow rows banks
	# the tender, then real Depot sales stamp both economy kinds.
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"], "the forage posting takes over")
	tm.apply_offline_elapsed(3_600_000)  # one away hour banks ~1,400 Glowshroom
	tm.stop_skill("foraging")
	assert_gt(tm.state.item_count("glowshroom"), 800,
		"the away window banked a real Glowshroom surplus (%d)" % tm.state.item_count("glowshroom"))
	assert_true(tm.depot_sell("glowshroom", 400)["ok"], "the first tender: exactly 400 units")
	units_sold += 400
	assert_true(tm.is_objective_stamped("forage_sell_caps_400"),
		"sell_count: SELL 400 GLOWSHROOM stamped by the real tender")
	guard = 0
	while not tm.is_objective_stamped("cook_crowns_2500") and guard < 20:
		var chunk: int = mini(200, tm.state.item_count("glowshroom"))
		assert_gt(chunk, 0, "the banked surplus covers the crowns rung")
		assert_true(tm.depot_sell("glowshroom", chunk)["ok"])
		units_sold += chunk
		guard += 1
	assert_true(tm.is_objective_stamped("cook_crowns_2500"),
		"crowns_total: EARN 2,500 CROWNS stamped — sales + merit pay are both earned income (guard %d)" % guard)

	# ---- the wallet-integration anchor: EXACT sale income + the auto-granted
	# MERIT PAY of every stamped line, and the lifetime counter agrees (the
	# journey never purchased, so posted == held).
	var merit := _merit_posted(tm)
	assert_eq(int(tm.state.crowns), units_sold * tm.engine.lib.item("glowshroom").value + merit,
		"wallet = tender income (%d cr) + every stamped rung's auto-granted merit (%d cr)" % [units_sold * 2, merit])
	assert_eq(int(tm.state.objectives["counters"].get("crowns", 0)), int(tm.state.crowns),
		"the lifetime crowns counter reads every posted Crown (sales + merit, no spends)")
	assert_gte(_stamped_count(tm), 12, "the journey stamped a dozen-plus rungs across 8 kinds")


# ---------------------------------------------------------------------------
# R2 — five real stamps in one skill, dossier UI state == engine state
# ---------------------------------------------------------------------------

func test_r2_dossier_ui_matches_engine_through_five_stamps() -> void:
	var tm: Variant = _make_tm()
	# Five REAL rungs of the Reclamation Dossier, all through live duty on one
	# posting: EARN CLEARANCE 2 -> SORT 25 -> EARN CLEARANCE 5 -> SORT 250 ->
	# EARN CLEARANCE 10 (323 tier-1 actions = 3,230 XP crosses 3,226).
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	for rung in ["scav_clearance_2", "scav_sort_25", "scav_clearance_5", "scav_sort_250",
			"scav_clearance_10"]:
		var slices: int = _pump_until(tm, func() -> bool: return tm.is_objective_stamped(rung))
		assert_true(tm.is_objective_stamped(rung), "%s stamped by real duty (%d slices)" % [rung, slices])
	tm.stop_skill("scavenging")
	assert_eq(int(tm.objectives.skill_summary(tm.state, "scavenging")["stamped"]), 5,
		"the engine counts exactly five stamped rungs")

	# Bind the real concourse AFTER the duty (the register reads engine truth
	# at bind; no offline windows run under a bound UI in this suite).
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(2)
	var reg: DossierRegister = c.docket_controller("scavenging").get("register")
	assert_false(reg.is_expanded(), "the register mounts folded (the O-1 slip discipline)")
	reg.expand()  # rows build at first expansion (the perf-idle discipline)
	await wait_frames(1)
	var rows := reg.rows()
	assert_eq(rows.size(), 23, "the register renders all 23 objectives of the T25 set")

	# THE SWEEP: every row's UI state equals the engine's own read — stamp
	# visibility, mono progress readout, posted order, description.
	var expected_ids: Array = []
	for row_dict in tm.dossier_summary("scavenging")["rows"]:
		expected_ids.append(String(row_dict["id"]))
	for i in rows.size():
		var row := rows[i]
		var truth: Dictionary = tm.objectives.progress(tm.state, row.objective_id)
		assert_eq(row.objective_id, expected_ids[i],
			"row %d is the engine's posted-order objective (%s)" % [i, row.objective_id])
		assert_eq(row.title.text, String(tm.engine.lib.objective(row.objective_id).description),
			"row %d quotes the data description verbatim" % i)
		assert_eq(row.stamp.visible, bool(truth["stamped"]),
			"row %d stamp visibility equals the engine's stamped set" % i)
		assert_eq(row.empty_box.visible, not bool(truth["stamped"]),
			"row %d empty box is exactly the stamp's complement" % i)
		assert_eq(row.progress.text, "%s/%s" % [SignageFmt.num(int(truth["current"])), SignageFmt.num(int(truth["target"]))],
			"row %d readout equals the live engine counter (%s vs %s/%s)" % [i, row.progress.text,
				SignageFmt.num(int(truth["current"])), SignageFmt.num(int(truth["target"]))])
	# The five worked rungs are the stamped five — no more, no less.
	var stamped_rows := 0
	for row in rows:
		if row.stamp.visible:
			stamped_rows += 1
	assert_eq(stamped_rows, 5, "exactly five rows show the red stamp glyph")
	# The summary counts engine truth, never a UI tally.
	assert_eq(reg.summary_text(), "D.O.C.S. FORM R-1 · 5/23 STAMPED",
		"the summary line posts the serial + progress verb (got '%s')" % reg.summary_text())
	assert_false(reg.is_complete(), "no completion plate while 18 rungs stand open")
	# Wallet integration on this journey: five rungs' merit, nothing else.
	assert_eq(int(tm.state.crowns), _merit_posted(tm),
		"the five rungs' MERIT PAY posted through the wallet exactly (%d cr)" % int(tm.state.crowns))


# ---------------------------------------------------------------------------
# R3 — the 23-rung cascade: stamped_count + the completion plate
# ---------------------------------------------------------------------------

## The 9th kind (stamped_count) certifies here: the 22nd stamp of a REAL
## skill's set cascades the meta rung in the same evaluation pass, the dossier
## completes exactly once, and the completion plate posts in-tree.
func test_r3_full_dossier_completion_cascades_the_meta_rung() -> void:
	var tm: Variant = _make_tm(CASCADE_SEED)  # T25's proven cascade seed
	var dossiers: Array = []
	tm.dossier_completed.connect(func(payload: Dictionary) -> void: dossiers.append(payload))

	# The 8-rung clearance ladder through the real level_up hook.
	tm.engine.grant_xp(tm.state, "scavenging",
		tm.engine.lib.xp_curve("standard_99").total_xp_to_reach(70), true)
	for grade in [2, 5, 10, 16, 30, 41, 54, 70]:
		assert_true(tm.is_objective_stamped("scav_clearance_%d" % grade),
			"the clearance-%d ladder rung stamped on the level-up path" % grade)

	# The count + item rungs through real offline duty windows (the away-time
	# the docs promise; counters maintained inside the shared _execute_action).
	# Guard-sized: each window repeats until its rung stamps, so drop variance
	# cannot wedge the journey.
	var windows := [
		["sort_scrap_pile", "scav_sort_250", 765_000],
		["strip_wreck", "scav_strip_50", 260_000],
		["drain_the_sump", "scav_girderling_100", 6_000_000],   # 40 rung + 100 Girderling
		["unbuild_the_overpass", "scav_overpass_60", 465_000],
		["sweep_service_corridors", "scav_corridors_75", 654_500],
		["pry_mezzanine_lockers", "scav_lockers_100", 1_020_000],
		["deconstruct_signal_tower", "scav_counterweight_250", 4_200_000],  # 150 rung + 250 Counterweights
		["excavate_foundation_grid", "scav_foundation_200", 2_626_000],
		["audit_archive_vault", "scav_strongroom_250", 3_795_000],
	]
	for triple in windows:
		var guard := 0
		while not tm.is_objective_stamped(triple[1]) and guard < 4:
			tm.stop_skill("scavenging")  # one posting on the record; rotate it
			assert_true(tm.start_activity(triple[0])["ok"], "posting rotates to %s" % triple[0])
			tm.apply_offline_elapsed(triple[2])
			guard += 1
		assert_true(tm.is_objective_stamped(triple[1]),
			"%s stamped by its away window(s) (%d)" % [triple[1], guard])
	# The remaining count rungs stamped inside those windows too.
	for rung in ["scav_sort_25", "scav_sump_40", "scav_signal_150"]:
		assert_true(tm.is_objective_stamped(rung), "%s stamped by the windows" % rung)
	assert_true(tm.is_objective_stamped("scav_crowns_5000"),
		"EARN 5,000 CROWNS stamped — merit pay is earned income")

	# Bind the real concourse BEFORE the final event (a live discrete Depot
	# tender — no offline windows run under a bound UI in this suite), fold
	# the register, and let the 22nd stamp expand it: the win moment posts.
	tm.stop_skill("scavenging")
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(2)
	var reg: DossierRegister = c.docket_controller("scavenging").get("register")
	reg.expand()  # rows build at first expansion (the perf-idle discipline)
	await wait_frames(1)
	reg.fold()
	assert_false(reg.is_expanded(), "the register stands folded before the final event")

	var stash := int(tm.state.inventory.get("scrap_metal", 0))
	assert_gt(stash, 0, "the windows banked a real Scrapnel surplus")
	if stash < 1_000:
		tm.state.add_item("scrap_metal", 1_000 - stash)  # the T25 cascade precedent
	assert_true(tm.depot_sell("scrap_metal", 1_000)["ok"], "the final event: a 1,000-unit tender")
	_flush(tm, ["objectives", "inventory"])
	await wait_frames(1)
	assert_true(tm.is_objective_stamped("scav_sell_scrap_1000"), "SELL 1,000 SCRAPNEL stamped")
	assert_true(tm.is_objective_stamped("scav_stamped_22"),
		"stamped_count: the meta rung cascaded in the same pass — the 22nd stamp completes the set")
	assert_eq(dossiers.size(), 1, "dossier_completed fired EXACTLY once")
	assert_eq(String(dossiers[0]["stamp_line"]), "ALL 23 STAMPED · FORM R-1",
		"the completion payload carries the T22 stamp line")
	assert_eq(int(dossiers[0]["total"]), 23, "total from data")
	assert_eq(_stamped_count_in(tm, "scavenging"), 23, "all 23 rungs of the skill stand stamped")
	assert_eq(tm.state.objectives["rewards_granted"], tm.state.objectives["stamped"],
		"every stamp granted its rewards (the R3 wallet integration)")

	# The completion plate posts IN-TREE on the real signal — then folds back
	# to the stamp-line slip.
	assert_true(reg.is_expanded(), "completion expands the register (the win moment posts)")
	assert_true(reg.is_complete(), "the register reads completion from engine truth")
	assert_true(reg.get_node("RegisterColumn/CompletionRecord").visible,
		"the ALL 23 STAMPED plate posts")
	assert_eq(reg.completion_stamp_text(), "ALL 23 STAMPED · FORM R-1",
		"the plate's stamp line is data-derived")
	reg.fold()
	assert_eq(reg.summary_text(), "ALL 23 STAMPED · FORM R-1",
		"the folded slip IS the completion stamp (one source of truth)")
	# Wallet: 2,000 cr of tender + every granted merit leg, exactly.
	assert_eq(int(tm.state.crowns), 1_000 * tm.engine.lib.item("scrap_metal").value + _merit_posted(tm),
		"wallet = tender income + the completed dossier's full merit pay")


func _stamped_count_in(tm: Variant, skill_id: String) -> int:
	return tm.objectives.stamped_count_for_skill(tm.state, skill_id)


# ---------------------------------------------------------------------------
# R4 — both zones cleared on real sims with the intended gear
# ---------------------------------------------------------------------------

func test_r4_both_zones_clear_with_intended_gear() -> void:
	var tm: Variant = _make_tm()
	var lib := _lib()

	# The Regional Manager is honestly locked at clearance 40 first — the
	# negative control for the second zone's gate.
	tm.engine.grant_xp(tm.state, "wasteland_combat", lib.xp_curve("standard_99").total_xp_to_reach(14), true)
	var locked: Dictionary = tm.engage_monster("regional_manager")
	assert_false(locked["ok"], "the Regional Manager refuses a clearance-14 patrol")
	assert_string_contains(str(locked["reason"]), "CLEARANCE 40 REQUIRED",
		"the refusal names the required grade")

	# ---- ZONE 1 — The Superintendent, the §2 intended loadout: slice-max
	# gear (Majority Whip + Carpool Carapace) + Radstag Stews.
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 20)
	assert_true(tm.equip_item("majority_whip")["ok"])
	assert_true(tm.equip_item("carpool_carapace")["ok"])
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "the Superintendent engages")
	var guard := 0
	while String(tm.state.combat["phase"]) == "fighting" and guard < 700:
		_pump(tm, 2_000)
		guard += 1
	assert_eq(String(tm.state.combat["phase"]), "victory", "ZONE 1 cleared (guard %d)" % guard)
	assert_true(bool(tm.state.combat["zone_clear"]), "the persisted Sunny zone flag set")
	assert_true(tm.is_objective_stamped("combat_secure_flats"),
		"SECURE THE SUNNY ZONE stamped on the real boss kill")
	assert_eq(int(tm.state.objectives["counters"].get("zone:dusty_flats", 0)), 1,
		"the Superintendent kill counted toward its 5-kill rung")
	assert_eq(int(tm.state.objectives["counters"].get("monster:sewer_landlord", 0)), 1,
		"SUPERINTENDENT 5 reads an honest 1/5")

	# ---- ZONE 2 — The Regional Manager, the §2.1 intended loadout: the T4
	# ladder (Cloture + Turnpike Aegis — the 25W/0L heavy set) + Court Feast,
	# at the real clearance-40 gate.
	tm.engine.grant_xp(tm.state, "wasteland_combat", lib.xp_curve("standard_99").total_xp_to_reach(40), true)
	assert_eq(int(tm.state.skills_level["wasteland_combat"]), 40, "the gate crossed on the shared XP pipeline")
	tm.state.add_item("cloture", 1)
	tm.state.add_item("turnpike_aegis", 1)
	tm.state.add_item("court_feast", 20)
	assert_true(tm.equip_item("cloture")["ok"], "the T4 heavy weapon equips")
	assert_true(tm.equip_item("turnpike_aegis")["ok"], "the T4 heavy armor equips (stamps its own rung)")
	assert_true(tm.is_objective_stamped("combat_equip_aegis"),
		"EQUIP TURNPIKE AEGIS stamped by the real T4 equip")
	var stats: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(int(stats["max_hit"]), 4 + lib.equipment_for("cloture").max_hit_bonus,
		"the T4 weapon's max hit posts from equipment data")
	assert_eq(int(stats["accuracy"]), 30 + lib.equipment_for("cloture").accuracy_bonus
			+ lib.equipment_for("turnpike_aegis").accuracy_bonus,
		"accuracy is additive from BOTH T4 slots, data-derived")
	assert_true(tm.engage_monster("regional_manager")["ok"], "the Regional Manager engages at 40")
	guard = 0
	while String(tm.state.combat["phase"]) == "fighting" and guard < 900:
		_pump(tm, 2_000)
		guard += 1
	assert_eq(String(tm.state.combat["phase"]), "victory", "ZONE 2 cleared with T4 gear (guard %d)" % guard)
	assert_gte(int(tm.state.objectives["counters"].get("zone:gift_court", 0)), 1,
		"the Gift Court zone counter counted the boss defeat")
	assert_true(tm.is_objective_stamped("combat_secure_court"),
		"SECURE THE GIFT COURT stamped on the real second-boss kill")
	assert_eq(int(tm.state.objectives["counters"].get("monster:regional_manager", 0)), 1,
		"REGIONAL MANAGER 3 reads an honest 1/3")

	# Wallet: this journey never sold — every Crown is auto-granted merit.
	assert_eq(int(tm.state.crowns), _merit_posted(tm),
		"both zone clearances paid through the wallet exactly (%d cr of merit)" % int(tm.state.crowns))
	assert_gte(_stamped_count(tm), 10, "the two win moments head a real stack of stamped rungs")


# ---------------------------------------------------------------------------
# R5 — the depth journey: tier-7 gathering, T4 weapon end to end
# ---------------------------------------------------------------------------

func test_r5_depth_journey_tier7_activity_to_T4_weapon() -> void:
	var tm: Variant = _make_tm()
	var lib := _lib()

	# ---- TRAIN scavenging tier by tier: the first crossing LIVE (the hook),
	# then real offline windows per tier, every gate crossed by duty.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "tier 1 posts live")
	_pump_until(tm, func() -> bool: return int(tm.state.skills_level["scavenging"]) >= 2)
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "the hook's own first crossing")
	# The tier ladder: (activity, gate it trains TOWARD).
	var ladder := [
		["sort_scrap_pile", 5], ["strip_wreck", 10], ["drain_the_sump", 16],
		["unbuild_the_overpass", 22], ["sweep_service_corridors", 30],
		["pry_mezzanine_lockers", 41],
	]
	for pair in ladder:
		var guard := 0
		while int(tm.state.skills_level["scavenging"]) < pair[1] and guard < 240:
			tm.stop_skill("scavenging")
			assert_true(tm.start_activity(pair[0])["ok"], "the posting climbs to %s (gate %d)" % pair)
			tm.apply_offline_elapsed(int(lib.activity(pair[0]).interval_ms) * 10)
			guard += 1
		assert_gte(int(tm.state.skills_level["scavenging"]), pair[1],
			"clearance %d crossed by real %s duty (%d windows)" % [pair[1], pair[0], guard])
	assert_true(tm.is_objective_stamped("scav_clearance_41"),
		"the tier-7 gate's own rung stamped on the way up")

	# ---- THE NEW TIER-7 ACTIVITY: Deconstruct the Signal Tower posts at
	# clearance 41 and its windows bank the deep-D materials.
	assert_true(tm.start_activity("deconstruct_signal_tower")["ok"],
		"the NEW tier-7 activity accepts the trained resident")
	tm.apply_offline_elapsed(400_000)  # ~35 actions
	assert_gte(int(tm.state.objectives["counters"].get("activity:deconstruct_signal_tower", 0)), 25,
		"the tier-7 activity executed real actions")
	assert_eq(tm.objectives.progress(tm.state, "scav_signal_150")["target"], 150,
		"its count rung is honestly open (not stamped by 35 actions)")
	# Every T4 chain input was GATHERED by the training + tier-7 windows.
	for item_id in ["scrap_metal", "girderling", "heritage_hardware", "counterweight",
			"survey_lens", "directive_cord"]:
		assert_gt(tm.state.item_count(item_id), 0,
			"the duty banked %s — the craft chain's inputs are real gathers" % item_id)

	# ---- Junksmithing clearances through the shared XP pipeline (the same
	# seam every craft's XP flows through — R1's T23 zone-test precedent; the
	# CHAIN below is the crafted path under certification).
	tm.stop_skill("scavenging")
	tm.engine.grant_xp(tm.state, "junksmithing", lib.xp_curve("standard_99").total_xp_to_reach(34), true)
	assert_gte(int(tm.state.skills_level["junksmithing"]), 34, "the smithy holds the veto's gate")

	# ---- THE CRAFT CHAIN, material -> alloy -> weapon, every step a REAL
	# crafting window consuming real inputs:
	#   Scrapnel x3 -> [smelt] Almost Bullion x8
	#   Almost Bullion x2 + Girderling -> [smelt] Quorum Alloy x4
	#   Quorum Alloy x2 + Heritage Hardware x2 + Counterweight -> [smelt] Unanimous Steel x2
	#   Unanimous Steel x2 + Survey Lens x2 + Directive Cord -> [enact] LINE-ITEM VETO x1
	var ingot0 := int(tm.state.inventory.get("scrap_ingot", 0))
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"], "the chain posts: Smelt Almost Bullion")
	var guard := 0
	while int(tm.state.inventory.get("scrap_ingot", 0)) < ingot0 + 8 and guard < 40:
		tm.apply_offline_elapsed(4_500)
		guard += 1
	assert_gte(int(tm.state.inventory.get("scrap_ingot", 0)), ingot0 + 8,
		"8 Almost Bullion smelted from gathered Scrapnel (%d windows)" % guard)
	tm.stop_skill("junksmithing")

	assert_true(tm.start_activity("smelt_quorum_alloy")["ok"], "the alloy step posts")
	guard = 0
	while int(tm.state.inventory.get("quorum_alloy", 0)) < 4 and guard < 20:
		tm.apply_offline_elapsed(7_000)
		guard += 1
	assert_gte(int(tm.state.inventory.get("quorum_alloy", 0)), 4, "4 Quorum Alloy smelted")
	tm.stop_skill("junksmithing")

	assert_true(tm.start_activity("smelt_unanimous_steel")["ok"], "the steel step posts")
	guard = 0
	while int(tm.state.inventory.get("unanimous_steel", 0)) < 2 and guard < 20:
		tm.apply_offline_elapsed(10_000)
		guard += 1
	assert_gte(int(tm.state.inventory.get("unanimous_steel", 0)), 2, "2 Unanimous Steel smelted")
	tm.stop_skill("junksmithing")

	assert_true(tm.start_activity("enact_line_item_veto")["ok"], "the weapon step posts")
	tm.apply_offline_elapsed(10_500)  # one 10 s craft — exactly the interval
	assert_eq(int(tm.state.inventory.get("line_item_veto", 0)), 1,
		"the T4 weapon ENACTED: exactly one Line-Item Veto crafted")
	tm.stop_skill("junksmithing")

	# ---- EQUIP it; derived stats change by the equipment data exactly.
	var bare: Dictionary = tm.combat.derived_stats(tm.state)
	assert_eq(int(bare["accuracy"]), 30, "bare accuracy is the chassis baseline")
	assert_eq(int(bare["max_hit"]), 4, "bare max hit is the chassis baseline")
	assert_eq(int(bare["speed"]), 3000, "bare speed is the chassis baseline")
	assert_true(tm.equip_item("line_item_veto")["ok"], "EQUIP the crafted T4 weapon")
	var geared: Dictionary = tm.combat.derived_stats(tm.state)
	var veto := lib.equipment_for("line_item_veto")
	assert_eq(int(geared["accuracy"]), 30 + veto.accuracy_bonus,
		"accuracy changed by the data bonus (+%d)" % veto.accuracy_bonus)
	assert_eq(int(geared["max_hit"]), 4 + veto.max_hit_bonus,
		"max hit changed by the data bonus (+%d)" % veto.max_hit_bonus)
	assert_eq(int(geared["speed"]), veto.attack_speed_ms,
		"the weapon's attack speed REPLACES the chassis baseline (%d ms)" % veto.attack_speed_ms)
	assert_true(tm.is_objective_stamped("combat_equip_veto"),
		"EQUIP LINE-ITEM VETO stamped by the real equip of the real craft")

	# Wallet: no sales on this journey — merit only, exact.
	assert_eq(int(tm.state.crowns), _merit_posted(tm),
		"the depth journey's rungs paid through the wallet exactly (%d cr)" % int(tm.state.crowns))


# ---------------------------------------------------------------------------
# R6 — v2 -> v3 objectives migration through the real SaveStore
# ---------------------------------------------------------------------------

func test_r6_v2_to_v3_migration_journey() -> void:
	var dir := _tmp_dir("r6_v2")
	var lib := _lib()
	# Play a v3-era resident: a real gathered clearance 5 + a real tender.
	var tm1: Variant = _make_tm()
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump_until(tm1, func() -> bool: return int(tm1.state.skills_level["scavenging"]) >= 5)
	tm1.stop_skill("scavenging")
	assert_gte(tm1.state.item_count("scrap_metal"), 30, "the shift banked a tender")
	assert_true(tm1.depot_sell("scrap_metal")["ok"], "a real Depot tender")
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW)["ok"], "the record files (v3)")
	var crowns_at_file := int(tm1.state.crowns)

	# Degrade to the honest v2 shape: save_version 2, no objectives namespace.
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["save_version"] = 2
	doc["engine"].erase("objectives")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()

	# ---- load: the documented migration policy, exactly.
	var tm2: Variant = _make_tm()
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2.quit_after_save = false
	store2._boot(dir, tm2, NOW + 1_000)
	assert_true(tm2.is_objective_stamped("scav_clearance_2"),
		"the derivable grade-2 rung stamps at adopt (clearance 5 proved from xp)")
	assert_true(tm2.is_objective_stamped("scav_clearance_5"),
		"the derivable grade-5 rung stamps likewise")
	assert_false(tm2.is_objective_stamped("scav_sort_25"),
		"per-activity counts are NOT derivable: honest zero, rung open")
	assert_eq(int(tm2.state.objectives["counters"].get("activity:sort_scrap_pile", 0)), 0,
		"the zero-counters migration policy, verbatim")
	assert_eq(int(tm2.state.objectives["counters"].get("level:scavenging", 0)), 5,
		"the derivable grade synced into the counters")
	assert_eq(int(tm2.state.objectives["counters"].get("crowns", 0)), 4 + 5,
		"lifetime crowns zeroed, then the two derivable rewards posted (earned)")
	assert_eq(int(tm2.state.crowns), crowns_at_file + 4 + 5,
		"banked Crowns kept + the derivable rewards posted EXACTLY once")

	# ---- the counters resume honestly from zero: one more window re-advances.
	assert_true(tm2.start_activity("sort_scrap_pile")["ok"], "the migrated resident re-posts")
	tm2.apply_offline_elapsed(300_000)  # ~100 actions
	assert_gte(int(tm2.state.objectives["counters"].get("activity:sort_scrap_pile", 0)), 90,
		"the counter re-advances by real duty from its honest zero")
	assert_true(tm2.is_objective_stamped("scav_sort_25"),
		"the reopened rung stamps on its own evidence")

	# ---- the record re-files v3 with the namespace intact.
	assert_true(store2.save_now(NOW + 2_000)["ok"], "the migrated record re-files")
	var redoc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(redoc["save_version"]), 3, "the re-filed record is v3")
	assert_true((redoc["engine"]["objectives"]["stamped"] as Array).has("scav_sort_25"),
		"the post-migration stamp persisted")


# ---------------------------------------------------------------------------
# R7 — the fresh-save first fifteen minutes: the onboarding cascade
# ---------------------------------------------------------------------------

## One rotation of real duty on ONE posting (a genuine new resident's path):
## by minute 7 the dossier has stamped >= 8 rungs (the T27 §6.4 model's
## ">= 8 rungs by minute 7"); the ORIENTATION FORM O-1 completes at the real
## deputize with the stipend posted exactly once; merit pay reaches the §6.4
## early-feel pin (>= 35 cr) by minute 15.
func test_r7_fresh_save_first_fifteen_minutes_onboarding_cascade() -> void:
	var tm: Variant = _make_tm()
	var stamp_log: Array = []
	tm.objective_stamped.connect(func(payload: Dictionary) -> void: stamp_log.append(String(payload["id"])))

	# ---- minute 0-2: the first posting, the first clearance, the first count rung.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "WORK A POSTED SHIFT: the first posting")
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("scav_clearance_2"))
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("scav_sort_25"))
	assert_true(tm.orientation_step_done_bool("work_shift"), "O-1: the shift stamped its step")
	assert_true(tm.orientation_step_done_bool("earn_clearance"), "O-1: the clearance stamped its step")

	# ---- minute 2-4: rotate through every department's first rung — the
	# cascade the model prices as recognition (4-6 cr each).
	tm.stop_skill("scavenging")
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
	_pump_until(tm, func() -> bool: return tm.state.item_count("duskcorn") >= 8 and tm.is_objective_stamped("forage_clearance_2"))
	tm.stop_skill("foraging")
	assert_true(tm.start_activity("grind_mandatory_grits")["ok"], "the mess takes the posting")
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("cook_clearance_2"))
	assert_true(tm.orientation_step_done_bool("provision_patrol"),
		"O-1: the cooked grits provision the patrol (the cook leg)")
	tm.stop_skill("cooking")
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"])
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("junk_clearance_2"))
	assert_true(tm.orientation_step_done_bool("process_product"), "O-1: the craft stamped its step")
	tm.stop_skill("junksmithing")

	# ---- the first victory: CLEAR A NUISANCE + the combat rung.
	var guard := 0
	while String(tm.state.combat["phase"]) != "victory" and guard < 60:
		if String(tm.state.combat["phase"]) != "fighting":
			assert_true(tm.engage_monster("junkyard_roach")["ok"], "ENGAGE the Litterbug")
		_pump(tm, 20_000, 2_000)
		guard += 1
	assert_eq(String(tm.state.combat["phase"]), "victory", "the first victory landed (guard %d)" % guard)
	tm.stop_combat()
	assert_true(tm.is_objective_stamped("combat_clearance_2"), "the combat dossier's first rung stamped")
	assert_true(tm.orientation_step_done_bool("clear_nuisance"), "O-1: the victory stamped its step")

	# ---- back to the tier-1 ladder: clearance 5 + the glow count rung.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("scav_clearance_5"))
	tm.stop_skill("scavenging")
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
	_pump_until(tm, func() -> bool: return tm.is_objective_stamped("forage_glow_25"))
	tm.stop_skill("foraging")

	# ---- THE MINUTE-7 BAR: >= 8 rungs stamped inside the first 7 minutes.
	assert_lte(int(tm.sim_time_ms), 7 * MIN_MS,
		"the rotation reached its eighth rung by minute 7 (sim %d ms)" % int(tm.sim_time_ms))
	assert_gte(_stamped_count(tm), 8,
		"AMENDMENT PIN: >= 8 dossier rungs stamped by minute 7 (got %d)" % _stamped_count(tm))
	assert_gte(stamp_log.size(), 8, "eight-plus real objective_stamped notices posted")

	# ---- minute 7-14: earn the deputy — sort, smelt, and SELL at the Depot
	# until the 300-Crown rung is affordable on first-session income.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	guard = 0
	while int(tm.state.crowns) < 300 and guard < 120:
		_pump(tm, 10_000, 1_000)
		if tm.state.item_count("scrap_metal") >= 60:
			assert_true(tm.depot_sell("scrap_metal")["ok"], "tender the banked Scrapnel stack")
		guard += 1
	assert_gte(int(tm.state.crowns), 300,
		"first-session income (duty + merit) reached the deputy's price (guard %d)" % guard)
	assert_true(tm.orientation_step_done_bool("file_crowns_claim"), "O-1: the tender stamped its step")
	assert_lte(int(tm.sim_time_ms), 15 * MIN_MS, "the price was reachable inside the session")

	# ---- the seventh O-1 step IS the deputize — completion + stipend once.
	var wallet_at_purchase := int(tm.state.crowns)
	var completed: Array = []
	tm.orientation_completed.connect(func(payload: Dictionary) -> void: completed.append(payload))
	var deputized: Dictionary = tm.deputize_resident()
	assert_true(deputized["ok"], "DEPUTIZE RESIDENT through the real purchase path")
	assert_eq(int(deputized["price"]), 300, "rung 1 at the T27-retuned data price")
	assert_eq(completed.size(), 1, "orientation_completed fired EXACTLY once")
	assert_eq(int(tm.state.crowns), wallet_at_purchase - 300 + 150,
		"crowns moved by EXACTLY -price +stipend (net +150 at the seventh stamp)")
	assert_true(bool(tm.state.orientation["stipend_claimed"]), "the stipend claimed exactly once")

	# ---- THE MINUTE-15 PIN: merit pay >= 35 cr (the §6.4 early-feel pin).
	var merit := _merit_posted(tm)
	assert_gte(merit, 35, "merit pay by minute 15 >= 35 cr (the early-feel pin; got %d)" % merit)
	assert_lte(int(tm.sim_time_ms), 15 * MIN_MS,
		"the whole cascade lived inside the first fifteen minutes (sim %d ms)" % int(tm.sim_time_ms))
	# Every Crown in the wallet is tender income or auto-granted merit — exact.
	var sold_value := int(tm.state.objectives["counters"].get("crowns", 0)) - merit - 150
	assert_eq(int(tm.state.crowns), sold_value + merit + 150 - 300,
		"the 15-minute wallet reconciles: tenders + merit + stipend - the deputy price")
