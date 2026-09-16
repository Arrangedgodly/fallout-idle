class_name Concourse
extends Control
## T9 — The Concourse: the shelter's main-game shell (scenes/main.tscn root).
##
## FIRST VIEWPORT (docs/ultron/design-brief.md — law for this surface): the
## shelter concourse — a wall of department plates (Scavenging, Foraging,
## Junksmithing, Cooking, Wasteland Patrol, Requisition Depot, Manifest, and
## — since T17 — Personnel) behind
## a half-open bulkhead door with wasteland daylight spilling in at the left
## edge. The active department's plate is energized — amber, swells forward,
## and carries a ">> " label prefix so the state never rides on color alone
## (Daredevil floor). Its docket panel occupies the right two-thirds of the
## body; the big stencled BEGIN SHIFT button on the docket is the primary
## action.
##
## T18 — ORIENTATION FORM O-1 is posted at the docket frame's top-right
## corner (always on the wall, never a modal): seven stencil lines, stamps
## filling as steps complete, and the current step carrying the orient_arrow
## cue. While orientation is incomplete the arrow glyph ALSO posts beside the
## current step's destination plate (the run-1 START HERE chalk, retired —
## its first-run directional role is subsumed by the O-1 cue, which walks
## with the resident step by step instead of pointing once).
##
## Everything is built from the T8 signage theme (installed via the UiTheme
## autoload) — plates, panels, notices, vents and gauges are theme variations,
## never ad-hoc styleboxes. The bulkhead-slide is the one authored motion:
## department changes slide a riveted shutter across the docket (bounded,
## CLOSE + OPEN seconds), the daylight mouth pulses as the door passes, and
## the new docket settles out of the door's shadow. Full keyboard navigation:
## every plate and control is focusable in one tab cycle with a visible amber
## focus ring (the slider lights its track border — Godot sliders draw no
## focus stylebox of their own).
##
## R3 (refinement 3, critique P3#5) — department hotkeys: each plate posts its
## designation digit ("SCAVENGING · 1" — the digit of its D-0n serial), and
## pressing that digit on the keyboard (row or keypad) selects the department
## from anywhere in the concourse, no Tab walk. The digit suffix rides the
## plate's own stencil text (the established button-digit idiom — the Depot's
## "BUY ×2"), so no new component and no geometry risk at 200% font scale; the
## tooltip names the key outright. Modifier combos (Cmd/Ctrl/Alt) are left to
## the OS, and a posted MAIL CALL owns the input while it is up (Esc
## acknowledges it — an interruption notice earns protected focus).
##
## Signals (SaveStore wires the two record controls since T3; T10a/T6 own the
## rest):
##   department_selected(id)       — plate pressed (intent, before transition)
##   department_changed(id)        — bulkhead transition completed
##   activity_start_requested(id)  — the docket's big stencled button
##   font_scale_changed(scale)     — settings console font scale (1.0/1.5/2.0)
##   save_requested                — FILE RECORD (SaveStore files the record)
##   quit_requested                — CLOCK OUT (SaveStore files, then quits)

signal department_selected(id: String)
signal department_changed(id: String)
signal activity_start_requested(id: String)
signal font_scale_changed(scale: float)
signal save_requested
signal quit_requested
signal mail_call_acknowledged(payload: Dictionary)

const DEPARTMENTS := [
	{
		"id": "scavenging", "plate": "SCAVENGING", "serial": "D-01",
		"notice": "SORT PROMPTLY. THE PILE IS PATIENT. THE PILE IS NOT, STRICTLY SPEAKING, SAFE.",
		"stamp": "COMPLIANCE APPRECIATED",
	},
	{
		"id": "foraging", "plate": "FORAGING", "serial": "D-02",
		"notice": "GATHER ONLY WHAT GLOWS BACK. THANK YOU FOR YOUR COMPLIANCE.",
		"stamp": "POSTED — SECTOR C",
	},
	{
		"id": "junksmithing", "plate": "JUNKSMITHING", "serial": "D-03",
		"notice": "HAMMER WITH PURPOSE. THE FORGE FILES ITS OWN REPORTS.",
		"stamp": "HEARING OPTIONAL",
	},
	{
		"id": "cooking", "plate": "COOKING", "serial": "D-04",
		"notice": "TODAY'S MENU IS YESTERDAY'S MENU. BON APPETIT.",
		"stamp": "NO SUBSTITUTIONS",
	},
	{
		"id": "wasteland_patrol", "plate": "WASTELAND PATROL", "serial": "D-05",
		"notice": "PLEASE ENJOY THE WASTELAND RESPONSIBLY. THE WASTELAND HAS NOT AGREED TO RECIPROATE.",
		"stamp": "DESIGNATED AMENITY",
	},
	{
		"id": "requisition_depot", "plate": "REQUISITION DEPOT", "serial": "D-06",
		"notice": "WELCOME, VALUED RESIDENT. TENDERS EXACT. RETURNS ARE A FUTURE DEPARTMENT.",
		"stamp": "TENDERS EXACT",
	},
		{
			"id": "manifest", "plate": "MANIFEST", "serial": "D-07",
			"notice": "EVERYTHING IN ITS PLACE. THE MANIFEST REMEMBERS WHAT YOU FORGET.",
			"stamp": "COUNTED WEEKLY",
		},
		{
			"id": "personnel", "plate": "PERSONNEL", "serial": "D-08",
			"notice": "POSTINGS ARE EARNED, STAFFED, AND CHEERFULLY AUDITED. THE BOARD DOES NOT PLAY FAVORITES. IT MERELY POSTS.",
			"stamp": "STAFFING CURRENT",
		},
	]

const TITLE := "VALUED RESIDENT"
const SUBTITLE := "AN IDLE WASTELAND · A D.O.C.S. FACILITY"
const FACILITY_SERIAL := "FACILITY PLATE 01 · REV. 1958-09"
const HEADER_NOTICE := ("NOTICE: THE CONCOURSE IS OPEN. ALL DEPARTMENTS REMAIN IN "
		+ "OPERATION. CHEERFUL DIRECTIVES CONTINUE AS SCHEDULED.")
const CONSOLE_SERIAL := "CONSOLE 09 · FORM 9-A"
const BEGIN_LABEL := "BEGIN SHIFT"
const ENERGIZED_PREFIX := ">> "

const TRANSITION_CLOSE_S := 0.24
const TRANSITION_OPEN_S := 0.34
const SWELL := 1.05
const FONT_STEPS := [1.0, 1.5, 2.0]

## Department hotkeys (R3): the digit row and the keypad both select; the
## index is the plate's position + 1 (the designation digit it posts).
## T17: the eighth plate — PERSONNEL, digit 8, D-08.
const HOTKEY_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8,
	KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8]

var first_run := true
var font_slider: HSlider
var font_readout: Label
var fullscreen_check: CheckButton
var save_button: Button
var quit_button: Button
var console_serial: Label
var header_notice: PanelContainer
var orientation_form: OrientationForm
var orientation_cue: OrientationCue
var shutter: PanelContainer
var docket_housing: PanelContainer
var docket_scroll: ScrollContainer
var mail_call: MailCallModal
var save_board: SaveNoticeBoard

var _ui_theme: Node  # the UiTheme autoload, soft-accessed so the script also
                     # compiles under --check-only/-s (no global identifiers)
var _mouth: BulkheadMouth
var _plates: Dictionary = {}   # id -> Button
var _dockets: Dictionary = {}  # id -> Control (VBox placeholder)
var _begin_buttons: Dictionary = {}  # id -> Button
var _controllers: Dictionary = {}    # id -> Docket (T10a live content)
var _dept_by_id: Dictionary = {}
var _plate_order: Array[Button] = []
var _active_id := ""
var _transitioning := false
var _slider_focus_lit := false
var _serial_token := 0
var _tm: Node = null              # TickManager (autoload in prod, twin in tests)
var _mail_hooked := false
var _orientation_hooked := false

func _ready() -> void:
	_ui_theme = get_node_or_null("/root/UiTheme")
	if _ui_theme == null:
		push_error("[concourse] UiTheme autoload missing — signage theme not installed")
	else:
		_ui_theme.install(self)
	if get_window() != null:
		get_window().min_size = Vector2i(1280, 720)  # desktop floor, resizable up
	# T15 keyboard reachability: ScrollContainer does not follow focus into
	# nested content (the docket housing wraps the scroll's child), so a
	# keyboard resident tabbing below the fold never saw the focused control.
	# The shell now scrolls every ancestor scroll region to the focused
	# control — the concourse's scroll regions stay keyboard-reachable at
	# every font scale.
	get_viewport().gui_focus_changed.connect(_on_shell_focus_changed)
	for d in DEPARTMENTS:
		_dept_by_id[d.id] = d
	_build_ui()
	_apply_active(DEPARTMENTS[0].id, false)
	set_first_run(true)
	_plates[DEPARTMENTS[0].id].grab_focus()  # the O-1 cue points here first run
	_settle_boot_swell()
	bind_engines()  # T10a: live engine data (autoloads in production)

## The first container layout pass resets child transforms assigned during
## _ready, so the boot swell is re-asserted one frame later, after layout.
## T18: the O-1 form + step cue re-position on the same settle — the first
## pass leaves them at stale rects whenever the plate wall's layout shifts
## late (an eighth plate joined the wall in T17).
func _settle_boot_swell() -> void:
	await get_tree().process_frame
	if is_inside_tree() and not _transitioning and _plates.has(_active_id):
		_set_plate_state(_plates[_active_id], true, false)
		_position_orientation_form()
		_position_orientation_cue()

# ------------------------------------------------------------------ public API
## Press-free programmatic entry (probe + future hotkeys). Emits the same
## signals a plate press produces. instant=true swaps without the slide.
func select_department(id: String, instant := false) -> void:
	if not _plates.has(id) or id == _active_id or _transitioning:
		return
	department_selected.emit(id)
	if instant:
		_apply_active(id, false)
		department_changed.emit(id)
		return
	_transitioning = true
	var width := docket_housing.size.x
	shutter.visible = true
	shutter.position.x = -width
	var tw := create_tween()
	tw.tween_property(shutter, "position:x", 0.0, TRANSITION_CLOSE_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(_set_mouth_energy, _mouth.energy, 1.0, TRANSITION_CLOSE_S + 0.08)
	tw.tween_callback(_apply_active.bind(id, true))
	tw.tween_property(shutter, "position:x", width, TRANSITION_OPEN_S) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_mouth_energy, 1.0, 0.0, TRANSITION_OPEN_S)
	tw.tween_callback(_on_transition_done.bind(id))

## T18: SaveStore owns first-run detection; the concourse applies it to the
## O-1 form (a brand-new resident meets the checklist EXPANDED, step 1 cued).
func set_first_run(on: bool) -> void:
	first_run = on
	if orientation_form != null:
		orientation_form.apply_first_run(on)

func active_department() -> String:
	return _active_id

func is_transitioning() -> bool:
	return _transitioning

func plates() -> Dictionary:
	return _plates

func plate_buttons_in_order() -> Array[Button]:
	return _plate_order

func docket_for(id: String) -> Control:
	return _dockets.get(id)

## T10a/T10b live docket content controller for a department.
func docket_controller(id: String) -> Docket:
	return _controllers.get(id)

func controllers() -> Dictionary:
	return _controllers

func begin_button_for(id: String) -> Button:
	return _begin_buttons.get(id)

func initial_focus() -> Control:
	return _plates[DEPARTMENTS[0].id]

## T18: the posted O-1 form (convenience accessor for probes/tests).
func orientation() -> OrientationForm:
	return orientation_form

## T18: the current-step plate cue (convenience accessor for probes/tests).
func cue() -> OrientationCue:
	return orientation_cue

## Every visible, enabled, focusable control in the concourse (probe walks
## the tab cycle against this list — the keyboard contract).
func focusable_controls() -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusable(self, out)
	return out

## Visible amber focus indicator for a focused control. Buttons, checks and
## option buttons resolve the theme's amber focus stylebox; the slider lights
## its track border via override (sliders draw no focus stylebox natively).
func focus_ring_lit(control: Control) -> bool:
	if control == null or not control.has_focus():
		return false
	if control is Slider:
		return _slider_focus_lit
	var sb := control.get_theme_stylebox("focus")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		return flat.border_color.is_equal_approx(SignageTokens.SIGNAL_AMBER) \
			and flat.border_width_top > 0 \
			and flat.expand_margin_left > 0.0
	return false

# ------------------------------------------------------------------ engines
## T10a: wire the concourse to the engine autoloads (production default) or
## to test twins injected by the GUT suite. Every docket controller, the
## MAIL CALL modal and the save-notice board follow the bound managers;
## rebinding to a different twin disconnects the old one first. The cached
## last_mail_call is presented when the load's mail_call_ready fired before
## this scene existed (SaveStore loads inside its own _ready).
func bind_engines(p_tm: Node = null, p_save: Node = null) -> void:
	var new_tm: Node = p_tm if p_tm != null else get_node_or_null("/root/TickManager")
	var new_save: Node = p_save if p_save != null else get_node_or_null("/root/SaveStore")
	if new_tm == null:
		return
	var rebound := new_tm != _tm
	if rebound and _tm != null and _mail_hooked:
		(_tm.mail_call_ready as Signal).disconnect(_on_mail_call_ready)
		_mail_hooked = false
	if rebound and _tm != null and _orientation_hooked:
		(_tm.orientation_step_done as Signal).disconnect(_on_orientation_step)
		(_tm.orientation_completed as Signal).disconnect(_on_orientation_complete)
		_orientation_hooked = false
	_tm = new_tm
	for id in _controllers:
		(_controllers[id] as Docket).bind(_tm)
	orientation_form.bind(_tm)
	if not _orientation_hooked:
		(_tm.orientation_step_done as Signal).connect(_on_orientation_step)
		(_tm.orientation_completed as Signal).connect(_on_orientation_complete)
		_orientation_hooked = true
	mail_call.lib = _tm.engine.lib
	if not _mail_hooked:
		(_tm.mail_call_ready as Signal).connect(_on_mail_call_ready)
		_mail_hooked = true
	save_board.bind(new_save)
	if rebound:
		_refresh_orientation_cue()
		var cached: Dictionary = _tm.state.last_mail_call
		# T17: a staffing-migration notice is presentable even at a zero
		# offline gap (the notice IS the mail) — see TickManager's contract.
		if int(cached.get("elapsed_ms", 0)) > 0 or cached.has("staffing"):
			mail_call.present(cached, _tm.engine.lib)


func bound_tick_manager() -> Node:
	return _tm


func _on_mail_call_ready(payload: Dictionary) -> void:
	mail_call.present(payload, _tm.engine.lib)


# ------------------------------------------------------------------ T18 orientation
## Every stamp re-aims the plate cue (a step change is the one authored
## moment: a bounded arrival swell — never a looping pulse).
func _on_orientation_step(_step_id: String) -> void:
	_refresh_orientation_cue(true)


## The seventh stamp: the cue retires with the tutorial (the arrow class
## exists only while orientation is incomplete), and the console posts the
## restrained completion line.
func _on_orientation_complete(payload: Dictionary) -> void:
	orientation_cue.visible = false
	var stipend := int(payload.get("stipend", 0))
	if stipend > 0:
		_flash_serial("FORM O-1 FILED · %s CROWNS POSTED" % SignageFmt.num(stipend))
	else:
		_flash_serial("FORM O-1 FILED · DULY ORIENTED")


func _refresh_orientation_cue(animate := false) -> void:
	if _tm == null or orientation_cue == null:
		return
	var target := ""
	if _tm.has_method("orientation_progress"):
		target = String(_tm.orientation_progress()["target"])
	orientation_cue.visible = target != ""
	if target != "" and _plates.has(target):
		orientation_cue.aim(_plates[target], animate)


# ------------------------------------------------------------------ hotkeys
## R3 (critique P3#5): the designation digit selects its department from
## anywhere in the concourse — the accelerator the Tab walk never had. Works
## unfocused (unhandled input, after the GUI had its turn — no control in the
## concourse consumes bare digits), honors the row AND the keypad, and is
## suppressed while MAIL CALL is posted (the interruption notice owns input;
## Esc acknowledges it). Modifier combos (Cmd/Ctrl/Alt + digit) stay with the
## OS. Focus follows the jump: the destination plate takes focus so the tab
## chain resumes INTO the new docket instead of dangling in the hidden one.
func _unhandled_input(event: InputEvent) -> void:
	if mail_call != null and mail_call.is_presenting():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.is_command_or_control_pressed() or key.is_alt_pressed():
		return
	var idx := HOTKEY_KEYS.find(key.keycode)
	if idx < 0:
		return
	if idx >= DEPARTMENTS.size():
		idx -= DEPARTMENTS.size()  # keypad half of the table
	var id: String = DEPARTMENTS[idx].id
	if not _plates.has(id) or id == _active_id or _transitioning:
		return
	_plates[id].grab_focus()
	select_department(id, false)
	get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ build
func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)

	# Rolled-steel concourse ground.
	var wall := Panel.new()
	wall.name = "Wall"
	wall.set_anchors_preset(PRESET_FULL_RECT)
	add_child(wall)

	# Half-open bulkhead at the left edge — daylight spilling through.
	_mouth = BulkheadMouth.new()
	_mouth.name = "BulkheadMouth"
	_mouth.anchor_top = 0.0
	_mouth.anchor_bottom = 1.0
	_mouth.offset_right = 160.0
	add_child(_mouth)

	var margins := _margins_box(56, 24, 28, 18)
	margins.name = "Layout"
	margins.set_anchors_preset(PRESET_FULL_RECT)
	add_child(margins)
	var col := _vbox(16)
	col.name = "Column"
	margins.add_child(col)

	col.add_child(_build_header())
	var body := _hbox(20)
	body.name = "BodyRow"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	body.add_child(_build_plate_wall())
	body.add_child(_build_docket_region())
	col.add_child(_build_console())

	# T18: ORIENTATION FORM O-1 — a posted paper notice at the docket frame's
	# top-right corner (the tutorial is always on the wall), plus the current
	# step's orient_arrow cue beside the destination plate. Both are drawn
	# over the wall/docket boundary, under the bulkhead shutter's z (the door
	# physically closes over posted paper) and under MAIL CALL.
	orientation_form = OrientationForm.new()
	orientation_form.name = "OrientationForm"
	orientation_form.z_index = 4
	orientation_form.dept_label = _dept_hint_for
	orientation_form.step_activated.connect(_on_orientation_step_activated)
	add_child(orientation_form)

	orientation_cue = OrientationCue.new()
	orientation_cue.name = "OrientationCue"
	orientation_cue.z_index = 20  # the run-1 chalk's plane — over the door's slide
	add_child(orientation_cue)

	_position_orientation_form()
	orientation_form.resized.connect(_position_orientation_form)
	header_notice.resized.connect(_position_orientation_form)
	docket_housing.resized.connect(_position_orientation_form)
	docket_housing.resized.connect(_position_orientation_cue)
	resized.connect(_position_orientation_form)
	resized.connect(_position_orientation_cue)
	for plate in _plate_order:
		plate.resized.connect(_position_orientation_cue)

	# T10a overlays: save notices post above the console; the MAIL CALL card
	# dims the concourse while posted (both bound to the engines later —
	# bind_engines() — and hidden until they have something to say).
	save_board = SaveNoticeBoard.new()
	save_board.name = "SaveNoticeBoard"
	save_board.set_anchors_preset(PRESET_FULL_RECT)
	save_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(save_board)

	mail_call = MailCallModal.new()
	mail_call.name = "MailCallModal"
	mail_call.z_index = 40
	add_child(mail_call)
	mail_call.acknowledged.connect(func(payload: Dictionary) -> void:
		mail_call_acknowledged.emit(payload))

func _build_header() -> Control:
	var row := _hbox(20)
	row.name = "HeaderRow"

	# The shelter's facility plate — the game title as signage. Content-
	# bearing plates are PanelContainers: the theme stylebox's content
	# margins become the plate's padding and the labels drive its size.
	var facility := _panel_box("EnamelPlate")
	facility.name = "FacilityPlate"
	facility.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fcol := _vbox(4)
	fcol.add_child(_label("PlateTitle", TITLE))
	fcol.add_child(_label("PlateBody", SUBTITLE))
	fcol.add_child(_label("PlateSerialNavy", FACILITY_SERIAL))
	facility.add_child(fcol)
	row.add_child(facility)

	# Standing posted notice. T18: while the O-1 form is EXPANDED, the form
	# posts over this slot (intake paperwork outranks standing flavor) and the
	# notice stands down; it returns when the form folds to its slip.
	var notice := _panel_box("PaperNotice")
	notice.name = "HeaderNotice"
	notice.custom_minimum_size = Vector2(380.0, 0.0)
	var ncol := _vbox(8)
	var copy := _label("PaperText", HEADER_NOTICE)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ncol.add_child(copy)
	ncol.add_child(_label("PaperStamp", "POSTED — SECTOR B"))
	notice.add_child(ncol)
	row.add_child(notice)
	header_notice = notice
	return row

func _build_plate_wall() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PlateWallScroll"
	scroll.custom_minimum_size = Vector2(360.0, 0.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wall := _vbox(6)
	wall.name = "PlateWall"
	wall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wall)
	for i in DEPARTMENTS.size():
		var d: Dictionary = DEPARTMENTS[i]
		var plate := Button.new()
		plate.name = "Plate_" + d.id
		# T17: the eighth plate (PERSONNEL) made the wall overflow the 720p
		# minimum shell — a scrollable wall breaks the arrow-column contract
		# (Godot's focus-neighbor search skips out-of-view controls) and the
		# orientation cue's settle pass. 50 px plates at 6 px separation keep
		# all eight on the wall at 1280x720 (8*50 + 7*6 = 442 <= 452); larger
		# windows simply breathe more.
		plate.custom_minimum_size = Vector2(340.0, 50.0)
		plate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		plate.text = _plate_text(d, i)
		plate.tooltip_text = "Open the %s docket (press %d)" % [d.plate.capitalize(), i + 1]
		plate.set_meta("dept_id", d.id)
		plate.set_meta("dept_index", i)
		plate.pressed.connect(select_department.bind(d.id, false))
		wall.add_child(plate)
		_plates[d.id] = plate
		_plate_order.append(plate)
	return scroll


## R3: the plate posts its designation digit — the D-0n serial's own number
## and the key that selects the department from anywhere in the concourse.
func _plate_text(d: Dictionary, index: int) -> String:
	return "%s · %d" % [d.plate, index + 1]

func _build_docket_region() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "DocketScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	docket_scroll = scroll
	docket_housing = _panel_box("SteelPanel")
	docket_housing.name = "DocketHousing"
	docket_housing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	docket_housing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	docket_housing.clip_contents = true
	scroll.add_child(docket_housing)

	var dm := _margins_box(24, 18, 24, 18)
	dm.name = "DocketMargin"
	for d in DEPARTMENTS:
		dm.add_child(_build_docket(d))
	docket_housing.add_child(dm)

	# The bulkhead shutter — a riveted slab that slides across the docket on
	# department changes, then slides on and hides.
	shutter = _panel_box("SteelPanel")
	shutter.name = "BulkheadShutter"
	shutter.visible = false
	shutter.z_index = 5
	var scol := _vbox(8)
	scol.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scol.add_child(_label("SectionLabel", "BULKHEAD 09"))
	scol.add_child(_label("MicroLabel", "DEPARTMENT CHANGE IN PROGRESS — STAND CLEAR"))
	shutter.add_child(scol)
	docket_housing.add_child(shutter)
	return scroll

## One department's docket placeholder — T10a/T10b replace the internals; the
## shell (header plate, posted directive, gauge inset, primary action) keeps.
func _build_docket(d: Dictionary) -> Control:
	var col := _vbox(16)
	col.name = "Docket_" + d.id
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.visible = false

	var header := _panel_box("EnamelPlate")
	header.name = "DocketHeader"
	var hcol := _vbox(4)
	hcol.add_child(_label("PlateTitle", d.plate))
	hcol.add_child(_label("PlateSerialNavy", "DOCKET NO. %s · REV. 1958-09" % d.serial))
	header.add_child(hcol)
	col.add_child(header)

	var notice := _panel_box("PaperNotice")
	notice.name = "DocketNotice"
	var ncol := _vbox(8)
	var copy := _label("PaperText", d.notice)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ncol.add_child(copy)
	ncol.add_child(_label("PaperStamp", d.stamp))
	notice.add_child(ncol)
	col.add_child(notice)

	# T10a/T10b: live docket content — every widget renders from ContentDB records
	# and the bound TickManager (no mocked data).
	var controller: Docket = null
	match d.id:
		"scavenging", "foraging":
			controller = DocketGathering.new(d.id)
		"junksmithing", "cooking":
			controller = DocketProcessing.new(d.id)
		"wasteland_patrol":
			controller = DocketPatrol.new()
		"manifest":
			controller = DocketManifest.new()
		"requisition_depot":
			controller = DocketDepot.new()
		"personnel":
			controller = DocketPersonnel.new()
	controller.name = "Content_" + d.id
	controller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(controller)
	_controllers[d.id] = controller

	# The primary action — the big stencled button plate on the docket.
	var begin := Button.new()
	begin.name = "BeginShift_" + d.id
	begin.theme_type_variation = "Energized"
	begin.text = BEGIN_LABEL
	begin.custom_minimum_size = Vector2(300.0, 64.0)
	begin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	begin.tooltip_text = "Begin the department shift"
	begin.pressed.connect(_on_begin_pressed.bind(d.id))
	col.add_child(begin)
	_begin_buttons[d.id] = begin
	if controller is DocketSkill:
		(controller as DocketSkill).primary_button = begin
	elif controller is DocketPatrol:
		(controller as DocketPatrol).primary_button = begin
	elif controller is DocketPersonnel:
		(controller as DocketPersonnel).primary_button = begin

	# T15: the docket's footer serial wraps (its width would otherwise lead
	# the docket at 200% font scale).
	var footer := _label("PlateSerial", "DOCKET %s · PROVISIONAL POSTING · FORM 9-A" % d.serial)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(footer)
	_dockets[d.id] = col
	return col


## The shell's primary button: announce the intent (T9 contract — probes and
## SaveStore listen), then route the action to the docket's controller
## (skill dockets toggle their slot through the engine façade; the patrol
## docket engages/withdraws through the combat façade).
func _on_begin_pressed(id: String) -> void:
	activity_start_requested.emit(id)
	if _controllers.has(id):
		(_controllers[id] as Docket).primary_action()

func _build_console() -> Control:
	var console := _panel_box("SteelPanel")
	console.name = "ConsoleBar"
	# T15: the console row FLOWS — a fixed HBox overflowed the 1280 shell at
	# 200% font scale (CLOCK OUT pushed off-window); the flow keeps one row at
	# 100% and wraps to two at 200%, sacrificing only the old spacer's
	# right-alignment.
	var row := HFlowContainer.new()
	row.name = "ConsoleRow"
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 10)
	console.add_child(row)

	row.add_child(_label("MicroLabel", "FONT SCALE"))

	font_slider = HSlider.new()
	font_slider.name = "FontScaleSlider"
	font_slider.min_value = 0.0
	font_slider.max_value = 2.0
	font_slider.step = 1.0
	font_slider.value = 0.0
	font_slider.tick_count = 3
	font_slider.ticks_on_borders = true
	font_slider.custom_minimum_size = Vector2(150.0, 26.0)
	font_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	font_slider.focus_mode = Control.FOCUS_ALL
	font_slider.tooltip_text = "Text size for all signage: 100, 150 or 200 percent"
	font_slider.value_changed.connect(_on_font_scale_value)
	font_slider.focus_entered.connect(_set_slider_focus.bind(true))
	font_slider.focus_exited.connect(_set_slider_focus.bind(false))
	row.add_child(font_slider)

	font_readout = _label("MonoValue", "100%")
	font_readout.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(font_readout)

	var sep := VSeparator.new()
	row.add_child(sep)

	fullscreen_check = CheckButton.new()
	fullscreen_check.name = "FullscreenCheck"
	fullscreen_check.text = "FULLSCREEN"
	fullscreen_check.tooltip_text = "Fill the resident's screen"
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	row.add_child(fullscreen_check)

	console_serial = _label("PlateSerial", CONSOLE_SERIAL)
	console_serial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(console_serial)

	save_button = Button.new()
	save_button.name = "SaveRecord"
	save_button.text = "FILE RECORD"
	save_button.tooltip_text = "File your record with the Department (save now)"
	save_button.pressed.connect(_on_save_pressed)
	row.add_child(save_button)

	quit_button = Button.new()
	quit_button.name = "ClockOut"
	quit_button.theme_type_variation = "Danger"
	quit_button.text = "CLOCK OUT"
	quit_button.tooltip_text = "End your shift and depart the Shelter (quit)"
	quit_button.pressed.connect(quit_requested.emit)
	row.add_child(quit_button)
	return console

# ------------------------------------------------------------------ state
func _apply_active(id: String, animate: bool) -> void:
	if _active_id != "" and _plates.has(_active_id):
		_set_plate_state(_plates[_active_id], false, animate)
	_active_id = id
	for did in _dockets:
		_dockets[did].visible = (did == id)
	# R1 (refinement critique P1#1/P2#3): a department change opens a FRESH
	# posting, so the docket viewport returns to its content top — the enamel
	# header plate leads, per the docket topology. Without the reset the
	# ScrollContainer keeps whatever offset focus-follow scrolling left behind,
	# which sliced the first visible line to glyph bottoms (instruction
	# headers, wrapped yield serials) and hid the docket header entirely on
	# the first-run screen.
	docket_scroll.scroll_vertical = 0
	_set_plate_state(_plates[id], true, animate)
	if animate:
		var docket: Control = _dockets[id]
		docket.position.x = 28.0
		docket.modulate.a = 0.35
		var settle := create_tween()
		settle.set_parallel(true)
		settle.tween_property(docket, "position:x", 0.0, 0.30) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		settle.tween_property(docket, "modulate:a", 1.0, 0.30) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

## Energized state = amber plate + swell forward + ">> " prefix — three cues,
## one of them non-color (Daredevil: state must not rely on color alone).
func _set_plate_state(plate: Button, energized: bool, animate: bool) -> void:
	var d: Dictionary = _dept_by_id[plate.get_meta("dept_id")]
	var text := _plate_text(d, int(plate.get_meta("dept_index")))
	if energized:
		plate.theme_type_variation = "Energized"
		plate.text = ENERGIZED_PREFIX + text
		plate.z_index = 10
	else:
		plate.theme_type_variation = ""
		plate.text = text
		plate.z_index = 0
	plate.pivot_offset = Vector2(0.0, plate.size.y * 0.5)
	var target := Vector2.ONE * (SWELL if energized else 1.0)
	if plate.has_meta("swell_tween"):
		# A finished tween is auto-freed; its stale meta entry must not be
		# killed (T10a's repeated programmatic selections surfaced this).
		var old_swell := plate.get_meta("swell_tween") as Tween
		if old_swell != null and old_swell.is_valid():
			old_swell.kill()
		plate.remove_meta("swell_tween")
	if animate:
		var tw := create_tween().tween_property(plate, "scale", target, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		plate.set_meta("swell_tween", tw)
	else:
		plate.scale = target

func _on_transition_done(id: String) -> void:
	shutter.visible = false
	_transitioning = false
	department_changed.emit(id)

# ------------------------------------------------------------- T18 O-1 form
## A pressed step row is a wayfinding control: open that step's department
## (the same transition a plate press drives).
func _on_orientation_step_activated(step_id: String) -> void:
	var target := OrientationTracker.step_target(step_id)
	if target != "":
		select_department(target, false)


## Department hint for the form's tooltips ("SCAVENGING · 1" — plate + key).
func _dept_hint_for(dept_id: String) -> String:
	if not _dept_by_id.has(dept_id):
		return ""
	var d: Dictionary = _dept_by_id[dept_id]
	var idx := DEPARTMENTS.find(d)
	return "%s · PRESS %d" % [String(d["plate"]), idx + 1]


## The O-1 form posts in TWO positions, both at the shell's right margin:
## EXPANDED — over the intake notice slot at the top of the shell (intake
## paperwork outranks the standing flavor notice, which stands down while the
## form leads; at 200% font scale the 380 px notice slot is the only anchor
## with vertical room for the full checklist above the console), hanging over
## the docket's top-right corner below it; SLIP — pinned to the docket
## frame's top-right corner. Re-positioned on every resize (window, font
## scale, and the form's own expanded/slip height change).
func _position_orientation_form() -> void:
	if orientation_form == null or docket_housing == null or header_notice == null:
		return
	if docket_housing.size == Vector2.ZERO or header_notice.size == Vector2.ZERO:
		return
	var size := orientation_form.size
	if orientation_form.is_expanded():
		var nr := header_notice.get_global_rect()
		orientation_form.global_position = Vector2(nr.end.x - size.x, nr.position.y)
	else:
		var hr := docket_housing.get_global_rect()
		orientation_form.global_position = Vector2(
			hr.end.x - size.x - 18.0, hr.position.y + 14.0)
	# The standing notice stands down while intake paperwork leads — modulate,
	# never visible=false, so the header row's layout never reflows (the
	# facility plate must not stretch mid-tutorial).
	header_notice.modulate = Color(1.0, 1.0, 1.0, 0.0 if orientation_form.is_expanded() else 1.0)


func _position_orientation_cue() -> void:
	if orientation_cue == null:
		return
	if not orientation_cue.visible:
		return
	var target := ""
	if _tm != null and _tm.has_method("orientation_progress"):
		target = String(_tm.orientation_progress()["target"])
	if target != "" and _plates.has(target):
		orientation_cue.aim(_plates[target], false)

# ------------------------------------------------------------------ console
func _on_font_scale_value(value: float) -> void:
	var scale: float = FONT_STEPS[int(clampf(value, 0.0, 2.0))]
	if _ui_theme != null:
		_ui_theme.apply_font_scale(scale)
	font_readout.text = "%d%%" % roundi(scale * 100.0)
	font_scale_changed.emit(scale)
	# T18: the O-1 form + cue re-position after the scaled layout settles.
	_reposition_orientation_after_layout()


func _reposition_orientation_after_layout() -> void:
	await get_tree().process_frame
	if is_inside_tree():
		_position_orientation_form()
		_position_orientation_cue()

func _set_slider_focus(lit: bool) -> void:
	_slider_focus_lit = lit
	if lit:
		var track := font_slider.get_theme_stylebox("slider").duplicate() as StyleBoxFlat
		track.border_color = SignageTokens.SIGNAL_AMBER
		track.set_border_width_all(2)
		font_slider.add_theme_stylebox_override("slider", track)
	else:
		font_slider.remove_theme_stylebox_override("slider")

func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _on_save_pressed() -> void:
	# Flash the queued state FIRST, then emit the intent: an attached recorder
	# (SaveStore) files synchronously inside the emit and its stamped result
	# replaces this flash instantly; with no recorder attached the queued
	# flash is what the resident sees.
	_flash_serial("RECORD QUEUED.")
	save_requested.emit()


## T3 wiring: SaveStore's save_completed lands here — the queued flash is
## replaced by the stamped result (filing is synchronous; the stamp carries
## the wall-clock moment the Department accepted the record). A refused
## filing (blocked by a newer on-disk record, disk failure) posts a notice
## line instead of a false all-clear.
func mark_record(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var stamp := Time.get_time_string_from_unix_time(int(result.get("unix_ms", 0)) / 1000)
		_flash_serial("RECORD FILED · %s" % stamp)
	else:
		_flash_serial("RECORD NOT FILED — NOTICE POSTED")


## One transient console-serial message: bumps the token so a newer message
## cancels an older one's restore, then restores the standing serial after
## two seconds.
func _flash_serial(text: String) -> void:
	_serial_token += 1
	var token := _serial_token
	console_serial.text = text
	await get_tree().create_timer(2.0).timeout
	if token == _serial_token:
		console_serial.text = CONSOLE_SERIAL

func _set_mouth_energy(value: float) -> void:
	_mouth.set_energy(value)

# ------------------------------------------------------------------ helpers
## Scroll every ScrollContainer ancestry of the newly focused control so the
## focus is actually on screen (keyboard focus-follow, T15).
func _on_shell_focus_changed(node: Node) -> void:
	if not (node is Control):
		return
	var c := node as Control
	var cur: Node = c.get_parent()
	while cur != null:
		if cur is ScrollContainer:
			(cur as ScrollContainer).ensure_control_visible(c)
		cur = cur.get_parent()


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		var blocked := c is BaseButton and (c as BaseButton).disabled
		if c.focus_mode != Control.FOCUS_NONE and not blocked \
				and c.is_visible_in_tree():
			out.append(c)
	for child in node.get_children():
		_collect_focusable(child, out)

func _panel(variation: String) -> Panel:
	var p := Panel.new()
	if not variation.is_empty():
		p.theme_type_variation = variation
	return p

## Content-bearing plate: a PanelContainer under the same theme variation —
## the stylebox's content margins become padding and the children drive the
## plate's size (a plain Panel ignores content minimums in Godot).
func _panel_box(variation: String) -> PanelContainer:
	var p := PanelContainer.new()
	if not variation.is_empty():
		p.theme_type_variation = variation
	return p

func _label(variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l

func _vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

func _vbox_h(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

func _hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

func _margins_box(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m

# ------------------------------------------------------------------ scenery
## The half-open bulkhead at the concourse's left edge: wasteland daylight
## through the slit, the door slab edge with its bolts, and a thin wash of
## light across the steel. Pulses while the shutter slides.
class BulkheadMouth:
	extends Control
	var energy := 0.0

	func set_energy(value: float) -> void:
		energy = value
		queue_redraw()

	func _draw() -> void:
		var t := SignageTokens
		var h := size.y
		# daylight wash across the wall (fades fast — a slit, not a window)
		draw_rect(Rect2(30, 0, 130, h), Color(t.SIGNAL_AMBER, 0.035))
		draw_rect(Rect2(30, 0, 64, h), Color(t.SIGNAL_AMBER, 0.07 + 0.06 * energy))
		# the slit core: bone daylight with a warm wash that pulses
		draw_rect(Rect2(7, 0, 11, h), t.BONE_ENAMEL)
		draw_rect(Rect2(7, 0, 11, h), Color(t.SIGNAL_AMBER, 0.16 + 0.22 * energy))
		# the door slab edge, slid half open
		draw_rect(Rect2(18, 0, 16, h), t.STEEL_LO)
		draw_rect(Rect2(18, 0, 2, h), t.STEEL_HI)
		var y := 42.0
		while y < h:
			draw_circle(Vector2(26, y), 2.3, t.STEEL_HI)
			y += 96.0

## T18 — the current orientation step's cue: the orient_arrow glyph (amber,
## heavy chevron) posted beside the destination plate, pointing at it. The
## arrow class exists only while orientation is incomplete (it retires with
## the tutorial, per the icon-grammar addendum); a step change is the one
## authored moment — a bounded arrival swell, never a looping pulse. Mouse
## transparent: it is a mark on the wall, not a control (the O-1 form's row
## is the interactive twin of this cue).
class OrientationCue:
	extends Control

	var glyph: TextureRect

	func _init() -> void:
		custom_minimum_size = Vector2(36.0, 36.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false
		glyph = TextureRect.new()
		var tex: Texture2D = load("res://assets/icons/orient_arrow.svg")
		if tex != null:
			glyph.texture = tex
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.set_anchors_preset(PRESET_FULL_RECT)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The glyph ships pointing right (toward rising x); posted at the
		# plate's right shoulder it must point LEFT — into the plate it names.
		glyph.rotation = PI
		add_child(glyph)

	## Post beside `plate` (right shoulder, vertically centered, clamped
	## inside the shell). `animate` plays the arrival swell on a step change.
	func aim(plate: Control, animate: bool) -> void:
		if plate == null or plate.size.y <= 0.0:
			return
		var gr := plate.get_global_rect()
		size = Vector2(36.0, 36.0)
		global_position = Vector2(gr.end.x + 4.0,
			maxf(gr.get_center().y - size.y * 0.5, 8.0))
		pivot_offset = size * 0.5
		if animate:
			scale = Vector2(0.72, 0.72)
			var tw := create_tween()
			tw.tween_property(self, "scale", Vector2.ONE, 0.26) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif scale != Vector2.ONE:
			scale = Vector2.ONE
