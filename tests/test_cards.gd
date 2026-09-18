extends GutTest
## tests/test_cards.gd — T30 compact skill-card wall (run-5 UX amendment).
##
## The user's direction is law: "I don't like all the skills being massive
## bars, I like the idea of making them condensed cards more like Melvor's
## UI." These tests pin the reworked left wall against the live engine:
##   1. STRUCTURE — the wall is a 2-column grid of 8 compact cards, reading
##      order = department order, each carrying its mark (existing SVG icon
##      set), its short stencil name + designation digit, and a 24px+ hit
##      target; skill cards add the XP micro gauge and the posting badge,
##      department cards carry their role readout only.
##   2. TAB ORDER — the engine's focus chain walks the cards in reading
##      order (row-major, the grid's own child order).
##   3. ENERGIZED PER CARD — every card, selected one by one, carries the
##      full cue set (energized variation + ">> " prefix + swell + amber
##      focus ring) while the other seven rest.
##   4. POSTING BADGES (live engine) — a skill card's filled deputy badge
##      stands exactly while that skill holds a posting (combat included);
##      the PERSONNEL card's readout counts occupied/slots.
##   5. READOUTS — card clearance/wallet/holdings/posting readouts equal
##      engine state digit-for-digit; the micro gauge fill equals XP-into-
##      level; at MAX the readout says so and the bar sits full.
##   6. GAUGE SLIMMING — the docket XP meters are 12 px (20 -> 12, the ~40%
##      cut) and stay clip-free at 200% font scale (value exact, docket fits
##      its column).
##   7. WALL FIT — all 8 cards render unscrolled inside the wall viewport at
##      1280x720, 100% font scale.
##   8. HOTKEYS — digits 1-8 select the new card order; focus follows.
##
## Harness: real concourse in a SubViewport, bare TickManager twin (never in
## tree), every state change flushed through the real batcher — test_a11y's
## discipline.

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260918
const DEPT_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest", "personnel"]
const SHORTS := ["SCAV", "FORAGE", "FORGE", "COOK",
	"PATROL", "DEPOT", "MANIFEST", "PERSONNEL"]
const SKILL_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_combat"]
const DEPT_ICONS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_combat", "crowns", "manifest_board", "deputy_badge"]

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
	_concourse.auto_reveal = false  # T33 seam: card-wall geometry pins stay hermetic
	_concourse.bind_engines(tm)
	await wait_frames(3)
	return tm


func _cards() -> Array[Button]:
	return _concourse.plate_buttons_in_order()


func _name_of(id: String) -> Label:
	return _concourse.plate_name_label(id)


func _card(id: String) -> Button:
	return _concourse.plates()[id] as Button


func _card_child(card: Button, child_name: String) -> Control:
	return card.find_child(child_name, true, false) as Control


# ---------------------------------------------------------------------------
# 1. structure — the condensed card wall
# ---------------------------------------------------------------------------

func test_wall_is_two_column_grid_of_eight_compact_cards() -> void:
	var tm: Variant = await _boot()
	var grid := _concourse.find_child("PlateWall", true, false) as GridContainer
	assert_not_null(grid, "the wall is a GridContainer")
	assert_eq(grid.columns, 2, "the grid has 2 columns (the run-5 direction)")
	var cards := _cards()
	assert_eq(cards.size(), 8, "eight department cards")
	for i in cards.size():
		var card := cards[i]
		var id: String = DEPT_IDS[i]
		assert_eq(card.name, "Plate_" + id, "card %d keeps its plate node name" % i)
		var name_l := _name_of(id)
		# Card 0 is energized at boot (scavenging is the boot department), so
		# its label carries the prefix cue here.
		var expect := "%s · %d" % [SHORTS[i], i + 1]
		if i == 0:
			expect = ">> " + expect
		assert_eq(name_l.text, expect,
			"card %d posts its short stencil name + designation digit" % i)
		assert_eq(name_l.theme_type_variation,
			"FormTitleEnergized" if i == 0 else "FormTitle",
			"card name is the stencil form title")
		# The mark: an existing SVG icon resolves on every card.
		var marks := card.find_children("*", "TextureRect", true, false)
		assert_true(marks.size() >= 1 and (marks[0] as TextureRect).texture != null,
			"card %d carries its mark" % i)
		# Hit target: the compact card stays a real button (24px WCAG floor,
		# with room).
		assert_true(card.size.x >= 24.0 and card.size.y >= 24.0,
			"card %d keeps a 24px+ hit target (%s)" % [i, str(card.size)])
		# Skill cards add the XP micro gauge + posting badge; departments
		# carry their role readout only.
		var bar := _card_child(card, "CardXP") as ProgressBar
		var badge := _card_child(card, "PostingBadge") as TextureRect
		if SKILL_IDS.has(id if id != "wasteland_patrol" else "wasteland_combat"):
			assert_not_null(bar, "skill card %d carries the XP micro gauge" % i)
			assert_eq(bar.theme_type_variation, "MicroGauge", "micro gauge uses the theme variation")
			assert_not_null(badge, "skill card %d carries the posting badge" % i)
			assert_false(badge.visible, "fresh game: card %d badge rests" % i)
		else:
			assert_null(bar, "department card %d carries no XP gauge" % i)
			assert_null(badge, "department card %d carries no posting badge" % i)


func test_tab_order_is_grid_reading_order() -> void:
	await _boot()
	var visited: Array[String] = []
	var cur: Control = _concourse.initial_focus()
	var guard := 0
	while guard < 300 and cur != null:
		if String(cur.name).begins_with("Plate_"):
			visited.append(String(cur.name).trim_prefix("Plate_"))
		cur = cur.find_next_valid_focus()
		guard += 1
	var wall_order: Array[String] = []
	for id in DEPT_IDS:
		wall_order.append(id)
	var seen: Array[String] = []
	for id in visited:
		if not seen.has(id):
			seen.append(id)
	assert_eq(seen, wall_order,
		"the tab chain meets the cards in reading order (row-major grid order)")


# ---------------------------------------------------------------------------
# 3. energized state, per card
# ---------------------------------------------------------------------------

func test_energized_cue_set_follows_each_selected_card() -> void:
	await _boot()
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await wait_frames(2)
		for other in DEPT_IDS:
			var card := _card(other)
			var name_l := _name_of(other)
			if other == id:
				assert_eq(card.theme_type_variation, "SkillCardEnergized",
					"%s selected: energized variation" % id)
				assert_string_starts_with(name_l.text, ">> ",
					"%s selected: the compact >> prefix cue" % id)
				assert_true(card.z_index > 0, "%s selected: raises toward the viewer" % id)
				# select_department(instant) applies the state without the
				# animated swell (the swell rides the real transition, pinned
				# in probe_concourse); the resting scale is exact either way.
				assert_true(card.scale.x <= 1.05 + 0.001,
					"%s selected: no shrink below rest scale" % id)
			else:
				assert_eq(card.theme_type_variation, "SkillCard",
					"%s selected: %s rests" % [id, other])
				assert_false(name_l.text.begins_with(">> "),
					"%s selected: %s carries no prefix" % [id, other])
		# The focus ring stays the amber contract on the selected card.
		var selected := _card(id)
		selected.grab_focus()
		await wait_frames(1)
		assert_true(_concourse.focus_ring_lit(selected),
			"%s card shows the amber focus ring" % id)
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
	var scav_badge := _card_child(_card("scavenging"), "PostingBadge") as TextureRect
	var patrol_badge := _card_child(_card("wasteland_patrol"), "PostingBadge") as TextureRect
	var personnel_read := _name_of("personnel").get_parent().find_child("CardRead", true, false) as Label
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

	# Combat occupies a posting like any skill: the PATROL card answers.
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = 4
	flush.call("staffing")
	await wait_frames(1)
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the patrol engages")
	flush.call("combat")
	await wait_frames(2)
	assert_true(patrol_badge.visible, "an engaged patrol raises the patrol card badge")
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

func test_card_readouts_equal_engine_state() -> void:
	var tm: Variant = await _boot()
	var lib: ContentLibrary = tm.engine.lib
	var curve: XpCurveDef = lib.xp_curve(lib.skill("scavenging").xp_curve)

	# Clearance readout + micro gauge: XP into the level, exactly.
	tm.engine.grant_xp(tm.state, "scavenging", 65)
	_flush(tm, "xp")
	await wait_frames(2)
	var level := int(tm.state.skills_level["scavenging"])
	var into := int(clampi(int(tm.state.skills_xp["scavenging"]) - int(curve.total_xp_to_reach(level)), 0, int(curve.xp_to_next(level))))
	var scav_read := _concourse.plate_name_label("scavenging").get_parent().find_child("CardRead", true, false) as Label
	var scav_bar := _card_child(_card("scavenging"), "CardXP") as ProgressBar
	assert_eq(scav_read.text, "CLR %02d · %s/%s" % [level,
		SignageFmt.num(into), SignageFmt.num(int(curve.xp_to_next(level)))],
		"scavenging card readout equals engine state digit-for-digit")
	assert_eq(scav_bar.value, float(into), "micro gauge fill equals XP into the level")
	assert_eq(scav_bar.max_value, float(int(curve.xp_to_next(level))), "micro gauge span equals the step")

	# Depot card: the wallet it tenders against. (Objectives auto-grant MERIT
	# PAY crowns on the level-ups above — the readout reads the ENGINE's
	# wallet, never a test literal.)
	tm.state.add_crowns(1_234)
	_flush(tm, "inventory")
	await wait_frames(2)
	var depot_read := _concourse.plate_name_label("requisition_depot").get_parent().find_child("CardRead", true, false) as Label
	assert_eq(depot_read.text, "%s CROWNS" % SignageFmt.num(int(tm.state.crowns)),
		"depot card reads the engine wallet (%d)" % int(tm.state.crowns))

	# Manifest card: the holdings count.
	tm.state.add_item("scrap_metal", 7)
	tm.state.add_item("glowshroom", 2)
	_flush(tm, "inventory")
	await wait_frames(2)
	var manifest_read := _concourse.plate_name_label("manifest").get_parent().find_child("CardRead", true, false) as Label
	assert_eq(manifest_read.text, "%d LINES" % tm.state.inventory.size(), "manifest card reads the holdings")

	# Maximum grade: the readout says MAX and the gauge sits full.
	tm.engine.grant_xp(tm.state, "foraging", 10_000_000)
	_flush(tm, "xp")
	await wait_frames(2)
	var forage_read := _concourse.plate_name_label("foraging").get_parent().find_child("CardRead", true, false) as Label
	var forage_bar := _card_child(_card("foraging"), "CardXP") as ProgressBar
	assert_eq(forage_read.text, "CLR 99 · MAX", "max-grade readout posts MAX")
	assert_eq(forage_bar.value, 1.0, "max-grade gauge sits full")


# ---------------------------------------------------------------------------
# 6. gauge slimming — 12 px XP meters, clip-free at 200%
# ---------------------------------------------------------------------------

func test_docket_xp_gauges_slim_and_hold_at_200_percent() -> void:
	var tm: Variant = await _boot()
	# The ~40% cut: 20 -> 12 px on every XP meter...
	var skill_gauge := (_concourse.docket_controller("scavenging") as DocketSkill).gauge
	assert_eq(skill_gauge.custom_minimum_size.y, 12.0, "skill docket XP gauge slims to 12 px")
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	assert_eq(patrol.gauge.custom_minimum_size.y, 12.0, "patrol XP gauge slims to 12 px")
	# ...while the condition/HP instruments keep their 20 px bodies.
	assert_eq(patrol.p_gauge.custom_minimum_size.y, 20.0, "resident HP gauge keeps its body")
	assert_eq(patrol.m_gauge.custom_minimum_size.y, 20.0, "fauna HP gauge keeps its body")

	# 200% font scale: the slimmed gauges carry no text of their own (the
	# mono readout below them keeps every digit), the readouts stay intact
	# and both dockets still fit their columns — no clipping anywhere.
	tm.engine.grant_xp(tm.state, "scavenging", 65)
	tm.engine.grant_xp(tm.state, "wasteland_combat", 40)
	_flush(tm, "xp")
	_concourse.font_slider.value = 2.0
	await wait_frames(3)
	assert_eq(skill_gauge.get_combined_minimum_size().y, 12.0,
		"200%: the gauge body stays 12 px (no font-driven growth to clip)")
	var read := (_concourse.docket_controller("scavenging") as DocketSkill).gauge_read
	assert_string_contains(read.text, "CLEARANCE", "200%: the mono readout keeps its digits")
	for id in ["scavenging", "wasteland_patrol"]:
		_concourse.select_department(id, true)
		await wait_frames(2)
		var scroll: ScrollContainer = _concourse.find_child("DocketScroll", true, false)
		var budget: float = scroll.size.x - 44.0 - 48.0
		var need: float = _concourse.docket_controller(id).get_combined_minimum_size().x
		assert_true(need <= budget, "200%%: %s docket fits its column (%.0f <= %.0f)" % [id, need, budget])
	_concourse.font_slider.value = 0.0
	await wait_frames(2)


# ---------------------------------------------------------------------------
# 7. wall fit — the acceptance floor at 1280x720
# ---------------------------------------------------------------------------

func test_all_eight_cards_render_without_wall_scroll_at_1280x720() -> void:
	await _boot()
	var wall := _concourse.find_child("PlateWallScroll", true, false) as ScrollContainer
	assert_eq(wall.scroll_vertical, 0, "the card wall rests unscrolled")
	var wall_rect := wall.get_global_rect()
	for i in _cards().size():
		var r := _cards()[i].get_global_rect()
		assert_true(wall_rect.encloses(r),
			"card %d (%s) renders fully inside the wall viewport (%s in %s)" % [
				i, DEPT_IDS[i], str(r), str(wall_rect)])
	# The docket still owns the right two-thirds beside the condensed wall.
	var body := _concourse.find_child("BodyRow", true, false) as Control
	var share: float = _concourse.docket_housing.get_global_rect().size.x / body.get_global_rect().size.x
	assert_true(share >= 0.63, "the docket region keeps its two-thirds share (%.2f)" % share)


# ---------------------------------------------------------------------------
# 8. hotkeys — 1-8 map onto the new card order
# ---------------------------------------------------------------------------

func test_hotkeys_select_the_new_card_order_with_focus_follow() -> void:
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
		assert_true(ok, "digit %d selects %s (the new card order)" % [i + 1, DEPT_IDS[i]])
		await wait_frames(2)
		assert_eq(_vp.gui_get_focus_owner(), _cards()[i],
			"digit %d moves focus to its card" % (i + 1))
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
	assert_true(kp_ok, "keypad 3 selects the forge (the new card order)")
