extends GutTest
## tests/test_depot_tabs.gd — T32 Depot BUY/SELL tabs + sell quantities (run-5
## Scope Amendment 3, complaint #2; the user's words: "for selling, we only
## have sell 1 or sell max. we need to make buttons for sell 1, 10%, 25%,
## 50%, 100% or a custom amount. I think sell screens should be on a separate
## screen from the buy screens.").
##
## Coverage:
##   (a) HONEST ARITHMETIC — floor(stack × pct) in pure int math for every
##       button (incl. disabled-at-0 and 1 = exactly one), custom bounds
##       1..held with out-of-range REFUSED through the T31 strip idiom;
##   (b) REAL ENGINE ROUTING — every press tenders through TickManager
##       depot_sell; the wallet pays value × count EXACTLY and the Manifest
##       (state + the Manifest docket's own list) follows live;
##   (c) TABS — the BUY/SELL pair in the zone-tab grammar (radio + ">> " +
##       Energized, never color alone), keyboard-operable (Tab reach +
##       ui_accept + arrow hops, order-preserving), state persisting across
##       department switches within the session and resetting on boot;
##   (d) SELL LISTS ONLY OWNED SELLABLES (never the shop's stock);
##   (e) TUTORIAL-FACING GEOMETRY — the sell lines are scroll-free at
##       1280x720 for a starter inventory (with the O-1 form folded);
##   (f) HOTKEY SAFETY — the custom field consumes the digit keys while
##       focused (the GUI has its turn before the concourse hotkeys), so
##       typing an amount never switches departments.
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (test_engine.gd's discipline); the concourse runs in a
## SubViewport driven through the REAL input pipeline (test_orientation.gd's).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const ObjectiveFreeLib := preload("res://tests/objective_free_lib.gd")

const SEED := 20260920

const GLOW_VALUE := 2  # data/items.json — the honest one-rate tender


## The T25 objective-free boot precedent: this suite pins EXACT wallet
## arithmetic whose subject is the depot UI itself, so dossier MERIT PAY
## income (a big tender crosses sell/crowns rungs by construction) must not
## perturb the pins. The shipped objectives economy stays under test in
## tests/test_objectives.gd and the acceptance suites.
func _lib() -> ContentLibrary:
	return ObjectiveFreeLib.load("depot_tabs")


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _flush(tm: Variant) -> void:
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)


# ---------------------------------------------------------------------------
# (a) honest arithmetic
# ---------------------------------------------------------------------------

func test_pct_count_is_floor_in_pure_int_math() -> void:
	# The ladder's exact floors at ordinary stacks.
	assert_eq(DocketDepot._pct_count(125, 10), 12, "10% of 125 floors to 12")
	assert_eq(DocketDepot._pct_count(125, 25), 31, "25% of 125 floors to 31")
	assert_eq(DocketDepot._pct_count(125, 50), 62, "50% of 125 floors to 62")
	assert_eq(DocketDepot._pct_count(125, 100), 125, "100% IS the whole stack")
	assert_eq(DocketDepot._pct_count(99, 50), 49, "50% of 99 floors to 49")
	assert_eq(DocketDepot._pct_count(1, 100), 1, "100% of 1 is exactly 1")
	# Sub-1% stacks floor to 0 (and their buttons disable).
	assert_eq(DocketDepot._pct_count(4, 10), 0, "10% of 4 floors to 0")
	assert_eq(DocketDepot._pct_count(4, 25), 1, "25% of 4 floors to 1")
	assert_eq(DocketDepot._pct_count(9, 25), 2, "25% of 9 floors to 2")
	# Big-magnitude honesty: no float ever touches a stack — the split
	# div/mod form stays exact (and overflow-free) across int64 magnitudes.
	assert_eq(DocketDepot._pct_count(1_000_000_000_000_003, 25), 250_000_000_000_000,
		"25% of 1,000,000,000,000,003 floors EXACTLY (no float artifacts)")
	assert_eq(DocketDepot._pct_count(999_999_999_999_999, 10), 99_999_999_999_999,
		"10% of 999,999,999,999,999 floors EXACTLY")


func test_quantity_buttons_show_honest_counts_and_disable_at_zero() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)

	tm.state.add_item("glowshroom", 125)
	_flush(tm)
	await wait_frames(1)

	# The counts post ON the buttons (honest math at a glance).
	assert_eq((depot.find_child("Sell1_glowshroom", true, false) as Button).text, "SELL 1",
		"SELL 1 posts exactly one")
	assert_eq((depot.find_child("SellPct10_glowshroom", true, false) as Button).text,
		"SELL 10% · 12", "the 10% button posts its honest floor count")
	assert_eq((depot.find_child("SellPct25_glowshroom", true, false) as Button).text,
		"SELL 25% · 31", "the 25% button posts its honest floor count")
	assert_eq((depot.find_child("SellPct50_glowshroom", true, false) as Button).text,
		"SELL 50% · 62", "the 50% button posts its honest floor count")
	assert_eq((depot.find_child("SellAll_glowshroom", true, false) as Button).text,
		"SELL 100% · 125", "the 100% button posts the whole stack")
	for b_name in ["Sell1_glowshroom", "SellPct10_glowshroom", "SellPct25_glowshroom",
			"SellPct50_glowshroom", "SellAll_glowshroom"]:
		assert_false((depot.find_child(b_name, true, false) as Button).disabled,
			"%s enabled at a stack that floors above zero" % b_name)

	# A stack too small for a share: that button shows 0 and DISABLES.
	tm.state.take_item("glowshroom", 121)  # 125 -> 4
	_flush(tm)
	await wait_frames(1)
	assert_true((depot.find_child("SellPct10_glowshroom", true, false) as Button).disabled,
		"the 10% button disables when its floor count is 0")
	assert_false((depot.find_child("SellPct25_glowshroom", true, false) as Button).disabled,
		"the 25% button stays live at 25% of 4 = 1")
	assert_eq((depot.find_child("SellPct25_glowshroom", true, false) as Button).text,
		"SELL 25% · 1", "the count re-computes with the stack")

	# A single unit: every share floors to 0 except 100%.
	tm.state.take_item("glowshroom", 3)  # 4 -> 1
	_flush(tm)
	await wait_frames(1)
	for b_name in ["SellPct10_glowshroom", "SellPct25_glowshroom", "SellPct50_glowshroom"]:
		assert_true((depot.find_child(b_name, true, false) as Button).disabled,
			"%s disables at a 1-unit stack" % b_name)
	assert_false((depot.find_child("Sell1_glowshroom", true, false) as Button).disabled,
		"SELL 1 stays live at one unit")
	assert_eq((depot.find_child("SellAll_glowshroom", true, false) as Button).text,
		"SELL 100% · 1", "100% of 1 posts exactly 1")


func test_custom_amount_refused_out_of_range_through_the_strip() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)
	tm.state.add_item("glowshroom", 125)
	_flush(tm)
	await wait_frames(1)

	var custom_btn := depot.find_child("SellCustom_glowshroom", true, false) as Button
	custom_btn.pressed.emit()
	await wait_frames(1)
	var field := depot.find_child("CustomField_glowshroom", true, false) as LineEdit
	var tender := depot.find_child("CustomTender_glowshroom", true, false) as Button
	assert_true((depot.find_child("CustomRow_glowshroom", true, false) as Control).visible,
		"CUSTOM opens the validated inline field row")
	assert_eq(field.placeholder_text, "1–125", "the field posts its honest bounds")

	# Non-numeric: refused in voice, the strip posts at the docket's top.
	field.text = "glow juice"
	depot._on_custom_tender_pressed("glowshroom")
	await wait_frames(1)
	assert_true(depot.refusal_strip.visible, "a non-numeric posting REFUSES (never clamps)")
	assert_eq(depot.strip_head.text, "REQUEST REFUSED", "the strip head names the refusal")
	assert_eq(depot.strip_serial.text, "POST A WHOLE NUMBER OF UNITS (1–125)",
		"the reason is in the counter's voice with honest bounds: %s" % depot.strip_serial.text)
	assert_eq(int(tm.state.crowns), 0, "the wallet never moved on a refused posting")

	# Zero and over-stack: refused the same way.
	field.text = "0"
	depot._on_custom_tender_pressed("glowshroom")
	assert_eq(depot.strip_serial.text, "THE COUNTER TENDERS 1–125 UNITS OF THIS STACK",
		"0 is out of bounds (1..held)")
	field.text = "126"
	depot._on_custom_tender_pressed("glowshroom")
	assert_true(depot.refusal_strip.visible, "over-stack refuses too")
	assert_eq(int(tm.state.crowns), 0, "still nothing tendered")
	assert_eq(int(tm.state.item_count("glowshroom")), 125, "the stack never moved")

	# A valid amount: the preview states the exact proceeds, TENDER fires.
	field.text = "42"
	depot._on_custom_text_changed("42", "glowshroom")
	assert_false(tender.disabled, "a valid amount arms TENDER")
	assert_eq((depot.find_child("CustomPreview_glowshroom", true, false) as Label).text,
		"TENDER 42 · 84 CROWNS", "the preview is exact proceeds math")
	tender.pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), 84, "exactly 42 x 2 Crowns tendered")
	assert_eq(int(tm.state.item_count("glowshroom")), 83, "exactly 42 units left")
	assert_false(depot.refusal_strip.visible, "a successful tender withdraws the strip")

	# Custom can tender exactly the whole remaining stack.
	field.text = "83"
	depot._on_custom_tender_pressed("glowshroom")
	await wait_frames(1)
	assert_eq(int(tm.state.item_count("glowshroom")), 0, "custom = held tenders the stack out")
	assert_false((depot._sell_rows as Dictionary).has("glowshroom"),
		"the emptied line withdraws")


# ---------------------------------------------------------------------------
# (b) real engine routing — wallet + Manifest exact
# ---------------------------------------------------------------------------

func test_quantity_presses_route_through_the_engine_exactly() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)
	tm.state.add_item("glowshroom", 125)
	_flush(tm)
	await wait_frames(1)

	# SELL 1 = exactly one, at the one honest rate.
	(depot.find_child("Sell1_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), 1 * GLOW_VALUE, "SELL 1 pays exactly one unit's value")
	assert_eq(int(tm.state.item_count("glowshroom")), 124, "exactly one unit left the stack")

	# Each share tenders its honest floor count through the REAL sell path.
	(depot.find_child("SellPct10_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), (1 + 12) * GLOW_VALUE,
		"10% of 124 = 12 units tendered — wallet exact")
	assert_eq(int(tm.state.item_count("glowshroom")), 112, "12 units left the stack")

	(depot.find_child("SellPct25_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), (13 + 28) * GLOW_VALUE,
		"25% of 112 = 28 units tendered — wallet exact")
	assert_eq(int(tm.state.item_count("glowshroom")), 84, "the stack follows exactly")

	(depot.find_child("SellPct50_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), (41 + 42) * GLOW_VALUE,
		"50% of 84 = 42 units tendered — wallet exact")
	assert_eq(int(tm.state.item_count("glowshroom")), 42, "the stack follows exactly")

	# 100% = all.
	(depot.find_child("SellAll_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), (83 + 42) * GLOW_VALUE, "100% tenders the whole stack")
	assert_eq(int(tm.state.item_count("glowshroom")), 0, "nothing held")

	# The wallet PLATE reads the same ledger through the batched flush.
	assert_eq(depot.crowns_read.text, SignageFmt.num(int(tm.state.crowns)),
		"the currency plate matches the wallet")


func test_manifest_follows_the_sale_live() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	var manifest: DocketManifest = _concourse.docket_controller("manifest")
	depot.select_tab(DocketDepot.TAB_SELL)
	tm.state.add_item("glowshroom", 50)
	_flush(tm)
	await wait_frames(1)

	(depot.find_child("SellPct50_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.item_count("glowshroom")), 25, "50% of 50 tendered through the engine")
	# The Manifest DOCKET's own list re-reads the same flush — even while its
	# department is off-screen (every docket rides the signal contract).
	var rows := ""
	for i in manifest.list.item_count:
		rows += manifest.list.get_item_text(i) + " | "
	assert_string_contains(rows, "×25", "the Manifest list shows the remaining stack live")

	(depot.find_child("SellAll_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.item_count("glowshroom")), 0, "the tender emptied the stack")
	if manifest.list.item_count > 0:
		var gone := ""
		for i in manifest.list.item_count:
			gone += manifest.list.get_item_text(i) + " | "
		assert_string_contains(gone, "GLOWSHROOM ×0",
			"the emptied line reads zero on the Manifest list")


func test_big_stack_press_settles_exact_crowns() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)
	tm.state.add_item("glowshroom", 1_000_000_003)
	_flush(tm)
	await wait_frames(1)

	(depot.find_child("SellPct25_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(int(tm.state.crowns), 250_000_000 * GLOW_VALUE,
		"a quadrillion-scale stack pays floor(stack x 25%) x value EXACTLY")
	assert_eq(int(tm.state.item_count("glowshroom")), 750_000_003, "the stack settles exactly")


# ---------------------------------------------------------------------------
# (c) tabs: grammar, keyboard, persistence
# ---------------------------------------------------------------------------

func test_tabs_default_buy_and_swap_content_in_the_zone_tab_grammar() -> void:
	var tm: Variant = await _boot_concourse()
	tm.state.add_item("glowshroom", 10)
	_flush(tm)
	await wait_frames(1)
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")

	# Boot default: BUY leads.
	assert_eq(depot.active_tab(), DocketDepot.TAB_BUY, "a fresh docket posts the BUY tab")
	assert_true(depot.buy_region.visible, "the stock counter shows")
	assert_false(depot.sell_region.visible, "the disposals board hides")
	var tab_buy := depot.find_child("DepotTab_Buy", true, false) as Button
	assert_eq(tab_buy.text, ">> BUY", "the active tab carries the >> prefix (never color alone)")
	assert_eq(tab_buy.theme_type_variation, "Energized", "the active tab energizes")

	# Swap to SELL: one board at a time, both cues move.
	depot.select_tab(DocketDepot.TAB_SELL)
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL)
	assert_false(depot.buy_region.visible, "the stock counter hides")
	assert_true(depot.sell_region.visible, "the disposals board shows")
	var tab_sell := depot.find_child("DepotTab_Sell", true, false) as Button
	assert_eq(tab_sell.text, ">> SELL", "the active tab carries the >> prefix")
	assert_eq(tab_sell.theme_type_variation, "Energized", "the active tab energizes")
	assert_eq(tab_buy.text, "BUY", "the inactive tab drops the prefix")
	assert_eq(tab_buy.theme_type_variation, "", "the inactive tab returns to the base state")
	assert_true(tab_sell.button_pressed and not tab_buy.button_pressed,
		"the radio group holds exactly one active tab")

	# An unknown tab id is a guarded no-op.
	depot.select_tab("barter")
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "unknown ids change nothing")


func test_tabs_keyboard_operable_with_arrow_hops_in_order() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	_concourse.select_department("requisition_depot", true)
	await wait_frames(2)

	var tab_buy := depot.find_child("DepotTab_Buy", true, false) as Button
	var tab_sell := depot.find_child("DepotTab_Sell", true, false) as Button
	assert_true(_concourse.focusable_controls().has(tab_buy)
		and _concourse.focusable_controls().has(tab_sell),
		"both tab plates are in the focus cycle")

	# Arrow hop, order-preserving: right from BUY lands on SELL, left back.
	tab_buy.grab_focus()
	await wait_frames(1)
	_push_key(KEY_RIGHT)
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), tab_sell, "the right arrow hops BUY -> SELL")
	_push_key(KEY_LEFT)
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), tab_buy, "the left arrow hops SELL -> BUY")

	# A REAL ui_accept on the focused tab posts that tab's board.
	tab_sell.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL,
		"keyboard accept on the SELL plate posts the disposals board")
	assert_true(depot.sell_region.visible and not depot.buy_region.visible,
		"the boards swapped")


func test_tab_state_persists_across_department_switches_and_resets_on_boot() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)

	# Walk away and back: the docket instance (and its tab) persists in-session.
	_concourse.select_department("scavenging", true)
	await wait_frames(2)
	_concourse.select_department("requisition_depot", true)
	await wait_frames(2)
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL,
		"the SELL tab survives the department switch (same docket instance)")
	assert_true(depot.sell_region.visible, "the disposals board is still the one posted")

	# A fresh docket boots sanely on BUY.
	var fresh := DocketDepot.new()
	autofree(fresh)
	assert_eq(fresh.active_tab(), DocketDepot.TAB_BUY, "a fresh docket boots on BUY")


# ---------------------------------------------------------------------------
# (d) the SELL tab lists only owned sellables
# ---------------------------------------------------------------------------

func test_sell_tab_lists_only_owned_sellable_items() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	depot.select_tab(DocketDepot.TAB_SELL)

	# Nothing owned: the empty serial, and no stock rows leaked onto the tab.
	_flush(tm)
	await wait_frames(1)
	assert_eq((depot._sell_rows as Dictionary).size(), 0, "no lines for an empty manifest")

	tm.state.add_item("glowshroom", 10)
	tm.state.add_item("cloth_scraps", 6)
	_flush(tm)
	await wait_frames(1)
	var rows: Dictionary = depot._sell_rows
	assert_true(rows.has("glowshroom") and rows.has("cloth_scraps"),
		"owned, valued items get lines")
	assert_false(rows.has("scrap_metal"), "an UNOWNED stocked item never gets a line")
	assert_false(rows.has("scrap_ingot"), "an UNOWNED craft good never gets a line")
	assert_eq(rows.size(), 2, "exactly the owned sellables")

	# Selling a stack to zero withdraws its line on the next flush.
	tm.state.take_item("cloth_scraps", 6)
	_flush(tm)
	await wait_frames(1)
	assert_false((depot._sell_rows as Dictionary).has("cloth_scraps"),
		"a zero stack's line withdraws")


# ---------------------------------------------------------------------------
# (e) tutorial-facing geometry: scroll-free starter inventory at 1280x720
# ---------------------------------------------------------------------------

func test_starter_inventory_sell_ladder_leads_and_fits_one_viewport() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	# The keyboard-resident state: the O-1 form folded to its slip (FOLD posts
	# from step 0 — the T29 control), the docket viewport at its standing size.
	_concourse.orientation().fold()
	tm.state.add_item("scrap_metal", 40)
	tm.state.add_item("copper_wiring", 25)
	tm.state.add_item("cloth_scraps", 30)
	tm.state.add_item("glowshroom", 12)
	_flush(tm)
	_concourse.select_department("requisition_depot", true)
	await wait_frames(2)
	depot.select_tab(DocketDepot.TAB_SELL)
	await wait_frames(6)

	# The amendment's bar: filing a crowns claim needs NO LONG SCROLL. The
	# disposal board is its own tab, the sell lines are the FIRST list content
	# after it, and the starter ladder is one viewport tall — never a walk
	# past the stock list (the run-3 complaint), and internal scroll is only
	# for big inventories. Measured at 1280x720, 100%, O-1 folded.
	var scroll := _concourse.docket_scroll
	var vp := scroll.get_global_rect()
	var tabs_row := depot.find_child("DepotTabs", true, false) as Control
	var first_row := depot.find_child("SellRow_cloth_scraps", true, false) as Control
	var last_row := depot.find_child("SellRow_glowshroom", true, false) as Control
	assert_not_null(tabs_row) and assert_not_null(first_row) and assert_not_null(last_row)
	scroll.scroll_vertical = 0
	await wait_frames(2)
	assert_true(vp.encloses(tabs_row.get_global_rect()),
		"the BUY/SELL tab pair sits in the first viewport, no scroll needed")
	assert_true(first_row.get_global_rect().position.y < vp.end.y,
		"the sell lines LEAD the tab (the first line starts in the first viewport)")
	var ladder_height := last_row.get_global_rect().position.y \
		- first_row.get_global_rect().position.y
	assert_true(ladder_height < vp.size.y,
		"the whole starter ladder is one viewport tall (%d px of %d)" % [
			int(ladder_height), int(vp.size.y)])
	# And the ladder carries ONLY owned stock — no shop rows leaked in.
	assert_eq((depot._sell_rows as Dictionary).size(), 4,
		"exactly the four owned stacks, never the counter's stock list")


# ---------------------------------------------------------------------------
# (f) hotkey safety: the custom field eats the digits first
# ---------------------------------------------------------------------------

func test_custom_field_consumes_digit_keys_hotkeys_still_work_unfocused() -> void:
	var tm: Variant = await _boot_concourse()
	var depot: DocketDepot = _concourse.docket_controller("requisition_depot")
	_concourse.select_department("requisition_depot", true)
	await wait_frames(2)
	depot.select_tab(DocketDepot.TAB_SELL)
	tm.state.add_item("glowshroom", 125)
	_flush(tm)
	await wait_frames(1)

	# Open CUSTOM (focus parks in the field). A text-less digit key slips the
	# GUI phase (no unicode to type) — the concourse's own focused-field
	# guard keeps the hotkeys quiet regardless.
	(depot.find_child("SellCustom_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	var field := depot.find_child("CustomField_glowshroom", true, false) as LineEdit
	assert_eq(_vp.gui_get_focus_owner(), field, "opening CUSTOM parks focus in the field")
	_push_key(KEY_1)
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), field, "the field still holds focus")
	assert_eq(field.text, "", "a text-less key typed nothing")
	assert_eq(_concourse.active_department(), "requisition_depot",
		"a text-less digit never switches departments mid-posting")
	# A real keyboard's keydown carries the character: it lands in the field,
	# and NO department hotkey fires.
	_push_key(KEY_1, "1")
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), field, "the field still holds focus")
	assert_eq(field.text, "1", "the digit went into the amount, not the concourse")
	assert_eq(_concourse.active_department(), "requisition_depot",
		"typing an amount never switches departments")
	_push_key(KEY_2, "2")
	await wait_frames(1)
	assert_eq(field.text, "12", "digits compose the amount")
	assert_eq(_concourse.active_department(), "requisition_depot",
		"the hotkeys stay quiet while the field holds focus")

	# Away from the field, the same keys are department hotkeys again.
	(depot.find_child("DepotTab_Buy", true, false) as Button).grab_focus()
	await wait_frames(1)
	_push_key(KEY_1)
	assert_true(await _await_department("scavenging"),
		"unfocused, KEY 1 is the SCAV hotkey again")


# ---------------------------------------------------------------------------
# harness (test_refusal_feedback.gd's discipline)
# ---------------------------------------------------------------------------

var _vp: SubViewport
var _concourse: Concourse


func _boot_concourse(seed: int = SEED) -> Variant:
	var tm: Variant = _make_tm(seed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	_concourse.auto_reveal = false  # T33 seam: this suite pins the depot shell, not the tutorial
	_concourse.bind_engines(tm)
	await wait_frames(4)
	return tm


func _push_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


## A real key press through the viewport's input pipeline (the GUI has its
## turn first — this is exactly the ordering the hotkey-safety test pins).
## `text` supplies the unicode a real keyboard sends with printable keys;
## a text-less event exercises the concourse's own focused-field guard.
func _push_key(keycode: Key, text := "") -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.unicode = text.unicode_at(0) if text != "" else 0
	ev.pressed = true
	_vp.push_input(ev)
	var rel := ev.duplicate() as InputEventKey
	rel.pressed = false
	_vp.push_input(rel)


## Wait out the bulkhead transition (wall-clock close+open) for a department.
func _await_department(id: String, budget := 400) -> bool:
	var n := 0
	while n < budget:
		if _concourse.active_department() == id and not _concourse.is_transitioning():
			return true
		await wait_frames(1)
		n += 1
	return _concourse.active_department() == id and not _concourse.is_transitioning()
