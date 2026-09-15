class_name MonsterDef
extends RefCounted
## MonsterDef — one wasteland encounter (T2 content schema).
##
## T7's tick auto-battle mirrors these stats against the player: attack speed,
## accuracy roll (attacker accuracy vs defender evasion), damage roll in
## [min_hit, max_hit]. Field contract: docs/content-schema.md.

var id: String
var name: String
var zone: String  ## Zone id — the slice ships exactly one zone.
var is_boss: bool
var level_gate: int  ## Clearance level in Wasteland Combat required to engage.
var max_hp: int
var attack_speed_ms: int
var accuracy: int
var evasion: int
var min_hit: int  ## Inclusive damage bounds (cross-checked: min_hit <= max_hit).
var max_hit: int
var xp_reward: int  ## Wasteland Combat XP granted on kill.
var drop_table: String  ## DropTableDef id rolled on victory.
var icon: String


static func hydrate(d: Dictionary) -> MonsterDef:
	var def := MonsterDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.zone = String(d["zone"])
	def.is_boss = bool(d["is_boss"])
	def.level_gate = int(d["level_gate"])
	def.max_hp = int(d["max_hp"])
	def.attack_speed_ms = int(d["attack_speed_ms"])
	def.accuracy = int(d["accuracy"])
	def.evasion = int(d["evasion"])
	def.min_hit = int(d["min_hit"])
	def.max_hit = int(d["max_hit"])
	def.xp_reward = int(d["xp_reward"])
	def.drop_table = String(d["drop_table"])
	def.icon = String(d["icon"])
	return def
