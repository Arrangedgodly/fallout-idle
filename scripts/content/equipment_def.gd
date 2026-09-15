class_name EquipmentDef
extends RefCounted
## EquipmentDef — combat data for an equipment item (T2 content schema).
##
## Keyed by (and always matching 1:1 with) an ItemDef whose category is
## "equipment". Bonuses are additive onto the player's base combat stats (T7);
## `attack_speed_ms` (weapon only) *replaces* the base attack interval.
## Field contract: docs/content-schema.md.

var item: String  ## ItemDef id — this record's identity.
var slot: String  ## "weapon" | "armor"
var attack_speed_ms: int = -1  ## Weapon only; -1 = keep base attack speed.
var accuracy_bonus: int = 0
var max_hit_bonus: int = 0
var evasion_bonus: int = 0
var max_hp_bonus: int = 0


static func hydrate(d: Dictionary) -> EquipmentDef:
	var def := EquipmentDef.new()
	def.item = String(d["item"])
	def.slot = String(d["slot"])
	def.attack_speed_ms = int(d["attack_speed_ms"]) if d.has("attack_speed_ms") else -1
	def.accuracy_bonus = int(d["accuracy_bonus"]) if d.has("accuracy_bonus") else 0
	def.max_hit_bonus = int(d["max_hit_bonus"]) if d.has("max_hit_bonus") else 0
	def.evasion_bonus = int(d["evasion_bonus"]) if d.has("evasion_bonus") else 0
	def.max_hp_bonus = int(d["max_hp_bonus"]) if d.has("max_hp_bonus") else 0
	return def


func id() -> String:
	return item


func is_weapon() -> bool:
	return slot == "weapon"
