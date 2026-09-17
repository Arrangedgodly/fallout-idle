extends GutTest
## tests/test_staffing.gd — T17 personnel engine + posting board validation
## (Architecture lane, Iron Man; Hulk's resilience lens on the migration).
##
## Covers the T17 acceptance matrix headless, against LIVE content:
##   (a) slot refusal — starting any activity category (gathering ×2,
##       processing ×2) or engaging the patrol with no free posting is
##       refused: NO state change, kind "posting_refused", payload carries
##       the requested content id (naming-bible §14 contract);
##   (b) posting lifecycle — ceasing frees immediately; patrol withdraw,
##       death and offline recall end the patrol's posting; re-engage while
##       fighting switches within the SAME posting (no refusal);
##   (c) purchase flow — the DEPUTIZE RESIDENT ladder reads data/staffing.json
##       (never hardcoded), refuses without funds in the Depot's voice, tops
##       out at 4 deputies = 5 postings;
##   (d) migration drill — a real v1 save (3 running skills) migrates to v2:
##       deputies 0, the MOST-RECENTLY-STARTED posting stays active, the rest
##       park in staffing.suspended with full slot state, and the MAIL CALL
##       carries "POSTINGS SUSPENDED — PERSONNEL SHORTAGE" + stopped lines
##       (posted even at a zero offline gap);
##   (e) offline respects postings — after the migration only the surviving
##       posting accrues; suspended selections accrue nothing;
##   (f) UI wiring — the PERSONNEL D-08 plate + posting board render engine
##       truth (ASSIGNED/AVAILABLE rows, badge fill state pair), the POSTING
##       REFUSED directive posts VERBATIM and withdraws when a posting frees,
##       the purchase button walks the ladder, and digit 8 is the hotkey.
##
## Determinism: bare TickManager twins booted with explicit seeds, never in
## the tree (advance_wall_ms is the only clock input) — test_engine.gd's
## discipline. The SaveStore twins use injected temp dirs (test_save.gd's).

const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")

const SEED := 20260917
const NOW := 1_768_000_000_000

const REFUSAL_SERIAL := "ALL DEPUTIES ARE ASSIGNED. CEASE A POSTING, OR DEPUTIZE ANOTHER RESIDENT AT THE PERSONNEL PLATE. EITHER REMEDY IS CHEERFULLY SUPPORTED."


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (staffing tests run on live data)")
	return result.library


func _make_tm(seed: int = SEED) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


func _pump(tm: Variant, total_ms: int, chunk_ms := 2_500) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _staff(tm: Variant, deputies: int) -> void:
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = deputies


func _tmp_dir(label: String) -> String:
	var dir := OS.get_user_data_dir().path_join("t17_staffing/%s_%d" % [label, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


# ---------------------------------------------------------------------------
# (a) slot refusal — every category, no state change
# ---------------------------------------------------------------------------

func test_refusal_kind_matches_naming_bible_machine_id() -> void:
	assert_eq(ActivityEngine.REFUSAL_KIND, "posting_refused",
		"refusal kind string is the §14 machine id")
	assert_eq(ActivityEngine.COMBAT_FIGHTING_PHASE, CombatSession.PHASE_FIGHTING,
		"the engine's combat-phase literal equals CombatSession.PHASE_FIGHTING (parse-cycle pin)")


func test_slot_refusal_each_category_no_state_change() -> void:
	var tm: Variant = _make_tm()
	assert_eq(tm.posting_slots(), 1, "fresh game: one posting (the resident's own hands)")
	assert_eq(tm.free_postings(), 1, "the posting is free")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "first posting starts")
	assert_eq(tm.occupied_postings(), 1, "one posting occupied")
	assert_eq(tm.free_postings(), 0, "the board is full")

	# Gathering #2, processing ×2 — all refused with the same kind, no change.
	for content_id in ["walk_the_glow_rows", "smelt_scrap_ingot", "grind_mandatory_grits"]:
		var r: Dictionary = tm.start_activity(content_id)
		assert_false(r["ok"], "%s refused with a full board" % content_id)
		assert_eq(str(r.get("kind", "")), "posting_refused", "%s refusal kind" % content_id)
		assert_eq(str(r.get("content_id", "")), content_id, "%s payload carries the requested id" % content_id)
		assert_eq(tm.state.active.keys(), ["scavenging"],
			"%s refusal changed no activity state" % content_id)

	# Combat engage — identical directive (the patrol holds a posting too).
	var c: Dictionary = tm.engage_monster("junkyard_roach")
	assert_false(c["ok"], "engage refused with a full board")
	assert_eq(str(c.get("kind", "")), "posting_refused", "engage refusal kind")
	assert_eq(str(c.get("content_id", "")), "junkyard_roach", "engage payload carries the monster id")
	assert_eq(str(tm.state.combat["phase"]), "idle", "refused engage leaves combat idle")

	# Unknown content refuses BEFORE the posting math (no phantom occupation).
	var unknown: Dictionary = tm.start_activity("not_a_real_activity")
	assert_false(unknown["ok"], "unknown content still refuses")

	# Switching the SAME skill keeps its posting (replace, not open).
	tm.engine.grant_xp(tm.state, "scavenging", 10_000)  # opens drain_the_sump (gate 10)
	var switched: Dictionary = tm.start_activity("drain_the_sump")
	assert_true(switched["ok"], "switching the skill's own slot reuses its posting: %s" % str(switched))
	assert_eq(tm.occupied_postings(), 1, "still exactly one posting held")


func test_cease_frees_slot_immediately() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	assert_false(tm.start_activity("walk_the_glow_rows")["ok"], "refused while full")
	tm.stop_skill("scavenging")
	assert_eq(tm.free_postings(), 1, "ceasing frees the posting immediately")
	assert_true(tm.start_activity("walk_the_glow_rows")["ok"], "the freed posting opens")


func test_patrol_occupies_withdraw_frees() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the patrol holds the posting")
	assert_eq(tm.occupied_postings(), 1, "an engaged patrol occupies one posting")
	assert_false(tm.start_activity("sort_scrap_pile")["ok"], "no second posting without a deputy")
	tm.stop_combat()
	assert_eq(tm.free_postings(), 1, "withdraw frees the posting")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the freed posting opens for a skill")
	# Switching fauna mid-fight stays inside the same posting (one posting,
	# no refusal — the switch never opens a second).
	tm.stop_skill("scavenging")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the patrol re-takes the posting")
	var switch: Dictionary = tm.engage_monster("fizzard")
	assert_false(switch["ok"], "Fizzard is clearance-gated (gate fires before postings)")
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # clearance 14
	var switched: Dictionary = tm.engage_monster("fizzard")
	assert_true(switched["ok"], "re-engaging while fighting switches within the posting")
	assert_eq(tm.occupied_postings(), 1, "still one posting (no double count)")


func test_death_ends_the_patrol_posting() -> void:
	var tm: Variant = _make_tm()
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # boss gate; zero food, zero gear
	assert_true(tm.engage_monster("sewer_landlord")["ok"], "boss engages (one posting)")
	assert_false(tm.start_activity("sort_scrap_pile")["ok"], "no free posting while fighting")
	_pump(tm, 400_000)
	assert_eq(str(tm.state.combat["phase"]), "dead", "the under-geared patrol dies")
	assert_eq(tm.free_postings(), 1, "death ends the posting")
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "the posting opens after death")


func test_offline_recall_ends_the_patrol_posting() -> void:
	var tm: Variant = _make_tm()
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)
	assert_true(tm.engage_monster("sewer_landlord")["ok"])
	_pump(tm, 1_000)
	var payload: Dictionary = tm.apply_offline_elapsed(600_000)
	assert_eq(str(tm.state.combat["phase"]), "recalled", "food-less offline fight recalls alive")
	assert_eq(tm.free_postings(), 1, "recall ends the posting")
	assert_false(payload.has("staffing"), "recall is not a staffing suspension (it posts its own notice)")


# ---------------------------------------------------------------------------
# (c) purchase flow — prices from data, funds refusal, cap
# ---------------------------------------------------------------------------

func test_deputize_ladder_reads_data_and_refuses_without_funds() -> void:
	var tm: Variant = _make_tm()
	var lib := _lib()
	var prices := [300, 2000, 9500, 25000]
	for i in 4:
		assert_eq(lib.deputies[i].price, prices[i], "ladder rung %d price is the T27-retuned value (balance-notes §5.2/§6.4)" % i)

	# No funds: in-voice Depot refusal, no state change.
	var broke: Dictionary = tm.deputize_resident()
	assert_false(broke["ok"], "purchase refuses without funds")
	assert_true(str(broke["reason"]).contains("INSUFFICIENT CROWNS (300 REQUIRED)"),
		"refusal carries the Depot tender wording with the data price: %s" % str(broke["reason"]))
	assert_eq(int(tm.state.staffing["deputies"]), 0, "no deputy granted")
	assert_eq(tm.state.crowns, 0, "no crowns moved")

	# Partial funds still refuse; exact funds buy.
	tm.state.add_crowns(299)
	var short: Dictionary = tm.deputize_resident()
	assert_false(short["ok"], "299 of 300 crowns still refuses")
	tm.state.add_crowns(1)
	var bought: Dictionary = tm.deputize_resident()
	assert_true(bought["ok"], "exact funds purchase the first deputy")
	assert_eq(int(bought["deputies"]), 1, "result carries the new deputy count")
	assert_eq(int(bought["posting_opened"]), 2, "result names the opened posting")
	assert_eq(tm.state.crowns, 0, "the full price was tendered")
	assert_eq(tm.posting_slots(), 2, "two postings now")

	# The ladder climbs to the full establishment, then refuses politely.
	tm.state.add_crowns(2000 + 9500 + 25000)
	assert_true(tm.deputize_resident()["ok"], "second deputy")
	assert_true(tm.deputize_resident()["ok"], "third deputy")
	assert_true(tm.deputize_resident()["ok"], "fourth deputy")
	assert_eq(tm.posting_slots(), 5, "1 resident + 4 deputies = 5 postings")
	var capped: Dictionary = tm.deputize_resident()
	assert_false(capped["ok"], "the establishment refuses a fifth deputy")
	assert_true(str(capped["reason"]).contains("FULL ESTABLISHMENT"), "cap refusal is in-voice: %s" % str(capped["reason"]))
	assert_eq(tm.state.crowns, 0, "the cap refusal charged nothing")

	# All five departments run at once — the amendment's target state.
	for content_id in ["sort_scrap_pile", "walk_the_glow_rows", "smelt_scrap_ingot", "grind_mandatory_grits"]:
		assert_true(tm.start_activity(content_id)["ok"], "%s posts" % content_id)
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "the fifth posting holds the patrol")
	assert_eq(tm.occupied_postings(), 5, "five of five postings assigned")


# ---------------------------------------------------------------------------
# (d) migration drill — v1 save, 3 running skills
# ---------------------------------------------------------------------------

## Saves a real v2 record, then degrades it to a v1 shape on disk
## (save_version 1, no staffing namespace) — the honest v1 twin.
func _write_v1_save(dir: String, tm: Variant, anchor_ms: int) -> void:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store._boot(dir, tm, anchor_ms)
	assert_true(store.save_now(anchor_ms)["ok"], "v2 record filed")
	var path := dir.path_join("save.json")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(int(doc["save_version"]), 3, "fresh records are v3 (T23 objectives rides save_version 3)")
	doc["save_version"] = 1
	doc["engine"].erase("staffing")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()


func test_migration_three_skills_one_survivor_plus_notice() -> void:
	var dir := _tmp_dir("migrate3")
	var tm1: Variant = _make_tm()
	_staff(tm1, 4)
	# Staggered starts: scavenging oldest, foraging middle, cooking newest —
	# the MOST-RECENTLY-STARTED posting (cooking) must survive.
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 10_000, 1_000)
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"])
	_pump(tm1, 10_000, 1_000)
	tm1.state.add_item("duskcorn", 10_000)  # the survivor is a recipe: stock it
	assert_true(tm1.start_activity("grind_mandatory_grits")["ok"])
	_pump(tm1, 10_000, 1_000)
	var cooking_completed: int = int(tm1.state.active["cooking"].completed)
	assert_true(cooking_completed >= 1, "cooking completed actions before the save")
	tm1.state.add_crowns(500)
	var anchor := NOW
	_write_v1_save(dir, tm1, anchor)

	# Load: migration + enforcement run inside the store boot.
	var tm2: Variant = _make_tm()
	var mail: Array = []
	tm2.mail_call_ready.connect(func(payload: Dictionary) -> void: mail.append(payload))
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, anchor)  # zero offline gap — the notice must still post

	assert_eq(int(tm2.state.staffing.get("deputies", -1)), 0, "v1 player gains 0 deputies")
	assert_eq(tm2.state.active.keys(), ["cooking"], "only the most-recently-started posting survives")
	var suspended: Dictionary = tm2.state.staffing.get("suspended", {})
	assert_eq(suspended.keys().size(), 2, "the two older postings are parked, not dropped")
	assert_true(suspended.has("scavenging") and suspended.has("foraging"), "parked keys are the older skills")
	var parked: Dictionary = suspended["scavenging"]
	assert_eq(str(parked["content_id"]), "sort_scrap_pile", "parked slot keeps its selection")
	assert_true(int(parked["completed"]) >= 1, "parked slot keeps its completed count")
	assert_true(parked.has("rng_state"), "parked slot keeps its RNG position (exact continuation state)")

	# The MAIL CALL notice: posted even at a zero gap.
	assert_eq(mail.size(), 1, "mail call posted once for the migration notice")
	if mail.is_empty():
		return
	var payload: Dictionary = mail[0]
	var staffing: Dictionary = payload.get("staffing", {})
	assert_eq(str(staffing.get("notice", "")), "POSTINGS SUSPENDED — PERSONNEL SHORTAGE",
		"the notice line is the recorded decision wording")
	assert_eq((staffing.get("suspended", []) as Array).size(), 2, "the notice names both parked postings")
	var reasons: Array = []
	for stop in payload.get("stopped", []):
		reasons.append(str((stop as Dictionary).get("reason", "")))
	assert_eq(reasons.count("posting_suspended"), 2, "one stopped line per suspended posting")
	# The record re-files as v2 with the staffing namespace intact.
	assert_true(store2.save_now(NOW + 1_000)["ok"], "re-filing works after migration")
	var redoc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("save.json")))
	assert_eq(int(redoc["save_version"]), 3, "the re-filed record is v3")
	assert_eq(int(redoc["engine"]["staffing"]["deputies"]), 0, "deputies persisted")
	assert_true(redoc["engine"]["staffing"]["suspended"].has("foraging"), "parked postings persisted")


func test_migration_combat_newest_keeps_the_patrol() -> void:
	var dir := _tmp_dir("migratecombat")
	var tm1: Variant = _make_tm()
	_staff(tm1, 4)
	tm1.engine.grant_xp(tm1.state, "wasteland_combat", 8_340)
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 10_000, 1_000)
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"])
	_pump(tm1, 10_000, 1_000)
	assert_true(tm1.engage_monster("junkyard_roach")["ok"], "the patrol engages LAST (newest posting)")
	_write_v1_save(dir, tm1, NOW)

	var tm2: Variant = _make_tm()
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW)
	assert_eq(str(tm2.state.combat["phase"]), "fighting", "the newest posting (the patrol) survives")
	assert_eq(tm2.state.active.keys(), [], "both older skill postings parked")
	assert_eq((tm2.state.staffing.get("suspended", {}) as Dictionary).keys().size(), 2,
		"a suspended patrol parks nothing — its designation lives in combat")
	assert_eq(str(tm2.state.combat["monster_id"]), "junkyard_roach", "designation preserved")


# ---------------------------------------------------------------------------
# (e) offline respects postings — only the surviving posting accrues
# ---------------------------------------------------------------------------

func test_offline_accrues_only_the_active_posting_after_migration() -> void:
	var dir := _tmp_dir("offline_slots")
	var tm1: Variant = _make_tm()
	_staff(tm1, 4)
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 5_000, 1_000)
	assert_true(tm1.start_activity("walk_the_glow_rows")["ok"])
	_pump(tm1, 5_000, 1_000)
	tm1.state.add_item("duskcorn", 10_000)
	assert_true(tm1.start_activity("grind_mandatory_grits")["ok"])  # newest survivor
	_pump(tm1, 5_000, 1_000)
	var anchor := NOW - 3_600_000  # a 1 h away gap
	_write_v1_save(dir, tm1, anchor)

	var tm2: Variant = _make_tm()
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2._boot(dir, tm2, NOW)  # load applies the 1 h gap through catch-up

	var payload: Dictionary = tm2.state.last_mail_call
	assert_eq(int(payload.get("elapsed_ms", -1)), 3_600_000, "the away gap applied")
	assert_true(payload["actions"].has("cooking"), "the surviving posting accrued")
	assert_false(payload["actions"].has("scavenging"), "a remembered-but-suspended selection accrues NOTHING")
	assert_false(payload["actions"].has("foraging"), "the second suspended selection accrues NOTHING")
	assert_false(payload["skills_xp"].has("scavenging"), "no suspended xp either")
	assert_eq(int(payload["actions"].get("cooking", -1)), 1_200,
		"1 h / 3 s = 1,200 actions on the one staffed posting")
	assert_true(payload.has("staffing"), "the suspension notice rides the same mail call")


func test_suspended_posting_clears_on_repost() -> void:
	var tm: Variant = _make_tm()
	# Park a suspended entry directly (the migration writer's shape).
	tm.state.staffing["suspended"]["scavenging"] = {
		"skill_id": "scavenging", "content_id": "sort_scrap_pile", "is_recipe": false,
		"interval_ms": 3000, "anchor_ms": 0, "completed": 3,
		"rng_seed": "0", "rng_state": "0", "stream_started": false}
	var started: Dictionary = tm.start_activity("sort_scrap_pile")
	assert_true(started["ok"], "re-posting the skill works with one free posting")
	assert_false(tm.state.staffing["suspended"].has("scavenging"),
		"a fresh posting supersedes the parked entry (remembered, not reserved)")


# ---------------------------------------------------------------------------
# (f) UI wiring — posting board, refusal directive, hotkey 8
# ---------------------------------------------------------------------------

func test_personnel_board_and_refusal_directive_wiring() -> void:
	var tm: Variant = _make_tm()
	var c := ConcourseScene.instantiate() as Concourse
	assert_not_null(c)
	add_child_autofree(c)
	c.bind_engines(tm)
	await wait_frames(2)

	# The eighth plate: PERSONNEL, D-08, digit 8.
	var plates: Array[Button] = c.plate_buttons_in_order()
	assert_eq(plates.size(), 8, "eight department plates on the wall")
	assert_eq(plates[7].text, "PERSONNEL · 8", "the eighth plate posts PERSONNEL with its designation digit")
	assert_true(plates[7].tooltip_text.contains("press 8"), "the tooltip names hotkey 8")

	# Keyboard: digit 8 routes through the concourse's hotkey handler.
	c.select_department("scavenging", true)
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_8
	c._unhandled_input(ev)
	await wait_seconds(1.0)  # the bulkhead slide (bounded ~0.6 s) must settle
	assert_eq(c.active_department(), "personnel", "digit 8 selects PERSONNEL")
	var personnel: DocketPersonnel = c.docket_controller("personnel")
	assert_not_null(personnel, "personnel docket is live content")

	# Board shape: one AVAILABLE row, purchase line at the data price.
	await wait_frames(2)
	assert_eq(personnel.board_box.get_children().size(), 1, "one row for the one-posting establishment")
	var row_texts := _label_texts(personnel.board_box.get_children()[0])
	assert_true(_joined(row_texts).contains("POSTING 1 · AVAILABLE"), "row reads AVAILABLE")
	assert_true(_joined(row_texts).contains("YOUR OWN TWO HANDS"), "posting 1 is the resident's own hands")
	assert_eq(personnel.deputize_button.text, "DEPUTIZE RESIDENT · 300 CROWNS",
		"purchase button label is the naming-bible form with the data price")

	# Fill the posting: the row flips to ASSIGNED with the skill + activity.
	tm.start_activity("sort_scrap_pile")
	await wait_frames(2)
	var assigned := _joined(_label_texts(personnel.board_box.get_children()[0]))
	assert_true(assigned.contains("POSTING 1 · ASSIGNED"), "row reads ASSIGNED")
	assert_true(assigned.contains("SCAVENGING — SORT THE SCRAP PILE"), "row names skill + activity")

	# Refusal: the foraging docket posts the directive plate VERBATIM.
	var forage: DocketGathering = c.docket_controller("foraging")
	forage.select_content("walk_the_glow_rows")
	await wait_frames(2)
	assert_true(forage.refusal_plate.visible, "the POSTING REFUSED directive plate is posted")
	assert_eq(forage.refusal_head.text, "POSTING REFUSED", "directive head verbatim")
	assert_eq(forage.refusal_serial.text, REFUSAL_SERIAL, "directive serial verbatim (fact + both remedies)")
	var refusal_icon := _first_texture_id(forage.refusal_plate)
	assert_eq(refusal_icon, "deputy_badge", "the directive carries the FILLED deputy badge glyph")

	# The patrol docket posts the same directive on a refused engage.
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol: DocketPatrol = c.docket_controller("wasteland_patrol")
	patrol._engage("junkyard_roach")
	await wait_frames(2)
	assert_true(patrol.refusal_plate.visible, "the patrol docket posts the same directive")
	assert_eq(patrol.refusal_serial.text, REFUSAL_SERIAL, "patrol directive serial verbatim")

	# Cease frees: the directives withdraw with the fact.
	tm.stop_skill("scavenging")
	await wait_frames(2)
	assert_false(forage.refusal_plate.visible, "skill directive withdraws when the posting frees")
	assert_false(patrol.refusal_plate.visible, "patrol directive withdraws too")

	# Purchase through the board button: funds/no-funds, ladder, cap line.
	c.select_department("personnel", true)
	await wait_frames(2)
	tm.state.add_crowns(300)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await wait_frames(2)
	var focusables := c.focusable_controls()
	assert_true(focusables.has(personnel.deputize_button),
		"the DEPUTIZE RESIDENT button is in the tab cycle while the line is posted")
	personnel.deputize_button.pressed.emit()
	await wait_frames(2)
	assert_eq(int(tm.state.staffing["deputies"]), 1, "board button purchases the deputy")
	assert_eq(personnel.board_box.get_children().size(), 2, "two rows posted")
	tm.state.add_crowns(2000 + 9500 + 25000)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await wait_frames(2)
	for i in 3:
		personnel.deputize_button.pressed.emit()
		await wait_frames(2)
	assert_eq(personnel.board_box.get_children().size(), 5, "five rows at the full establishment")
	assert_false(personnel.purchase_plate.visible, "purchase line retires at the cap")
	assert_true(personnel.cap_line.visible, "completion line posts at the cap")
	assert_eq(c.begin_button_for("personnel").text, "ESTABLISHMENT AT FULL STRENGTH",
		"the shell's primary plate reflects the full establishment")



func _label_texts(control: Control) -> Array[String]:
	var out: Array[String] = []
	for l in control.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


func _joined(parts: Array[String]) -> String:
	return " | ".join(parts)


func _first_texture_id(control: Control) -> String:
	for tr in control.find_children("*", "TextureRect", true, false):
		var tex: Texture2D = (tr as TextureRect).texture
		if tex != null:
			return str(tex.resource_path).get_file().get_basename()
	return ""
