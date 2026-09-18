extends GutTest
## tests/test_refusal_feedback.gd — T31 refusal feedback + REASSIGN (run-5
## Scope Amendment 3; the user's words: "Skills require manually being shut
## off to trigger a new skill, there is no UI feedback when you click a skill
## and it doesn't engage (unclear whether its because you lack resources, are
## currently training another skill, etc.)").
##
## Coverage:
##   (a) engine swap semantics — validate-then-cease+start atomic on
##       ActivityEngine.swap_posting and CombatSession.swap_engage:
##       refusals (clearance / resources) return BEFORE any mutation (the
##       original posting keeps running — never stranded), the default cease
##       target is the OLDEST held posting (the enforce_staffing order; an
##       engaged patrol competes on engage_ms and withdraws alive with its
##       designation preserved), an explicit cease target is honored and a
##       stale one falls back to oldest, a same-skill swap replaces in place,
##       and a free posting means nothing is ceased;
##   (b) refusal kinds — slot-full keeps the §14 machine id
##       ("posting_refused"), clearance and supplies refusals carry their own
##       kinds ("clearance_refused" / "resources_refused") and the supplies
##       payload names the missing inputs with counts (truthful attribution);
##   (c) UI feedback — the refusal strip posts at the TOP of the docket
##       (child index 0, in-flow, above the cards) with the reason in voice
##       ("ALL POSTINGS ASSIGNED — CEASE ONE OR REASSIGN" / "CLEARANCE N
##       REQUIRED — EARN IT IN THIS DEPARTMENT" / "INSUFFICIENT SUPPLIES: …"),
##       the clicked card flashes its "× " denial cue at the click point (one
##       bounded flash, then the canonical state), and a successful action or
##       the truth gate clears the strip;
##   (d) REASSIGN — the strip restates the swap ("REASSIGN — CEASE …,
##       COMMENCE …"), the button is keyboard-reachable, a REAL ui_accept on
##       the focused button executes the engine swap, and the strip confirms
##       ("POSTING REASSIGNED" + what actually ceased); DISMISS clears via a
##       real mouse click.
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (test_engine.gd's discipline); the concourse runs in a
## SubViewport driven through the REAL input pipeline (test_orientation.gd's).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260919
const NOW := 1_768_000_000_000

const STRIP_SLOT_FULL := "ALL POSTINGS ASSIGNED — CEASE ONE OR REASSIGN"
const STRIP_CLEARANCE := "CLEARANCE %d REQUIRED — EARN IT IN THIS %s"
const STRIP_SUPPLIES := "INSUFFICIENT SUPPLIES: %s"
const STRIP_PLAN := "REASSIGN — CEASE %s, COMMENCE %s"
const STRIP_REASSIGNED := "POSTING REASSIGNED"


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (refusal tests run on live data)")
	return result.library


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _staff(tm: Variant, deputies: int) -> void:
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = deputies


func _set_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in b:
		if not a.has(x):
			return false
	return true


# ---------------------------------------------------------------------------
# (a)+(b) engine swap semantics + refusal kinds
# ---------------------------------------------------------------------------

func test_swap_validates_first_and_never_strands() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the resident's posting starts")

	# Resources veto: the dry recipe is refused BEFORE anything ceases, with
	# the missing inputs named (have/need counts from live inventory).
	var dry: Dictionary = tm.swap_posting("smelt_scrap_ingot")
	assert_false(dry["ok"], "swapping to a resource-gated recipe with no stock refuses")
	assert_eq(str(dry.get("kind")), "resources_refused", "the refusal kind is resources")
	assert_true(str(dry.get("reason")).contains("INSUFFICIENT SUPPLIES: 3× SCRAPNEL"),
		"the reason names the missing input with counts: %s" % str(dry.get("reason")))
	assert_eq((dry.get("missing", []) as Array).size(), 1, "the payload carries one missing line")
	assert_eq(int((dry.get("missing", [{}])[0] as Dictionary).get("need", 0)), 3, "need count from the recipe")
	assert_eq(int((dry.get("missing", [{}])[0] as Dictionary).get("have", -1)), 0, "have count from the manifest")
	assert_eq(tm.state.active.keys(), ["scavenging"], "NO STRAND: the original posting still runs")
	assert_eq(tm.occupied_postings(), 1, "the posting was never ceased")

	# Clearance veto: same no-strand guarantee, clearance kind.
	var gated: Dictionary = tm.swap_posting("forge_scrap_shiv")
	assert_false(gated["ok"], "swapping past a clearance gate refuses")
	assert_eq(str(gated.get("kind")), "clearance_refused", "the refusal kind is clearance")
	assert_eq(int(gated.get("gate", {}).get("level", 0)), 8, "the gate payload names the grade")
	assert_eq(tm.state.active.keys(), ["scavenging"], "NO STRAND after the clearance refusal")

	# Plain start refuses with the same kinds (attribution parity).
	var plain: Dictionary = tm.start_activity("forge_scrap_shiv")
	assert_eq(str(plain.get("kind")), "clearance_refused", "start carries the clearance kind too")


func test_swap_ceases_oldest_and_starts_atomically() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	var swap: Dictionary = tm.swap_posting("walk_the_glow_rows")
	assert_true(swap["ok"], "the one-press swap succeeds: %s" % str(swap))
	var ceased: Dictionary = swap.get("ceased", {})
	assert_eq(str(ceased.get("skill_id")), "scavenging", "the oldest (only) posting ceased")
	assert_eq(str(ceased.get("content_id")), "sort_scrap_pile", "the ceased record is named")
	assert_eq(tm.state.active.keys(), ["foraging"], "the new posting holds")
	assert_eq(str(tm.state.active["foraging"].get("content_id")), "walk_the_glow_rows")
	assert_eq(tm.occupied_postings(), 1, "atomic: exactly one posting before and after")


func test_swap_same_skill_replaces_in_place_ceases_nothing() -> void:
	var tm: Variant = _make_tm()
	_staff(tm, 1)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	tm.engine.grant_xp(tm.state, "scavenging", 20_000)  # drain_the_sump gate 10
	var swap: Dictionary = tm.swap_posting("drain_the_sump", "foraging")
	assert_true(swap["ok"], "a same-skill swap succeeds")
	assert_true((swap.get("ceased", {}) as Dictionary).is_empty(),
		"the skill's own posting reuses — nothing ceased: %s" % str(swap.get("ceased")))
	assert_eq(tm.occupied_postings(), 1, "the same posting still holds (replaced in place)")
	assert_eq(str(tm.state.active["scavenging"].get("content_id")), "drain_the_sump",
		"the skill's slot replaced in place")


func test_swap_explicit_cease_target_and_oldest_fallback() -> void:
	var tm: Variant = _make_tm()
	_staff(tm, 1)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
	tm.engine.grant_xp(tm.state, "scavenging", 20_000)
	tm.state.add_item("duskcorn", 100)

	# Explicit target: the named posting ceases (foraging), not the oldest.
	var explicit: Dictionary = tm.swap_posting("grind_mandatory_grits", "foraging")
	assert_true(explicit["ok"], "explicit-cease swap succeeds: %s" % str(explicit))
	assert_eq(str(explicit.get("ceased", {}).get("skill_id")), "foraging",
		"the CHOSEN posting ceased: %s" % str(explicit.get("ceased")))
	assert_true(_set_eq(tm.state.active.keys(), ["cooking", "scavenging"]),
		"the new posting holds beside the untouched one")

	# Stale target (no longer held) falls back to the OLDEST held posting:
	# drain_the_sump's anchor (its start) predates grind's.
	var fallback: Dictionary = tm.swap_posting("walk_the_glow_rows", "foraging")
	assert_true(fallback["ok"], "fallback swap succeeds")
	assert_eq(str(fallback.get("ceased", {}).get("skill_id")), "scavenging",
		"the oldest held posting ceased when the named one is gone: %s" % str(fallback.get("ceased")))
	assert_true(_set_eq(tm.state.active.keys(), ["cooking", "foraging"]), "the swap landed")


func test_swap_with_free_posting_ceases_nothing() -> void:
	var tm: Variant = _make_tm()
	_staff(tm, 3)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"])
	tm.state.add_item("scrap_metal", 100)
	var swap: Dictionary = tm.swap_posting("smelt_scrap_ingot")
	assert_true(swap["ok"], "the swap starts through the free posting")
	assert_true((swap.get("ceased", {}) as Dictionary).is_empty(),
		"a free posting means nothing is ceased: %s" % str(swap.get("ceased")))
	assert_eq(tm.state.active.keys().size(), 3, "three postings hold")


func test_missing_inputs_names_every_short_line() -> void:
	var tm: Variant = _make_tm()
	tm.engine.grant_xp(tm.state, "junksmithing", 4_000)  # forge_scrap_shiv gate 8
	var r: RecipeDef = tm.engine.lib.recipe("forge_scrap_shiv")
	var missing: Array = tm.engine.missing_inputs(tm.state, r)
	assert_eq(missing.size(), 2, "both inputs short (2× Almost Bullion, 1× Compliant Wire)")
	assert_eq(ActivityEngine.missing_voice(missing), "2× ALMOST BULLION · 1× COMPLIANT WIRE",
		"the voice line names each missing input with its count: %s"
			% ActivityEngine.missing_voice(missing))
	tm.state.add_item("scrap_ingot", 2)
	tm.state.add_item("compliant_wire", 1)
	assert_eq(tm.engine.missing_inputs(tm.state, r).size(), 0, "stocked: nothing missing")


func test_patrol_swap_and_no_strand() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the skill holds the one posting")

	# Clearance veto first: the patrol keeps nothing, loses nothing.
	var veto: Dictionary = tm.swap_engage("fizzard")
	assert_false(veto["ok"], "a clearance-gated patrol swap refuses")
	assert_eq(str(veto.get("kind")), "clearance_refused", "the refusal kind is clearance")
	assert_eq(str(tm.state.combat.get("phase")), "idle", "no fight started")

	# The real swap: cease the skill posting, engage atomically.
	var swap: Dictionary = tm.swap_engage("junkyard_roach")
	assert_true(swap["ok"], "the patrol swap succeeds: %s" % str(swap))
	assert_eq(str(swap.get("ceased", {}).get("skill_id")), "scavenging", "the skill posting made room")
	assert_eq(str(tm.state.combat.get("phase")), "fighting", "the patrol fights")
	assert_eq(tm.state.active.keys(), [], "the skill posting is gone (not stranded mid-)")
	assert_eq(tm.occupied_postings(), 1, "exactly one posting held")

	# A refused swap while FIGHTING strands nothing (the patrol keeps fighting).
	var gated: Dictionary = tm.swap_engage("fizzard")
	assert_false(gated["ok"], "the gated re-designation refuses")
	assert_eq(str(tm.state.combat.get("phase")), "fighting", "the fight continues")


func test_skill_swap_ceases_the_patrol_when_it_is_oldest() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.swap_engage("junkyard_roach")["ok"], "the patrol takes the posting first")
	var swap: Dictionary = tm.swap_posting("sort_scrap_pile")
	assert_true(swap["ok"], "the skill swap succeeds")
	assert_true(bool(swap.get("ceased", {}).get("combat", false)),
		"the ceased posting was the patrol: %s" % str(swap.get("ceased")))
	assert_eq(str(tm.state.combat.get("phase")), "idle", "the patrol withdrew alive")
	assert_eq(str(tm.state.combat.get("monster_id")), "junkyard_roach",
		"the designation is preserved (re-engage anytime)")
	assert_eq(tm.state.active.keys(), ["scavenging"], "the skill holds the posting")


# ---------------------------------------------------------------------------
# (c)+(d) UI: the strip at the top, the denial cue, REASSIGN, clearing
# ---------------------------------------------------------------------------

var _vp: SubViewport
var _concourse: Concourse


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


func _push_accept() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)


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


func test_strip_posts_at_top_on_refused_click_with_reassign() -> void:
	var tm: Variant = await _boot_concourse()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the board is full")
	_concourse.select_department("foraging", true)
	await wait_frames(2)
	var forage: DocketGathering = _concourse.docket_controller("foraging")

	forage.select_content("walk_the_glow_rows")
	await wait_frames(2)

	# THE fix: the strip is the docket's FIRST child — top of the docket,
	# in-flow, above the cards (never below the fold).
	assert_eq(forage.refusal_strip.get_index(), 0, "the refusal strip pins the docket's top")
	assert_true(forage.refusal_strip.visible, "the strip is posted")
	assert_eq(forage.strip_head.text, "POSTING REFUSED", "the head is the naming-bible serial")
	assert_eq(forage.strip_serial.text, STRIP_SLOT_FULL, "the reason in voice")
	assert_eq(forage.strip_plan.text, STRIP_PLAN % ["SCAVENGING", "WALK THE GLOW ROWS"],
		"the restatement names the cease and the commence: %s" % forage.strip_plan.text)
	assert_true(forage.strip_reassign.visible, "REASSIGN is offered on the slot refusal")
	assert_true(_concourse.focusable_controls().has(forage.strip_reassign),
		"REASSIGN is keyboard-reachable")
	assert_true(_concourse.focusable_controls().has(forage.strip_dismiss),
		"DISMISS is keyboard-reachable")

	# The click point answers too: the clicked card flashes the denial cue.
	var card = forage._cards["walk_the_glow_rows"]
	assert_true(bool(forage._deny_active.get("walk_the_glow_rows", false)), "the flash is live")
	assert_eq(card.title.theme_type_variation, "FormTitleDanger", "red ink (the registered pair)")
	assert_eq(card.title.text, "× WALK THE GLOW ROWS", "the × prefix is the non-color cue")
	await wait_seconds(0.8)
	assert_false(bool(forage._deny_active.get("walk_the_glow_rows", false)), "one bounded flash, then it reverts")
	assert_eq(card.title.text, "Walk the Glow Rows", "the canonical title restored")
	assert_eq(card.title.theme_type_variation, "FormTitle", "the canonical variation restored")
	assert_true(forage.refusal_strip.visible, "the refusal strip stands until answered")


func test_reassign_via_real_input_swaps_and_confirms() -> void:
	var tm: Variant = await _boot_concourse()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the board is full")
	_concourse.select_department("foraging", true)
	await wait_frames(2)
	var forage: DocketGathering = _concourse.docket_controller("foraging")
	forage.select_content("walk_the_glow_rows")
	await wait_frames(2)
	assert_true(forage.refusal_strip.visible, "the refusal strip is posted")

	# REAL input: focus the REASSIGN button, press ui_accept through the
	# SubViewport's input pipeline.
	forage.strip_reassign.grab_focus()
	await wait_frames(1)
	assert_eq(_vp.gui_get_focus_owner(), forage.strip_reassign, "REASSIGN holds focus")
	_push_accept()
	await wait_frames(2)

	assert_eq(tm.state.active.keys(), ["foraging"], "the swap executed: foraging holds")
	assert_eq(str(tm.state.active["foraging"].get("content_id")), "walk_the_glow_rows")
	assert_eq(tm.occupied_postings(), 1, "atomic — one posting")
	assert_eq(forage.strip_head.text, STRIP_REASSIGNED, "the strip CONFIRMS")
	assert_true(forage.strip_serial.text.contains("CEASED SCAVENGING"),
		"the confirmation names what actually ceased: %s" % forage.strip_serial.text)
	assert_true(forage.strip_serial.text.contains("NOW HOLDS THE POSTING"),
		"the confirmation names the new holder")
	assert_false(forage.strip_reassign.visible, "the confirmation offers no second swap")

	# DISMISS: a real mouse click at the button's center clears the strip.
	# The expanded O-1 form leaves the docket viewport short (the fresh-game
	# state), so focus DISMISS first — the T29 focus-follow scrolls it fully
	# into the viewport (the keyboard-reveal discipline) — then click the
	# settled center.
	forage.strip_dismiss.grab_focus()
	await wait_frames(2)
	var at: Vector2 = forage.strip_dismiss.get_global_rect().get_center()
	await _real_click(at)
	await wait_frames(2)
	assert_false(forage.refusal_strip.visible, "a real click on DISMISS clears the strip")


func test_supplies_strip_names_the_missing_stock() -> void:
	var tm: Variant = await _boot_concourse()
	_concourse.select_department("cooking", true)
	await wait_frames(2)
	var cook: DocketProcessing = _concourse.docket_controller("cooking")

	cook.select_content("grind_mandatory_grits")  # needs 2× Duskcorn; none stocked
	await wait_frames(2)
	assert_true(cook.refusal_strip.visible, "the supplies refusal posts the strip")
	assert_eq(cook.strip_head.text, "SUPPLIES MISSING", "the head names the family")
	assert_eq(cook.strip_serial.text, STRIP_SUPPLIES % "2× DUSKCORN",
		"the missing input with its count: %s" % cook.strip_serial.text)
	assert_false(cook.strip_reassign.visible, "no REASSIGN on a supplies refusal")
	var card = cook._cards["grind_mandatory_grits"]
	assert_eq(card.title.text, "× GRIND MANDATORY GRITS", "the clicked card answers")

	# Truth gate: stocking the line withdraws the strip on the next flush.
	tm.state.add_item("duskcorn", 4)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await wait_frames(2)
	assert_false(cook.refusal_strip.visible, "the strip withdraws when the fact clears")


func test_clearance_strip_attribution_and_truth_gate() -> void:
	var tm: Variant = await _boot_concourse()
	_concourse.select_department("junksmithing", true)
	await wait_frames(2)
	var forge: DocketProcessing = _concourse.docket_controller("junksmithing")

	# Clearance outranks supplies in the strip's attribution (the gate fires
	# first — the engine's own order).
	forge.select_content("forge_scrap_shiv")  # gate 8, clearance 1, no stock either
	await wait_frames(2)
	assert_true(forge.refusal_strip.visible, "the clearance refusal posts the strip")
	assert_eq(forge.strip_head.text, "CLEARANCE REQUIRED", "the head names the family")
	assert_eq(forge.strip_serial.text, STRIP_CLEARANCE % [8, "DEPARTMENT"],
		"the grade and the earning surface: %s" % forge.strip_serial.text)
	assert_false(forge.strip_reassign.visible, "no REASSIGN on a clearance refusal")

	# Truth gate: earning the grade withdraws the strip (and flips to the
	# supplies fact on the next click — attribution follows the state).
	tm.engine.grant_xp(tm.state, "junksmithing", 20_000)
	tm.batcher.mark("xp")
	tm.batcher.force_flush(tm.sim_time_ms)
	await wait_frames(2)
	assert_false(forge.refusal_strip.visible, "the strip withdraws when the grade is earned")


func test_successful_start_clears_a_standing_strip() -> void:
	var tm: Variant = await _boot_concourse()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the board is full")
	_concourse.select_department("foraging", true)
	await wait_frames(2)
	var forage: DocketGathering = _concourse.docket_controller("foraging")
	forage.select_content("walk_the_glow_rows")
	await wait_frames(2)
	assert_true(forage.refusal_strip.visible, "the refusal strip stands")

	# The resident answers by hand: cease, then start — the strip clears on
	# the next successful action from this docket.
	tm.stop_skill("scavenging")
	await wait_frames(2)
	assert_false(forage.refusal_strip.visible, "truth gate: a freed posting withdraws the strip")
	forage.select_content("walk_the_glow_rows")
	await wait_frames(2)
	assert_eq(tm.state.active.keys(), ["foraging"], "the shift starts")
	assert_false(forage.refusal_strip.visible, "a successful start keeps the strip clear")


func test_patrol_strip_reassign_flow() -> void:
	var tm: Variant = await _boot_concourse()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the board is full")
	_concourse.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol: DocketPatrol = _concourse.docket_controller("wasteland_patrol")

	patrol._engage("junkyard_roach")
	await wait_frames(2)
	assert_true(patrol.refusal_strip.visible, "the refused engage posts the strip")
	assert_eq(patrol.strip_serial.text, STRIP_SLOT_FULL, "the reason in voice")
	assert_eq(patrol.strip_plan.text, STRIP_PLAN % ["SCAVENGING", "LITTERBUG"],
		"the patrol's restatement uses the fauna's display name: %s" % patrol.strip_plan.text)
	assert_eq(patrol.strip_plan.text, "REASSIGN — CEASE SCAVENGING, COMMENCE LITTERBUG",
		"the exact restatement")
	var card = patrol._cards["junkyard_roach"]
	assert_eq(card.title.text, "× LITTERBUG", "the clicked fauna card answers")

	# REASSIGN through the strip (press) → the patrol swaps in.
	patrol.strip_reassign.pressed.emit()
	await wait_frames(2)
	assert_eq(str(tm.state.combat.get("phase")), "fighting", "the patrol fights")
	assert_eq(tm.state.active.keys(), [], "the skill posting ceased")
	assert_eq(patrol.strip_head.text, STRIP_REASSIGNED, "the strip confirms")
	assert_true(patrol.strip_serial.text.contains("LITTERBUG NOW HOLDS THE POSTING"),
		"the confirmation is patrol-voiced: %s" % patrol.strip_serial.text)

	# A refused swap while fighting strands nothing and re-attributes.
	patrol._engage("fizzard")
	await wait_frames(2)
	assert_eq(str(tm.state.combat.get("phase")), "fighting", "the fight continues")
	assert_eq(patrol.strip_head.text, "CLEARANCE REQUIRED", "the strip re-attributes truthfully")
	assert_eq(patrol.strip_serial.text, STRIP_CLEARANCE % [7, "ZONE"],
		"the patrol's earning surface is the ZONE (Fizzard's gate is 7): %s" % patrol.strip_serial.text)
