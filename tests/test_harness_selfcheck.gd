extends GutTest
## tests/test_harness_selfcheck.gd — T12 harness self-check + exit-code drill.
##
## Proves the harness end-to-end from inside the suite:
##   - the GUT addon is present and the plugin is enabled in project.godot;
##   - the R2 load-bearing patterns work under this binary: float-tolerance
##     asserts (assert_almost_eq, for T13 closed-form offline math) and seeded
##     RandomNumberGenerator reproducibility (for T13 combat sims);
##   - the exit-code drill: this script shipped T12 with a deliberately
##     failing assertion (assert_eq(1, 2)) — ./run_tests.sh returned 1 — and
##     was then flipped to the passing form below, returning 0. Both runs are
##     logged verbatim in production-log.md (T12 entry): the runner's 0/1
##     contract is proven, not assumed.

func test_gut_addon_is_installed_and_enabled() -> void:
	assert_true(FileAccess.file_exists("res://addons/gut/gut_cmdln.gd"),
		"GUT CLI runner exists at addons/gut/gut_cmdln.gd")
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	assert_true(project_text.contains('enabled=PackedStringArray("res://addons/gut/plugin.cfg")'),
		"project.godot enables the GUT editor plugin")


func test_float_tolerance_asserts_work() -> void:
	# R2: assert_almost_eq is the closed-form idle-math pattern for T13
	# (tick accumulation vs closed form must agree within tolerance).
	var tick_sum := 0.0
	for i in 10:
		tick_sum += 0.1
	assert_almost_eq(tick_sum, 1.0, 0.000001, "10 x 0.1 accumulates to ~1.0")


func test_seeded_rng_is_reproducible() -> void:
	# R2: engine RNG seeding is the determinism mechanism T13 combat sims rely on.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 48763
	b.seed = 48763
	var draws_a: Array[int] = []
	var draws_b: Array[int] = []
	for i in 25:
		draws_a.append(a.randi_range(1, 10000))
		draws_b.append(b.randi_range(1, 10000))
	assert_eq(draws_a, draws_b, "same seed -> identical randi_range sequence")


func test_exit_code_drill_flipped_to_pass() -> void:
	# Deliberate FAIL case flipped to pass: shipped T12 first as
	# assert_eq(1, 2, ...) — ./run_tests.sh returned 1 — then flipped to the
	# form below, returning 0. Both exit codes are logged verbatim in
	# production-log.md (T12 entry): the 0/1 contract is proven, not assumed.
	assert_eq(2, 1 + 1, "T12 drill: originally assert_eq(1, 2) to prove EXIT 1")
