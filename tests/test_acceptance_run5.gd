extends GutTest
## tests/test_acceptance_run5.gd — T34 RUN-5 ACCEPTANCE JOURNEYS (one suite,
## one journey per Scope Amendment 3 complaint — each certification drives the
## same route the run's fixes shipped, through the REAL input pipeline):
##
##   (a) COMPACT SHELL (complaint #3, T30) — all 8 compact cards keyboard-
##       reachable in GRID ORDER (one tab walk), the 1-8 hotkeys select from
##       anywhere with focus following the jump, and the wall is LIVE: posting
##       badges and role readouts flip with engine truth on the batched flush.
##       Also pins the T34 cleanup fixes: the O-1 slip's completion mark reads
##       honestly (outline while the tutorial runs) and the Personnel board
##       summary carries its own plural ("1 POSTING", not "1 POSTINGS").
##   (b) REFUSAL FEEDBACK (complaint #1, T31) — a REAL mouse click on a
##       blocked card fires the refusal strip at the TOP of the docket (child
##       index 0, in-flow) with the truthful reason and the REASSIGN
##       restatement; one focused ui_accept executes the swap; the strip
##       confirms what actually ceased (engine truth).
##   (c) DEPOT (complaint #2, T32) — BUY/SELL tabs in the zone-tab grammar,
##       keyboard-operable, the SELL lines leading their board; every rung of
##       the quantity ladder (1 / 10% / 25% / 50% / 100%) plus CUSTOM posts
##       EXACT wallet math through the real engine (disabled at 0); out-of-
##       range custom amounts are refused in voice, never clamped silently.
##   (d) TUTORIAL WALKTHROUGH (complaint #4, T33) — a fresh save driven
##       through all seven steps on the reveal machinery + primary buttons
##       alone, every press's target asserted fully in view, the whole
##       journey inside a bounded UI-action budget (<= 25 presses; the user
##       took over five minutes). Suite-side re-certification of T33's
##       machinery assertions (tests/test_tutorial_reveal.gd owns the deep
##       per-step pins; this is the acceptance bar).
##   (e) NO BLOCKADE REGRESSION (run-4 contract, T29) — the blockade-class
##       audit (no input-present non-modal control may paint over a
##       focusable) re-run SUITE-SIDE across the representative shell states
##       at both font scales: fresh expanded, mid-tutorial running, the 5/7
##       slip, completed, a posted save notice, MAIL CALL open and closed.
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (test_engine.gd's discipline); the concourse runs in a SubViewport
## driven through the REAL input pipeline (test_orientation.gd's); the depot
## journey boots the T25 objective-free fixture so dossier merit pay cannot
## perturb exact wallet pins (test_depot_tabs.gd's rule); the walkthrough runs
## on the shipped content library (the whole economy is the subject).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const ObjectiveFreeLib := preload("res://tests/objective_free_lib.gd")

const SEED := 20260922
const WALKTHROUGH_SEED := 20260921
const ACTION_BUDGET := 25

const GLOW_VALUE := 2  # data/items.json — the honest one-rate tender

const IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest", "personnel"]

var _vp: SubViewport
var _concourse: Concourse
var _actions := 0


# ------------------------------------------------------------------ harness
func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (the acceptance runs on live data)")
	return result.library


func _make_tm(seed: int, p_lib: ContentLibrary = null) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(p_lib if p_lib != null else _lib(), seed)
	return tm


func _flush(tm: Variant) -> void:
	tm.batcher.mark("inventory")
	tm.batcher.mark("orientation")
	tm.batcher.mark("xp")
	tm.batcher.force_flush(tm.sim_time_ms)


func _pump(tm: Variant, total_ms: int, chunk_ms := 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _boot(seed: int = SEED, p_lib: ContentLibrary = null, reveal := false) -> Variant:
	var tm: Variant = _make_tm(seed, p_lib)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	if not reveal:
		_concourse.auto_reveal = false  # journeys (a)(b)(c)(e) pin the shell
	# (d) leaves the seam ON: the boot reveal IS part of its machinery.
	_concourse.bind_engines(tm)
	# Production boot fidelity + battery-order determinism (the T33 lesson):
	# a session starts at the 100% scale whatever a prior suite's slider did.
	var ui_theme: Node = get_tree().root.get_node_or_null("UiTheme")
	if ui_theme != null:
		ui_theme.apply_font_scale(1.0)
	await wait_frames(4)
	return tm


func _await_department(id: String, budget_frames := 240) -> bool:
	var n := 0
	while n < budget_frames and (_concourse.is_transitioning()
			or _concourse.active_department() != id):
		await wait_frames(1)
		n += 1
	return _concourse.active_department() == id and not _concourse.is_transitioning()


func _push_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


func _push_tab() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_focus_next"
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


func _push_digit(keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = true
	_vp.push_input(ev)
	var rel := ev.duplicate() as InputEventKey
	rel.pressed = false
	_vp.push_input(rel)


func _real_click(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	_vp.push_input(ev)
	await wait_frames(1)
	var rel := ev.duplicate() as InputEventMouseButton
	rel.pressed = false
	_vp.push_input(rel)


func _real_type(text: String) -> void:
	for ch in text:
		var ev := InputEventKey.new()
		var lower := ch.to_lower()
		if lower >= "a" and lower <= "z":
			ev.keycode = KEY_A + (lower.unicode_at(0) - "a".unicode_at(0))
		else:
			ev.keycode = ch.unicode_at(0) as Key
		ev.unicode = ch.unicode_at(0)
		ev.pressed = true
		_vp.push_input(ev)
		var rel := ev.duplicate() as InputEventKey
		rel.pressed = false
		_vp.push_input(rel)


func _push_enter() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	_vp.push_input(ev)
	var rel := ev.duplicate() as InputEventKey
	rel.pressed = false
	_vp.push_input(rel)


func _badge(card: Button) -> TextureRect:
	return card.find_child("PostingBadge", true, false) as TextureRect


## The walkthrough's arrival: the bulkhead finishes, then the reveal's own
## layout frame lands — scroll + pulse are asserted after this.
func _await_settled(max_frames := 240) -> void:
	var n := 0
	while n < max_frames and _concourse.is_transitioning():
		await wait_frames(1)
		n += 1
	await wait_frames(3)


func _in_view(ctrl: Control) -> bool:
	var vr := _concourse.docket_scroll.get_global_rect()
	var cr := ctrl.get_global_rect()
	return vr.encloses(cr.grow(-2.0))


func _assert_in_view(ctrl: Control, what: String) -> void:
	var vr := _concourse.docket_scroll.get_global_rect()
	var cr := ctrl.get_global_rect()
	assert_true(vr.encloses(cr.grow(-2.0)),
		"%s fully in view (target %s vs viewport %s)" % [what, str(cr), str(vr)])


## One walkthrough press — the acceptance accounting. A docket control must
## already be fully in view (the reveal put it there); the press rides the
## real input pipeline.
func _press(btn: Button, what: String, in_docket := true) -> void:
	_actions += 1
	assert_true(btn.is_visible_in_tree(),
		"walkthrough action %d (%s): control visible" % [_actions, what])
	if in_docket:
		_assert_in_view(btn, "walkthrough action %d (%s)" % [_actions, what])
	btn.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)


# ---------------------------------------------------------------------------
# (a) COMPACT SHELL — grid order, hotkeys 1-8, live badges
# ---------------------------------------------------------------------------

func test_a_compact_shell_grid_order_hotkeys_and_live_badges() -> void:
	var tm: Variant = await _boot()
	var plates: Array[Button] = _concourse.plate_buttons_in_order()
	assert_eq(plates.size(), 8, "the compact wall posts all eight cards")
	# Reading order = department order (row-major in the 2-column grid), and
	# every card carries its own designation digit (the hotkey it answers).
	for i in plates.size():
		assert_eq(String(plates[i].get_meta("dept_id")), IDS[i],
			"card %d is %s in grid order" % [i, IDS[i]])
		var label: Label = _concourse.plate_name_label(IDS[i])
		assert_string_contains(label.text, "· %d" % (i + 1),
			"card %d posts its designation digit (%s)" % [i, label.text])
		assert_string_contains(String(plates[i].tooltip_text).to_lower(), "press %d" % (i + 1),
			"card %d's tooltip names the key" % i)

	# KEYBOARD GRID ORDER: one tab walk reaches every card in reading order.
	plates[0].grab_focus()
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), plates[0], "the walk starts at card 1")
	for i in range(1, 8):
		_push_tab()
		await wait_frames(1)
		assert_eq(_vp.gui_get_focus_owner(), plates[i],
			"tab %d lands on card %d (grid order)" % [i, i + 1])

	# HOTKEYS 1-8: a real digit selects its department from anywhere, and
	# focus follows the jump (the tab chain resumes INTO the new docket).
	# Steer off card 1 first so every loop press is a real navigation.
	_push_digit(KEY_3)
	assert_true(await _await_department("junksmithing"), "the pre-step parks on the forge")
	for i in 8:
		_push_digit([KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8][i])
		assert_true(await _await_department(IDS[i]),
			"hotkey %d selects %s through the real input pipeline" % [i + 1, IDS[i]])
		assert_eq(_vp.gui_get_focus_owner(), plates[i], "focus followed hotkey %d" % (i + 1))

	# BADGES LIVE: the filled deputy badge burns exactly while the department
	# holds a posting — skills and the patrol alike — and the Personnel card's
	# role readout follows the engine on the same flush.
	var scav_badge := _badge(plates[0])
	var patrol_badge := _badge(plates[4])
	assert_false(scav_badge.visible, "SCAV badge dark while idle")
	assert_false(patrol_badge.visible, "PATROL badge dark while idle")
	var p_read: Label = plates[7].find_child("CardRead", true, false)
	assert_eq(p_read.text, "0/1 POSTED", "the Personnel readout reads the empty board")
	# The patrol counts as a posting too (its badge follows the fight); it
	# takes the empty board first (one posting per concurrent shift).
	assert_true(bool(tm.engage_monster("junkyard_roach")["ok"]), "the patrol engages")
	_flush(tm)
	await wait_frames(2)
	assert_true(patrol_badge.visible, "PATROL badge burns while the fight runs")
	assert_eq(p_read.text, "1/1 POSTED", "the Personnel readout counts the patrol")
	tm.stop_combat()
	_flush(tm)
	await wait_frames(2)
	assert_false(patrol_badge.visible, "PATROL badge darkens when the fight ends")
	assert_eq(p_read.text, "0/1 POSTED", "the readout reads the freed board")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the scav posting starts")
	_flush(tm)
	await wait_frames(2)
	assert_true(scav_badge.visible, "SCAV badge burns while the posting runs")
	assert_eq(p_read.text, "1/1 POSTED", "the Personnel readout follows the assignment")
	tm.stop_skill("scavenging")
	_flush(tm)
	await wait_frames(2)
	assert_false(scav_badge.visible, "SCAV badge darkens when the posting ceases")

	# T34 cleanup pins (capture-evidenced): the O-1 slip's completion mark is
	# an honest OUTLINE while the tutorial runs, and the Personnel summary
	# carries its own plural at a one-slot establishment.
	var slip_stamp: Control = _concourse.orientation().find_child("SlipStamp", true, false)
	assert_false(bool(slip_stamp.get("stamped")),
		"the slip's completion mark is unstamped while the tutorial runs (no false done cue)")
	var summary: Label = (_concourse.docket_controller("personnel") as DocketPersonnel).summary_line
	assert_string_contains(summary.text, "· 1 POSTING ·",
		"the board summary reads singular at one slot (%s)" % summary.text)


# ---------------------------------------------------------------------------
# (b) REFUSAL FEEDBACK — real click, truthful strip, one-press REASSIGN
# ---------------------------------------------------------------------------

func test_b_refusal_real_click_truthful_strip_and_one_press_reassign() -> void:
	var tm: Variant = await _boot()
	_concourse.orientation().fold()  # the steady-state slip: room to click
	await wait_frames(1)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the board is full")

	# The resident clicks the FORAGE card (a real mouse click through the
	# viewport pipeline) — the department opens.
	var forage_plate: Button = _concourse.plates()["foraging"]
	await _real_click(forage_plate.get_global_rect().get_center())
	assert_true(await _await_department("foraging"),
		"a real click on the card opens the foraging docket")
	var forage: DocketGathering = _concourse.docket_controller("foraging")
	var card = forage._cards["walk_the_glow_rows"]  # the Card model; its .button is the node
	var card_btn: Button = card.button
	_concourse.docket_scroll.ensure_control_visible(card_btn)
	await wait_frames(2)

	# The resident clicks the blocked card: IMMEDIATE feedback, at the TOP.
	await _real_click(card_btn.get_global_rect().get_center())
	await wait_frames(2)
	assert_eq(forage.refusal_strip.get_index(), 0,
		"the refusal strip pins the docket's top (child index 0, in-flow)")
	assert_true(forage.refusal_strip.visible, "the strip posts on the refused click")
	assert_eq(forage.strip_head.text, "POSTING REFUSED", "the head is the registered serial")
	assert_eq(forage.strip_serial.text, "ALL POSTINGS ASSIGNED — CEASE ONE OR REASSIGN",
		"the reason is stated truthfully (slots, in voice)")
	assert_eq(forage.strip_plan.text, "REASSIGN — CEASE SCAVENGING, COMMENCE WALK THE GLOW ROWS",
		"the restatement names the cease and the commence")
	assert_true(forage.strip_reassign.visible, "REASSIGN is offered on a slot refusal")
	# The strip LEADS the docket's content: structurally child 0, and in the
	# laid-out docket it posts above the card the resident clicked (any scroll
	# moves them together — the strip is the first in-flow content, never
	# below it).
	assert_lte(forage.refusal_strip.get_global_rect().position.y,
		card_btn.get_global_rect().position.y,
		"the strip posts above the refused card (in-flow top, never scrolled past)")

	# ONE press: the focused REASSIGN answers ui_accept and the swap lands
	# atomically; the confirmation names what actually ceased (engine truth).
	forage.strip_reassign.grab_focus()
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), forage.strip_reassign, "REASSIGN holds focus")
	_push_accept()
	await wait_frames(2)
	assert_eq(tm.state.active.keys(), ["foraging"],
		"the swap executed: foraging holds the posting")
	assert_eq(String(tm.state.active["foraging"].get("content_id")), "walk_the_glow_rows",
		"the requested content is what started")
	assert_eq(tm.occupied_postings(), 1, "atomic — the establishment still runs one posting")
	assert_false(tm.state.active.has("scavenging"), "the scav posting ceased")
	assert_eq(forage.strip_head.text, "POSTING REASSIGNED", "the strip confirms")
	assert_string_contains(forage.strip_serial.text, "CEASED SCAVENGING",
		"the confirmation names what ceased: %s" % forage.strip_serial.text)
	assert_string_contains(forage.strip_serial.text, "NOW HOLDS THE POSTING",
		"the confirmation names the new holder")
	# The clicked card's own denial cue flashed at the click point (non-color
	# "× " prefix, one bounded flash, then the state cue restored — and since
	# the swap made this very posting RUN, the restored cue is the ">> "
	# running prefix, not the denial).
	await wait_seconds(0.8)  # outlive the bounded 0.45 s flash
	assert_false(String(card.title.text).begins_with("× "),
		"the denial prefix withdrew after its bounded flash (%s)" % card.title.text)
	assert_string_contains(card.title.text, "Walk the Glow Rows",
		"the canonical title stands under the state cue")


# ---------------------------------------------------------------------------
# (c) DEPOT — tabs, the full quantity ladder, exact wallet math
# ---------------------------------------------------------------------------

func test_c_depot_tabs_sell_ladder_leads_and_exact_wallet_math() -> void:
	var tm: Variant = await _boot(SEED, ObjectiveFreeLib.load("acceptance_run5"))
	tm.state.add_crowns(50)
	tm.state.add_item("glowshroom", 125)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	# The journey opens the Depot the way a resident does — the real 6 hotkey
	# (the docket only posts when its department is active).
	_push_digit(KEY_6)
	assert_true(await _await_department("requisition_depot"),
		"hotkey 6 opens the Depot docket")

	# Boot onto BUY; the SELL tab answers the keyboard and the ">> " +
	# Energized cues move with it (never color alone).
	assert_eq(depot.active_tab(), DocketDepot.TAB_BUY, "the depot boots on BUY")
	assert_true(depot.buy_region.visible and not depot.sell_region.visible,
		"BUY is the posted board at boot")
	depot.tab_sell.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL,
		"a real ui_accept posts the SELL board")
	assert_true(depot.sell_region.visible and not depot.buy_region.visible,
		"SELL is now the one posted board")
	assert_string_contains(depot.tab_sell.text, ">> ",
		"the active tab carries the non-color cue")
	assert_eq(depot.tab_sell.theme_type_variation, "Energized",
		"the active tab carries the Energized variation")
	depot.tab_buy.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	assert_eq(depot.active_tab(), DocketDepot.TAB_BUY, "the arrow back re-posts BUY")
	depot.tab_sell.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "SELL is re-posted for the ladder leg")
	_flush(tm)
	await wait_frames(2)

	# SELL LEADS: the disposal lines are the board's first content — the
	# resident's own sellables, never the shop's stock list.
	var first_board_child: Control = depot.sell_box.get_child(0)
	assert_true(String(first_board_child.name).begins_with("SellRow_"),
		"the disposal lines lead the SELL board (%s)" % first_board_child.name)
	for child in depot.sell_box.get_children():
		if child is Control and String(child.name).begins_with("SellRow_"):
			assert_false("copper_wiring" in String(child.name) or "duskcorn_seed" in String(child.name),
				"the shop's stock never leaks onto the sell board")

	# THE FULL LADDER with exact wallet math, every rung through a real
	# focused ui_accept: 125 held at 2 crowns each.
	var wallet := func() -> int: return int(tm.state.crowns)
	var rows := _ladder(depot, "glowshroom")
	assert_eq((rows[10] as Button).text, "SELL 10% · 12", "the 10% rung posts its honest floor")
	assert_eq((rows[25] as Button).text, "SELL 25% · 31", "the 25% rung posts its honest floor")
	assert_eq((rows[50] as Button).text, "SELL 50% · 62", "the 50% rung posts its honest floor")
	assert_eq((rows[100] as Button).text, "SELL 100% · 125", "the 100% rung posts the whole stack")
	# The exact presses: 1 then 10% of 124 (=12), 25% of 112 (=28), 50% of 84
	# (=42), 100% of 42 (=42) — the ladder re-computes on the live stack.
	var plan := [[1, 1], [10, 12], [25, 28], [50, 42], [100, 42]]
	var expected := int(wallet.call())
	for step in plan:
		var b: Button = rows[step[0]]
		assert_false(b.disabled, "the %d%% rung is live at this stack" % step[0])
		b.grab_focus()
		await wait_frames(1)
		_push_accept()
		await wait_frames(2)
		expected += step[1] * GLOW_VALUE
		assert_eq(int(wallet.call()), expected,
			"SELL %d%% paid exactly %d x %d crowns (wallet %d)" % [
				step[0], step[1], GLOW_VALUE, expected])
		_flush(tm)
		await wait_frames(1)
	assert_eq(int(tm.state.item_count("glowshroom")), 0,
		"the whole stack tendered across the ladder")
	# An emptied stack WITHDRAWS its disposal row entirely: the counter's
	# NOTHING TO TENDER line leads the empty board (the honest empty state).
	assert_true(depot.sell_box.get_child(0) is Label,
		"an emptied stack withdraws the row for the counter's empty line")
	assert_string_contains((depot.sell_box.get_child(0) as Label).text, "NOTHING TO TENDER",
		"the empty board posts the counter's honest line")

	# DISABLED AT 0, HONESTLY: a sub-share stack disables the rungs whose
	# floor is 0, at their honest labels — while the live rungs stay live.
	tm.state.add_item("glowshroom", 4)
	_flush(tm)
	await wait_frames(2)
	rows = _ladder(depot, "glowshroom")  # the stack's return rebuilt the row
	assert_true((rows[10] as Button).disabled, "10% of 4 floors to 0 — the rung disables")
	assert_eq((rows[10] as Button).text, "SELL 10% · 0", "the disabled rung posts its honest 0")
	assert_false((rows[25] as Button).disabled, "25% of 4 = 1 — the rung stays live")
	assert_eq((rows[25] as Button).text, "SELL 25% · 1", "the live rung posts its honest 1")
	var crowns_before := int(wallet.call())

	# CUSTOM: the select-preview-commit surface. Open the field, type an
	# exact amount through the REAL key pipeline, watch the preview, TENDER.
	tm.state.add_item("glowshroom", 10)  # 14 on hand
	_flush(tm)
	await wait_frames(2)
	depot.find_child("SellCustom_glowshroom", true, false).grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	var field: LineEdit = depot.find_child("CustomField_glowshroom", true, false)
	assert_true((field.get_parent() as Control).visible, "CUSTOM opens the field row")
	field.grab_focus()
	await wait_frames(1)
	_real_type("7")
	await wait_frames(2)
	assert_eq((depot.find_child("CustomPreview_glowshroom", true, false) as Label).text,
		"TENDER 7 · 14 CROWNS", "the preview states the exact proceeds")
	var tender: Button = depot.find_child("CustomTender_glowshroom", true, false)
	assert_false(tender.disabled, "a valid amount arms TENDER")
	tender.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	assert_eq(int(wallet.call()), crowns_before + 7 * GLOW_VALUE,
		"the custom tender paid exactly 7 x %d crowns" % GLOW_VALUE)
	assert_eq(int(tm.state.item_count("glowshroom")), 7, "the custom sale took exactly 7")

	# OUT OF RANGE IS REFUSED IN VOICE — never clamped, never silent. The
	# posting attempt is a real Enter in the focused field (the TENDER
	# control disarms itself on an invalid amount).
	field.grab_focus()
	await wait_frames(1)
	_real_type("99")
	await wait_frames(2)
	assert_eq((depot.find_child("CustomPreview_glowshroom", true, false) as Label).text,
		"THE COUNTER TENDERS 1–7 UNITS OF THIS STACK",
		"the preview states the honest bounds")
	assert_true(tender.disabled, "an out-of-range amount disarms TENDER")
	_push_enter()
	await wait_frames(2)
	assert_eq(int(wallet.call()), crowns_before + 7 * GLOW_VALUE,
		"nothing tendered on the out-of-range posting")
	assert_true(depot.refusal_strip.visible,
		"the refusal strip posts in the counter's voice")
	assert_string_contains(_strip_serial_text(depot), "1–7",
		"the strip names the honest bounds")


## The quantity ladder's five rungs for one stack, fetched fresh — a stack
## that empties and returns REBUILDS its row (freeing the old buttons), so
## no caller may hold rung references across a stack transition.
func _ladder(depot: DocketDepot, item: String) -> Dictionary:
	return {
		1: depot.find_child("Sell1_" + item, true, false),
		10: depot.find_child("SellPct10_" + item, true, false),
		25: depot.find_child("SellPct25_" + item, true, false),
		50: depot.find_child("SellPct50_" + item, true, false),
		100: depot.find_child("SellAll_" + item, true, false),
	}


## The depot's strip serial whatever kind posted (the bounds refusal is the
## "generic" kind — the reason rides verbatim).
func _strip_serial_text(depot: DocketDepot) -> String:
	return depot.strip_serial.text


# ---------------------------------------------------------------------------
# (d) TUTORIAL WALKTHROUGH — all 7 steps on the machinery, <= 25 actions
# ---------------------------------------------------------------------------

func test_d_tutorial_walkthrough_all_steps_within_action_budget() -> void:
	var tm: Variant = await _boot(WALKTHROUGH_SEED, null, true)
	var form := _concourse.orientation()
	# The boot reveal posted step 1's target (the five-second contract).
	await _await_settled()
	var sort_card: Button = _concourse.docket_controller("scavenging") \
		.find_child("Card_sort_scrap_pile", true, false)
	_assert_in_view(sort_card, "boot reveal: the tier-1 card")

	# -- Step 1: WORK A POSTED SHIFT. --
	await _press(sort_card, "post the scrap-pile shift")
	assert_true(tm.orientation_step_done_bool("work_shift"), "step 1 stamped")
	_pump(tm, 240_000)  # the shift works (time, not presses)
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("earn_clearance"),
		"step 2 stamped by the shift's XP")
	assert_eq(_concourse.active_department(), "requisition_depot",
		"the claim reveal opened the Depot")
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the SELL board is posted")
	var first_id := depot.first_sellable_id()
	assert_ne(first_id, "", "the shift yielded sellable stock")
	var sell_row: Control = depot.find_child("SellRow_" + first_id, true, false)
	_assert_in_view(sell_row, "the first sellable row — the hunt is over")

	# -- Step 3: FILE A CROWNS CLAIM — SELL 1 on the revealed row. --
	var sell1: Button = sell_row.find_child("Sell1_" + first_id, true, false)
	await _press(sell1, "tender one unit")
	assert_true(tm.orientation_step_done_bool("file_crowns_claim"), "step 3 stamped")
	_flush(tm)
	await _await_settled()
	var smelt: Button = _concourse.docket_controller("junksmithing") \
		.find_child("Card_smelt_scrap_ingot", true, false)
	_assert_in_view(smelt, "the craftable recipe card")

	# -- Step 4: PROCESS A PRODUCT (the posting is full: REASSIGN makes room).
	await _press(smelt, "ask for the smelt")
	await _press(_concourse.docket_controller("junksmithing").strip_reassign,
		"reassign the posting to the smelt", false)
	assert_true(tm.state.active.has("junksmithing"), "the smelt holds the posting")
	_pump(tm, 5_000)
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("process_product"), "step 4 stamped")

	# -- Step 5: PROVISION THE PATROL — forage, then cook (the documented
	# split legs; the honest source cue first). --
	var walk_card: Button = _concourse.docket_controller("foraging") \
		.find_child("Card_walk_the_glow_rows", true, false)
	assert_eq(_concourse.active_department(), "foraging",
		"the provision reveal cues the Duskcorn source")
	_assert_in_view(walk_card, "the forage card in view")
	await _press(walk_card, "ask for the forage walk")
	await _press(_concourse.docket_controller("foraging").strip_reassign,
		"reassign the posting to the forage", false)
	assert_true(tm.state.active.has("foraging"), "the forage holds the posting")
	_pump(tm, 80_000)
	_flush(tm)
	await _await_settled()
	await _press(form.row_for("provision_patrol"), "re-ask PROVISION THE PATROL", false)
	await _await_settled()
	var grits: Button = _concourse.docket_controller("cooking") \
		.find_child("Card_grind_mandatory_grits", true, false)
	assert_eq(_concourse.active_department(), "cooking", "the cook leg opens Cooking")
	_assert_in_view(grits, "the grits card in view")
	await _press(grits, "ask for the grits")
	await _press(_concourse.docket_controller("cooking").strip_reassign,
		"reassign the posting to the kitchen", false)
	assert_true(tm.state.active.has("cooking"), "the kitchen holds the posting")
	_pump(tm, 4_000)
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("provision_patrol"), "step 5 stamped (cooked)")

	# -- Step 6: CLEAR A NUISANCE — engage, reassign, let the fight run. --
	var roach: Button = _concourse.docket_controller("wasteland_patrol") \
		.find_child("Fauna_junkyard_roach", true, false)
	assert_eq(_concourse.active_department(), "wasteland_patrol",
		"the clear reveal opened the Patrol")
	_assert_in_view(roach, "the fauna card in view")
	await _press(roach, "designate the roach")
	await _press(_concourse.docket_controller("wasteland_patrol").strip_reassign,
		"reassign the posting to the patrol", false)
	assert_eq(String(tm.state.combat.get("phase", "")), "fighting", "the patrol is engaged")
	_pump(tm, 300_000, 2_500)
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("clear_nuisance"), "step 6 stamped (victory)")
	var purchase: Control = _concourse.docket_controller("personnel") \
		.find_child("DeputizeLine", true, false)
	assert_eq(_concourse.active_department(), "personnel", "the deputize reveal opened Personnel")
	_assert_in_view(purchase, "the purchase row in view")

	# -- Step 7: DEPUTIZE A RESIDENT — afford it honestly (re-ask FILE, tender
	# what the SELL board puts in view), then purchase on the revealed row. --
	await _press(form.get_node("FormColumn/FormHeader/OpenForm"),
		"open the posted slip", false)
	await _press(form.row_for("file_crowns_claim"), "re-ask FILE A CROWNS CLAIM", false)
	await _await_settled()
	assert_eq(_concourse.active_department(), "requisition_depot", "the re-ask revealed the Depot")
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the SELL board is posted again")
	var sells := 0
	while int(tm.state.crowns) < 300 and sells < 12:
		var btn := _first_in_view_sellall(depot)
		assert_not_null(btn, "an in-view tender button is always on offer")
		if btn == null:
			break
		await _press(btn, "tender a stack (%d)" % (sells + 1))
		_flush(tm)
		await wait_frames(1)
		sells += 1
	assert_gte(int(tm.state.crowns), 300, "the honest journey affords the deputy ladder")
	await _press(form.row_for("deputize_resident"), "re-ask DEPUTIZE A RESIDENT", false)
	await _await_settled()
	var deputize: Button = (_concourse.docket_controller("personnel") as DocketPersonnel).deputize_button
	await _press(deputize, "deputize a resident")
	assert_true(tm.orientation_step_done_bool("deputize_resident"), "step 7 stamped")
	assert_true(bool(tm.state.orientation["completed"]), "FORM O-1 complete: DULY ORIENTED")

	# THE STRUCTURAL PIN + the T34 cleanup bookends: the whole journey inside
	# the budget; the slip's completion mark now reads DONE — honestly.
	print("RUN5 WALKTHROUGH ACTION COUNT: %d (budget %d)" % [_actions, ACTION_BUDGET])
	assert_lte(_actions, ACTION_BUDGET,
		"the seven-step walkthrough took %d UI actions (budget %d)" % [_actions, ACTION_BUDGET])
	assert_gte(int(tm.state.crowns), 150, "the completion stipend posted on top of the wallet")
	var slip_stamp: Control = _concourse.orientation().find_child("SlipStamp", true, false)
	assert_true(bool(slip_stamp.get("stamped")),
		"the slip's completion mark stamps at completion (the fill is the fact)")


## The first tender button that is enabled AND fully in view (the reveal
## discipline: the resident presses what the docket put in front of them).
func _first_in_view_sellall(depot: DocketDepot) -> Button:
	for child in depot.sell_box.get_children():
		if not String(child.name).begins_with("SellRow_"):
			continue
		var row := child as Control
		for grandchild in row.get_children():
			if grandchild is HFlowContainer:
				for sub in (grandchild as HFlowContainer).get_children():
					if sub is Button and String((sub as Button).name).begins_with("SellAll_"):
						var b := sub as Button
						if not b.disabled and b.is_visible_in_tree() and _in_view(b):
							return b
	return null


# ---------------------------------------------------------------------------
# (e) NO BLOCKADE REGRESSION — the T29 audit suite-side, across states
# ---------------------------------------------------------------------------

func test_e_blockade_audit_green_across_states_and_scales() -> void:
	var tm: Variant = await _boot()
	var form := _concourse.orientation()
	# Settle the shell into the steady state the audit contract covers (the
	# probe's own preamble does this through its font-scale legs): the T30
	# energized swell is a transient emphasis on the ACTIVE card (it pokes
	# sub-pixel into the grid gap and is re-applied on every department
	# change); one font-scale round-trip settles it so the matrix audits the
	# standing composition, exactly as the probe's audit does.
	_concourse.font_slider.value = 2.0
	await wait_frames(3)
	_concourse.font_slider.value = 0.0
	await wait_frames(3)
	for scale_value in [0.0, 2.0]:
		_concourse.font_slider.value = scale_value
		await wait_frames(3)
		var sc := "100%" if scale_value < 1.0 else "200%"

		# State A — fresh 0/7, form EXPANDED (the first-run contract).
		tm.new_game(SEED)
		_concourse.set_first_run(true)
		await wait_frames(2)
		_audit("fresh-0/7 " + sc, false)

		# State B — mid 2/7 with a running posting.
		tm.start_activity("sort_scrap_pile")
		tm.engine.grant_xp(tm.state, "scavenging", 25)
		tm.stop_skill("scavenging")
		tm.batcher.force_flush(tm.sim_time_ms)
		await wait_frames(2)
		assert_eq(int(tm.orientation_progress()["count"]), 2, "mid 2/7 staged (" + sc + ")")
		_audit("mid-2/7 " + sc, false)

		# State C — the 5/7 auto-fold slip, then a manual OPEN.
		tm.new_game(SEED)
		_stage(tm, ["file_crowns_claim", "process_product", "provision_patrol",
			"work_shift", "earn_clearance"])
		await wait_frames(2)
		assert_false(form.is_expanded(), "5/7: the slip is posted (" + sc + ")")
		_audit("slip-5/7 " + sc, false)
		form.expand()
		await wait_frames(2)
		_audit("reopen-5/7 " + sc, false)
		form.fold()
		await wait_frames(1)

		# State D — completed: the record, then the permanent slip.
		tm.new_game(SEED)
		_stage(tm, ["work_shift", "earn_clearance", "file_crowns_claim",
			"process_product", "provision_patrol", "clear_nuisance", "deputize_resident"])
		var settled := false
		var n := 0
		while n < 4000 and not form.is_expanded():
			await wait_frames(1)
			n += 1
		settled = form.is_expanded()
		assert_true(settled, "completed: the record celebrated once (" + sc + ")")
		_audit("completed-record " + sc, false)
		# Wait out the celebration's bounded beat (the record slips back and
		# the one-shot flag clears — the next leg's auto-fold depends on it).
		var slipped := false
		n = 0
		while n < 4000 and form.is_expanded():
			await wait_frames(1)
			n += 1
		slipped = not form.is_expanded()
		assert_true(slipped, "completed: the record settled back to the slip (" + sc + ")")
		form.fold()
		await wait_frames(1)

		# State E — a posted save notice (the docked row).
		_concourse.save_board.post("save_write_failed", {"reason": "desk full"})
		await wait_frames(2)
		assert_true(_concourse.save_board.is_posting(), "save notice posted (" + sc + ")")
		_audit("save-notice " + sc, false)
		_concourse.save_board.ack_button.pressed.emit()
		await wait_frames(1)

		# State F — MAIL CALL presented: the one intentional input trap.
		var payload := {"elapsed_ms": 60_000, "skills_xp": {"scavenging": 10},
			"items": {}, "levels": {}, "actions": {}, "stopped": []}
		_concourse.mail_call.present(payload, tm.engine.lib)
		await wait_frames(2)
		_audit("mail-open " + sc, true)
		_concourse.mail_call.acknowledge()
		await wait_frames(2)
		_audit("mail-closed " + sc, false)
	# Suite hygiene: the font scale lives in the shared UiTheme autoload —
	# restore the production default so no later suite inherits the 200% leg.
	var ui_theme: Node = get_tree().root.get_node_or_null("UiTheme")
	if ui_theme != null:
		ui_theme.apply_font_scale(1.0)


## Engine-true fast paths for the audit states (test_orientation's discipline;
## order-independent — the engine stamps order-agnostically).
func _stage(tm: Variant, steps: Array) -> void:
	if steps.has("work_shift"):
		tm.start_activity("sort_scrap_pile")
		tm.stop_skill("scavenging")
	if steps.has("earn_clearance"):
		tm.engine.grant_xp(tm.state, "scavenging", 25)
	if steps.has("file_crowns_claim"):
		tm.state.add_item("scrap_metal", 5)
		tm.depot_sell("scrap_metal")
	if steps.has("process_product"):
		tm.state.add_item("scrap_metal", 30)
		tm.start_activity("smelt_scrap_ingot")
		_pump(tm, 5_000)
		tm.stop_skill("junksmithing")
	if steps.has("provision_patrol"):
		tm.state.add_item("scrap_shiv", 1)
		tm.equip_item("scrap_shiv")
	if steps.has("clear_nuisance"):
		tm.engage_monster("junkyard_roach")
		_pump(tm, 300_000)
	if steps.has("deputize_resident"):
		tm.state.add_crowns(300)
		tm.deputize_resident()
	tm.batcher.force_flush(tm.sim_time_ms)


func _collect_solids(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c)
	for child in node.get_children():
		_collect_solids(child, out)


## A control's EFFECTIVE rect: clipped by every clipping ancestor (scroll-
## hosted content is invisible and unreachable past its viewport).
func _effective_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null and p is Control:
		var pc := p as Control
		if pc.clip_contents or pc is ScrollContainer:
			r = r.intersection(pc.get_global_rect())
		p = p.get_parent()
	return r


## Does `a` paint above `b`? (z_index, then sibling order under the common
## ancestor — Godot's child sort.)
func _paints_above(a: Control, b: Control) -> bool:
	var chain_a: Array[Node] = []
	var chain_b: Array[Node] = []
	var na: Node = a
	while na != null:
		chain_a.push_front(na)
		na = na.get_parent()
	var nb: Node = b
	while nb != null:
		chain_b.push_front(nb)
		nb = nb.get_parent()
	var i := 0
	while i < chain_a.size() and i < chain_b.size() and chain_a[i] == chain_b[i]:
		i += 1
	if i == 0 or i >= chain_a.size() or i >= chain_b.size():
		return false
	var ca := chain_a[i] as Control
	var cb := chain_b[i] as Control
	if ca == null or cb == null:
		return false
	if ca.z_index != cb.z_index:
		return ca.z_index > cb.z_index
	return ca.get_index() > cb.get_index()


## The T29 blockade-class audit, suite-side: no input-present non-modal
## control may paint over any focusable's effective rect. MAIL CALL is the
## one asserted exemption (modal by design).
func _audit(tag: String, allow_modal: bool) -> void:
	var focusables := _concourse.focusable_controls()
	var solids: Array[Control] = []
	_collect_solids(_concourse, solids)
	var mail := _concourse.mail_call
	var offenders: Array[String] = []
	var modal_pairs := 0
	for s in solids:
		var s_rect := _effective_rect(s)
		if s_rect.get_area() <= 0.0:
			continue
		for f in focusables:
			if s == f or s.is_ancestor_of(f) or f.is_ancestor_of(s):
				continue
			if not s_rect.intersects(_effective_rect(f)):
				continue
			if not _paints_above(s, f):
				continue
			if allow_modal and (s == mail or mail.is_ancestor_of(s) or mail.is_ancestor_of(f)):
				modal_pairs += 1
				continue
			offenders.append("'%s'(%s) over '%s'" % [s.name, s.theme_type_variation, f.name])
	assert_true(offenders.is_empty(),
		"blockade %s: zero input blockades (%d focusables; offenders: %s)" % [
			tag, focusables.size(), "; ".join(offenders)])
	if allow_modal:
		assert_true(mail.is_presenting() and modal_pairs > 0,
			"blockade %s: the presenting MAIL CALL is the one input trap" % tag)
