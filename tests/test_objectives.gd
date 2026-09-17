extends GutTest
## tests/test_objectives.gd — T23 DEPARTMENTAL DOSSIER engine validation
## (Iron Man architecture + Hulk resilience lens).
##
## The T23 acceptance matrix, all headless:
##   (a) every condition kind stamps from the REAL engine event that earns
##       it (level crossing, gather action + gather yield, craft, kill,
##       sell, equip, boss zone-clear, set-completion cascade, lifetime
##       crowns) — including the reserved gift_court zone id;
##   (b) auto-grant exactly once: idempotent evaluation, save/load round
##       trip never re-rewards;
##   (c) reward paths: MERIT PAY through the wallet (exact deltas),
##       COMMENDATION through the shared XP pipeline incl. a level crossing
##       and a cross-skill leg; the T22 reward-line/notice formats;
##   (d) offline settlement: gather/craft counters exact through the shared
##       _execute_action (live twin vs offline twin), kills + levels settle
##       from the mail-call payload, stamps + reward legs fold into
##       payload.objectives / skills_xp / levels;
##   (e) migrations: v2->v3 drill (zero-counters policy + derivable level
##       sync, documented), the intact v1->v2->v3 chain, mangled-namespace
##       validation drills, in-place repair;
##   (f) loader defect drills (13 beyond the shipped probe set, each
##       asserting the T2 error grammar: record id + field + reason);
##   (g) per-skill dossier grouping + the shipped-set contract.
##
## Fixture discipline: T23 proved the engine on a FIXTURE library (full data/
## copy + a 14-objective set covering every kind) through the injectable
## ContentLoader.load_all(dir) + _boot(lib, seed) seams; T25 authors the
## SHIPPED set (23 objectives per skill) and this suite extends with
## engine-driven spot tests against that real set (pacing, the full-dossier
## stamped_count cascade, an unresolvable-ref loader drill) plus the
## amendment-floor contract. Determinism: explicit seeds, never in the tree,
## advance_wall_ms only.

const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260923
const NOW := 1_768_000_000_000
const DOMAIN_FILES := [
	"items.json", "skills.json", "activities.json", "recipes.json",
	"drop_tables.json", "monsters.json", "equipment.json", "shop_stock.json",
	"xp_curves.json", "staffing.json", "zones.json",
]

## The fixture dossier set — one objective per condition kind, voice-rule
## clean (verb-first, <= 6 words, no "!"), bible names only. Ids are stable
## per this suite; file order IS the canonical posted order under test.
const FIXTURE_OBJECTIVES := [
	{"id": "scav_grade_2", "skill": "scavenging", "description": "EARN CLEARANCE 2",
		"condition": {"kind": "level_reach", "target": 2}, "reward": {"crowns": 10}},
	{"id": "scav_sort_20", "skill": "scavenging", "description": "SORT THE SCRAP PILE 20",
		"condition": {"kind": "gather_count", "ref": "sort_scrap_pile", "target": 20},
		"reward": {"crowns": 25, "xp": {"skill": "scavenging", "amount": 60}}},
	{"id": "scav_gather_25", "skill": "scavenging", "description": "GATHER 25 SCRAPNEL",
		"condition": {"kind": "gather_count", "ref": "scrap_metal", "target": 25},
		"reward": {"crowns": 15}},
	{"id": "scav_sell_20", "skill": "scavenging", "description": "SELL 20 SCRAPNEL",
		"condition": {"kind": "sell_count", "ref": "scrap_metal", "target": 20},
		"reward": {"crowns": 20}},
	{"id": "scav_stamped_all", "skill": "scavenging", "description": "STAMP 4 DUTIES",
		"condition": {"kind": "stamped_count", "target": 4}, "reward": {"crowns": 50}},
	{"id": "junk_smelt_5", "skill": "junksmithing", "description": "SMELT 5 ALMOST BULLION",
		"condition": {"kind": "craft_count", "ref": "smelt_scrap_ingot", "target": 5},
		"reward": {"crowns": 30}},
	{"id": "cook_grits_3", "skill": "cooking", "description": "GRIND 3 MANDATORY GRITS",
		"condition": {"kind": "craft_count", "ref": "grind_mandatory_grits", "target": 3},
		"reward": {"xp": {"skill": "junksmithing", "amount": 40}}},
	{"id": "combat_grade_3", "skill": "wasteland_combat", "description": "EARN CLEARANCE 3",
		"condition": {"kind": "level_reach", "target": 3}, "reward": {"crowns": 20}},
	{"id": "combat_litterbugs_2", "skill": "wasteland_combat", "description": "CLEAR 2 LITTERBUGS",
		"condition": {"kind": "kill_count", "ref": "junkyard_roach", "target": 2},
		"reward": {"xp": {"skill": "wasteland_combat", "amount": 30}}},
	{"id": "combat_equip_shiv", "skill": "wasteland_combat", "description": "EQUIP POINT OF ORDER",
		"condition": {"kind": "equip_item", "ref": "scrap_shiv", "target": 1},
		"reward": {"crowns": 15}},
	{"id": "combat_secure_flats", "skill": "wasteland_combat", "description": "SECURE THE SUNNY ZONE",
		"condition": {"kind": "zone_clear", "ref": "dusty_flats", "target": 1},
		"reward": {"crowns": 200}},
	{"id": "combat_secure_court", "skill": "wasteland_combat", "description": "SECURE THE GIFT COURT",
		"condition": {"kind": "zone_clear", "ref": "gift_court", "target": 1},
		"reward": {"crowns": 300}},
	{"id": "forage_crowns_60", "skill": "foraging", "description": "EARN 60 CROWNS",
		"condition": {"kind": "crowns_total", "target": 60}, "reward": {"crowns": 25}},
	{"id": "forage_duskcorn_5", "skill": "foraging", "description": "GATHER 5 DUSKCORN",
		"condition": {"kind": "gather_count", "ref": "duskcorn", "target": 5},
		"reward": {"crowns": 10}},
]


# ----------------------------------------------------------------- fixtures --

func _tmp_dir(label: String) -> String:
	var dir := OS.get_user_data_dir().path_join("t23_objectives/%s_%d" % [label, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## Full data/ copy + a fixture objectives.json (or a mutated data file for
## drills: `mutate_file` names the file, `mutate` maps its parsed doc).
func _fixture_dir(label: String, objectives: Variant = FIXTURE_OBJECTIVES,
		mutate_file := "", mutate: Callable = Callable()) -> String:
	var dir := _tmp_dir(label)
	for file_name in DOMAIN_FILES:
		DirAccess.copy_absolute("res://data/%s" % file_name, dir.path_join(file_name))
	if mutate_file != "" and mutate.is_valid():
		var other: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(mutate_file)))
		var mf := FileAccess.open(dir.path_join(mutate_file), FileAccess.WRITE)
		mf.store_string(JSON.stringify(mutate.call(other), "\t"))
		mf.close()
	var f := FileAccess.open(dir.path_join("objectives.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 1, "objectives": objectives}, "\t"))
	f.close()
	return dir


func _fixture_lib(dir: String) -> ContentLibrary:
	var result = ContentLoader.load_all(dir)
	assert_true(result.ok(), "fixture content loads (errors: %s)" % str(result.errors))
	assert_not_null(result.library, "fixture library hydrates")
	return result.library


func _make_tm(lib: ContentLibrary, seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(lib, seed)
	return tm


func _pump(tm: Variant, total_ms: int, chunk_ms := 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


# ---------------------------------------------------------------------------
# (g) shipped-set contract + fixture grouping
# ---------------------------------------------------------------------------

## The T25-authored set, parsed from the shipped file (each call re-reads, so
## drill mutations never contaminate other tests).
func _shipped_objectives() -> Array:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/objectives.json"))
	return doc["objectives"]


func test_shipped_set_meets_the_amendment_floor() -> void:
	var result = ContentLoader.load_all()
	assert_true(result.ok(), "the live set loads clean with the authored dossier set (errors: %s)" % str(result.errors))
	var lib: ContentLibrary = result.library
	assert_eq(lib.zones.size(), 2, "both run-3 zone ids ship in zones.json")
	assert_not_null(lib.zone("dusty_flats"), "dusty_flats resolves")
	assert_not_null(lib.zone("gift_court"), "gift_court resolves with T24 fauna")
	# THE Scope Amendment 2 hard acceptance: >= 20 per skill, >= 100 total
	# (probe-pinned too; this is the suite-side contract).
	assert_gte(lib.objectives.size(), 100, "the shipped set carries >= 100 objectives (got %d)" % lib.objectives.size())
	for skill in lib.skills.values():
		assert_gte(lib.objectives_for_skill(skill.id).size(), 20,
			"dossier '%s' carries >= 20 objectives (got %d)" % [skill.id, lib.objectives_for_skill(skill.id).size()])
	# Voice rules as loader law, swept test-side on every description: <= 6
	# words, no "!", plate idiom (stencil caps — lowercase prose is the banned
	# pattern's first symptom). Verb-first + bible names are the §13.1
	# Class-A registration claim (naming-bible §10 T25 row).
	for obj in lib.objectives.values():
		var description := String(obj.description)
		assert_lte(description.split(" ", false).size(), 6,
			"<= 6 words ('%s' — Addendum 2 hard cap)" % description)
		assert_false(description.contains("!", ), "no exclamation point ('%s')" % description)
		assert_eq(description, description.to_upper(), "plate idiom: stencil caps ('%s')" % description)


# ---------------------------------------------------------------------------
# (h) T25 spot tests — the authored set through the real engine
# ---------------------------------------------------------------------------

## Pacing sanity: the early rungs stamp within MINUTES of simulated fresh
## play on one posting — rungs, not walls. The staged checks ride the §3
## hook arithmetic (first level-up 6 s; clearance 5 at 425 XP ~= minute 2.2;
## 100 actions of tier-1 gathering by minute 5).
func test_shipped_early_rungs_stamp_within_first_minutes() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("shipped_pacing", _shipped_objectives())))
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "fresh posting on tier 1")
	# 6 s — the hook's own pace: 2 actions x 10 XP crosses level 2 (20 XP).
	_pump(tm, 6_000)
	assert_true(tm.is_objective_stamped("scav_clearance_2"),
		"EARN CLEARANCE 2 stamped at the 6-s first-level-up pace")
	# 90 s — 30 actions: the first count rung lands in ~75 s of duty.
	_pump(tm, 84_000)
	assert_true(tm.is_objective_stamped("scav_sort_25"),
		"SORT THE SCRAP PILE 25 stamped inside the first 2 minutes")
	# 5 min — 100 actions = 1,000 XP = level 6 (the §3 five-level hook).
	_pump(tm, 210_000)
	assert_true(tm.is_objective_stamped("scav_clearance_5"),
		"EARN CLEARANCE 5 stamped by minute 5 of tier-1 duty")
	assert_eq(int(tm.state.skills_level["scavenging"]), 6, "1,000 XP = level 6, the hook arithmetic intact")
	# The next rung is honestly open at exactly 100/250 — a rung, not a wall.
	assert_eq(tm.objectives.progress(tm.state, "scav_sort_250"), {"current": 100, "target": 250, "stamped": false},
		"the 250 rung reads exactly 100/250 at minute 5")
	# Honesty sweep: nothing outside the played dossier moved; the tier-5
	# material rung reads a true 0 (no tier-1 table yields Girderling).
	assert_false(tm.is_objective_stamped("forage_clearance_2"), "an unplayed dossier stamps nothing")
	assert_eq(tm.objectives.progress(tm.state, "scav_girderling_100")["current"], 0,
		"GATHER 100 GIRDERLING reads 0 at tier 1 — the counter tracks yields, not wishes")
	assert_eq(int(tm.state.crowns), 30 + 25 + 50,
		"three MERIT PAY legs posted exactly (grade 2, sort 25, grade 5)")


## The meta cascade across a REAL skill's set: every one of scavenging's 23
## authored objectives stamps through real engine seams (level crossings via
## grant_xp's level_up hook; gather counts + item yields through the shared
## _execute_action on offline windows — counters exact by construction; the
## sale through depot_sell), and the 22nd stamp cascades STAMP 22 RECLAMATION
## DUTIES in the same evaluation pass.
func test_shipped_full_dossier_cascade_across_real_set() -> void:
	var dir := _fixture_dir("shipped_cascade", _shipped_objectives())
	var lib := _fixture_lib(dir)
	var tm: Variant = _make_tm(lib)
	var dossiers: Array = []
	tm.dossier_completed.connect(func(payload: Dictionary) -> void: dossiers.append(payload))

	# The 8-rung ladder (clearances 2..70): every crossing feeds the max-grade
	# counter through the real level_up hook.
	tm.engine.grant_xp(tm.state, "scavenging", lib.xp_curve("standard_99").total_xp_to_reach(70), true)
	for grade in [2, 5, 10, 16, 30, 41, 54, 70]:
		assert_true(tm.is_objective_stamped("scav_clearance_%d" % grade),
			"the clearance-%d ladder rung stamped on the level-up path" % grade)

	# The 10 activity counts + 2 item-yield counts: one offline window per
	# activity (target actions + slack; the sump/signal windows are sized for
	# the Girderling/Counterweight item rungs on their rich tables). Offline
	# settlement maintains counters inside the shared _execute_action — the
	# live/offline twin-exactness seam T23 pinned.
	var windows := [
		["sort_scrap_pile", 765_000],       # 250 rung (>= 255 actions)
		["strip_wreck", 260_000],           # 50 rung
		["drain_the_sump", 6_000_000],      # 40 rung + 100 Girderling (15%/action)
		["unbuild_the_overpass", 465_000],  # 60 rung
		["sweep_service_corridors", 654_500],  # 75 rung
		["pry_mezzanine_lockers", 1_020_000],  # 100 rung
		["deconstruct_signal_tower", 4_200_000],  # 150 rung + 250 Counterweights
		["excavate_foundation_grid", 2_626_000],  # 200 rung
		["audit_archive_vault", 3_795_000],       # 250 rung
	]
	for pair in windows:
		tm.stop_skill("scavenging")  # one posting on the record; rotate it
		assert_true(tm.start_activity(pair[0])["ok"], "posting rotates to %s" % pair[0])
		tm.apply_offline_elapsed(pair[1])
	for rung in ["scav_sort_25", "scav_sort_250", "scav_strip_50", "scav_sump_40",
			"scav_overpass_60", "scav_corridors_75", "scav_lockers_100", "scav_signal_150",
			"scav_foundation_200", "scav_strongroom_250", "scav_girderling_100",
			"scav_counterweight_250"]:
		assert_true(tm.is_objective_stamped(rung), "%s stamped by its window" % rung)
	# Lifetime Crowns crossed 5,000 on MERIT PAY alone (~8,800 posted by now).
	assert_true(tm.is_objective_stamped("scav_crowns_5000"),
		"EARN 5,000 CROWNS stamped — merit pay is earned income")
	assert_true(int(tm.state.objectives["counters"].get("crowns", 0)) >= 5_000,
		"the crowns counter reads the honest lifetime total")

	# The 22nd stamp — the sale — cascades the set-completion meta in the SAME
	# evaluation pass (21 stamped before it: 8 ladder + 10 counts + 2 items
	# + the crowns rung).
	tm.stop_skill("scavenging")
	var stash := int(tm.state.inventory.get("scrap_metal", 0))
	assert_gt(stash, 0, "the windows banked a real Scrapnel surplus")
	if stash < 1_000:
		tm.state.add_item("scrap_metal", 1_000 - stash)
	assert_true(tm.depot_sell("scrap_metal", 1_000)["ok"], "the final event: a 1,000-unit tender")
	assert_true(tm.is_objective_stamped("scav_sell_scrap_1000"), "SELL 1,000 SCRAPNEL stamped")
	assert_true(tm.is_objective_stamped("scav_stamped_22"),
		"the meta rung cascaded in the same pass — the 22nd stamp completes the set")
	assert_eq(dossiers.size(), 1, "dossier_completed fired once for scavenging")
	assert_eq(String(dossiers[0]["skill"]), "scavenging", "completion payload names the dossier")
	assert_eq(int(dossiers[0]["total"]), 23, "total from data (23 authored objectives)")
	assert_eq(String(dossiers[0]["stamp_line"]), "ALL 23 STAMPED · FORM R-1", "the T22 completion stamp, count from data")
	assert_eq(int(tm.state.objectives["counters"].get("stamped:scavenging", 0)), 23,
		"the derived per-skill stamp counter rebuilt to 23")
	assert_eq(tm.state.objectives["rewards_granted"], tm.state.objectives["stamped"],
		"every stamp in the completed dossier granted its rewards")
	# Other dossiers stay honestly open — their sets were never touched.
	assert_false(tm.is_objective_stamped("forage_stamped_22"),
		"the foraging meta rung stays open (its set untouched)")


## The loader drill against the SHIPPED set: a deliberately unresolvable
## condition ref is rejected in the T2 error grammar (record id + field +
## reason), and a stamped_count target over the real per-skill ceiling is
## unreachable by construction.
func test_shipped_set_rejects_unresolvable_ref_and_unreachable_set() -> void:
	var ghost := _shipped_objectives()
	for obj in ghost:
		if String(obj["id"]) == "scav_sort_25":
			obj["condition"]["ref"] = "ghost_pile"
	_drill_error("shipped_ghost_ref", ghost,
		"condition.ref: references unknown activities/items id 'ghost_pile'")
	var over := _shipped_objectives()
	for obj in over:
		if String(obj["id"]) == "scav_stamped_22":
			obj["condition"]["target"] = 23  # 23 objectives in the skill -> ceiling 22
	_drill_error("shipped_set_ceiling", over, "the set can never complete")


func test_fixture_grouping_per_skill_in_file_order() -> void:
	var lib := _fixture_lib(_fixture_dir("grouping"))
	assert_eq(lib.objectives.size(), 14, "fixture set hydrates 14 objectives")
	assert_eq(lib.objectives_for_skill("scavenging").map(func(o: ObjectiveDef) -> String: return o.id),
		["scav_grade_2", "scav_sort_20", "scav_gather_25", "scav_sell_20", "scav_stamped_all"],
		"scavenging dossier = file order")
	assert_eq(lib.objectives_for_skill("wasteland_combat").map(func(o: ObjectiveDef) -> String: return o.id),
		["combat_grade_3", "combat_litterbugs_2", "combat_equip_shiv", "combat_secure_flats", "combat_secure_court"],
		"combat dossier = file order")
	assert_eq(lib.objectives_for_skill("foraging").size(), 2, "foraging dossier groups 2")
	assert_eq(lib.objectives_for_skill("junksmithing").size(), 1, "junksmithing dossier groups 1")
	assert_eq(lib.objectives_for_skill("cooking").size(), 1, "cooking dossier groups 1")


# ---------------------------------------------------------------------------
# (a) every condition kind through the real engine
# ---------------------------------------------------------------------------

func test_level_reach_stamps_on_real_level_up() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("level")))
	var notices: Array = []
	tm.objective_stamped.connect(func(payload: Dictionary) -> void: notices.append(payload))
	assert_false(tm.is_objective_stamped("scav_grade_2"), "fresh record: unstamped")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	_pump(tm, 8_000)  # 2 actions x 10 xp -> level 2 at 20 xp (the hook's pace)
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "two actions crossed level 2")
	assert_true(tm.is_objective_stamped("scav_grade_2"), "the level-up path stamps EARN CLEARANCE 2")
	assert_eq(notices.size(), 1, "one notice for the stamp")
	assert_eq(String(notices[0]["kind"]), "objective_stamped", "notice kind is the §15 id")
	assert_eq(String(notices[0]["id"]), "scav_grade_2", "notice carries the objective id")
	assert_eq(String(notices[0]["skill"]), "scavenging", "notice carries the dossier skill")
	assert_eq(String(notices[0]["description"]), "EARN CLEARANCE 2", "notice carries the description")
	assert_eq(String(notices[0]["reward_line"]), "MERIT PAY · 10 CROWNS", "notice carries the T22 reward line")
	assert_eq(int(notices[0]["crowns"]), 10, "notice carries the crowns leg")
	assert_eq(int(tm.state.crowns), 10, "MERIT PAY posted through the wallet")


func test_gather_count_by_activity_and_item() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("gather")))
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	# Deterministic per seed; loop to the crossing with a generous guard.
	var guard := 0
	while not tm.is_objective_stamped("scav_sort_20") and guard < 400:
		_pump(tm, 1_000)
		guard += 1
	assert_true(tm.is_objective_stamped("scav_sort_20"), "20 actions of one activity stamps (pumped %d s)" % guard)
	var counters: Dictionary = tm.state.objectives["counters"]
	var actions := int(counters.get("activity:sort_scrap_pile", 0))
	assert_eq(actions * 10, int(tm.state.skills_xp["scavenging"]) - 60,
		"the activity counter equals completed actions exactly (10 xp/action, minus the 60-xp reward leg)")
	guard = 0
	while not tm.is_objective_stamped("scav_gather_25") and guard < 400:
		_pump(tm, 1_000)
		guard += 1
	assert_true(tm.is_objective_stamped("scav_gather_25"), "25 gathered Scrapnel stamps the item-yield leg")
	# Re-read: every seam's ensure re-houses the counters dict.
	assert_true(int(tm.state.objectives["counters"].get("item_gathered:scrap_metal", 0)) >= 25,
		"the item counter counts units yielded by activity drop rolls")


func test_craft_count_stamps_and_cross_skill_xp_leg() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("craft")))
	tm.state.add_item("scrap_metal", 50)
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"])
	_pump(tm, 22_000)  # 5 crafts at 4 s each
	assert_true(tm.is_objective_stamped("junk_smelt_5"), "5 completed crafts stamp SMELT 5 ALMOST BULLION")
	tm.stop_skill("junksmithing")  # free the posting (one posting on a fresh record)
	var counters: Dictionary = tm.state.objectives["counters"]
	assert_eq(int(counters.get("recipe:smelt_scrap_ingot", 0)), 5, "craft counter = completed crafts")
	# The COOKING objective's COMMENDATION leg pays JUNKSMITHING xp (a
	# cross-skill leg is legal; xp.skill is independent of the dossier).
	tm.state.add_item("duskcorn", 10)
	assert_true(tm.start_activity("grind_mandatory_grits")["ok"])
	_pump(tm, 12_000)  # 3+ grits at 3 s
	assert_true(tm.is_objective_stamped("cook_grits_3"), "3 grits stamp the cooking dossier line")
	assert_eq(int(tm.state.skills_xp["junksmithing"]), 5 * 14 + 40,
		"the xp leg posted 40 junksmithing xp on top of the smelting (5 x 14)")


func test_kill_count_stamps_on_real_victories() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("kill")))
	tm.state.add_item("scrap_shiv", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"])  # faster clears; also stamps its own line
	var kills := 0
	var guard := 0
	while kills < 2 and guard < 200:
		if String(tm.state.combat["phase"]) != "fighting":
			assert_true(tm.engage_monster("junkyard_roach")["ok"])
		_pump(tm, 20_000, 2_000)
		guard += 1
		if String(tm.state.combat["phase"]) == "victory":
			kills += 1
	assert_eq(kills, 2, "two real victories landed (guard %d)" % guard)
	assert_true(tm.is_objective_stamped("combat_litterbugs_2"), "2 Litterbug victories stamp the kill line")
	var counters: Dictionary = tm.state.objectives["counters"]
	assert_eq(int(counters.get("monster:junkyard_roach", 0)), kills, "kill counter = victories")
	assert_eq(int(counters.get("item_equipped:scrap_shiv", 0)), 1, "equip counter counted the real equip")


func test_zone_clear_stamps_on_real_boss_kill_and_stays_zone_scoped() -> void:
	var dir := _fixture_dir("zone")
	var lib := _fixture_lib(dir)
	var tm: Variant = _make_tm(lib)
	# Clearance 14 gates the Superintendent; majority whip + carpool carapace
	# + stews is test_combat's winning boss config (beatable inside 600 s).
	# Live grant (emit_levels=true): every crossing feeds the max-grade
	# counter through the real level_up hook — combat_grade_3 stamps here.
	tm.engine.grant_xp(tm.state, "wasteland_combat", lib.xp_curve("standard_99").total_xp_to_reach(14), true)
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 10)  # survivability (test_combat's boss config)
	assert_true(tm.equip_item("majority_whip")["ok"])
	assert_true(tm.equip_item("carpool_carapace")["ok"])
	var crowns_at_engage := int(tm.state.crowns)
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "boss engages at clearance 14")
	var guard := 0
	while String(tm.state.combat["phase"]) == "fighting" and guard < 350:
		_pump(tm, 2_000)
		guard += 1
	assert_eq(String(tm.state.combat["phase"]), "victory", "the Superintendent cleared (guard %d)" % guard)
	assert_true(tm.is_objective_stamped("combat_secure_flats"), "a real boss kill stamps SECURE THE SUNNY ZONE")
	# Honest reward cascade, all deterministic: the boss kill posts the zone
	# line's 200 MERIT PAY, which pushes lifetime Crowns past 60 (+25 more).
	assert_eq(int(tm.state.crowns) - crowns_at_engage, 200 + 25,
		"zone + lifetime-crowns rewards posted exactly once each")
	# Zone-scoped: the reserved gift_court line stays open — a dusty_flats
	# clear proves nothing about the Gift Court (its fauna is T24's).
	assert_false(tm.is_objective_stamped("combat_secure_court"),
		"the gift_court objective exists, resolves, and stays honestly open at 0/1")
	var prog: Dictionary = tm.objectives.progress(tm.state, "combat_secure_court")
	assert_eq(prog, {"current": 0, "target": 1, "stamped": false}, "gift_court progress reads 0/1")


func test_sell_count_and_lifetime_crowns_total() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("sell")))
	tm.state.add_item("scrap_metal", 60)
	assert_true(tm.depot_sell("scrap_metal", 20)["ok"], "one tender: exactly 20 units")
	assert_true(tm.is_objective_stamped("scav_sell_20"), "20 units tendered stamp SELL 20 SCRAPNEL")
	var counters: Dictionary = tm.state.objectives["counters"]
	assert_eq(int(counters.get("item_sold:scrap_metal", 0)), 20, "sell counter = units tendered")
	assert_eq(int(counters.get("crowns", 0)), 85,
		"lifetime crowns = 40 tendered + the sell line's 20 + the crowns line's own 25 (merit pay is earned)")
	assert_true(tm.is_objective_stamped("forage_crowns_60"),
		"EARN 60 CROWNS stamped in the same pass — the sell's MERIT PAY is itself earned income")
	# Spending does NOT move the counter (only posts count).
	tm.state.add_crowns(10_000)
	assert_true(tm.depot_buy("glowshroom", 1)["ok"])
	assert_eq(int(counters.get("crowns", 0)), 85, "a purchase is not an earn")


func test_stamped_count_cascade_completes_the_dossier() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("cascade")))
	var dossiers: Array = []
	tm.dossier_completed.connect(func(payload: Dictionary) -> void: dossiers.append(payload))
	# The four real scavenging events, in journey order. Each stamps its own
	# line; the fourth crossing cascades STAMP 4 DUTIES in the SAME pass.
	tm.engine.grant_xp(tm.state, "scavenging", 25)  # level 2 -> scav_grade_2
	assert_true(tm.is_objective_stamped("scav_grade_2"))
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	var guard := 0
	while not tm.is_objective_stamped("scav_gather_25") and guard < 400:
		_pump(tm, 1_000)
		guard += 1
	assert_true(tm.is_objective_stamped("scav_sort_20"), "20 actions stamped")
	assert_true(tm.is_objective_stamped("scav_gather_25"), "25 Scrapnel stamped")
	tm.stop_skill("scavenging")
	var stash := int(tm.state.inventory.get("scrap_metal", 0))
	if stash < 20:
		tm.state.add_item("scrap_metal", 20 - stash)
	assert_true(tm.depot_sell("scrap_metal", 20)["ok"], "the fourth event: a 20-unit tender")
	assert_true(tm.is_objective_stamped("scav_sell_20"), "the sell line stamped")
	assert_true(tm.is_objective_stamped("scav_stamped_all"),
		"the set-completion line cascaded in the same evaluation pass")
	assert_eq(dossiers.size(), 1, "dossier_completed fired once for scavenging")
	assert_eq(String(dossiers[0]["skill"]), "scavenging", "completion payload names the skill")
	assert_eq(int(dossiers[0]["total"]), 5, "total from data (5 objectives in the fixture skill)")
	assert_eq(String(dossiers[0]["stamp_line"]), "ALL 5 STAMPED · FORM R-1", "the T22 completion stamp verbatim")
	# The whole cascade is deterministic: sell (+40 tender) stamps the sell
	# line (+20), the set line (+50), and crosses lifetime 60 (+25) — order
	# is the canonical file order: the scavenging five, then forage_crowns_60.
	assert_eq(tm.state.objectives["stamped"], [
		"scav_grade_2", "scav_sort_20", "scav_gather_25", "scav_sell_20",
		"scav_stamped_all", "forage_crowns_60"],
		"the stamped set rides in canonical posted (file) order")
	assert_eq(tm.state.objectives["rewards_granted"], tm.state.objectives["stamped"],
		"every stamp granted its rewards")
	assert_eq(int(tm.state.objectives["counters"].get("stamped:scavenging", 0)), 5,
		"the derived per-skill stamp counter rebuilt to 5")
	assert_eq(int(tm.state.crowns), 10 + 25 + 15 + 40 + 20 + 50 + 25,
		"honest wallet math: the tender (40) + five merit lines (10/25/15/20/50) + the crowns line (25)")


## T26 pin (the completion arm guard): a RE-ENTRANT cascade — an XP-leg
## grant re-entering evaluation inside _stamp while nested passes land the
## remaining objectives — used to emit dossier_completed TWICE for one
## completion (the in-flight _stamp's own check fired after the nested last
## stamper had already fired). Repro: seed every real scavenging counter to
## its target, one evaluate — re-entrant XP legs complete the skill across
## nested passes. Exactly ONE completion notice may post (T23 header: "when
## a skill's LAST objective stamps"); the guard re-arms only if the skill
## later drops below total (content adds objectives).
func test_dossier_completed_emits_once_under_reentrant_cascade() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("reentrant", _shipped_objectives())))
	var completions: Array = []
	tm.dossier_completed.connect(func(payload: Dictionary) -> void: completions.append(payload))
	tm.objectives.ensure_objectives(tm.state)
	var counters: Dictionary = tm.state.objectives["counters"]
	for obj_id in tm.engine.lib.objectives:
		var obj: ObjectiveDef = tm.engine.lib.objectives[obj_id]
		if obj.skill != "scavenging" or obj.counter_key == "":
			continue
		counters[obj.counter_key] = maxi(int(counters.get(obj.counter_key, 0)), obj.target)
	tm.objectives.evaluate(tm.state)
	assert_eq(tm.objectives.stamped_count_for_skill(tm.state, "scavenging"), 23,
		"the whole real 23-rung scavenging dossier stamps in the cascade")
	assert_eq(completions.size(), 1,
		"dossier_completed posts exactly once despite re-entrant nested passes (got %d)" % completions.size())
	assert_eq(String(completions[0]["stamp_line"]), "ALL 23 STAMPED · FORM R-1",
		"the one completion carries the T22 stamp line")
	# Idempotence: a re-evaluation neither re-stamps nor re-completes.
	tm.objectives.evaluate(tm.state)
	assert_eq(completions.size(), 1, "re-evaluation does not re-complete")


# ---------------------------------------------------------------------------
# (b) auto-grant exactly once + idempotence + round trip
# ---------------------------------------------------------------------------

func test_grant_exactly_once_idempotent_and_no_regrant_on_load() -> void:
	var dir := _fixture_dir("once")
	var lib := _fixture_lib(dir)
	var tm1: Variant = _make_tm(lib)
	tm1.state.add_item("scrap_shiv", 1)
	assert_true(tm1.equip_item("scrap_shiv")["ok"])
	var crowns_at_stamp := int(tm1.state.crowns)
	assert_eq(crowns_at_stamp, 15, "the equip line paid 15 exactly once")
	# Re-evaluation (the reload path) re-rewards nothing.
	tm1.objectives.evaluate(tm1.state)
	assert_eq(int(tm1.state.crowns), 15, "a second evaluation grants nothing")
	# Round trip through the REAL SaveStore.
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW + 1_000)["ok"], "record filed")
	var tm2: Variant = _make_tm(lib)
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	assert_true(tm2.is_objective_stamped("combat_equip_shiv"), "the stamp survived the round trip")
	assert_eq(int(tm2.state.crowns), crowns_at_stamp, "the loaded record NEVER re-rewards")
	assert_eq(tm2.state.objectives["stamped"], ["combat_equip_shiv"], "stamped set persisted")
	assert_eq(tm2.state.objectives["counters"], tm1.state.objectives["counters"],
		"counters survived the JSON round trip exactly")


# ---------------------------------------------------------------------------
# (c) reward paths — xp level crossing through the shared pipeline
# ---------------------------------------------------------------------------

func test_xp_reward_leg_crosses_levels_through_shared_pipeline() -> void:
	var tm: Variant = _make_tm(_fixture_lib(_fixture_dir("xpcross")))
	assert_eq(int(tm.state.skills_level["junksmithing"]), 1, "fresh smith at clearance 1")
	tm.state.add_item("duskcorn", 10)
	assert_true(tm.start_activity("grind_mandatory_grits")["ok"])
	_pump(tm, 12_000)  # 3 grits -> cook_grits_3 pays 40 junksmithing xp
	assert_true(tm.is_objective_stamped("cook_grits_3"))
	assert_eq(int(tm.state.skills_xp["junksmithing"]), 40, "the xp leg posted exactly 40")
	assert_eq(int(tm.state.skills_level["junksmithing"]), 2,
		"40 xp crossed clearance 2 (20) through the shared level pipeline")
	assert_eq(int(tm.state.objectives["counters"].get("level:junksmithing", 0)), 2,
		"the reward's level crossing fed the max-grade counter (level_up hook)")


func test_reward_lines_carry_the_t22_formats() -> void:
	var lib := _fixture_lib(_fixture_dir("lines"))
	# Dual-leg line (crowns + xp) and single-leg lines, verbatim.
	var dual: ObjectiveDef = lib.objective("scav_sort_20")
	assert_eq(ObjectivesTracker.reward_line(dual), "MERIT PAY · 25 CROWNS · COMMENDATION · 60 XP",
		"dual reward line joins both legs with the T22 nouns")
	assert_eq(ObjectivesTracker.notice_line(dual), "FORM R-1 STAMPED · 25 CROWNS · 60 XP POSTED",
		"dual notice line — both legs posted")
	var xp_only: ObjectiveDef = lib.objective("cook_grits_3")
	assert_eq(ObjectivesTracker.reward_line(xp_only), "COMMENDATION · 40 XP", "xp-only reward line")
	assert_eq(ObjectivesTracker.notice_line(xp_only), "FORM R-1 STAMPED · 40 XP POSTED", "xp-only notice line")
	var crowns_only: ObjectiveDef = lib.objective("scav_grade_2")
	assert_eq(ObjectivesTracker.reward_line(crowns_only), "MERIT PAY · 10 CROWNS", "crowns-only reward line")
	# Mono grouping through SignageFmt (the Addendum 2 numeral rule).
	var big := ObjectiveDef.new()
	big.reward_crowns = 1250
	assert_eq(ObjectivesTracker.reward_line(big), "MERIT PAY · 1,250 CROWNS",
		"numerals render grouped mono digits")
	# The façade read the T26 registers will bind: rows in posted order.
	var tm: Variant = _make_tm(lib)
	var summary: Dictionary = tm.dossier_summary("scavenging")
	assert_eq(int(summary["stamped"]), 0, "fresh dossier reads 0/5")
	assert_eq(int(summary["total"]), 5, "total from data")
	assert_eq(String(summary["stamp_line"]), "", "no completion stamp while open")
	assert_eq((summary["rows"] as Array).map(func(r: Dictionary) -> String: return String(r["id"])),
		["scav_grade_2", "scav_sort_20", "scav_gather_25", "scav_sell_20", "scav_stamped_all"],
		"façade rows ride the posted order")
	assert_eq(String(summary["rows"][1]["reward_line"]), "MERIT PAY · 25 CROWNS · COMMENDATION · 60 XP",
		"rows carry their reward lines")


# ---------------------------------------------------------------------------
# (d) offline settlement
# ---------------------------------------------------------------------------

func test_offline_crafts_settle_with_exact_twin_state() -> void:
	var dir := _fixture_dir("offline_craft")
	var lib := _fixture_lib(dir)
	# Offline twin: the away window crafts 5 grits (input-capped) — counters
	# maintained by the shared _execute_action, stamps at settlement.
	var off: Variant = _make_tm(lib, SEED)
	off.state.add_item("duskcorn", 10)
	assert_true(off.start_activity("grind_mandatory_grits")["ok"])
	var off_notices: Array = []
	off.objective_stamped.connect(func(payload: Dictionary) -> void: off_notices.append(payload))
	var payload: Dictionary = off.apply_offline_elapsed(20_000)
	assert_true(off.is_objective_stamped("cook_grits_3"), "the away window's crafts stamped at settlement")
	assert_true(payload.has("objectives"), "the mail-call payload carries the offline stamps")
	var stamps: Array = payload["objectives"]["stamps"]
	assert_true(stamps.any(func(p: Dictionary) -> bool: return String(p["id"]) == "cook_grits_3"),
		"the stamp rides the payload for the MAIL CALL notice")
	assert_eq(int(payload["skills_xp"].get("junksmithing", 0)), 40,
		"the reward xp leg folded into the payload's skills_xp")
	assert_eq(payload["levels"].get("junksmithing"), {"from": 1, "to": 2},
		"the reward's level crossing folded into the payload's levels")
	assert_eq(int(payload["skills_xp"].get("cooking", 0)), 60, "activity xp unaffected (5 crafts x 12)")
	assert_false(off_notices.is_empty(), "the immediate notice fired too (T18 offline-seam precedent)")
	# Live twin: the same window pumped live stamps the same line mid-window.
	var live: Variant = _make_tm(lib, SEED)
	live.state.add_item("duskcorn", 10)
	assert_true(live.start_activity("grind_mandatory_grits")["ok"])
	_pump(live, 20_000)
	assert_true(live.is_objective_stamped("cook_grits_3"), "the live twin stamped the same line")
	# Twin exactness on everything the window touched (anchors differ by
	# design — the offline rewind — so compare the player-facing state).
	assert_eq(live.state.skills_xp, off.state.skills_xp, "twin xp identical (rewards included)")
	assert_eq(live.state.inventory, off.state.inventory, "twin manifests identical")
	assert_eq(live.state.crowns, off.state.crowns, "twin wallets identical")
	assert_eq(live.state.objectives, off.state.objectives,
		"twin objectives state identical (counters + stamps + grants)")


func test_offline_kills_settle_from_mail_call_deltas() -> void:
	var dir := _fixture_dir("offline_kill")
	var lib := _fixture_lib(dir)
	var tm: Variant = _make_tm(lib)
	tm.state.add_item("scrap_shiv", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"])
	tm.state.add_item("radstag_stew", 20)  # survivability through the window
	assert_true(tm.engage_monster("junkyard_roach")["ok"])
	var payload: Dictionary = tm.apply_offline_elapsed(600_000)
	var kills := int(payload["combat"].get("kills", 0))
	assert_gt(kills, 1, "the away window farmed multiple kills (got %d)" % kills)
	assert_true(tm.is_objective_stamped("combat_litterbugs_2"),
		"kills from the payload's delta stamped the kill line at settlement")
	var counters: Dictionary = tm.state.objectives["counters"]
	assert_eq(int(counters.get("monster:junkyard_roach", 0)), kills, "kill counter = payload kills")
	var stamps: Array = payload["objectives"]["stamps"]
	assert_true(stamps.any(func(p: Dictionary) -> bool: return String(p["id"]) == "combat_litterbugs_2"),
		"the kill stamp rode the payload")
	# Level evidence settles too (kill xp crossed clearances during the window).
	assert_true(int(counters.get("level:wasteland_combat", 0)) >= 2,
		"the window's level crossing fed the max-grade counter")


# ---------------------------------------------------------------------------
# (e) migrations + save validation + repair
# ---------------------------------------------------------------------------

func _veteran_pair(dir: String) -> Array:
	var lib := _fixture_lib(dir)
	var tm: Variant = _make_tm(lib)
	# A progressed v2-era player: grades earned, Crowns banked — hand-crafted
	# (direct field writes fire NO engine seams, so the objectives namespace
	# stays empty, exactly like a genuine v2 record).
	tm.state.skills_xp["scavenging"] = lib.xp_curve("standard_99").total_xp_to_reach(5)
	tm.state.skills_level["scavenging"] = 5
	tm.state.skills_xp["wasteland_combat"] = lib.xp_curve("standard_99").total_xp_to_reach(3)
	tm.state.skills_level["wasteland_combat"] = 3
	tm.state.crowns = 400
	return [lib, tm]


func test_v2_to_v3_zero_counters_and_derivable_level_sync() -> void:
	var dir := _fixture_dir("v2migrate")
	var pair := _veteran_pair(dir)
	var lib: ContentLibrary = pair[0]
	var tm1: Variant = pair[1]
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW + 1_000)["ok"], "v3 filed")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["save_version"] = 2
	doc["engine"].erase("objectives")  # degrade to the honest v2 shape
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()

	var tm2: Variant = _make_tm(lib)
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	# The documented policy: per-skill max grades are derivable and synced —
	# the level-ladder lines those grades satisfy stamp at adopt (+ rewards);
	# every count/crowns counter starts honestly at zero.
	assert_true(tm2.is_objective_stamped("scav_grade_2"), "clearance 5 proved from xp -> the grade-2 line stamps")
	assert_true(tm2.is_objective_stamped("combat_grade_3"), "combat clearance 3 proved likewise")
	assert_false(tm2.is_objective_stamped("scav_sort_20"), "per-activity counts are NOT derivable: zero, unstamped")
	assert_false(tm2.is_objective_stamped("forage_crowns_60"),
		"lifetime Crowns earned are NOT derivable (the balance proves nothing): zero")
	var counters: Dictionary = tm2.state.objectives["counters"]
	assert_eq(int(counters.get("level:scavenging", 0)), 5, "derivable grades synced into the counters")
	assert_eq(int(counters.get("activity:sort_scrap_pile", 0)), 0, "count counters zeroed (documented)")
	assert_eq(int(counters.get("crowns", 0)), 30,
		"lifetime crowns zeroed by migration, then the two derivable rewards posted (+10 +20 = earned)")
	assert_eq(tm2.state.objectives["stamped"], ["scav_grade_2", "combat_grade_3"],
		"stamps in canonical file order")
	assert_eq(int(tm2.state.crowns), 400 + 10 + 20, "banked Crowns kept + the two derivable rewards posted once")


func test_v1_to_v3_chain_intact() -> void:
	var dir := _fixture_dir("v1chain")
	var pair := _veteran_pair(dir)
	var lib: ContentLibrary = pair[0]
	var tm1: Variant = pair[1]
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW + 1_000)["ok"], "v3 filed")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["save_version"] = 1
	doc["engine"].erase("staffing")
	doc["engine"].erase("orientation")
	doc["engine"].erase("objectives")  # degrade to the honest run-1 shape
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()

	var tm2: Variant = _make_tm(lib)
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	# The whole chain walked: staffing seeded (v1->v2), orientation seeded +
	# back-filled, objectives seeded (v2->v3) + derivable stamps.
	assert_eq(int(tm2.state.staffing.get("deputies", -1)), 0, "v1->v2 seeded staffing")
	assert_true(tm2.state.orientation.has("steps_done"), "v1->v2 seeded orientation")
	assert_true(tm2.is_objective_stamped("scav_grade_2"), "v2->v3 seeded objectives + derivable grade stamps")
	# Re-file stamps v3.
	assert_true(store2.save_now(NOW + 3_000)["ok"], "re-file ok")
	var redoc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(redoc["save_version"]), 3, "the re-filed record is v3")
	assert_eq(int(redoc["engine"]["objectives"]["counters"]["level:scavenging"]), 5,
		"the synced grade counter persists")


func test_validation_rejects_mangled_objectives_namespace() -> void:
	var pair := _veteran_pair(_fixture_dir("validation"))
	var tm1: Variant = pair[1]
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	var base := {
		"meta": {"created_unix": 1, "updated_unix": 1, "playtime_s": 0},
		"anchor_unix_ms": 1,
		"engine_sim_time_ms": 0,
		"content_schema_version": 1,
		"engine": tm1.state.to_dict(),
		"settings": {},
	}
	for label in [
			["unknown counter key", {"counters": {"activity:ghost_pile": 1}, "stamped": [], "rewards_granted": []}],
			["counter shape", {"counters": "many", "stamped": [], "rewards_granted": []}],
			["negative counter", {"counters": {"crowns": -5}, "stamped": [], "rewards_granted": []}],
			["counter value type", {"counters": {"crowns": "plenty"}, "stamped": [], "rewards_granted": []}],
			["unknown stamped id", {"counters": {}, "stamped": ["overtime"], "rewards_granted": []}],
			["stamped twice", {"counters": {}, "stamped": ["scav_grade_2", "scav_grade_2"], "rewards_granted": []}],
			["granted without stamp", {"counters": {}, "stamped": [], "rewards_granted": ["scav_grade_2"]}],
			["stamped shape", {"counters": {}, "stamped": "scav_grade_2", "rewards_granted": []}],
			["not an object", "filed verbally"],
		]:
		var doc: Dictionary = base.duplicate(true)
		doc["engine"]["objectives"] = label[1]
		var why: String = store._validate_doc(doc)
		assert_ne(why, "", "%s is refused" % String(label[0]))
		assert_string_contains(why, "objectives", "%s names the namespace (got '%s')" % [String(label[0]), why])
	# Honest control: the unmangled base document IS a valid v3 record.
	assert_eq(String(store._validate_doc(base)), "", "the base doc itself validates clean")


func test_ensure_repairs_mangled_namespace_in_place() -> void:
	var lib := _fixture_lib(_fixture_dir("repair"))
	var tm: Variant = _make_tm(lib)
	# Hand-mangle: junk counter keys, stringy counter values, an unknown
	# stamped id, out-of-order stamps, a stale derived counter.
	tm.state.objectives = {
		"counters": {"activity:ghost_pile": 3, "crowns": "12", "stamped:scavenging": 9},
		"stamped": ["scav_sell_20", "ghost_objective", "scav_grade_2"],
		"rewards_granted": ["scav_sell_20"],
	}
	tm.objectives.ensure_objectives(tm.state)
	var counters: Dictionary = tm.state.objectives["counters"]
	assert_false(counters.has("activity:ghost_pile"), "unknown counter keys drop")
	assert_eq(int(counters.get("crowns", -1)), 12, "counter values re-typed to int")
	assert_eq(tm.state.objectives["stamped"], ["scav_grade_2", "scav_sell_20"],
		"unknown ids dropped, canonical file order restored")
	assert_eq(int(counters.get("stamped:scavenging", 0)), 2, "derived per-skill counter rebuilt from the set")


# ---------------------------------------------------------------------------
# (f) loader defect drills — the T2 error grammar, record id + field + reason
# ---------------------------------------------------------------------------

func _drill_error(label: String, objectives: Variant, needle: String,
		mutate_file := "", mutate: Callable = Callable()) -> void:
	var dir := _fixture_dir("drill_%s" % label, objectives, mutate_file, mutate)
	var result = ContentLoader.load_all(dir)
	assert_false(result.ok(), "%s rejected (errors: %s)" % [label, str(result.errors)])
	assert_true(result.errors.any(func(e: String) -> bool: return e.contains(needle)),
		"%s names the defect (want '%s' in %s)" % [label, needle, str(result.errors)])


func test_loader_rejects_unknown_refs() -> void:
	_drill_error("unknown skill", [_obj("x_skill", "alchemy", "EARN CLEARANCE 2", "level_reach", 2, {}, "scavenging")],
		"skill: references unknown skills id 'alchemy'")
	_drill_error("unknown monster", [_obj("x_mon", "wasteland_combat", "CLEAR 2 GHOSTS", "kill_count", 2,
		{"ref": "ghost_roach"}, "wasteland_combat")],
		"condition.ref: references unknown monsters id 'ghost_roach'")
	_drill_error("unknown gather ref", [_obj("x_gather", "scavenging", "GATHER 5 NOTHING", "gather_count", 5,
		{"ref": "unobtainium"}, "scavenging")],
		"condition.ref: references unknown activities/items id 'unobtainium'")
	_drill_error("unknown xp skill", [_obj("x_xp", "scavenging", "EARN CLEARANCE 2", "level_reach", 2, {}, "",
		{"xp": {"skill": "alchemy", "amount": 10}})],
		"reward.xp.skill: references unknown skills id 'alchemy'")


func test_loader_rejects_zone_ref_not_in_shipped_zones_list() -> void:
	# The zones-list decision: the list is exhaustive — a zone_clear ref must
	# resolve against data/zones.json (no per-id tolerance; gift_court ships
	# in the list from day one).
	_drill_error("unknown zone", [_obj("x_zone", "wasteland_combat", "SECURE NOWHERE", "zone_clear", 1,
		{"ref": "third_zone"}, "wasteland_combat")],
		"condition.ref: references unknown zones id 'third_zone'")
	# The moment a zone leaves the list, its objective stops validating:
	# gift_court erased from zones.json -> the reserved-id objective fails.
	_drill_error("gift_court must ship in zones",
		[_obj("combat_secure_court", "wasteland_combat", "SECURE THE GIFT COURT", "zone_clear", 1,
			{"ref": "gift_court"}, "wasteland_combat")],
		"references unknown zones id 'gift_court'",
		"zones.json", func(z: Dictionary) -> Dictionary:
			z["zones"] = z["zones"].filter(func(zz: Dictionary) -> bool: return String(zz["id"]) != "gift_court")
			return z)
	# A monster referencing an unknown zone is rejected too (the cross-check
	# that upgrades zone strings to real references).
	_drill_error("monster zone must resolve", FIXTURE_OBJECTIVES,
		"zone: references unknown zones id 'mall'",
		"monsters.json", func(m: Dictionary) -> Dictionary:
			m["monsters"][0]["zone"] = "mall"
			return m)


func test_loader_rejects_voice_rule_violations() -> void:
	_drill_error("seven words", [_obj("x_words", "scavenging", "SORT THE WHOLE ENTIRE PILE TWICE MORE", "gather_count",
		5, {"ref": "sort_scrap_pile"}, "scavenging")],
		"description: must be at most 6 words")
	_drill_error("exclamation", [_obj("x_bang", "scavenging", "SORT IT NOW!", "gather_count", 5,
		{"ref": "sort_scrap_pile"}, "scavenging")],
		"must not contain '!'")


func test_loader_rejects_bad_rewards_and_conditions() -> void:
	_drill_error("no reward legs", [_obj("x_free", "scavenging", "EARN CLEARANCE 2", "level_reach", 2, {}, "")],
		"at least one reward leg is required")
	_drill_error("zero crowns leg", [_obj("x_zero", "scavenging", "EARN CLEARANCE 2", "level_reach", 2, {}, "",
		{"crowns": 0})],
		"crowns: must be between 1 and")
	_drill_error("level over max", [_obj("x_max", "scavenging", "EARN CLEARANCE 100", "level_reach", 100, {}, "scavenging")],
		"target: must be between 2 and 99, got 100")
	_drill_error("unreachable set", [_obj("x_set", "scavenging", "STAMP 5 DUTIES", "stamped_count", 5, {}, "scavenging")],
		"the set can never complete")


func test_loader_rejects_ownership_violations() -> void:
	# Kills belong to the combat dossier; crafts to their own skill; equips
	# need equipment; gather-by-item must be producible by the dossier skill.
	_drill_error("kill in wrong dossier", [_obj("x_own1", "scavenging", "CLEAR 2 LITTERBUGS", "kill_count", 2,
		{"ref": "junkyard_roach"}, "scavenging")],
		"kill objectives belong to the combat skill's dossier")
	_drill_error("craft in wrong dossier", [_obj("x_own2", "cooking", "SMELT 5 ALMOST BULLION", "craft_count", 5,
		{"ref": "smelt_scrap_ingot"}, "cooking")],
		"recipe 'smelt_scrap_ingot' belongs to skill 'junksmithing'")
	_drill_error("equip non-equipment", [_obj("x_own3", "wasteland_combat", "EQUIP DUSKCORN", "equip_item", 1,
		{"ref": "duskcorn"}, "wasteland_combat")],
		"references unknown equipment item 'duskcorn'")
	_drill_error("gather unproducible item", [_obj("x_own4", "scavenging", "GATHER 5 DUSKCORN", "gather_count", 5,
		{"ref": "duskcorn"}, "scavenging")],
		"no 'scavenging' activity drop table produces item 'duskcorn'")


func test_loader_rejects_duplicate_ids_and_missing_ref_field() -> void:
	_drill_error("duplicate ids", [
		_obj("dupe", "scavenging", "EARN CLEARANCE 2", "level_reach", 2, {}, "scavenging"),
		_obj("dupe", "scavenging", "EARN CLEARANCE 3", "level_reach", 3, {}, "scavenging")],
		"duplicate objective id 'dupe'")
	_drill_error("ref required", [{"id": "x_noref", "skill": "wasteland_combat",
		"description": "CLEAR 2 LITTERBUGS",
		"condition": {"kind": "kill_count", "target": 2}, "reward": {"crowns": 5}}],
		"condition kind 'kill_count' requires a content ref")


## Objective-record builder for drills (defaults make a valid shape; each
## drill poisons exactly one field).
func _obj(id: String, skill: String, description: String, kind: String, target: int,
		condition_extra: Dictionary, xp_skill: String, reward_extra: Dictionary = {}) -> Dictionary:
	var condition := {"kind": kind, "target": target}
	for key in condition_extra:
		condition[key] = condition_extra[key]
	var reward: Dictionary = reward_extra.duplicate()
	if reward.is_empty() and xp_skill != "":
		reward = {"xp": {"skill": xp_skill, "amount": 10}}
	elif xp_skill != "" and not reward.has("xp"):
		reward["xp"] = {"skill": xp_skill, "amount": 10}
	return {
		"id": id,
		"skill": skill,
		"description": description,
		"condition": condition,
		"reward": reward,
	}
