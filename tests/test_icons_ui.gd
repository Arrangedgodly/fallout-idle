extends GutTest
## tests/test_icons_ui.gd — T19 inline-icon usage (Privacy/Assets lane).
##
## The icon-grammar contract (design-brief addendum "Icon grammar additions",
## ids from naming-bible §14) is binding on the SHIPPED UI, not just the SVG
## files: a stat glyph renders wherever its stat's number posts, the clearance
## staircase marks gate plates (never a padlock), item icons ride yield and
## claim lines, the Crowns mark sits beside every Depot price, verb-echo
## glyphs ride the patrol button WITH the word, and log stamps carry their
## subject's mark at small size. These tests instantiate the real concourse
## on a real TickManager twin and assert TextureRects are actually present
## beside the numbers (probe_icons.gd proves the SVG set; these prove the
## wiring). Plus the T19 no-collapse pin: inline icons are fixed-min-size
## TextureRects in flows/beside EXPAND_FILL labels — assert at 200% font
## scale, with an engaged patrol (the icon-densest state), that no label
## collapses below its longest word.


const ConcourseScene := preload("res://scenes/main.tscn")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED := 20260915
const DEPT_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest"]
const STAT_GLYPHS := ["stat_condition", "stat_accuracy", "stat_evade",
	"stat_max_hit", "stat_interval"]


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (icon tests run on live data)")
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
	c.auto_reveal = false  # T33 seam: this suite pins pre-deep-link shell behavior
	c.bind_engines(tm)
	await wait_frames(2)
	return c


## Icon rect whose texture resource path ends with the given glyph id.
func _is_glyph(node: Node, glyph_id: String) -> bool:
	if not node is TextureRect:
		return false
	var t: Texture2D = (node as TextureRect).texture
	return t != null and t.resource_path.ends_with("/%s.svg" % glyph_id)


func _glyph_count(root_node: Node, glyph_id: String) -> int:
	var n := 0
	for node in root_node.find_children("*", "TextureRect", true, false):
		if _is_glyph(node, glyph_id) and (node as TextureRect).is_visible_in_tree():
			n += 1
	return n


# ---------------------------------------------------------------------------
# 1. stats panel + fauna cards: one TextureRect per stat glyph, beside values
# ---------------------------------------------------------------------------

func test_stats_panel_renders_a_glyph_per_stat() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol := c.docket_controller("wasteland_patrol") as DocketPatrol
	assert_not_null(patrol, "patrol docket mounted")
	var housing: Control = patrol.stats_line
	for glyph in STAT_GLYPHS:
		assert_eq(_glyph_count(housing, glyph), 1,
			"derived-stats panel renders exactly one '%s' glyph (stat glyphs name exactly their stat)" % glyph)
	# The joined honest-math serial is unchanged by the flow restructure.
	assert_eq(patrol.stats_text(),
		"ACCURACY 30 · EVADE 10 · MAX HIT 1-4 · SWING EVERY 3.0 S · CONDITION 100",
		"bare-chassis derived stats unchanged (honest math)")


func test_fauna_cards_renders_stat_glyphs_and_claim_icons() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol := c.docket_controller("wasteland_patrol") as DocketPatrol
	var cards: Dictionary = patrol.get("_cards")
	var litter: DocketPatrol.FaunaCard = cards["junkyard_roach"]
	for glyph in STAT_GLYPHS:
		assert_gte(_glyph_count(litter.stats_line, glyph), 1,
			"fauna posting carries the '%s' glyph beside its stat number" % glyph)
	# Claim line: one item icon per drop-table entry (junkyard_roach table has
	# two entries: bugmeat + tattercloth).
	var item_icons := 0
	for node in litter.drops_line.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture != null:
			item_icons += 1
	assert_eq(item_icons, 2, "claim line carries one item icon per table entry")
	# Locked fauna gate plate carries the staircase, never a padlock silhouette
	# (the grammar pins the class; the file set proves no padlock was authored).
	var boss: DocketPatrol.FaunaCard = cards["sewer_landlord"]
	assert_true(boss.gate_plate.visible, "boss gate plate visible at level 1")
	assert_eq(_glyph_count(boss.gate_plate, "clearance_step"), 1,
		"locked fauna gate carries the clearance staircase glyph")


# ---------------------------------------------------------------------------
# 2. workshop dockets: yield icons, interval glyph, gate staircase, log icons
# ---------------------------------------------------------------------------

func test_gathering_yields_and_gates_carry_icons() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("scavenging", true)
	await wait_frames(2)
	var docket := c.docket_controller("scavenging") as DocketGathering
	var cards: Dictionary = docket.get("_cards")
	var open: DocketSkill.Card = cards["sort_scrap_pile"]
	# Yield line: item icon per drop-table entry (3 entries on the first tier).
	var yield_icons := 0
	for node in open.yields_line.find_children("*", "TextureRect", true, false):
		if (node as TextureRect).texture != null:
			yield_icons += 1
	assert_eq(yield_icons, 3, "yield line carries one item icon per drop entry")
	# Interval stat glyph rides the rate line beside the interval number.
	assert_eq(_glyph_count(open.rate_line, "stat_interval"), 1,
		"rate line carries the interval glyph before its mono number")
	# Locked tier gate plate carries the staircase.
	var locked: DocketSkill.Card = cards["strip_wreck"]
	assert_true(locked.gate_plate.visible, "locked tier posts its gate plate")
	assert_eq(_glyph_count(locked.gate_plate, "clearance_step"), 1,
		"locked tier gate carries the clearance staircase glyph")

	# Drop lines: stamped deltas carry the item's mark at 18 px (ItemList
	# fixed icon size) — run the shift, then inspect the log's item icons.
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 6_500)
	await wait_frames(1)
	var stamped_with_icon := 0
	for i in docket.log.item_count:
		if "SCRAPNEL +" in docket.log.get_item_text(i) \
				or "COPPER SNARL +" in docket.log.get_item_text(i) \
				or "TATTERCLOTH +" in docket.log.get_item_text(i):
			if docket.log.get_item_icon(i) != null:
				stamped_with_icon += 1
	assert_gt(stamped_with_icon, 0, "drop delta lines carry the item's icon")
	# The clearance fanfare carries the staircase glyph.
	var clearance_with_icon := false
	for i in docket.log.item_count:
		if "CLEARANCE" in docket.log.get_item_text(i) and docket.log.get_item_icon(i) != null:
			clearance_with_icon = true
	assert_true(clearance_with_icon, "clearance stamps carry the staircase glyph")


# ---------------------------------------------------------------------------
# 3. Depot: Crowns mark beside every price; gated row staircase; ledger icons
# ---------------------------------------------------------------------------

func test_depot_prices_carry_crowns_mark() -> void:
	var tm: Variant = _make_tm(SEED)
	tm.state.add_item("glowshroom", 1)
	tm.state.add_crowns(1_000)
	_flush(tm)
	var c := await _make_concourse(tm)
	c.select_department("requisition_depot", true)
	await wait_frames(2)
	var depot := c.docket_controller("requisition_depot") as DocketDepot
	# Every stock (buy) row carries the Crowns mark beside the price line.
	var stock_rows := 0
	for row in depot.stock_box.get_children():
		if row.name.begins_with("BuyRow_"):
			stock_rows += 1
			assert_eq(_glyph_count(row, "crowns"), 1,
				"stock row %s posts the Crowns mark beside its price" % row.name)
	assert_gt(stock_rows, 0, "stock rows rendered")
	# Every disposal (sell) row carries it too — T32: the disposal board is
	# its own tab now, so post the SELL tab to sweep it (the glyph discipline
	# is unchanged; the rows simply hide with the BUY tab).
	depot.select_tab(DocketDepot.TAB_SELL)
	await wait_frames(1)
	var sell_rows := 0
	for row in depot.sell_box.get_children():
		if row.name.begins_with("SellRow_"):
			sell_rows += 1
			assert_eq(_glyph_count(row, "crowns"), 1,
				"disposal row %s posts the Crowns mark beside the tender" % row.name)
	assert_gt(sell_rows, 0, "disposal rows rendered")
	# Back to the stock counter for the gated row + the ledger-stamp presses.
	depot.select_tab(DocketDepot.TAB_BUY)
	await wait_frames(1)
	# Gated stock row: staircase on the clearance plate.
	var gated_row: Control = depot.find_child("BuyRow_scrap_metal", true, false)
	assert_not_null(gated_row, "gated stock line rendered")
	assert_eq(_glyph_count(gated_row, "clearance_step"), 1,
		"gated stock line carries the clearance staircase glyph")
	# Ledger stamps: requisitions carry the item mark, tenders the Crowns mark.
	(depot.find_child("Buy1_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	var req_iconed := false
	for i in depot.log.item_count:
		if "REQUISITIONED" in depot.log.get_item_text(i) and depot.log.get_item_icon(i) != null:
			req_iconed = true
	assert_true(req_iconed, "requisition stamps carry the item's icon")
	(depot.find_child("Sell1_glowshroom", true, false) as Button).pressed.emit()
	await wait_frames(1)
	var tender_iconed := false
	for i in depot.log.item_count:
		if "TENDERED" in depot.log.get_item_text(i) and depot.log.get_item_icon(i) != null:
			tender_iconed = true
	assert_true(tender_iconed, "tender stamps carry the Crowns mark")


# ---------------------------------------------------------------------------
# 4. patrol button verb glyphs + battle-log subject marks + gear serials
# ---------------------------------------------------------------------------

func test_patrol_button_and_log_carry_glyphs() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	var patrol := c.docket_controller("wasteland_patrol") as DocketPatrol
	var begin := c.begin_button_for("wasteland_patrol")

	# Verb echo: icon + label TOGETHER (never wordless buttons).
	assert_eq(begin.text, "ENGAGE PATROL", "engage label intact")
	assert_not_null(begin.icon, "idle primary carries the ENGAGE verb glyph")
	assert_true(begin.icon.resource_path.ends_with("/btn_engage.svg"),
		"idle primary carries btn_engage (double chevron forward)")

	(patrol.get("_cards").get("junkyard_roach").button as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(begin.text, "WITHDRAW PATROL", "withdraw label intact")
	assert_true(begin.icon.resource_path.ends_with("/btn_withdraw.svg"),
		"fighting primary carries btn_withdraw (return arrow)")

	# Gauge reads carry the condition dial beside the numbers.
	var board: Control = patrol.p_read.get_parent()
	assert_eq(_glyph_count(board, "stat_condition"), 1,
		"resident gauge read carries the condition glyph")

	# Battle-log subject marks at 18 px: the fauna's swings wear its mark, the
	# resident's wear the condition dial.
	_pump(tm, 9_000)
	await wait_frames(1)
	var resident_lines := 0
	var fauna_lines := 0
	for i in patrol.log.item_count:
		var t := patrol.log.get_item_text(i)
		var icon := patrol.log.get_item_icon(i)
		if icon == null:
			continue
		if t.begins_with("RESIDENT »"):
			resident_lines += 1
		elif "» RESIDENT" in t:
			fauna_lines += 1
	assert_gt(fauna_lines, 0, "fauna swing lines carry a subject icon")
	assert_gt(resident_lines, 0, "resident swing lines carry a subject icon")

	# Gear serials: equipping gear posts [stat glyph][bonus] segments.
	tm.state.add_item("scrap_shiv", 2)
	_flush(tm)
	c.select_department("manifest", true)
	await wait_frames(2)
	var manifest := c.docket_controller("manifest") as DocketManifest
	assert_true(manifest.select_line_for("scrap_shiv"))
	manifest.equip_button.pressed.emit()
	await wait_frames(1)
	assert_eq(_glyph_count(manifest.weapon_serial, "stat_interval") +
		_glyph_count(manifest.weapon_serial, "stat_accuracy") +
		_glyph_count(manifest.weapon_serial, "stat_max_hit") +
		_glyph_count(manifest.weapon_serial, "stat_evade") +
		_glyph_count(manifest.weapon_serial, "stat_condition"), 3,
		"weapon serial carries one glyph per stat it posts (shiv: interval/acc/max hit)")
	assert_eq(manifest.weapon_serial_text(), "SWING 2.6 S · ACC +10 · MAX HIT +4",
		"gear serial text unchanged by the glyph restructure")


# ---------------------------------------------------------------------------
# 5. mail call: skill + combat lines carry their marks (items already did)
# ---------------------------------------------------------------------------

func test_mail_call_lines_carry_icons() -> void:
	var tm: Variant = _make_tm(SEED)
	var c := await _make_concourse(tm)
	c.mail_call.present({"elapsed_ms": 1_800_000,
		"skills_xp": {"scavenging": 120}, "items": {"scrap_metal": 3},
		"levels": {}, "actions": {"scavenging": 12},
		"combat": {"kills": 2, "monster_id": "junkyard_roach", "outcome": "victory"},
		"stopped": []}, _lib())
	await wait_frames(1)
	var body := c.mail_call.body_box
	assert_eq(_glyph_count(body, "scavenging"), 1,
		"per-skill gain line carries the department's mark")
	assert_eq(_glyph_count(body, "junkyard_roach"), 1,
		"patrol kill line carries the engaged fauna's mark")
	assert_eq(_glyph_count(body, "scrap_metal"), 1,
		"item gain line carries the item's mark")
	c.mail_call.acknowledge()


# ---------------------------------------------------------------------------
# 6. no-collapse pin with icons present at 200% (engaged patrol = densest)
# ---------------------------------------------------------------------------

func test_no_label_collapses_below_its_longest_word_with_icons_at_200() -> void:
	var tm: Variant = _make_tm(SEED)
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(1_000)
	_flush(tm)
	var c := await _make_concourse(tm)
	tm.start_activity("sort_scrap_pile")
	# The icon-densest state: an engaged patrol stamps iconed log lines and
	# lights the verb-echo button glyph.
	c.select_department("wasteland_patrol", true)
	await wait_frames(2)
	(c.docket_controller("wasteland_patrol").get("_cards")
		.get("junkyard_roach").button as Button).pressed.emit()
	_pump(tm, 9_000)
	await wait_frames(1)
	var icon_total := 0
	for id in DEPT_IDS:
		c.select_department(id, true)
		await wait_frames(2)
		for node in c.docket_for(id).find_children("*", "TextureRect", true, false):
			if (node as TextureRect).is_visible_in_tree() \
					and (node as TextureRect).texture != null:
				icon_total += 1
	assert_gt(icon_total, 40, "inline icons are present across the dockets (got %d)" % icon_total)

	c.font_slider.value = 2.0
	await wait_frames(3)
	for id in DEPT_IDS:
		c.select_department(id, true)
		await wait_frames(2)
		_assert_no_collapsed_labels(c.docket_for(id), "%s @200%% with icons" % id, 4)
	tm.stop_skill("scavenging")
	c.font_slider.value = 0.0


## Shared collapse assertion (test_a11y.gd's guard, re-pinned here with the
## T19 inline icons mounted: icons are fixed-min-size TextureRects, so a
## wrapped serial beside one still owes its longest word its width).
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
