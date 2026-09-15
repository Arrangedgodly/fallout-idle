class_name ItemDef
extends RefCounted
## ItemDef — one inventory item (T2 content schema).
##
## Everything that can sit in the Manifest (inventory) is an Item. Equipment is
## an Item with `category == "equipment"` plus a matching EquipmentDef record.
## Food is `category == "food"` with a positive `heal` (consumed by combat
## auto-eat, T7). Field contract: docs/content-schema.md.

var id: String
var name: String
var category: String  ## "resource" | "material" | "food" | "equipment"
var value: int  ## Caps the Depot pays for one of these (sell price).
var heal: int = -1  ## HP restored when eaten; -1 = not edible (food must be >= 1).
var icon: String  ## Icon asset id; resolves to res://assets/icons/<icon>.svg (T11).


static func hydrate(d: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.category = String(d["category"])
	def.value = int(d["value"])
	def.heal = int(d["heal"]) if d.has("heal") else -1
	def.icon = String(d["icon"])
	return def


func is_food() -> bool:
	return category == "food"


func is_equipment() -> bool:
	return category == "equipment"
