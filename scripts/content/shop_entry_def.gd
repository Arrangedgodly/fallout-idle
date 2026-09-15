class_name ShopEntryDef
extends RefCounted
## ShopEntryDef — one Depot (shop) stock line (T2 content schema).
##
## Buying charges `buy_price` caps; selling always pays ItemDef.value (single
## honest sell price lives on the item). `gate_skill`/`gate_level` (both or
## neither) hide the line behind a clearance, per town-hall criterion 2.
## Field contract: docs/content-schema.md.

var item: String  ## ItemDef id — this record's identity.
var buy_price: int  ## Caps charged per unit (>= 1).
var gate_skill: String = ""  ## SkillDef id; "" = ungated.
var gate_level: int = 0  ## Clearance level in gate_skill; 0 = ungated.


static func hydrate(d: Dictionary) -> ShopEntryDef:
	var def := ShopEntryDef.new()
	def.item = String(d["item"])
	def.buy_price = int(d["buy_price"])
	if d.has("gate") and d["gate"] != null:
		def.gate_skill = String(d["gate"]["skill"])
		def.gate_level = int(d["gate"]["level"])
	return def


func id() -> String:
	return item


func is_gated() -> bool:
	return gate_skill != ""
