class_name OrientationForm
extends PanelContainer
## OrientationForm — T18 the posted ORIENTATION FORM O-1 (naming-bible §10/§14
## verbatim copy; design-brief addendum "Orientation — the posted paper form"),
## T29 re-docked after the user's blockade report.
##
## A DOCKED posted-paper strip at the top of the docket region (the concourse
## mounts it inside the docket column's layout, above the docket scroll), NOT a
## modal and — since T29 — NEVER an overlay: the strip takes layout space and
## the docket viewport resizes around it, so no control can ever sit under the
## paper (the run-3 defect: the form floated at z 4 over the docket's top-right
## corner, had no fold control below 5 stamps, and ate every click inside its
## rect — see production-log T29). Two states —
##   EXPANDED (incomplete or re-viewed): the paper header row (title + intake
##     serial + the FOLD control at the strip's right edge — posted from the
##     very first run, step 0) over an internally-scrolling checklist body:
##     the seven stencil lines (step mark + verbatim title + the stamp slot),
##     capped so the docket viewport always keeps the majority of the region.
##     The current step row carries the orient_arrow glyph pointing at the
##     plate wall and jumps to its department on press; stamped rows show the
##     red stamp_check and dim to the registered NAVY_DIM-on-paper pair;
##     future rows show the empty box.
##   SLIP (folded, or completed): the one-line posted-record chip — title +
##     seven mini stamp boxes (+ the red mark at completion) + OPEN in the
##     same right-edge slot. Posted records never vanish; the slip is the
##     re-view control.
## Auto-fold at >= 5 stamped steps stays as a convenience (fires once, the
## moment the fifth line stamps; a manual OPEN afterwards sticks for the rest
## of the tutorial). Completion swaps the checklist for the record: the DULY
## ORIENTED · FORM O-1 stamp + the ORIENTATION STIPEND line (amount from
## data/staffing.json, never hardcoded), holds for one bounded beat, then
## settles into the slip.
##
## LOW-TEXT PIN (the user's complaint is law): every visible word on the form
## is budgeted — 33 expanded-incomplete (37 worst case since T33, when the
## current step carries its one honest prerequisite suffix), 18
## expanded-complete, 4 on the slip (word_count() walks it;
## tests/test_orientation.gd pins <= 40 per state).
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
const COLLAPSE_AT_STEPS := 5  ## the auto-fold convenience fires at >= 5 stamped steps
## The docked strip's checklist body is budgeted so the docket viewport below
## keeps AT LEAST DOCKET_VIEWPORT_FLOOR of the docket region at every scale —
## the strip takes layout space (T29: never an overlay) but never starves the
## docket; whatever does not fit the budget scrolls INSIDE the strip.
const DOCKET_VIEWPORT_FLOOR := 168.0
const BODY_MAX := 402.0
const BODY_MIN := 24.0
const FORM_CHROME_Y := 30.0  ## paper stylebox margins + column separation
const BUDGET_SAFETY := 6.0   ## never plan to the last pixel

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
const CELEBRATE_S := 2.6  ## the completion record's bounded beat before the slip

var tm: Node = null  # TickManager instance (soft-typed: compiles under --check-only)

var _col: VBoxContainer
var _header_row: HBoxContainer
var _serial_label: Label
var _slip_marks: HBoxContainer
var _mini_marks: Dictionary = {}  # step_id -> MiniMark
var _body_scroll: ScrollContainer
var _rows_box: VBoxContainer
var _done_box: VBoxContainer
var _stipend_line: Label
var _fold_button: Button
var _open_button: Button

var _rows: Dictionary = {}  # step_id -> StepRow
var _row_order: Array[String] = []
var _expanded := true
var _celebrating := false
var _auto_folded := false  ## the >= 5 convenience fires once per tutorial
var _complete_flag := false  ## last-read completion (drives the serial tier)
## Concourse callback (dept_id -> "SCAVENGING · 1"-style hint for tooltips).
var dept_label: Callable = Callable()
## T33 deep-linking: Concourse callback (step_id -> {"suffix": String,
## "dept": String}) for the CURRENT step — the honest prerequisite suffix
## when the step's action is not yet reachable (e.g. "WORK FOR INVENTORY
## FIRST" while the counter has nothing to tender) and the department the
## reveal actually cues (the action's honest SOURCE on the fallback paths).
## Registered wording (naming-bible §10 T33 rows); the words ride the step
## line itself, so the prerequisite is stated where the step is read, never
## only in a tooltip.
var reveal_info: Callable = Callable()


func _init() -> void:
	name = "OrientationForm"
	theme_type_variation = "PaperNotice"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _notification(what: int) -> void:
	# The docket region's height sets the checklist body's budget (the strip
	# keeps the docket the majority at every window size) — re-apply on every
	# layout pass that changes our own rect.
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_apply_body_budget.call_deferred()


# ------------------------------------------------------------------ build --
func _build() -> void:
	_col = VBoxContainer.new()
	_col.name = "FormColumn"
	_col.add_theme_constant_override("separation", 6)
	add_child(_col)

	# The strip's header row — the one line that is ALWAYS posted: title (+
	# intake serial while the checklist leads), the slip's progress marks,
	# and the edge control: FOLD while expanded, OPEN while slipped. T29: the
	# FOLD control posts from the very first run (step 0) — the run-3 build
	# withheld it below 5 stamps and the resident had no way to fold.
	_header_row = HBoxContainer.new()
	_header_row.name = "FormHeader"
	_header_row.add_theme_constant_override("separation", 12)
	_col.add_child(_header_row)

	var title_col := VBoxContainer.new()
	title_col.name = "TitleCol"
	title_col.add_theme_constant_override("separation", 1)
	var title_label := _label("PaperTitle", TITLE)
	title_label.name = "FormTitle"
	title_col.add_child(title_label)
	_serial_label = _label("PlateSerialNavy", INTAKE_SERIAL)
	_serial_label.name = "IntakeSerial"
	title_col.add_child(_serial_label)
	_header_row.add_child(title_col)

	# Slip progress: seven mini stamp boxes (the fill is the state) — icon-only
	# by design, zero words. Rides the header line so the slip is ONE line.
	_slip_marks = HBoxContainer.new()
	_slip_marks.name = "SlipMarks"
	_slip_marks.add_theme_constant_override("separation", 5)
	_slip_marks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for step_id: String in OrientationTracker.STEPS:
		var mark := MiniMark.new()
		mark.name = "SlipMark_" + step_id
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slip_marks.add_child(mark)
		_mini_marks[step_id] = mark
	_slip_marks.add_child(_glyph("stamp_check", MINI_SIZE + 8, "SlipStamp"))
	_header_row.add_child(_slip_marks)

	var spacer := Control.new()
	spacer.name = "HeaderSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_row.add_child(spacer)

	_fold_button = Button.new()
	_fold_button.name = "FoldForm"
	_fold_button.text = FOLD_LABEL
	_fold_button.tooltip_text = "Fold Form O-1 to its posted slip (stamped steps stay stamped)"
	_fold_button.pressed.connect(fold)
	_header_row.add_child(_fold_button)

	_open_button = Button.new()
	_open_button.name = "OpenForm"
	_open_button.text = OPEN_LABEL
	_open_button.tooltip_text = "Re-view Orientation Form O-1"
	_open_button.pressed.connect(expand)
	_header_row.add_child(_open_button)

	# The checklist body — docked layout space, internally scrolled so the
	# strip can never push the docket's interactive controls off-screen (the
	# body budget keeps the docket viewport the majority of the region).
	_body_scroll = ScrollContainer.new()
	_body_scroll.name = "FormBody"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_child(_body_scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "StepRows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 3)
	_body_scroll.add_child(_rows_box)
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
	_done_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_body_scroll.add_child(_done_box)


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
	_complete_flag = complete
	# A fresh tutorial (new game) re-arms the auto-fold convenience.
	if count < COLLAPSE_AT_STEPS and not complete:
		_auto_folded = false
	# The >= 5 convenience: the moment the fifth line stamps, the form folds
	# itself to the slip — once (a later manual OPEN sticks for the rest of
	# the tutorial; completion re-expands for its own bounded beat).
	if not complete and not _celebrating and _expanded and not _auto_folded \
			and count >= COLLAPSE_AT_STEPS:
		_auto_folded = true
		_expanded = false
	_done_box.visible = complete
	_rows_box.visible = not complete
	_body_scroll.visible = _expanded
	_slip_marks.visible = complete or not _expanded
	_fold_button.visible = _expanded
	_open_button.visible = not _expanded
	if complete:
		_set_stipend(int(p["stipend"]))
	for step_id: String in _row_order:
		var suffix := ""
		var hint := _dept_hint(OrientationTracker.step_target(step_id))
		if step_id == current and reveal_info.is_valid():
			var info: Dictionary = reveal_info.call(step_id)
			suffix = String(info.get("suffix", ""))
			var resolved := String(info.get("dept", ""))
			if resolved != "":
				hint = _dept_hint(resolved)
		(_rows[step_id] as StepRow).apply(
			bool(done.get(step_id, false)), step_id == current, hint, suffix)
		(_mini_marks[step_id] as MiniMark).set_stamped(bool(done.get(step_id, false)))
	_apply_body_budget()


func _set_stipend(amount: int) -> void:
	var text := STIPEND_LINE % SignageFmt.num(amount)
	if _stipend_line.text != text:
		_stipend_line.text = text


## Budget the checklist body from the REAL layout: the docket region's other
## rows (save-notice strip when posted, the docket scroll's own floor) get
## their minimums first, then the strip's header, then whatever remains is
## the checklist body (scrolling internally). At tight budgets the intake
## serial line stands down FIRST (the responsive tier — the title, the marks,
## the FOLD control and at least BODY_MIN of checklist always stay posted),
## so no scale can push the docket below its floor. Standalone mounts (unit
## tests) are unconstrained.
func _apply_body_budget() -> void:
	if _body_scroll == null or not is_inside_tree():
		return
	var budget := BODY_MAX
	var serial_roomy := true
	var region := get_parent()
	if region != null and region is Control and (region as Control).size.y > 0.0:
		var reserved := 0.0
		var visible_siblings := 0
		for sibling in (region as Control).get_children():
			if not (sibling is Control) or sibling == self:
				continue
			if not (sibling as Control).is_visible_in_tree():
				continue
			if sibling is ScrollContainer:
				# The docket viewport's bar is the FLOOR the audit pins (its
				# structural backstop is lower) — reserve the bar, not the
				# backstop, so the pin holds by construction.
				reserved += maxf((sibling as Control).get_combined_minimum_size().y,
					DOCKET_VIEWPORT_FLOOR)
			else:
				reserved += (sibling as Control).get_combined_minimum_size().y
			visible_siblings += 1
		var sep: float = (region as VBoxContainer).get_theme_constant("separation") \
			if region is VBoxContainer else 0.0
		reserved += sep * float(visible_siblings)
		var header_h: float = _header_row.get_combined_minimum_size().y
		var base: float = (region as Control).size.y - reserved - FORM_CHROME_Y \
			- header_h - BUDGET_SAFETY
		var serial_h: float = _serial_label.get_combined_minimum_size().y
		serial_roomy = base - serial_h >= BODY_MIN
		budget = clampf(base - (serial_h if serial_roomy else 0.0), BODY_MIN, BODY_MAX)
	# The serial tier (budget-driven, never loses the title or the FOLD).
	_serial_label.visible = _complete_flag == false and _expanded and serial_roomy
	if _expanded:
		var need: float = _rows_box.get_combined_minimum_size().y \
			if _rows_box.visible else _done_box.get_combined_minimum_size().y
		_body_scroll.custom_minimum_size.y = minf(need, budget)
	else:
		_body_scroll.custom_minimum_size.y = 0.0


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
	var base_title := ""
	var arrow: TextureRect
	var stamp: TextureRect
	var empty_box: Control
	var mark: TextureRect
	var title: Label

	var _kind := ""  # "", "future", "current", "done" — guards restyle churn
	var _key := ""  # kind + "|" + suffix — the full guarded restyle key


	func _init(p_step: String, p_title: String, p_icon: String) -> void:
		step_id = p_step
		base_title = p_title
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
		# The form posts in the docket region; the plate wall is LEFT — the
		# row's arrow points that way (the plate cue points back at it).
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
	## T33: `suffix` is the honest prerequisite line ("" mostly) — appended to
	## the CURRENT row's stencil title when the step's action is not yet
	## reachable (the naming-bible titles stay verbatim; the suffix is the
	## registered mechanism that states what must happen FIRST).
	func apply(done: bool, current: bool, dept_hint: String, suffix := "") -> void:
		var kind := "done" if done else ("current" if current else "future")
		var key := kind + "|" + suffix
		if key == _key:
			return
		_key = key
		_kind = kind
		arrow.visible = kind == "current"
		stamp.visible = kind == "done"
		empty_box.visible = kind == "future"
		var ink: Color = SignageTokens.NAVY_DIM if done else SignageTokens.INSTITUTIONAL_NAVY
		title.add_theme_color_override("font_color", ink)
		var shown := base_title
		if not done and current and not suffix.is_empty():
			shown = "%s — %s" % [base_title, suffix]
		title.text = shown
		if done:
			tooltip_text = "Stamped: %s — verified complete." % base_title
		elif current:
			if suffix.is_empty():
				tooltip_text = "Do this now: open %s." % dept_hint if dept_hint != "" \
					else "Do this now: %s." % base_title
			elif dept_hint != "":
				tooltip_text = "Do this first: %s — then open %s." % [
					suffix.to_lower(), dept_hint]
			else:
				tooltip_text = "Do this first: %s." % suffix.to_lower()
		else:
			tooltip_text = "Queued orientation step: %s." % base_title


	## The unstamped slot: a drawn navy outline box (the empty half of the
	## stamp_check state pair — the fill is the state, never color alone).
	class EmptyBox:
		extends Control

		func _init() -> void:
			custom_minimum_size = Vector2(14.0, 14.0)

		func _draw() -> void:
			draw_rect(Rect2(Vector2.ZERO, size),
				Color(SignageTokens.INSTITUTIONAL_NAVY, 0.8), false, 2.0)
