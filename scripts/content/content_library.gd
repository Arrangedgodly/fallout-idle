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


func shop_entries() -> Array[ShopEntryDef]:
	return shop_stock


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
		_: return {}


func record_count() -> int:
	return items.size() + skills.size() + activities.size() + recipes.size() \
		+ drop_tables.size() + monsters.size() + equipment.size() \
		+ shop_stock.size() + xp_curves.size()


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
