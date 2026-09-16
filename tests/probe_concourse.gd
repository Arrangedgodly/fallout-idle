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
##   8. (capture mode) PNGs at 1280x720 + 1920x1080 for first-run and
##      active-department states under .impeccable/review/t9/, validated.

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
	await _check_font_scale()
	if _capture_mode:
		await _capture_sets()
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
	var expected_count := 7 + 1 + 4  # plates + active begin button + console controls
	_check(focusables.size() == expected_count,
		"%d focusable controls (expected %d: 7 plates, begin, slider, fullscreen, save, quit)" % [
			focusables.size(), expected_count])
	var names: Array[String] = []
	for c in focusables:
		names.append(c.name)
		_check(c.focus_mode != Control.FOCUS_NONE, "%s is focusable" % c.name)

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
	# BEGIN SHIFT on the active docket, driven by keyboard.
	var begin := _concourse.begin_button_for("wasteland_patrol")
	_hook(_concourse.activity_start_requested, "begin")
	begin.grab_focus()
	await _frames(1)
	_push_action("ui_accept")
	await _frames(1)
	_check(_counts["begin"] == 1, "ui_accept on BEGIN SHIFT fires activity_start_requested")

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
		print("PROBE_OK checks=%d (concourse themed; 7 plates; two-thirds docket; first-run chalk + energized cues; full tab/arrow coverage with amber focus rings; bounded bulkhead slide; console signals wired)" % checks)
		quit(0)
	else:
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for f in failures:
			printerr("  - " + f)
		quit(1)
