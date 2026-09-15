class_name SkillDef
extends RefCounted
## SkillDef — one trainable skill (T2 content schema).
##
## The five slice skills (Scavenging, Foraging, Junksmithing, Cooking,
## Wasteland Combat) each get one record. Field contract: docs/content-schema.md.

var id: String
var name: String
var kind: String  ## "gathering" | "processing" | "combat"
var max_level: int  ## Must equal the referenced XpCurveDef's max_level (cross-checked).
var xp_curve: String  ## XpCurveDef id.
var icon: String


static func hydrate(d: Dictionary) -> SkillDef:
	var def := SkillDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.kind = String(d["kind"])
	def.max_level = int(d["max_level"])
	def.xp_curve = String(d["xp_curve"])
	def.icon = String(d["icon"])
	return def


func is_combat() -> bool:
	return kind == "combat"
