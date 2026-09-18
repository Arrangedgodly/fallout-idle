extends GutTest
## tests/test_tutorial_reveal.gd — T33 tutorial deep-linking (run-5 Scope
## Amendment 3, complaint #4; the user's words are the law this suite pins:
## "Tutorial was very unclear, especially for FILE A CROWN CLAIM that you had
## to scroll to the bottom of a very large window to sell a product. It took
## me over 5 minutes to figure out what the fuck the game wanted me to do.")
##
## Coverage:
##   (a) THE TARGET MAP — every step resolves to its documented target
##       (department + control), including the honest prerequisite fallbacks
##       (sell with nothing held -> the stock's source; craft with missing
##       inputs -> the input's source; PROVISION splits equip/cook legs by
##       reachability);
##   (b) REVEAL PER STEP — the machinery selects the department, posts the
##       right tab (FILE A CROWNS CLAIM -> Depot/SELL), scrolls the docket so
##       the target control is FULLY in view (clipped-rect check), and marks
##       it with exactly ONE settle pulse — never stealing focus;
##   (c) HONEST PREREQUISITES — the step line gains its registered suffix
##       while the action is unreachable (WORK FOR INVENTORY FIRST / GATHER
##       SUPPLIES FIRST), within the <= 40-word form pin, and withdraws the
##       moment the action becomes reachable;
##   (d) MOTION DISCIPLINE — one pulse per reveal, bounded ~0.5 s, settles
##       to rest, never repeats (re-reveal restarts one pulse, never stacks);
##   (e) KEYBOARD PATH — a focused wayfinding row + real ui_accept deep-links
##       through the real input pipeline, and Esc returns to the department
##       the jump departed from;
##   (f) THE WALKTHROUGH (acceptance core) — a fresh save driven through all
##       seven steps using ONLY the reveal machinery + primary buttons,
##       asserting each step's target in view at the moment of the press and
##       the whole journey inside a bounded UI-action budget (the user took
##       over five minutes; the structural fix is a number: <= 25 presses).
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (test_engine.gd's discipline); the concourse runs in a
## SubViewport driven through the REAL input pipeline (test_orientation.gd's).
## The shipped content library drives the walkthrough (the whole economy is
## the subject; dossier merit pay is income, not noise, here).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260921
const ACTION_BUDGET := 25

var _vp: SubViewport
var _concourse: Concourse
var _actions := 0


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (the walkthrough runs on live data)")
	tm._boot(result.library, seed)
	return tm


func _flush(tm: Variant) -> void:
	tm.batcher.mark("inventory")
	tm.batcher.mark("orientation")
	tm.batcher.force_flush(tm.sim_time_ms)


func _pump(tm: Variant, total_ms: int, chunk_ms := 1_000) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _boot(seed := SEED) -> Variant:
	var tm: Variant = _make_tm(seed)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(_vp)
	_concourse = ConcourseScene.instantiate() as Concourse
	assert_not_null(_concourse, "concourse instantiates")
	_vp.add_child(_concourse)
	_concourse.bind_engines(tm)
	# Production boot fidelity + battery-order determinism: a session starts
	# at the 100% scale (an earlier suite's slider leg must not leak into
	# this suite's layout pins).
	var ui_theme: Node = get_tree().root.get_node_or_null("UiTheme")
	if ui_theme != null:
		ui_theme.apply_font_scale(1.0)
	await wait_frames(4)
	return tm


## The reveal's arrival: the bulkhead finishes (when it ran at all), then the
## reveal's own layout frame lands — scroll + pulse are asserted after this.
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


func _pulse_count(ctrl: Control) -> int:
	return int(ctrl.get_meta("reveal_pulses", 0))


func _push_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


func _push_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	_vp.push_input(ev)
	var rel := ev.duplicate() as InputEventKey
	rel.pressed = false
	_vp.push_input(rel)


## One walkthrough press — the acceptance accounting. A docket control must
## already be fully in view (the reveal put it there); a plate must be
## visible. The press itself rides the real input pipeline.
func _press(btn: Button, what: String, in_docket := true) -> void:
	_actions += 1
	assert_true(btn.is_visible_in_tree(), "walkthrough action %d (%s): control visible" % [_actions, what])
	if in_docket:
		_assert_in_view(btn, "walkthrough action %d (%s)" % [_actions, what])
	btn.grab_focus()
	await wait_frames(1)
	_push_accept()
	await wait_frames(2)


# ---------------------------------------------------------------------------
# (a) the documented target map
# ---------------------------------------------------------------------------

func test_target_map_matches_documented_choices() -> void:
	var tm: Variant = await _boot()
	_flush(tm)
	# WORK A POSTED SHIFT -> Scavenging's tier-1 card.
	var res := _concourse.step_reveal_resolution("work_shift")
	assert_eq(String(res["dept"]), "scavenging", "work_shift targets Scavenging")
	assert_eq((res["control"] as Control).name, "Card_sort_scrap_pile",
		"work_shift targets the tier-1 card")
	assert_eq(String(res["suffix"]), "", "work_shift carries no prerequisite")
	# EARN A CLEARANCE -> the active docket's XP meter (the gauge block).
	res = _concourse.step_reveal_resolution("earn_clearance")
	assert_eq(String(res["dept"]), "scavenging", "earn_clearance targets Scavenging")
	assert_eq((res["control"] as Control), (_concourse.docket_controller("scavenging") as DocketSkill).gauge_vent,
		"earn_clearance targets the clearance gauge vent")
	# FILE A CROWNS CLAIM, nothing held -> the honest SOURCE fallback.
	res = _concourse.step_reveal_resolution("file_crowns_claim")
	assert_eq(String(res["dept"]), "scavenging",
		"file_crowns_claim with an empty counter cues the stock's source")
	assert_eq((res["control"] as Control).name, "Card_sort_scrap_pile",
		"the fallback target is the source's tier-1 card")
	assert_eq(String(res["suffix"]), Concourse.SUFFIX_INVENTORY,
		"the honest prerequisite suffix posts")
	# PROCESS A PRODUCT, nothing craftable -> the missing input's source.
	res = _concourse.step_reveal_resolution("process_product")
	assert_eq(String(res["dept"]), "scavenging",
		"process_product with empty bins cues the input's source (scrap metal)")
	assert_eq(String(res["suffix"]), Concourse.SUFFIX_SUPPLIES,
		"the gather-supplies suffix posts")
	# PROVISION THE PATROL, no gear and no food inputs -> the cook leg's
	# missing input source (Duskcorn grows at Foraging).
	res = _concourse.step_reveal_resolution("provision_patrol")
	assert_eq(String(res["dept"]), "foraging",
		"provision_patrol fresh cues the Duskcorn source (Foraging — documented)")
	assert_eq(String(res["suffix"]), Concourse.SUFFIX_SUPPLIES,
		"the gather-supplies suffix posts on the cook leg too")
	# CLEAR A NUISANCE -> the first engageable fauna card.
	res = _concourse.step_reveal_resolution("clear_nuisance")
	assert_eq(String(res["dept"]), "wasteland_patrol", "clear_nuisance targets the Patrol")
	assert_eq((res["control"] as Control).name, "Fauna_junkyard_roach",
		"clear_nuisance targets the first engageable card (tier-1 fauna)")
	# DEPUTIZE A RESIDENT -> the personnel purchase row.
	res = _concourse.step_reveal_resolution("deputize_resident")
	assert_eq(String(res["dept"]), "personnel", "deputize_resident targets Personnel")
	assert_eq((res["control"] as Control).name, "DeputizeLine",
		"deputize_resident targets the purchase row")


func test_target_map_staged_states() -> void:
	var tm: Variant = await _boot()
	# Stock on hand: the sell fallback becomes the SELL row; the smelt recipe
	# becomes craftable; the cook leg still lacks Duskcorn.
	tm.state.add_item("scrap_metal", 30)
	_flush(tm)
	await wait_frames(1)
	var res := _concourse.step_reveal_resolution("file_crowns_claim")
	assert_eq(String(res["dept"]), "requisition_depot",
		"with stock held, FILE A CROWNS CLAIM targets the Depot")
	assert_eq(String(res["tab"]), DocketDepot.TAB_SELL, "the reveal posts the SELL tab")
	assert_eq((res["control"] as Control).name, "SellRow_scrap_metal",
		"the target is the first sellable row")
	assert_eq(String(res["suffix"]), "", "no prerequisite while the counter can tender")
	res = _concourse.step_reveal_resolution("process_product")
	assert_eq(String(res["dept"]), "junksmithing", "with inputs held, PROCESS targets Junksmithing")
	assert_eq((res["control"] as Control).name, "Card_smelt_scrap_ingot",
		"the target is the first craftable recipe card")
	# Duskcorn on hand: the cook leg becomes craftable -> Cooking's card.
	tm.state.add_item("duskcorn", 4)
	_flush(tm)
	await wait_frames(1)
	res = _concourse.step_reveal_resolution("provision_patrol")
	assert_eq(String(res["dept"]), "cooking", "with Duskcorn held, the cook leg targets Cooking")
	assert_eq((res["control"] as Control).name, "Card_grind_mandatory_grits",
		"the cook leg targets the first craftable food recipe")
	assert_eq(String(res["suffix"]), "", "the craftable cook leg carries no prerequisite")
	# Gear on hand: the equip leg wins -> the Manifest's EQUIP control.
	tm.state.add_item("scrap_shiv", 1)
	_flush(tm)
	await wait_frames(1)
	res = _concourse.step_reveal_resolution("provision_patrol")
	assert_eq(String(res["dept"]), "manifest", "with gear held, PROVISION targets the Manifest")
	assert_eq((res["control"] as Control).name, "EquipSelected",
		"the equip leg targets the EQUIP control")
	assert_eq(String(res["select_item"]), "scrap_shiv",
		"the reveal arms the gear line (the EQUIP control's honest enable)")
	# Source resolution sanity: crafted goods resolve through their recipe.
	var src: Dictionary = _concourse._item_source("scrap_ingot")
	assert_eq(String(src["skill"]), "junksmithing", "scrap_ingot sources from the forge")
	assert_eq(int(src["gate"]), 1, "at the recipe's own gate")


# ---------------------------------------------------------------------------
# (b) reveal per step — department + tab + scroll + pulse
# ---------------------------------------------------------------------------

func test_reveal_per_step_department_tab_scroll_and_pulse() -> void:
	var tm: Variant = await _boot()
	_flush(tm)
	var form := _concourse.orientation()
	# (1) WORK A POSTED SHIFT, via the wayfinding row (the real path). The
	# boot reveal already pulsed this card once — the press adds exactly one.
	var row: Button = form.row_for("work_shift")
	var focus_before: Control = _vp.gui_get_focus_owner()
	var pulses_before := _pulse_count(_concourse.docket_controller("scavenging")
		.find_child("Card_sort_scrap_pile", true, false))
	row.pressed.emit()
	await _await_settled()
	var card: Control = _concourse.docket_controller("scavenging").find_child("Card_sort_scrap_pile", true, false)
	assert_eq(_concourse.active_department(), "scavenging", "reveal keeps/opens the department")
	_assert_in_view(card, "the tier-1 card after the work_shift reveal")
	assert_eq(_pulse_count(card), pulses_before + 1, "exactly one settle pulse per reveal")
	assert_eq(_vp.gui_get_focus_owner(), focus_before, "the reveal never steals focus")
	# (2) EARN A CLEARANCE, via the public machinery.
	_concourse.reveal_step("earn_clearance")
	await _await_settled()
	var gauge_vent: Control = (_concourse.docket_controller("scavenging") as DocketSkill).gauge_vent
	_assert_in_view(gauge_vent, "the clearance gauge after the earn reveal")
	assert_eq(_pulse_count(gauge_vent), 1, "one pulse on the gauge vent")
	# Stock: the SELL row exists and the smelt recipe is craftable.
	tm.state.add_item("scrap_metal", 30)
	_flush(tm)
	await wait_frames(1)
	# (3) FILE A CROWNS CLAIM — the complaint's own journey: row press ->
	# Depot opens ON THE SELL BOARD with the first sellable row in view.
	form.row_for("file_crowns_claim").pressed.emit()
	await _await_settled()
	assert_eq(_concourse.active_department(), "requisition_depot",
		"the claim reveal opens the Depot")
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the Depot posts the SELL board")
	var sell_row: Control = depot.find_child("SellRow_scrap_metal", true, false)
	_assert_in_view(sell_row, "the first sellable row — no scrolling for the resident")
	assert_eq(_pulse_count(sell_row), 1, "one settle pulse on the sell row")
	# (4) PROCESS A PRODUCT.
	_concourse.reveal_step("process_product")
	await _await_settled()
	var smelt: Control = _concourse.docket_controller("junksmithing").find_child("Card_smelt_scrap_ingot", true, false)
	assert_eq(_concourse.active_department(), "junksmithing", "the craft reveal opens Junksmithing")
	_assert_in_view(smelt, "the craftable recipe card")
	assert_eq(_pulse_count(smelt), 1, "one pulse on the recipe card")
	# (5) PROVISION THE PATROL (cook leg with Duskcorn held).
	tm.state.add_item("duskcorn", 4)
	_flush(tm)
	await wait_frames(1)
	_concourse.reveal_step("provision_patrol")
	await _await_settled()
	var grits: Control = _concourse.docket_controller("cooking").find_child("Card_grind_mandatory_grits", true, false)
	assert_eq(_concourse.active_department(), "cooking", "the cook leg opens Cooking")
	_assert_in_view(grits, "the craftable food recipe card")
	# (6) CLEAR A NUISANCE.
	_concourse.reveal_step("clear_nuisance")
	await _await_settled()
	var roach: Control = _concourse.docket_controller("wasteland_patrol").find_child("Fauna_junkyard_roach", true, false)
	assert_eq(_concourse.active_department(), "wasteland_patrol", "the nuisance reveal opens the Patrol")
	_assert_in_view(roach, "the engageable fauna card")
	# (7) DEPUTIZE A RESIDENT.
	_concourse.reveal_step("deputize_resident")
	await _await_settled()
	var purchase: Control = _concourse.docket_controller("personnel").find_child("DeputizeLine", true, false)
	assert_eq(_concourse.active_department(), "personnel", "the deputize reveal opens Personnel")
	_assert_in_view(purchase, "the purchase row")


# ---------------------------------------------------------------------------
# (c) honest prerequisite suffixes
# ---------------------------------------------------------------------------

func test_prerequisite_suffix_posts_and_withdraws() -> void:
	var tm: Variant = await _boot()
	var form := _concourse.orientation()
	# Walk steps 1-2 through the real engine, holding NOTHING: the current
	# step becomes FILE A CROWNS CLAIM with an empty counter.
	tm.start_activity("sort_scrap_pile")
	tm.engine.grant_xp(tm.state, "scavenging", 25)  # level 2 (the shared pipeline)
	tm.stop_skill("scavenging")
	_flush(tm)
	await wait_frames(2)
	var row: Button = form.row_for("file_crowns_claim")
	var title: Label = row.get_node("Row/Title")
	assert_eq(title.text, "FILE A CROWNS CLAIM — WORK FOR INVENTORY FIRST",
		"the step line states the prerequisite honestly")
	assert_lte(form.word_count(), 40,
		"the low-text pin holds with the suffix (got %d words)" % form.word_count())
	assert_string_contains(String(row.tooltip_text).to_lower(), "do this first",
		"the accessible name states the prerequisite first")
	# The reveal cues the SOURCE while the suffix stands.
	var res := _concourse.step_reveal_resolution("file_crowns_claim")
	assert_eq(String(res["dept"]), "scavenging", "the fallback cue points at the stock's source")
	# Stock arrives: the suffix withdraws and the cue moves to the SELL row.
	tm.state.add_item("scrap_metal", 6)
	_flush(tm)
	await wait_frames(2)
	assert_eq(title.text, "FILE A CROWNS CLAIM",
		"the suffix withdraws the moment the counter can tender (copy never outlives its fact)")
	res = _concourse.step_reveal_resolution("file_crowns_claim")
	assert_eq(String(res["dept"]), "requisition_depot", "the cue moves to the Depot")
	# PROCESS: sell down to a sub-recipe stack and the gather suffix posts.
	tm.state.take_item("scrap_metal", 4)  # 6 -> 2 (smelt needs 3)
	tm.depot_sell("scrap_metal", 2)  # stamps FILE A CROWNS CLAIM, counter empty again
	_flush(tm)
	await wait_frames(2)
	var prow: Button = form.row_for("process_product")
	var ptitle: Label = prow.get_node("Row/Title")
	assert_eq(ptitle.text, "PROCESS A PRODUCT — GATHER SUPPLIES FIRST",
		"the craft step states its prerequisite while the bins run dry")
	tm.state.add_item("scrap_metal", 3)
	_flush(tm)
	await wait_frames(2)
	assert_eq(ptitle.text, "PROCESS A PRODUCT",
		"the craft suffix withdraws when the recipe becomes craftable")


# ---------------------------------------------------------------------------
# (d) motion discipline — one bounded pulse, never repeating
# ---------------------------------------------------------------------------

func test_pulse_fires_once_per_reveal_and_settles() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	_flush(tm)
	await wait_frames(1)
	_concourse.reveal_step("file_crowns_claim")
	await _await_settled()
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	var sell_row: Control = depot.find_child("SellRow_scrap_metal", true, false)
	assert_eq(_pulse_count(sell_row), 1, "one pulse per reveal")
	await wait_seconds(0.2)
	assert_eq(_pulse_count(sell_row), 1, "the pulse does not repeat inside its beat")
	# A re-reveal restarts ONE pulse (token-guarded), never stacks.
	_concourse.reveal_step("file_crowns_claim")
	await _await_settled()
	assert_eq(_pulse_count(sell_row), 2, "each reveal contributes exactly one pulse")
	# The pulse settles: back at rest inside the beat + the settle time.
	await wait_seconds(0.9)
	assert_eq((sell_row as Control).modulate, Color.WHITE, "the pulse settles to rest")
	var tw_v: Variant = sell_row.get_meta("reveal_pulse_tween") \
		if sell_row.has_meta("reveal_pulse_tween") else null
	assert_true(tw_v == null or not is_instance_valid(tw_v) \
			or not (tw_v as Tween).is_valid(),
		"no pulse tween lingers (bounded, never looping)")


# ---------------------------------------------------------------------------
# (e) keyboard path — wayfinding + Esc returns
# ---------------------------------------------------------------------------

func test_keyboard_wayfinding_row_deep_links_and_esc_returns() -> void:
	var tm: Variant = await _boot()
	tm.state.add_item("scrap_metal", 30)
	_flush(tm)
	await wait_frames(1)
	var form := _concourse.orientation()
	var row: Button = form.row_for("file_crowns_claim")
	row.grab_focus()
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), row, "the wayfinding row takes focus")
	_push_accept()
	await wait_frames(1)
	assert_true(await _await_department("requisition_depot"),
		"the focused row deep-links to the Depot via the real input pipeline")
	await wait_frames(3)  # the reveal's landing (scroll + pulse) follows the bulkhead
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the jump lands on the SELL board")
	var sell_row: Control = depot.find_child("SellRow_scrap_metal", true, false)
	_assert_in_view(sell_row, "the sell row is in view after the keyboard jump")
	assert_eq(_pulse_count(sell_row), 1, "the keyboard jump pulses once")
	assert_eq(_vp.gui_get_focus_owner(), row, "focus stays with the resident (no theft)")
	# Esc returns to the department the jump departed from (Scavenging, boot).
	_push_escape()
	await wait_frames(1)
	assert_true(await _await_department("scavenging"), "Esc returns to the departed department")
	# The memory is spent: a second Esc navigates nowhere.
	_push_escape()
	await wait_frames(6)
	assert_eq(_concourse.active_department(), "scavenging", "a spent Esc memory navigates no more")


func _await_department(id: String, budget_frames := 240) -> bool:
	var n := 0
	while n < budget_frames and (_concourse.is_transitioning()
			or _concourse.active_department() != id):
		await wait_frames(1)
		n += 1
	return _concourse.active_department() == id and not _concourse.is_transitioning()


# ---------------------------------------------------------------------------
# (f) THE WALKTHROUGH — seven steps, machinery + primary buttons, <= 25 presses
# ---------------------------------------------------------------------------

func test_walkthrough_fresh_save_all_steps_within_action_budget() -> void:
	var tm: Variant = await _boot()
	var form := _concourse.orientation()
	# The boot reveal posted step 1's target (the five-second contract).
	await _await_settled()
	var sort_card: Button = _concourse.docket_controller("scavenging").find_child("Card_sort_scrap_pile", true, false)
	_assert_in_view(sort_card, "boot reveal: the tier-1 card")

	# -- Step 1: WORK A POSTED SHIFT -- press the revealed card. --
	await _press(sort_card, "post the scrap-pile shift")
	assert_true(tm.orientation_step_done_bool("work_shift"), "step 1 stamped")
	_pump(tm, 240_000)  # the shift works (time, not presses)
	_flush(tm)
	await _await_settled()
	# The stamp walk posted the next targets: EARN stamped mid-shift, and the
	# claim reveal brought the Depot's SELL board up with the row in view.
	assert_true(tm.orientation_step_done_bool("earn_clearance"), "step 2 stamped by the shift's XP")
	assert_eq(_concourse.active_department(), "requisition_depot",
		"the claim reveal opened the Depot")
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the SELL board is posted")
	var first_id := depot.first_sellable_id()
	assert_ne(first_id, "", "the shift yielded sellable stock")
	var sell_row: Control = depot.find_child("SellRow_" + first_id, true, false)
	_assert_in_view(sell_row, "the first sellable row -- the five-minute hunt is over")

	# -- Step 3: FILE A CROWNS CLAIM -- press the row's SELL 1. --
	var sell1: Button = sell_row.find_child("Sell1_" + first_id, true, false)
	await _press(sell1, "tender one unit")
	assert_true(tm.orientation_step_done_bool("file_crowns_claim"), "step 3 stamped")
	_flush(tm)
	await _await_settled()
	var smelt: Button = _concourse.docket_controller("junksmithing").find_child("Card_smelt_scrap_ingot", true, false)
	assert_eq(_concourse.active_department(), "junksmithing", "the craft reveal opened Junksmithing")
	_assert_in_view(smelt, "the craftable recipe card")

	# -- Step 4: PROCESS A PRODUCT -- card press; the posting is full, so the
	# T31 strip's REASSIGN makes room (both are primary docket controls). --
	await _press(smelt, "ask for the smelt")
	var forge_strip: Button = _concourse.docket_controller("junksmithing").strip_reassign
	await _press(forge_strip, "reassign the posting to the smelt", false)
	assert_true(tm.state.active.has("junksmithing"), "the smelt holds the posting")
	_pump(tm, 5_000)  # one craft
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("process_product"), "step 4 stamped")
	# The provision reveal cues the cook leg's honest source: foraging.
	var walk_card: Button = _concourse.docket_controller("foraging").find_child("Card_walk_the_glow_rows", true, false)
	assert_eq(_concourse.active_department(), "foraging",
		"the provision reveal cues the Duskcorn source (nothing cookable yet)")
	_assert_in_view(walk_card, "the forage card in view")

	# -- Step 5: PROVISION THE PATROL -- forage, then cook. --
	await _press(walk_card, "ask for the forage walk")
	var forage_strip: Button = _concourse.docket_controller("foraging").strip_reassign
	await _press(forage_strip, "reassign the posting to the forage", false)
	assert_true(tm.state.active.has("foraging"), "the forage holds the posting")
	_pump(tm, 80_000)  # Duskcorn and Glowshroom bank up
	_flush(tm)
	await _await_settled()
	# Re-ask the step (the wayfinding row): the cook leg is now craftable.
	await _press(form.row_for("provision_patrol"), "re-ask PROVISION THE PATROL", false)
	await _await_settled()
	var grits: Button = _concourse.docket_controller("cooking").find_child("Card_grind_mandatory_grits", true, false)
	assert_eq(_concourse.active_department(), "cooking", "the cook leg opens Cooking")
	_assert_in_view(grits, "the grits card in view")
	await _press(grits, "ask for the grits")
	var cook_strip: Button = _concourse.docket_controller("cooking").strip_reassign
	await _press(cook_strip, "reassign the posting to the kitchen", false)
	assert_true(tm.state.active.has("cooking"), "the kitchen holds the posting")
	_pump(tm, 4_000)  # one food craft
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("provision_patrol"), "step 5 stamped (cooked food)")
	# The clear reveal posted the fauna card.
	var roach: Button = _concourse.docket_controller("wasteland_patrol").find_child("Fauna_junkyard_roach", true, false)
	assert_eq(_concourse.active_department(), "wasteland_patrol", "the clear reveal opened the Patrol")
	_assert_in_view(roach, "the fauna card in view")

	# -- Step 6: CLEAR A NUISANCE -- engage; reassign; let the fight run. --
	await _press(roach, "designate the roach")
	var patrol_strip: Button = _concourse.docket_controller("wasteland_patrol").strip_reassign
	await _press(patrol_strip, "reassign the posting to the patrol", false)
	assert_false(tm.state.active.has("cooking"), "the kitchen yielded the posting")
	assert_eq(String(tm.state.combat.get("phase", "")), "fighting", "the patrol is engaged")
	_pump(tm, 300_000, 2_500)  # the fight resolves (time, not presses)
	_flush(tm)
	await _await_settled()
	assert_true(tm.orientation_step_done_bool("clear_nuisance"), "step 6 stamped (victory)")
	var purchase: Control = _concourse.docket_controller("personnel").find_child("DeputizeLine", true, false)
	assert_eq(_concourse.active_department(), "personnel", "the deputize reveal opened Personnel")
	_assert_in_view(purchase, "the purchase row in view")

	# -- Step 7: DEPUTIZE A RESIDENT -- afford it honestly: re-ask the FILE
	# step on the form (OPEN the folded slip, press the wayfinding row) -- the
	# reveal brings the SELL board back with the first stack in view, and each
	# tender withdraws its row, pulling the next one up (no scrolling anywhere:
	# only reveals and primary buttons).
	await _press(form.get_node("FormColumn/FormHeader/OpenForm"), "open the posted slip", false)
	await _press(form.row_for("file_crowns_claim"), "re-ask FILE A CROWNS CLAIM", false)
	await _await_settled()
	assert_eq(_concourse.active_department(), "requisition_depot",
		"the re-ask revealed the Depot")
	assert_eq(depot.active_tab(), DocketDepot.TAB_SELL, "the SELL board is posted again")
	var sells := 0
	while tm.state.crowns < 300 and sells < 12:
		var btn := _first_in_view_sellall(depot)
		assert_not_null(btn, "an in-view tender button is always on offer")
		if btn == null:
			break
		await _press(btn, "tender a stack (%d)" % (sells + 1))
		_flush(tm)
		await wait_frames(1)
		sells += 1
	assert_gte(tm.state.crowns, 300, "the honest journey affords the deputy ladder")
	# Re-ask the final step the honest way (the form is already open from the
	# re-ask above): press the wayfinding row -- the reveal brings the
	# purchase row back into view.
	await _press(form.row_for("deputize_resident"), "re-ask DEPUTIZE A RESIDENT", false)
	await _await_settled()
	var deputize: Button = _concourse.docket_controller("personnel").deputize_button
	await _press(deputize, "deputize a resident")
	assert_true(tm.orientation_step_done_bool("deputize_resident"), "step 7 stamped")
	assert_true(bool(tm.state.orientation["completed"]), "FORM O-1 complete: DULY ORIENTED")

	# THE STRUCTURAL PIN: the whole journey inside the action budget.
	print("WALKTHROUGH ACTION COUNT: %d (budget %d)" % [_actions, ACTION_BUDGET])
	assert_lte(_actions, ACTION_BUDGET,
		"the seven-step walkthrough took %d UI actions (budget %d; the user took over five minutes)"
			% [_actions, ACTION_BUDGET])
	assert_gte(int(tm.state.crowns), 150, "the completion stipend posted on top of the wallet")


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
