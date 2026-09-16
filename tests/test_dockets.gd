extends GutTest
## tests/test_dockets.gd — T10a UI wiring validation (Theme/UI lane).
##
## Instantiates the real concourse scene (scenes/main.tscn) and binds it to a
## fresh TickManager twin (never in the tree — advance_wall_ms is the only
## clock input, same discipline as test_engine.gd). Asserts that displayed
## values EQUAL engine state after signal-driven updates: gauges, gates,
## craftable counts, manifest rows, depot wallet lines, mail-call payload
## rendering. No polling of labels per frame anywhere — updates flow through
## the T6 bulk/discrete signal contract only (one test pins that by unbinding
## and proving labels freeze while the engine advances).


const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260915
const TICK_MS := 100


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (docket tests run on live data)")
	return result.library


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), seed)
	return tm


## Feed exactly `total_ms` through the public wall funnel in sub-budget chunks.
func _pump(tm: Variant, total_ms: int, chunk_ms := 500) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


## Mark a region + force flush — the harness-side twin of an engine-side
## mutation when a test seeds inventory/wallet directly through state.
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


func _cards(docket: DocketSkill) -> Dictionary:
	return docket.get("_cards")


# ---------------------------------------------------------------------------
# formatting (mono digits are load-bearing)
# ---------------------------------------------------------------------------

func test_fmt_num_grouping() -> void:
	assert_eq(SignageFmt.num(0), "0")
	assert_eq(SignageFmt.num(999), "999")
	assert_eq(SignageFmt.num(1_000), "1,000")
	assert_eq(SignageFmt.num(9_999_999), "9,999,999")
	assert_eq(SignageFmt.num(-4_205), "-4,205")


func test_fmt_duration_and_pct() -> void:
	assert_eq(SignageFmt.duration(45_000), "45S")
	assert_eq(SignageFmt.duration(180_000), "3M 00S")
	assert_eq(SignageFmt.duration(7_320_000), "2H 02M")
	assert_eq(SignageFmt.pct(70, 100), "70")
	assert_eq(SignageFmt.pct(15, 100), "15")
	assert_eq(SignageFmt.pct(1, 16), "6.3", "one decimal only when needed")
	assert_eq(SignageFmt.qty(1, 2), "×1-2")
	assert_eq(SignageFmt.qty(3, 3), "×3")


# ---------------------------------------------------------------------------
# gathering docket
# ---------------------------------------------------------------------------

func test_gathering_docket_matches_engine_state() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(1)
	var docket := c.docket_controller("scavenging") as DocketGathering
	assert_not_null(docket, "scavenging controller mounted")
	var cards := _cards(docket)
	assert_eq(cards.size(), 4, "four tier cards from data")

	# Honest rates: the tier card prints the table's exact fractions.
	var first: DocketSkill.Card = cards["sort_scrap_pile"]
	assert_true("YIELDS:" in first.yields_text(), "yields line posted")
	assert_true("SCRAPNEL 70%" in first.yields_text(), "70%% weight printed: %s" % first.yields_text())
	assert_true("+10 XP / ACTION" in first.rate_text(), "xp per action in mono")
	assert_true("3.0 S INTERVAL" in first.rate_text(), "interval in mono")

	# Start through the card button, then through the primary button.
	(first.button as Button).pressed.emit()
	assert_true(tm.state.active.has("scavenging"), "card press starts the engine slot")
	assert_true(docket.status_plate.visible, "energized status plate visible")
	assert_string_contains(docket.status_line.text, ">>", "non-color running cue")
	assert_eq(c.begin_button_for("scavenging").text, "END SHIFT", "primary retexts while running")

	_pump(tm, 6_100)
	var curve = tm.engine.lib.xp_curve(tm.engine.lib.skill("scavenging").xp_curve)
	var level: int = int(tm.state.skills_level["scavenging"])
	var into: int = int(tm.state.skills_xp["scavenging"]) - curve.total_xp_to_reach(level)
	assert_eq(docket.gauge_read.text, "CLEARANCE %02d · %s/%s XP TO NEXT" % [
		level, SignageFmt.num(into), SignageFmt.num(curve.xp_to_next(level))],
		"gauge label equals engine state exactly")
	assert_eq(docket.gauge.value, float(clampi(into, 0, curve.xp_to_next(level))), "gauge fill matches xp-into-level")

	var stamped := false
	for i in docket.log.item_count:
		if "SCRAPNEL +" in docket.log.get_item_text(i) \
				or "COPPER SNARL +" in docket.log.get_item_text(i) \
				or "TATTERCLOTH +" in docket.log.get_item_text(i):
			stamped = true
	assert_true(stamped, "drop lines stamped from the batched signal")

	# Level-up fanfare rides the immediate signal.
	assert_true(_log_has(docket, "CLEARANCE 02 EARNED"), "clearance fanfare stamped")

	(c.begin_button_for("scavenging") as Button).pressed.emit()
	assert_false(tm.state.active.has("scavenging"), "primary press stops the slot")
	assert_eq(c.begin_button_for("scavenging").text, "BEGIN SHIFT", "primary retexts when idle")
	assert_false(docket.status_plate.visible, "status plate clears")


func test_gate_locks_render_and_denial_stamps() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(1)
	var docket := c.docket_controller("scavenging") as DocketGathering
	var cards := _cards(docket)

	var locked: DocketSkill.Card = cards["strip_wreck"]
	assert_true(locked.gate_plate.visible, "locked tier posts its clearance plate")
	assert_string_contains(locked.gate_text.text, "CLEARANCE 5 REQUIRED", "required level shown")
	assert_string_contains(locked.gate_text.text, "EARNED BY WORKING THIS DEPARTMENT'S POSTED SHIFTS",
		"gate plate teaches the earning path (refinement 2, critique P2#4)")
	var open: DocketSkill.Card = cards["sort_scrap_pile"]
	assert_false(open.gate_plate.visible, "level-1 tier has no gate plate")

	(locked.button as Button).pressed.emit()
	assert_false(tm.state.active.has("scavenging"), "engine refuses the gated start")
	assert_true(_log_has(docket, "CLEARANCE 5 REQUIRED"), "denial stamped with clearance wording")

	# Elevation opens the gate: grant to exactly level 5, force the xp flush.
	tm.engine.grant_xp(tm.state, "scavenging", 425)
	_flush(tm, "xp")
	await wait_frames(1)
	assert_false(locked.gate_plate.visible, "CLEARANCE 5 opens at level 5")


func _log_has(docket: Docket, needle: String) -> bool:
	for i in docket.log.item_count:
		if needle in docket.log.get_item_text(i):
			return true
	return false


# ---------------------------------------------------------------------------
# processing docket
# ---------------------------------------------------------------------------

func test_processing_craft_consumes_and_stamps() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("junksmithing", true)
	await wait_frames(1)
	var docket := c.docket_controller("junksmithing") as DocketProcessing
	var cards := _cards(docket)
	assert_eq(cards.size(), 7, "seven recipe cards from data")

	tm.state.add_item("scrap_metal", 9)
	_flush(tm)
	await wait_frames(1)
	var smelt: DocketSkill.Card = cards["smelt_scrap_ingot"]
	assert_string_contains(smelt.yields_text(), "CRAFTABLE 3", "craftable count from live inventory: %s" % smelt.yields_text())
	assert_string_contains(smelt.yields_text(), "3 × SCRAPNEL", "inputs posted")
	assert_string_contains(smelt.yields_text(), "» 1 × ALMOST BULLION", "output posted")

	(smelt.button as Button).pressed.emit()
	assert_true(tm.state.active.has("junksmithing"), "recipe shift posted")
	_pump(tm, 17_000)  # 3 crafts at 4/8/12 s; the 16 s action finds no inputs
	assert_eq(int(tm.state.inventory.get("scrap_ingot", 0)), 3, "three ingots crafted")
	assert_eq(int(tm.state.inventory.get("scrap_metal", 0)), 0, "all scrap consumed")
	assert_eq(int(tm.state.skills_xp["junksmithing"]), 42, "14 xp per craft x3")
	assert_true(_log_has(docket, "CRAFT"), "craft stamps posted")
	assert_true(_log_has(docket, "SUPPLIES EXHAUSTED"), "dry stop stamped")
	assert_false(tm.state.active.has("junksmithing"), "engine stopped the dry recipe")

	# Posting a dry recipe refuses up front with the missing lines named.
	(smelt.button as Button).pressed.emit()
	assert_false(tm.state.active.has("junksmithing"), "no doomed slot started")
	assert_true(_log_has(docket, "NOTHING TO WORK WITH"), "dry refusal stamped")
	assert_true(_log_has(docket, "SCRAPNEL 0/3"), "shortfall line named with mono counts")


# ---------------------------------------------------------------------------
# manifest docket
# ---------------------------------------------------------------------------

func test_manifest_rows_and_equipment() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("manifest", true)
	await wait_frames(1)
	var docket := c.docket_controller("manifest") as DocketManifest

	tm.state.add_item("scrap_metal", 12)
	tm.state.add_item("scrap_shiv", 1)
	tm.state.add_item("hubcap_vest", 1)
	_flush(tm)
	await wait_frames(1)

	var rows := ""
	for i in docket.list.item_count:
		rows += docket.list.get_item_text(i) + " | "
	assert_string_contains(rows, "SCRAPNEL ×12", "mono counts on manifest rows")
	assert_string_contains(rows, "POINT OF ORDER ×1", "equipment rows present")

	# Non-gear selection leaves EQUIP disarmed.
	assert_true(docket.select_line_for("scrap_metal"))
	assert_true(docket.equip_button.disabled, "EQUIP disarmed for a resource line")

	# Weapon equip consumes the unit; the previous weapon returns on swap.
	assert_true(docket.select_line_for("scrap_shiv"))
	assert_false(docket.equip_button.disabled)
	docket.equip_button.pressed.emit()
	assert_eq(str(tm.state.combat.get("weapon", "")), "scrap_shiv", "weapon slot filled")
	assert_eq(int(tm.state.inventory.get("scrap_shiv", 0)), 0, "equipped unit left the Manifest")
	assert_string_contains(docket.weapon_name.text, "POINT OF ORDER", "slot plate names the gear")
	assert_false(docket.weapon_unequip.disabled, "UNEQUIP armed")

	# Swap to armor through its slot's unequip, then back.
	docket.weapon_unequip.pressed.emit()
	assert_eq(str(tm.state.combat.get("weapon", "")), "", "weapon slot emptied")
	assert_eq(int(tm.state.inventory.get("scrap_shiv", 0)), 1, "unit returned to Manifest")


# ---------------------------------------------------------------------------
# depot docket
# ---------------------------------------------------------------------------

func test_depot_transactions_update_wallet_and_inventory() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("requisition_depot", true)
	await wait_frames(1)
	var docket := c.docket_controller("requisition_depot") as DocketDepot

	tm.state.add_crowns(100)
	_flush(tm)
	await wait_frames(1)
	assert_eq(docket.crowns_read.text, "100", "currency plate reads the wallet")

	var buy1 := docket.find_child("Buy1_glowshroom", true, false) as Button
	assert_not_null(buy1, "BUY 1 button exists for the ungated line")
	buy1.pressed.emit()
	assert_eq(tm.state.crowns, 94, "6 Crowns tendered")
	assert_eq(int(tm.state.inventory.get("glowshroom", 0)), 1, "one unit stocked")
	assert_eq(docket.crowns_read.text, "94", "currency plate updated via signal")

	var buy_max := docket.find_child("BuyMax_glowshroom", true, false) as Button
	assert_eq(buy_max.text, "BUY ×15", "max button computes the wallet's reach (94/6)")
	buy_max.pressed.emit()
	assert_eq(tm.state.crowns, 4, "94 - 90 tendered for 15 units")
	assert_eq(int(tm.state.inventory.get("glowshroom", 0)), 16, "15 more stocked")
	assert_true(buy_max.disabled, "BUY ×0 disabled when broke")

	var sell_all := docket.find_child("SellAll_glowshroom", true, false) as Button
	sell_all.pressed.emit()
	assert_eq(tm.state.crowns, 36, "16 units x 2 Crowns buy-back")
	assert_eq(int(tm.state.inventory.get("glowshroom", 0)), 0, "stack tendered away")
	assert_false((docket.get("_sell_rows") as Dictionary).has("glowshroom"),
		"disposal line withdrawn when the stack empties")

	# Gated lines: the plate posts, the façade refuses with CLEARANCE wording.
	var gated_row := docket.find_child("BuyRow_scrap_metal", true, false)
	assert_not_null(gated_row, "gated stock line rendered")
	var gate_copy := ""
	for l in (gated_row as Control).find_children("*", "Label", true, false):
		gate_copy += (l as Label).text + " "
	assert_string_contains(gate_copy, "CLEARANCE 3 REQUIRED", "gate plate on the stock line")
	var refused: Dictionary = tm.depot_buy("scrap_metal", 1)
	assert_false(refused["ok"], "façade refuses the gated buy")
	assert_string_contains(str(refused["reason"]), "CLEARANCE 3", "refusal carries clearance wording")

	# Busted wallet refuses honestly (fresh twin: zero Crowns).
	var tm_broke: Variant = _make_tm(SEED)
	var broke: Dictionary = tm_broke.depot_buy("glowshroom", 1)
	assert_false(broke["ok"], "façade refuses when broke")
	assert_string_contains(str(broke["reason"]), "INSUFFICIENT CROWNS")


# ---------------------------------------------------------------------------
# MAIL CALL
# ---------------------------------------------------------------------------

func test_mail_call_renders_payload_and_traps_focus() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 3_000)
	var xp0: int = int(tm.state.skills_xp["scavenging"])
	tm.apply_offline_elapsed(3_600_000)  # 1 h away -> mail_call_ready
	await wait_frames(2)
	assert_true(c.mail_call.is_presenting(), "modal presents from the engine signal")
	var gained: int = int(tm.state.skills_xp["scavenging"]) - xp0
	assert_true(gained > 0, "offline gains accrued")

	var texts: Array[String] = []
	for l in c.mail_call.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_true(texts.any(func(t: String) -> bool: return t == "MAIL CALL"), "title posted")
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("AWAY 1H 00M")),
		"elapsed time posted (got %s)" % str(texts.slice(0, 3)))
	assert_true(texts.any(func(t: String) -> bool:
		return t.begins_with("SCAVENGING +%s XP" % SignageFmt.num(gained))),
		"per-skill xp line exact")
	assert_true(texts.any(func(t: String) -> bool: return t.contains("SCRAPNEL +")),
		"item gain lines posted")
	assert_eq(c.mail_call.ack_button.text, "ACKNOWLEDGE RECEIPT", "stamped acknowledgment")

	# Focus trap: the ack button holds focus while presenting.
	c.mail_call.ack_button.grab_focus()
	await wait_frames(1)
	assert_true(c.mail_call.ack_button.has_focus(), "ack button focused while presenting")

	# Lambda captures are by value in GDScript — record into a container.
	var acked: Dictionary = {}
	c.mail_call.acknowledged.connect(func(payload: Dictionary) -> void: acked["payload"] = payload)
	c.mail_call.ack_button.pressed.emit()
	assert_false(c.mail_call.is_presenting(), "acknowledge closes the modal")
	assert_eq(int((acked.get("payload", {}) as Dictionary).get("elapsed_ms", 0)), 3_600_000,
		"ack signal round-trips the payload")


func test_mail_call_renders_patrol_recall_line() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	# T7 payload extension (tests may craft payloads; shipped scenes never do).
	var payload: Dictionary = {
		"elapsed_ms": 7_200_000,
		"skills_xp": {"wasteland_combat": 8_340},
		"items": {"girderling": 6},
		"levels": {"wasteland_combat": {"from": 14, "to": 15}},
		"actions": {"wasteland_combat": 3},
		"stopped": [{"skill_id": "wasteland_combat", "content_id": "sewer_landlord",
			"reason": "patrol_recalled"}],
		"combat": {"kills": 3, "monster_id": "sewer_landlord", "outcome": "recalled",
			"notice": "PATROL RECALLED", "zone_cleared": true},
	}
	c.mail_call.present(payload, tm.engine.lib)
	await wait_frames(1)
	assert_true(c.mail_call.is_presenting())
	var texts: Array[String] = []
	for l in c.mail_call.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	assert_true(texts.any(func(t: String) -> bool: return "PATROL RECALLED" in t),
		"recall plate posted")
	assert_true(texts.any(func(t: String) -> bool: return "3 KILLS" in t),
		"offline kills posted")
	assert_true(texts.any(func(t: String) -> bool: return "ZONE CLEARED" in t),
		"offline zone clear posted")
	assert_true(texts.any(func(t: String) -> bool: return "CLEARANCE 14 » 15" in t),
		"level crossing posted")
	c.mail_call.acknowledge()


func test_mail_call_presents_cached_payload_at_bind() -> void:
	# The load's mail_call_ready can fire before the concourse exists (SaveStore
	# loads in its own _ready) — binding must present state.last_mail_call.
	var tm: Variant = _make_tm(SEED)
	tm.start_activity("sort_scrap_pile")
	tm.apply_offline_elapsed(600_000)
	var c := ConcourseScene.instantiate() as Concourse
	add_child_autofree(c)
	await wait_frames(2)  # _ready runs bind_engines() against the autoload...
	assert_false(c.mail_call.is_presenting(), "no presentation from the production autoload (fresh twin state)")
	c.bind_engines(tm)  # rebind to the twin carrying the cached payload
	await wait_frames(1)
	assert_true(c.mail_call.is_presenting(), "cached last_mail_call presented at bind")
	assert_true(int(c.mail_call.payload().get("elapsed_ms", 0)) == 600_000, "payload carried")
	c.mail_call.acknowledge()
	tm.stop_skill("scavenging")


# ---------------------------------------------------------------------------
# save notices + signal discipline
# ---------------------------------------------------------------------------

func test_save_notice_board_kinds() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	for kind in ["primary_corrupt_backup_loaded", "all_saves_corrupt_fresh_state",
			"refused_newer_save_version", "save_write_failed"]:
		c.save_board.post(kind, {"found_save_version": 99, "supported_save_version": 1,
			"restored_from": "save.json.bak1", "reason": "disk full"})
		assert_true(c.save_board.is_posting(), "%s posts" % kind)
	c.save_board.post("not_a_real_kind", {})
	assert_true(c.save_board.kind() == "save_write_failed", "unknown kinds are ignored")

	var acked := {"kind": ""}
	c.save_board.acknowledged.connect(func(kind: String) -> void: acked["kind"] = kind)
	c.save_board.ack_button.pressed.emit()
	assert_false(c.save_board.is_posting(), "acknowledge clears the plate")
	assert_eq(acked["kind"], "save_write_failed", "ack signal carries the kind")


func test_labels_freeze_when_unbound() -> void:
	# Signal discipline: unbound dockets must not track the engine — labels
	# mutate only inside the batched/discrete signal handlers.
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(1)
	var docket := c.docket_controller("scavenging") as DocketGathering
	var cards := _cards(docket)
	(cards["sort_scrap_pile"].button as Button).pressed.emit()
	_pump(tm, 3_100)
	await wait_frames(2)
	var frozen := docket.gauge_read.text
	var frozen_inv := str(tm.state.inventory.duplicate())
	docket.unbind()
	_pump(tm, 6_100)
	await wait_frames(2)
	assert_eq(docket.gauge_read.text, frozen, "gauge frozen after unbind (no polling)")
	assert_ne(str(tm.state.inventory.duplicate()), frozen_inv, "engine advanced on")
	tm.stop_skill("scavenging")


func test_rebinding_twins_disconnects_previous_manager() -> void:
	var tm_a: Variant = _make_tm(SEED)
	var tm_b: Variant = _make_tm(SEED + 1)
	var c := await _make_concourse(tm_a)
	c.select_department("scavenging", true)
	await wait_frames(1)
	var docket := c.docket_controller("scavenging") as DocketGathering

	c.bind_engines(tm_b)
	await wait_frames(1)
	var cards := _cards(docket)
	(cards["sort_scrap_pile"].button as Button).pressed.emit()
	assert_true(tm_b.state.active.has("scavenging"), "docket follows the new twin")

	# The old twin stays untouched and its signals drive nothing.
	_pump(tm_a, 3_100)
	await wait_frames(1)
	assert_false(tm_a.state.active.has("scavenging"), "old twin never started")
	assert_eq(c.bound_tick_manager(), tm_b, "concourse reports the bound twin")
	tm_b.stop_skill("scavenging")


# ---------------------------------------------------------------------------
# committed theme artifact pin (T10a retry: the stale-.tres escape)
# ---------------------------------------------------------------------------

## Production renders from the COMMITTED assets/theme/signage_theme.tres
## (UiTheme._ready loads THEME_PATH; scenes never build the theme live). The
## T10a verifier FAIL shipped a .tres regenerated before the final builder
## edit: FormTitleEnergized was missing, so every energized card title fell
## back to the base Label (bone grotesk 16 on navy) instead of the amber
## stencil 18 on the registered amber/navy 6.96 pair — and the green suite
## could not see it. These tests pin the artifact against the builder so a
## stale .tres can never pass silently again.
const THEME_TRES_PATH := "res://assets/theme/signage_theme.tres"


func test_committed_theme_tres_matches_builder_registry() -> void:
	var tres := load(THEME_TRES_PATH) as Theme
	assert_not_null(tres, "committed theme .tres loads")
	var fresh := SignageTheme.build()

	for entry in SignageTheme.FONT_SIZE_BASES:
		var type_name: String = entry[0]
		var base_type: String = entry[1]
		var size: int = entry[2]
		assert_eq(tres.get_font_size("font_size", type_name), size,
			"%s font_size in the committed .tres matches the builder registry (0 = missing — regenerate via generate_theme.gd)" % type_name)
		if base_type != "":
			assert_eq(tres.get_type_variation_base(type_name), base_type,
				"%s registered in the .tres as a variation of %s (empty = missing — regenerate via generate_theme.gd)" % [type_name, base_type])
		if base_type == "Label":
			assert_eq(tres.get_color("font_color", type_name),
				fresh.get_color("font_color", type_name),
				"%s label ink in the .tres matches the builder" % type_name)


func test_energized_card_title_resolves_amber_stencil_18() -> void:
	# The exact escape, proven at runtime the way production reads it: a
	# Label under the committed theme with the FormTitleEnergized variation
	# must resolve the amber token at stencil 18 — not the base-Label
	# fallback (bone 16) the stale artifact served.
	var tres := load(THEME_TRES_PATH) as Theme
	assert_not_null(tres, "committed theme .tres loads")
	assert_true(tres.has_color("font_color", "FormTitleEnergized"),
		"FormTitleEnergized color exists (the stale-artifact escape)")
	assert_eq(tres.get_color("font_color", "FormTitleEnergized"),
		SignageTokens.SIGNAL_AMBER, "energized title ink is the amber token")
	assert_eq(tres.get_font_size("font_size", "FormTitleEnergized"), 18,
		"energized title size is the stencil 18")
	var fv := tres.get_font("font", "FormTitleEnergized") as FontVariation
	assert_not_null(fv, "energized title font is the tracked stencil variation")
	if fv != null:
		assert_not_null(fv.base_font, "stencil base font round-tripped through the .tres")

	# Control-level resolution: the variation alone (no explicit theme type,
	# exactly how docket card titles are styled) must draw amber stencil 18.
	var title := Label.new()
	title.theme = tres
	title.theme_type_variation = "FormTitleEnergized"
	add_child_autofree(title)
	assert_true(title.has_theme_color("font_color", "FormTitleEnergized"),
		"variation color resolvable through the control")
	assert_eq(title.get_theme_color("font_color", "FormTitleEnergized"),
		SignageTokens.SIGNAL_AMBER, "resolved title color is amber")
	assert_eq(title.get_theme_font_size("font_size", "FormTitleEnergized"), 18,
		"resolved title size is 18")
	assert_eq(title.get_theme_font_size("font_size"), 18,
		"size resolves through the variation alone")
