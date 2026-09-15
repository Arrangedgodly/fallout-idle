class_name DropTableDef
extends RefCounted
## DropTableDef — a weighted, player-visible drop table (T2 content schema).
##
## One roll = one weighted pick among `entries`; `rolls` picks per action/kill.
## Rates are honest and visible: entry chance = weight / total_weight()
## (Professor X's visible-drop-tables convention; T10 renders these fractions).
## Field contract: docs/content-schema.md.

var id: String
var name: String  ## Display name shown above the drop line ("SCRAP PILE YIELDS").
var rolls: int  ## Independent picks per completed action (>= 1).
var entries: Array[Entry]  ## At least one entry.


class Entry extends RefCounted:
	var item: String  ## ItemDef id.
	var weight: int  ## Relative selection weight (>= 1).
	var qty_min: int  ## Inclusive quantity bounds on a won pick.
	var qty_max: int

	func _init(p_item: String = "", p_weight: int = 0, p_qty_min: int = 1, p_qty_max: int = 1) -> void:
		item = p_item
		weight = p_weight
		qty_min = p_qty_min
		qty_max = p_qty_max


static func hydrate(d: Dictionary) -> DropTableDef:
	var def := DropTableDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.rolls = int(d["rolls"])
	for entry_d in d["entries"]:
		def.entries.append(Entry.new(
			String(entry_d["item"]),
			int(entry_d["weight"]),
			int(entry_d["qty_min"]),
			int(entry_d["qty_max"]),
		))
	return def


func total_weight() -> int:
	var total := 0
	for entry in entries:
		total += entry.weight
	return total


func entry_for_item(item_id: String) -> Entry:
	for entry in entries:
		if entry.item == item_id:
			return entry
	return null
