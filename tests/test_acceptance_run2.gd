extends GutTest
## tests/test_acceptance_run2.gd — T21 run-2 acceptance suite (Hawkeye lane).
##
## Automates the Scope Amendment 1 acceptance criteria (town-hall.md, run 2)
## headless against LIVE content, JOURNEY style — each test walks one resident
## from a fresh save (or a v1 record for the migration journey) through the
## real engines, the real facades, and where the criterion is visible, the real
## concourse. The per-system unit batteries stay in their run-2 homes
## (tests/test_staffing.gd, tests/test_orientation.gd, tests/test_icons_ui.gd);
## this file certifies the AMENDMENT criteria end to end:
##
##   A1  tutorial journey — fresh save → the ORIENTATION FORM O-1 is posted
##       with step 1 cued; all 7 steps complete through real engine events (a
##       real gathered clearance, a real Depot tender, a real craft, a real
##       equip, a real victory, a real deputize); DULY ORIENTED posts with the
##       stipend granted EXACTLY once, the record settles into its slip, the
##       ≤ 40-word pin carries in every state, and a completed record never
##       re-rewards through a real save/load round trip.
##   A2  slot-enforcement journey — fresh save → a second skill start is
##       refused with the verbatim POSTING REFUSED directive and ZERO state
##       change; deputy 1 is bought with 250 Crowns EARNED through the
##       slice's own economy (gather → sell at the Depot) via the real
##       purchase path; the second skill then starts and both run
##       concurrently; ceasing frees the posting again.
##   A3  icon coverage — every stats-panel stat resolves a glyph (structural
##       sweep over derived_stats), every locked gate plate across ALL six
##       content dockets carries the clearance staircase, log lines carry
##       their subject marks (drop + battle logs), and every price line on
##       the Depot AND the Personnel purchase line carries the crown mark.
##       The sweeps are exhaustive where practical (gate plates, Depot rows);
##       the mapping table below documents the one spot-set (stat → glyph).
##   A4  migration journey — a hand-degraded v1 record (3 running skills)
##       loads through the real SaveStore: slots enforced (newest posting
##       survives, losers parked with full slot state), the honest suspension
##       notice posts verbatim in the MAIL CALL, a further start is refused,
##       re-posting clears a parked entry, the record re-files as v2, and the
##       orientation namespace back-fills exactly its lifetime evidence.
##
## Determinism: fresh TickManager twins booted with explicit seeds via _boot(),
## never added to the tree (advance_wall_ms is the only clock input — the same
## discipline as test_acceptance/test_staffing/test_orientation).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260921
const NOW := 1_768_000_000_000
const TICK_MS := 100
const WORD_BUDGET := 40  ## the amendment's "a little too text heavy" law, as pinned

const REFUSAL_SERIAL := "ALL DEPUTIES ARE ASSIGNED. CEASE A POSTING, OR DEPUTIZE ANOTHER RESIDENT AT THE PERSONNEL PLATE. EITHER REMEDY IS CHEERFULLY SUPPORTED."
const SUSPENDED_NOTICE := "POSTINGS SUSPENDED — PERSONNEL SHORTAGE"
const STAMP_LINE := "DULY ORIENTED · FORM O-1"
const STIPEND_LINE := "ORIENTATION STIPEND — 150 CROWNS · THANK YOU FOR YOUR PROMPT COMPLIANCE."

## derived_stats key → the glyph that names it (docket.gd's GLYPH_* constants).
## min_hit and max_hit share one stat_max_hit glyph (the panel posts them as a
## single "MAX HIT 1-4" segment) — that sharing IS the mapping, not a gap.
const STAT_GLYPHS := {
	"max_hp": "stat_condition",
	"accuracy": "stat_accuracy",
	"evasion": "stat_evade",
	"min_hit": "stat_max_hit",
	"max_hit": "stat_max_hit",
	"speed": "stat_interval",
}
const SKILL_DEPTS := ["scavenging", "foraging", "junksmithing", "cooking"]


# ------------------------------------------------------------------ helpers --

func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (run-2 acceptance runs on live data)")
	return result.library


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


func _flush(tm: Variant, regions: Array = ["inventory"]) -> void:
	for region in regions:
		tm.batcher.mark(region)
	tm.batcher.force_flush(tm.sim_time_ms)


func _make_concourse(tm: Variant) -> Concourse:
	var c := ConcourseScene.instantiate() as Concourse
	assert_not_null(c, "concourse scene instantiates")
	add_child_autofree(c)
	c.bind_engines(tm)
	await wait_frames(2)
	return c


func _tmp_dir(label: String) -> String:
	var dir := OS.get_user_data_dir().path_join("t21_run2/%s_%d" % [label, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _glyph_count(root_node: Node, glyph_id: String) -> int:
	var n := 0
	for node in root_node.find_children("*", "TextureRect", true, false):
		if node is TextureRect:
			var t: Texture2D = (node as TextureRect).texture
			if t != null and t.resource_path.ends_with("/%s.svg" % glyph_id) \
					and (node as TextureRect).is_visible_in_tree():
				n += 1
	return n


func _done(tm: Variant, step_id: String) -> bool:
	return tm.orientation_step_done_bool(step_id)


# ---------------------------------------------------------------------------
# A1 — tutorial journey: the O-1 form from first posting to DULY ORIENTED
# ---------------------------------------------------------------------------

func test_a1_tutorial_journey_seven_steps_to_duly_oriented() -> void:
	var tm: Variant = _make_tm()
	var c := await _make_concourse(tm)
	var form: OrientationForm = c.orientation()
	assert_not_null(form, "the ORIENTATION FORM O-1 mounts on the concourse")
	assert_true(form.visible, "the form is posted (a notice, never a modal)")
	assert_true(form.is_expanded(), "fresh save: the form meets the resident EXPANDED")
	assert_lte(form.word_count(), WORD_BUDGET,
		"AMENDMENT PIN: the fresh form is low-text (<= 40 words, got %d)" % form.word_count())
	# First step cued: row 1 carries the arrow, the plate cue is posted, and the
	# engine's current step is WORK A POSTED SHIFT.
	assert_eq(str(tm.orientation_progress()["current"]), "work_shift",
		"the engine's first open step is WORK A POSTED SHIFT")
	var row1: Button = form.row_for("work_shift")
	assert_true((row1.get_node("Row/ArrowGlyph") as Control).is_visible_in_tree(),
		"the current row carries the orient_arrow cue")
	assert_true(c.cue().visible, "the plate cue is posted beside the destination")

	var stamped: Array = []
	tm.orientation_step_done.connect(func(step_id: String) -> void: stamped.append(step_id))
	var completed: Array = []
	tm.orientation_completed.connect(func(payload: Dictionary) -> void: completed.append(payload))

	# ---- step 1/2 — a real gathering shift: start stamps WORK A POSTED SHIFT,
	# and its real ticks carry the first clearance across (level 2 at 20 xp).
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "step 1: BEGIN SHIFT on the scrap pile")
	assert_true(_done(tm, "work_shift"), "WORK A POSTED SHIFT stamped by the real start event")
	_pump(tm, 8_000, TICK_MS)
	assert_eq(int(tm.state.skills_level["scavenging"]), 2,
		"two real actions crossed clearance 02 (the balance hook's own promise)")
	assert_true(_done(tm, "earn_clearance"), "EARN A CLEARANCE stamped by the real level-up path")
	assert_eq(tm.state.orientation["steps_done"], ["work_shift", "earn_clearance"],
		"steps_done always sits in posted order (canonical set semantics)")
	tm.stop_skill("scavenging")  # one posting: cease frees it for the craft leg

	# ---- step 3 — a real Depot tender files the claim (the journey's own drops).
	var lib := _lib()
	var metal: int = tm.state.item_count("scrap_metal")
	assert_gt(metal, 0, "the shift gathered Scrapnel to tender")
	var sale: Dictionary = tm.depot_sell("scrap_metal")  # whole stack
	assert_true(sale["ok"], "step 3: the Depot tenders the whole Scrapnel stack")
	assert_eq(int(sale["crowns"]), metal * lib.item("scrap_metal").value,
		"tender pays ItemDef.value x stack EXACTLY (honest sell price)")
	assert_eq(tm.state.crowns, metal * 2, "wallet arithmetic exact")
	assert_true(_done(tm, "file_crowns_claim"), "FILE A CROWNS CLAIM stamped by the real sale")

	# ---- step 4 — a real (non-food) craft stamps the product step only.
	tm.state.add_item("scrap_metal", 30)
	assert_true(tm.start_activity("smelt_scrap_ingot")["ok"], "step 4: post the smelter")
	_pump(tm, 5_000, TICK_MS)
	assert_true(_done(tm, "process_product"), "PROCESS A PRODUCT stamped by a real recipe action")
	assert_false(_done(tm, "provision_patrol"), "an ingot is not a provision (equip-or-cook owns that)")
	tm.stop_skill("junksmithing")

	# ---- step 5 — a real equip provisions the patrol (the other qualifying leg).
	tm.state.add_item("scrap_shiv", 1)
	assert_true(tm.equip_item("scrap_shiv")["ok"], "step 5: EQUIP the shiv from the Manifest")
	assert_true(_done(tm, "provision_patrol"), "PROVISION THE PATROL stamped by the real equip leg")

	# ---- step 6 — a real fight to VICTORY POSTED.
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "step 6: ENGAGE the Litterbug")
	_pump(tm, 300_000, 2_500)
	assert_eq(str(tm.state.combat["phase"]), "victory", "the fight resolved VICTORY POSTED")
	assert_true(_done(tm, "clear_nuisance"), "CLEAR A NUISANCE stamped by the real victory")

	# ---- step 7 — a real deputize purchase is the seventh stamp (and the
	# completion fires with the stipend — the T20 ordering: the stipend posts AT
	# the seventh stamp, i.e. immediately after the first deputize).
	var crowns_before := int(tm.state.crowns)
	tm.state.add_crowns(maxi(250 - crowns_before, 0))  # top up to the data price
	var wallet_before_purchase := int(tm.state.crowns)
	var deputized: Dictionary = tm.deputize_resident()
	assert_true(deputized["ok"], "step 7: DEPUTIZE RESIDENT through the real purchase path")
	assert_eq(int(deputized["price"]), 250, "rung 1 price is the T20-tuned data value")
	assert_eq(completed.size(), 1, "orientation_completed fired EXACTLY once")
	assert_eq(int(completed[0]["stipend"]), 150, "payload carries the data/staffing.json stipend")
	assert_eq(int(tm.state.crowns), wallet_before_purchase - 250 + 150,
		"crowns moved by EXACTLY -price +stipend (net +150 at the seventh stamp)")
	assert_true(bool(tm.state.orientation["completed"]), "completed flag set")
	assert_true(bool(tm.state.orientation["stipend_claimed"]), "stipend claimed exactly once")
	assert_eq(tm.state.orientation["steps_done"], OrientationTracker.STEPS,
		"all seven steps stand in posted order")
	assert_eq(stamped.size(), 7, "seven step_done emissions, one per step")

	# The completed record posts the naming-bible lines verbatim, low-text.
	_flush(tm, ["orientation"])
	await wait_frames(2)
	assert_true(form.is_expanded(), "completion holds the record open for its beat")
	assert_lte(form.word_count(), WORD_BUDGET,
		"the completed record is low-text (<= 40 words, got %d)" % form.word_count())
	assert_eq((form.get_node("FormColumn/CompletionRecord/StampRow/StampLine") as Label).text,
		STAMP_LINE, "the DULY ORIENTED stamp posts verbatim")
	assert_eq((form.get_node("FormColumn/CompletionRecord/StipendRow/StipendLine") as Label).text,
		STIPEND_LINE, "the stipend line posts the naming-bible reward wording verbatim")
	assert_false(c.cue().visible, "the arrow class retires with the tutorial")
	# The slip state: after the 2.6 s celebration beat the record settles.
	await wait_seconds(3.2)
	assert_false(form.is_expanded(), "the completed record settles into its posted slip")
	assert_lte(form.word_count(), WORD_BUDGET, "the slip is low-text (<= 40 words)")

	# ---- the completed record never re-rewards: a real save/load round trip.
	var dir := _tmp_dir("a1_roundtrip")
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store.quit_after_save = false
	store._boot(dir, tm, NOW)
	assert_true(store.save_now(NOW + 1_000)["ok"], "the completed record files")
	var crowns_at_file := int(tm.state.crowns)

	var tm2: Variant = _make_tm()
	var re_completed: Array = []
	tm2.orientation_completed.connect(func(payload: Dictionary) -> void: re_completed.append(payload))
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW + 2_000)
	assert_true(bool(tm2.state.orientation["completed"]), "completion survives the reload")
	assert_true(bool(tm2.state.orientation["stipend_claimed"]), "the claim survives the reload")
	assert_eq(int(tm2.state.crowns), crowns_at_file, "a completed record NEVER re-rewards on load")
	assert_eq(re_completed.size(), 0, "no second orientation_completed on load")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("save.json")))
	assert_eq(int(doc["engine"]["orientation"]["steps_done"].size()), 7,
		"the filed record carries all seven stamps")


# ---------------------------------------------------------------------------
# A2 — slot-enforcement journey: refusal → earned deputy → concurrency → cease
# ---------------------------------------------------------------------------

func test_a2_slot_enforcement_journey_refusal_earned_deputize_concurrency() -> void:
	var tm: Variant = _make_tm()
	var c := await _make_concourse(tm)
	assert_eq(tm.posting_slots(), 1, "fresh save: the establishment holds ONE posting")
	assert_eq(int(tm.state.staffing["deputies"]), 0, "no deputies")

	# ---- the refusal: a second skill start is refused, verbatim, no change.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the resident's own hands take posting 1")
	var frozen_active: Dictionary = tm.state.active.duplicate(true)
	var frozen_xp: Dictionary = tm.state.skills_xp.duplicate()
	var frozen_inventory: Dictionary = tm.state.inventory.duplicate()

	var refused: Dictionary = tm.start_activity("walk_the_glow_rows")
	assert_false(refused["ok"], "the second skill start is REFUSED")
	assert_eq(str(refused["reason"]), "POSTING REFUSED", "the directive head posts verbatim")
	assert_eq(str(refused["kind"]), "posting_refused", "the §14 machine id")
	assert_eq(str(refused["content_id"]), "walk_the_glow_rows", "the payload names the request")
	assert_eq(tm.state.active.duplicate(true), frozen_active, "NO state change: slots untouched")
	assert_eq(tm.state.skills_xp, frozen_xp, "NO state change: no xp")
	assert_eq(tm.state.inventory, frozen_inventory, "NO state change: no items")
	assert_eq(tm.state.crowns, 0, "NO state change: wallet untouched")

	# The directive posts on the docket verbatim (the UI side of the refusal).
	var forage: DocketGathering = c.docket_controller("foraging")
	forage.select_content("walk_the_glow_rows")
	_flush(tm, ["activity"])
	await wait_frames(2)
	assert_true(forage.refusal_plate.visible, "the POSTING REFUSED directive plate is posted")
	assert_eq(forage.refusal_head.text, "POSTING REFUSED", "directive head verbatim in-tree")
	assert_eq(forage.refusal_serial.text, REFUSAL_SERIAL,
		"directive serial verbatim (fact + both remedies)")

	# ---- earn the deputy through the slice's own economy: gather, then sell.
	# The scrap-pile table's honest sell EV is 2.85 cr/action (balance-notes
	# §5.1); pump in 30 s bites until the whole inventory tenders >= 250
	# (deterministic for the fixed seed; ~2 min of sim on the mean curve).
	var fed := 0
	while _stack_value(tm) < 250 and fed < 900_000:
		_pump(tm, 30_000, 2_500)
		fed += 30_000
	assert_gte(_stack_value(tm), 250,
		"the posted shifts earned the deputy's price at honest sell value (%d cr)" % _stack_value(tm))
	for item_id in ["scrap_metal", "copper_wiring", "cloth_scraps"]:  # the shift keeps running — selling needs no cease
		if tm.state.item_count(item_id) > 0:
			assert_true(tm.depot_sell(item_id)["ok"], "tender the whole %s stack" % item_id)
	assert_gte(tm.state.crowns, 250, "the wallet holds the earned price")

	# ---- the real purchase path: 250 Crowns buy deputy 1 exactly.
	var wallet := int(tm.state.crowns)
	var bought: Dictionary = tm.deputize_resident()
	assert_true(bought["ok"], "DEPUTIZE RESIDENT settles through the real purchase path")
	assert_eq(int(bought["price"]), 250, "the data ladder's rung-1 price")
	assert_eq(int(bought["deputies"]), 1, "one deputy on the establishment")
	assert_eq(int(bought["posting_opened"]), 2, "a second posting opened")
	assert_eq(tm.state.crowns, wallet - 250, "EXACTLY the price tendered")
	assert_eq(tm.posting_slots(), 2, "two postings now")

	# ---- the second skill starts (posting 1 still on post), and both run
	# CONCURRENTLY.
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"],
		"the previously refused start now posts")
	_flush(tm, ["activity"])
	await wait_frames(2)
	assert_true(forage.refusal_plate.visible,
		"the directive honestly stands while the board is full again (2 of 2 assigned)")
	assert_eq(tm.occupied_postings(), 2, "both postings assigned (posting 1 never ceased)")
	var scav_xp0 := int(tm.state.skills_xp["scavenging"])
	var forage_xp0 := int(tm.state.skills_xp["foraging"])
	_pump(tm, 12_000, TICK_MS)
	assert_gt(int(tm.state.skills_xp["scavenging"]), scav_xp0, "posting 1 accrued while posting 2 ran")
	assert_gt(int(tm.state.skills_xp["foraging"]), forage_xp0, "posting 2 accrued concurrently")
	assert_true(int(tm.state.active["scavenging"].completed)
			+ int(tm.state.active["foraging"].completed) >= 6,
		"both postings executed real actions in the same window (3 s intervals)")

	# ---- cease frees the posting again (a third skill opens into it), and the
	# directive withdraws with the fact.
	tm.stop_skill("scavenging")
	assert_eq(tm.free_postings(), 1, "ceasing frees the posting immediately")
	_flush(tm, ["activity"])
	await wait_frames(2)
	assert_false(forage.refusal_plate.visible,
		"the directive withdraws the moment a posting frees (copy never outlives its fact)")
	tm.state.add_item("scrap_metal", 30)
	var third: Dictionary = tm.start_activity("smelt_scrap_ingot")
	assert_true(third["ok"], "the freed posting opens for a third skill")
	assert_eq(tm.occupied_postings(), 2, "posting 1 (re-tasked) + posting 2 assigned")


func _stack_value(tm: Variant) -> int:
	var lib := _lib()
	var total := 0
	for item_id in ["scrap_metal", "copper_wiring", "cloth_scraps"]:
		total += int(tm.state.item_count(item_id)) * lib.item(item_id).value
	return total


# ---------------------------------------------------------------------------
# A3 — icon coverage: stats glyphs, gate staircases, log subject marks, prices
# ---------------------------------------------------------------------------

func test_a3_icon_coverage_stats_gates_logs_and_prices() -> void:
	var tm: Variant = _make_tm()
	tm.state.add_item("glowshroom", 1)  # a disposal line so sell rows render
	tm.state.add_crowns(1_000)
	_flush(tm)
	var c := await _make_concourse(tm)

	# ---- (1) EVERY stats-panel stat has a glyph — structural sweep: every key
	# the engine's derived_stats posts maps to exactly one glyph class, and the
	# panel renders one of each (the mapping table is the contract; this is the
	# one documented spot-set — min/max hit share the max-hit glyph because the
	# panel posts them as one segment).
	var derived: Dictionary = tm.combat.derived_stats(tm.state)
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol := c.docket_controller("wasteland_patrol") as DocketPatrol
	for stat_key in derived.keys():
		assert_true(STAT_GLYPHS.has(stat_key),
			"stat '%s' resolves a glyph class (every posted stat is named)" % stat_key)
	var rendered_glyphs := {}
	for stat_key in derived.keys():
		var glyph_id: String = STAT_GLYPHS[stat_key]
		if not rendered_glyphs.has(glyph_id):
			rendered_glyphs[glyph_id] = true
			assert_eq(_glyph_count(patrol.stats_line, glyph_id), 1,
				"the derived-stats panel renders the '%s' glyph beside its number" % glyph_id)
	assert_eq(rendered_glyphs.size(), 5, "five distinct stat glyphs on the panel (min/max hit share)")

	# ---- (2) gate plates carry the staircase — EXHAUSTIVE sweep of every
	# locked card on all four workshop dockets + every locked fauna card, the
	# expected lock count derived from the content data (never a hand literal).
	var lib: ContentLibrary = tm.engine.lib
	var expected_locked := 0
	for dept in SKILL_DEPTS:
		for content_id in lib.activities:
			var a: ActivityDef = lib.activities[content_id]
			if a.skill == dept and a.level_gate > 1:
				expected_locked += 1
		for content_id in lib.recipes:
			var r: RecipeDef = lib.recipes[content_id]
			if r.skill == dept and r.level_gate > 1:
				expected_locked += 1
	var locked_total := 0
	for dept in SKILL_DEPTS:
		c.select_department(dept, true)
		await wait_frames(2)
		var docket: DocketSkill = c.docket_controller(dept)
		for content_id in (docket.get("_cards") as Dictionary):
			var card: DocketSkill.Card = docket.get("_cards")[content_id]
			if not card.gate_plate.visible:
				continue
			locked_total += 1
			assert_string_contains(card.gate_text.text, "CLEARANCE", "%s gate names its grade" % content_id)
			assert_eq(_glyph_count(card.gate_plate, "clearance_step"), 1,
				"%s: the locked gate carries the clearance staircase (never a padlock)" % content_id)
	assert_eq(locked_total, expected_locked,
		"every data-locked workshop card posted a gate plate (%d of %d)" % [locked_total, expected_locked])

	c.select_department("wasteland_patrol", true)  # re-mount the patrol docket
	await wait_frames(2)
	var fauna_expected := 0
	var fauna_locked := 0
	for monster_id in lib.monsters:
		if (lib.monsters[monster_id] as MonsterDef).level_gate > 1:
			fauna_expected += 1
	for monster_id in (patrol.get("_cards") as Dictionary):
		var fauna: DocketPatrol.FaunaCard = patrol.get("_cards")[monster_id]
		if not fauna.gate_plate.visible:
			continue
		fauna_locked += 1
		assert_eq(_glyph_count(fauna.gate_plate, "clearance_step"), 1,
			"%s: the fauna gate carries the staircase" % monster_id)
	assert_eq(fauna_locked, fauna_expected,
		"every clearance-gated fauna card posted a gate plate (%d)" % fauna_locked)

	# ---- (3) log lines carry their subject marks — a real shift + a real fight.
	c.select_department("scavenging", true)
	await wait_frames(2)
	var gather: DocketGathering = c.docket_controller("scavenging")
	(gather.get("_cards")["sort_scrap_pile"].button as Button).pressed.emit()
	_pump(tm, 9_500, TICK_MS)
	await wait_frames(1)
	var drop_lines_iconed := 0
	for i in gather.log.item_count:
		var line := gather.log.get_item_text(i)
		if (" +" in line) and gather.log.get_item_icon(i) != null:
			drop_lines_iconed += 1
	assert_gt(drop_lines_iconed, 0, "stamped drop lines carry the item's mark")

	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	(patrol.get("_cards")["junkyard_roach"].button as Button).pressed.emit()
	_pump(tm, 9_000, 2_500)
	await wait_frames(1)
	var subject_iconed := 0
	for i in patrol.log.item_count:
		if patrol.log.get_item_icon(i) != null:
			subject_iconed += 1
	assert_gt(subject_iconed, 0, "battle-log lines carry their subject's mark")
	tm.stop_combat()
	tm.stop_skill("scavenging")

	# ---- (4) prices carry the crown mark — EXHAUSTIVE sweep of every Depot
	# stock + disposal row, plus the Personnel purchase line.
	c.select_department("requisition_depot", true)
	await wait_frames(2)
	var depot := c.docket_controller("requisition_depot") as DocketDepot
	var buy_rows := 0
	for row in depot.stock_box.get_children():
		if row.name.begins_with("BuyRow_"):
			buy_rows += 1
			assert_eq(_glyph_count(row, "crowns"), 1,
				"%s posts the crown mark beside its price" % row.name)
	var sell_rows := 0
	for row in depot.sell_box.get_children():
		if row.name.begins_with("SellRow_"):
			sell_rows += 1
			assert_eq(_glyph_count(row, "crowns"), 1,
				"%s posts the crown mark beside its tender" % row.name)
	assert_gt(buy_rows, 5, "the whole stock ledger swept (%d rows)" % buy_rows)
	assert_gte(sell_rows, 1, "disposal rows swept")
	assert_eq(_glyph_count(depot.find_child("BuyRow_scrap_metal", true, false), "clearance_step"), 1,
		"the gated stock line carries the staircase beside its grade")

	c.select_department("personnel", true)
	await wait_frames(2)
	var personnel: DocketPersonnel = c.docket_controller("personnel")
	assert_eq(_glyph_count(personnel.purchase_flow, "crowns"), 1,
		"the DEPUTIZE RESIDENT price carries the crown mark")
	assert_true(personnel.deputize_button.icon != null
		and personnel.deputize_button.icon.resource_path.ends_with("/btn_deputize.svg"),
		"the purchase button carries its verb glyph WITH the word")
	assert_gte(_glyph_count(personnel.board_box, "deputy_badge_outline"), 1,
		"AVAILABLE rows carry the outline badge (the state-pair fill)")
	assert_gte(_glyph_count(personnel.crowns_read.get_parent().get_parent(), "crowns"), 1,
		"the personnel wallet posts the crown mark")


# ---------------------------------------------------------------------------
# A4 — migration journey: a v1 record meets the posting board
# ---------------------------------------------------------------------------

func test_a4_migration_journey_v1_record_enforced_with_notice() -> void:
	var dir := _tmp_dir("a4_v1")
	# Play a run-1-shaped twin: three running skills, staggered (scavenging
	# oldest, foraging middle, cooking newest), then degrade the filed record
	# to the honest v1 shape (save_version 1, no staffing/orientation).
	var tm1: Variant = _make_tm()
	tm1.engine.ensure_staffing(tm1.state)
	tm1.state.staffing["deputies"] = 4  # run-1 rules: everything ran at once
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 10_000, 1_000)
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"])
	_pump(tm1, 10_000, 1_000)
	tm1.state.add_item("duskcorn", 10_000)
	assert_true(tm1.start_activity("grind_mandatory_grits")["ok"])
	_pump(tm1, 10_000, 1_000)
	var store1: Variant = SaveStoreScript.new()
	autofree(store1)
	store1.quit_after_save = false
	store1._boot(dir, tm1, NOW)
	assert_true(store1.save_now(NOW)["ok"], "the record files (v2)")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["save_version"] = 1
	doc["engine"].erase("staffing")
	doc["engine"].erase("orientation")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()

	# ---- load: migration + enforcement + the honest notice, at a ZERO gap.
	var tm2: Variant = _make_tm()
	var mail: Array = []
	tm2.mail_call_ready.connect(func(payload: Dictionary) -> void: mail.append(payload))
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2.quit_after_save = false
	store2._boot(dir, tm2, NOW)  # same wall moment: the notice is the point

	assert_eq(int(tm2.state.staffing.get("deputies", -1)), 0, "the v1 player gains 0 deputies")
	assert_eq(tm2.posting_slots(), 1, "the establishment is one posting (the resident's hands)")
	assert_eq(tm2.state.active.keys(), ["cooking"], "only the MOST-RECENTLY-STARTED posting survives")
	var suspended: Dictionary = tm2.state.staffing.get("suspended", {})
	assert_eq(suspended.keys().size(), 2, "the two older postings park, never drop")
	for skill_id in ["scavenging", "foraging"]:
		var parked: Dictionary = suspended[skill_id]
		assert_eq(str(parked["content_id"]), "sort_scrap_pile" if skill_id == "scavenging" else "walk_the_glow_rows",
			"%s keeps its posted selection" % skill_id)
		assert_true(int(parked["completed"]) >= 1, "%s keeps its completed count" % skill_id)
		assert_true(parked.has("rng_state"), "%s keeps its RNG position" % skill_id)

	# The honest suspension notice rides the MAIL CALL (posted at zero gap).
	assert_eq(mail.size(), 1, "the MAIL CALL posted once for the migration")
	var staffing: Dictionary = mail[0].get("staffing", {})
	assert_eq(str(staffing.get("notice", "")), SUSPENDED_NOTICE,
		"the suspension notice posts verbatim")
	assert_eq((staffing.get("suspended", []) as Array).size(), 2, "the notice names both parked postings")
	var reasons: Array = []
	for stop in mail[0].get("stopped", []):
		reasons.append(str((stop as Dictionary).get("reason", "")))
	assert_eq(reasons.count("posting_suspended"), 2, "one stopped line per suspended posting")

	# ---- slots are ENFORCED on the migrated record: a further start refuses.
	tm2.state.add_item("scrap_metal", 30)
	var refused: Dictionary = tm2.start_activity("smelt_scrap_ingot")
	assert_false(refused["ok"], "a new posting on the one-posting establishment REFUSES")
	assert_eq(str(refused["kind"]), "posting_refused", "the refusal is the §14 kind")
	assert_eq(tm2.state.active.keys(), ["cooking"], "the refusal changed nothing")

	# ---- resume: cease the survivor, re-post a parked skill — it clears.
	tm2.stop_skill("cooking")
	var reposted: Dictionary = tm2.start_activity("walk_the_glow_rows")
	assert_true(reposted["ok"], "a parked skill re-posts into the freed posting")
	assert_false(tm2.state.staffing["suspended"].has("foraging"),
		"the re-post clears its parked entry (remembered, not reserved)")
	assert_true(tm2.state.staffing["suspended"].has("scavenging"),
		"the untouched park stands until ITS skill re-posts")

	# ---- the orientation namespace back-fills exactly its lifetime evidence
	# (the twin gathered, cleared grades, and cooked — but never sold, fought,
	# or deputized).
	for step_id in ["work_shift", "earn_clearance", "process_product", "provision_patrol"]:
		assert_true(_done(tm2, step_id), "lifetime evidence stamps %s on first evaluation" % step_id)
	for step_id in ["file_crowns_claim", "clear_nuisance", "deputize_resident"]:
		assert_false(_done(tm2, step_id), "%s honestly stays open (no evidence in the record)" % step_id)

	# ---- the record re-files as v2 with the staffing namespace intact.
	assert_true(store2.save_now(NOW + 1_000)["ok"], "the migrated record re-files")
	var redoc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(redoc["save_version"]), 2, "the re-filed record is v2")
	assert_eq(int(redoc["engine"]["staffing"]["deputies"]), 0, "deputies persisted")
	assert_true(redoc["engine"]["staffing"]["suspended"].has("scavenging"), "the standing park persisted")
