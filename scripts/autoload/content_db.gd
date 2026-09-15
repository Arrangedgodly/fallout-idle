extends Node
## ContentDB — autoload gateway to the validated content library (T2).
##
## Per R1 (docs/ultron/research/r1-content-storage.md): JSON under res://data/
## is the source of truth; ContentLoader validates every record at boot and
## hydrates typed classes. Any validation error fails the boot loudly — the
## game never starts with content the schema rejected.

var library: ContentLibrary = null
var load_errors: Array[String] = []
var load_warnings: Array[String] = []


func _init() -> void:
	var result := ContentLoader.load_all()
	load_errors = result.errors
	load_warnings = result.warnings
	library = result.library
	for warning in load_warnings:
		push_warning(warning)


func _ready() -> void:
	if not load_errors.is_empty():
		for err in load_errors:
			push_error(err)
		push_error("[content] %d validation error(s) — refusing to start. Fix the records above (file · record · field: reason)." % load_errors.size())
		# Fail loud next frame so every error prints before the process exits.
		get_tree().quit.call_deferred(1)


# -- Typed lookups (null on unknown id; gameplay code never touches raw JSON) --

func item(id: String) -> ItemDef:
	return library.item(id) if library != null else null


func skill(id: String) -> SkillDef:
	return library.skill(id) if library != null else null


func activity(id: String) -> ActivityDef:
	return library.activity(id) if library != null else null


func recipe(id: String) -> RecipeDef:
	return library.recipe(id) if library != null else null


func drop_table(id: String) -> DropTableDef:
	return library.drop_table(id) if library != null else null


func monster(id: String) -> MonsterDef:
	return library.monster(id) if library != null else null


func equipment_for(item_id: String) -> EquipmentDef:
	return library.equipment_for(item_id) if library != null else null


func xp_curve(id: String) -> XpCurveDef:
	return library.xp_curve(id) if library != null else null


func shop_entries() -> Array[ShopEntryDef]:
	return library.shop_entries() if library != null else []


func record_count() -> int:
	return library.record_count() if library != null else 0
