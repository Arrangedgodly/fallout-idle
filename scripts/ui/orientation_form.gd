class_name OrientationForm
extends PanelContainer
## OrientationForm — T18 the posted ORIENTATION FORM O-1 (naming-bible §10/§14
## verbatim copy; design-brief addendum "Orientation — the posted paper form").
##
## A posted paper notice taped to the docket frame's top-right corner (the
## concourse mounts + positions this control), NOT a modal: the tutorial is
## always on the wall. Two states —
##   EXPANDED (incomplete): title + intake serial + the seven stencil lines
##     (step mark + verbatim title + the stamp slot). The current step row
##     carries the orient_arrow glyph pointing at the plate wall and jumps to
##     its department on press; stamped rows show the red stamp_check and dim
##     to the registered NAVY_DIM-on-paper pair; future rows show the empty
##     box. Foldable to the slip only once >= 5 steps are stamped (early on
##     the tutorial IS the priority — the fold control appears once the
##     resident knows the shelter).
##   SLIP (completed, or folded): the posted-record chip — title + seven mini
##     stamp boxes (+ the red mark at completion) + OPEN. Posted records
##     never vanish; the slip is the re-view control.
## Completion swaps the checklist for the record: the DULY ORIENTED · FORM O-1
## stamp + the ORIENTATION STIPEND line (amount from data/staffing.json,
## never hardcoded), holds for one bounded beat, then settles into the slip.
##
## LOW-TEXT PIN (the user's complaint is law): every visible word on the form
## is budgeted — 33 expanded-incomplete, 18 expanded-complete, 5 on the slip
## (word_count() walks it; tests/test_orientation.gd pins <= 40 per state).
##
## Update discipline: the Docket contract — rows are built once and restyled
## only through guarded setters; refreshes ride the 4 Hz "orientation" bulk
## region and the two immediate discrete signals. Cues are never color-alone:
## the stamp glyph (filled box vs empty box) IS the done state; the arrow
## glyph IS the current state; the fold control is a labeled button.

signal step_activated(step_id: String)

const TITLE := "ORIENTATION FORM O-1"
const INTAKE_SERIAL := "POSTED AT INTAKE · D.O.C.S. FORM O-1"
const FOLD_LABEL := "FOLD"
const OPEN_LABEL := "OPEN"
const STAMP_LINE := "DULY ORIENTED · FORM O-1"
const STIPEND_LINE := "ORIENTATION STIPEND — %s CROWNS · THANK YOU FOR YOUR PROMPT COMPLIANCE."
const COLLAPSE_AT_STEPS := 5  ## the fold control posts at >= 5 stamped steps

## Display metadata per step (titles are naming-bible §10 VERBATIM; the mark
## glyphs are the T19 grammar pair stamp_check/orient_arrow). Step targets
## come from OrientationTracker.STEP_TARGETS — the engine owns the mapping.
const STEP_TITLES := {
	OrientationTracker.STEP_WORK_SHIFT: "WORK A POSTED SHIFT",
	OrientationTracker.STEP_EARN_CLEARANCE: "EARN A CLEARANCE",
	OrientationTracker.STEP_FILE_CROWNS_CLAIM: "FILE A CROWNS CLAIM",
	OrientationTracker.STEP_PROCESS_PRODUCT: "PROCESS A PRODUCT",
	OrientationTracker.STEP_PROVISION_PATROL: "PROVISION THE PATROL",
	OrientationTracker.STEP_CLEAR_NUISANCE: "CLEAR A NUISANCE",
	OrientationTracker.STEP_DEPUTIZE_RESIDENT: "DEPUTIZE A RESIDENT",
}
const STEP_ICONS := {
	OrientationTracker.STEP_WORK_SHIFT: "scavenging",
	OrientationTracker.STEP_EARN_CLEARANCE: "clearance_step",
	OrientationTracker.STEP_FILE_CROWNS_CLAIM: "crowns",
	OrientationTracker.STEP_PROCESS_PRODUCT: "junksmithing",
	OrientationTracker.STEP_PROVISION_PATROL: "cooking",
	OrientationTracker.STEP_CLEAR_NUISANCE: "junkyard_roach",
	OrientationTracker.STEP_DEPUTIZE_RESIDENT: "deputy_badge",
}

const ICON_DIR := "res://assets/icons/"
const MINI_SIZE := 12
const FORM_MIN_WIDTH := 296.0
const CELEBRATE_S := 2.6  ## the completion record's bounded beat before the slip

var tm: Node = null  # TickManager instance (soft-typed: compiles under --check-only)

var _col: VBoxContainer
var _serial_label: Label
var _slip_marks: HBoxContainer
var _mini_marks: Dictionary = {}  # step_id -> MiniMark
var _rows_box: VBoxContainer
var _done_box: VBoxContainer
var _stipend_line: Label
var _fold_button: Button
var _open_button: Button

var _rows: Dictionary = {}  # step_id -> StepRow
var _row_order: Array[String] = []
var _expanded := true
var _celebrating := false
## Concourse callback (dept_id -> "SCAVENGING · 1"-style hint for tooltips).
var dept_label: Callable = Callable()


func _init() -> void:
	name = "OrientationForm"
	theme_type_variation = "PaperNotice"
	custom_minimum_size = Vector2(FORM_MIN_WIDTH, 0.0)
	_build()


# ------------------------------------------------------------------ build --
func _build() -> void:
	_col = VBoxContainer.new()
	_col.name = "FormColumn"
	_col.add_theme_constant_override("separation", 7)
	add_child(_col)

	var title_label := _label("PaperTitle", TITLE)
	title_label.name = "FormTitle"
	_col.add_child(title_label)

	_serial_label = _label("PlateSerialNavy", INTAKE_SERIAL)
	_serial_label.name = "IntakeSerial"
	_col.add_child(_serial_label)

	# Slip progress: seven mini stamp boxes (the fill is the state) — icon-only
	# by design, zero words.
	_slip_marks = HBoxContainer.new()
	_slip_marks.name = "SlipMarks"
	_slip_marks.add_theme_constant_override("separation", 5)
	for step_id: String in OrientationTracker.STEPS:
		var mark := MiniMark.new()
		mark.name = "SlipMark_" + step_id
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slip_marks.add_child(mark)
		_mini_marks[step_id] = mark
	_slip_marks.add_child(_glyph("stamp_check", MINI_SIZE + 8, "SlipStamp"))
	_col.add_child(_slip_marks)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "StepRows"
	_rows_box.add_theme_constant_override("separation", 3)
	_col.add_child(_rows_box)
	for step_id: String in OrientationTracker.STEPS:
		var row := StepRow.new(step_id, String(STEP_TITLES[step_id]),
			String(STEP_ICONS[step_id]))
		row.pressed.connect(_on_row_pressed.bind(step_id))
		_rows_box.add_child(row)
		_rows[step_id] = row
		_row_order.append(step_id)

	# The completion record (replaces the checklist once DULY ORIENTED posts).
	_done_box = VBoxContainer.new()
	_done_box.name = "CompletionRecord"
	_done_box.add_theme_constant_override("separation", 6)
	var stamp_row := HBoxContainer.new()
	stamp_row.name = "StampRow"
	stamp_row.add_theme_constant_override("separation", 8)
	stamp_row.add_child(_glyph("stamp_check", 24, "StampGlyph"))
	var stamp_line := _label("PaperStamp", STAMP_LINE)
	stamp_line.name = "StampLine"
	stamp_row.add_child(stamp_line)
	_done_box.add_child(stamp_row)
	var stipend_row := HBoxContainer.new()
	stipend_row.name = "StipendRow"
	stipend_row.add_theme_constant_override("separation", 8)
	stipend_row.add_child(_glyph("crowns", 20, "StipendCrowns"))
	_stipend_line = _label("PlateSerialNavy", "")
	_stipend_line.name = "StipendLine"
	_stipend_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stipend_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stipend_row.add_child(_stipend_line)
	_done_box.add_child(stipend_row)
	_col.add_child(_done_box)

	_fold_button = Button.new()
	_fold_button.name = "FoldForm"
	_fold_button.text = FOLD_LABEL
	_fold_button.tooltip_text = "Fold Form O-1 to its posted slip (stamped steps stay stamped)"
	_fold_button.pressed.connect(fold)
	_col.add_child(_fold_button)

	_open_button = Button.new()
	_open_button.name = "OpenForm"
	_open_button.text = OPEN_LABEL
	_open_button.tooltip_text = "Re-view Orientation Form O-1"
	_open_button.pressed.connect(expand)
	_col.add_child(_open_button)


# --------------------------------------------------------- bind + refresh --
const TM_SIGNALS := ["bulk_state_changed", "orientation_step_done", "orientation_completed"]
var _handlers := {}


## Wire to a TickManager (production autoload or a never-in-tree test twin);
## rebinding disconnects the old manager first (the Docket bind contract).
func bind(p_tm: Node) -> void:
	if tm == p_tm and p_tm != null:
		return
	unbind()
	tm = p_tm
	if tm == null:
		return
	_handlers = {
		"bulk_state_changed": _on_bulk_state_changed,
		"orientation_step_done": _on_step_done,
		"orientation_completed": _on_completed,
	}
	for s in TM_SIGNALS:
		(tm.get(s) as Signal).connect(_handlers[s])
	refresh()
	# A COMPLETED record boots as the posted slip (the celebration already
	# happened in the session that stamped the seventh line); re-view via OPEN.
	if bool(_progress()["complete"]):
		_expanded = false
		refresh()


func unbind() -> void:
	if tm != null and not _handlers.is_empty():
		for s in TM_SIGNALS:
			var sig: Signal = tm.get(s)
			if sig.is_connected(_handlers[s]):
				sig.disconnect(_handlers[s])
	tm = null
	_handlers = {}


## First-run application (SaveStore owns the detection): a brand-new resident
## meets the form EXPANDED with step 1 cued — the five-second contract.
func apply_first_run(on: bool) -> void:
	if on:
		_expanded = true
	refresh()


func is_expanded() -> bool:
	return _expanded


func is_foldable(count: int) -> bool:
	return count >= COLLAPSE_AT_STEPS


func expand() -> void:
	_expanded = true
	refresh()


func fold() -> void:
	_expanded = false
	refresh()


func row_for(step_id: String) -> StepRow:
	return _rows.get(step_id)


func step_rows() -> Array:
	return _rows_box.get_children()


func _on_bulk_state_changed(changes: Dictionary) -> void:
	if changes.has("orientation"):
		refresh()


func _on_step_done(_step_id: String) -> void:
	refresh()


## The seventh stamp: the record replaces the checklist for one bounded beat
## (the restrained celebration — no modal, one swell), then the form settles
## into its posted slip.
func _on_completed(_payload: Dictionary) -> void:
	_expanded = true
	_celebrating = true
	refresh()
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_done_box, "scale", Vector2(1.06, 1.06), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_done_box, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(CELEBRATE_S).timeout
	_celebrating = false
	if not is_inside_tree():
		return
	_expanded = false
	refresh()


## One full re-read of the engine truth. Restyle-only: every toggle is a
## guarded comparison, so a 4 Hz flush never churns controls for static state.
func refresh() -> void:
	var p: Dictionary = _progress()
	var complete: bool = bool(p["complete"])
	var count: int = int(p["count"])
	var done: Dictionary = p["done"]
	var current := String(p["current"])
	_done_box.visible = complete
	_rows_box.visible = not complete
	_serial_label.visible = not complete and _expanded
	_slip_marks.visible = complete or not _expanded
	_fold_button.visible = _expanded and (complete or count >= COLLAPSE_AT_STEPS)
	_open_button.visible = not _expanded
	if complete:
		_set_stipend(int(p["stipend"]))
	for step_id: String in _row_order:
		(_rows[step_id] as StepRow).apply(
			bool(done.get(step_id, false)), step_id == current,
			_dept_hint(OrientationTracker.step_target(step_id)))
		(_mini_marks[step_id] as MiniMark).set_stamped(bool(done.get(step_id, false)))


func _set_stipend(amount: int) -> void:
	var text := STIPEND_LINE % SignageFmt.num(amount)
	if _stipend_line.text != text:
		_stipend_line.text = text


func _progress() -> Dictionary:
	if tm != null and tm.has_method("orientation_progress"):
		return tm.orientation_progress()
	return {"done": {}, "count": 0, "total": OrientationTracker.STEPS.size(),
		"complete": false, "current": "", "target": "", "stipend": 0}


func _dept_hint(dept_id: String) -> String:
	if dept_id == "" or not dept_label.is_valid():
		return ""
	return String(dept_label.call(dept_id))


func _on_row_pressed(step_id: String) -> void:
	step_activated.emit(step_id)


# ------------------------------------------------------------- word audit --
## Every visible word on the form (tokens carrying at least one alphanumeric;
## separators like "·" are not words). The low-text pin: <= 40 per state.
func word_count() -> int:
	if not is_inside_tree() or not is_visible_in_tree():
		return 0
	return _subtree_word_count(_col)


func _subtree_word_count(node: Node) -> int:
	if not (node is Control):
		return 0
	var c := node as Control
	if not c.is_visible_in_tree():
		return 0
	var words := 0
	if c is Label:
		words += _count_words((c as Label).text)
	elif c is Button:
		words += _count_words((c as Button).text)
	for child in c.get_children():
		words += _subtree_word_count(child)
	return words


static func _count_words(text: String) -> int:
	var n := 0
	for token in text.split(" ", false):
		var has_alnum := false
		for ch in token:
			if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
				has_alnum = true
				break
		if has_alnum:
			n += 1
	return n


# ---------------------------------------------------------------- helpers --
func _label(variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _glyph(icon_id: String, size: int, glyph_name: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = glyph_name
	var tex: Texture2D = load(ICON_DIR + icon_id + ".svg")
	if tex != null:
		t.texture = tex
	t.custom_minimum_size = Vector2(float(size), float(size))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


# ============================================================== mini mark ==
## The slip's progress box: drawn geometry — navy outline (unstamped) vs the
## red stamp glyph (stamped). The fill is the state, never color alone.
class MiniMark:
	extends Control

	const STAMP_TEX := preload("res://assets/icons/stamp_check.svg")

	var stamped := false

	func _init() -> void:
		custom_minimum_size = Vector2(12.0, 12.0)

	func set_stamped(on: bool) -> void:
		if stamped == on:
			return
		stamped = on
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if stamped:
			draw_texture_rect(STAMP_TEX, r, false)
		else:
			draw_rect(r, Color(SignageTokens.INSTITUTIONAL_NAVY, 0.85), false, 2.0)


# ================================================================ step row ==
## One stencil line: [state glyph][step mark][title]. The leading glyph is the
## state pair — empty box (future) / orient_arrow aimed at the plate wall
## (current) / red stamp_check (done) — so every state reads without color.
## StepRow rides Docket.CardButton's sizing (a plain Button ignores child
## content minimums — the T15 lesson). Flat paper styling: transparent normal
## state, faint navy hover/press; the theme's amber Button focus ring is
## inherited untouched.
class StepRow:
	extends "res://scripts/ui/docket.gd".CardButton

	var step_id := ""
	var arrow: TextureRect
	var stamp: TextureRect
	var empty_box: Control
	var mark: TextureRect
	var title: Label

	var _kind := ""  # "", "future", "current", "done" — guards restyle churn


	func _init(p_step: String, p_title: String, p_icon: String) -> void:
		step_id = p_step
		name = "Step_" + p_step
		focus_mode = Control.FOCUS_ALL
		tooltip_text = "Orientation step: %s" % p_title
		_flat_stylebox("normal", Color(0, 0, 0, 0.0))
		_flat_stylebox("hover", Color(SignageTokens.INSTITUTIONAL_NAVY, 0.07))
		_flat_stylebox("pressed", Color(SignageTokens.INSTITUTIONAL_NAVY, 0.13))
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)

		arrow = _glyph("orient_arrow", 18)
		arrow.name = "ArrowGlyph"
		# The form posts at the docket's right edge; the plate wall is LEFT —
		# the row's arrow points that way (the plate cue points back at it).
		arrow.rotation = PI
		arrow.pivot_offset = Vector2(9.0, 9.0)
		row.add_child(arrow)
		stamp = _glyph("stamp_check", 18)
		stamp.name = "StampGlyph"
		row.add_child(stamp)
		empty_box = EmptyBox.new()
		empty_box.name = "EmptyBox"
		empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(empty_box)

		mark = _glyph(p_icon, 20)
		row.add_child(mark)

		title = Label.new()
		title.name = "Title"
		title.theme_type_variation = "PaperText"
		title.text = p_title
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		add_child(row)


	func _glyph(icon_id: String, size: int) -> TextureRect:
		var t := TextureRect.new()
		var tex: Texture2D = load("res://assets/icons/" + icon_id + ".svg")
		if tex != null:
			t.texture = tex
		t.custom_minimum_size = Vector2(float(size), float(size))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return t


	func _flat_stylebox(state_name: String, tint: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = tint
		sb.set_corner_radius_all(2)
		add_theme_stylebox_override(state_name, sb)


	## CardButton._sync_min REPLACES custom_minimum_size (it does not max with
	## it), so the WCAG 2.5.8 hit-target floor is re-asserted on top of the
	## content-derived minimum (T15's 24 px discipline).
	func _sync_min() -> void:
		super._sync_min()
		custom_minimum_size = Vector2(
			custom_minimum_size.x, maxf(custom_minimum_size.y, 26.0))


	## Restyle to the state (guarded — a no-change refresh touches nothing).
	## done dims the title to the registered NAVY_DIM-on-paper pair (T8's
	## contrast table carries it; never a mid-air alpha guess).
	func apply(done: bool, current: bool, dept_hint: String) -> void:
		var kind := "done" if done else ("current" if current else "future")
		if kind == _kind:
			return
		_kind = kind
		arrow.visible = kind == "current"
		stamp.visible = kind == "done"
		empty_box.visible = kind == "future"
		var ink: Color = SignageTokens.NAVY_DIM if done else SignageTokens.INSTITUTIONAL_NAVY
		title.add_theme_color_override("font_color", ink)
		var t := String(title.text)
		if done:
			tooltip_text = "Stamped: %s — verified complete." % t
		elif current:
			tooltip_text = "Do this now: open %s." % dept_hint if dept_hint != "" \
				else "Do this now: %s." % t
		else:
			tooltip_text = "Queued orientation step: %s." % t


	## The unstamped slot: a drawn navy outline box (the empty half of the
	## stamp_check state pair — the fill is the state, never color alone).
	class EmptyBox:
		extends Control

		func _init() -> void:
			custom_minimum_size = Vector2(14.0, 14.0)

		func _draw() -> void:
			draw_rect(Rect2(Vector2.ZERO, size),
				Color(SignageTokens.INSTITUTIONAL_NAVY, 0.8), false, 2.0)
