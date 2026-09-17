class_name ContentLibrary
extends RefCounted
## ContentLibrary — the hydrated, typed, read-only view of res://data (T2).
##
## Produced by ContentLoader after every record passed validation. Gameplay
## code (T6/T7/T10) reads content through here or through the ContentDB
## autoload — never from raw JSON. All lookups return null for unknown ids.


var items: Dictionary = {}  ## String -> ItemDef
var skills: Dictionary = {}  ## String -> SkillDef
var activities: Dictionary = {}  ## String -> ActivityDef
var recipes: Dictionary = {}  ## String -> RecipeDef
var drop_tables: Dictionary = {}  ## String -> DropTableDef
var monsters: Dictionary = {}  ## String -> MonsterDef
var equipment: Dictionary = {}  ## String (item id) -> EquipmentDef
var shop_stock: Array[ShopEntryDef] = []  ## File order = Depot display order.
var xp_curves: Dictionary = {}  ## String -> XpCurveDef
var deputies: Array[DeputyDef] = []  ## T17 staffing ladder; file order = purchase order.
var orientation_stipend: int = 0  ## T18 Crowns posted by the DULY ORIENTED reward line (data/staffing.json).
var zones: Dictionary = {}  ## String -> ZoneDef (T23; insertion order = file order).
## String -> ObjectiveDef (T23; insertion order = file order — the CANONICAL
## posted order of `objectives.stamped`, the orientation steps_done pattern).
## T23 ships the schema + engine with an EMPTY set; T25 authors >= 20/skill.
var objectives: Dictionary = {}
var _objective_order: Dictionary = {}  ## id -> file-order index (built at install; the O(1) sort key — T25)


func item(id: String) -> ItemDef:
	return items.get(id)


func skill(id: String) -> SkillDef:
	return skills.get(id)


func activity(id: String) -> ActivityDef:
	return activities.get(id)


func recipe(id: String) -> RecipeDef:
	return recipes.get(id)


func drop_table(id: String) -> DropTableDef:
	return drop_tables.get(id)


func monster(id: String) -> MonsterDef:
	return monsters.get(id)


func equipment_for(item_id: String) -> EquipmentDef:
	return equipment.get(item_id)


func xp_curve(id: String) -> XpCurveDef:
	return xp_curves.get(id)


func zone(id: String) -> ZoneDef:
	return zones.get(id)


func objective(id: String) -> ObjectiveDef:
	return objectives.get(id)


## One skill's dossier, in file (posted) order — the T26 register renders
## this array directly; `stamped` ordering uses the same file-order index.
func objectives_for_skill(skill_id: String) -> Array[ObjectiveDef]:
	var out: Array[ObjectiveDef] = []
	for obj_id in objectives:
		var def: ObjectiveDef = objectives[obj_id]
		if def.skill == skill_id:
			out.append(def)
	return out


## Canonical posted-order index of an objective id (-1 unknown) — the sort
## key for `objectives.stamped` / `objectives.rewards_granted`. O(1) from the
## install-time map (T25: the old linear scan ran inside every stamp's
## append-sort comparator — quadratic on the stamp path).
func objective_order_index(objective_id: String) -> int:
	return int(_objective_order.get(objective_id, -1))


## Called by the loader's install pass (file order == insertion order).
func index_objective_order(objective_id: String) -> void:
	if not _objective_order.has(objective_id):
		_objective_order[objective_id] = _objective_order.size()


func shop_entries() -> Array[ShopEntryDef]:
	return shop_stock


## Crowns the NEXT deputy costs at the current rung (deputies owned so far =
## `rung`, 0-based). -1 when the establishment is already at full strength
## (rung >= ladder size) — the engine surfaces that as its own refusal.
func deputy_price_at(rung: int) -> int:
	if rung < 0 or rung >= deputies.size():
		return -1
	return deputies[rung].price


## The id -> def dictionary backing a domain name (loader cross-check helper).
func _pool(domain: String) -> Dictionary:
	match domain:
		"items": return items
		"skills": return skills
		"activities": return activities
		"recipes": return recipes
		"drop_tables": return drop_tables
		"monsters": return monsters
		"equipment": return equipment
		"xp_curves": return xp_curves
		"zones": return zones
		"objectives": return objectives
		_: return {}


func record_count() -> int:
	return items.size() + skills.size() + activities.size() + recipes.size() \
		+ drop_tables.size() + monsters.size() + equipment.size() \
		+ shop_stock.size() + xp_curves.size() + deputies.size() \
		+ zones.size() + objectives.size()


## Items with no obtainment path (no drop table, recipe output, or shop stock
## line). Warnings only — T5's "no orphan items" acceptance turns these empty.
func orphan_item_ids() -> Array[String]:
	var obtainable := {}
	for table in drop_tables.values():
		for entry in table.entries:
			obtainable[entry.item] = true
	for recipe in recipes.values():
		obtainable[recipe.output.item] = true
	for entry in shop_stock:
		obtainable[entry.item] = true
	var orphans: Array[String] = []
	for item_id in items:
		if not obtainable.has(item_id):
			orphans.append(item_id)
	orphans.sort()
	return orphans


## Drop tables no activity or monster ever rolls. Warnings only (T5 cleanup).
func unused_drop_table_ids() -> Array[String]:
	var used := {}
	for activity in activities.values():
		used[activity.drop_table] = true
	for monster in monsters.values():
		used[monster.drop_table] = true
	var unused: Array[String] = []
	for table_id in drop_tables:
		if not used.has(table_id):
			unused.append(table_id)
	unused.sort()
	return unused
