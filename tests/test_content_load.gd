extends GutTest
## tests/test_content_load.gd — T12 GUT content-load test (the real guard).
##
## Run via ./run_tests.sh (whole suite) or directly:
##   "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
##
## Proves the T12 "genuine content-load guard": every assertion reads the LIVE
## authored content (res://data via the production ContentLoader), so a broken
## record anywhere in the set fails this script and flips the suite exit code
## to 1. Demonstrated live during T12 by mutating data/items.json (value ->
## string) — see production-log.md T12 entry.
##
## Coexistence convention (T12): GUT tests live alongside the legacy probes;
## this script calls into the probe's logic by preloading it as a constant
## source (DOMAIN_FILES / GOLDEN_RECORD_COUNT stay owned by probe_content.gd
## so the two suites cannot drift on what "the full set" means). The probes
## remain runnable as plain --script smoke checks and are NOT collected by
## GUT (prefix test_ only).

const ProbeContent := preload("res://tests/probe_content.gd")


func test_authored_set_loads_and_validates() -> void:
	var result := ContentLoader.load_all()
	assert_true(result.ok(), "authored set validates (errors: %s)" % str(result.errors))
	assert_eq(result.errors.size(), 0, "zero loader errors")
	assert_eq(result.warnings.size(), 0, "zero loader warnings (orphan scans clean)")


func test_library_hydrates_typed_records() -> void:
	var result := ContentLoader.load_all()
	assert_not_null(result.library, "load_all hydrates a ContentLibrary")
	if result.library == null:
		return
	var lib: ContentLibrary = result.library
	# The probe-owned expectation: 21+5+8+11+13+5+4+11+1 records (T5 set).
	assert_eq(lib.record_count(), ProbeContent.GOLDEN_RECORD_COUNT,
		"record_count matches the probe's golden count")
	# Typed hydration + R1 int coercion on a known record.
	var scrap: ItemDef = lib.item("scrap_metal")
	assert_not_null(scrap, "item('scrap_metal') resolves")
	assert_true(scrap is ItemDef, "lookup is a typed ItemDef")
	assert_eq(scrap.name, "Scrapnel", "display name round-trips")
	assert_eq(typeof(scrap.value), TYPE_INT, "value is int (JSON float coerced per R1)")
	assert_eq(scrap.value, 2, "value round-trips as 2")
	# Combat-critical stats are int-typed for T7's deterministic sim.
	var boss: MonsterDef = lib.monster("sewer_landlord")
	assert_not_null(boss, "boss record resolves")
	assert_true(boss.is_boss, "boss flag round-trips")
	assert_eq(typeof(boss.max_hp), TYPE_INT, "monster max_hp is int")


func test_malformed_record_is_rejected_with_actionable_error() -> void:
	# Broken-record guarantee through the exact production code path: one
	# wrong-typed field in a mutated copy under user:// must be rejected with
	# record id + field + reason (mirror of probe_content defect 1).
	var dir := DirAccess.make_dir_recursive_absolute("user://t12_gut/broken")
	assert_true(dir == OK, "fixture dir created")
	for file_name in ProbeContent.DOMAIN_FILES:
		var text := FileAccess.get_file_as_string("res://data/%s" % file_name)
		assert_true(text != "", "fixture source readable: %s" % file_name)
		if file_name == "items.json":
			var doc: Dictionary = JSON.parse_string(text)
			doc["items"][0]["value"] = "lots"  # string where a number is required
			text = JSON.stringify(doc, "\t")
		var write := FileAccess.open("user://t12_gut/broken/%s" % file_name, FileAccess.WRITE)
		assert_not_null(write, "fixture writable: %s" % file_name)
		if write == null:
			return
		write.store_string(text)
		write.close()
	var result := ContentLoader.load_all("user://t12_gut/broken")
	assert_false(result.ok(), "wrong-typed value is rejected (ok() == false)")
	assert_null(result.library, "rejected set hydrates no library")
	var joined := "\n".join(result.errors)
	assert_true(joined.contains("items[0] (id=scrap_metal)"), "error names the record")
	assert_true(joined.contains("value: must be a number, got String ('lots')"),
		"error names field + reason")
	# Tidy the fixture.
	var cleanup := DirAccess.open("user://t12_gut/broken")
	if cleanup != null:
		for file_name in ProbeContent.DOMAIN_FILES:
			cleanup.remove(file_name)
	var parent := DirAccess.open("user://t12_gut")
	if parent != null:
		parent.remove("broken")
