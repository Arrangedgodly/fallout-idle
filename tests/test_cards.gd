extends GutTest
## tests/test_cards.gd — T35 wall revert + condensed docket item cards
## (run-6 correction of the run-5 direction).
##
## The user's correction is law: "i want the items inside of the skills to be
## the condensed cards, not the overarching skills on the right, that was
## fine as a list. lets keep the progress bars attached though so you can
## easily see progress and what is active etc." These tests pin BOTH sides:
##
##   THE WALL (reverted, list-style — the pre-T30 shape):
##   1. STRUCTURE — one full-width column of 8 plates (VBox list, NOT the
##      T30 2-column grid), full stencil names + designation digits, 24px+
##      hit targets; skill plates RETAIN the T30 additions — the XP micro
##      gauge (MicroGauge) and the posting badge — and every plate carries
##      its mono readout.
##   2. TAB ORDER — one tab cycle walks the plates in department order.
##   3. ENERGIZED PER PLATE — the full cue set (variation + ">> " prefix +
##      amber readout + z-order) follows the selection.
##   4. POSTING BADGES (live engine) — a skill plate's badge stands exactly
##      while that skill holds a posting (combat included).
##   5. READOUTS — plate readouts equal engine state digit-for-digit; the
##      micro gauge fill equals XP-into-level; MAX at the cap.
##   6. WALL FIT — all 8 plates render unscrolled inside the wall viewport
##      at 1280x720/100%; the docket keeps its two-thirds share.
##   7. HOTKEYS — digits 1-8 select; focus follows (behavior unchanged).
##
##   THE DOCKETS (the condensed cards — where the run-5 direction lands):
##   8. CONDENSED GRID — the item cards post in an adaptive 2-up grid
##      (one column at 200%), and the docket's card stack is MEASURABLY
##      SMALLER than the pre-T35 stacked blocks (baseline constants measured
##      on the parent commit 73a9216: scavenging 1606 px / junksmithing
##      3538 px / patrol sunny board 795 px at 1280x720/100%).
##   9. HONEST MATH INTACT — rate/yield/stats/drops segments and the gate
##      serial (with the earning path) survive the condensation verbatim;
##      the gate posts INLINE (red ink, the registered pair) exactly while
##      locked.
##  10. PROGRESS ATTACHED — the ACTIVE card carries a live XP meter (the
##      gauge's own math, bound to the engine); idle cards carry none; the
##      fighting fauna card carries its HP instrument.
##
## Harness: real concourse in a SubViewport, bare TickManager twin (never in
## tree), every state change flushed through the real batcher — test_a11y's
## discipline.

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260918
const DEPT_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest", "personnel"]
const PLATE_NAMES := ["SCAVENGING", "FORAGING", "JUNKSMITHING", "COOKING",
	"WASTELAND PATROL", "REQUISITION DEPOT", "MANIFEST", "PERSONNEL"]
const SKILL_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_combat"]

var _vp: SubViewport
var _concourse: Concourse


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (card tests run on live data)")
	return result.library


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _flush(tm: Variant, region := "inventory") -> void:
	tm.batcher.mark(region)
	tm.batcher.force_flush(tm.sim_time_ms)


func _boot(seed: int = SEED) -> Variant:
	var tm: Variant = _make_tm(seed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	_concourse.auto_reveal = false  # T33 seam: shell geometry pins stay hermetic
	_concourse.bind_engines(tm)
	await wait_frames(3)
	return tm


func _select(id: String) -> void:
	_concourse.select_department(id, true)
	await wait_frames(4)


func _plates() -> Array[Button]:
	return _concourse.plate_buttons_in_order()


func _name_of(id: String) -> Label:
	return _concourse.plate_name_label(id)


func _plate(id: String) -> Button:
	return _concourse.plates()[id] as Button


func _plate_child(plate: Button, child_name: String) -> Control:
	return plate.find_child(child_name, true, false) as Control


# ---------------------------------------------------------------------------
# 1. structure — the reverted list wall, T30 additions retained
# ---------------------------------------------------------------------------

func test_wall_is_single_column_list_with_retained_readouts_bars_and_badges() -> void:
	var tm: Variant = await _boot()
	var wall := _concourse.find_child("PlateWall", true, false) as VBoxContainer
	assert_not_null(wall, "the wall is a single-column list (T35 revert — NOT the T30 grid)")
	assert_null(_concourse.find_child("PlateWall", true, false) as GridContainer,
		"the wall is not a GridContainer anymore")
	var plates := _plates()
	assert_eq(plates.size(), 8, "eight department plates")
	assert_eq(wall.get_child_count(), 8, "the wall column holds exactly the eight plates")
	for i in plates.size():
		var plate := plates[i]
		var id: String = DEPT_IDS[i]
		assert_eq(plate.name, "Plate_" + id, "plate %d keeps its plate node name" % i)
		# Full stencil name + designation digit (the pre-T30 text form).
		var name_l := _name_of(id)
		var expect := "%s · %d" % [PLATE_NAMES[i], i + 1]
		if i == 0:
			expect = ">> " + expect  # plate 0 is energized at boot
		assert_eq(name_l.text, expect,
			"plate %d posts its full stencil name + designation digit" % i)
		assert_eq(name_l.theme_type_variation,
			"FormTitleEnergized" if i == 0 else "FormTitle",
			"plate name is the stencil form title")
		# The T30 additions that survive the revert: mono readout on every
		# plate; XP micro gauge + posting badge on skill plates only.
		var read := _plate_child(plate, "CardRead") as Label
		assert_not_null(read, "plate %d carries its mono readout" % i)
		var bar := _plate_child(plate, "CardXP") as ProgressBar
		var badge := _plate_child(plate, "PostingBadge") as TextureRect
		if SKILL_IDS.has(id if id != "wasteland_patrol" else "wasteland_combat"):
			assert_not_null(bar, "skill plate %d retains the XP micro gauge" % i)
			assert_eq(bar.theme_type_variation, "MicroGauge", "micro gauge uses the theme variation")
			assert_not_null(badge, "skill plate %d retains the posting badge" % i)
			assert_false(badge.visible, "fresh game: plate %d badge rests" % i)
		else:
			assert_null(bar, "department plate %d carries no XP gauge" % i)
			assert_null(badge, "department plate %d carries no posting badge" % i)
		# Hit target + list width (the full-width plate line).
		assert_true(plate.size.x >= 24.0 and plate.size.y >= 24.0,
			"plate %d keeps a 24px+ hit target (%s)" % [i, str(plate.size)])
		assert_true(plate.size.x >= 300.0, "plate %d spans the wall column" % i)


func test_tab_order_is_list_reading_order() -> void:
	await _boot()
	var visited: Array[String] = []
	var cur: Control = _concourse.initial_focus()
	var guard := 0
	while guard < 300 and cur != null:
		if String(cur.name).begins_with("Plate_"):
			visited.append(String(cur.name).trim_prefix("Plate_"))
		cur = cur.find_next_valid_focus()
		guard += 1
	var seen: Array[String] = []
	for id in visited:
		if not seen.has(id):
			seen.append(id)
	assert_eq(seen, DEPT_IDS,
		"the tab chain meets the plates in department order (the list's own order)")


# ---------------------------------------------------------------------------
# 3. energized state, per plate
# ---------------------------------------------------------------------------

func test_energized_cue_set_follows_each_selected_plate() -> void:
	await _boot()
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await wait_frames(2)
		for other in DEPT_IDS:
			var plate := _plate(other)
			var name_l := _name_of(other)
			var read := _plate_child(plate, "CardRead") as Label
			if other == id:
				assert_eq(plate.theme_type_variation, "SkillCardEnergized",
					"%s selected: energized variation" % id)
				assert_string_starts_with(name_l.text, ">> ",
					"%s selected: the >> prefix cue" % id)
				assert_eq(read.theme_type_variation, "MonoValueEnergized",
					"%s selected: the readout switches to the amber mono" % id)
				assert_true(plate.z_index > 0, "%s selected: raises toward the viewer" % id)
				assert_true(plate.scale.x <= 1.05 + 0.001,
					"%s selected: no shrink below rest scale" % id)
			else:
				assert_eq(plate.theme_type_variation, "SkillCard",
					"%s selected: %s rests" % [id, other])
				assert_false(name_l.text.begins_with(">> "),
					"%s selected: %s carries no prefix" % [id, other])
		# The focus ring stays the amber contract on the selected plate.
		var selected := _plate(id)
		selected.grab_focus()
		await wait_frames(1)
		assert_true(_concourse.focus_ring_lit(selected),
			"%s plate shows the amber focus ring" % id)
	_concourse.select_department("scavenging", true)
	await wait_frames(1)


# ---------------------------------------------------------------------------
# 4. posting badges — engine truth, never decoration
# ---------------------------------------------------------------------------

func test_posting_badges_follow_engine_truth_and_personnel_counts() -> void:
	var tm: Variant = await _boot()
	var flush := func(region: String) -> void:
		tm.batcher.mark(region)
		tm.batcher.force_flush(tm.sim_time_ms)
	var scav_badge := _plate_child(_plate("scavenging"), "PostingBadge") as TextureRect
	var patrol_badge := _plate_child(_plate("wasteland_patrol"), "PostingBadge") as TextureRect
	var personnel_read := _plate_child(_plate("personnel"), "CardRead") as Label
	assert_false(scav_badge.visible, "fresh game: scavenging badge hidden")
	assert_eq(personnel_read.text, "0/1 POSTED", "fresh game: the personnel count reads 0/1")

	# A posted shift raises the badge and the count together.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the shift posts")
	flush.call("activity")
	await wait_frames(2)
	assert_true(scav_badge.visible, "posted shift raises the scavenging badge")
	assert_eq(personnel_read.text, "1/1 POSTED", "the count follows the posting")

	# Ceasing withdraws the badge the same flush.
	tm.stop_skill("scavenging")
	flush.call("activity")
	await wait_frames(2)
	assert_false(scav_badge.visible, "cease withdraws the badge (copy never outlives its fact)")

	# Combat occupies a posting like any skill: the PATROL plate answers.
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = 4
	flush.call("staffing")
	await wait_frames(1)
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the patrol engages")
	flush.call("combat")
	await wait_frames(2)
	assert_true(patrol_badge.visible, "an engaged patrol raises the patrol plate badge")
	# The establishment has 5 slots; the engaged patrol holds the one posting.
	assert_eq(personnel_read.text, "1/5 POSTED", "the count reads the occupied posting")
	tm.stop_combat()
	flush.call("combat")
	await wait_frames(2)
	assert_false(patrol_badge.visible, "withdraw lowers the patrol badge")
	assert_eq(personnel_read.text, "0/5 POSTED", "freeing the patrol posting drops the count")


# ---------------------------------------------------------------------------
# 5. readouts — honest digits from the engine
# ---------------------------------------------------------------------------

func test_plate_readouts_equal_engine_state() -> void:
	var tm: Variant = await _boot()
	var lib: ContentLibrary = tm.engine.lib
	var curve: XpCurveDef = lib.xp_curve(lib.skill("scavenging").xp_curve)

	# Clearance readout + micro gauge: XP into the level, exactly.
	tm.engine.grant_xp(tm.state, "scavenging", 65)
	_flush(tm, "xp")
	await wait_frames(2)
	var level := int(tm.state.skills_level["scavenging"])
	var into := int(clampi(int(tm.state.skills_xp["scavenging"]) - int(curve.total_xp_to_reach(level)), 0, int(curve.xp_to_next(level))))
	var scav_read := _plate_child(_plate("scavenging"), "CardRead") as Label
	var scav_bar := _plate_child(_plate("scavenging"), "CardXP") as ProgressBar
	assert_eq(scav_read.text, "CLR %02d · %s/%s" % [level,
		SignageFmt.num(into), SignageFmt.num(int(curve.xp_to_next(level)))],
		"scavenging plate readout equals engine state digit-for-digit")
	assert_eq(scav_bar.value, float(into), "micro gauge fill equals XP into the level")
	assert_eq(scav_bar.max_value, float(int(curve.xp_to_next(level))), "micro gauge span equals the step")

	# Depot plate: the wallet it tenders against. (Objectives auto-grant MERIT
	# PAY crowns on the level-ups above — the readout reads the ENGINE's
	# wallet, never a test literal.)
	tm.state.add_crowns(1_234)
	_flush(tm, "inventory")
	await wait_frames(2)
	var depot_read := _plate_child(_plate("requisition_depot"), "CardRead") as Label
	assert_eq(depot_read.text, "%s CROWNS" % SignageFmt.num(int(tm.state.crowns)),
		"depot plate reads the engine wallet (%d)" % int(tm.state.crowns))

	# Manifest plate: the holdings count.
	tm.state.add_item("scrap_metal", 7)
	tm.state.add_item("glowshroom", 2)
	_flush(tm, "inventory")
	await wait_frames(2)
	var manifest_read := _plate_child(_plate("manifest"), "CardRead") as Label
	assert_eq(manifest_read.text, "%d LINES" % tm.state.inventory.size(), "manifest plate reads the holdings")

	# Maximum grade: the readout says MAX and the gauge sits full.
	tm.engine.grant_xp(tm.state, "foraging", 10_000_000)
	_flush(tm, "xp")
	await wait_frames(2)
	var forage_read := _plate_child(_plate("foraging"), "CardRead") as Label
	var forage_bar := _plate_child(_plate("foraging"), "CardXP") as ProgressBar
	assert_eq(forage_read.text, "CLR 99 · MAX", "max-grade readout posts MAX")
	assert_eq(forage_bar.value, 1.0, "max-grade gauge sits full")


# ---------------------------------------------------------------------------
# 6/7. wall fit + hotkeys — the acceptance floor at 1280x720
# ---------------------------------------------------------------------------

func test_all_eight_plates_render_without_wall_scroll_at_1280x720() -> void:
	await _boot()
	var wall := _concourse.find_child("PlateWallScroll", true, false) as ScrollContainer
	assert_eq(wall.scroll_vertical, 0, "the plate wall rests unscrolled")
	var wall_rect := wall.get_global_rect()
	for i in _plates().size():
		var r := _plates()[i].get_global_rect()
		assert_true(wall_rect.encloses(r),
			"plate %d (%s) renders fully inside the wall viewport (%s in %s)" % [
				i, DEPT_IDS[i], str(r), str(wall_rect)])
	# The docket still owns the right two-thirds beside the wall.
	var body := _concourse.find_child("BodyRow", true, false) as Control
	var share: float = _concourse.docket_housing.get_global_rect().size.x / body.get_global_rect().size.x
	assert_true(share >= 0.63, "the docket region keeps its two-thirds share (%.2f)" % share)


func test_hotkeys_select_their_department_with_focus_follow() -> void:
	await _boot()
	for i in DEPT_IDS.size():
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_1 + i
		_concourse._unhandled_input(ev)
		var ok := false
		var n := 0
		while n < 400:
			if _concourse.active_department() == DEPT_IDS[i] and not _concourse.is_transitioning():
				ok = true
				break
			await wait_frames(1)
			n += 1
		assert_true(ok, "digit %d selects %s" % [i + 1, DEPT_IDS[i]])
		await wait_frames(2)
		assert_eq(_vp.gui_get_focus_owner(), _plates()[i],
			"digit %d moves focus to its plate" % (i + 1))
	# The keypad half of the table too (wait out the transition).
	var kp := InputEventKey.new()
	kp.pressed = true
	kp.keycode = KEY_KP_3
	_concourse._unhandled_input(kp)
	var kp_ok := false
	var k := 0
	while k < 400:
		if _concourse.active_department() == "junksmithing" and not _concourse.is_transitioning():
			kp_ok = true
			break
		await wait_frames(1)
		k += 1
	assert_true(kp_ok, "keypad 3 selects the forge")


# ---------------------------------------------------------------------------
# 8. the condensed docket item cards — where the run-5 direction lands
# ---------------------------------------------------------------------------

## Pre-T35 baselines, measured on the parent commit 73a9216 (laid-out card
## stack heights at 1280x720/100%, records staged on seed 20260930): the
## stacked blocks were 1606 px (scavenging tiers), 3538 px (junksmithing
## recipes) and 795 px (the patrol's sunny board). The condensed grids must
## sit measurably BELOW them.
const PRE35_GATHERING_H := 1606.0
const PRE35_PROCESSING_H := 3538.0
const PRE35_PATROL_H := 795.0


func _card_stack_height(id: String) -> float:
	var box: Control = (_concourse.docket_controller(id) as Control).get("cards_box")
	var content_h := 0.0
	for child in box.get_children():
		var c := child as Control
		if c.is_visible_in_tree():
			content_h = maxf(content_h, c.position.y + c.size.y)
	return content_h


func test_docket_item_cards_are_condensed_two_up_and_smaller_than_pre35() -> void:
	var tm: Variant = await _boot()
	# Gathering family (scavenging is the boot department).
	await wait_frames(4)
	var scav := _concourse.docket_controller("scavenging") as DocketSkill
	var grid := scav.cards_box as GridContainer
	assert_not_null(grid, "the tier cards post in a grid")
	assert_eq(grid.columns, 2, "the tier cards densify 2-up at 1280x720/100%")
	var card_w := 0.0
	for child in grid.get_children():
		card_w = maxf(card_w, (child as Control).size.x)
	assert_true(card_w <= grid.size.x * 0.55,
		"each condensed card is about half the docket width (%.0f <= %.0f)" % [card_w, grid.size.x * 0.55])
	var scav_h := _card_stack_height("scavenging")
	assert_true(scav_h < PRE35_GATHERING_H,
		"the condensed tier stack is measurably smaller than pre-T35 (%.0f < %.0f)" % [scav_h, PRE35_GATHERING_H])

	# Processing family.
	await _select("junksmithing")
	var smith := _concourse.docket_controller("junksmithing") as DocketProcessing
	assert_eq((smith.cards_box as GridContainer).columns, 2, "recipe cards densify 2-up")
	var smith_h := _card_stack_height("junksmithing")
	assert_true(smith_h < PRE35_PROCESSING_H,
		"the condensed recipe stack is measurably smaller than pre-T35 (%.0f < %.0f)" % [smith_h, PRE35_PROCESSING_H])

	# Patrol family (the sunny board's five fauna cards).
	await _select("wasteland_patrol")
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	assert_eq((patrol.cards_box as GridContainer).columns, 2, "fauna cards densify 2-up")
	var patrol_h := _card_stack_height("wasteland_patrol")
	assert_true(patrol_h < PRE35_PATROL_H,
		"the condensed fauna board is measurably smaller than pre-T35 (%.0f < %.0f)" % [patrol_h, PRE35_PATROL_H])


func test_card_grid_collapses_to_one_column_at_200_percent() -> void:
	var tm: Variant = await _boot()
	await wait_frames(2)
	_concourse.font_slider.value = 2.0
	await wait_frames(8)
	await _select("scavenging")
	var scav := _concourse.docket_controller("scavenging") as DocketSkill
	assert_eq((scav.cards_box as GridContainer).columns, 1,
		"200%: the tier cards collapse to one column (no horizontal overflow)")
	await _select("junksmithing")
	var smith := _concourse.docket_controller("junksmithing") as DocketProcessing
	assert_eq((smith.cards_box as GridContainer).columns, 1, "200%: recipe cards in one column")
	# And the docket still fits its column (the T30 width-fit law holds).
	var scroll: ScrollContainer = _concourse.find_child("DocketScroll", true, false)
	var budget: float = scroll.size.x - 44.0 - 48.0
	for id in ["scavenging", "junksmithing", "wasteland_patrol"]:
		await _select(id)
		var need: float = _concourse.docket_controller(id).get_combined_minimum_size().x
		assert_true(need <= budget, "200%%: %s docket fits its column (%.0f <= %.0f)" % [id, need, budget])
	_concourse.font_slider.value = 0.0
	await wait_frames(2)


# ---------------------------------------------------------------------------
# 9. honest math intact on the condensed cards
# ---------------------------------------------------------------------------

func test_honest_math_and_gate_behavior_survive_the_condensation() -> void:
	var tm: Variant = await _boot()
	await wait_frames(2)
	var scav := _concourse.docket_controller("scavenging") as DocketGathering
	var cards: Dictionary = scav.get("_cards")
	# The tier card's rate + yield serials, verbatim (segment flows).
	var tier: DocketSkill.Card = cards["sort_scrap_pile"]
	assert_string_contains(tier.rate_text(), "+10 XP / ACTION", "rate serial keeps the exact XP")
	assert_string_contains(tier.rate_text(), "3.0 S INTERVAL", "rate serial keeps the exact interval")
	assert_string_contains(tier.yields_text(), "YIELDS:", "yield serial keeps its head")
	assert_string_contains(tier.yields_text(), "SCRAPNEL", "yield serial names the item")
	assert_string_contains(tier.yields_text(), "70%", "yield serial keeps the exact rate")
	# The compact card body + gate behavior.
	assert_eq(tier.button.theme_type_variation, "SkillCard",
		"the condensed card uses the compact SkillCard body")
	assert_false(tier.gate_plate.visible, "level-1 tier has no gate")
	var locked: DocketSkill.Card = cards["strip_wreck"]
	assert_true(locked.gate_plate.visible, "locked tier posts its clearance gate (inline)")
	assert_string_contains(locked.gate_text.text, "CLEARANCE 5 REQUIRED", "required level shown")
	assert_string_contains(locked.gate_text.text, "EARNED BY WORKING THIS DEPARTMENT'S POSTED SHIFTS",
		"gate teaches the earning path (refinement 2, critique P2#4)")
	assert_eq(locked.gate_text.theme_type_variation, "FormTitleDanger",
		"the inline gate posts in the registered red-on-bone ink")

	# Processing: craftable counts from live inventory stay exact.
	await _select("junksmithing")
	var smith := _concourse.docket_controller("junksmithing") as DocketProcessing
	var smith_cards: Dictionary = smith.get("_cards")
	var smelt: DocketSkill.Card = smith_cards["smelt_scrap_ingot"]
	var craftable_now: int = int(tm.state.inventory.get("scrap_metal", 0)) / 3
	assert_string_contains(smelt.yields_text(), "CRAFTABLE %d" % craftable_now,
		"craftable count reads live inventory (%d)" % craftable_now)
	tm.state.add_item("scrap_metal", 12)
	_flush(tm, "inventory")
	await wait_frames(2)
	var craftable_after: int = int(tm.state.inventory.get("scrap_metal", 0)) / 3
	assert_string_contains(smelt.yields_text(), "CRAFTABLE %d" % craftable_after,
		"craftable count tracks inventory via the batched flush (%d)" % craftable_after)

	# Patrol: stats + claim serials verbatim, gate inline.
	await _select("wasteland_patrol")
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	var fauna: Dictionary = patrol.get("_cards")
	var roach: DocketPatrol.FaunaCard = fauna["junkyard_roach"]
	assert_string_contains(roach.stats_text(), "HP 18", "fauna stats keep the exact HP")
	assert_string_contains(roach.stats_text(), "ACC", "fauna stats keep accuracy")
	assert_string_contains(roach.drops_text(), "CLAIMS:", "claim serial keeps its head")
	assert_eq(roach.button.theme_type_variation, "SkillCard", "the fauna card uses the compact body")
	var bunny: DocketPatrol.FaunaCard = fauna["greater_dust_bunny"]
	assert_true(bunny.gate_plate.visible, "locked fauna posts its gate (inline)")
	assert_string_contains(bunny.gate_text.text, "CLEARANCE 4 REQUIRED", "fauna gate names the grade")
	assert_string_contains(bunny.gate_text.text, "EARNED BY PATROLLING THIS ZONE",
		"fauna gate names the earning path")


# ---------------------------------------------------------------------------
# 10. progress attached — the ACTIVE card's meter, the fighting card's HP
# ---------------------------------------------------------------------------

func test_active_card_carries_live_progress_bar_and_idle_cards_none() -> void:
	var tm: Variant = await _boot()
	await wait_frames(2)
	var scav := _concourse.docket_controller("scavenging") as DocketSkill
	var cards: Dictionary = scav.get("_cards")
	var tier: DocketSkill.Card = cards["sort_scrap_pile"]
	var other: DocketSkill.Card = cards["strip_wreck"]
	var bar: ProgressBar = tier.bar
	assert_not_null(bar, "the condensed card carries its progress meter")
	assert_false(bar.visible, "idle: the card meter rests (nothing is active)")
	assert_false(other.bar.visible, "idle: the locked card carries no meter either")

	# Post the shift: the meter attaches to the ACTIVE card and reads the
	# skill's XP-into-level — the gauge's own engine math.
	tm.engine.grant_xp(tm.state, "scavenging", 20)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the shift posts")
	_flush(tm, "activity")
	_flush(tm, "xp")
	await wait_frames(2)
	assert_true(bar.visible, "running: the ACTIVE card's meter attaches")
	assert_false(other.bar.visible, "running: only the active card carries a meter")
	var lib: ContentLibrary = tm.engine.lib
	var curve: XpCurveDef = lib.xp_curve(lib.skill("scavenging").xp_curve)
	var level := int(tm.state.skills_level["scavenging"])
	var into := int(clampi(int(tm.state.skills_xp["scavenging"]) - int(curve.total_xp_to_reach(level)), 0, int(curve.xp_to_next(level))))
	assert_eq(bar.max_value, float(int(curve.xp_to_next(level))), "meter span equals the clearance step")
	assert_eq(bar.value, float(into), "meter fill equals XP into the level (live-bound)")
	# More XP moves it on the next flush — it is live, not a snapshot.
	tm.engine.grant_xp(tm.state, "scavenging", 11)
	_flush(tm, "xp")
	await wait_frames(2)
	assert_eq(bar.value, float(clampi(into + 11, 0, int(curve.xp_to_next(level)))),
		"meter tracks the engine flush by flush")

	# End the shift: the meter detaches.
	tm.stop_skill("scavenging")
	_flush(tm, "activity")
	await wait_frames(2)
	assert_false(bar.visible, "idle again: the meter detaches (copy never outlives its fact)")


func test_fighting_fauna_card_keeps_its_hp_instrument() -> void:
	var tm: Variant = await _boot()
	await _select("wasteland_patrol")
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	var fauna: Dictionary = patrol.get("_cards")
	var roach: DocketPatrol.FaunaCard = fauna["junkyard_roach"]
	assert_false(roach.hp_bar.visible, "idle: the fauna card carries no HP instrument")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the patrol engages")
	# A couple of swings land (the twin's real funnel), then the flush.
	for _i in 60:
		tm.advance_wall_ms(100)
	_flush(tm, "combat")
	await wait_frames(2)
	var mdef: MonsterDef = tm.engine.lib.monster("junkyard_roach")
	assert_true(roach.hp_bar.visible, "fighting: the fauna card carries its HP instrument")
	assert_eq(roach.hp_bar.max_value, float(mdef.max_hp), "HP instrument span equals the fauna's max HP")
	assert_true(roach.hp_bar.value < float(mdef.max_hp),
		"HP instrument is live (%.0f < %.0f after the opening swings)" % [roach.hp_bar.value, mdef.max_hp])
	# Only the fighting card carries it.
	var bunny: DocketPatrol.FaunaCard = fauna["greater_dust_bunny"]
	assert_false(bunny.hp_bar.visible, "unengaged fauna stays instrument-free")
	# Withdraw: the instrument detaches.
	tm.stop_combat()
	_flush(tm, "combat")
	await wait_frames(2)
	assert_false(roach.hp_bar.visible, "withdraw detaches the instrument")
