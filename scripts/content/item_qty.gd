class_name ItemQty
extends RefCounted
## ItemQty — a (item id, quantity) stack value object (T2).
##
## Shared shape for recipe inputs/outputs. Hydrated from JSON by ContentLoader;
## never constructed from raw dicts by gameplay code.

var item: String
var qty: int


func _init(p_item: String = "", p_qty: int = 0) -> void:
	item = p_item
	qty = p_qty
