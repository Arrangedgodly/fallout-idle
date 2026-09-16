extends SceneTree
## tests/probe_concourse.gd — T9 concourse shell probe (plain --script; R2
## bootstrap pattern, like tests/probe_theme.gd).
##
## Run (assertions only, headless):
##   "$GODOT" --headless --path . -s res://tests/probe_concourse.gd
## Run with captures (needs a real renderer; the runner retries windowed on
## exit 42, per T8's fallback):
##   "$GODOT" --path . -s res://tests/probe_concourse.gd -- capture
##
## Proves the T9 acceptance criteria:
##   1. the concourse instantiates from scenes/main.tscn with the T8 theme
##      installed (no ad-hoc panels: every Panel carries a theme variation);
##   2. the department plate wall: all 7 plates, names/order per the naming
##      bible and the design-brief first viewport; the facility plate carries
##      the game title; the docket region occupies >= 2/3 of the body at
##      1280x720 AND 1920x1080;
##   3. first-run: START HERE chalk visible, first plate energized with the
##      full cue set (amber variation + ">> " prefix + swell + z-order);
##   4. full keyboard navigation: initial focus set; every focusable control
##      reachable in one tab cycle; arrow neighbors link the plate column;
##      ui_accept on a focused plate drives a real department transition;
##   5. every focusable shows a visible amber focus ring when focused
##      (theme focus stylebox for buttons/checks; lit track for the slider);
##   6. bulkhead-slide transition: bounded duration, shutter covers and
##      clears, energized state moves with all cues, chalk dismissed,
##      duplicate/unknown selections are ignored;
##   7. console wiring: font scale slider drives UiTheme (100/150/200%),
##      FILE RECORD/CLOCK OUT emit their stub signals, BEGIN SHIFT emits the
##      activity signal;
##   8. T10a docket content wired to the live engine: gates as CLEARANCE
##      plates, visible drop rates, keyboard-driven start/stop, gauge digits
##      equal engine state, stamped drop/craft lines, manifest equip/unequip,
##      depot buy/sell through the façade, MAIL CALL presents + acknowledges,
##      save-notice plates post and dismiss (all keyboard);
##   8b. T10b Wasteland Patrol wired to the live combat engine: fauna postings
##      with visible stats + claim rates + clearance gates, keyboard engage/
##      withdraw, HP gauges equal engine state, stamped battle lines, death
##      renders DECEASED — RETURN TO SHELTER with zero loss displayed, offline
##      recall renders PATROL RECALLED (alive) + MAIL CALL, first boss clear
##      posts the persistent ZONE SECURED plate, stats panel derives from
##      equipment, focus traversal covers the new focusables;
##   9. R1 geometry pin (refinement 1, critique P1#1 + P2#3): the header row
##      and the docket content region never intersect, a department change
##      resets the docket scroll to its content top (the enamel header plate
##      leads, fully inside the viewport), no visible docket label is sliced
##      at the viewport's top edge and every label renders all its wrapped
##      lines — at 1280x720 AND 1920x1080, 100% AND 200% font scale, across
##      all seven departments; plus the manifest EQUIP-control clearance at
##      200% (the critique's unverified claim, pinned as refuted);
##   10. (capture mode) PNGs at 1280x720 + 1920x1080 for first-run and
##      active-department states under .impeccable/review/t9/, plus the T10a
##      set (one per department, running state, MAIL CALL, locked gates)
##      under .impeccable/review/t10a/ and the T10b set (engaged battle,
##      death state, zone-clear plate) under .impeccable/review/t10b/ —
##      all validated.

const CONCOURSE_PATH := "res://scenes/main.tscn"
const REVIEW_DIR := "res://.impeccable/review/t9"
const CAPTURE_UNSUPPORTED_EXIT := 42

const EXPECTED_PLATES := ["SCAVENGING", "FORAGING", "JUNKSMITHING", "COOKING",
	"WASTELAND PATROL", "REQUISITION DEPOT", "MANIFEST"]
const EXPECTED_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest"]
const ALLOWED_PANEL_VARIATIONS := ["", "EnamelPlate", "EnergizedPlate",
	"DangerPlate", "SteelPanel", "VentHousing", "PaperNotice"]

var checks := 0
var failures: Array[String] = []
var _capture_mode := false
var _capture_unsupported := false
var _done := false
var _vp: SubViewport
var _concourse: Concourse
var _counts := {}
var _last_changed_id := ""

func _initialize() -> void:
	_capture_mode = "capture" in OS.get_cmdline_user_args()
	_run()

func _process(_delta: float) -> bool:
	return _done

func _run() -> void:
	if not _setup():
		_report_and_quit()
		return
	await _frames(2)
	_check_structure()
	await _frames(1)
	_check_first_run()
	await _check_focus_traversal()
	await _check_focus_rings()
	await _check_transition()
	await _check_console_signals()
	await _check_t10a_dockets()
	await _check_t10b_patrol()
	await _check_font_scale()
	await _check_r1_viewport_geometry()
	if _capture_mode:
		await _capture_sets()
		await _capture_t10a_sets()
		await _capture_t10b_sets()
		if _capture_unsupported:
			_done = true
			return  # already quitting CAPTURE_UNSUPPORTED_EXIT for the runner
	_report_and_quit()

# ------------------------------------------------------------------ setup
func _setup() -> bool:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var packed := load(CONCOURSE_PATH) as PackedScene
	_check(packed != null, "concourse scene loads from %s" % CONCOURSE_PATH)
	if packed == null:
		return false
	_concourse = packed.instantiate() as Concourse
	_check(_concourse != null, "concourse root is the Concourse script")
	if _concourse == null:
		return false
	_vp.add_child(_concourse)

	var ui_theme := root.get_node_or_null("UiTheme")
	_check(ui_theme != null, "UiTheme autoload present for the concourse")
	if ui_theme != null:
		_check(_concourse.theme == ui_theme.get("theme"),
			"concourse carries the installed signage theme (UiTheme.install)")
	return true

# ------------------------------------------------------------------ checks
func _check_structure() -> void:
	# Root fills the viewport.
	_check(_concourse.size.is_equal_approx(Vector2(1280, 720)),
		"concourse root fills 1280x720 (got %s)" % str(_concourse.size))

	# No ad-hoc panels: every Panel/PanelContainer uses a theme variation from
	# T8's library (PanelContainers carry content, Panels are chrome/ground).
	var panels: Array[Control] = []
	_collect(_concourse, "Panel", panels)
	_collect(_concourse, "PanelContainer", panels)
	var unthemed: Array[String] = []
	for p in panels:
		if not ALLOWED_PANEL_VARIATIONS.has(p.theme_type_variation):
			unthemed.append("%s(%s)" % [p.name, p.theme_type_variation])
	_check(unthemed.is_empty(), "all panels carry theme variations (offenders: %s)" % ", ".join(unthemed))

	# Plate wall: 7 plates, names and order per naming bible / first viewport.
	var plates := _concourse.plate_buttons_in_order()
	_check(plates.size() == 7, "plate wall has 7 department plates (got %d)" % plates.size())
	for i in mini(plates.size(), EXPECTED_PLATES.size()):
		var expect: String = EXPECTED_PLATES[i]
		if i == 0 and _concourse.active_department() == EXPECTED_IDS[0]:
			expect = ">> " + expect  # first plate is energized at boot
		_check(plates[i].text == expect,
			"plate %d text '%s' (expected '%s')" % [i, plates[i].text, expect])
	_check(plates[0].tooltip_text.length() > 0, "plates carry accessibility tooltips")

	# Facility plate: the game title as the shelter's facility plate.
	var facility := _concourse.find_child("FacilityPlate", true, false) as PanelContainer
	_check(facility != null and facility.theme_type_variation == "EnamelPlate",
		"facility plate exists as an EnamelPlate")
	if facility != null:
		var texts := _label_texts(facility)
		_check(texts.any(func(t: String) -> bool: return "VALUED RESIDENT" in t),
			"facility plate carries the title VALUED RESIDENT")
		_check(texts.any(func(t: String) -> bool: return "AN IDLE WASTELAND" in t),
			"facility plate carries the subtitle AN IDLE WASTELAND")
		_check(facility.get_global_rect().size.y >= 40.0,
			"facility plate laid out (h=%.0f, not collapsed)" % facility.get_global_rect().size.y)

	# Layout sanity: header row + docket internals laid out (a zero-height
	# collapse would hide them while text-existence checks still pass).
	var header_notice := _concourse.find_child("HeaderNotice", true, false) as Control
	_check(header_notice != null and header_notice.get_global_rect().size.y >= 30.0,
		"header notice paper laid out")
	var active_docket := _concourse.docket_for(_concourse.active_department())
	var docket_header: Control = active_docket.find_child("DocketHeader", true, false) if active_docket != null else null
	_check(docket_header != null and docket_header.get_global_rect().size.y >= 30.0,
		"docket header plate laid out")
	var begin_btn := _concourse.begin_button_for(_concourse.active_department())
	_check(begin_btn != null and begin_btn.get_global_rect().size.x
			<= _concourse.docket_housing.get_global_rect().size.x * 0.6,
		"BEGIN SHIFT is a button plate, not a full-width banner")

	# Docket region on the right two-thirds, at 1280x720.
	_check_docket_share(1280)

func _check_docket_share(width: int) -> void:
	var wall := _concourse.find_child("PlateWallScroll", true, false) as Control
	var body := _concourse.find_child("BodyRow", true, false) as Control
	var housing := _concourse.docket_housing
	if wall == null or body == null or housing == null:
		_check(false, "wall/body/docket nodes present for the two-thirds check")
		return
	var body_w := body.get_global_rect().size.x
	var docket_w := housing.get_global_rect().size.x
	var share := docket_w / body_w
	_check(share >= 0.63, "docket region occupies the right two-thirds at %d (share %.2f)" % [width, share])

func _check_first_run() -> void:
	_check(_concourse.first_run, "first run active at boot")
	var chalk := _concourse.chalk()
	_check(chalk != null and chalk.visible, "START HERE chalk visible on first run")
	if chalk != null:
		var texts := _label_texts(chalk)
		_check(texts.has("START HERE"), "chalk reads START HERE (got %s)" % str(texts))
		var p0_rect := _concourse.plate_buttons_in_order()[0].get_global_rect()
		var c_rect := chalk.get_global_rect()
		_check(c_rect.get_center().y >= p0_rect.position.y and c_rect.get_center().y <= p0_rect.end.y
				and c_rect.end.x > p0_rect.position.x,
			"chalk sits beside the first plate, pointing at it")
		var facility_plate := _concourse.find_child("FacilityPlate", true, false) as Control
		if facility_plate != null:
			_check(c_rect.position.y + 28.0 >= facility_plate.get_global_rect().end.y - 2.0,
				"chalk label stays below the facility plate (no bone-on-bone)")

	var first := _concourse.plate_buttons_in_order()[0]
	_check(first.theme_type_variation == "Energized", "active plate uses the Energized variation")
	_check(first.text.begins_with(">> "), "active plate carries the '>> ' prefix cue")
	_check(first.z_index > 0, "active plate raises toward the viewer")
	_check(absf(first.scale.x - 1.05) < 0.001 and absf(first.scale.y - 1.05) < 0.001,
		"active plate swells forward (scale %s)" % str(first.scale))
	for i in range(1, 7):
		var p := _concourse.plate_buttons_in_order()[i]
		_check(p.theme_type_variation == "" and not p.text.begins_with(">> ") and p.scale == Vector2.ONE,
			"plate %d rests in default state" % i)
	_check(_concourse.active_department() == "scavenging", "scavenging is the boot department")
	for id in EXPECTED_IDS:
		var d := _concourse.docket_for(id)
		_check(d != null, "docket placeholder exists for %s" % id)
		if d != null:
			_check(d.visible == (id == "scavenging"), "docket %s visibility follows active" % id)
	var begin := _concourse.begin_button_for("scavenging")
	_check(begin != null and begin.visible and begin.text == "BEGIN SHIFT",
		"active docket shows the big stencled BEGIN SHIFT button")

func _check_focus_traversal() -> void:
	var focusables := _concourse.focusable_controls()
	# Expected set: the 7 plates + the 4 console controls + every visible
	# focusable inside the ACTIVE docket (T10a content mounts cards, logs,
	# buy/sell/equip buttons there; hidden dockets must contribute nothing).
	var docket := _concourse.docket_for(_concourse.active_department())
	var docket_focus: Array[Control] = []
	if docket != null:
		_collect_focusable_controls(docket, docket_focus)
	var expected_count := 7 + 4 + docket_focus.size()
	_check(focusables.size() == expected_count,
		"%d focusable controls (expected %d: 7 plates, 4 console, %d in the active docket)" % [
			focusables.size(), expected_count, docket_focus.size()])
	var names: Array[String] = []
	for c in focusables:
		names.append(c.name)
		_check(c.focus_mode != Control.FOCUS_NONE, "%s is focusable" % c.name)
	# Hidden dockets contribute nothing to the focusable set.
	for id in EXPECTED_IDS:
		if id == _concourse.active_department():
			continue
		for c in _concourse.focusable_controls():
			var hidden_docket := _concourse.docket_for(id)
			if hidden_docket != null and hidden_docket.is_ancestor_of(c):
				_check(false, "focusable %s lives in hidden docket %s" % [c.name, id])

	# Initial focus: the first plate (what START HERE points at).
	var owner_now := _vp.gui_get_focus_owner()
	_check(owner_now == _concourse.initial_focus(),
		"initial focus is the first plate (got %s)" % (owner_now.name if owner_now else "none"))

	# Tab cycle: walking the engine's focus chain from initial focus must
	# reach every focusable control.
	var visited := {}
	var cur: Control = _concourse.initial_focus()
	var guard := 0
	while guard < 64 and not visited.has(cur):
		visited[cur] = true
		cur = cur.find_next_valid_focus()
		guard += 1
	for c in focusables:
		_check(visited.has(c), "focusable %s reachable from initial focus via tab chain" % c.name)
	_check(visited.size() == focusables.size(),
		"tab chain covers exactly the focusable set (%d/%d)" % [visited.size(), focusables.size()])

	# Arrow keys drive the plate wall: ui_down/ui_up pushed through the
	# viewport's real input pipeline must walk the column plate by plate.
	var plates := _concourse.plate_buttons_in_order()
	plates[0].grab_focus()
	await _frames(1)
	for i in range(1, 7):
		_push_action("ui_down")
		await _frames(1)
		var down_owner := _vp.gui_get_focus_owner()
		_check(down_owner == plates[i],
			"arrow DOWN moves focus to plate %d (got %s)" % [i, down_owner.name if down_owner else "none"])
	for i in range(6, 0, -1):
		_push_action("ui_up")
		await _frames(1)
		var up_owner := _vp.gui_get_focus_owner()
		_check(up_owner == plates[i - 1],
			"arrow UP moves focus to plate %d (got %s)" % [i - 1, up_owner.name if up_owner else "none"])

func _check_focus_rings() -> void:
	var focusables := _concourse.focusable_controls()
	for c in focusables:
		c.grab_focus()
		await _frames(1)
		_check(_vp.gui_get_focus_owner() == c, "%s holds viewport focus when grabbed" % c.name)
		_check(_concourse.focus_ring_lit(c), "%s shows a visible amber focus ring when focused" % c.name)
	# ui_accept through the viewport's input pipeline on a plain button:
	# proves keyboard activation, not just focus.
	var save := _concourse.save_button
	save.grab_focus()
	await _frames(1)
	_hook(_concourse.save_requested, "save_requested")
	_push_action("ui_accept")
	await _frames(1)
	_check(_counts["save_requested"] == 1, "ui_accept on focused FILE RECORD fires save_requested")
	_concourse.initial_focus().grab_focus()

func _check_transition() -> void:
	_hook(_concourse.department_selected, "selected")
	_hook(_concourse.department_changed, "changed")
	_concourse.department_changed.connect(func(id: String) -> void: _last_changed_id = id)

	# Keyboard-driven transition: focus the patrol plate, press Enter.
	var plates := _concourse.plate_buttons_in_order()
	plates[4].grab_focus()  # WASTELAND PATROL
	await _frames(1)
	var t0 := Time.get_ticks_msec()
	_push_action("ui_accept")
	var ok := await _wait_until(func() -> bool: return _counts["changed"] > 0, 150)
	_check(ok, "department transition completed (department_changed emitted)")
	if not ok:
		return
	var elapsed := Time.get_ticks_msec() - t0
	_check(elapsed <= 750, "bulkhead slide bounded (%d ms <= 750)" % elapsed)
	_check(_last_changed_id == "wasteland_patrol", "transition targeted wasteland_patrol")
	_check(_concourse.active_department() == "wasteland_patrol", "active department updated")
	_check(_counts["selected"] == 1, "department_selected emitted once")

	await _frames(20)  # let the swell settle
	var patrol := plates[4]
	var scav := plates[0]
	_check(patrol.theme_type_variation == "Energized" and patrol.text == ">> WASTELAND PATROL",
		"patrol plate energized after transition")
	_check(absf(patrol.scale.x - 1.05) < 0.02, "patrol plate swell settled (%.3f)" % patrol.scale.x)
	_check(scav.theme_type_variation == "" and scav.text == "SCAVENGING" and scav.scale == Vector2.ONE,
		"scavenging plate reset to default state")
	_check(_concourse.docket_for("wasteland_patrol").visible, "patrol docket visible after transition")
	_check(not _concourse.docket_for("scavenging").visible, "scavenging docket hidden after transition")
	_check(not _concourse.chalk().visible and not _concourse.first_run,
		"START HERE chalk dismissed after the first department change")
	_check(not _concourse.shutter.visible and not _concourse.is_transitioning(),
		"bulkhead shutter cleared after transition")

	# Idempotence guards: same department and unknown ids emit nothing.
	_concourse.select_department("wasteland_patrol")
	_concourse.select_department("voluntary_overtime")
	await _frames(50)
	_check(_counts["changed"] == 1 and _counts["selected"] == 1,
		"duplicate/unknown department selections ignored")

func _check_console_signals() -> void:
	# BEGIN SHIFT on the active docket, driven by keyboard. (T10b: the patrol
	# controller treats this as ENGAGE — withdrawn right after so the later
	# sections start from a clean engine state.)
	var begin := _concourse.begin_button_for("wasteland_patrol")
	_hook(_concourse.activity_start_requested, "begin")
	begin.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(_counts["begin"] == 1, "ui_accept on BEGIN SHIFT fires activity_start_requested")
	var tm_console: Node = _concourse.bound_tick_manager()
	if tm_console != null:
		tm_console.stop_combat()

	# CLOCK OUT emits its stub signal (T3 owns persistence).
	_hook(_concourse.quit_requested, "quit")
	_concourse.quit_button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(_counts["quit"] == 1, "ui_accept on CLOCK OUT fires quit_requested")

	# FILE RECORD feedback: the console serial flashes RECORD QUEUED, then
	# restores on a real-time 2 s timer — wait on time, not frames (headless
	# frames outpace wall clock).
	_concourse.save_button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(_concourse.console_serial.text == "RECORD QUEUED.", "FILE RECORD flashes RECORD QUEUED")
	await create_timer(2.4).timeout
	_check(_concourse.console_serial.text.begins_with("CONSOLE"), "console serial restores after the flash")

	# Fullscreen toggle is wired (headless display server no-ops the mode
	# change). Skipped in capture runs: flipping the real window disturbs the
	# SubViewport render target used for the captures.
	if _capture_mode:
		_check(_concourse.fullscreen_check.focus_mode != Control.FOCUS_NONE,
			"fullscreen toggle present and focusable (mode flip skipped in capture runs)")
	else:
		_concourse.fullscreen_check.button_pressed = true
		await _frames(1)
		_concourse.fullscreen_check.button_pressed = false
		await _frames(1)
		_check(not _concourse.fullscreen_check.button_pressed, "fullscreen toggle operable")

# ------------------------------------------------------------------ T10a dockets
## Live-engine docket wiring: the concourse binds the production TickManager
## (in-memory only — SaveStore stays dormant under -s, nothing persists), so
## every check below drives REAL engine state through the real input pipeline
## or the real façade, then asserts the rendered widgets agree with the engine.
func _check_t10a_dockets() -> void:
	var tm: Node = _concourse.bound_tick_manager()
	_check(tm != null, "concourse bound a TickManager")
	if tm == null:
		return

	# -- Gathering: gates render, keyboard starts the shift, drops stamp. --
	_concourse.select_department("scavenging", true)
	await _frames(2)
	var gather := _concourse.docket_controller("scavenging") as DocketGathering
	_check(gather != null, "scavenging docket is live content")
	var cards: Dictionary = gather.get("_cards")
	_check(cards.size() == 4, "four tier cards posted from data (got %d)" % cards.size())
	var locked_card: DocketSkill.Card = cards.get("strip_wreck")
	_check(locked_card != null and locked_card.gate_plate.visible \
			and "CLEARANCE 5 REQUIRED" in locked_card.gate_text.text,
		"locked tier posts CLEARANCE 5 REQUIRED (got '%s')" % (
			locked_card.gate_text.text if locked_card else "no card"))
	var open_card: DocketSkill.Card = cards.get("sort_scrap_pile")
	_check(open_card != null and not open_card.gate_plate.visible,
		"level-1 tier ungated")
	_check("YIELDS:" in open_card.yields_line.text and "SCRAPNEL" in open_card.yields_line.text
			and "70%" in open_card.yields_line.text,
		"drop rates visible on the tier card (honest math): %s" % open_card.yields_line.text)

	open_card.button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(tm.state.active.has("scavenging"), "ui_accept on a focused tier card starts the engine slot")
	_check(gather.status_plate.visible and ">> SHIFT IN PROGRESS" in gather.status_line.text,
		"energized status plate shows the running shift (non-color cue included)")
	_check(_concourse.begin_button_for("scavenging").text == "END SHIFT",
		"primary button retexts to END SHIFT while running")

	# A few actions complete: gauge + stamped drop lines must match engine state.
	_pump(tm, 6_100)
	var gauge_text: String = gather.gauge_read.text
	var curve = tm.engine.lib.xp_curve(tm.engine.lib.skill("scavenging").xp_curve)
	var level := int(tm.state.skills_level["scavenging"])
	var into: int = int(tm.state.skills_xp["scavenging"]) - curve.total_xp_to_reach(level)
	_check(gauge_text == "CLEARANCE %02d · %s/%s XP TO NEXT" % [
			level, str(into), str(curve.xp_to_next(level))],
		"gauge digits equal engine state exactly (got '%s')" % gauge_text)
	var drop_stamped := false
	for i in gather.log.item_count:
		if "SCRAPNEL +" in gather.log.get_item_text(i) or "COPPER SNARL +" in gather.log.get_item_text(i) \
				or "TATTERCLOTH +" in gather.log.get_item_text(i):
			drop_stamped = true
	_check(drop_stamped, "drop lines stamped from the batched signal (log has %d lines)" % gather.log.item_count)

	# BEGIN toggles the shift off (keyboard).
	_concourse.begin_button_for("scavenging").grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(not tm.state.active.has("scavenging"), "ui_accept on END SHIFT stops the slot")
	_check(_concourse.begin_button_for("scavenging").text == "BEGIN SHIFT",
		"primary button retexts to BEGIN SHIFT when idle")

	# -- Processing: craftable counts from live inventory, craft consumes. --
	_concourse.select_department("junksmithing", true)
	await _frames(2)
	var smith := _concourse.docket_controller("junksmithing") as DocketProcessing
	_check(smith != null, "junksmithing docket is live content")
	var smith_cards: Dictionary = smith.get("_cards")
	var smelt: DocketSkill.Card = smith_cards.get("smelt_scrap_ingot")
	var craftable_now: int = int(tm.state.inventory.get("scrap_metal", 0)) / 3
	_check(smelt != null and "CRAFTABLE %d" % craftable_now in smelt.yields_line.text,
		"craftable count reads live inventory (%d craftable): %s" % [
			craftable_now, smelt.yields_line.text])
	tm.state.add_item("scrap_metal", 12)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	var craftable_after: int = int(tm.state.inventory.get("scrap_metal", 0)) / 3
	_check("CRAFTABLE %d" % craftable_after in smelt.yields_line.text,
		"craftable count tracks inventory via the batched signal (+12 scrap -> %d): %s" % [
			craftable_after, smelt.yields_line.text])
	var gated_recipe: DocketSkill.Card = smith_cards.get("forge_scrap_shiv")
	_check(gated_recipe != null and gated_recipe.gate_plate.visible
			and "CLEARANCE 8 REQUIRED" in gated_recipe.gate_text.text,
		"locked recipe posts CLEARANCE 8 REQUIRED")
	smelt.button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(tm.state.active.has("junksmithing"), "ui_accept posts the recipe shift")
	var scrap_before := int(tm.state.inventory.get("scrap_metal", 0))
	_pump(tm, 4_100)
	_check(int(tm.state.inventory.get("scrap_ingot", 0)) == 1
			and int(tm.state.inventory.get("scrap_metal", 0)) == scrap_before - 3,
		"one craft consumed 3 scrap and produced 1 ingot (engine-verified)")
	var craft_stamped := false
	for i in smith.log.item_count:
		if "CRAFT" in smith.log.get_item_text(i):
			craft_stamped = true
	_check(craft_stamped, "craft line stamped in the log")
	tm.stop_skill("junksmithing")

	# -- Manifest: rows from live inventory, equip/unequip through buttons. --
	_concourse.select_department("manifest", true)
	await _frames(2)
	var manifest := _concourse.docket_controller("manifest") as DocketManifest
	tm.state.add_item("scrap_shiv", 2)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	var row_text := ""
	for i in manifest.list.item_count:
		row_text += manifest.list.get_item_text(i) + " | "
	_check("POINT OF ORDER ×2" in row_text, "manifest rows show name + mono count (got %s)" % row_text)
	_check(manifest.select_line_for("scrap_shiv") and not manifest.equip_button.disabled,
		"selecting an equipment line arms the EQUIP button")
	manifest.equip_button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(str(tm.state.combat.get("weapon", "")) == "scrap_shiv",
		"EQUIP consumes a Manifest unit into the weapon slot")
	_check(int(tm.state.inventory.get("scrap_shiv", 0)) == 1, "equipped unit left the Manifest")
	_check("POINT OF ORDER" in manifest.weapon_name.text, "weapon slot plate shows the equipped gear")
	manifest.weapon_unequip.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(str(tm.state.combat.get("weapon", "")) == "" and int(tm.state.inventory.get("scrap_shiv", 0)) == 2,
		"UNEQUIP returns the unit to the Manifest")

	# -- Depot: currency plate, buy/sell update wallet + inventory, gates. --
	_concourse.select_department("requisition_depot", true)
	await _frames(2)
	var depot := _concourse.docket_controller("requisition_depot") as DocketDepot
	tm.state.add_crowns(1_000)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	_check(depot.crowns_read.text == "1,000", "currency plate reads the wallet in mono digits (got '%s')" % depot.crowns_read.text)
	var buy1 := depot.find_child("Buy1_glowshroom", true, false) as Button
	_check(buy1 != null and not buy1.disabled, "ungated stock line carries a live BUY 1 button")
	buy1.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(tm.state.crowns == 994 and int(tm.state.inventory.get("glowshroom", 0)) == 1,
		"keyboard BUY 1 tenders 6 Crowns and stocks one unit")
	_check(depot.crowns_read.text == "994", "currency plate updated via the batched signal")
	var gated_row := depot.find_child("BuyRow_scrap_metal", true, false) as Control
	var gate_text := ""
	if gated_row != null:
		for l in gated_row.find_children("*", "Label", true, false):
			gate_text += (l as Label).text + " "
	_check("CLEARANCE 3 REQUIRED" in gate_text, "gated stock line posts CLEARANCE 3 REQUIRED (got '%s')" % gate_text)
	var sell1 := depot.find_child("Sell1_glowshroom", true, false) as Button
	_check(sell1 != null, "owned item shows a disposal line")
	sell1.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(tm.state.crowns == 996 and int(tm.state.inventory.get("glowshroom", 0)) == 0,
		"keyboard SELL 1 tenders back at the honest value (+2 Crowns)")

	# -- MAIL CALL: real offline payload renders + keyboard acknowledge. --
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 2_000)
	tm.apply_offline_elapsed(1_800_000)
	await _frames(2)
	_check(_concourse.mail_call.is_presenting(), "MAIL CALL presents on mail_call_ready")
	var mail_texts := _label_texts(_concourse.mail_call)
	_check(mail_texts.any(func(t: String) -> bool: return t.begins_with("AWAY 30M")),
		"mail call posts the elapsed time (got %s)" % str(mail_texts.slice(0, 3)))
	_check(mail_texts.any(func(t: String) -> bool: return "SCAVENGING +" in t),
		"mail call posts per-skill xp gains")
	_check(_vp.gui_get_focus_owner() == _concourse.mail_call.ack_button,
		"ACKNOWLEDGE RECEIPT holds focus while the notice is posted")
	_push_action("ui_accept")
	await _frames(1)
	_check(not _concourse.mail_call.is_presenting(), "ui_accept acknowledges the mail call")
	tm.stop_skill("scavenging")

	# -- Save notices post on the concourse and acknowledge away. --
	_concourse.save_board.post("refused_newer_save_version", {
		"found_save_version": 99, "supported_save_version": 1})
	await _frames(1)
	_check(_concourse.save_board.is_posting() and "NEWER BUILD" in _concourse.save_board.title_line.text,
		"save notice plate posts on the concourse")
	_concourse.save_board.ack_button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(not _concourse.save_board.is_posting(), "notice acknowledges away by keyboard")

	# -- Foraging docket mounts (static structural check). --
	_concourse.select_department("foraging", true)
	await _frames(2)
	var forage := _concourse.docket_controller("foraging") as DocketGathering
	_check(forage != null and forage.get("_cards").size() == 4,
		"foraging docket posts its four tier cards")

	# -- Layout guard: no docket may demand horizontal scrolling at 1280x720
	#    (long lines stack full-width; side-by-side rows stay narrow). --
	var housing_w: float = _concourse.docket_housing.size.x - 44.0 - 48.0
	for id in EXPECTED_IDS:
		var dk: Control = _concourse.docket_for(id)
		var need: float = dk.get_combined_minimum_size().x
		_check(need <= housing_w, "docket %s fits without horizontal scroll (%.0f <= %.0f)" % [
			id, need, housing_w])


func _pump(tm: Node, total_ms: int) -> void:
	# Same discipline as the GUT _pump: chunks under the 2,500 ms budget.
	var fed := 0
	while fed < total_ms:
		var step := mini(500, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step


func _pump_until_phase(tm: Node, phase: String, budget_ms: int) -> bool:
	var fed := 0
	while fed < budget_ms:
		if str(tm.state.combat.get("phase", "")) == phase:
			return true
		_pump(tm, 500)
		fed += 500
	return str(tm.state.combat.get("phase", "")) == phase


# ------------------------------------------------------------------ T10b patrol
## Wasteland Patrol wired to the live combat engine through the SAME bound
## TickManager: honest stats/rates on the fauna postings, keyboard engage and
## withdraw, gauges equal engine state, stamped battle lines, death/recall/
## zone-clear phase plates, gear-derived stats, focus traversal.
func _check_t10b_patrol() -> void:
	var tm: Node = _concourse.bound_tick_manager()
	_check(tm != null, "engine bound for the patrol checks")
	if tm == null:
		return
	_concourse.select_department("wasteland_patrol", true)
	await _frames(2)
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	_check(patrol != null, "patrol docket is live content (T10b)")
	if patrol == null:
		return
	var cards: Dictionary = patrol.get("_cards")
	_check(cards.size() == 5, "five fauna postings (4 monsters + boss)")
	var litter: DocketPatrol.FaunaCard = cards.get("junkyard_roach")
	_check(litter != null and "HP 18" in litter.stats_line.text
			and "ACC 15" in litter.stats_line.text and "EVERY 2.8 S" in litter.stats_line.text,
		"fauna stats visible on the posting (honest math)")
	_check(litter != null and "65%" in litter.drops_line.text and "×1-2" in litter.drops_line.text,
		"claim table with exact rates visible")
	var boss: DocketPatrol.FaunaCard = cards.get("sewer_landlord")
	_check(boss != null and boss.gate_plate.visible and "CLEARANCE 14 REQUIRED" in boss.gate_text.text,
		"boss posts its clearance gate")
	_check(boss != null and "SENIOR FAUNA" in boss.tag_line.text, "boss tagged as senior fauna")
	_check(patrol.stats_line.text == "ACCURACY 30 · EVADE 10 · MAX HIT 1-4 · SWING EVERY 3.0 S · CONDITION 100",
		"bare-chassis derived stats posted (got '%s')" % patrol.stats_line.text)

	# Keyboard engage: focus a fauna card, press Enter.
	litter.button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(str(tm.state.combat.get("phase", "")) == "fighting",
		"ui_accept on a focused fauna card engages through the façade")
	_check(patrol.phase_plate.visible and patrol.phase_line.text == ">> PATROL ENGAGED — LITTERBUG",
		"energized phase plate while fighting (non-color cue included)")
	_check((litter.title as Label).text == ">> LITTERBUG", "engaged fauna card energized")
	_check(_concourse.begin_button_for("wasteland_patrol").text == "WITHDRAW PATROL",
		"primary retexts to WITHDRAW PATROL while fighting")
	_pump(tm, 7_000)
	await _frames(1)
	var cc: Dictionary = tm.state.combat
	_check(patrol.p_read.text == "RESIDENT · %s/100 CONDITION" % str(int(cc["p_hp"])),
		"resident gauge equals engine p_hp (got '%s')" % patrol.p_read.text)
	_check(patrol.m_read.text == "LITTERBUG · %s/18 HP" % str(int(cc["m_hp"])),
		"fauna gauge equals engine m_hp (got '%s')" % patrol.m_read.text)
	var battle_line := false
	for i in patrol.log.item_count:
		var t := patrol.log.get_item_text(i)
		if "»" in t and ("DAMAGE" in t or "MISS" in t):
			battle_line = true
	_check(battle_line, "battle lines stamped from the batched signals")

	# Keyboard withdraw via the primary button.
	_concourse.begin_button_for("wasteland_patrol").grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(str(tm.state.combat.get("phase", "")) == "idle", "ui_accept on WITHDRAW stops the fight")
	_check(_concourse.begin_button_for("wasteland_patrol").text == "ENGAGE PATROL",
		"primary retexts to ENGAGE PATROL when stopped")

	# Live death: ungearred boss fight halts + renders RETURN TO SHELTER.
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)
	tm.batcher.mark("xp")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	boss.button.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(str(tm.state.combat.get("phase", "")) == "fighting", "boss engages at clearance 14")
	# Layout guard WHILE FIGHTING (the phase plate's long directive serials are
	# the docket's widest state — the idle-state T10a guard cannot see them).
	var housing_w: float = _concourse.docket_housing.size.x - 44.0 - 48.0
	var need_w: float = _concourse.docket_for("wasteland_patrol").get_combined_minimum_size().x
	_check(need_w <= housing_w, "patrol docket fits while fighting the boss (%.0f <= %.0f)" % [
		need_w, housing_w])
	var inv_before: Dictionary = tm.state.inventory.duplicate()
	var ok_dead := _pump_until_phase(tm, "dead", 90_000)
	_check(ok_dead, "ungearred boss fight ends in death")
	await _frames(1)
	_check(patrol.phase_plate.theme_type_variation == "DangerPlate"
			and patrol.phase_line.text == "DECEASED — RETURN TO SHELTER",
		"death renders the red RETURN TO SHELTER plate")
	_check("NOTHING WAS LOST" in patrol.phase_serial.text, "zero loss displayed on the plate")
	need_w = _concourse.docket_for("wasteland_patrol").get_combined_minimum_size().x
	_check(need_w <= housing_w, "patrol docket fits in the death state (%.0f <= %.0f)" % [
		need_w, housing_w])
	_check(tm.state.inventory.duplicate() == inv_before, "death removed nothing")
	_pump(tm, 3_000)
	_check(str(tm.state.combat.get("phase", "")) == "dead", "combat halted after death")

	# Offline recall: alive at pre-blow HP, rendered here AND via mail call.
	(boss.button as Button).pressed.emit()
	_pump(tm, 6_000)
	tm.apply_offline_elapsed(3_600_000)
	await _frames(2)
	_check(str(tm.state.combat.get("phase", "")) == "recalled", "offline gap recalls the patrol")
	_check(int(tm.state.combat.get("p_hp", 0)) > 0, "recalled patrol is alive at pre-blow HP")
	_check(patrol.phase_line.text == "PATROL RECALLED — RETURN TO SHELTER",
		"recall renders the RETURN TO SHELTER plate family")
	_check(_concourse.mail_call.is_presenting(), "recall surfaced via MAIL CALL")
	_check(_vp.gui_get_focus_owner() == _concourse.mail_call.ack_button,
		"acknowledge button holds focus while the notice is posted")
	_push_action("ui_accept")
	await _frames(1)
	_check(not _concourse.mail_call.is_presenting(), "ui_accept acknowledges the mail call")

	# First boss clear: the persistent ZONE SECURED win-moment plate.
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 10)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	tm.equip_item("majority_whip")
	tm.equip_item("carpool_carapace")
	await _frames(1)
	_check(patrol.stats_line.text == "ACCURACY 75 · EVADE 40 · MAX HIT 1-18 · SWING EVERY 2.0 S · CONDITION 150",
		"stats re-derive from equipped gear (got '%s')" % patrol.stats_line.text)
	var clears := {"n": 0}
	(tm.zone_cleared as Signal).connect(func(_mid: String) -> void: clears["n"] += 1)
	_check(not patrol.zone_plate.visible, "zone plate hidden before the first clear")
	(boss.button as Button).pressed.emit()
	var ok_win := _pump_until_phase(tm, "victory", 300_000)
	_check(ok_win, "max gear + rations clears the boss")
	await _frames(1)
	_check(int(clears["n"]) == 1, "zone_cleared emitted exactly once")
	_check(bool(tm.state.combat.get("zone_clear", false)), "persistent zone_clear state set")
	_check(patrol.zone_plate.visible, "ZONE SECURED plate posted on first clear")

	# Focus traversal with the patrol docket active (new focusables covered).
	var focusables := _concourse.focusable_controls()
	var docket_focus: Array[Control] = []
	_collect_focusable_controls(_concourse.docket_for("wasteland_patrol"), docket_focus)
	_check(focusables.size() == 7 + 4 + docket_focus.size(),
		"%d focusables (7 plates, 4 console, %d patrol)" % [focusables.size(), docket_focus.size()])
	var visited := {}
	var cur: Control = _concourse.initial_focus()
	var guard := 0
	while guard < 128 and not visited.has(cur):
		visited[cur] = true
		cur = cur.find_next_valid_focus()
		guard += 1
	for f in focusables:
		_check(visited.has(f), "focusable %s reachable via tab chain" % f.name)


func _collect_focusable_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		var blocked := c is BaseButton and (c as BaseButton).disabled
		if c.focus_mode != Control.FOCUS_NONE and not blocked and c.is_visible_in_tree():
			out.append(c)
	for child in node.get_children():
		_collect_focusable_controls(child, out)


func _check_font_scale() -> void:
	var ui_theme := root.get_node_or_null("UiTheme")
	var theme: Theme = _concourse.theme
	_hook(_concourse.font_scale_changed, "scale")
	# Every step is a value CHANGE from the previous one, so each emits.
	for step in [["1", 1.5, "150%", 39], ["2", 2.0, "200%", 52], ["0", 1.0, "100%", 26]]:
		_concourse.font_slider.value = float(step[0].to_int())
		await _frames(1)
		_check(_counts["scale"] >= 1, "font_scale_changed emitted for %s" % step[2])
		_check(_concourse.font_readout.text == step[2],
			"font readout shows %s in mono (got %s)" % [step[2], _concourse.font_readout.text])
		_check(theme.get_font_size("font_size", "PlateTitle") == step[3],
			"theme PlateTitle resizes to %d at %s" % [step[3], step[2]])
		if ui_theme != null:
			_check(float(ui_theme.get("font_scale")) == step[1],
				"UiTheme.font_scale tracks the slider at %s" % step[2])
		_counts["scale"] = 0

# ------------------------------------------------------------------ R1 geometry pin
## Refinement 1 (critique P1#1 + P2#3): the first-viewport "collision" and the
## glyph-bottoms instruction headers shared one root cause — the docket
## ScrollContainer kept a stale scroll offset across department changes, so
## the first visible line rendered sliced at the viewport's top edge and the
## docket header plate sat scrolled out of view. The fix resets the docket to
## its content top on every department change; these assertions pin that
## contract at both supported resolutions, both font-scale extremes, across
## every department.
func _check_r1_viewport_geometry() -> void:
	for vp_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		_vp.size = vp_size
		await _frames(4)
		for scale_value in [0.0, 2.0]:
			_concourse.font_slider.value = scale_value
			await _frames(2)
			var scale_name := "100%" if scale_value < 1.0 else "200%"
			var header := _concourse.find_child("HeaderRow", true, false) as Control
			var scroll := _concourse.find_child("DocketScroll", true, false) as ScrollContainer
			_check(header != null and scroll != null,
				"R1 %dx%d %s: header row + docket scroll present" % [vp_size.x, vp_size.y, scale_name])
			if header == null or scroll == null:
				return
			# The first-viewport pin: the header row and the docket's content
			# region never intersect (touching counts as failing — the shell
			# column guarantees a 16 px seam).
			_check(not header.get_global_rect().intersects(scroll.get_global_rect()),
				"R1 %dx%d %s: header row and docket content region never intersect" % [
					vp_size.x, vp_size.y, scale_name])
			for id in EXPECTED_IDS:
				_concourse.select_department(id, true)
				await _frames(1)
				_check(scroll.scroll_vertical == 0,
					"R1 %dx%d %s %s: department change resets the docket scroll to top" % [
						vp_size.x, vp_size.y, scale_name, id])
				var docket := _concourse.docket_for(id)
				var vp_rect := scroll.get_global_rect()
				# A fresh posting leads with its enamel header plate, whole.
				var plate := docket.find_child("DocketHeader", true, false) as Control
				_check(plate != null and vp_rect.encloses(plate.get_global_rect()),
					"R1 %dx%d %s %s: docket header plate fully inside the viewport" % [
						vp_size.x, vp_size.y, scale_name, id])
				# No instruction label is clipped: nothing visible crosses the
				# viewport's top edge, and every wrapped label renders every
				# line inside its own rect (the POSTED SHIFTS family).
				for l in docket.find_children("*", "Label", true, false):
					var label := l as Label
					if not label.is_visible_in_tree() or label.text.strip_edges() == "":
						continue
					var r := label.get_global_rect()
					if r.end.y > vp_rect.position.y + 0.5:
						_check(r.position.y >= vp_rect.position.y - 0.5,
							"R1 %dx%d %s %s: label '%s' not sliced at the docket top edge" % [
								vp_size.x, vp_size.y, scale_name, id,
								label.text.substr(0, 28)])
					_check(label.get_visible_line_count() >= label.get_line_count(),
						"R1 %dx%d %s %s: label '%s' renders every wrapped line (%d/%d)" % [
							vp_size.x, vp_size.y, scale_name, id, label.text.substr(0, 28),
							label.get_visible_line_count(), label.get_line_count()])
			# The critique's unverified 200% claim, pinned: the manifest EQUIP
			# control never rides behind the slot plates or the list.
			if scale_value > 1.0:
				var manifest := _concourse.docket_controller("manifest") as DocketManifest
				var equip_rect := manifest.equip_button.get_global_rect()
				_check(not equip_rect.intersects(manifest.slots_row.get_global_rect())
						and not equip_rect.intersects(manifest.list.get_global_rect()),
					"R1 200%%: manifest EQUIP control clear of the slot plates and list")
	# Restore the probe's standing state (1280x720, 100%) for the capture sets.
	_vp.size = Vector2i(1280, 720)
	_concourse.font_slider.value = 0.0
	await _frames(2)

# ------------------------------------------------------------------ capture
func _capture_sets() -> void:
	if DirAccess.make_dir_recursive_absolute(REVIEW_DIR) != OK:
		_check(false, "review dir created")

	# 1280x720 — first-run, then active-department. select_department()
	# legitimately dismisses the chalk on a change (the resident started), so
	# the boot state is composed by selecting first, then re-posting the chalk.
	_concourse.select_department("scavenging", true)
	await _frames(2)
	_concourse.set_first_run(true)
	await _frames(6)
	if not _snap("concourse_first_1280x720.png"):
		return
	_concourse.select_department("wasteland_patrol", true)
	await _frames(6)
	if not _snap("concourse_active_1280x720.png"):
		return

	# 1920x1080 — same two states.
	_vp.size = Vector2i(1920, 1080)
	await _frames(8)
	_check_docket_share(1920)
	_concourse.select_department("scavenging", true)
	await _frames(2)
	_concourse.set_first_run(true)
	await _frames(6)
	if not _snap("concourse_first_1920x1080.png"):
		return
	_concourse.select_department("wasteland_patrol", true)
	await _frames(6)
	if not _snap("concourse_active_1920x1080.png"):
		return
	_validate_saved_pngs()

func _snap(file_name: String) -> bool:
	var img := _vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		_capture_unsupported = true
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		return false
	var path := REVIEW_DIR + "/" + file_name
	var err := img.save_png(path)
	_check(err == OK, "captured %s (err=%d)" % [path, err])
	return true


# ------------------------------------------------------- T10a capture set
## One shot per T10a department + the running state + MAIL CALL + the
## locked-gate state, at 1280x720 (plus 1920x1080 coverage). Everything on
## screen is LIVE engine state driven through the bound TickManager — a
## fresh seeded game, real starts, real pumps, real offline catch-up.
const T10A_DIR := "res://.impeccable/review/t10a"

func _capture_t10a_sets() -> void:
	if DirAccess.make_dir_recursive_absolute(T10A_DIR) != OK:
		_check(false, "t10a review dir created")
	var tm: Node = _concourse.bound_tick_manager()
	if tm == null:
		_check(false, "capture: engine bound")
		return
	_vp.size = Vector2i(1280, 720)  # the t9 set ends at 1920x1080; reset
	tm.new_game(20260915)
	tm.batcher.mark("inventory")
	tm.batcher.mark("xp")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(2)

	# Scavenging, fresh ledger — the locked-gate state (3 CLEARANCE plates).
	_concourse.set_first_run(false)
	_concourse.select_department("scavenging", true)
	await _frames(6)
	if not _snap_t10a("docket_scavenging_locked_gates_1280x720.png"):
		return

	# Scavenging, shift running with stamped yield lines.
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 12_500)
	await _frames(2)
	if not _snap_t10a("docket_scavenging_running_1280x720.png"):
		return
	tm.stop_skill("scavenging")

	# Foraging (fresh — tiers 2-4 locked).
	_concourse.select_department("foraging", true)
	await _frames(6)
	if not _snap_t10a("docket_foraging_1280x720.png"):
		return

	# Junksmithing with a stocked Manifest + a running craft.
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("copper_wiring", 20)
	tm.state.add_item("cloth_scraps", 16)
	_concourse.select_department("junksmithing", true)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(2)
	tm.start_activity("smelt_scrap_ingot")
	_pump(tm, 9_500)
	await _frames(2)
	if not _snap_t10a("docket_junksmithing_1280x720.png"):
		return
	tm.stop_skill("junksmithing")

	# Cooking with stock (craftable counts live).
	tm.state.add_item("duskcorn", 12)
	tm.state.add_item("glowshroom", 6)
	tm.state.add_item("roach_meat", 4)
	_concourse.select_department("cooking", true)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(6)
	if not _snap_t10a("docket_cooking_1280x720.png"):
		return

	# Manifest with owned goods + an equipped weapon.
	tm.state.add_item("scrap_shiv", 1)
	tm.equip_item("scrap_shiv")
	tm.state.add_crowns(850)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	_concourse.select_department("manifest", true)
	await _frames(6)
	if not _snap_t10a("docket_manifest_1280x720.png"):
		return

	# Depot: currency plate + stock + disposal lines from the same ledger.
	_concourse.select_department("requisition_depot", true)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(6)
	if not _snap_t10a("docket_depot_1280x720.png"):
		return

	# MAIL CALL over the concourse — real offline catch-up (2 h away).
	_concourse.select_department("scavenging", true)
	await _frames(2)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 3_000)
	tm.apply_offline_elapsed(7_200_000)
	await _frames(6)
	if not _snap_t10a("mail_call_1280x720.png"):
		return
	_concourse.mail_call.acknowledge()
	tm.stop_skill("scavenging")
	await _frames(2)

	# 1920x1080 coverage: running docket, depot, mail call.
	_vp.size = Vector2i(1920, 1080)
	await _frames(8)
	_concourse.select_department("scavenging", true)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 7_000)
	await _frames(2)
	if not _snap_t10a("docket_scavenging_running_1920x1080.png"):
		return
	tm.stop_skill("scavenging")
	_concourse.select_department("requisition_depot", true)
	await _frames(6)
	if not _snap_t10a("docket_depot_1920x1080.png"):
		return
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 3_000)
	tm.apply_offline_elapsed(3_600_000)
	await _frames(6)
	if not _snap_t10a("mail_call_1920x1080.png"):
		return
	_concourse.mail_call.acknowledge()
	tm.stop_skill("scavenging")
	_validate_t10a_pngs()


func _snap_t10a(file_name: String) -> bool:
	var img := _vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		_capture_unsupported = true
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		return false
	var path := T10A_DIR + "/" + file_name
	var err := img.save_png(path)
	_check(err == OK, "captured %s (err=%d)" % [path, err])
	return true


# ------------------------------------------------------- T10b capture set
## Engaged battle, death state, and the zone-clear plate — all LIVE engine
## state: a seeded fresh game, real grants/equips/engages, real pumps, real
## offline recall-free progression. 1280x720 for all three states plus
## 1920x1080 coverage for the engaged board and the zone plate.
const T10B_DIR := "res://.impeccable/review/t10b"

func _capture_t10b_sets() -> void:
	if DirAccess.make_dir_recursive_absolute(T10B_DIR) != OK:
		_check(false, "t10b review dir created")
		return
	var tm: Node = _concourse.bound_tick_manager()
	if tm == null:
		_check(false, "capture: engine bound")
		return
	_vp.size = Vector2i(1280, 720)  # the t10a set ends at 1920x1080; reset
	tm.new_game(20260915)
	tm.engine.grant_xp(tm.state, "wasteland_combat", 8_340)  # boss clearance
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 10)
	tm.state.add_item("mandatory_grits", 4)
	tm.batcher.mark("inventory")
	tm.batcher.mark("xp")
	tm.batcher.force_flush(tm.sim_time_ms)
	_concourse.set_first_run(false)
	_concourse.select_department("wasteland_patrol", true)
	await _frames(2)
	tm.equip_item("majority_whip")
	tm.equip_item("carpool_carapace")
	await _frames(2)

	# Engaged battle: mid-fight against the boss with gear + rations visible.
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	var boss: DocketPatrol.FaunaCard = (patrol.get("_cards") as Dictionary).get("sewer_landlord")
	(boss.button as Button).pressed.emit()
	_pump(tm, 40_000)  # gauges partially drained, swings + rations stamped
	await _frames(2)
	if not _snap_t10b("patrol_engaged_1280x720.png"):
		return

	# Death state: strip the gear and the rations, re-engage, fall honestly.
	tm.stop_combat()
	tm.unequip_slot("weapon")
	tm.unequip_slot("armor")
	tm.state.inventory.erase("radstag_stew")
	tm.state.inventory.erase("mandatory_grits")
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	(boss.button as Button).pressed.emit()
	_pump_until_phase(tm, "dead", 120_000)
	await _frames(2)
	if not _snap_t10b("patrol_death_1280x720.png"):
		return

	# Zone-clear win moment: re-gear, re-engage, secure the zone.
	tm.equip_item("majority_whip")
	tm.equip_item("carpool_carapace")
	tm.state.add_item("radstag_stew", 10)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	await _frames(1)
	(boss.button as Button).pressed.emit()
	var ok_win := _pump_until_phase(tm, "victory", 300_000)
	_check(ok_win, "capture: boss cleared for the zone plate")
	await _frames(2)
	if not _snap_t10b("patrol_zone_clear_1280x720.png"):
		return

	# 1920x1080 coverage: engaged board again (re-engage mid-fight) + plate.
	_vp.size = Vector2i(1920, 1080)
	await _frames(8)
	(boss.button as Button).pressed.emit()
	_pump(tm, 25_000)
	await _frames(2)
	if not _snap_t10b("patrol_engaged_1920x1080.png"):
		return
	tm.stop_combat()
	await _frames(2)
	if not _snap_t10b("patrol_zone_clear_1920x1080.png"):
		return
	_validate_t10b_pngs()


func _snap_t10b(file_name: String) -> bool:
	var img := _vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		_capture_unsupported = true
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		return false
	var path := T10B_DIR + "/" + file_name
	var err := img.save_png(path)
	_check(err == OK, "captured %s (err=%d)" % [path, err])
	return true


func _validate_t10b_pngs() -> void:
	var expects := {
		"patrol_engaged_1280x720.png": Vector2i(1280, 720),
		"patrol_death_1280x720.png": Vector2i(1280, 720),
		"patrol_zone_clear_1280x720.png": Vector2i(1280, 720),
		"patrol_engaged_1920x1080.png": Vector2i(1920, 1080),
		"patrol_zone_clear_1920x1080.png": Vector2i(1920, 1080),
	}
	for file_name: String in expects:
		var path := T10B_DIR + "/" + file_name
		var fa := FileAccess.open(path, FileAccess.READ)
		_check(fa != null and fa.get_length() > 0, "%s saved with size > 0" % file_name)
		if fa == null:
			continue
		fa.close()
		var img := Image.load_from_file(path)
		_check(img != null, "%s is a loadable image" % file_name)
		if img == null:
			continue
		_check(Vector2i(img.get_width(), img.get_height()) == expects[file_name],
			"%s dimensions %dx%d" % [file_name, img.get_width(), img.get_height()])
		var colors := {}
		for x in range(0, img.get_width(), 16):
			for y in range(0, img.get_height(), 16):
				colors[img.get_pixel(x, y).to_html(true)] = true
		_check(colors.size() >= 8, "%s renders real content (%d distinct sampled colors)" % [
			file_name, colors.size()])


func _validate_t10a_pngs() -> void:
	var expects := {
		"docket_scavenging_locked_gates_1280x720.png": Vector2i(1280, 720),
		"docket_scavenging_running_1280x720.png": Vector2i(1280, 720),
		"docket_foraging_1280x720.png": Vector2i(1280, 720),
		"docket_junksmithing_1280x720.png": Vector2i(1280, 720),
		"docket_cooking_1280x720.png": Vector2i(1280, 720),
		"docket_manifest_1280x720.png": Vector2i(1280, 720),
		"docket_depot_1280x720.png": Vector2i(1280, 720),
		"mail_call_1280x720.png": Vector2i(1280, 720),
		"docket_scavenging_running_1920x1080.png": Vector2i(1920, 1080),
		"docket_depot_1920x1080.png": Vector2i(1920, 1080),
		"mail_call_1920x1080.png": Vector2i(1920, 1080),
	}
	for file_name: String in expects:
		var path := T10A_DIR + "/" + file_name
		var fa := FileAccess.open(path, FileAccess.READ)
		_check(fa != null and fa.get_length() > 0, "%s saved with size > 0" % file_name)
		if fa == null:
			continue
		fa.close()
		var img := Image.load_from_file(path)
		_check(img != null, "%s is a loadable image" % file_name)
		if img == null:
			continue
		_check(Vector2i(img.get_width(), img.get_height()) == expects[file_name],
			"%s dimensions %dx%d" % [file_name, img.get_width(), img.get_height()])
		var colors := {}
		for x in range(0, img.get_width(), 16):
			for y in range(0, img.get_height(), 16):
				colors[img.get_pixel(x, y).to_html(true)] = true
		_check(colors.size() >= 8, "%s renders real content (%d distinct sampled colors)" % [
			file_name, colors.size()])

func _validate_saved_pngs() -> void:
	var expects := {
		"concourse_first_1280x720.png": Vector2i(1280, 720),
		"concourse_active_1280x720.png": Vector2i(1280, 720),
		"concourse_first_1920x1080.png": Vector2i(1920, 1080),
		"concourse_active_1920x1080.png": Vector2i(1920, 1080),
	}
	for file_name: String in expects:
		var path := REVIEW_DIR + "/" + file_name
		var fa := FileAccess.open(path, FileAccess.READ)
		_check(fa != null and fa.get_length() > 0, "%s saved with size > 0" % file_name)
		if fa == null:
			continue
		fa.close()
		var img := Image.load_from_file(path)
		_check(img != null, "%s is a loadable image" % file_name)
		if img == null:
			continue
		_check(Vector2i(img.get_width(), img.get_height()) == expects[file_name],
			"%s dimensions %dx%d" % [file_name, img.get_width(), img.get_height()])
		var colors := {}
		for x in range(0, img.get_width(), 16):
			for y in range(0, img.get_height(), 16):
				colors[img.get_pixel(x, y).to_html(true)] = true
		_check(colors.size() >= 8, "%s renders real content (%d distinct sampled colors)" % [
			file_name, colors.size()])

# ------------------------------------------------------------------ helpers
func _push_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)

func _hook(sig: Signal, key: String) -> void:
	_counts[key] = 0
	sig.connect(func(..._args) -> void: _counts[key] += 1)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait_until(cond: Callable, timeout_frames: int) -> bool:
	var n := 0
	while n < timeout_frames:
		if cond.call():
			return true
		await process_frame
		n += 1
	return cond.call()

func _collect(node: Node, type_name: String, out: Array) -> void:
	if node.get_class() == type_name:
		out.append(node)
	for child in node.get_children():
		_collect(child, type_name, out)

func _label_texts(root_node: Node) -> Array[String]:
	var out: Array[String] = []
	for l in root_node.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("  FAIL: " + label)

func _report_and_quit() -> void:
	_done = true
	if failures.is_empty():
		print("PROBE_OK checks=%d (concourse themed; 7 plates; two-thirds docket; first-run chalk + energized cues; full tab/arrow coverage with amber focus rings incl. T10a/T10b docket content; bounded bulkhead slide; console signals wired; T10a live-engine dockets: gates, honest rates, keyboard start/stop, gauge==state, stamps, equip/unequip, depot tenders, MAIL CALL, save notices; T10b patrol: honest fauna stats + claim rates + gates, keyboard engage/withdraw, gauges==state, battle stamps, DECEASED/RETURN TO SHELTER zero-loss, PATROL RECALLED + mail call, persistent ZONE SECURED, gear-derived stats, traversal)" % checks)
		quit(0)
	else:
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for f in failures:
			printerr("  - " + f)
		quit(1)
