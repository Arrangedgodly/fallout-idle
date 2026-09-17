extends GutTest
## tests/test_orientation.gd — T18 ORIENTATION FORM O-1 validation (Design
## lane + Daredevil's claims; the user's complaint "too text heavy and not
## clear how I should get started" is the law this suite pins).
##
## Covers the T18 acceptance matrix headless, against LIVE content:
##   (a) step detection — each of the 7 steps stamps from the REAL engine
##       event that earns it (start a gathering shift, level up, sell, craft,
##       equip / cook, first victory, deputize) — order-agnostic except where
##       naturally sequential;
##   (b) persistence — mid-tutorial save/load round-trips the namespace; a
##       completed record reloads as the posted slip and NEVER re-rewards;
##       v1 migration seeds the namespace and the adopt evaluation stamps
##       every step lifetime evidence already satisfies;
##   (c) stipend — granted exactly once, amount from data/staffing.json
##       (never hardcoded), T20-tuned 150 Crowns (balance-notes §5.2);
##   (d) cue + keyboard — the current step's cue points at the right
##       department plate, follows step changes, retires at completion; the
##       rows + fold control are keyboard-reachable and a row press opens
##       its department;
##   (e) low-text audit — the form's total word count <= 40 in EVERY state
##       (the "not text heavy" requirement, enforced as a pin);
##   (f) validation — mangled orientation namespaces are refused; staffing
##       defect drills on orientation_stipend.
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (advance_wall_ms is the only clock input) — test_engine.gd's
## discipline; SaveStore twins use injected temp dirs (test_save.gd's).

const ConcourseScene := preload("res://scenes/main.tscn")
const ObjectiveFreeLib := preload("res://tests/objective_free_lib.gd")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260918
const NOW := 1_768_000_000_000
const WORD_BUDGET := 40

const STEP_TITLES := {
	"work_shift": "WORK A POSTED SHIFT",
	"earn_clearance": "EARN A CLEARANCE",
	"file_crowns_claim": "FILE A CROWNS CLAIM",
	"process_product": "PROCESS A PRODUCT",
	"provision_patrol": "PROVISION THE PATROL",
	"clear_nuisance": "CLEAR A NUISANCE",
	"deputize_resident": "DEPUTIZE A RESIDENT",
}

var _vp: SubViewport
var _concourse: Concourse


func _lib() -> ContentLibrary:
	# T25: the O-1 stipend-once arithmetic pins boot on the objective-free
	# fixture — dossier merit pay no longer perturbs them (T27-safe).
	return ObjectiveFreeLib.load("orientation")


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


func _flush(tm: Variant) -> void:
	tm.batcher.force_flush(tm.sim_time_ms)


func _tmp_dir(label: String) -> String:
	var dir := OS.get_user_data_dir().path_join("t18_orientation/%s_%d" % [label, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _stamp_all_but(tm: Variant, skip: Array) -> void:
	# Engine-true fast-path: drive each step's real event, skipping `skip`.
	if not skip.has("work_shift"):
		assert_true(tm.start_activity("sort_scrap_pile")["ok"])
		tm.stop_skill("scavenging")
	if not skip.has("earn_clearance"):
		tm.engine.grant_xp(tm.state, "scavenging", 25)  # level 2 at 20 xp (the shared pipeline)
	if not skip.has("file_crowns_claim"):
		tm.state.add_item("scrap_metal", 5)
		assert_true(tm.depot_sell("scrap_metal")["ok"])
	if not skip.has("process_product"):
		tm.state.add_item("scrap_metal", 30)
		assert_true(tm.start_activity("smelt_scrap_ingot")["ok"])
		_pump(tm, 5_000)
		tm.stop_skill("junksmithing")
	if not skip.has("provision_patrol"):
		tm.state.add_item("scrap_shiv", 1)
		assert_true(tm.equip_item("scrap_shiv")["ok"])
	if not skip.has("deputize_resident"):
		tm.state.add_crowns(300)
		assert_true(tm.deputize_resident()["ok"])
	if not skip.has("clear_nuisance"):
		assert_true(tm.engage_monster("junkyard_roach")["ok"])
		_pump(tm, 300_000, 2_500)


# ---------------------------------------------------------------------------
# (0) the §14 machine-id contract + step titles are the naming bible verbatim
# ---------------------------------------------------------------------------

func test_step_ids_and_order_match_naming_bible() -> void:
	assert_eq(OrientationTracker.STEPS, [
		"work_shift", "earn_clearance", "file_crowns_claim", "process_product",
		"provision_patrol", "clear_nuisance", "deputize_resident"],
		"the 7 §14 step ids in posted order")
	assert_eq(OrientationForm.STEP_TITLES, STEP_TITLES,
		"form titles are the naming-bible §10 rows VERBATIM")


func test_step_targets_are_concourse_departments() -> void:
	var dept_ids := []
	for d in Concourse.DEPARTMENTS:
		dept_ids.append(String(d["id"]))
	for step_id in OrientationTracker.STEPS:
		var target := OrientationTracker.step_target(step_id)
		assert_ne(target, "", "step %s has a target department" % step_id)
		assert_true(dept_ids.has(target),
			"step %s targets a real plate (%s)" % [step_id, target])
	# The documented cue choices (production log): earliest-path cooking for
	# PROVISION THE PATROL, the personnel plate for the run-2 system it teaches.
	assert_eq(OrientationTracker.step_target("work_shift"), "scavenging",
		"step 1 points at the first-viewport department")
	assert_eq(OrientationTracker.step_target("earn_clearance"), "scavenging",
		"EARN A CLEARANCE points where the XP comes from")
	assert_eq(OrientationTracker.step_target("file_crowns_claim"), "requisition_depot",
		"claims are filed at the Depot")
	assert_eq(OrientationTracker.step_target("provision_patrol"), "cooking",
		"the earliest qualifying provision path is a cooked meal (documented)")
	assert_eq(OrientationTracker.step_target("deputize_resident"), "personnel",
		"the tutorial teaches the T17 system at its own plate")


# ---------------------------------------------------------------------------
# (a) step detection — every step through the real engine
# ---------------------------------------------------------------------------

func test_work_shift_stamps_on_gathering_start_only() -> void:
	var tm: Variant = _make_tm()
	assert_false(tm.orientation_step_done_bool("work_shift"), "fresh record: unstamped")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "gathering shift starts")
	assert_true(tm.orientation_step_done_bool("work_shift"),
		"BENGIN SHIFT on a gathering activity stamps WORK A POSTED SHIFT")
	# A recipe start is NOT a gathering shift (PROCESS A PRODUCT owns crafts).
	var tm2: Variant = _make_tm()
	tm2.state.add_item("duskcorn", 10)
	assert_true(tm2.start_activity("grind_mandatory_grits")["ok"], "recipe starts")
	assert_false(tm2.orientation_step_done_bool("work_shift"),
		"a recipe posting is not a gathering shift")


func test_earn_clearance_stamps_on_any_level_up() -> void:
	var tm: Variant = _make_tm()
	var stamped: Array = []
	tm.orientation_step_done.connect(func(step_id: String) -> void: stamped.append(step_id))
	# Real ticks: sort_scrap_pile at 10 xp/action, level 2 at 20 xp — two
	# actions in ~6 s (the balance hook's own promise).
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	_pump(tm, 8_000)
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "two actions crossed level 2")
	assert_true(tm.orientation_step_done_bool("earn_clearance"),
		"the level-up path stamps EARN A CLEARANCE")
	assert_true(stamped.has("earn_clearance"), "step_done emitted for the clearance")


func test_crowns_claim_stamps_on_first_sale() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_item("scrap_metal", 5)
	assert_true(tm.depot_sell("scrap_metal")["ok"], "first tender settles")
	assert_true(tm.orientation_step_done_bool("file_crowns_claim"),
		"a Depot sale stamps FILE A CROWNS CLAIM")
	# Buying does NOT stamp it (crowns must be CLAIMED, not spent).
	var tm2: Variant = _make_tm()
	tm2.state.add_crowns(10_000)
	assert_true(tm2.depot_buy("glowshroom", 1)["ok"], "a purchase settles")
	assert_false(tm2.orientation_step_done_bool("file_crowns_claim"),
		"spending Crowns is not filing a claim")


func test_process_product_and_food_provision_stamp_on_first_craft() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_item("duskcorn", 10)
	assert_true(tm.start_activity("grind_mandatory_grits")["ok"])
	_pump(tm, 4_000)  # one 3 s craft
	assert_true(tm.orientation_step_done_bool("process_product"),
		"a completed recipe stamps PROCESS A PRODUCT")
	assert_true(tm.orientation_step_done_bool("provision_patrol"),
		"a FOOD output also stamps PROVISION THE PATROL (either leg qualifies)")
	# A non-food craft stamps the product step but not provisions.
	var tm2: Variant = _make_tm()
	tm2.state.add_item("scrap_metal", 30)
	assert_true(tm2.start_activity("smelt_scrap_ingot")["ok"])
	_pump(tm2, 5_000)
	assert_true(tm2.orientation_step_done_bool("process_product"), "ingot craft stamps product")
	assert_false(tm2.orientation_step_done_bool("provision_patrol"),
		"an ingot is not a provision (equip or food only)")


func test_provision_patrol_equip_leg() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_item("scrap_shiv", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "gear equipped")
	assert_true(tm.orientation_step_done_bool("provision_patrol"),
		"equipping stamps PROVISION THE PATROL (the other qualifying leg)")
	assert_false(tm.orientation_step_done_bool("process_product"),
		"equipping is not crafting")


func test_clear_nuisance_stamps_on_first_victory() -> void:
	var tm: Variant = _make_tm()
	var stamped: Array = []
	tm.orientation_step_done.connect(func(step_id: String) -> void: stamped.append(step_id))
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "engage the pest")
	_pump(tm, 300_000, 2_500)
	assert_eq(String(tm.state.combat["phase"]), "victory", "Litterbug cleared (bare hands)")
	assert_true(tm.orientation_step_done_bool("clear_nuisance"),
		"a combat victory stamps CLEAR A NUISANCE")
	assert_true(stamped.has("clear_nuisance"), "step_done emitted for the victory")
	# The same fight's kill-XP crossing level 2 also stamped the clearance —
	# order-agnostic by design.
	assert_true(tm.orientation_step_done_bool("earn_clearance"),
		"victory XP crossing a grade stamps the clearance too (order-agnostic)")


func test_deputize_stamps_on_purchase() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_crowns(300)
	assert_true(tm.deputize_resident()["ok"], "second posting purchased")
	assert_true(tm.orientation_step_done_bool("deputize_resident"),
		"a deputy purchase stamps DEPUTIZE A RESIDENT")


func test_completion_in_reverse_order_stipend_once() -> void:
	var tm: Variant = _make_tm()
	var completed: Array = []
	tm.orientation_completed.connect(func(payload: Dictionary) -> void: completed.append(payload))
	# Reverse order: 7 -> 1. Each step stamps through its real event.
	assert_eq(tm.next_deputy_price(), 300, "ladder price from data (T27-retuned, balance-notes §6.4)")
	tm.state.add_crowns(350)
	assert_true(tm.deputize_resident()["ok"], "step 7: deputize")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "step 6: engage")
	_pump(tm, 300_000, 2_500)
	assert_true(tm.orientation_step_done_bool("clear_nuisance"), "step 6 stamped")
	tm.stop_combat()
	tm.state.add_item("scrap_shiv", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "step 5: equip")
	tm.state.add_item("scrap_metal", 30)
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"], "step 4: craft")
	_pump(tm, 5_000)
	tm.stop_skill("junksmithing")
	tm.state.add_item("scrap_metal", 5)
	assert_true(tm.depot_sell("scrap_metal", 5)["ok"], "step 3: sell 5 (exact tender)")
	tm.engine.grant_xp(tm.state, "foraging", 25, false)  # step 2: a clearance
	# crowns before the seventh stamp: 350-300=50, +10 for five Scrapnel, = 60
	assert_eq(tm.state.crowns, 60, "crowns before the stipend land")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "step 1: gather (the seventh stamp)")
	assert_eq(int(_lib().orientation_stipend), 150, "stipend amount from data (T20-tuned)")
	assert_eq(completed.size(), 1, "orientation_completed fired ONCE")
	assert_eq(int(completed[0]["stipend"]), 150, "payload carries the stipend amount")
	assert_eq(tm.state.crowns, 210, "stipend posted exactly once at the seventh stamp (60 + 150)")
	assert_true(bool(tm.state.orientation["completed"]), "completed flag set")
	assert_true(bool(tm.state.orientation["stipend_claimed"]), "stipend claimed once")
	# Re-evaluation (the reload path) re-rewards nothing.
	tm.orientation.evaluate(tm.state)
	assert_eq(tm.state.crowns, 210, "evaluation after completion grants nothing")


# ---------------------------------------------------------------------------
# (b) persistence + migration
# ---------------------------------------------------------------------------

func test_namespace_round_trips_through_player_state() -> void:
	var tm: Variant = _make_tm()
	_stamp_all_but(tm, ["provision_patrol", "clear_nuisance", "deputize_resident"])
	var d: Dictionary = tm.state.to_dict()
	var back: PlayerState = PlayerState.from_dict(d, _lib())
	assert_eq(back.orientation["steps_done"], ["work_shift", "earn_clearance",
		"file_crowns_claim", "process_product"],
		"steps_done round-trips in stamp order")
	assert_false(bool(back.orientation["completed"]), "incomplete round-trips")
	assert_false(bool(back.orientation["stipend_claimed"]), "unclaimed round-trips")


func test_mid_tutorial_save_load_and_completed_no_re_reward() -> void:
	var dir := _tmp_dir("roundtrip")
	var tm1: Variant = _make_tm()
	_stamp_all_but(tm1, ["provision_patrol", "clear_nuisance", "deputize_resident"])
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW + 1_000)["ok"], "mid-tutorial record filed")

	# Mid-tutorial load: the same four steps stand, nothing re-granted.
	var tm2: Variant = _make_tm()
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	assert_eq(tm2.orientation.steps_done_count(tm2.state), 4, "four steps survive the load")
	assert_true(tm2.orientation_step_done_bool("work_shift"), "work_shift survived")
	assert_false(bool(tm2.state.orientation["completed"]), "still incomplete")

	# Finish on tm2, file again, reload into a third twin: no re-reward.
	_stamp_all_but(tm2, ["work_shift", "earn_clearance", "file_crowns_claim", "process_product"])
	assert_true(bool(tm2.state.orientation["completed"]), "completed on the loaded record")
	var crowns_at_completion := int(tm2.state.crowns)
	assert_true(store2.save_now(NOW + 3_000)["ok"], "completed record filed")
	var tm3: Variant = _make_tm()
	var store3: Variant = SaveStoreScript.new()
	autofree(store3)
	store3._boot(dir, tm3, NOW + 4_000)
	assert_true(bool(tm3.state.orientation["completed"]), "completion persisted")
	assert_true(bool(tm3.state.orientation["stipend_claimed"]), "claim persisted")
	assert_eq(int(tm3.state.crowns), crowns_at_completion,
		"a completed record NEVER re-rewards on load")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("save.json")))
	assert_eq(int(doc["engine"]["orientation"]["steps_done"].size()), 7,
		"the filed record carries all seven stamps")


func test_v1_migration_seeds_and_evaluation_backfills() -> void:
	var dir := _tmp_dir("v1migrate")
	var tm1: Variant = _make_tm()
	# A progressed run-1 player: gathering + processing xp, a clearance,
	# sold crowns, gear worn, combat xp (the evidence set).
	tm1.engine.grant_xp(tm1.state, "scavenging", 500)
	tm1.engine.grant_xp(tm1.state, "junksmithing", 300)
	tm1.engine.grant_xp(tm1.state, "wasteland_combat", 25)
	tm1.state.add_crowns(120)
	tm1.state.combat["weapon"] = "scrap_shiv"
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW + 1_000)["ok"], "v2 filed")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["save_version"] = 1
	doc["engine"].erase("staffing")
	doc["engine"].erase("orientation")  # degrade to the honest run-1 shape
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()

	var tm2: Variant = _make_tm()
	var stamped: Array = []
	tm2.orientation_step_done.connect(func(step_id: String) -> void: stamped.append(step_id))
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	# The migration seeded the namespace; the adopt evaluation stamped every
	# evidence-satisfied step instantly...
	for step_id in ["work_shift", "earn_clearance", "file_crowns_claim",
			"process_product", "provision_patrol", "clear_nuisance"]:
		assert_true(tm2.orientation_step_done_bool(step_id),
			"evidence stamps %s on first evaluation" % step_id)
		assert_true(stamped.has(step_id), "step_done emitted for %s at adopt" % step_id)
	# ...but a step with no evidence stays open (they never deputized).
	assert_false(tm2.orientation_step_done_bool("deputize_resident"),
		"no deputies in the record: step 7 stays open")
	assert_false(bool(tm2.state.orientation["completed"]), "form stays open")


func test_offline_settlement_stamps_derived_steps() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_item("duskcorn", 10)
	assert_true(tm.start_activity("grind_mandatory_grits")["ok"])
	tm.apply_offline_elapsed(10_000)  # 3 crafts + levels while away
	assert_true(tm.orientation_step_done_bool("process_product"),
		"an offline craft stamps PROCESS A PRODUCT at settlement")
	assert_true(tm.orientation_step_done_bool("earn_clearance"),
		"offline level crossings stamp EARN A CLEARANCE at settlement")


# ---------------------------------------------------------------------------
# (c) validation — mangled namespaces are refused; stipend defect drills
# ---------------------------------------------------------------------------

func test_validation_rejects_mangled_orientation() -> void:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	var base := _valid_doc()
	for label in [
			["unknown step", {"steps_done": ["overtime_is_not_a_step"], "completed": false, "stipend_claimed": false}],
			["completed with six steps", {"steps_done": OrientationTracker.STEPS.slice(0, 6), "completed": true, "stipend_claimed": true}],
			["all steps but not completed", {"steps_done": OrientationTracker.STEPS.duplicate(), "completed": false, "stipend_claimed": false}],
			["stipend claimed while open", {"steps_done": ["work_shift"], "completed": false, "stipend_claimed": true}],
			["steps not an array", {"steps_done": "work_shift", "completed": false, "stipend_claimed": false}],
			["not an object", "filed verbally"],
		]:
		var doc: Dictionary = base.duplicate(true)
		doc["engine"]["orientation"] = label[1]
		var why: String = store._validate_doc(doc)
		assert_ne(why, "", "%s is refused" % String(label[0]))
		assert_string_contains(why, "orientation", "%s names the namespace (got '%s')" % [String(label[0]), why])
	# A T17-window v2 record WITHOUT the namespace stays loadable (hydrates fresh).
	var clean: Dictionary = base.duplicate(true)
	clean["engine"].erase("orientation")
	assert_eq(String(store._validate_doc(clean)), "",
		"an orientation-less v2 record hydrates a fresh form (documented lenience)")


func _valid_doc() -> Dictionary:
	var tm: Variant = _make_tm()
	return {
		"meta": {"created_unix": 1, "updated_unix": 1, "playtime_s": 0},
		"anchor_unix_ms": 1,
		"engine_sim_time_ms": 0,
		"content_schema_version": 1,
		"engine": tm.state.to_dict(),
		"settings": {},
	}


func test_staffing_stipend_defect_drills() -> void:
	assert_eq(int(_lib().orientation_stipend), 150,
		"orientation_stipend loads from data/staffing.json (T20-tuned 150)")
	var tmp := _tmp_dir("staffing_defects")
	for fname in ["items.json", "skills.json", "activities.json", "recipes.json",
			"drop_tables.json", "monsters.json", "equipment.json", "shop_stock.json", "xp_curves.json",
			"zones.json", "objectives.json"]:
		DirAccess.copy_absolute("res://data/%s" % fname, tmp.path_join(fname))
	for label in [
			["missing key", {"schema_version": 1, "deputies": _deputies_doc()}],
			["zero stipend", {"schema_version": 1, "orientation_stipend": 0, "deputies": _deputies_doc()}],
			["string stipend", {"schema_version": 1, "orientation_stipend": "60", "deputies": _deputies_doc()}],
		]:
		var f := FileAccess.open(tmp.path_join("staffing.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(label[1]))
		f.close()
		var result = ContentLoader.load_all(tmp)
		assert_false(result.ok(), "%s rejected" % String(label[0]))
		assert_true(result.errors.any(func(e: String) -> bool: return e.contains("orientation_stipend")),
			"%s names orientation_stipend (errors: %s)" % [String(label[0]), str(result.errors)])


func _deputies_doc() -> Array:
	var out: Array = []
	for rung in _lib().deputies:
		out.append({"id": rung.id, "price": rung.price})
	return out


# ---------------------------------------------------------------------------
# (d) + (e) the form on the concourse — cue, keyboard, low-text
# ---------------------------------------------------------------------------

func _boot_concourse(seed := SEED) -> Variant:
	var tm: Variant = _make_tm(seed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	_concourse.bind_engines(tm)
	await wait_frames(4)
	return tm


func _form() -> OrientationForm:
	return _concourse.orientation()


func _visible_focusables_in(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		var blocked := c is BaseButton and (c as BaseButton).disabled
		if c.focus_mode != Control.FOCUS_NONE and not blocked and c.is_visible_in_tree():
			out.append(c)
	for child in node.get_children():
		_visible_focusables_in(child, out)


func test_form_first_run_expanded_step1_cued_five_second_contract() -> void:
	var tm: Variant = await _boot_concourse()
	var form := _form()
	assert_not_null(form, "O-1 form mounted on the concourse")
	assert_true(form.visible, "the form is posted (never a modal)")
	assert_true(form.is_expanded(), "first run: the form meets the resident EXPANDED")
	assert_lte(form.word_count(), WORD_BUDGET,
		"low-text pin: expanded fresh form <= 40 words (got %d)" % form.word_count())
	# All seven rows, verbatim titles.
	var rows := form.step_rows()
	assert_eq(rows.size(), 7, "seven stencil lines")
	for i in rows.size():
		var title: Label = rows[i].get_node("Row/Title")
		assert_eq(title.text, STEP_TITLES[OrientationTracker.STEPS[i]],
			"row %d carries its naming-bible title verbatim" % (i + 1))
	# Step 1 is the current row: arrow glyph visible, others show the empty box.
	var row1: Button = form.row_for("work_shift")
	var row3: Button = form.row_for("file_crowns_claim")
	assert_true((row1.get_node("Row/ArrowGlyph") as Control).is_visible_in_tree(),
		"current row carries the orient_arrow glyph")
	assert_false((row3.get_node("Row/ArrowGlyph") as Control).is_visible_in_tree(),
		"a future row carries no arrow")
	# The plate cue: visible, aiming at the SCAVENGING plate.
	var cue := _concourse.cue()
	assert_true(cue.visible, "the step cue posts beside the destination plate")
	var plate1: Control = _concourse.plates()["scavenging"]
	var cue_rect := cue.get_global_rect()
	var plate_rect := plate1.get_global_rect()
	assert_almost_eq(cue_rect.position.y + cue_rect.size.y * 0.5,
		plate_rect.get_center().y, 12.0,
		"cue vertically centered on the scavenging plate")
	assert_almost_eq(cue_rect.position.x, plate_rect.end.x + 4.0, 10.0,
		"cue sits at the plate's right shoulder, pointing into it")
	# The form posts over the intake notice slot (right margin), fully on
	# screen — the standing flavor notice stands down while intake leads.
	var form_rect := form.get_global_rect()
	var housing := _concourse.docket_housing.get_global_rect()
	assert_almost_eq(form_rect.end.x, housing.end.x, 24.0,
		"form's right edge aligns with the docket frame's right margin")
	assert_true(form_rect.position.x >= 0.0 and form_rect.end.x <= 1280.0 + 1.0,
		"form fully on screen horizontally at 100%")
	assert_true(form_rect.end.y <= 720.0 + 1.0, "form fully on screen at 720p")
	# Fold control absent at zero steps (pinned open while the tutorial leads).
	assert_false(form.get_node("FormColumn/FoldForm").is_visible_in_tree(),
		"no fold control before 5 stamps (documented rule)")


func _arrow_visible(row: Button) -> bool:
	return (row.get_node("Row/ArrowGlyph") as Control).is_visible_in_tree()


func test_form_follows_steps_cue_walks_and_retires() -> void:
	var tm: Variant = await _boot_concourse()
	var form := _form()
	var cue := _concourse.cue()
	# Step 1 + 2 stamp: the current step becomes FILE A CROWNS CLAIM -> Depot.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	tm.engine.grant_xp(tm.state, "scavenging", 25)
	tm.stop_skill("scavenging")  # free the posting for the craft leg below
	_flush(tm)
	await wait_frames(2)
	assert_true(_stamp_visible(form.row_for("work_shift")), "done row shows the stamp glyph")
	assert_true(_arrow_visible(form.row_for("file_crowns_claim")),
		"the current row moved to FILE A CROWNS CLAIM")
	var depot_plate: Control = _concourse.plates()["requisition_depot"]
	var cue_rect := cue.get_global_rect()
	assert_almost_eq(cue_rect.position.y + cue_rect.size.y * 0.5,
		depot_plate.get_global_rect().get_center().y, 12.0,
		"the cue followed the step to the DEPOT plate")
	# Complete the form: the cue retires.
	_stamp_all_but(tm, ["work_shift", "earn_clearance"])
	_flush(tm)
	await wait_frames(2)
	assert_false(cue.visible, "the arrow class retires with the tutorial")


func _stamp_visible(row: Button) -> bool:
	return (row.get_node("Row/StampGlyph") as Control).is_visible_in_tree()


func test_keyboard_path_rows_and_fold() -> void:
	var tm: Variant = await _boot_concourse()
	var form := _form()
	# All seven rows are keyboard-reachable in one tab cycle from boot focus.
	var form_focus: Array[Control] = []
	_visible_focusables_in(form, form_focus)
	assert_eq(form_focus.size(), 7, "seven focusable rows (no fold at 0 steps)")
	var focusables: Array[Control] = []
	_visible_focusables_in(_concourse, focusables)
	assert_true(focusables.size() >= 7 + 8 + 4,
		"rows join the concourse tab cycle (%d focusables)" % focusables.size())
	var visited := {}
	var cur: Control = _vp.gui_get_focus_owner()
	var guard := 0
	while guard < 128 and cur != null and not visited.has(cur):
		visited[cur] = true
		cur = cur.find_next_valid_focus()
		guard += 1
	for row in form_focus:
		assert_true(visited.has(row), "%s reachable via tab chain" % row.name)

	# Row press = wayfinding: accept on the current row opens Scavenging.
	var row1: Button = form.row_for("work_shift")
	row1.grab_focus()
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), row1, "row takes focus")
	var focus_ring: StyleBoxFlat = row1.get_theme_stylebox("focus") as StyleBoxFlat
	assert_not_null(focus_ring, "row resolves an amber focus ring")
	assert_true(focus_ring.border_color.is_equal_approx(SignageTokens.SIGNAL_AMBER)
			and focus_ring.border_width_top > 0 and focus_ring.expand_margin_left > 0.0,
		"row focus ring is the theme's amber contract")

	# At five stamps the fold control posts; keyboard folds and re-opens.
	_stamp_all_but(tm, ["clear_nuisance", "deputize_resident"])
	_flush(tm)
	await wait_frames(2)
	var fold: Button = form.get_node("FormColumn/FoldForm")
	assert_true(fold.is_visible_in_tree(), "fold posts at >= 5 stamps")
	fold.grab_focus()
	fold.pressed.emit()
	await wait_frames(1)
	assert_false(form.is_expanded(), "keyboard fold collapses to the slip")
	assert_lte(form.word_count(), WORD_BUDGET, "slip within the word budget")
	var open: Button = form.get_node("FormColumn/OpenForm")
	assert_true(open.is_visible_in_tree(), "the slip carries OPEN (re-view control)")
	open.pressed.emit()
	await wait_frames(1)
	assert_true(form.is_expanded(), "keyboard OPEN re-expands the form")


func test_completion_celebrates_then_slips_low_text_every_state() -> void:
	var tm: Variant = await _boot_concourse()
	var form := _form()
	assert_lte(form.word_count(), WORD_BUDGET, "expanded incomplete <= 40 words")
	_stamp_all_but(tm, [])
	_flush(tm)
	await wait_frames(2)
	assert_true(bool(tm.state.orientation["completed"]), "form completed")
	assert_true(form.is_expanded(), "completion holds the record open for its beat")
	assert_lte(form.word_count(), WORD_BUDGET,
		"completed record <= 40 words (got %d)" % form.word_count())
	var stamp_line: Label = form.get_node("FormColumn/CompletionRecord/StampRow/StampLine")
	assert_eq(stamp_line.text, "DULY ORIENTED · FORM O-1", "the stamp posts verbatim")
	var stipend_line: Label = form.get_node("FormColumn/CompletionRecord/StipendRow/StipendLine")
	assert_eq(stipend_line.text,
		"ORIENTATION STIPEND — 150 CROWNS · THANK YOU FOR YOUR PROMPT COMPLIANCE.",
		"the stipend line posts the naming-bible reward wording")
	# The console posts the restrained notice.
	assert_string_contains(_concourse.console_serial.text, "FORM O-1 FILED",
		"console serial carries the completion notice")
	await wait_seconds(3.2)  # past the 2.6 s celebration beat
	assert_false(form.is_expanded(), "the form settles into its posted slip")
	assert_lte(form.word_count(), WORD_BUDGET, "slip <= 40 words")
	# Re-view: OPEN expands the completed record again.
	form.get_node("FormColumn/OpenForm").pressed.emit()
	await wait_frames(1)
	assert_true(form.is_expanded(), "the completed record re-views")
	assert_lte(form.word_count(), WORD_BUDGET, "re-viewed record <= 40 words")


func test_form_respects_font_scale_200() -> void:
	var tm: Variant = await _boot_concourse()
	_concourse.font_slider.value = 2.0
	await wait_frames(4)
	var form := _form()
	var form_rect := form.get_global_rect()
	assert_true(form_rect.position.x >= 0.0 and form_rect.end.x <= 1280.0 + 1.0,
		"form stays fully on screen at 200%% (x %s)" % str(form_rect))
	assert_true(form_rect.end.y <= 720.0 + 1.0,
		"form stays fully on screen at 200%% (y %s)" % str(form_rect))
	# No wrapped label inside the form collapses to a sliver (T15 lesson) —
	# measured on VISIBLE labels only (hidden state boxes measure 1 px).
	for label in _labels_in(form):
		var l := label as Label
		if l.is_visible_in_tree() and l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			assert_gt(l.get_global_rect().size.x, 40.0,
				"wrapped label %s renders horizontally at 200%%" % l.name)
	# Collapse works at 200% and pins the slip on screen.
	_stamp_all_but(tm, [])
	_flush(tm)
	await wait_frames(1)
	var fold: Button = form.get_node("FormColumn/FoldForm")
	assert_true(fold.is_visible_in_tree(), "fold posts at completion-expansion")
	fold.pressed.emit()
	await wait_frames(2)
	assert_false(form.is_expanded(), "fold works at 200%")
	assert_lte(form.get_global_rect().end.y, 720.0 + 1.0, "slip pinned on screen at 200%%")


func _labels_in(node: Node, out: Array = []) -> Array:
	if node is Label:
		out.append(node)
	for child in node.get_children():
		_labels_in(child, out)
	return out
