extends GutTest
## tests/test_resilience.gd — T14 adversarial hardening pass (Hulk lane:
## everything fails eventually). Every class of failure the plan's T14 entry
## names gets a pin here:
##   (a) fmt big numbers: exact grouping below 10^15, int-math suffixes at
##       10^15+ (Q/QI), full int64 range incl. the INT64_MIN absi() edge,
##       zero-int-artifact sweep over every display form
##   (b) clock semantics: anchors are UTC epoch ms — DST transitions are not
##       special (pure epoch arithmetic, pinned across the real 2026 America/
##       New_York spring-forward and fall-back instants); a 12 h mid-session
##       stall clamps + records without ever double-counting against the save
##       anchor
##   (c) zero/negative guards: loader rejects zero/negative intervals; zero-
##       food combat death halts at 0 HP with zero loss; selling to zero;
##       buying at the exactly-affordable boundary; divide-by-zero sweep
##   (d) big-int state: crowns/xp/stacks past the 2^53 JSON cliff ship as
##       strings and round-trip bit-exact (the RNG convention, swept to ALL
##       unbounded player ints)
##   (e) XP level-99 cap: level clamps at 99 while lifetime XP keeps
##       accumulating exactly — never frozen, never overflowing
##   (f) MAX_OFFLINE_EVENTS honest truncation: the payload flag exists, is
##       reachable (through the documented test seam), and MailCallModal
##       surfaces it as a stamped line
##   (g) 50-iteration save-corruption fuzz (seeded, deterministic): random
##       truncation / byte flips / garbage / valid-JSON-wrongness against
##       primary + backups — never a crash, always a recovery or an honest
##       fresh-with-notice
##   (h) serialization latches: a filing during a resolving load and a
##       re-entrant filing from inside save_completed are both refused
##   (i) the T9-flagged gallery zero-height fix (deviation 6): every
##       content-bearing gallery plate lays out with real height

const SaveStoreScript := preload("res://scripts/autoload/save_store.gd")
const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")
const GalleryScene := preload("res://scenes/dev/theme_gallery.tscn")

const SEED := 20260915
const NOW := 1_769_000_000_000
const INT64_MAX := 9_223_372_036_854_775_807
const INT64_MIN := -9_223_372_036_854_775_807 - 1
const CLIFF := 9_007_199_254_740_993  ## 2^53 + 1 — first int JSON loses
const TWELVE_H := 43_200_000
const SIX_H := 21_600_000
## Real America/New_York DST instants (UTC epoch ms): 2026-03-08 07:00Z is
## 02:00 EST -> 03:00 EDT (spring); 2026-11-01 06:00Z is 02:00 EDT -> 01:00
## EST (fall). Anchors are UTC epoch ms (Time.get_unix_time_from_system), so
## local-time jumps must never appear in the elapsed math.
const DST_SPRING_MS := 1_772_953_200_000
const DST_FALL_MS := 1_793_512_800_000


# ------------------------------------------------------------------ helpers --

func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (resilience tests run on live data")
	return result.library


func _make_tm() -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)
	tm._boot(_lib(), SEED)
	return tm


func _make_store(dir: String, tm: Variant, now := NOW) -> Variant:
	var store: Variant = SaveStoreScript.new()
	autofree(store)
	store._boot(dir, tm, now)
	return store


func _pump(tm: Variant, total_ms: int, chunk_ms := 500) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _tmp_dir(label: String) -> String:
	return OS.get_temp_dir().path_join("t14_%s_%d_%d" % [
		label, int(Time.get_unix_time_from_system() * 1000.0), randi() % 100000])


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.flush()
	f.close()


# ---------------------------------------------------------------------------
# (a) fmt — big numbers, int64 edges, zero artifacts
# ---------------------------------------------------------------------------

func test_fmt_exact_grouping_below_suffix_threshold() -> void:
	assert_eq(SignageFmt.num(0), "0")
	assert_eq(SignageFmt.num(999_999_999), "999,999,999",
		"the 999,999,999-Crown class stays exact grouped commas")
	assert_eq(SignageFmt.num(-1_234_567), "-1,234,567")
	assert_eq(SignageFmt.num(999_999_999_999_999), "999,999,999,999,999",
		"last exact value before the suffix threshold")


func test_fmt_suffix_form_from_quadrillion_up() -> void:
	assert_eq(SignageFmt.num(1_000_000_000_000_000), "1.000Q")
	assert_eq(SignageFmt.num(2_470_123_456_789_012), "2.470Q",
		"suffix decimals TRUNCATE (2.470…012 understates, never rounds up)")
	assert_eq(SignageFmt.num(-2_470_123_456_789_012), "-2.470Q")
	assert_eq(SignageFmt.num(999_999_999_999_999_999), "999.999Q")
	assert_eq(SignageFmt.num(INT64_MAX), "9.223QI", "int64 max renders in QI")
	assert_eq(SignageFmt.num(INT64_MIN), "-9.223QI",
		"int64 min: no absi() overflow, no double-dash")


func test_fmt_seconds_is_int_math_exact() -> void:
	assert_eq(SignageFmt.seconds(3_000), "3.0")
	assert_eq(SignageFmt.seconds(7_500), "7.5")
	assert_eq(SignageFmt.seconds(1), "0.0")
	assert_eq(SignageFmt.seconds(-1_500), "-1.5")
	assert_eq(SignageFmt.seconds(CLIFF), "9007199254740.9",
		"2^53+1 ms is exact (float division would print ...409.0 or worse)")


func test_fmt_zero_and_guard_sweep() -> void:
	assert_eq(SignageFmt.pct(7, 0), "0", "pct with zero total guards to 0")
	assert_eq(SignageFmt.pct(0, 0), "0")
	assert_eq(SignageFmt.pct(1, 16), "6.3", "non-zero control still exact")
	assert_eq(SignageFmt.duration(0), "0S")
	assert_eq(SignageFmt.duration(TWELVE_H), "12H 00M")
	assert_eq(SignageFmt.delta(INT64_MIN), "-9223372036854775808",
		"delta prints the exact int64 string")


## Every num() output over the whole range is one of the two mono-safe shapes
## — no scientific notation, no float artifacts, no runaway digit runs.
func test_fmt_corpus_is_mono_safe() -> void:
	var corpus: Array[int] = [0, 1, 999, 1_000, 999_999, 1_000_000, 1_000_000_000,
		CLIFF - 1, CLIFF, CLIFF + 1, 999_999_999_999_999, 1_000_000_000_000_000,
		1_000_000_000_000_001, 999_999_999_999_999_999, INT64_MAX - 1, INT64_MAX,
		INT64_MIN]
	var grouped := RegEx.create_from_string("^-?\\d{1,3}(,\\d{3})*$")
	var suffix := RegEx.create_from_string("^-?\\d{1,3}\\.\\d{3}QI?$")
	for v in corpus:
		var text := SignageFmt.num(v)
		assert_true(grouped.search(text) != null or suffix.search(text) != null,
			"num(%d) is mono-safe: %s" % [v, text])
		assert_false(text.contains("e+"), "no scientific notation in %s" % text)
		assert_false(text.contains(".0."), "no stacked decimals in %s" % text)


# ---------------------------------------------------------------------------
# (b) clock semantics — UTC anchors, DST, mid-session stalls
# ---------------------------------------------------------------------------

## Anchors are UTC epoch ms (Time.get_unix_time_from_system), so a wall hour
## that contains a DST transition is still exactly one elapsed hour — the
## elapsed math is a pure subtraction of two UTC ints and never consults local
## time. Pinned across both real 2026 America/New_York transition instants.
func test_offline_elapsed_is_pure_utc_epoch_arithmetic_across_dst() -> void:
	# One hour ending exactly at the spring-forward instant, and one hour
	# starting exactly at it: both are exactly 3,600,000 ms.
	assert_eq(TickManager.compute_offline_elapsed_ms(
		DST_SPRING_MS - 3_600_000, DST_SPRING_MS), 3_600_000,
		"hour INTO the spring-forward instant: exact")
	assert_eq(TickManager.compute_offline_elapsed_ms(
		DST_SPRING_MS, DST_SPRING_MS + 3_600_000), 3_600_000,
		"hour OUT OF the spring-forward instant: exact (local clocks jumped)")
	assert_eq(TickManager.compute_offline_elapsed_ms(
		DST_FALL_MS, DST_FALL_MS + 3_600_000), 3_600_000,
		"the repeated local hour at fall-back is still one UTC hour")
	# A save written the day BEFORE the transition, loaded the day AFTER:
	# elapsed = plain day of UTC, DST never enters it.
	assert_eq(TickManager.compute_offline_elapsed_ms(
		DST_SPRING_MS - 86_400_000, DST_SPRING_MS + 86_400_000), 172_800_000,
		"day spanning a transition is exactly one UTC day")
	# Backwards stays clamped at zero (the T6/T3 guard, re-pinned at the edge).
	assert_eq(TickManager.compute_offline_elapsed_ms(
		DST_FALL_MS + 3_600_000, DST_FALL_MS), 0,
		"clock running backwards across a transition yields zero, not negative")


## The same property through the full save -> load -> gains pipeline: a gap
## whose endpoints straddle a DST transition grants exactly the UTC-elapsed
## production (identical to a twin fed the same elapsed directly).
func test_dst_straddling_save_load_grants_exact_utc_gap() -> void:
	var dir := _tmp_dir("dst")
	var tm1: Variant = _make_tm()
	assert_true(tm1.start_activity("sort_scrap_pile")["ok"])
	_pump(tm1, 30_000)
	var store: Variant = _make_store(dir, tm1, DST_SPRING_MS - 3_600_000)
	assert_true(store.save_now(DST_SPRING_MS - 3_600_000)["ok"])

	var tm2: Variant = _make_tm()
	_make_store(dir, tm2, DST_SPRING_MS + 3_600_000)  # loads across the jump
	assert_eq(int(tm2.state.last_mail_call.get("elapsed_ms", -1)), 7_200_000,
		"elapsed is the UTC gap (2 h), not the 3 h a local clock would show")

	var twin: Variant = _make_tm()
	assert_true(twin.start_activity("sort_scrap_pile")["ok"])
	_pump(twin, 30_000)
	twin.apply_offline_elapsed(7_200_000)
	assert_eq(tm2.state.skills_xp, twin.state.skills_xp,
		"DST-straddling load == twin fed the exact UTC gap")


## System sleep mid-session: the funnel clamps a 12 h single-frame stall to
## its 2.5 s catch-up budget, records the drop, and the dropped time can never
## re-enter through the save anchor (offline math runs only on post-anchor
## wall time — the two mechanisms cannot double-count).
func test_mid_session_12h_stall_clamps_records_and_never_double_counts() -> void:
	var tm: Variant = _make_tm()
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	_pump(tm, 5_000)
	var ticks_before: int = int(tm.stats["ticks_executed"])
	var xp_before: int = int(tm.state.skills_xp["scavenging"])

	tm.advance_wall_ms(TWELVE_H)  # the sleep: one giant inter-frame delta
	assert_eq(int(tm.stats["ticks_executed"]), ticks_before + 25,
		"exactly MAX_CATCHUP_TICKS_PER_FRAME (25) sim ticks served the stall")
	assert_eq(int(tm.stats["clamped_stalls"]), 1, "the clamp fired and recorded")
	assert_eq(int(tm.stats["last_clamp_dropped_ms"]), TWELVE_H - 2_500,
		"12 h minus the served 2.5 s is recorded as dropped")
	assert_eq(int(tm.stats["total_dropped_ms"]), TWELVE_H - 2_500, "total tracks it")
	assert_true(int(tm.state.skills_xp["scavenging"]) > xp_before,
		"the served 2.5 s of catch-up still produced gains")

	# File a record at the moment the stall resolved; the anchor is NOW.
	var dir := _tmp_dir("stall")
	var store: Variant = _make_store(dir, tm, NOW)
	assert_true(store.save_now(NOW)["ok"])

	# Reload at the same wall moment: zero offline math on top of the stall.
	var tm2: Variant = _make_tm()
	_make_store(dir, tm2, NOW)
	assert_eq(int(tm2.state.last_mail_call.get("elapsed_ms", -1)), 0,
		"immediate reload: no offline math stacked onto the clamped stall")
	assert_eq(tm2.state.skills_xp, tm.state.skills_xp, "state identical to the stalling session")

	# Reload six real hours later: exactly 6 h of offline math — the 12 h the
	# funnel dropped is NOT smuggled back in through the anchor.
	var tm3: Variant = _make_tm()
	_make_store(dir, tm3, NOW + SIX_H)
	assert_eq(int(tm3.state.last_mail_call.get("elapsed_ms", -1)), SIX_H,
		"post-stall offline gap is exactly the post-anchor wall time")

	# Paranoia: an absurd inter-frame delta also clamps without overflowing.
	var tm4: Variant = _make_tm()
	tm4.advance_wall_ms(9_000_000_000_000_000)  # ~285 years in one frame
	assert_eq(int(tm4.stats["clamped_stalls"]), 1, "absurd delta clamps once")
	assert_eq(int(tm4.stats["ticks_executed"]), 25, "still only 25 ticks")


# ---------------------------------------------------------------------------
# (c) zero/negative guards
# ---------------------------------------------------------------------------

## Data has no zero/negative intervals — pin that the loader keeps it that
## way (fail-loud, actionable), across every field the engines divide by.
func test_loader_rejects_zero_and_negative_intervals() -> void:
	var cases: Array = [
		["activities.json", "activities", "interval_ms", 0],
		["recipes.json", "recipes", "interval_ms", -100],
		["monsters.json", "monsters", "attack_speed_ms", 0],
		["equipment.json", "equipment", "attack_speed_ms", -1],
	]
	for case in cases:
		var dir := DirAccess.make_dir_recursive_absolute(
			"user://t14_gut/zero_interval")
		assert_true(dir == OK, "fixture dir created")
		var file_name: String = case[0]
		var key: String = case[1]
		var field: String = case[2]
		var bad_value: int = case[3]
		for src in ["items", "skills", "activities", "recipes", "drop_tables",
				"monsters", "equipment", "shop_stock", "xp_curves"]:
			var path := "res://data/%s.json" % src
			var text := FileAccess.get_file_as_string(path)
			if src + ".json" == file_name:
				var doc: Dictionary = JSON.parse_string(text)
				doc[key][0][field] = bad_value
				text = JSON.stringify(doc, "\t")
			var w := FileAccess.open("user://t14_gut/zero_interval/%s.json" % src, FileAccess.WRITE)
			assert_not_null(w, "fixture writable: %s" % src)
			if w == null:
				return
			w.store_string(text)
			w.close()
		var result := ContentLoader.load_all("user://t14_gut/zero_interval")
		assert_false(result.ok(), "%s %s=%d is rejected" % [file_name, field, bad_value])
		var joined := "\n".join(result.errors)
		assert_true(joined.contains("%s[0]" % key), "error names the record (%s)" % joined)
		assert_true(joined.contains("must be between 100 and 600000"),
			"error states the interval bound (%s)" % joined)
		var cleanup := DirAccess.open("user://t14_gut/zero_interval")
		if cleanup != null:
			for src in ["items", "skills", "activities", "recipes", "drop_tables",
					"monsters", "equipment", "shop_stock", "xp_curves"]:
				cleanup.remove("%s.json" % src)


## A save carrying a zero-interval slot (the _due_count division) is rejected
## by load validation — backups/fresh take over, never a divide-by-zero.
func test_save_validation_rejects_zero_interval_slot() -> void:
	var dir := _tmp_dir("zeroSlot")
	var tm: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm, NOW)
	assert_true(tm.start_activity("sort_scrap_pile")["ok"])
	_pump(tm, 1_000)
	assert_true(store.save_now(NOW)["ok"])
	var doc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	doc["engine"]["active"]["scavenging"]["interval_ms"] = 0
	_write(dir.path_join("save.json"), JSON.stringify(doc, "\t"))

	var tm2: Variant = _make_tm()
	var noticed: Array = []
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2.notice_raised.connect(func(kind: String, _d: Dictionary) -> void: noticed.append(kind))
	store2._boot(dir, tm2, NOW)
	assert_eq(int(tm2.state.active.size()), 0,
		"zero-interval slot never hydrates (fresh engine state)")
	assert_true(noticed.is_empty() or noticed[0] == "all_saves_corrupt_fresh_state",
		"the malformed save surfaces as corruption notice, not a crash: %s" % str(noticed))


## Zero food, zero inventory, no gear: the fight runs, death halts at exactly
## 0 HP, nothing is lost, the log never goes negative, and re-engaging works.
func test_zero_food_combat_death_halts_with_zero_loss() -> void:
	var tm: Variant = _make_tm()
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # clearance 14 (boss gate)
	assert_true(tm.engage_monster("sewer_landlord")["ok"],
		"boss engages at clearance 14 with an empty Manifest")
	assert_eq(tm.state.inventory.size(), 0, "zero-food precondition: truly empty")

	var ended: Array = []
	tm.combat_ended.connect(func(result: Dictionary) -> void: ended.append(result))
	_pump(tm, 120_000)  # ~2 min of sim: the no-food boss fight is unwinnable
	assert_eq(ended.size(), 1, "the fight ended exactly once")
	assert_eq(String(ended[0]["outcome"]), "death", "it ended in death")
	assert_eq(int(ended[0]["eaten"]), 0, "nothing was ever eaten (there was nothing)")
	assert_eq(str(tm.state.combat["phase"]), "dead", "phase dead: RETURN TO SHELTER")
	assert_eq(int(tm.state.combat["p_hp"]), 0, "HP halts at exactly 0, never negative")
	assert_eq(tm.state.inventory.size(), 0, "zero loss: inventory still empty")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), 8_340,
		"zero loss: banked xp untouched by death")

	var xp_at_death: int = int(tm.state.skills_xp["wasteland_combat"])
	var hp_at_death: int = int(tm.state.combat["p_hp"])
	_pump(tm, 60_000)  # the dead fight must stay halted — no zombie swings
	assert_eq(int(tm.state.combat["p_hp"]), hp_at_death, "no further damage after death")
	assert_eq(int(tm.state.skills_xp["wasteland_combat"]), xp_at_death, "no further xp after death")
	assert_true(tm.engage_monster("junkyard_roach")["ok"], "re-engage works after death")


## Selling to zero and clamping, buying at the exactly-affordable edge.
func test_depot_sell_to_zero_and_buy_at_exact_boundary() -> void:
	var tm: Variant = _make_tm()

	# SELL: over-asking quantity clamps to the stack, then the entry erases.
	tm.state.add_item("scrap_metal", 3)
	var res: Dictionary = tm.depot_sell("scrap_metal", 5)
	assert_true(res["ok"], "over-ask sell settles the clamped stack")
	assert_eq(int(res["qty"]), 3, "sold exactly what was on hand (mini clamp)")
	assert_eq(int(res["crowns"]), 6, "3 x value 2 = 6 Crowns")
	assert_false(tm.state.inventory.has("scrap_metal"), "stack erased at zero (no 0-entry)")
	var res2: Dictionary = tm.depot_sell("scrap_metal", 1)
	assert_false(res2["ok"], "selling from zero is refused")
	assert_eq(String(res2["reason"]), "NOTHING TO SELL")
	assert_eq(int(tm.state.crowns), 6, "wallet unchanged by the refusal")
	assert_false(tm.depot_sell("unobtanium")["ok"], "unknown item refused")

	# SELL ALL (qty <= 0 tenders the whole stack).
	tm.state.add_item("cloth_scraps", 4)
	var res3: Dictionary = tm.depot_sell("cloth_scraps", 0)
	assert_true(res3["ok"] and int(res3["qty"]) == 4, "qty<=0 tenders everything")

	# BUY at the exactly-affordable boundary: glowshroom, 6 Crowns, ungated.
	tm.state.crowns = 6
	assert_eq(tm.depot_max_affordable("glowshroom"), 1, "6 Crowns affords exactly 1")
	var buy: Dictionary = tm.depot_buy("glowshroom", 1)
	assert_true(buy["ok"], "exactly-affordable buy succeeds")
	assert_eq(int(tm.state.crowns), 0, "wallet lands at exactly 0")
	assert_false(tm.depot_buy("glowshroom", 1)["ok"], "one past the boundary is refused")
	assert_eq(int(tm.state.crowns), 0, "refusal leaves the empty wallet at 0")
	assert_eq(tm.state.item_count("glowshroom"), 1, "the refused buy granted nothing")

	# BUY MAX at an exact multiple: 20 = 3x6 + 2, then 18 = exact 3x6.
	tm.state.crowns = 20
	assert_eq(tm.depot_max_affordable("glowshroom"), 3)
	assert_true(tm.depot_buy("glowshroom", 3)["ok"])
	assert_eq(int(tm.state.crowns), 2, "max buy leaves the remainder")
	tm.state.crowns = 18
	var max_n: int = tm.depot_max_affordable("glowshroom")
	assert_eq(max_n, 3, "exact multiple: 18/6 == 3")
	assert_true(tm.depot_buy("glowshroom", max_n)["ok"])
	assert_eq(int(tm.state.crowns), 0, "exact-multiple max buy lands at 0")

	# Quantity guards.
	assert_false(tm.depot_buy("glowshroom", 0)["ok"], "qty 0 refused")
	assert_false(tm.depot_buy("glowshroom", -2)["ok"], "negative qty refused")
	assert_eq(tm.depot_max_affordable("glowshroom"), 0, "broke wallet affords 0 (0/n is guarded)")


## Divide-by-zero sweep over the guarded engine/fmt paths.
func test_divide_by_zero_sweep() -> void:
	assert_eq(CombatSession.hit_chance_bp(0, 0), 5_000,
		"zero accuracy + zero evasion guards to the equal-stats center")
	assert_eq(CombatSession.hit_chance_bp(30, 10), 7_500,
		"control: normal stats still harmonic (30*10000/40)")
	var curve: XpCurveDef = _lib().xp_curve("standard_99")
	assert_eq(curve.xp_to_next(99), 0, "xp_to_next at the 99 cap is 0 (UI wraps maxi)")
	assert_eq(curve.xp_to_next(1) > 0, true)
	assert_eq(curve.level_for_total_xp(0), 1)
	assert_eq(curve.level_for_total_xp(10_000_000_000_000_000), 99,
		"absurd xp still derives level 99 (loop is cap-bounded, not xp-bounded)")
	var tm: Variant = _make_tm()
	assert_eq(tm.depot_max_affordable("glowshroom"), 0, "max affordable at 0 crowns")
	tm.state.crowns = 0
	assert_false(tm.depot_buy("glowshroom", 1)["ok"], "0-crowns buy refused, no div issues")


# ---------------------------------------------------------------------------
# (d) big-int state through the save pipeline
# ---------------------------------------------------------------------------

## Crowns / lifetime XP / inventory stacks past the 2^53 JSON cliff ship as
## strings, validate on the way back in, and round-trip bit-exact — the RNG
## convention swept to every unbounded player int. Small values keep their
## historical numeric shape.
func test_big_int_state_round_trips_past_the_json_cliff() -> void:
	var dir := _tmp_dir("bigint")
	var tm: Variant = _make_tm()
	const BIG_XP := 9_007_199_254_740_997  # 2^53 + 5, odd: the cliff's first casualty class
	const BIG_STACK := 4_611_686_018_427_387_903  # < 2^62, odd on purpose
	tm.state.crowns = CLIFF
	tm.state.skills_xp["scavenging"] = BIG_XP
	tm.state.add_item("scrap_metal", BIG_STACK)
	tm.state.add_item("glowshroom", 5)  # small value stays numeric
	var store: Variant = _make_store(dir, tm, NOW)
	assert_true(store.save_now(NOW)["ok"], "filing succeeds with cliff-scale ints")

	var doc: Dictionary = JSON.parse_string(_read(dir.path_join("save.json")))
	assert_eq(typeof(doc["engine"]["crowns"]), TYPE_STRING,
		"crowns past 2^53 ships as a string")
	assert_eq(String(doc["engine"]["crowns"]), str(CLIFF), "... exact digits")
	assert_eq(typeof(doc["engine"]["skills_xp"]["scavenging"]), TYPE_STRING,
		"cliff-scale xp ships as a string")
	assert_eq(typeof(doc["engine"]["inventory"]["scrap_metal"]), TYPE_STRING,
		"cliff-scale stack ships as a string")
	assert_eq(typeof(doc["engine"]["inventory"]["glowshroom"]), TYPE_FLOAT,
		"small stack keeps the numeric shape (JSON numbers parse as float)")

	var tm2: Variant = _make_tm()
	var store2: Variant = _make_store(dir, tm2, NOW)  # validates + adopts
	assert_eq(String(store2.load_report["loaded_from"]), "save.json",
		"the big-int save loads from the primary (validation accepts the string form)")
	assert_eq(int(tm2.state.crowns), CLIFF, "crowns round-trip EXACT (2^53+1 survives)")
	assert_eq(int(tm2.state.skills_xp["scavenging"]), BIG_XP, "xp round-trip exact")
	assert_eq(int(tm2.state.inventory["scrap_metal"]), BIG_STACK, "stack round-trip exact")
	assert_eq(int(tm2.state.inventory["glowshroom"]), 5, "small stack round-trip exact")
	assert_eq(int(tm2.state.skills_level["scavenging"]), 99, "level re-derived at the cap")


# ---------------------------------------------------------------------------
# (e) XP level-99 cap
# ---------------------------------------------------------------------------

func test_xp_cap_clamps_level_and_keeps_accumulating_exactly() -> void:
	var tm: Variant = _make_tm()
	var curve: XpCurveDef = _lib().xp_curve("standard_99")
	var total_to_99: int = curve.total_xp_to_reach(99)
	assert_eq(curve.total_xp_to_reach(100), total_to_99,
		"total-to-reach clamps past the cap (100 == 99)")

	var levels: Array = []
	tm.level_up.connect(func(skill: String, _o: int, n: int) -> void: levels.append([skill, n]))
	# Live grant straight through the cap: level freezes at 99, xp keeps exact sum.
	tm.engine.grant_xp(tm.state, "scavenging", total_to_99)
	assert_eq(int(tm.state.skills_level["scavenging"]), 99, "exactly at the cap")
	assert_eq(levels.size(), 98, "one emission per crossing, none past 99")
	tm.engine.grant_xp(tm.state, "scavenging", 10_000_000_000_000_000)
	assert_eq(int(tm.state.skills_level["scavenging"]), 99, "level CLAMPED at 99 past the cap")
	assert_eq(levels.size(), 98, "no phantom level_up past 99")
	assert_eq(int(tm.state.skills_xp["scavenging"]), total_to_99 + 10_000_000_000_000_000,
		"lifetime xp keeps accumulating exactly (clamped level, growing truth)")

	# Offline at the cap: xp delta rides the payload, no levels entry appears.
	assert_true(tm.start_activity("sort_scrap_pile")["ok"], "a shift runs at the cap")
	var payload: Dictionary = tm.apply_offline_elapsed(30_000)
	assert_eq(int(payload["skills_xp"].get("scavenging", 0)), 100,
		"offline xp at the cap still grants (10 actions x 10 xp in 30 s)")
	assert_false(payload["levels"].has("scavenging"),
		"no level crossing reported for a capped skill")


## The capped gauge renders "MAXIMUM GRADE" with suffix-form lifetime xp —
## the big-number display path through a real bound docket.
func test_capped_gauge_displays_maximum_grade_with_suffix_xp() -> void:
	var tm: Variant = _make_tm()
	var curve: XpCurveDef = _lib().xp_curve("standard_99")
	tm.engine.grant_xp(tm.state, "scavenging", curve.total_xp_to_reach(99) + 1_234_567_890_123_456)
	var docket := DocketGathering.new("scavenging")
	add_child_autofree(docket)
	docket.bind(tm)
	assert_true(docket.gauge_read.text.contains("MAXIMUM GRADE"),
		"capped gauge copy: %s" % docket.gauge_read.text)
	assert_true(docket.gauge_read.text.contains("1.234Q"),
		"10^15-scale lifetime xp renders in suffix form on a real display path: %s"
		% docket.gauge_read.text)
	assert_eq(docket.gauge.value, 1.0, "capped gauge reads full")


# ---------------------------------------------------------------------------
# (f) MAX_OFFLINE_EVENTS honest truncation
# ---------------------------------------------------------------------------

## The truncation flag exists, is reachable, leaves the fight resumable, and
## MailCallModal renders it as a stamped line (T7's honest-truncation note).
func test_offline_event_budget_truncation_flag_surfaces() -> void:
	var tm: Variant = _make_tm()
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)
	tm.state.add_item("radstag_stew", 50)
	assert_true(tm.engage_monster("sewer_landlord")["ok"])
	_pump(tm, 1_000)
	tm.combat.offline_event_budget = 12  # documented T14 test seam
	var payload: Dictionary = tm.apply_offline_elapsed(SIX_H)
	assert_true(bool(payload["combat"].get("truncated", false)),
		"budget exhausted: payload flags truncation honestly")
	assert_eq(str(tm.state.combat["phase"]), "fighting",
		"the fight resumes live at the truncation point (no phantom stop)")
	var kills: int = int(payload["combat"].get("kills", 0))
	assert_true(kills >= 0, "kills count well-formed under truncation")

	# The modal posts the truncation line (and only when truncated).
	var lib := _lib()
	var modal := MailCallModal.new()
	add_child_autofree(modal)
	modal.present(payload, lib)
	var texts: Array[String] = []
	for child in modal.body_box.get_children():
		if child is Label:
			texts.append((child as Label).text)
	var joined := " | ".join(texts)
	assert_true(joined.contains("TRUNCATED"),
		"MAIL CALL surfaces the truncation flag: %s" % joined)

	var tm2: Variant = _make_tm()  # control: full budget, small gap -> no flag
	tm2.engine.grant_xp(tm2.state, "wasteland_combat", 8_340)
	tm2.state.add_item("radstag_stew", 50)
	assert_true(tm2.engage_monster("sewer_landlord")["ok"])
	var payload2: Dictionary = tm2.apply_offline_elapsed(30_000)
	assert_false(payload2.has("combat") and bool(payload2["combat"].get("truncated", false)),
		"no truncation flag when the budget holds")


# ---------------------------------------------------------------------------
# (g) save-corruption fuzz — 50 seeded iterations
# ---------------------------------------------------------------------------

## Random truncation / byte flips / garbage / valid-JSON-wrongness against
## primary + backups. Deterministic (fixed seed). Never a crash; every
## outcome is a load (primary/backup), a fresh-with-notice, or a version
## refusal; and recovery can always re-file.
func test_save_corruption_fuzz_50_iterations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5140  # fixed seed: the drill is reproducible
	var outcomes := {"primary": 0, "backup": 0, "fresh_corrupt": 0, "blocked": 0}
	for i in range(50):
		var dir := _tmp_dir("fuzz%d" % i)
		var tm: Variant = _make_tm()
		var store: Variant = _make_store(dir, tm, NOW)
		# 1-4 filings → a populated primary and a variably-full ring.
		for f in range(1 + rng.randi_range(0, 3)):
			tm.state.add_crowns(100 * (f + 1))
			assert_true(store.save_now(NOW + f * 1_000)["ok"], "iteration %d: filing %d" % [i, f])
		# Choose the damage set: primary only / +1 backup / +all backups / everything.
		var mode := rng.randi_range(0, 4)
		var targets: Array[String] = ["save.json"]
		match mode:
			1: targets.append("save.json.bak1")
			2:
				targets.append("save.json.bak1")
				targets.append("save.json.bak2")
			3:
				for bak in ["bak1", "bak2", "bak3"]:
					targets.append("save.json." + bak)
			4: targets = ["save.json", "save.json.bak1", "save.json.bak3"]
		for target in targets:
			if not FileAccess.file_exists(dir.path_join(target)):
				continue
			_damage_file(dir.path_join(target), rng)

		var tm2: Variant = _make_tm()
		var store2: Variant = SaveStoreScript.new()
		autofree(store2)
		var noticed: Array = []
		store2.notice_raised.connect(func(kind: String, _d: Dictionary) -> void: noticed.append(kind))
		store2._boot(dir, tm2, NOW + 10_000)  # the drill: load damaged media
		var from := String(store2.load_report["loaded_from"])
		if store2.save_blocked:
			outcomes["blocked"] += 1
			assert_true(noticed.has("refused_newer_save_version"),
				"iteration %d: refusal carries its notice" % i)
			continue  # a newer-version record must never be clobbered
		if from == "fresh-corrupt":
			outcomes["fresh_corrupt"] += 1
			assert_true(noticed.has("all_saves_corrupt_fresh_state"),
				"iteration %d: fresh carries the corruption notice" % i)
			assert_eq(int(tm2.state.crowns), 0, "iteration %d: fresh wallet" % i)
		elif from.begins_with("save.json.bak"):
			outcomes["backup"] += 1
			assert_true(noticed.has("primary_corrupt_backup_loaded"),
				"iteration %d: backup restore carries its notice" % i)
		else:
			outcomes["primary"] += 1
			assert_true(noticed.is_empty() or noticed[0] != "all_saves_corrupt_fresh_state",
				"iteration %d: a primary load raises no corruption notice" % i)
		assert_true(int(tm2.state.crowns) >= 0, "iteration %d: wallet sane" % i)
		# Recovery can always re-file, and the re-filed record reloads clean.
		var resave: Dictionary = store2.save_now(NOW + 20_000)
		assert_true(resave["ok"], "iteration %d: recovery re-files (%s)" % [i, str(resave)])
		var tm3: Variant = _make_tm()
		var store3: Variant = _make_store(dir, tm3, NOW + 20_000)
		assert_eq(String(store3.load_report["loaded_from"]), "save.json",
			"iteration %d: the recovery record loads from the primary" % i)
		assert_eq(store3.notice, {}, "iteration %d: clean reload after recovery" % i)
	assert_true(outcomes["primary"] + outcomes["backup"] + outcomes["fresh_corrupt"] > 0,
		"the drill exercised at least one non-refusal path: %s" % str(outcomes))
	print("T14 FUZZ OUTCOMES: ", outcomes)


func _damage_file(path: String, rng: RandomNumberGenerator) -> void:
	var text := _read(path)
	match rng.randi_range(0, 4):
		0:  # truncate at a random byte
			if text.length() > 10:
				_write(path, text.substr(0, rng.randi_range(1, text.length() - 1)))
		1:  # flip one random byte (printable, keeps it string-safe)
			if text.length() > 10:
				var at := rng.randi_range(0, text.length() - 1)
				var flip := char(rng.randi_range(32, 126))
				_write(path, text.substr(0, at) + flip + text.substr(at + 1))
		2:  # overwrite with garbage
			var garbage := ""
			for j in range(rng.randi_range(0, 200)):
				garbage += char(rng.randi_range(32, 126))
			_write(path, garbage)
		3:  # valid JSON, wrong shape
			var junk: Array = ["[]", "null", "{}", "{\"save_version\": \"x\"}",
				"[1, 2, 3]", "\"a string\""]
			_write(path, junk[rng.randi_range(0, junk.size() - 1)])
		4:  # valid save shape, impossible values
			var doc: Dictionary = {
				"save_version": 1, "meta": {"created_unix": 0, "updated_unix": 0, "playtime_s": 0},
				"anchor_unix_ms": 1e300, "engine": {"crowns": -5,
					"skills_xp": {"nosuchskill": 1e300}, "inventory": {},
					"active": {}, "world_seed": 1}}
			_write(path, JSON.stringify(doc))


# ---------------------------------------------------------------------------
# (h) serialization latches — no interleaved filings
# ---------------------------------------------------------------------------

## A filing attempted from inside load_or_fresh's notice chain (the only
## re-entrancy the main thread allows) is refused — the half-resolving state
## never reaches the disk.
func test_filing_during_load_is_refused() -> void:
	var dir := _tmp_dir("latch")
	var tm: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm, NOW)
	tm.state.add_crowns(10)
	assert_true(store.save_now(NOW + 1_000)["ok"])
	tm.state.add_crowns(5)
	assert_true(store.save_now(NOW + 2_000)["ok"])
	_write(dir.path_join("save.json"), "{\"save_version\": 1, \"engine\": {\"cr")

	var reentrant: Array = []
	var tm2: Variant = _make_tm()
	var store2: Variant = SaveStoreScript.new()
	autofree(store2)
	store2.notice_raised.connect(func(_kind: String, _d: Dictionary) -> void:
		# Worst-case handler: files a record mid-load.
		reentrant.append(store2.save_now(NOW + 3_000)))
	store2._boot(dir, tm2, NOW + 3_000)
	assert_eq(reentrant.size(), 1, "the notice fired once during load")
	assert_false(bool(reentrant[0]["ok"]), "the mid-load filing was refused")
	assert_true(String(reentrant[0]["reason"]).contains("load is still resolving"),
		"refusal names the latch: %s" % str(reentrant[0]))
	assert_false(FileAccess.file_exists(dir.path_join("save.json.tmp")),
		"no scratch file from the refused attempt")
	assert_eq(int(tm2.state.crowns), 10,
		"the backup restore itself was untouched by the refused filing")


## A filing re-entered from inside save_completed's handler chain is refused
## (the latch spans the emission) — the ring advances by exactly one.
func test_reentrant_filing_from_save_completed_is_refused() -> void:
	var dir := _tmp_dir("relatch")
	var tm: Variant = _make_tm()
	var store: Variant = _make_store(dir, tm, NOW)
	var reentrant: Array = []
	store.save_completed.connect(func(_result: Dictionary) -> void:
		if reentrant.is_empty():
			reentrant.append(store.save_now(NOW + 1_000)))
	assert_true(store.save_now(NOW + 1_000)["ok"], "the outer filing succeeds")
	assert_eq(reentrant.size(), 1, "the handler ran exactly once")
	assert_false(bool(reentrant[0]["ok"]), "the re-entrant filing was refused")
	assert_true(String(reentrant[0]["reason"]).contains("already in progress"),
		"refusal names the latch: %s" % str(reentrant[0]))
	assert_false(FileAccess.file_exists(dir.path_join("save.json.bak1")),
		"the ring advanced by exactly the one filing (no double rotation)")


# ---------------------------------------------------------------------------
# (i) gallery zero-height fix (T9 deviation 6, assigned to T14)
# ---------------------------------------------------------------------------

func test_gallery_plates_lay_out_with_real_height() -> void:
	var gallery := GalleryScene.instantiate() as Control
	assert_not_null(gallery, "gallery scene instantiates")
	add_child_autofree(gallery)
	for i in 3:
		await get_tree().process_frame
	var probes := {
		"Header": 100.0,
		"Header/HeaderMargin/HeaderColumn/HeaderRow/TitlePlate": 60.0,
		"Header/HeaderMargin/HeaderColumn/HeaderRow/HeaderNotice": 60.0,
		"GaugesPanel": 100.0,
		"MaterialsRow/SteelSpecimen": 60.0,
		"MaterialsRow/PaperSpecimen": 60.0,
		"MaterialsRow/DangerSpecimen": 60.0,
		"TypeRow/OnSteel": 100.0,
		"TypeRow/OnBone": 60.0,
		"TypeRow/OnNavy": 60.0,
		"TypeRow/OnPaper": 60.0,
		"TypeRow/OnRed": 60.0,
	}
	var column := gallery.get_node("Margins/Scroll/Column") as Control
	for path in probes:
		var node := column.get_node_or_null(path) as Control
		assert_not_null(node, "gallery node exists: %s" % path)
		if node == null:
			continue
		assert_true(node.size.y >= float(probes[path]),
			"%s lays out with real height (%.0f px, was 0 before the T14 fix)"
			% [path, node.size.y])
	assert_true(column.size.y > 1500.0,
		"the wall scrolls a real document (%.0f px tall)" % column.size.y)
