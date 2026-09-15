class_name RecipeDef
extends RefCounted
## RecipeDef — one processing recipe (T2 content schema).
##
## T6 executes these like activities (interval → consume inputs → grant output
## + XP). Consumes every input stack atomically, produces the output stack.
## Field contract: docs/content-schema.md.

var id: String
var name: String
var skill: String  ## SkillDef id that trains this recipe.
var level_gate: int  ## Clearance level in `skill` required to craft.
var interval_ms: int
var xp_per_action: int
var inputs: Array[ItemQty]  ## Consumed per craft (>= 1 entry).
var output: ItemQty  ## Produced per craft.
var icon: String = ""  ## Optional; empty = render the output item's icon.


static func hydrate(d: Dictionary) -> RecipeDef:
	var def := RecipeDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.skill = String(d["skill"])
	def.level_gate = int(d["level_gate"])
	def.interval_ms = int(d["interval_ms"])
	def.xp_per_action = int(d["xp_per_action"])
	for input_d in d["inputs"]:
		def.inputs.append(ItemQty.new(String(input_d["item"]), int(input_d["qty"])))
	def.output = ItemQty.new(String(d["output"]["item"]), int(d["output"]["qty"]))
	if d.has("icon"):
		def.icon = String(d["icon"])
	return def
