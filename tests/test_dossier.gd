extends GutTest
## tests/test_dossier.gd — T26 DEPARTMENTAL DOSSIER UI wiring (Theme/UI lane,
## Daredevil constraints).
##
## Instantiates the real concourse bound to a fresh TickManager twin (never in
## the tree; advance_wall_ms is the only clock input — same discipline as
## test_patrol.gd) and asserts the dossier registers render from LIVE data,
## progress readouts equal engine counters, a real stamp dims its row + posts
## the naming-bible-verbatim notice (log stamp + console flash, no claim
## button anywhere), the completion plate posts exactly once, the O-1 fold
## discipline holds, and the Patrol zone tab pair swaps one zone's board +
## certificates at a time (Addendum 2's recorded direction) with a keyboard
## path. Everything flows through the batched/discrete signal contract.


const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260915

## dept id -> dossier title (naming-bible §10 T22 rows — verbatim, binding).
const DOSSIER_TITLES := {
	"scavenging": "RECLAMATION DOSSIER",
	"foraging": "GROUNDSKEEPING DOSSIER",
	"junksmithing": "FABRICATION DOSSIER",
	"cooking": "MESS DOSSIER",
	"wasteland_patrol": "EXTERIOR DOSSIER",
}


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (dossier tests run on live data)")
	return result.library


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _pump(tm: Variant, total_ms: int, chunk_ms := 500) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


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


func _docket(c: Concourse, dept: String) -> Docket:
	var d := c.docket_controller(dept)
	assert_not_null(d, "%s controller mounted" % dept)
	c.select_department(dept, true)
	return d


func _register(c: Concourse, dept: String) -> DossierRegister:
	var d := _docket(c, dept)
	var reg: DossierRegister = d.get("register")
	assert_not_null(reg, "%s mounts a DossierRegister" % dept)
	return reg


func _log_has(log: ItemList, needle: String) -> bool:
	for i in log.item_count:
		if needle in log.get_item_text(i):
			return true
	return false


func _log_count(log: ItemList, needle: String) -> int:
	var n := 0
	for i in log.item_count:
		if needle in log.get_item_text(i):
			n += 1
	return n


func _row_for(reg: DossierRegister, objective_id: String) -> DossierRegister.RegisterRow:
	for row in reg.rows():
		if row.objective_id == objective_id:
			return row
	return null


func _visible_card_count(patrol: DocketPatrol) -> int:
	var n := 0
	for id in (patrol.get("_cards") as Dictionary):
		if (patrol.get("_cards") as Dictionary)[id].button.visible:
			n += 1
	return n


# ---------------------------------------------------------------------------
# the five registers (live data, posted order, T22 titles)
# ---------------------------------------------------------------------------

func test_five_dossiers_render_23_rows_from_live_data() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	for dept in DOSSIER_TITLES:
		var reg := _register(c, dept)
		assert_false(reg.is_expanded(), "%s register mounts folded (the O-1 fold discipline)" % dept)
		reg.expand()  # rows build at first expansion (perf-idle discipline)
		await wait_frames(1)
		var rows := reg.rows()
		assert_eq(rows.size(), 23, "%s register renders all 23 objectives (T25 set)" % dept)
		assert_eq(reg.summary_text(), "D.O.C.S. FORM R-1 · 0/23 STAMPED",
			"%s header posts the form serial + progress verb (got '%s')" % [dept, reg.summary_text()])
		assert_string_contains(reg.get_node("RegisterColumn/DossierTitle").text,
			DOSSIER_TITLES[dept], "%s posts its T22 dossier title" % dept)
		# Posted order + honest lines straight from the engine's own read.
		var summary: Dictionary = tm.dossier_summary(_skill_of(dept))
		for i in rows.size():
			var row := rows[i]
			assert_eq(row.objective_id, String(summary["rows"][i]["id"]),
				"%s row %d is the engine's posted-order objective" % [dept, i])
			assert_eq(row.title.text, String(summary["rows"][i]["description"]),
				"%s row %d quotes the data description verbatim" % [dept, i])
			assert_false(row.stamp.visible, "%s fresh row %d unstamped (empty box state)" % [dept, i])
			assert_true(row.empty_box.visible, "%s fresh row %d shows the empty checkbox square" % [dept, i])


func _skill_of(dept: String) -> String:
	return "wasteland_combat" if dept == "wasteland_patrol" else dept


# ---------------------------------------------------------------------------
# progress readouts == engine counters
# ---------------------------------------------------------------------------

func test_progress_readouts_match_engine_counters() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var reg := _register(c, "scavenging")
	reg.expand()  # rows build at first expansion
	await wait_frames(1)

	tm.start_activity("sort_scrap_pile")
	var acted := 0
	while acted < 3:
		_pump(tm, 1_000, 250)
		acted = int(tm.state.objectives["counters"].get("activity:sort_scrap_pile", 0))
	tm.stop_skill("scavenging")
	_flush(tm, "inventory")
	_flush(tm, "xp")
	await wait_frames(1)

	for i in reg.rows().size():
		var row := reg.rows()[i]
		var truth: Dictionary = tm.objectives.progress(tm.state, row.objective_id)
		var expected := "%s/%s" % [SignageFmt.num(int(truth["current"])), SignageFmt.num(int(truth["target"]))]
		assert_eq(row.progress.text, expected,
			"row %d readout equals the live counter (%s vs %s)" % [i, row.progress.text, expected])
	# The worked activity's own row moved off zero (the register is alive).
	var sort_row := _row_for(reg, "scav_sort_25")
	assert_ne(sort_row, null, "scav_sort_25 row present")
	assert_string_contains(sort_row.progress.text, "/25", "gather rung reads against its data target")
	assert_gt(int(sort_row.progress.text.split("/")[0].replace(",", "")), 0,
		"worked actions show in the readout")


# ---------------------------------------------------------------------------
# a real stamp: row dims, notice rides the stamp idiom, console flashes
# ---------------------------------------------------------------------------

func test_stamp_dims_row_notices_and_flashes_console() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var reg := _register(c, "scavenging")
	reg.expand()  # rows build at first expansion
	await wait_frames(1)
	var forage_log: ItemList = (_docket(c, "foraging") as DocketSkill).log
	var forage_lines := forage_log.item_count

	# A real level crossing stamps scav_clearance_2 (reward 30 crowns from
	# data) through the engine's own level_up seam.
	tm.engine.grant_xp(tm.state, "scavenging", 500)
	_flush(tm, "xp")
	await wait_frames(1)

	var row2 := _row_for(reg, "scav_clearance_2")
	assert_ne(row2, null, "clearance-2 row present")
	assert_true(row2.stamp.visible, "stamped row shows the red stamp_check glyph")
	assert_false(row2.empty_box.visible, "stamped row retires the empty box")
	assert_eq((row2.title as Label).get_theme_color("font_color"), SignageTokens.NAVY_DIM,
		"stamped row dims to the registered NAVY_DIM-on-paper pair")
	assert_eq((row2.progress as Label).get_theme_color("font_color"), SignageTokens.NAVY_DIM,
		"stamped row's readout dims with it")

	# The summary counts engine truth, never a UI tally.
	var stamped_n := int(tm.objectives.skill_summary(tm.state, "scavenging")["stamped"])
	assert_eq(reg.summary_text(), "D.O.C.S. FORM R-1 · %d/23 STAMPED" % stamped_n,
		"summary equals the engine's stamped count")

	# Auto-grant notice: log stamp + console flash, naming-bible verbatim.
	assert_true(_log_has((_docket(c, "scavenging") as DocketSkill).log,
		"FORM R-1 STAMPED · 30 CROWNS POSTED"),
		"grant posts the verbatim FORM R-1 notice in the owning docket's log")
	assert_string_contains(c.console_serial.text, "FORM R-1 STAMPED",
		"console serial flashes the notice (got '%s')" % c.console_serial.text)
	assert_eq(forage_log.item_count, forage_lines,
		"another department's log stays silent (ownership respected)")


# ---------------------------------------------------------------------------
# completion: the plate posts exactly once; the fold keeps the stamp
# ---------------------------------------------------------------------------

func test_completion_plate_posts_once_and_folds_to_stamp_line() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var reg := _register(c, "scavenging")
	var docket := _docket(c, "scavenging") as DocketSkill

	# Force every scavenging condition true through the counters (engine
	# seams own evaluation; the cascade stamps in canonical posted order —
	# re-entrant XP legs stamp through the nested passes, so the SET is the
	# truth, not the outer call's return).
	tm.objectives.ensure_objectives(tm.state)
	var counters: Dictionary = tm.state.objectives["counters"]
	for obj_id in tm.engine.lib.objectives:
		var obj: ObjectiveDef = tm.engine.lib.objectives[obj_id]
		if obj.skill != "scavenging" or obj.counter_key == "":
			continue
		counters[obj.counter_key] = maxi(int(counters.get(obj.counter_key, 0)), obj.target)
	tm.objectives.evaluate(tm.state)
	assert_eq(tm.objectives.stamped_count_for_skill(tm.state, "scavenging"), 23,
		"all 23 scavenging objectives stamp in the cascade")
	_flush(tm, "objectives")
	await wait_frames(1)

	assert_true(reg.is_complete(), "register reads completion from engine truth")
	assert_eq(reg.completion_stamp_text(), "ALL 23 STAMPED · FORM R-1",
		"completion plate posts the data-derived stamp line")
	assert_true(reg.is_expanded(), "completion expands the register (the win moment posts)")
	assert_true(reg.get_node("RegisterColumn/CompletionRecord").visible,
		"ALL N STAMPED plate visible while expanded")
	assert_true(_log_has(docket.log, "ALL 23 STAMPED · FORM R-1"),
		"the log carries the completion line once")

	# Exactly once: a re-evaluation stamps nothing new and re-posts nothing.
	var crowns := int(tm.state.crowns)
	assert_eq(tm.objectives.evaluate(tm.state).size(), 0, "re-evaluation stamps nothing")
	assert_eq(_log_count(docket.log, "ALL 23 STAMPED"), 1, "completion line appears once")
	assert_eq(int(tm.state.crowns), crowns, "re-evaluation grants nothing")

	# The folded record IS the stamp (the O-1 slip precedent).
	reg.fold()
	assert_eq(reg.summary_text(), "ALL 23 STAMPED · FORM R-1",
		"folded summary line is the completion stamp")
	assert_eq(reg.summary_text(), reg.completion_stamp_text(),
		"folded line and plate agree (one source of truth)")
	reg.expand()
	assert_true(reg.get_node("RegisterColumn/CompletionRecord").visible,
		"re-expanding still posts the plate (stamped rows stay stamped)")


# ---------------------------------------------------------------------------
# fold discipline + the no-claim rule
# ---------------------------------------------------------------------------

func test_fold_open_cycle_keeps_stamps_and_claims_nothing() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var reg := _register(c, "scavenging")
	var docket := _docket(c, "scavenging") as DocketSkill

	tm.engine.grant_xp(tm.state, "scavenging", 500)  # stamp scav_clearance_2
	_flush(tm, "xp")
	await wait_frames(1)

	# OPEN expands (rows + the standing no-claim notice + FOLD); FOLD re-slips.
	assert_false(reg.get_node("RegisterColumn/ObjectiveRows").visible, "rows folded at mount")
	reg.get_node("RegisterColumn/OpenRegister").pressed.emit()
	assert_true(reg.is_expanded(), "OPEN expands the register")
	assert_true(reg.get_node("RegisterColumn/ObjectiveRows").visible, "rows post expanded")
	assert_string_contains(reg.get_node("RegisterColumn/NoClaimNotice").text,
		"MERIT PAY POSTS ITSELF. NO CLAIM IS REQUIRED. NONE HAS EVER BEEN.",
		"the standing no-claim footer posts verbatim (expanded)")
	reg.get_node("RegisterColumn/FoldRegister").pressed.emit()
	assert_false(reg.is_expanded(), "FOLD re-slips the register")

	# Stamped rows stay stamped through the fold cycle.
	var row2 := _row_for(reg, "scav_clearance_2")
	assert_true(row2.stamp.visible, "stamp survives the fold cycle")
	assert_false(row2.empty_box.visible, "empty box never returns for a stamped row")

	# No claim button anywhere: a row press changes nothing (rewards post
	# themselves — the DULY ORIENTED precedent, generalized).
	var stamped := (tm.state.objectives["stamped"] as Array).size()
	var crowns := int(tm.state.crowns)
	var lines := docket.log.item_count
	for row in reg.rows():
		row.pressed.emit()
	assert_eq((tm.state.objectives["stamped"] as Array).size(), stamped, "row presses stamp nothing")
	assert_eq(int(tm.state.crowns), crowns, "row presses grant nothing")
	assert_eq(docket.log.item_count, lines, "row presses log nothing")


# ---------------------------------------------------------------------------
# Patrol zone tabs (Addendum 2's recorded direction)
# ---------------------------------------------------------------------------

func test_patrol_zone_tabs_switch_boards_and_certificates() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var patrol := _docket(c, "wasteland_patrol") as DocketPatrol

	# Default: the Sunny board, one zone's fauna at a time.
	assert_eq(patrol.active_zone, "dusty_flats", "Sunny zone posts by default")
	assert_true(patrol.zone_tab_sunny.button_pressed, "Sunny tab pressed")
	assert_false(patrol.zone_tab_gift.button_pressed, "Gift Court tab not pressed")
	assert_string_contains(patrol.zone_tab_sunny.text, ">> THE SUNNY EXCLUSION ZONE",
		"active tab carries the >> prefix (non-color cue)")
	assert_string_contains(patrol.zone_serial.text, "DESIGNATED OUTDOOR AMENITY AREA",
		"zone serial posts the Sunny signage form")
	assert_eq(_visible_card_count(patrol), 5, "exactly the Sunny five post")
	assert_false((patrol.get("_cards") as Dictionary)["regional_manager"].button.visible,
		"Gift Court boss hidden while Sunny posts")

	# Switch to the Gift Court: its six post, the copy swaps, both
	# certificates stay hidden (neither zone has cleared).
	patrol.zone_tab_gift.pressed.emit()
	assert_eq(patrol.active_zone, "gift_court", "tab press swaps the zone")
	assert_eq(_visible_card_count(patrol), 6, "exactly the Gift Court six post")
	assert_string_contains(patrol.zone_serial.text,
		"GIFT COURT — DESIGNATED RETAIL AMENITY AREA",
		"zone serial swaps to the T24-registered Gift Court copy")
	var rm = (patrol.get("_cards") as Dictionary)["regional_manager"]
	assert_string_contains(rm.tag_line.text, "REGIONAL AUTHORITY DETECTED",
		"the Regional Manager posts its T24 boss plate")
	var cart = (patrol.get("_cards") as Dictionary)["runaway_cart"]
	assert_string_contains(cart.tag_line.text, "UNSHELVED",
		"zone-2 pests read the UNSHELVED classification family")
	assert_false(patrol.zone_plate.visible, "no Sunny certificate (zone not cleared)")
	assert_false(patrol.zone_plate_gift.visible, "no Gift Court certificate (boss standing)")

	# The Regional Manager falls: the certificate posts ON THE GIFT COURT TAB
	# (the zone:gift_court lifetime counter — engine truth, repeat-kill safe).
	tm.objectives.note_victory(tm.state, "regional_manager")
	_flush(tm, "objectives")
	_flush(tm, "combat")
	await wait_frames(1)
	assert_true(patrol.zone_plate_gift.visible, "Gift Court certificate posts on its own tab")
	assert_string_contains(
		patrol.zone_plate_gift.get_child(0).get_child(0).text,
		"POSTED — SECTOR G · D.O.C.S. FORM Z-9",
		"the certificate carries the registered sector-G serial")
	assert_true(patrol.zone_plate.visible == false,
		"Sunny certificate still hidden on the Gift Court tab")

	# Back to Sunny: its certificate mounts exactly on its own truth
	# (combat.zone_clear, the persisted first-boss flag).
	patrol.zone_tab_sunny.pressed.emit()
	assert_false(patrol.zone_plate_gift.visible, "Gift Court certificate stays on its tab")
	assert_false(patrol.zone_plate.visible,
		"Sunny certificate hidden until the Superintendent falls")
	tm.state.combat["zone_clear"] = true
	_flush(tm, "combat")
	await wait_frames(1)
	assert_true(patrol.zone_plate.visible, "Sunny certificate posts on its own tab once cleared")
	patrol.zone_tab_gift.pressed.emit()
	assert_false(patrol.zone_plate.visible, "one zone's certificate at a time")


func test_zone_tabs_keyboard_operable() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var patrol := _docket(c, "wasteland_patrol") as DocketPatrol

	# The tab pair is focusable, arrow-wired, and rides the tab chain.
	for tab in [patrol.zone_tab_sunny, patrol.zone_tab_gift]:
		assert_eq(tab.focus_mode, Control.FOCUS_ALL, "zone tab focusable")
	assert_eq(patrol.zone_tab_sunny.focus_neighbor_right, patrol.zone_tab_gift.get_path(),
		"arrow-right hops Sunny -> Gift Court")
	assert_eq(patrol.zone_tab_gift.focus_neighbor_left, patrol.zone_tab_sunny.get_path(),
		"arrow-left hops Gift Court -> Sunny")

	var focusables := c.focusable_controls()
	assert_true(focusables.has(patrol.zone_tab_sunny), "Sunny tab in the focusable set")
	assert_true(focusables.has(patrol.zone_tab_gift), "Gift Court tab in the focusable set")
	var visited := {}
	var cur: Control = c.initial_focus()
	var guard := 0
	while guard < 256 and not visited.has(cur):
		visited[cur] = true
		cur = cur.find_next_valid_focus()
		guard += 1
	for f in focusables:
		assert_true(visited.has(f), "focusable %s reachable via tab chain" % f.name)

	# Keyboard accept on the focused Gift Court tab swaps the board.
	patrol.zone_tab_gift.grab_focus()
	await wait_frames(1)
	assert_true(patrol.zone_tab_gift.has_focus(), "Gift Court tab holds focus")
	patrol.zone_tab_gift.pressed.emit()
	assert_eq(patrol.active_zone, "gift_court", "accept on the focused tab posts its board")


# ---------------------------------------------------------------------------
# the EXTERIOR DOSSIER binds to the combat skill
# ---------------------------------------------------------------------------

func test_patrol_register_binds_combat_skill() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	var patrol := _docket(c, "wasteland_patrol") as DocketPatrol
	var reg: DossierRegister = patrol.register
	assert_eq(reg.skill_id, "wasteland_combat",
		"the register binds the content-derived combat skill id")
	assert_eq(reg.get_node("RegisterColumn/DossierTitle").text, "EXTERIOR DOSSIER",
		"the patrol register posts the T22 EXTERIOR title")
	reg.expand()  # rows build at first expansion
	assert_eq(reg.rows().size(), 23, "EXTERIOR DOSSIER renders its 23 objectives")
	# The dossier rides the patrol's own log + register: a kill shows in the
	# kill rung's readout through the engine's victory seam.
	tm.objectives.note_victory(tm.state, "junkyard_roach")
	_flush(tm, "objectives")
	await wait_frames(1)
	var litter_row := _row_for(reg, "combat_litterbug_10")
	assert_ne(litter_row, null, "Litterbug kill rung present")
	assert_eq(litter_row.progress.text, "1/10",
		"first Litterbug victory counts in the kill rung (engine seam)")
