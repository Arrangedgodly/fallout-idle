class_name ActivityDef
extends RefCounted
## ActivityDef — one repeatable gathering action (T2 content schema).
##
## T6 executes these: every `interval_ms` the player completes one action,
## gains `xp_per_action` skill XP, and rolls `drop_table` once per `rolls`.
## All integers — offline catch-up is closed-form integer math on these fields.
## Field contract: docs/content-schema.md.

var id: String
var name: String
var skill: String  ## SkillDef id that trains this activity.
var level_gate: int  ## Clearance level in `skill` required to start.
var interval_ms: int  ## Wall-clock time per action (ms).
var xp_per_action: int
var drop_table: String  ## DropTableDef id rolled once per completed action.
var icon: String


static func hydrate(d: Dictionary) -> ActivityDef:
	var def := ActivityDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.skill = String(d["skill"])
	def.level_gate = int(d["level_gate"])
	def.interval_ms = int(d["interval_ms"])
	def.xp_per_action = int(d["xp_per_action"])
	def.drop_table = String(d["drop_table"])
	def.icon = String(d["icon"])
	return def
