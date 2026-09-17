extends RefCounted
## tests/objective_free_lib.gd — T25 shared boot helper (not a GUT script:
## no test_ prefix, never collected).
##
## The pre-objectives systems suites — engine, combat, orientation,
## resilience, run-2 acceptance — pin EXACT wallet/XP arithmetic on journeys
## whose subject is their own system (offline exactness, death zero-loss,
## stipend-once, big-number clamps, the earned-economy deputize). T25 authors
## the shipped dossier set, so those journeys now cross objective thresholds
## and inherit MERIT PAY / COMMENDATION income; pinning reward values inside
## five unrelated suites would break at every T27 retune by construction.
##
## These suites therefore boot on a full data/ copy with an EMPTY objectives
## array through the T23 injectable ContentLoader.load_all(dir) seam — the
## pins keep meaning exactly what they meant when written, and the objectives
## economy stays under test where it belongs (tests/test_objectives.gd drives
## the real set; probe_content asserts the amendment floor on shipped data).
## Memoized per scratch name: one fixture dir + one load per suite.

const DOMAIN_FILES := [
	"items.json", "skills.json", "activities.json", "recipes.json",
	"drop_tables.json", "monsters.json", "equipment.json", "shop_stock.json",
	"xp_curves.json", "staffing.json", "zones.json", "objectives.json",
]

static var _cache := {}


## Full data/ copy with objectives.json emptied, loaded through the exact
## production loader path. `scratch` names the calling suite (its fixture
## dir under user://t25_objective_free/).
static func load(scratch: String) -> ContentLibrary:
	if _cache.has(scratch):
		return _cache[scratch]
	var dir := OS.get_user_data_dir().path_join(
		"t25_objective_free/%s_%d" % [scratch, Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(dir)
	for file_name in DOMAIN_FILES:
		DirAccess.copy_absolute("res://data/%s" % file_name, dir.path_join(file_name))
	var f := FileAccess.open(dir.path_join("objectives.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 1, "objectives": []}, "\t"))
	f.close()
	var result = ContentLoader.load_all(dir)
	assert(result != null and result.ok(),
		"objective-free fixture loads clean (errors: %s)" % str(result.errors))
	assert(result != null and result.library != null, "fixture hydrates a library")
	assert(result.library.objectives.is_empty(), "fixture ships zero objectives")
	_cache[scratch] = result.library
	return result.library
