extends SceneTree
## tests/probe_content.gd — T2 content-schema probe (plain --script; R2
## bootstrap-smoke pattern until T12 wires GUT).
##
## Run: "$GODOT" --headless --path . -s res://tests/probe_content.gd
## Exit 0 = all checks pass; 1 = any failure (each printed to stderr).
##
## Proves the T2 acceptance criteria:
##   1. the authored content set under res://data (T5 balance content
##      replaced the golden set 2026-09-15) loads + validates (zero errors,
##      zero warnings) and hydrates TYPED classes with int-coerced fields,
##      round-tripping values against the JSON source;
##   2. a deliberately malformed record yields an actionable error
##      (record id + field + reason), via the exact production code path
##      (ContentLoader.load_all on a mutated copy under user://);
##   3. the ContentDB autoload is live at the first process frame and
##      serving typed lookups.

const DOMAIN_FILES := [
	"items.json", "skills.json", "activities.json", "recipes.json",
	"drop_tables.json", "monsters.json", "equipment.json", "shop_stock.json",
	"xp_curves.json", "staffing.json",
]
const GOLDEN_RECORD_COUNT := 83  # 21 items + 5 skills + 8 activities + 11 recipes + 13 drop tables + 5 monsters + 4 equipment + 11 shop lines + 1 curve + 4 deputy rungs (T5 set + T17 staffing)

var checks := 0
var failures: Array[String] = []
var _frame := 0


func _initialize() -> void:
	_check_golden_set()
	_check_malformed_set()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_check_autoload_wiring()
		_report_and_quit()
	return true


# -------------------------------------------------------------- golden set

func _check_golden_set() -> void:
	var result := ContentLoader.load_all()
	_check(result.ok(), "golden set validates with zero errors (got: %s)" % str(result.errors))
	_check(result.warnings.is_empty(), "golden set produces zero warnings (got: %s)" % str(result.warnings))
	if result.library == null:
		_check(false, "golden set hydrates a ContentLibrary")
		return
	var lib := result.library

	# Items — typed hydration + int coercion (JSON numbers arrive as float).
	var scrap := lib.item("scrap_metal")
	_check(scrap is ItemDef, "item('scrap_metal') hydrates an ItemDef")
	_check(scrap != null and scrap.name == "Scrapnel", "item name round-trips (T4 display name)")
	_check(scrap != null and scrap.category == "resource", "item category round-trips")
	_check(scrap != null and typeof(scrap.value) == TYPE_INT and scrap.value == 2,
		"item value is int 2 (float->int coercion, R1)")
	_check(scrap != null and scrap.heal == -1, "non-food item heal sentinel is -1")
	var stew := lib.item("radstag_stew")
	_check(stew != null and stew.is_food() and typeof(stew.heal) == TYPE_INT and stew.heal == 80,
		"food item heal is int 80 and is_food()")
	var shiv := lib.item("scrap_shiv")
	_check(shiv != null and shiv.is_equipment(), "equipment item is_equipment()")

	# Skills.
	var combat := lib.skill("wasteland_combat")
	_check(combat != null and combat.is_combat() and combat.max_level == 99 and combat.xp_curve == "standard_99",
		"combat skill kind/max_level/xp_curve round-trip")

	# Activities — the fields T6 executes.
	var sort := lib.activity("sort_scrap_pile")
	_check(sort != null and sort.skill == "scavenging" and sort.level_gate == 1,
		"activity skill + level_gate round-trip")
	_check(sort != null and typeof(sort.interval_ms) == TYPE_INT and sort.interval_ms == 3000,
		"activity interval_ms is int 3000")
	_check(sort != null and sort.xp_per_action == 10 and sort.drop_table == "scrap_pile",
		"activity xp + drop_table round-trip")

	# Recipes — nested inputs/output hydrate as typed ItemQty.
	var forge := lib.recipe("forge_scrap_shiv")
	_check(forge != null and forge.inputs.size() == 2, "recipe inputs hydrate (2 stacks)")
	_check(forge != null and forge.inputs[0].item == "scrap_ingot" and typeof(forge.inputs[0].qty) == TYPE_INT and forge.inputs[0].qty == 2,
		"recipe input stack item + int qty round-trip")
	_check(forge != null and forge.output.item == "scrap_shiv" and forge.output.qty == 1,
		"recipe output round-trips")

	# Drop tables — visible rates.
	var table := lib.drop_table("scrap_pile")
	_check(table != null and table.rolls == 1 and table.entries.size() == 3, "drop table rolls + entries hydrate")
	_check(table != null and table.entries[1].item == "copper_wiring" and typeof(table.entries[1].weight) == TYPE_INT,
		"drop entry item + int weight round-trip")
	_check(table != null and table.total_weight() == 100, "drop table total_weight() == 100 (visible-rate denominator)")

	# Monsters — combat stats.
	var boss := lib.monster("sewer_landlord")
	_check(boss != null and boss.is_boss and typeof(boss.is_boss) == TYPE_BOOL, "monster is_boss is bool true")
	_check(boss != null and typeof(boss.max_hp) == TYPE_INT and boss.max_hp == 340 and boss.min_hit <= boss.max_hit,
		"monster max_hp int 340, hit bounds ordered")
	_check(boss != null and boss.xp_reward == 1000 and boss.drop_table == "superintendents_receipts", "monster xp + drop_table round-trip")

	# Equipment — slot semantics + optional fields.
	var shiv_equip := lib.equipment_for("scrap_shiv")
	_check(shiv_equip != null and shiv_equip.is_weapon() and shiv_equip.attack_speed_ms == 2600,
		"weapon attack_speed_ms override round-trips")
	var vest := lib.equipment_for("hubcap_vest")
	_check(vest != null and vest.slot == "armor" and vest.evasion_bonus == 12 and vest.attack_speed_ms == -1,
		"armor bonuses round-trip; no attack_speed_ms override (-1)")

	# Shop stock — order, gates, ungated default.
	var stock := lib.shop_entries()
	_check(stock.size() == 11 and stock[0].item == "glowshroom" and stock[0].buy_price == 6,
		"shop stock order + buy_price round-trip")
	_check(stock[0] != null and not stock[0].is_gated(), "ungated shop line defaults")
	_check(stock[2] != null and stock[2].item == "copper_wiring" and stock[2].buy_price == 12,
		"shop stock order round-trips past the first line")
	_check(stock[2].is_gated() and stock[2].gate_skill == "scavenging" and stock[2].gate_level == 5,
		"shop gate.skill/gate.level round-trip")

	# XP curve — array length, int packing, closed-form helpers.
	var curve := lib.xp_curve("standard_99")
	_check(curve != null and curve.max_level == 99 and curve.xp_per_level.size() == 98,
		"xp curve length == max_level - 1 (98)")
	_check(curve != null and curve.xp_per_level is PackedInt64Array and curve.xp_per_level[0] == 20 and curve.xp_per_level[97] == 48542,
		"xp curve values are packed ints and round-trip (20 .. 48542)")
	_check(curve != null and curve.total_xp_to_reach(1) == 0 and curve.total_xp_to_reach(2) == 20 and curve.level_for_total_xp(20) == 2 and curve.xp_to_next(99) == 0,
		"xp curve closed-form helpers are int-exact")

	# Staffing ladder (T17) — typed hydration + the read path the engine uses.
	_check(lib.deputies.size() == 4, "staffing ladder posts exactly 4 rungs (1 + 4 = 5 postings)")
	var rung0: DeputyDef = lib.deputies[0]
	_check(rung0 != null and rung0.id == "second_deputy" and typeof(rung0.price) == TYPE_INT and rung0.price == 75,
		"first deputy rung hydrates (id + int price 75)")
	_check(lib.deputy_price_at(0) == 75 and lib.deputy_price_at(3) == 12000 and lib.deputy_price_at(4) == -1,
		"deputy_price_at() reads the ladder and returns -1 past the cap")

	# Whole-library shape.
	_check(lib.record_count() == GOLDEN_RECORD_COUNT, "library record_count() == %d" % GOLDEN_RECORD_COUNT)


# ------------------------------------------------------------ malformed set

## Copies the real golden set under user://t2_probe/<name>/ with one deliberate
## defect per fixture, then loads it through the exact production code path.
## One defect per fixture, because the loader gates cross-reference checks on
## a clean per-record pass (shape errors fail before refs are walked).
func _load_mutated_fixture(fixture: String, defect: Callable) -> ContentLoader.Result:
	var dir := DirAccess.make_dir_recursive_absolute("user://t2_probe/%s" % fixture)
	_check(dir == OK, "fixture dir created: %s" % fixture)
	for file_name in DOMAIN_FILES:
		if defect.call("skip_file", file_name, ""):
			continue
		var text := FileAccess.get_file_as_string("res://data/%s" % file_name)
		_check(text != "", "fixture source readable: %s" % file_name)
		var write := FileAccess.open("user://t2_probe/%s/%s" % [fixture, file_name], FileAccess.WRITE)
		if write == null:
			_check(false, "fixture writable: %s" % file_name)
			return null
		write.store_string(String(defect.call("text", file_name, text)))
		write.close()
	var result := ContentLoader.load_all("user://t2_probe/%s" % fixture)
	# Tidy up before asserting.
	var cleanup := DirAccess.open("user://t2_probe/%s" % fixture)
	if cleanup != null:
		for file_name in DOMAIN_FILES:
			if not defect.call("skip_file", file_name, ""):
				cleanup.remove(file_name)
		var parent := DirAccess.open("user://t2_probe")
		if parent != null:
			parent.remove(fixture)
	return result


func _check_malformed_set() -> void:
	# Defect 1 — wrong-typed field in a known record: value "lots".
	var wrong_type := _load_mutated_fixture("wrong_type", func(action: String, file_name: String, text: String) -> Variant:
		if action == "skip_file":
			return false
		if file_name != "items.json":
			return text
		var doc: Dictionary = JSON.parse_string(text)
		doc["items"][0]["value"] = "lots"
		return JSON.stringify(doc, "\t"))
	_check(wrong_type != null and not wrong_type.ok(), "wrong-typed value is rejected (ok() == false)")
	_check(wrong_type != null and wrong_type.library == null, "wrong-typed value hydrates no library")
	if wrong_type != null:
		for err in wrong_type.errors:
			print("    mutated-set error: " + err)
		_check_contains(wrong_type.errors, "items[0] (id=scrap_metal)", "wrong-typed field error names the record")
		_check_contains(wrong_type.errors, "value: must be a number, got String ('lots')", "wrong-typed field error names field + reason")

	# Defect 2 — dangling cross-reference: activity points at a drop table
	# that doesn't exist. Domain records are all shape-valid, so this proves
	# the cross-domain reference pass fires.
	var dangling := _load_mutated_fixture("dangling_ref", func(action: String, file_name: String, text: String) -> Variant:
		if action == "skip_file":
			return false
		if file_name != "activities.json":
			return text
		var doc: Dictionary = JSON.parse_string(text)
		doc["activities"][0]["drop_table"] = "vault_of_greed"
		return JSON.stringify(doc, "\t"))
	_check(dangling != null and not dangling.ok(), "dangling reference is rejected (ok() == false)")
	_check(dangling != null and dangling.library == null, "dangling reference hydrates no library")
	if dangling != null:
		for err in dangling.errors:
			print("    mutated-set error: " + err)
		_check_contains(dangling.errors, "activities[sort_scrap_pile]", "dangling ref error names the record id")
		_check_contains(dangling.errors, "drop_table: references unknown drop_tables id 'vault_of_greed'", "dangling ref error names field + reason")

	# Defect 3 — an entire domain file omitted.
	var missing := _load_mutated_fixture("missing_file", func(action: String, file_name: String, text: String) -> Variant:
		if action == "skip_file":
			return file_name == "monsters.json"
		return text)
	_check(missing != null and not missing.ok(), "missing domain file is rejected (ok() == false)")
	if missing != null:
		for err in missing.errors:
			print("    mutated-set error: " + err)
		_check_contains(missing.errors, "data/monsters.json: required content file is missing", "missing domain file error names the file")

	# Defect 4 — T17: a deputy ladder that gets cheaper is rejected (the
	# cross-check pins rung count + non-decreasing prices).
	var cheap_ladder := _load_mutated_fixture("cheap_ladder", func(action: String, file_name: String, text: String) -> Variant:
		if action == "skip_file":
			return false
		if file_name != "staffing.json":
			return text
		var doc: Dictionary = JSON.parse_string(text)
		doc["deputies"][1]["price"] = 10
		return JSON.stringify(doc, "	"))
	_check(cheap_ladder != null and not cheap_ladder.ok(), "cheaper deputy rung is rejected (ok() == false)")
	if cheap_ladder != null:
		for err in cheap_ladder.errors:
			print("    mutated-set error: " + err)
		_check_contains(cheap_ladder.errors, "deputies[1] (id=third_deputy) · price: 10 is lower than the previous rung's 75",
			"descending-ladder error names the rung + both prices")

	_check(wrong_type != null and dangling != null and missing != null
		and wrong_type.errors.size() + dangling.errors.size() + missing.errors.size() >= 3,
		"three defect classes each yield >= 1 actionable error")


# ----------------------------------------------------------- autoload wiring

func _check_autoload_wiring() -> void:
	# First process frame is when autoloads are guaranteed live (T1 lesson).
	var root := get_root()
	_check(root.has_node("ContentDB"), "ContentDB autoload is live at first process frame")
	if not root.has_node("ContentDB"):
		return
	var db: Node = root.get_node("ContentDB")
	_check(db.get("load_errors") != null and (db.get("load_errors") as Array).is_empty(),
		"ContentDB boot had zero content errors")
	_check(db.get("library") != null, "ContentDB holds a hydrated library")
	_check(int(db.call("record_count")) == GOLDEN_RECORD_COUNT, "ContentDB record_count() == %d" % GOLDEN_RECORD_COUNT)
	var stew: ItemDef = db.call("item", "radstag_stew")
	_check(stew != null and stew.heal == 80, "ContentDB.item('radstag_stew') serves typed lookups")


# ---------------------------------------------------------------- reporting

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _check_contains(haystack: Array[String], needle: String, label: String) -> void:
	_check(haystack.any(func(e: String) -> bool: return e.contains(needle)),
		"%s — expected an error containing: %s" % [label, needle])


func _report_and_quit() -> void:
	if failures.is_empty():
		print("PROBE_OK checks=%d (golden set hydrates typed; malformed records yield id+field+reason; ContentDB live)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("PROBE_FAIL " + failure)
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
