extends GutTest
## tests/test_a11y.gd — T15 accessibility audit, pinned (Daredevil lane).
##
## Everything here drives the REAL concourse (scenes/main.tscn) inside a
## SubViewport through the REAL input pipeline (push_input InputEventActions —
## zero mouse events anywhere) against a fresh TickManager twin, then asserts
## the keyboard/accessibility contract:
##   1. cold-boot keyboard-only journey — every department, start/stop an
##      activity, craft, buy/sell, equip/unequip, engage/withdraw patrol,
##      open/close the MAIL CALL modal (trap + both escape paths), adjust the
##      font-scale slider with arrow keys, FILE RECORD, CLOCK OUT;
##   2. a visible amber focus ring on EVERY focusable control in EVERY
##      department, plus the modal and the save-notice ack buttons;
##   3. focus targets meet the 24 px minimum (WCAG 2.5.8) — pins the
##      CardButton fix (cards previously collapsed to ~22 px);
##   4. every interactive control carries an accessible name (self-describing
##      text or an explicit tooltip);
##   4b. R3 department hotkeys: plates post their designation digits and keys
##      1-7 (row + keypad) select the departments through the real input
##      pipeline from anywhere, focus following to the destination plate;
##   5. state changes never ride on color alone (">> " prefixes, CLEARANCE
##      gate text, distinct phase wording, distinct toggle glyphs);
##   6. the MAIL CALL modal traps focus and escapes by Esc AND Enter;
##   7. the settings slider changes the scale through arrow keys;
##   8. card buttons contain their content (the T10a/T10b overlap bug);
##   9. motion is brief, bounded and never loops;
##  10. COLLAPSE GUARD: no visible Label anywhere renders narrower than its
##      longest word (the T15 fix-round pin — an autowrapped Label's ~1 px
##      minimum, starved by an HBox, stacked serials one character per line
##      at BOTH font scales), checked on every department at 100% AND 200%,
##      plus the MAIL CALL modal and the save-notice board.
## The runtime CONTRAST re-audit and the 200% captures live in
## tests/probe_a11y.gd (they need the probe's render-adjacent pass).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260915
const DEPT_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest"]
const SOURCE_SCAN := [
	"res://scenes/main.gd",
	"res://scripts/ui/docket.gd",
	"res://scripts/ui/docket_skill.gd",
	"res://scripts/ui/docket_gathering.gd",
	"res://scripts/ui/docket_processing.gd",
	"res://scripts/ui/docket_manifest.gd",
	"res://scripts/ui/docket_depot.gd",
	"res://scripts/ui/docket_patrol.gd",
	"res://scripts/ui/mail_call_modal.gd",
	"res://scripts/ui/save_notice_board.gd",
	"res://scripts/ui/orientation_form.gd",
]

var _vp: SubViewport
var _concourse: Concourse


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (a11y tests run on live data)")
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


## Real input pipeline: one action press+release through the viewport.
func _push(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


func _focus_owner() -> Control:
	return _vp.gui_get_focus_owner()


## Tab (ui_focus_next) until the focus owner satisfies pred; returns the owner
## or null after max tabs. No mouse, no grab_focus — the journey walks itself.
func _tab_until(pred: Callable, max_tabs := 48) -> Control:
	for i in max_tabs:
		var owner := _focus_owner()
		if owner != null and pred.call(owner):
			return owner
		_push("ui_focus_next")
		await wait_frames(1)
	return _focus_owner() if _focus_owner() != null and pred.call(_focus_owner()) else null


func _await_department(id: String, budget := 400) -> bool:
	var n := 0
	while n < budget:
		if _concourse.active_department() == id and not _concourse.is_transitioning():
			return true
		await wait_frames(1)
		n += 1
	return _concourse.active_department() == id and not _concourse.is_transitioning()


func _boot(seed := SEED) -> Variant:
	var tm: Variant = _make_tm(seed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	_concourse.auto_reveal = false  # T33 seam: the keyboard/a11y pins predate the deep links
	_concourse.bind_engines(tm)
	await wait_frames(3)
	return tm


func _focusable_in(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		var blocked := c is BaseButton and (c as BaseButton).disabled
		if c.focus_mode != Control.FOCUS_NONE and not blocked and c.is_visible_in_tree():
			out.append(c)
	for child in node.get_children():
		_focusable_in(child, out)


# ---------------------------------------------------------------------------
# 1. the cold-boot keyboard-only journey
# ---------------------------------------------------------------------------
func test_cold_boot_keyboard_only_full_journey() -> void:
	var tm: Variant = await _boot()
	# Engine-side seeding only (a resident's prior holdings — not input).
	tm.state.add_item("scrap_metal", 12)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	await wait_frames(1)

	# Cold boot: initial focus is the first plate, no input needed.
	assert_eq(_focus_owner(), _concourse.initial_focus(),
		"cold boot focuses the O-1 step-1 cue plate")
	assert_eq(_focus_owner().name, "Plate_scavenging", "boot focus is the scavenging plate")

	# --- Scavenging: start a shift from a focused tier card, then stop. ---
	var card := await _tab_until(func(c: Control) -> bool: return c.name == "Card_sort_scrap_pile")
	assert_not_null(card, "tab reaches the tier card with keyboard only")
	_push("ui_accept")
	await wait_frames(1)
	assert_true(tm.state.active.has("scavenging"), "keyboard accept starts the shift")
	var gather := _concourse.docket_controller("scavenging") as DocketGathering
	assert_string_contains(gather.status_line.text, ">>", "running state carries the prefix cue")
	var begin := await _tab_until(func(c: Control) -> bool: return c.name == "BeginShift_scavenging")
	assert_not_null(begin, "tab reaches BEGIN SHIFT")
	assert_string_contains(begin.text, "END", "primary retexts to END SHIFT while running")
	_push("ui_accept")
	await wait_frames(1)
	assert_false(tm.state.active.has("scavenging"), "keyboard accept stops the shift")

	# --- Walk the card wall with arrows (T30 grid geometry: 2 columns,
	# row-major reading order — within a row ui_right/ui_left, across rows
	# ui_down/ui_up); visit EVERY department. ---
	var walked := await _tab_until(func(c: Control) -> bool:
		return c.name.begins_with("Plate_") and c.name != "Plate_scavenging")
	assert_not_null(walked, "tab returns to the card wall")
	# Each leg re-anchors on the CURRENT department's card first, then arrows
	# one grid move to the next department in reading order: index i -> i+1
	# is ui_right from an even index (row's left card), ui_down from an odd
	# one (next row's first column).
	var current := "scavenging"
	for target in ["foraging", "junksmithing", "cooking", "wasteland_patrol",
			"requisition_depot", "manifest"]:
		var plate_name := "Plate_" + current
		var anchor := await _tab_until(func(c: Control) -> bool: return c.name == plate_name)
		assert_not_null(anchor, "tab anchors on %s" % plate_name)
		var idx := DEPT_IDS.find(current)
		if idx % 2 == 0:
			# Left card of a row: the next department is one ui_right away.
			_push("ui_right")
			await wait_frames(1)
		else:
			# Right card of a row: the next department starts the next row —
			# ui_down drops straight below (the row's right card), ui_left
			# finishes the move onto it.
			_push("ui_down")
			await wait_frames(1)
			_push("ui_left")
			await wait_frames(1)
		var owner := _focus_owner()
		assert_eq(owner.name, "Plate_" + target, "arrow lands on %s" % target)
		_push("ui_accept")
		assert_true(await _await_department(target), "keyboard accept opens %s" % target)
		assert_true(_concourse.docket_for(target).visible, "%s docket visible" % target)
		current = target

		# --- Per-department keyboard work. ---
		match target:
			"junksmithing":
				var recipe := await _tab_until(func(c: Control) -> bool:
					return c.name == "Card_smelt_scrap_ingot")
				assert_not_null(recipe, "tab reaches the recipe card")
				_push("ui_accept")
				await wait_frames(1)
				assert_true(tm.state.active.has("junksmithing"), "keyboard craft shift starts")
				_pump(tm, 4_100)
				assert_eq(int(tm.state.inventory.get("scrap_ingot", 0)), 1,
					"keyboard-posted craft completed (1 ingot)")
				var stop := await _tab_until(func(c: Control) -> bool:
					return c.name == "BeginShift_junksmithing")
				_push("ui_accept")
				await wait_frames(1)
				assert_false(tm.state.active.has("junksmithing"), "keyboard stops the craft")
			"wasteland_patrol":
				var fauna := await _tab_until(func(c: Control) -> bool:
					return c.name == "Fauna_junkyard_roach")
				assert_not_null(fauna, "tab reaches the fauna posting")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(str(tm.state.combat["phase"]), "fighting",
					"keyboard accept engages the patrol")
				_pump(tm, 3_000)
				var withdraw := await _tab_until(func(c: Control) -> bool:
					return c.name == "BeginShift_wasteland_patrol")
				assert_not_null(withdraw, "tab reaches WITHDRAW PATROL")
				assert_string_contains(withdraw.text, "WITHDRAW", "primary retexts while fighting")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(str(tm.state.combat["phase"]), "idle", "keyboard withdraws the patrol")
			"requisition_depot":
				var buy := await _tab_until(func(c: Control) -> bool:
					return c.name == "Buy1_glowshroom")
				assert_not_null(buy, "tab reaches BUY 1")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(int(tm.state.inventory.get("glowshroom", 0)), 1,
					"keyboard BUY 1 stocks one unit")
				assert_eq(int(tm.state.crowns), 994, "keyboard BUY tenders 6 Crowns")
				# T32: the SELL board is its own tab now — the keyboard journey
				# walks to the tab plate, posts it with ui_accept, and only
				# then reaches the disposal buttons.
				var sell_tab := await _tab_until(func(c: Control) -> bool:
					return c.name == "DepotTab_Sell")
				assert_not_null(sell_tab, "tab reaches the SELL tab plate")
				_push("ui_accept")
				await wait_frames(1)
				var depot_c := _concourse.docket_controller("requisition_depot") as DocketDepot
				assert_true(depot_c.sell_region.visible and not depot_c.buy_region.visible,
					"keyboard accept posts the SELL board")
				var sell := await _tab_until(func(c: Control) -> bool:
					return c.name == "Sell1_glowshroom")
				assert_not_null(sell, "tab reaches SELL 1")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(int(tm.state.inventory.get("glowshroom", 0)), 0,
					"keyboard SELL 1 tenders the unit back")
			"manifest":
				var lines := await _tab_until(func(c: Control) -> bool:
					return c.name == "ManifestLines")
				assert_not_null(lines, "tab reaches the Manifest list")
				_push("ui_down")  # select the first (equipment) row
				await wait_frames(1)
				var equip := await _tab_until(func(c: Control) -> bool:
					return c.name == "EquipSelected")
				assert_not_null(equip, "tab reaches EQUIP")
				assert_false(equip.disabled, "arrow selection arms EQUIP")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(str(tm.state.combat.get("weapon", "")), "scrap_shiv",
					"keyboard EQUIP fills the weapon slot")
				var unequip := await _tab_until(func(c: Control) -> bool:
					return c.name == "UnequipWeapon")
				assert_not_null(unequip, "tab reaches UNEQUIP")
				_push("ui_accept")
				await wait_frames(1)
				assert_eq(str(tm.state.combat.get("weapon", "")), "",
					"keyboard UNEQUIP returns the gear")

	# --- Back up the wall to Scavenging for the MAIL CALL leg. ---
	var manifest_plate := await _tab_until(func(c: Control) -> bool: return c.name == "Plate_manifest")
	assert_not_null(manifest_plate, "tab returns to the card wall")
	# Manifest sits at column 0, row 3 (grid index 6): three ui_up moves climb
	# the column back to Scavenging (grid index 0).
	for i in 3:
		_push("ui_up")
		await wait_frames(1)
	assert_eq(_focus_owner().name, "Plate_scavenging", "arrow UP walks back to Scavenging")
	_push("ui_accept")
	assert_true(await _await_department("scavenging"), "keyboard returns to Scavenging")
	var card2 := await _tab_until(func(c: Control) -> bool: return c.name == "Card_sort_scrap_pile")
	_push("ui_accept")
	await wait_frames(1)
	_pump(tm, 3_000)
	tm.apply_offline_elapsed(3_600_000)
	await wait_frames(3)
	assert_true(_concourse.mail_call.is_presenting(), "MAIL CALL opens on offline gains")
	assert_eq(_focus_owner(), _concourse.mail_call.ack_button,
		"the modal's ACKNOWLEDGE button takes focus on open")
	for i in 15:
		_push("ui_focus_next")
		await wait_frames(1)
	assert_true(_concourse.mail_call.is_ancestor_of(_focus_owner()),
		"tabbing stays trapped inside the modal")
	_push("ui_cancel")
	await wait_frames(1)
	assert_false(_concourse.mail_call.is_presenting(), "Esc acknowledges the mail call")

	# --- Settings: the slider through arrow keys. ---
	var slider := await _tab_until(func(c: Control) -> bool: return c.name == "FontScaleSlider")
	assert_not_null(slider, "tab reaches the font-scale slider")
	_push("ui_right")
	await wait_frames(1)
	assert_string_contains(_concourse.font_readout.text, "150", "arrow RIGHT -> 150%")
	assert_eq(_concourse.theme.get_font_size("font_size", "PlateTitle"), 39,
		"slider resizes the theme to 150%")
	_push("ui_right")
	await wait_frames(1)
	assert_eq(_concourse.theme.get_font_size("font_size", "PlateTitle"), 52,
		"slider resizes the theme to 200%")
	_push("ui_left")
	_push("ui_left")
	await wait_frames(1)
	assert_eq(_concourse.theme.get_font_size("font_size", "PlateTitle"), 26,
		"arrow LEFT restores 100%")

	# --- Save + quit through the console. ---
	var counts := {"save": 0, "quit": 0}  # dict: lambdas capture by value
	_concourse.save_requested.connect(func() -> void: counts["save"] += 1)
	var save_btn := await _tab_until(func(c: Control) -> bool: return c.name == "SaveRecord")
	assert_not_null(save_btn, "tab reaches FILE RECORD")
	_push("ui_accept")
	await wait_frames(1)
	assert_eq(counts["save"], 1, "keyboard FILE RECORD files the intent")
	_concourse.quit_requested.connect(func() -> void: counts["quit"] += 1)
	var quit_btn := await _tab_until(func(c: Control) -> bool: return c.name == "ClockOut")
	assert_not_null(quit_btn, "tab reaches CLOCK OUT (was off-window at 200% before the flow fix)")
	assert_true(quit_btn.get_global_rect().end.x <= 1280.0,
		"CLOCK OUT is on screen at 1280 wide")
	_push("ui_accept")
	await wait_frames(1)
	assert_eq(counts["quit"], 1, "keyboard CLOCK OUT emits the quit intent")


# ---------------------------------------------------------------------------
# 2. focus rings on every focusable, every department
# ---------------------------------------------------------------------------
func test_focus_ring_lit_on_every_focusable_every_department() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await wait_frames(2)
		var checked := 0
		for c in _concourse.focusable_controls():
			c.grab_focus()
			await wait_frames(1)
			assert_eq(_focus_owner(), c, "%s holds focus in %s" % [c.name, id])
			assert_true(_concourse.focus_ring_lit(c),
				"%s shows the amber focus ring in %s" % [c.name, id])
			checked += 1
		assert_gt(checked, 7 + 4, "%s mounts docket focusables beyond shell+console" % id)
		# T32: the depot's SELL board is its own tab — sweep BOTH boards so
		# neither side's focusables ever escape the ring/name contract.
		if id == "requisition_depot":
			var depot_c := _concourse.docket_controller(id) as DocketDepot
			depot_c.select_tab(DocketDepot.TAB_SELL)
			await wait_frames(2)
			for c in _concourse.focusable_controls():
				if not depot_c.sell_region.is_ancestor_of(c):
					continue
				c.grab_focus()
				await wait_frames(1)
				assert_eq(_focus_owner(), c, "%s holds focus on the SELL board" % c.name)
				assert_true(_concourse.focus_ring_lit(c),
					"%s shows the amber focus ring on the SELL board" % c.name)
			depot_c.select_tab(DocketDepot.TAB_BUY)
			await wait_frames(2)

	# The modal's ack button while presenting.
	_concourse.mail_call.present({"elapsed_ms": 60_000, "skills_xp": {}, "items": {},
		"levels": {}, "actions": {}, "stopped": []}, _lib())
	await wait_frames(1)
	assert_true(_concourse.focus_ring_lit(_concourse.mail_call.ack_button),
		"modal ACKNOWLEDGE shows the ring")
	_concourse.mail_call.acknowledge()

	# The save-notice board's ack button while posting.
	_concourse.save_board.post("save_write_failed", {"reason": "desk full"})
	await wait_frames(2)
	_concourse.save_board.ack_button.grab_focus()
	await wait_frames(1)
	assert_true(_concourse.focus_ring_lit(_concourse.save_board.ack_button),
		"save-notice ACKNOWLEDGE shows the ring")
	_concourse.save_board.ack_button.pressed.emit()


# ---------------------------------------------------------------------------
# 3. focus targets meet the 24 px minimum
# ---------------------------------------------------------------------------
func test_focus_targets_meet_24px_minimum() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await wait_frames(2)
		for c in _concourse.focusable_controls():
			var r := c.get_global_rect()
			assert_gte(r.size.x, 24.0, "%s target width %.0f in %s" % [c.name, r.size.x, id])
			assert_gte(r.size.y, 24.0, "%s target height %.0f in %s" % [c.name, r.size.y, id])


# ---------------------------------------------------------------------------
# 4. accessible names
# ---------------------------------------------------------------------------
func test_every_interactive_control_has_accessible_name() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await wait_frames(2)
		# Every visible interactive control — including disabled buttons (BUY ×0
		# still must announce itself). Self-describing text OR an explicit name.
		var interactives: Array[Control] = []
		_collect_interactive(_concourse, interactives)
		assert_gt(interactives.size(), 10, "%s mounts interactive controls" % id)
		for c in interactives:
			var text := ""
			if c is BaseButton:
				text = (c as BaseButton).text
			assert_true(text.strip_edges() != "" or c.tooltip_text.strip_edges() != "",
				"%s carries an accessible name (text or tooltip) in %s" % [c.name, id])
	# The modal + save board ack buttons too.
	_concourse.mail_call.present({"elapsed_ms": 60_000, "skills_xp": {}, "items": {},
		"levels": {}, "actions": {}, "stopped": []}, _lib())
	await wait_frames(1)
	assert_true(_concourse.mail_call.ack_button.text != ""
		or _concourse.mail_call.ack_button.tooltip_text != "",
		"modal ack carries a name")
	_concourse.mail_call.acknowledge()


func _collect_interactive(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		var interactive := c is BaseButton or c is Slider or c is ItemList or c is LineEdit
		if interactive and c.is_visible_in_tree():
			out.append(c)
	for child in node.get_children():
		_collect_interactive(child, out)


# ---------------------------------------------------------------------------
# 5. state changes never ride on color alone
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 4b. R3 (critique P3#5): department hotkeys — the posted designation digit
#     is a live accelerator through the real input pipeline
# ---------------------------------------------------------------------------
func test_department_hotkeys_select_from_anywhere() -> void:
	await _boot()
	# Every card posts its designation digit on its stencil name label (also
	# its D-0n serial digit; T30 moved the text from the Button to the label
	# stack).
	var plates := _concourse.plate_buttons_in_order()
	var all_ids := ["scavenging", "foraging", "junksmithing", "cooking",
		"wasteland_patrol", "requisition_depot", "manifest", "personnel"]
	for i in plates.size():
		var card_name: Label = _concourse.plate_name_label(all_ids[i])
		assert_true(card_name.text.ends_with("· %d" % (i + 1)),
			"card %d posts its designation digit (got '%s')" % [i, card_name.text])
		assert_string_contains(plates[i].tooltip_text, "press %d" % (i + 1),
			"card %d tooltip names the key" % i)
	# Park focus deep in the console and start AWAY from key 1's department —
	# the shortcut must work from anywhere, and a digit pressed on the ACTIVE
	# department is a guarded no-op (asserted below), not a focus jump.
	_concourse.select_department("manifest", true)
	await wait_frames(1)
	_concourse.save_button.grab_focus()
	await wait_frames(1)
	for i in DEPT_IDS.size():
		_push_key(KEY_1 + i)
		assert_true(await _await_department(DEPT_IDS[i], 150),
			"key %d selects %s through the real input pipeline" % [i + 1, DEPT_IDS[i]])
		await wait_frames(1)
		assert_eq(_vp.gui_get_focus_owner(), plates[i],
			"key %d moves focus to the destination plate" % (i + 1))
	# The keypad works; a repeat press on the active department is a no-op.
	_push_key(KEY_KP_7)
	assert_true(await _await_department("manifest", 150), "keypad 7 selects the Manifest")
	var selected := {"n": 0}
	_concourse.department_selected.connect(func(_id: String) -> void: selected["n"] += 1)
	_push_key(KEY_KP_7)
	await wait_frames(10)
	assert_eq(int(selected["n"]), 0, "hotkey on the active department emits nothing")
	assert_eq(_concourse.active_department(), "manifest", "active department unchanged")


## One physical key press through the SubViewport's real input pipeline.
func _push_key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	_vp.push_input(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	_vp.push_input(up)


func test_state_changes_not_color_alone() -> void:
	var tm: Variant = await _boot()
	# Cards: the active card carries the prefix + variation, others don't.
	var plates := _concourse.plate_buttons_in_order()
	var boot_name: Label = _concourse.plate_name_label("scavenging")
	assert_string_contains(boot_name.text, ">> ", "active card prefixes")
	assert_eq(plates[0].theme_type_variation, "SkillCardEnergized", "active card variation")
	assert_false(_concourse.plate_name_label("cooking").text.begins_with(">> "), "inactive card has no prefix")

	# Running gathering card: prefix + status plate + retext.
	_concourse.select_department("scavenging", true)
	await wait_frames(1)
	var gather := _concourse.docket_controller("scavenging") as DocketGathering
	var cards: Dictionary = gather.get("_cards")
	var open_card: DocketSkill.Card = cards["sort_scrap_pile"]
	(open_card.button as Button).pressed.emit()
	await wait_frames(1)
	assert_string_contains(open_card.title.text, ">> ", "running card title carries the prefix")
	assert_string_contains(gather.status_line.text, ">> ", "status plate carries the prefix")
	assert_string_contains(_concourse.begin_button_for("scavenging").text, "END",
		"primary retexts while running")
	tm.stop_skill("scavenging")
	await wait_frames(1)
	assert_false(open_card.title.text.begins_with(">> "), "stopped card drops the prefix")

	# Locked gates: text names the grade on every gated card in every docket.
	for id in DEPT_IDS:
		var controller := _concourse.docket_controller(id)
		var gate_texts := _gate_texts(controller)
		for gate in gate_texts:
			assert_string_contains(gate, "CLEARANCE", "gate text in %s" % id)
			assert_string_contains(gate, "REQUIRED", "gate demands in %s" % id)
	assert_gt(_gate_texts(_concourse.docket_controller("scavenging")).size(), 0,
		"scavenging shows locked gates at level 1")

	# Patrol phase wording: each phase has its own words, not just a color.
	_concourse.select_department("wasteland_patrol", true)
	await wait_frames(1)
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	var boss: MonsterDef = _lib().monster("sewer_landlord")
	var wordings: Array[String] = []
	for phase in ["fighting", "dead", "victory", "recalled"]:
		patrol._apply_phase_plate(phase, boss)
		assert_true(patrol.phase_plate.visible, "phase plate visible: %s" % phase)
		assert_ne(patrol.phase_line.text, "", "phase wording non-empty: %s" % phase)
		wordings.append(patrol.phase_line.text)
	assert_ne(wordings[0], wordings[1], "fighting and dead wordings differ")
	assert_ne(wordings[1], wordings[2], "dead and victory wordings differ")
	assert_ne(wordings[2], wordings[3], "victory and recalled wordings differ")
	# The persistent zone plate carries its own words.
	tm.state.combat["zone_clear"] = true
	_flush(tm, "combat")
	await wait_frames(1)
	assert_true(patrol.zone_plate.visible, "zone plate visible on zone_clear")
	var zone_texts := ""
	for l in patrol.zone_plate.find_children("*", "Label", true, false):
		zone_texts += (l as Label).text + " "
	assert_string_contains(zone_texts, "ZONE SECURED", "zone plate wording")

	# The fullscreen toggle: distinct glyphs, not a hue shift.
	var unchecked: Texture2D = _concourse.fullscreen_check.get_theme_icon("unchecked")
	var checked: Texture2D = _concourse.fullscreen_check.get_theme_icon("checked")
	assert_ne(unchecked.get_rid().get_id(), checked.get_rid().get_id(),
		"toggle states use distinct glyphs (non-color cue)")


func _gate_texts(controller: Control) -> Array[String]:
	var out: Array[String] = []
	if controller == null:
		return out
	for l in controller.find_children("*", "Label", true, false):
		if (l as Label).visible and "REQUIRED" in (l as Label).text:
			out.append((l as Label).text)
	return out


# ---------------------------------------------------------------------------
# 6. modal trap + both escape paths
# ---------------------------------------------------------------------------
func test_mail_call_modal_trap_and_escapes() -> void:
	await _boot()
	var payload := {"elapsed_ms": 3_600_000, "skills_xp": {"scavenging": 120},
		"items": {"scrapnel": 3}, "levels": {}, "actions": {"scavenging": 12}, "stopped": []}
	_concourse.mail_call.present(payload, _lib())
	await wait_frames(1)
	assert_true(_concourse.mail_call.is_presenting(), "modal presents")
	assert_eq(_focus_owner(), _concourse.mail_call.ack_button, "ack grabs focus on open")
	# The trap: heavy tabbing never leaves the modal subtree.
	for i in 24:
		_push("ui_focus_next")
		await wait_frames(1)
		if _concourse.mail_call.is_presenting():
			assert_true(_concourse.mail_call.is_ancestor_of(_focus_owner()),
				"focus trapped (owner %s)" % _focus_owner().name)
	# Escape path 1: Esc.
	_push("ui_cancel")
	await wait_frames(1)
	assert_false(_concourse.mail_call.is_presenting(), "Esc acknowledges")
	# Escape path 2: Enter on the focused ack button.
	_concourse.mail_call.present(payload, _lib())
	await wait_frames(1)
	assert_eq(_focus_owner(), _concourse.mail_call.ack_button, "ack re-grabs focus")
	_push("ui_accept")
	await wait_frames(1)
	assert_false(_concourse.mail_call.is_presenting(), "Enter acknowledges")


# ---------------------------------------------------------------------------
# 7. slider keyboard operation (standalone pin; also exercised in the journey)
# ---------------------------------------------------------------------------
func test_settings_slider_keyboard_changes_scale() -> void:
	await _boot()
	var ui_theme := _vp.get_node_or_null("/root/UiTheme")
	_concourse.font_slider.grab_focus()
	await wait_frames(1)
	assert_eq(_focus_owner(), _concourse.font_slider, "slider focusable")
	assert_true(_concourse.focus_ring_lit(_concourse.font_slider),
		"slider lights its track border when focused")
	var scales: Array = []
	_concourse.font_scale_changed.connect(func(s: float) -> void: scales.append(s))
	_push("ui_right")
	await wait_frames(1)
	assert_almost_eq(_concourse.font_slider.value, 1.0, 0.001, "ui_right steps the slider")
	assert_eq(_concourse.theme.get_font_size("font_size", "PlateTitle"), 39,
		"theme follows the slider (150%)")
	if ui_theme != null:
		assert_almost_eq(float(ui_theme.get("font_scale")), 1.5, 0.001,
			"UiTheme.font_scale tracks 150%")
	_push("ui_left")
	await wait_frames(1)
	assert_eq(_concourse.theme.get_font_size("font_size", "PlateTitle"), 26,
		"theme follows the slider back (100%)")
	assert_almost_eq(float(ui_theme.get("font_scale")) if ui_theme != null else 1.0, 1.0, 0.001,
		"UiTheme.font_scale tracks 100%")
	assert_has(scales, 1.5, "font_scale_changed emitted with the new scale")


# ---------------------------------------------------------------------------
# 8. card buttons contain their content (the shipped-overlap regression pin)
# ---------------------------------------------------------------------------
func test_card_buttons_contain_their_content() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	_flush(tm)
	for id in ["scavenging", "wasteland_patrol"]:
		_concourse.select_department(id, true)
		await wait_frames(2)
		var controller := _concourse.docket_controller(id)
		var card_buttons := controller.find_children("Card_*", "Button", true, false) \
			+ controller.find_children("Fauna_*", "Button", true, false)
		assert_gt(card_buttons.size(), 0, "%s mounts card buttons" % id)
		for b in card_buttons:
			var button := b as Button
			var r := button.get_global_rect()
			assert_gte(r.size.y, 24.0, "%s card height %.0f" % [button.name, r.size.y])
			for child in button.get_children():
				if child is Control:
					var cr := (child as Control).get_global_rect()
					assert_gte(cr.position.y, r.position.y - 0.5,
						"%s content starts inside the plate" % button.name)
					assert_lte(cr.end.y, r.end.y + 0.5,
						"%s content ends inside the plate (no spill onto the next card)" % button.name)


# ---------------------------------------------------------------------------
# 9. motion: brief, bounded, never looping
# ---------------------------------------------------------------------------
func test_motion_brief_bounded_never_looping() -> void:
	await _boot()
	assert_lte(Concourse.TRANSITION_CLOSE_S + Concourse.TRANSITION_OPEN_S, 0.7,
		"bulkhead slide total under 0.7 s")
	# A real keyboard-driven transition is bounded wall-clock (probe pins the
	# visual; here the journey contract: focus -> accept -> changed).
	var t0 := Time.get_ticks_msec()
	_concourse.plates()["manifest"].grab_focus()
	await wait_frames(1)
	_push("ui_accept")
	var n := 0
	while n < 500 and _concourse.is_transitioning():
		await wait_frames(1)
		n += 1
	assert_eq(_concourse.active_department(), "manifest", "keyboard transition completed")
	assert_lte(Time.get_ticks_msec() - t0, 2_000, "transition resolves within 2 s wall")
	assert_false(_concourse.is_transitioning(), "transition flag clears")
	# Nothing anywhere loops a tween (the only authored motions are the bounded
	# bulkhead slide, swell and the O-1 one-shot swells).
	for path in SOURCE_SCAN:
		var fa := FileAccess.open(path, FileAccess.READ)
		assert_not_null(fa, "source readable: %s" % path)
		if fa == null:
			continue
		var src := fa.get_as_text()
		fa.close()
		assert_false(src.contains("set_loops("), "no looping tweens in %s" % path)
		assert_false(src.contains("Tween.LOOP_INFINITE"), "no infinite tweens in %s" % path)


# ---------------------------------------------------------------------------
# 10. collapse guard: no Label renders narrower than its longest word
# ---------------------------------------------------------------------------
## The T15 fix-round regression pin. An autowrapped Label's minimum width
## collapses to ~1 px, so a wrapped serial placed as an HBox sibling of an
## EXPAND_FILL label is starved to a vertical one-character column — exactly
## what the T15 wrapping fix did to every skill-docket rate line and status
## serial (verifier-measured 1x491 at 100%, 1x1089 at 200%). A legible
## layout always owes a Label at least the width of its widest unbreakable
## word, at every font scale, on every screen: assert it.
func test_no_label_collapses_below_its_longest_word() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	# A running shift renders the energized status plate + serial too.
	tm.start_activity("sort_scrap_pile")
	await wait_frames(1)
	for slider_value in [0.0, 2.0]:
		_concourse.font_slider.value = slider_value
		await wait_frames(3)
		var pct := int((1.0 + 0.5 * slider_value) * 100.0)
		for id in DEPT_IDS:
			_concourse.select_department(id, true)
			await wait_frames(2)
			_assert_no_collapsed_labels(_concourse, "%s @%d%%" % [id, pct], 4)
	tm.stop_skill("scavenging")

	# The overlay screens carry wrapped serials too (the MAIL CALL item rows
	# shipped the same collapse class) — guard them at both scales.
	for slider_value in [0.0, 2.0]:
		_concourse.font_slider.value = slider_value
		await wait_frames(3)
		var pct := int((1.0 + 0.5 * slider_value) * 100.0)
		_concourse.mail_call.present({"elapsed_ms": 3_600_000,
			"skills_xp": {"scavenging": 120}, "items": {"scrapnel": 3, "scrap_metal": 12},
			"levels": {}, "actions": {"scavenging": 12}, "stopped": []}, _lib())
		await wait_frames(1)
		assert_true(_concourse.mail_call.is_presenting(), "modal presents @%d%%" % pct)
		_assert_no_collapsed_labels(_concourse.mail_call, "mail call modal @%d%%" % pct)
		_concourse.mail_call.acknowledge()
		_concourse.save_board.post("save_write_failed", {"reason": "desk full"})
		await wait_frames(2)
		_assert_no_collapsed_labels(_concourse.save_board, "save notice @%d%%" % pct)
		_concourse.save_board.ack_button.pressed.emit()
	_concourse.font_slider.value = 0.0


## Shared collapse assertion: every visible Label in the subtree renders at
## least as wide as its longest word (see test 10 for the defect class).
func _assert_no_collapsed_labels(root_node: Node, where: String, min_count := 1) -> void:
	var checked := 0
	for l in root_node.find_children("*", "Label", true, false):
		var lab := l as Label
		if not lab.is_visible_in_tree() or lab.text.strip_edges() == "":
			continue
		checked += 1
		var floor := _longest_word_width(lab)
		assert_gte(lab.size.x, floor - 1.0,
			"%s: %s width %.1f >= longest word %.1f" % [
				where, lab.name, lab.size.x, floor])
		assert_false(lab.size.x < 8.0 and lab.size.y > 40.0,
			"%s: %s renders as a vertical column (%.1fx%.1f)" % [
				where, lab.name, lab.size.x, lab.size.y])
	assert_gt(checked, min_count, "%s renders labels to guard" % where)


## The rendered width of the label's widest unbreakable chunk, in the label's
## own font at its own (theme-scaled) size — the floor a legible layout owes
## every wrapped serial.
func _longest_word_width(lab: Label) -> float:
	var font := lab.get_theme_font("font")
	if font == null:
		return 0.0
	var fs := lab.get_theme_font_size("font_size")
	var widest := 0.0
	for word in lab.text.split(" ", false):
		widest = maxf(widest, font.get_string_size(
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return widest
