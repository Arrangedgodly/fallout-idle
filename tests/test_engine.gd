extends GutTest
## tests/test_engine.gd — T6 idle engine core validation (Thor lane).
##
## Covers the T6 acceptance matrix headless, against LIVE content (res://data
## through the production ContentLoader — same convention as
## test_content_load.gd):
##   (a) 1 h live sim (36,000 ticks @ 10 Hz, seeded) == closed-form offline
##       math for the same elapsed ms — item/xp totals EXACTLY equal.
##   (b) drift: 10 min with forced frame jitter (random 0–200 ms deltas)
##       still matches closed form exactly; a >budget stall clamps + records.
##   (c) clearance gates + per-level level_up signal + gate re-evaluation.
##   (d) offline: 6 h closed form == 6 h seeded sim (incl. a stockpile-capped
##       recipe slot); clock backwards → zero elapsed, no negative gains.
##   (e) performance: 60 s windowed run — bulk signal count <= 4 Hz budget,
##       per-tick wall time recorded + asserted under threshold.
## Plus unit coverage: UpdateBatcher gating, PlayerState round-trip (level
## repair), mail-call payload shape, currency guards, autoload wiring.
##
## Determinism: every sim uses a fresh TickManager instance booted with an
## explicit seed via _boot() and never added to the scene tree, so _process
## never fires and advance_wall_ms() is the only clock input.

const TickManagerScript := preload("res://scripts/autoload/tick_manager.gd")

const SEED_A := 424242
const SEED_6H := 90210
const HOUR_MS := 3_600_000
const SIX_HOURS_MS := 21_600_000
const TEN_MIN_MS := 600_000
const SIXTY_S_MS := 60_000
const TICK_MS := 100


func _lib() -> ContentLibrary:
	var result = ContentLoader.load_all()
	assert_not_null(result.library, "content loads (engine tests run on live data)")
	return result.library


func _make_tm(seed: int) -> Variant:
	var tm: Variant = TickManagerScript.new()
	autofree(tm)  # bare Nodes leak without this (GUT orphan discipline)
	tm._boot(_lib(), seed)
	return tm


## T17: pre-rule concurrency scenarios (multi-slot sim twins) staff the full
## establishment through the state seam — the run-2 new game opens ONE
## posting (the purchase flow itself is tests/test_staffing.gd's subject).
func _full_staff(tm: Variant) -> void:
	tm.engine.ensure_staffing(tm.state)
	tm.state.staffing["deputies"] = 4


## Feed exactly `total_ms` through the public wall funnel in equal chunks.
func _pump(tm: Variant, total_ms: int, chunk_ms: int) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(chunk_ms, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _assert_xp_match(a: Dictionary, b: Dictionary, label: String) -> void:
	for skill_id in a:
		assert_eq(int(a[skill_id]), int(b.get(skill_id, -1)),
			"%s: skill '%s' lifetime xp equal (sim vs closed form)" % [label, skill_id])
	assert_eq(a.size(), b.size(), "%s: same skill count" % label)


func _assert_inventory_match(a: Dictionary, b: Dictionary, label: String) -> void:
	for item_id in a:
		assert_eq(int(a[item_id]), int(b.get(item_id, -1)),
			"%s: item '%s' stack equal (sim vs closed form)" % [label, item_id])
	assert_eq(a.size(), b.size(),
		"%s: same item variety (%s vs %s)" % [label, str(a.keys()), str(b.keys())])


# ---------------------------------------------------------------------------
# (c) gates + level-ups (cheap primitives first)
# ---------------------------------------------------------------------------

func test_new_state_shape() -> void:
	var tm: Variant = _make_tm(SEED_A)
	assert_eq(tm.state.skills_xp.size(), 5, "all five slice skills present")
	for skill_id in tm.state.skills_xp:
		assert_eq(int(tm.state.skills_xp[skill_id]), 0, "%s starts at 0 xp" % skill_id)
		assert_eq(int(tm.state.skills_level[skill_id]), 1, "%s starts at level 1" % skill_id)
	assert_true(tm.state.inventory.is_empty(), "Manifest starts empty")
	assert_eq(tm.state.crowns, 0, "wallet starts empty")
	assert_eq(tm.sim_time_ms, 0, "sim clock starts at 0")


func test_gate_blocks_and_level_up_unlocks() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var events: Array = []
	tm.level_up.connect(func(skill_id: String, old_level: int, new_level: int) -> void:
		events.append([skill_id, old_level, new_level]))

	# Clearance gate: Strip a Wreck needs Scavenging 5.
	var blocked: Dictionary = tm.start_activity("strip_wreck")
	assert_false(blocked["ok"], "gated activity refuses to start")
	assert_true(String(blocked["reason"]).contains("CLEARANCE 5"),
		"gate error carries CLEARANCE wording: %s" % str(blocked["reason"]))
	assert_false(tm.engine.is_unlocked(tm.state, "strip_wreck"), "is_unlocked agrees the gate is shut")
	assert_eq(tm.engine.gate_of("strip_wreck"), {"skill": "scavenging", "level": 5},
		"gate_of exposes the clearance for T10 plates")

	# Tier-1 gathering: 10 xp / 3 s → level 2 exactly at the 2nd action (6 s).
	var started: Dictionary = tm.start_activity("sort_scrap_pile")
	assert_true(started["ok"], "tier-1 activity starts at level 1: %s" % str(started))
	_pump(tm, 6_100, TICK_MS)  # 61 ticks → 2 actions completed (due at 3000, 6000)
	assert_eq(int(tm.state.skills_xp["scavenging"]), 20, "exactly 2 actions of xp at 6.1 s")
	assert_eq(int(tm.state.skills_level["scavenging"]), 2, "level 2 at 20 xp (curve step 1 = 20)")
	assert_eq(events.size(), 1, "exactly one level-up so far (immediate, not batched)")
	assert_eq(events[0], ["scavenging", 1, 2], "level_up args are (skill, old, new)")
	assert_false(tm.engine.is_unlocked(tm.state, "strip_wreck"), "still locked at level 2")

	# Level 5 → gate opens; starting a new activity on the skill replaces the slot.
	tm.engine.grant_xp(tm.state, "scavenging", 425 - 20)  # total 425 xp = level 5
	assert_true(tm.engine.is_unlocked(tm.state, "strip_wreck"), "CLEARANCE 5 opens at level 5")
	var stopped_events: Array = []
	tm.activity_stopped.connect(func(_s: String, _c: String, reason: String) -> void:
		stopped_events.append(reason))
	var switched: Dictionary = tm.start_activity("strip_wreck")
	assert_true(switched["ok"], "switching to the gated activity works")
	assert_eq(stopped_events, ["replaced"], "old slot stops with reason 'replaced'")


func test_level_up_counts_match_curve() -> void:
	var tm: Variant = _make_tm(SEED_A)
	var count := {"n": 0}
	tm.level_up.connect(func(_s: String, _o: int, _n: int) -> void: count["n"] = int(count["n"]) + 1)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, HOUR_MS, 1_000)
	# 1200 actions * 10 xp = 12,000 xp; standard_99 → level 15 (16 needs 12,113).
	assert_eq(int(tm.state.skills_xp["scavenging"]), 12_000, "1 h of tier-1 = 12,000 xp")
	assert_eq(int(tm.state.skills_level["scavenging"]), 15, "level 15 (12,000 xp on standard_99)")
	assert_eq(int(count["n"]), 14, "one immediate signal per level crossed (1→15)")


# ---------------------------------------------------------------------------
# (a) 1 h sim == closed form, EXACTLY
# ---------------------------------------------------------------------------

func test_one_hour_sim_equals_closed_form() -> void:
	# SIM TWIN: both gathering skills concurrently (Melvor-style per-skill slots).
	var sim: Variant = _make_tm(SEED_A)
	_full_staff(sim)
	assert_true((tm_start(sim, "sort_scrap_pile"))["ok"])
	assert_true((tm_start(sim, "walk_the_glow_rows"))["ok"])
	_pump(sim, HOUR_MS, 1_000)
	assert_eq(int(sim.stats["ticks_executed"]), 36_000, "1 h at 10 Hz = exactly 36,000 sim ticks")
	assert_eq(sim.sim_time_ms, HOUR_MS, "sim clock ends at exactly 3,600,000 ms (no drift)")

	# CLOSED-FORM TWIN: same seed, same slots, pure arithmetic + N rolls.
	var off: Variant = _make_tm(SEED_A)
	_full_staff(off)
	assert_true((tm_start(off, "sort_scrap_pile"))["ok"])
	assert_true((tm_start(off, "walk_the_glow_rows"))["ok"])
	var payload: Dictionary = off.apply_offline_elapsed(HOUR_MS)

	_assert_xp_match(sim.state.skills_xp, off.state.skills_xp, "(a) 1h")
	_assert_inventory_match(sim.state.inventory, off.state.inventory, "(a) 1h")
	for skill_id in sim.state.active:
		assert_eq(sim.state.active[skill_id].completed, off.state.active[skill_id].completed,
			"(a) 1h: '%s' completed action count equal" % skill_id)
	assert_eq(int(payload["elapsed_ms"]), HOUR_MS, "payload records the full gap")
	assert_eq(int(sim.state.active["scavenging"].completed), 1_200, "1 h / 3 s = 1,200 actions")
	# Payload gains == final state (both twins started empty).
	assert_eq(payload["skills_xp"], {"scavenging": 12_000, "foraging": 12_000},
		"MAIL CALL xp gains equal the sim's totals")
	var gain: Dictionary = payload["items"]
	var expect: Dictionary = sim.state.inventory.duplicate()
	for item_id in gain:
		assert_eq(int(gain[item_id]), int(expect.get(item_id, -1)),
			"(a) 1h: MAIL CALL item gain '%s' equals sim total" % item_id)
	assert_eq(gain.size(), expect.size(), "MAIL CALL covers every item the sim produced")


func tm_start(tm: Variant, content_id: String) -> Dictionary:
	return tm.start_activity(content_id)


# ---------------------------------------------------------------------------
# (b) jitter + stall clamp
# ---------------------------------------------------------------------------

func test_jittered_frames_match_closed_form() -> void:
	var sim: Variant = _make_tm(SEED_A)
	_full_staff(sim)
	tm_start(sim, "sort_scrap_pile")
	tm_start(sim, "walk_the_glow_rows")

	var jitter := RandomNumberGenerator.new()
	jitter.seed = 777
	var fed := 0
	while TEN_MIN_MS - fed > 200:
		var d := jitter.randi_range(0, 200)  # forced 0–200 ms frame jitter
		sim.advance_wall_ms(d)
		fed += d
	sim.advance_wall_ms(TEN_MIN_MS - fed)  # land on exactly 600,000 ms fed
	assert_eq(sim.sim_time_ms, TEN_MIN_MS, "int-ms accumulator: 10 min lands exactly (no float drift)")
	assert_eq(int(sim.stats["clamped_stalls"]), 0, "sub-budget jitter never clamps")

	var off: Variant = _make_tm(SEED_A)
	_full_staff(off)
	tm_start(off, "sort_scrap_pile")
	tm_start(off, "walk_the_glow_rows")
	off.apply_offline_elapsed(TEN_MIN_MS)
	_assert_xp_match(sim.state.skills_xp, off.state.skills_xp, "(b) jitter")
	_assert_inventory_match(sim.state.inventory, off.state.inventory, "(b) jitter")


func test_stall_clamps_records_and_resyncs() -> void:
	var tm: Variant = _make_tm(SEED_A)
	tm_start(tm, "sort_scrap_pile")
	tm.advance_wall_ms(10_000)  # one 10 s frame stall
	assert_eq(int(tm.stats["ticks_executed"]), 25, "clamped to MAX_CATCHUP_TICKS_PER_FRAME (25)")
	assert_eq(tm.sim_time_ms, 2_500, "only 2.5 s of sim ran for the stalled frame")
	assert_eq(int(tm.stats["clamped_stalls"]), 1, "stall recorded")
	assert_eq(int(tm.stats["last_clamp_dropped_ms"]), 7_500, "dropped remainder recorded (7.5 s)")
	assert_eq(int(tm.stats["total_dropped_ms"]), 7_500, "dropped total accumulates")

	# The dropped time must not resurrect as phantom actions: 500 ms more →
	# sim 3,000 → exactly 1 action. Closed form for 3,000 ms agrees.
	tm.advance_wall_ms(500)
	assert_eq(int(tm.state.active["scavenging"].completed), 1, "exactly one action by sim 3,000 ms")
	assert_eq(int(tm.state.skills_xp["scavenging"]), 10, "no phantom xp from clamped time")
	var off: Variant = _make_tm(SEED_A)
	_full_staff(off)
	tm_start(off, "sort_scrap_pile")
	off.apply_offline_elapsed(3_000)
	_assert_inventory_match(tm.state.inventory, off.state.inventory, "(b) clamp")


# ---------------------------------------------------------------------------
# (d) offline catch-up
# ---------------------------------------------------------------------------

func test_six_hour_offline_matches_seeded_sim() -> void:
	# Slots chosen inventory-independent: foraging (glowshroom/duskcorn) +
	# smelting from a 500-scrap stockpile (scavenging would cross-feed scrap
	# live — that coupling semantic is covered by its own test below).
	var sim: Variant = _make_tm(SEED_6H)
	_full_staff(sim)
	sim.state.add_item("scrap_metal", 500)
	tm_start(sim, "walk_the_glow_rows")
	tm_start(sim, "smelt_scrap_ingot")
	_pump(sim, SIX_HOURS_MS, 1_000)
	assert_eq(int(sim.stats["ticks_executed"]), 216_000, "6 h at 10 Hz = 216,000 ticks")

	var off: Variant = _make_tm(SEED_6H)
	_full_staff(off)
	off.state.add_item("scrap_metal", 500)
	tm_start(off, "walk_the_glow_rows")
	tm_start(off, "smelt_scrap_ingot")
	var payload: Dictionary = off.apply_offline_elapsed(SIX_HOURS_MS)

	_assert_xp_match(sim.state.skills_xp, off.state.skills_xp, "(d) 6h")
	_assert_inventory_match(sim.state.inventory, off.state.inventory, "(d) 6h")
	# Stockpile-capped recipe: 500 scrap / 3 = 166 crafts, 2 scrap left.
	assert_eq(int(off.state.inventory.get("scrap_metal", 0)), 2, "closed form leaves 2 scrap")
	assert_eq(int(sim.state.inventory.get("scrap_metal", 0)), 2, "sim leaves the same 2 scrap")
	assert_eq(int(off.state.inventory.get("scrap_ingot", 0)), 166, "166 ingots closed-form")
	assert_eq(int(sim.state.inventory.get("scrap_ingot", 0)), 166, "166 ingots simulated")
	assert_eq(int(payload["actions"]["junksmithing"]), 166, "MAIL CALL action count = affordable cap")
	assert_false(off.state.active.has("junksmithing"), "dry recipe slot stops during catch-up")
	assert_false(sim.state.active.has("junksmithing"), "and in the live sim too")
	assert_eq(int(payload["actions"]["foraging"]), 7_200, "6 h / 3 s = 7,200 foraging actions")
	assert_eq(int(off.state.active["foraging"].completed), 7_200, "foraging actions all completed")
	assert_true(off.state.active.has("foraging"), "gathering slot keeps running (remainder carried)")
	assert_eq(int(off.state.active["foraging"].anchor_ms), -SIX_HOURS_MS,
		"anchor rewound by the gap — phase remainder carried exactly")


func test_offline_clock_backwards_is_zero_not_negative() -> void:
	var tm: Variant = _make_tm(SEED_A)
	tm.state.add_item("scrap_metal", 9)
	tm.state.skills_xp["scavenging"] = 111
	tm_start(tm, "sort_scrap_pile")
	var xp0: Dictionary = tm.state.skills_xp.duplicate()
	var inv0: Dictionary = tm.state.inventory.duplicate()

	var mail_calls := {"n": 0}
	tm.mail_call_ready.connect(func(_p: Dictionary) -> void: mail_calls["n"] = int(mail_calls["n"]) + 1)

	# Engine core: negative elapsed → zero-gain no-op.
	var payload: Dictionary = tm.engine.apply_offline(tm.state, 0, -5_000)
	assert_eq(int(payload["elapsed_ms"]), 0, "negative elapsed reports 0")
	assert_true(payload["skills_xp"].is_empty() and payload["items"].is_empty(),
		"no gains when the clock ran backwards")
	assert_eq(tm.state.skills_xp, xp0, "xp untouched")
	assert_eq(tm.state.inventory, inv0, "Manifest untouched")
	assert_true(tm.state.active.has("scavenging"), "slot survives a backwards clock")

	# Wall-clock helper + façade: future-dated save timestamp → zero, no signal.
	assert_eq(TickManagerScript.compute_offline_elapsed_ms(10_000_000, 4_000_000), 0,
		"future timestamp clamps to 0 elapsed")
	var from_save: Dictionary = tm.apply_offline_from_save(9_999_999, 1_000_000)
	assert_eq(int(from_save["elapsed_ms"]), 0, "future-dated save → zero gap")
	assert_eq(int(mail_calls["n"]), 0, "zero gap emits no MAIL CALL")
	assert_eq(tm.state.skills_xp, xp0, "still untouched")


func test_offline_coupled_semantic_is_documented_divergence() -> void:
	# T6 offline semantic (production-log): recipes cap at the SAVE-TIME
	# stockpile; concurrent gathering feeds crafting LIVE but not OFFLINE.
	# This pins the boundary deliberately — it is a semantic, not drift.
	# Both runs start with 12 scrap (4 crafts). NOTE the paired live rule:
	# a slot whose inputs run dry at a due action STOPS (Melvor-style) — with
	# zero stock it would stop at its very first action (t = 4,000 ms) before
	# any drop lands, so the cross-feed demo needs starter stock.
	var sim: Variant = _make_tm(SEED_6H)  # scavenging feeds live smelting
	_full_staff(sim)
	sim.state.add_item("scrap_metal", 12)
	tm_start(sim, "sort_scrap_pile")
	tm_start(sim, "smelt_scrap_ingot")
	_pump(sim, HOUR_MS, 1_000)
	var sim_ingots := int(sim.state.inventory.get("scrap_ingot", 0))
	assert_gt(sim_ingots, 4, "live sim out-crafts its stockpile (drops extend the run)")

	var off: Variant = _make_tm(SEED_6H)  # same start, same stockpile
	_full_staff(off)
	off.state.add_item("scrap_metal", 12)
	tm_start(off, "sort_scrap_pile")
	tm_start(off, "smelt_scrap_ingot")
	var payload: Dictionary = off.apply_offline_elapsed(HOUR_MS)
	assert_eq(int(payload["actions"].get("junksmithing", 0)), 4,
		"offline recipes craft only from the save-time stockpile (12/3 = 4)")
	assert_false(off.state.active.has("junksmithing"), "the dry slot stops offline")
	assert_gt(int(off.state.inventory.get("scrap_metal", 0)), 0,
		"offline gathering still banks the raw drops for later")


# ---------------------------------------------------------------------------
# (e) performance + signal budget
# ---------------------------------------------------------------------------

func test_signal_budget_and_tick_cost_over_60s_window() -> void:
	var tm: Variant = _make_tm(SEED_A)
	# All four non-combat slots busy (worst slice case), recipes never dry.
	_full_staff(tm)
	tm.state.add_item("scrap_metal", 10_000_000)
	tm.state.add_item("duskcorn", 10_000_000)
	for content_id in ["sort_scrap_pile", "walk_the_glow_rows", "smelt_scrap_ingot", "grind_mandatory_grits"]:
		var r: Dictionary = tm.start_activity(content_id)
		assert_true(r["ok"], "slot starts: %s (%s)" % [content_id, str(r)])

	var bulk := {"n": 0}
	tm.bulk_state_changed.connect(func(_c: Dictionary) -> void: bulk["n"] = int(bulk["n"]) + 1)
	var levelups := {"n": 0}
	tm.level_up.connect(func(_s: String, _o: int, _n: int) -> void: levelups["n"] = int(levelups["n"]) + 1)

	var max_frame_us := 0
	var total_us := 0
	var frames := 0
	while frames < SIXTY_S_MS / TICK_MS:  # frame-paced: one 100 ms feed per render frame
		var t0 := Time.get_ticks_usec()
		tm.advance_wall_ms(TICK_MS)
		var dt := Time.get_ticks_usec() - t0
		total_us += dt
		max_frame_us = maxi(max_frame_us, dt)
		frames += 1
	assert_eq(tm.sim_time_ms, SIXTY_S_MS, "60 s window pumped exactly")

	# 4 Hz bulk ceiling: continuously dirty → at most one flush per 250 ms.
	var budget := 4 * 60  # 4 Hz * 60 s
	assert_true(int(bulk["n"]) <= budget,
		"bulk emissions %d within 4 Hz budget (%d)" % [int(bulk["n"]), budget])
	assert_true(int(bulk["n"]) >= 2, "bulk signal does flow while dirty")
	var expected_levelups := 0
	for skill_id in ["scavenging", "foraging", "junksmithing", "cooking"]:
		expected_levelups += int(tm.state.skills_level[skill_id]) - 1
	assert_eq(int(levelups["n"]), expected_levelups,
		"level-ups bypass the bulk gate (immediate, one per crossing)")

	# Tick cost: 25 ms is the hard assert (sim budget is 100 ms/tick; typical
	# measured value is well under 1 ms — recorded for the production log).
	assert_true(max_frame_us < 25_000,
		"worst single frame's sim cost %d us under 25 ms threshold" % max_frame_us)
	assert_true(total_us < 3_000_000, "whole 60 s window sim cost %d us under 3 s" % total_us)
	print("T6 PERF RECORD: frames=%d ticks=%d bulk_signals=%d (budget %d) levelups=%d max_frame_us=%d total_us=%d" % [
		frames, int(tm.stats["ticks_executed"]), int(bulk["n"]), budget, int(levelups["n"]), max_frame_us, total_us,
	])


# ---------------------------------------------------------------------------
# units: batcher, payload shape, state round-trip, currency, autoload wiring
# ---------------------------------------------------------------------------

func test_update_batcher_gating() -> void:
	var b := UpdateBatcher.new()
	assert_false(b.flush_due(0), "clean batcher never flushes")
	b.mark("xp")
	b.mark("inventory")
	assert_true(b.flush_due(100), "first dirty flush goes through")
	assert_eq(b.emission_count, 1, "one emission so far")
	b.mark("xp")
	assert_false(b.flush_due(200), "inside the 250 ms gate: no flush")
	assert_false(b.flush_due(349), "still inside the gate")
	assert_true(b.flush_due(350), "gate opens at 250 ms since last flush")
	b.mark("xp")
	assert_true(b.force_flush(351), "user-action force flush ignores the gate")
	b.mark("activity")
	var received: Array = []
	b.flushed.connect(func(changes: Dictionary) -> void: received.append(changes))
	assert_true(b.force_flush(400), "flush emits the collapsed change set")
	assert_eq(received, [{"activity": true}], "flushed carries exactly the dirty regions")


func test_mail_call_payload_shape() -> void:
	var tm: Variant = _make_tm(SEED_A)
	tm.state.add_item("duskcorn", 9)  # 4 grits craftable in a 12 s gap
	tm_start(tm, "grind_mandatory_grits")
	var payload: Dictionary = tm.apply_offline_elapsed(12_000)
	for key in ["elapsed_ms", "skills_xp", "items", "levels", "actions", "stopped"]:
		assert_true(payload.has(key), "payload has '%s'" % key)
	assert_eq(int(payload["elapsed_ms"]), 12_000, "elapsed is int ms")
	assert_eq(payload["skills_xp"], {"cooking": 48}, "4 crafts * 12 xp")
	assert_eq(payload["items"], {"mandatory_grits": 4, "duskcorn": -8},
		"item deltas are signed ints (outputs up, inputs down)")
	assert_eq(payload["levels"], {"cooking": {"from": 1, "to": 2}}, "levels carried as from/to")
	assert_eq(payload["actions"], {"cooking": 4}, "action counts per skill")
	assert_true(payload["stopped"] is Array, "stopped is a list")
	assert_eq(int(tm.state.inventory.get("duskcorn", 0)), 1, "1 duskcorn remains")
	assert_eq(tm.state.last_mail_call, payload, "payload cached on state for T10")


func test_player_state_roundtrip_repairs_levels() -> void:
	var tm: Variant = _make_tm(SEED_A)
	tm_start(tm, "sort_scrap_pile")
	_pump(tm, 30_000, 1_000)
	tm.state.add_item("vintage_snack_cake", 7)
	tm.state.add_crowns(1234)
	var slot_before = tm.state.active["scavenging"]
	assert_true(slot_before.stream_started, "drops rolled → stream positioned")
	var restored: PlayerState = PlayerState.from_dict(tm.state.to_dict(), _lib())
	assert_eq(restored.skills_xp, tm.state.skills_xp, "xp round-trips")
	assert_eq(restored.inventory, tm.state.inventory, "Manifest round-trips")
	assert_eq(restored.crowns, 1234, "Crowns round-trip")
	assert_eq(restored.world_seed, tm.state.world_seed, "seed round-trips (stream replay)")
	var slot_after = restored.active["scavenging"]
	assert_eq(slot_after.rng_state, slot_before.rng_state, "rng state persists for exact continuation")
	assert_eq(slot_after.completed, slot_before.completed, "progress persists")
	assert_eq(slot_after.anchor_ms, slot_before.anchor_ms, "anchor persists (remainder carried)")
	# Level drift repair: levels are never read from a save — re-derived from xp.
	tm.state.skills_level["scavenging"] = 99
	var repaired: PlayerState = PlayerState.from_dict(tm.state.to_dict(), _lib())
	assert_eq(int(repaired.skills_level["scavenging"]), int(restored.skills_level["scavenging"]),
		"level is re-derived from xp, never trusted from the save")


func test_currency_guards() -> void:
	var tm: Variant = _make_tm(SEED_A)
	tm.state.add_crowns(100)
	assert_true(tm.state.try_spend_crowns(60), "spend within wallet works")
	assert_eq(tm.state.crowns, 40, "40 left")
	assert_false(tm.state.try_spend_crowns(41), "overdraft refused")
	assert_false(tm.state.try_spend_crowns(-5), "negative spend refused")
	tm.state.add_crowns(-50)
	assert_eq(tm.state.crowns, 40, "negative grant ignored")


func test_autoload_wired_and_drivable() -> void:
	# The real autoload singleton (registered in project.godot after UiTheme).
	assert_not_null(TickManager, "TickManager autoload present")
	assert_not_null(TickManager.engine, "engine booted")
	assert_not_null(TickManager.state, "state booted")
	var before: int = TickManager.sim_time_ms
	TickManager.advance_wall_ms(TICK_MS)
	assert_eq(TickManager.sim_time_ms, before + TICK_MS, "manual advance drives the live autoload")
	var r: Dictionary = TickManager.start_activity("sort_scrap_pile")
	assert_true(r["ok"], "autoload accepts a start request")
	TickManager.stop_skill("scavenging")
	assert_false(TickManager.state.active.has("scavenging"), "and a stop request")
