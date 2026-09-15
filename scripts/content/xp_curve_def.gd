class_name XpCurveDef
extends RefCounted
## XpCurveDef — per-level XP requirements for one skill band (T2 content schema).
##
## `xp_per_level[i]` is the XP needed to advance from level (i+1) to (i+2);
## the array length is always max_level - 1 (level 1 is free). Hand-tunable
## per-entry — no formula is imposed by the engine. All integer math.
## Field contract: docs/content-schema.md.

var id: String
var name: String
var max_level: int
var xp_per_level: PackedInt64Array  ## Length == max_level - 1; every entry >= 1.


static func hydrate(d: Dictionary) -> XpCurveDef:
	var def := XpCurveDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	def.max_level = int(d["max_level"])
	var levels := PackedInt64Array()
	for raw in d["xp_per_level"]:
		levels.append(int(raw))
	def.xp_per_level = levels
	return def


## Total XP a level-1 character must earn to REACH `level` (1 -> 0).
func total_xp_to_reach(level: int) -> int:
	if level <= 1:
		return 0
	var clamped := mini(level, max_level)
	var total := 0
	for i in range(clamped - 1):
		total += xp_per_level[i]
	return total


## Highest level attainable with `total_xp` (closed-form inverse; T6/T13 use).
func level_for_total_xp(total_xp: int) -> int:
	var level := 1
	var spent := 0
	while level < max_level and spent + xp_per_level[level - 1] <= total_xp:
		spent += xp_per_level[level - 1]
		level += 1
	return level


## XP still needed to advance FROM `level` (0 at max_level).
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	return xp_per_level[level - 1]
