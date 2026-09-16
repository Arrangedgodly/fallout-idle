class_name ContentLoader
extends RefCounted
## ContentLoader — reads res://data/*.json, validates every record, hydrates
## typed classes (T2; implements R1: docs/ultron/research/r1-content-storage.md).
##
## Source of truth is JSON on disk; this loader is the ONLY reader. It enforces:
##   - exact key sets (typos and stale fields are errors, never silently kept),
##   - types + ranges on every field (JSON numbers arrive as float — ints are
##     coerced and bounds-checked well below the 2^53 precision cliff),
##   - cross-domain reference integrity + duplicate-id detection,
##   - strict icon resolution: every icon id must resolve to a shipped
##     res://assets/icons/<id>.svg (T11 no-row-no-ship gate),
##   - orphan detection (warnings — T5's "no orphan items" gate reads these).
##
## Every error is actionable and shaped:
##   [content] data/<file>.json · <records>[i] (id=<id>) · <field>: <reason>
## Boot policy: any error -> ContentDB refuses to start the game (fail loud).

const SCHEMA_VERSION := 1
const DATA_DIR := "res://data"

# Field-range contract (mirrored in docs/content-schema.md — keep in sync).
const ITEM_CATEGORIES := ["resource", "material", "food", "equipment"]
const EQUIPMENT_SLOTS := ["weapon", "armor"]
const SKILL_KINDS := ["gathering", "processing", "combat"]
const VALUE_MAX := 1000000  ## caps per unit / buy price
const QTY_MAX := 999  ## inventory stack ceiling (design-brief ranges)
const HEAL_MAX := 10000
const INTERVAL_MS_MIN := 100
const INTERVAL_MS_MAX := 600000
const XP_MAX := 1000000
const LEVEL_MAX := 99
const MAX_LEVEL_MIN := 2
const WEIGHT_MAX := 100000
const ENTRIES_MAX := 64
const ROLLS_MAX := 10
const STAT_MAX := 100000  ## combat hp/accuracy/evasion scale
const HIT_MAX := 10000
const BONUS_MAX := 10000
const XP_PER_LEVEL_MAX := 100000000
const ID_LEN_MAX := 64
const DEPUTY_RUNGS := 4  ## run-2 staffing ladder: 1 + 4 deputies = 5 postings


class Result:
	extends RefCounted
	var library: ContentLibrary = null
	var errors: Array[String] = []
	var warnings: Array[String] = []

	func ok() -> bool:
		return errors.is_empty()


## Accumulates actionable errors while walking one domain file.
class Ctx:
	extends RefCounted
	var file := ""
	var errors: Array[String] = []
	var path := ""
	var rec_id := ""

	func err(field: String, reason: String) -> void:
		errors.append("[content] %s · %s · %s: %s" % [file, pointer(), field, reason])

	func pointer() -> String:
		if rec_id != "":
			return "%s (id=%s)" % [path, rec_id]
		return path

	## Point the context at a record (used by install-time checks).
	func at(p_path: String, p_id: String) -> void:
		path = p_path
		rec_id = p_id

	## Child context for nested structures (inputs[i], entries[j], gate, output).
	func nested(segment: String) -> Ctx:
		var child := Ctx.new()
		child.file = file
		child.errors = errors
		child.rec_id = rec_id
		child.path = "%s.%s" % [path, segment]
		return child


## Entry point. `dir` is overridable so headless tests can validate fixture
## sets (e.g. malformed copies under user://) via the exact production path.
static func load_all(dir: String = DATA_DIR) -> Result:
	var res := Result.new()
	var lib := ContentLibrary.new()
	for spec in _domain_specs():
		_load_domain(dir, spec, lib, res)
	if res.errors.is_empty():
		_cross_check(lib, res)
		if res.errors.is_empty():
			res.library = lib
			for orphan in lib.orphan_item_ids():
				res.warnings.append("[content] orphan item '%s': no drop table, recipe output, or shop line can produce it" % orphan)
			for unused in lib.unused_drop_table_ids():
				res.warnings.append("[content] drop table '%s' is never rolled by any activity or monster" % unused)
	return res


static func _domain_specs() -> Array[Dictionary]:
	return [
		{"file": "items.json", "key": "items", "validate": _validate_item, "install": _install_items},
		{"file": "skills.json", "key": "skills", "validate": _validate_skill, "install": _install_skills},
		{"file": "activities.json", "key": "activities", "validate": _validate_activity, "install": _install_activities},
		{"file": "recipes.json", "key": "recipes", "validate": _validate_recipe, "install": _install_recipes},
		{"file": "drop_tables.json", "key": "drop_tables", "validate": _validate_drop_table, "install": _install_drop_tables},
		{"file": "monsters.json", "key": "monsters", "validate": _validate_monster, "install": _install_monsters},
		{"file": "equipment.json", "key": "equipment", "validate": _validate_equipment, "install": _install_equipment},
		{"file": "shop_stock.json", "key": "shop_stock", "validate": _validate_shop_entry, "install": _install_shop},
		{"file": "xp_curves.json", "key": "xp_curves", "validate": _validate_xp_curve, "install": _install_xp_curves},
		{"file": "staffing.json", "key": "deputies", "validate": _validate_deputy, "install": _install_deputies},
	]


# ---------------------------------------------------------------- domain pass

static func _load_domain(dir: String, spec: Dictionary, lib: ContentLibrary, res: Result) -> void:
	var rel := "data/%s" % spec["file"]
	var ctx := Ctx.new()
	ctx.file = rel
	ctx.errors = res.errors
	var path := "%s/%s" % [dir, spec["file"]]

	if not FileAccess.file_exists(path):
		res.errors.append("[content] %s: required content file is missing" % rel)
		return
	var parser := JSON.new()
	var parse_err := parser.parse(FileAccess.get_file_as_string(path))
	if parse_err != OK:
		res.errors.append("[content] %s: JSON syntax error on line %d: %s" %
			[rel, parser.get_error_line(), parser.get_error_message()])
		return
	var root: Variant = parser.data
	if root is not Dictionary:
		res.errors.append("[content] %s: top level must be a JSON object, got %s" %
			[rel, _type_name(root)])
		return
	var doc: Dictionary = root

	# Exact top-level key set: {schema_version, <records key>} — nothing else.
	for key in ["schema_version", spec["key"]]:
		if not doc.has(key):
			res.errors.append("[content] %s · top level: missing required key '%s'" % [rel, key])
	for key in doc:
		if key != "schema_version" and key != spec["key"]:
			res.errors.append("[content] %s · top level: unknown key '%s' (expected only 'schema_version' and '%s')" %
				[rel, key, spec["key"]])
	if res.errors.any(func(e: String) -> bool: return e.begins_with("[content] %s · top level" % rel)):
		return

	var version: Variant = doc["schema_version"]
	if version is not float and version is not int:
		res.errors.append("[content] %s · top level · 'schema_version': must be an integer, got %s" %
			[rel, _type_name(version)])
		return
	if int(version) != SCHEMA_VERSION:
		res.errors.append("[content] %s · top level · 'schema_version': is %d but this build's loader understands %d — content and code must move together (docs/content-schema.md)" %
			[rel, int(version), SCHEMA_VERSION])
		return

	var records: Variant = doc[spec["key"]]
	if records is not Array:
		res.errors.append("[content] %s · '%s': must be an array of records, got %s" %
			[rel, spec["key"], _type_name(records)])
		return

	var defs: Array = []
	for i in records.size():
		var record: Variant = records[i]
		ctx.path = "%s[%d]" % [spec["key"], i]
		ctx.rec_id = _best_effort_id(record)
		if record is not Dictionary:
			ctx.err("(record)", "must be a JSON object, got %s" % _type_name(record))
			continue
		var def: Variant = spec["validate"].call(record, ctx)
		if def != null:
			defs.append(def)
	spec["install"].call(lib, defs, ctx, spec["key"])


static func _install_items(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.items.has(def.id):
			ctx.err("id", "duplicate item id '%s' — already defined in this file" % def.id)
			continue
		lib.items[def.id] = def


static func _install_skills(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.skills.has(def.id):
			ctx.err("id", "duplicate skill id '%s' — already defined in this file" % def.id)
			continue
		lib.skills[def.id] = def


static func _install_activities(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.activities.has(def.id):
			ctx.err("id", "duplicate activity id '%s' — already defined in this file" % def.id)
			continue
		lib.activities[def.id] = def


static func _install_recipes(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.recipes.has(def.id):
			ctx.err("id", "duplicate recipe id '%s' — already defined in this file" % def.id)
			continue
		lib.recipes[def.id] = def


static func _install_drop_tables(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.drop_tables.has(def.id):
			ctx.err("id", "duplicate drop table id '%s' — already defined in this file" % def.id)
			continue
		lib.drop_tables[def.id] = def


static func _install_monsters(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.monsters.has(def.id):
			ctx.err("id", "duplicate monster id '%s' — already defined in this file" % def.id)
			continue
		lib.monsters[def.id] = def


static func _install_equipment(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.item)
		if lib.equipment.has(def.item):
			ctx.err("item", "duplicate equipment record for item '%s' — already defined in this file" % def.item)
			continue
		lib.equipment[def.item] = def


static func _install_shop(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.item)
		var duplicate := false
		for existing in lib.shop_stock:
			if existing.item == def.item:
				ctx.err("item", "duplicate shop stock line for item '%s' — already defined in this file" % def.item)
				duplicate = true
				break
		if not duplicate:
			lib.shop_stock.append(def)


static func _install_xp_curves(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		if lib.xp_curves.has(def.id):
			ctx.err("id", "duplicate xp curve id '%s' — already defined in this file" % def.id)
			continue
		lib.xp_curves[def.id] = def


## The staffing ladder installs in FILE ORDER (ladder order = purchase
## order); duplicate ids are rejected like every other domain.
static func _install_deputies(lib: ContentLibrary, defs: Array, ctx: Ctx, key: String) -> void:
	for def in defs:
		ctx.at(key, def.id)
		var duplicate := false
		for existing in lib.deputies:
			if existing.id == def.id:
				ctx.err("id", "duplicate deputy record id '%s' — already defined in this file" % def.id)
				duplicate = true
				break
		if not duplicate:
			lib.deputies.append(def)


# ------------------------------------------------------------ record schemas

static func _validate_item(rec: Dictionary, ctx: Ctx) -> ItemDef:
	_check_keys(rec, ctx, ["id", "name", "category", "value", "icon"], ["heal"])
	var id := _get_id(rec, ctx, "id")
	var item_name := _get_string(rec, ctx, "name")
	var category := _get_enum(rec, ctx, "category", ITEM_CATEGORIES)
	var value: Variant = _get_int(rec, ctx, "value", 0, VALUE_MAX)
	var icon := _get_id(rec, ctx, "icon")
	if id == "" or item_name == "" or category == "" or value == null or icon == "":
		return null
	var heal: int = -1
	if rec.has("heal"):
		if category != "food":
			ctx.err("heal", "only food items may define 'heal', but category is '%s'" % category)
			return null
		var heal_raw: Variant = _get_int(rec, ctx, "heal", 1, HEAL_MAX)
		if heal_raw == null:
			return null
		heal = heal_raw
	elif category == "food":
		ctx.err("heal", "food items must define 'heal' (HP restored by auto-eat, 1-%d)" % HEAL_MAX)
		return null
	var def := ItemDef.new()
	def.id = id
	def.name = item_name
	def.category = category
	def.value = value
	def.heal = heal
	def.icon = icon
	return def


static func _validate_skill(rec: Dictionary, ctx: Ctx) -> SkillDef:
	_check_keys(rec, ctx, ["id", "name", "kind", "max_level", "xp_curve", "icon"])
	var id := _get_id(rec, ctx, "id")
	var skill_name := _get_string(rec, ctx, "name")
	var kind := _get_enum(rec, ctx, "kind", SKILL_KINDS)
	var max_level: Variant = _get_int(rec, ctx, "max_level", MAX_LEVEL_MIN, LEVEL_MAX)
	var xp_curve := _get_id(rec, ctx, "xp_curve")
	var icon := _get_id(rec, ctx, "icon")
	if id == "" or skill_name == "" or kind == "" or max_level == null or xp_curve == "" or icon == "":
		return null
	var def := SkillDef.new()
	def.id = id
	def.name = skill_name
	def.kind = kind
	def.max_level = max_level
	def.xp_curve = xp_curve
	def.icon = icon
	return def


static func _validate_activity(rec: Dictionary, ctx: Ctx) -> ActivityDef:
	_check_keys(rec, ctx, ["id", "name", "skill", "level_gate", "interval_ms", "xp_per_action", "drop_table", "icon"])
	var id := _get_id(rec, ctx, "id")
	var activity_name := _get_string(rec, ctx, "name")
	var skill := _get_id(rec, ctx, "skill")
	var level_gate: Variant = _get_int(rec, ctx, "level_gate", 1, LEVEL_MAX)
	var interval_ms: Variant = _get_int(rec, ctx, "interval_ms", INTERVAL_MS_MIN, INTERVAL_MS_MAX)
	var xp: Variant = _get_int(rec, ctx, "xp_per_action", 1, XP_MAX)
	var drop_table := _get_id(rec, ctx, "drop_table")
	var icon := _get_id(rec, ctx, "icon")
	if id == "" or activity_name == "" or skill == "" or level_gate == null or interval_ms == null or xp == null or drop_table == "" or icon == "":
		return null
	var def := ActivityDef.new()
	def.id = id
	def.name = activity_name
	def.skill = skill
	def.level_gate = level_gate
	def.interval_ms = interval_ms
	def.xp_per_action = xp
	def.drop_table = drop_table
	def.icon = icon
	return def


static func _validate_recipe(rec: Dictionary, ctx: Ctx) -> RecipeDef:
	_check_keys(rec, ctx, ["id", "name", "skill", "level_gate", "interval_ms", "xp_per_action", "inputs", "output"], ["icon"])
	var id := _get_id(rec, ctx, "id")
	var recipe_name := _get_string(rec, ctx, "name")
	var skill := _get_id(rec, ctx, "skill")
	var level_gate: Variant = _get_int(rec, ctx, "level_gate", 1, LEVEL_MAX)
	var interval_ms: Variant = _get_int(rec, ctx, "interval_ms", INTERVAL_MS_MIN, INTERVAL_MS_MAX)
	var xp: Variant = _get_int(rec, ctx, "xp_per_action", 1, XP_MAX)
	var inputs_raw: Variant = _get_array_of_dicts(rec, ctx, "inputs", 1, 4)
	var output_raw: Variant = _get_dict(rec, ctx, "output", ["item", "qty"])
	if id == "" or recipe_name == "" or skill == "" or level_gate == null or interval_ms == null or xp == null or inputs_raw == null or output_raw == null:
		return null

	var inputs: Array[ItemQty] = []
	for i in inputs_raw.size():
		var stack_ctx := ctx.nested("inputs[%d]" % i)
		var item := _get_id(inputs_raw[i], stack_ctx, "item")
		var qty: Variant = _get_int(inputs_raw[i], stack_ctx, "qty", 1, QTY_MAX)
		if item == "" or qty == null:
			return null
		inputs.append(ItemQty.new(item, qty))

	var out_ctx := ctx.nested("output")
	var out_item := _get_id(output_raw, out_ctx, "item")
	var out_qty: Variant = _get_int(output_raw, out_ctx, "qty", 1, QTY_MAX)
	if out_item == "" or out_qty == null:
		return null

	var icon := ""
	if rec.has("icon"):
		icon = _get_id(rec, ctx, "icon")
		if icon == "":
			return null

	var def := RecipeDef.new()
	def.id = id
	def.name = recipe_name
	def.skill = skill
	def.level_gate = level_gate
	def.interval_ms = interval_ms
	def.xp_per_action = xp
	def.inputs = inputs
	def.output = ItemQty.new(out_item, out_qty)
	def.icon = icon
	return def


static func _validate_drop_table(rec: Dictionary, ctx: Ctx) -> DropTableDef:
	_check_keys(rec, ctx, ["id", "name", "rolls", "entries"])
	var id := _get_id(rec, ctx, "id")
	var table_name := _get_string(rec, ctx, "name")
	var rolls: Variant = _get_int(rec, ctx, "rolls", 1, ROLLS_MAX)
	var entries_raw: Variant = _get_array_of_dicts(rec, ctx, "entries", 1, ENTRIES_MAX)
	if id == "" or table_name == "" or rolls == null or entries_raw == null:
		return null

	var entries: Array[DropTableDef.Entry] = []
	for i in entries_raw.size():
		var entry_ctx := ctx.nested("entries[%d]" % i)
		_check_keys(entries_raw[i], entry_ctx, ["item", "weight", "qty_min", "qty_max"])
		var item := _get_id(entries_raw[i], entry_ctx, "item")
		var weight: Variant = _get_int(entries_raw[i], entry_ctx, "weight", 1, WEIGHT_MAX)
		var qty_min: Variant = _get_int(entries_raw[i], entry_ctx, "qty_min", 1, QTY_MAX)
		var qty_max: Variant = _get_int(entries_raw[i], entry_ctx, "qty_max", 1, QTY_MAX)
		if item == "" or weight == null or qty_min == null or qty_max == null:
			return null
		if qty_min > qty_max:
			entry_ctx.err("qty_min", "qty_min (%d) must be <= qty_max (%d)" % [qty_min, qty_max])
			return null
		entries.append(DropTableDef.Entry.new(item, weight, qty_min, qty_max))

	var def := DropTableDef.new()
	def.id = id
	def.name = table_name
	def.rolls = rolls
	def.entries = entries
	return def


static func _validate_monster(rec: Dictionary, ctx: Ctx) -> MonsterDef:
	_check_keys(rec, ctx, ["id", "name", "zone", "is_boss", "level_gate", "max_hp", "attack_speed_ms", "accuracy", "evasion", "min_hit", "max_hit", "xp_reward", "drop_table", "icon"])
	var id := _get_id(rec, ctx, "id")
	var monster_name := _get_string(rec, ctx, "name")
	var zone := _get_id(rec, ctx, "zone")
	var is_boss: Variant = _get_bool(rec, ctx, "is_boss")
	var level_gate: Variant = _get_int(rec, ctx, "level_gate", 1, LEVEL_MAX)
	var max_hp: Variant = _get_int(rec, ctx, "max_hp", 1, STAT_MAX)
	var attack_speed_ms: Variant = _get_int(rec, ctx, "attack_speed_ms", INTERVAL_MS_MIN, INTERVAL_MS_MAX)
	var accuracy: Variant = _get_int(rec, ctx, "accuracy", 1, STAT_MAX)
	var evasion: Variant = _get_int(rec, ctx, "evasion", 0, STAT_MAX)
	var min_hit: Variant = _get_int(rec, ctx, "min_hit", 0, HIT_MAX)
	var max_hit: Variant = _get_int(rec, ctx, "max_hit", 1, HIT_MAX)
	var xp_reward: Variant = _get_int(rec, ctx, "xp_reward", 1, XP_MAX)
	var drop_table := _get_id(rec, ctx, "drop_table")
	var icon := _get_id(rec, ctx, "icon")
	if id == "" or monster_name == "" or zone == "" or is_boss == null or level_gate == null or max_hp == null or attack_speed_ms == null or accuracy == null or evasion == null or min_hit == null or max_hit == null or xp_reward == null or drop_table == "" or icon == "":
		return null
	if min_hit > max_hit:
		ctx.err("min_hit", "min_hit (%d) must be <= max_hit (%d)" % [min_hit, max_hit])
		return null
	var def := MonsterDef.new()
	def.id = id
	def.name = monster_name
	def.zone = zone
	def.is_boss = is_boss
	def.level_gate = level_gate
	def.max_hp = max_hp
	def.attack_speed_ms = attack_speed_ms
	def.accuracy = accuracy
	def.evasion = evasion
	def.min_hit = min_hit
	def.max_hit = max_hit
	def.xp_reward = xp_reward
	def.drop_table = drop_table
	def.icon = icon
	return def


static func _validate_equipment(rec: Dictionary, ctx: Ctx) -> EquipmentDef:
	_check_keys(rec, ctx, ["item", "slot"], ["attack_speed_ms", "accuracy_bonus", "max_hit_bonus", "evasion_bonus", "max_hp_bonus"])
	var item := _get_id(rec, ctx, "item")
	var slot := _get_enum(rec, ctx, "slot", EQUIPMENT_SLOTS)
	if item == "" or slot == "":
		return null
	var attack_speed_ms: int = -1
	if rec.has("attack_speed_ms"):
		if slot != "weapon":
			ctx.err("attack_speed_ms", "only weapons may override attack_speed_ms, but slot is '%s'" % slot)
			return null
		var speed_raw: Variant = _get_int(rec, ctx, "attack_speed_ms", INTERVAL_MS_MIN, INTERVAL_MS_MAX)
		if speed_raw == null:
			return null
		attack_speed_ms = speed_raw
	var accuracy_bonus: Variant = _optional_int(rec, ctx, "accuracy_bonus", BONUS_MAX)
	var max_hit_bonus: Variant = _optional_int(rec, ctx, "max_hit_bonus", BONUS_MAX)
	var evasion_bonus: Variant = _optional_int(rec, ctx, "evasion_bonus", BONUS_MAX)
	var max_hp_bonus: Variant = _optional_int(rec, ctx, "max_hp_bonus", BONUS_MAX)
	if accuracy_bonus == null or max_hit_bonus == null or evasion_bonus == null or max_hp_bonus == null:
		return null
	var def := EquipmentDef.new()
	def.item = item
	def.slot = slot
	def.attack_speed_ms = attack_speed_ms
	def.accuracy_bonus = accuracy_bonus
	def.max_hit_bonus = max_hit_bonus
	def.evasion_bonus = evasion_bonus
	def.max_hp_bonus = max_hp_bonus
	return def


static func _validate_shop_entry(rec: Dictionary, ctx: Ctx) -> ShopEntryDef:
	_check_keys(rec, ctx, ["item", "buy_price"], ["gate"])
	var item := _get_id(rec, ctx, "item")
	var buy_price: Variant = _get_int(rec, ctx, "buy_price", 1, VALUE_MAX)
	if item == "" or buy_price == null:
		return null
	var def := ShopEntryDef.new()
	def.item = item
	def.buy_price = buy_price
	if rec.has("gate"):
		var gate_ctx := ctx.nested("gate")
		var gate: Variant = _get_dict(rec, ctx, "gate", ["skill", "level"])
		if gate == null:
			return null
		var gate_skill := _get_id(gate, gate_ctx, "skill")
		var gate_level: Variant = _get_int(gate, gate_ctx, "level", 1, LEVEL_MAX)
		if gate_skill == "" or gate_level == null:
			return null
		def.gate_skill = gate_skill
		def.gate_level = gate_level
	return def


static func _validate_xp_curve(rec: Dictionary, ctx: Ctx) -> XpCurveDef:
	_check_keys(rec, ctx, ["id", "name", "max_level", "xp_per_level"])
	var id := _get_id(rec, ctx, "id")
	var curve_name := _get_string(rec, ctx, "name")
	var max_level: Variant = _get_int(rec, ctx, "max_level", MAX_LEVEL_MIN, LEVEL_MAX)
	if id == "" or curve_name == "" or max_level == null:
		return null
	if rec["xp_per_level"] is not Array:
		ctx.err("xp_per_level", "must be an array of XP ints, got %s" % _type_name(rec["xp_per_level"]))
		return null
	var raw_levels: Array = rec["xp_per_level"]
	if raw_levels.size() != max_level - 1:
		ctx.err("xp_per_level", "length (%d) must be exactly max_level - 1 (%d) — one entry per level-up from level 1" %
			[raw_levels.size(), max_level - 1])
		return null
	var levels := PackedInt64Array()
	for i in raw_levels.size():
		var step: Variant = _get_int_value(raw_levels[i], ctx, "xp_per_level[%d]" % i, 1, XP_PER_LEVEL_MAX)
		if step == null:
			return null
		levels.append(step)
	var def := XpCurveDef.new()
	def.id = id
	def.name = curve_name
	def.max_level = max_level
	def.xp_per_level = levels
	return def


## One staffing rung: id + price (T17). Ladder integrity is cross-checked in
## _cross_check (exactly DEPUTY_RUNGS rungs, non-decreasing prices).
static func _validate_deputy(rec: Dictionary, ctx: Ctx) -> DeputyDef:
	_check_keys(rec, ctx, ["id", "price"])
	var id := _get_id(rec, ctx, "id")
	var price: Variant = _get_int(rec, ctx, "price", 1, VALUE_MAX)
	if id == "" or price == null:
		return null
	var def := DeputyDef.new()
	def.id = id
	def.price = price
	return def


# ------------------------------------------------------------- cross-checks

## Reference integrity across domains; runs only when per-record validation
## passed everywhere, so hydrated defs are complete enough to walk.
static func _cross_check(lib: ContentLibrary, res: Result) -> void:
	for skill in lib.skills.values():
		_require_ref(lib, res, "data/skills.json", "skills[%s]" % skill.id, "xp_curve", "xp_curves", skill.xp_curve)
		var curve := lib.xp_curve(skill.xp_curve)
		if curve != null and curve.max_level != skill.max_level:
			res.errors.append("[content] data/skills.json · skills[%s] · max_level: is %d but xp curve '%s' tops out at %d — they must agree" %
				[skill.id, skill.max_level, skill.xp_curve, curve.max_level])

	for activity in lib.activities.values():
		_require_ref(lib, res, "data/activities.json", "activities[%s]" % activity.id, "skill", "skills", activity.skill)
		_require_ref(lib, res, "data/activities.json", "activities[%s]" % activity.id, "drop_table", "drop_tables", activity.drop_table)

	for recipe in lib.recipes.values():
		_require_ref(lib, res, "data/recipes.json", "recipes[%s]" % recipe.id, "skill", "skills", recipe.skill)
		_require_ref(lib, res, "data/recipes.json", "recipes[%s]" % recipe.id, "output.item", "items", recipe.output.item)
		for i in recipe.inputs.size():
			_require_ref(lib, res, "data/recipes.json", "recipes[%s]" % recipe.id, "inputs[%d].item" % i, "items", recipe.inputs[i].item)

	for table in lib.drop_tables.values():
		for i in table.entries.size():
			_require_ref(lib, res, "data/drop_tables.json", "drop_tables[%s]" % table.id, "entries[%d].item" % i, "items", table.entries[i].item)

	for monster in lib.monsters.values():
		_require_ref(lib, res, "data/monsters.json", "monsters[%s]" % monster.id, "drop_table", "drop_tables", monster.drop_table)

	for equip in lib.equipment.values():
		_require_ref(lib, res, "data/equipment.json", "equipment[%s]" % equip.item, "item", "items", equip.item)
		var item := lib.item(equip.item)
		if item != null and not item.is_equipment():
			res.errors.append("[content] data/equipment.json · equipment[%s] · item: item '%s' has category '%s', expected 'equipment'" %
				[equip.item, item.id, item.category])

	for entry in lib.shop_stock:
		_require_ref(lib, res, "data/shop_stock.json", "shop_stock[%s]" % entry.item, "item", "items", entry.item)
		if entry.gate_skill != "":
			_require_ref(lib, res, "data/shop_stock.json", "shop_stock[%s]" % entry.item, "gate.skill", "skills", entry.gate_skill)

	# T17 staffing ladder: exactly DEPUTY_RUNGS rungs (1 + 4 = 5 postings, the
	# amendment's all-5-skills target), prices non-decreasing in ladder order.
	if lib.deputies.size() != DEPUTY_RUNGS:
		res.errors.append("[content] data/staffing.json · deputies: must contain exactly %d rungs (1 resident + %d deputies = 5 postings), got %d" %
			[DEPUTY_RUNGS, DEPUTY_RUNGS, lib.deputies.size()])
	else:
		for i in range(1, lib.deputies.size()):
			if lib.deputies[i].price < lib.deputies[i - 1].price:
				res.errors.append("[content] data/staffing.json · deputies[%d] (id=%s) · price: %d is lower than the previous rung's %d — a deputy ladder never gets cheaper" %
					[i, lib.deputies[i].id, lib.deputies[i].price, lib.deputies[i - 1].price])

	# T11 strict icon gate: every icon id must resolve to a shipped SVG asset
	# under res://assets/icons/ — an unresolvable icon is a boot error, not a
	# silent missing sprite (per R3 + the ASSETS.md no-row-no-ship gate).
	for icon_item in lib.items.values():
		_require_icon(res, "data/items.json", "items[%s]" % icon_item.id, icon_item.icon)
	for icon_skill in lib.skills.values():
		_require_icon(res, "data/skills.json", "skills[%s]" % icon_skill.id, icon_skill.icon)
	for icon_activity in lib.activities.values():
		_require_icon(res, "data/activities.json", "activities[%s]" % icon_activity.id, icon_activity.icon)
	for icon_monster in lib.monsters.values():
		_require_icon(res, "data/monsters.json", "monsters[%s]" % icon_monster.id, icon_monster.icon)
	for icon_recipe in lib.recipes.values():
		_require_icon(res, "data/recipes.json", "recipes[%s]" % icon_recipe.id, icon_recipe.icon)

	# Every equipment-category item must carry an EquipmentDef (both directions).
	for item in lib.items.values():
		if item.is_equipment() and not lib.equipment.has(item.id):
			res.errors.append("[content] data/items.json · items[%s] · category: equipment item has no matching record in data/equipment.json" % item.id)

	# Monsters gate on a combat skill; the slice must own exactly one.
	var combat_skills: Array[String] = []
	for skill in lib.skills.values():
		if skill.is_combat():
			combat_skills.append(skill.id)
	if combat_skills.is_empty():
		res.errors.append("[content] data/skills.json · skills: no skill with kind 'combat' — monsters gate on one (Wasteland Combat)")


static func _require_ref(lib: ContentLibrary, res: Result, file: String, pointer: String, field: String, domain: String, id: String) -> void:
	if lib._pool(domain).has(id):
		return
	res.errors.append("[content] %s · %s · %s: references unknown %s id '%s'" %
		[file, pointer, field, domain, id])


## T11 strict icon gate: an icon id resolves iff res://assets/icons/<id>.svg
## exists as a loadable resource (ResourceLoader follows .import remaps in
## exported builds) or as a source file on disk (fresh checkouts pre-import).
static func _require_icon(res: Result, file: String, pointer: String, icon: String) -> void:
	if icon == "":
		return
	var path := "res://assets/icons/%s.svg" % icon
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		return
	res.errors.append("[content] %s · %s · icon: does not resolve — no icon asset '%s' (expected %s; T11 strict gate: every icon id needs a shipped SVG + an ASSETS.md row)" %
		[file, pointer, icon, path])


# ------------------------------------------------------------ field helpers

static func _check_keys(rec: Dictionary, ctx: Ctx, required: Array, optional := []) -> void:
	for field in required:
		if not rec.has(field):
			ctx.err(field, "missing required field")
	var known := {}
	for field in required + optional:
		known[field] = true
	for field in rec:
		if not known.has(field):
			ctx.err(field, "unknown field (valid fields: %s) — typos are errors here, never silently dropped" %
				", ".join(PackedStringArray(required + optional)))


## Snake-case id: [a-z][a-z0-9_]{0,63} — enforced everywhere ids and icon refs appear.
static func _get_id(rec: Dictionary, ctx: Ctx, field: String) -> String:
	var value := _get_string(rec, ctx, field, ID_LEN_MAX)
	if value == "":
		return ""
	for i in value.length():
		var c := value.unicode_at(i)
		var is_lower: bool = c >= 97 and c <= 122
		var is_digit: bool = c >= 48 and c <= 57
		if i == 0 and not is_lower:
			ctx.err(field, "must start with a lowercase letter, got '%s'" % value)
			return ""
		if not (is_lower or is_digit or c == 95):
			ctx.err(field, "may only contain lowercase letters, digits and underscores, got '%s'" % value)
			return ""
	return value


static func _get_string(rec: Dictionary, ctx: Ctx, field: String, max_len := 200) -> String:
	if not rec.has(field):
		return ""
	var value: Variant = rec[field]
	if value is not String:
		ctx.err(field, "must be a string, got %s (%s)" % [_type_name(value), _short(value)])
		return ""
	if value.length() > max_len:
		ctx.err(field, "must be at most %d characters, got %d" % [max_len, value.length()])
		return ""
	if value.strip_edges() == "":
		ctx.err(field, "must not be empty or whitespace-only")
		return ""
	return value


static func _get_int(rec: Dictionary, ctx: Ctx, field: String, lo: int, hi: int) -> Variant:
	if not rec.has(field):
		return null
	return _get_int_value(rec[field], ctx, field, lo, hi)


## Validate a raw numeric value (JSON numbers arrive as float: coerce whole
## floats to int, reject fractional/wrong-typed, bounds-check — R1).
static func _get_int_value(raw: Variant, ctx: Ctx, field: String, lo: int, hi: int) -> Variant:
	var value: Variant = raw
	if value is float:
		if value != floor(value):
			ctx.err(field, "must be a whole number, got %s" % _short(value))
			return null
		value = int(value)
	elif value is not int:
		ctx.err(field, "must be a number, got %s (%s)" % [_type_name(value), _short(value)])
		return null
	if value < lo or value > hi:
		ctx.err(field, "must be between %d and %d, got %d" % [lo, hi, value])
		return null
	return value


static func _get_bool(rec: Dictionary, ctx: Ctx, field: String) -> Variant:
	if not rec.has(field):
		return null
	var value: Variant = rec[field]
	if value is not bool:
		ctx.err(field, "must be true or false, got %s (%s)" % [_type_name(value), _short(value)])
		return null
	return value


static func _get_enum(rec: Dictionary, ctx: Ctx, field: String, options: Array) -> String:
	var value := _get_string(rec, ctx, field)
	if value == "":
		return ""
	if not options.has(value):
		ctx.err(field, "must be one of [%s], got '%s'" % [", ".join(PackedStringArray(options)), value])
		return ""
	return value


static func _get_dict(rec: Dictionary, ctx: Ctx, field: String, required_keys: Array) -> Variant:
	if not rec.has(field):
		return null
	var value: Variant = rec[field]
	if value is not Dictionary:
		ctx.err(field, "must be a JSON object, got %s" % _type_name(value))
		return null
	for key in required_keys:
		if not value.has(key):
			ctx.err("%s.%s" % [field, key], "missing required key inside '%s'" % field)
	return value


static func _get_array_of_dicts(rec: Dictionary, ctx: Ctx, field: String, min_n: int, max_n: int) -> Variant:
	if not rec.has(field):
		return null
	var value: Variant = rec[field]
	if value is not Array:
		ctx.err(field, "must be an array, got %s" % _type_name(value))
		return null
	if value.size() < min_n or value.size() > max_n:
		ctx.err(field, "must contain %d-%d entries, got %d" % [min_n, max_n, value.size()])
		return null
	for i in value.size():
		if value[i] is not Dictionary:
			ctx.err("%s[%d]" % [field, i], "must be a JSON object, got %s" % _type_name(value[i]))
			return null
	return value


static func _optional_int(rec: Dictionary, ctx: Ctx, field: String, hi: int) -> Variant:
	if not rec.has(field):
		return 0
	return _get_int(rec, ctx, field, 0, hi)


static func _best_effort_id(record: Variant) -> String:
	if record is not Dictionary:
		return ""
	for key in ["id", "item"]:
		if record.has(key) and record[key] is String:
			return record[key]
	return ""


static func _short(value: Variant) -> String:
	var text := str(value)
	if text.length() > 40:
		text = text.substr(0, 40) + "..."
	return "'%s'" % text


static func _type_name(value: Variant) -> String:
	return type_string(typeof(value))
