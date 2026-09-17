class_name DossierRegister
extends PanelContainer
## DossierRegister — T26 the DEPARTMENTAL DOSSIER (FORM R-1) section posted
## inside each of the five skill dockets (naming-bible §10 T22 rows +
## design-brief Addendum 2; copy verbatim, binding).
##
## It is a SECTION of the existing docket, never a ninth plate and never an
## overlay: the plate wall, the bulkhead transitions and the system-level R1
## geometry pins are untouched. The mounted docket owns the engine truth —
## it calls refresh(tm) on the batched regions whose counters move and on the
## two immediate discrete signals; the register renders only what it is
## handed (never infers progress).
##
## FOLD DISCIPLINE (the O-1 precedent, the documented T26 choice): 23 rows
## cannot fit a 720p docket beside the working regions, so the register
## mounts FOLDED to its posted summary line — title + serial + "N/23
## STAMPED" — with an OPEN toggle that posts the full register (stamped rows
## stay stamped through every fold). Unlike the O-1 form (the tutorial IS
## the priority, so it starts expanded), the dossier is a RECORD, not a
## tutorial: the docket's working regions stay first. The folded summary
## keeps every register at ~10 words (low-text discipline); the completed
## record folds to "ALL 23 STAMPED · FORM R-1".
##
## Row idiom (Addendum 2): the O-1 row at scale — [empty checkbox square →
## red stamp_check when stamped] + [objective line, stencil plate idiom] +
## [mono progress readout "12/40"] + [reward line "MERIT PAY · N CROWNS" /
## "COMMENDATION · N XP"]. Stamped rows dim to the registered NAVY_DIM
## on-paper pair and keep their stamps — the state is never color-alone
## (the stamp glyph IS the state; unstamped rows carry no state word).
## Rewards post themselves (engine T23); there is no claim button anywhere
## — the standing footer says so once per register.
##
## Update discipline: rows are built at FIRST EXPANSION (the perf-idle
## discipline — 5 dockets x 23 CardButtons is a one-time ~10 ms frame that
## must never ride the boot) and restyled only through guarded setters (a
## no-change refresh writes nothing — the T19/T24 no-change-signature
## precedent; refreshes ride the 4 Hz regions).

const FORM_SERIAL := "D.O.C.S. FORM R-1"
const FOLD_LABEL := "FOLD"
const OPEN_LABEL := "OPEN"
const PROGRESS_SUFFIX := "STAMPED"
const NO_CLAIM_NOTICE := "MERIT PAY POSTS ITSELF. NO CLAIM IS REQUIRED. NONE HAS EVER BEEN."
const COMPLETION_SERIAL := "DOSSIER DULY STAMPED. THE DEPARTMENT TAKES NOTICE. FURTHER DUTIES ARE UNDER CONSIDERATION."

## Per-skill dossier titles (naming-bible §10 T22 — verbatim, binding).
const DOSSIER_TITLES := {
	"scavenging": "RECLAMATION DOSSIER",
	"foraging": "GROUNDSKEEPING DOSSIER",
	"junksmithing": "FABRICATION DOSSIER",
	"cooking": "MESS DOSSIER",
	"wasteland_combat": "EXTERIOR DOSSIER",
}

const ICON_DIR := "res://assets/icons/"
const GLYPH_STAMP := "stamp_check"
const GLYPH_CROWNS := "crowns"

var skill_id := ""
var dossier_title := ""

var _title_label: Label
var _serial_label: Label
var _completion_box: VBoxContainer
var _completion_stamp: Label
var _completion_serial: Label
var _rows_box: VBoxContainer
var _footer_label: Label
var _fold_button: Button
var _open_button: Button

var _rows: Array[RegisterRow] = []
var _expanded := false
var _summary := {}  # last-applied engine truth (guarded restyle baseline)


static func title_for(skill: String) -> String:
	return String(DOSSIER_TITLES.get(skill, skill.to_upper() + " DOSSIER"))


func _init(p_skill_id: String, p_title := "") -> void:
	skill_id = p_skill_id
	dossier_title = p_title if p_title != "" else title_for(p_skill_id)
	name = "DossierRegister_" + skill_id
	theme_type_variation = "PaperNotice"
	_build()


# ------------------------------------------------------------------ build --
func _build() -> void:
	var col := VBoxContainer.new()
	col.name = "RegisterColumn"
	col.add_theme_constant_override("separation", 7)
	add_child(col)

	_title_label = _label("PaperTitle", dossier_title)
	_title_label.name = "DossierTitle"
	col.add_child(_title_label)

	_serial_label = _label("PlateSerialNavy", "")
	_serial_label.name = "DossierSerial"
	col.add_child(_serial_label)

	# The completion record (posted while every objective of the skill is
	# stamped — the ALL N STAMPED rubber stamp, count from data).
	_completion_box = VBoxContainer.new()
	_completion_box.name = "CompletionRecord"
	_completion_box.add_theme_constant_override("separation", 6)
	_completion_box.visible = false
	var stamp_row := HBoxContainer.new()
	stamp_row.name = "StampRow"
	stamp_row.add_theme_constant_override("separation", 8)
	stamp_row.add_child(_glyph(GLYPH_STAMP, 24, "StampGlyph"))
	_completion_stamp = _label("PaperStamp", "")
	_completion_stamp.name = "StampLine"
	stamp_row.add_child(_completion_stamp)
	_completion_box.add_child(stamp_row)
	_completion_serial = _label("PaperText", COMPLETION_SERIAL)
	_completion_serial.name = "CompletionSerial"
	_completion_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_completion_box.add_child(_completion_serial)
	col.add_child(_completion_box)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "ObjectiveRows"
	_rows_box.add_theme_constant_override("separation", 3)
	col.add_child(_rows_box)

	_footer_label = _label("PlateSerialNavy", NO_CLAIM_NOTICE)
	_footer_label.name = "NoClaimNotice"
	_footer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_footer_label)

	_fold_button = Button.new()
	_fold_button.name = "FoldRegister"
	_fold_button.text = FOLD_LABEL
	_fold_button.tooltip_text = "Fold the %s to its posted summary (stamped rows stay stamped)" % dossier_title.to_lower()
	_fold_button.pressed.connect(fold)
	col.add_child(_fold_button)

	_open_button = Button.new()
	_open_button.name = "OpenRegister"
	_open_button.text = OPEN_LABEL
	_open_button.tooltip_text = "Re-view the %s objective register" % dossier_title.to_lower()
	_open_button.pressed.connect(expand)
	col.add_child(_open_button)


## The register's engine read (one summary per refresh). The dockets hand
## the TickManager in; the façade is tm.dossier_summary (all numbers engine
## truth). Never in _init — lib/state exist only after bind.
func refresh(tm: Node) -> void:
	if tm == null or not tm.has_method("dossier_summary"):
		return
	apply_summary(tm.dossier_summary(skill_id))


func apply_summary(summary: Dictionary) -> void:
	_summary = summary
	var stamped := int(summary.get("stamped", 0))
	var total := int(summary.get("total", 0))
	var complete := total > 0 and stamped >= total
	var rows: Array = summary.get("rows", [])

	# Rows are built ON FIRST EXPANSION, never at bind (the perf-idle
	# discipline: 5 dockets x 23 CardButton rows is a one-time ~10 ms frame
	# when it rides the boot frame; the folded summary needs no row controls,
	# and the register mounts folded). Once built they persist through every
	# fold — stamped rows stay stamped.
	if not _expanded and _rows.is_empty():
		_apply_fold(false, complete, "%s/%s %s" % [SignageFmt.num(stamped),
			SignageFmt.num(total), PROGRESS_SUFFIX], String(summary.get("stamp_line", "")))
		return
	while _rows.size() < rows.size():
		var row := RegisterRow.new()
		_rows_box.add_child(row)
		_rows.append(row)
	for i in _rows.size():
		if i < rows.size():
			_rows[i].apply(rows[i])
		else:
			_rows[i].visible = false

	# Summary serial: "12/23 STAMPED" (mono digits through SignageFmt); the
	# completed record posts the full rubber stamp as its summary line.
	var serial := "%s/%s %s" % [SignageFmt.num(stamped), SignageFmt.num(total), PROGRESS_SUFFIX]
	var stamp_line := String(summary.get("stamp_line", ""))
	_apply_fold(_expanded, complete, serial, stamp_line)


func _apply_fold(expanded: bool, complete: bool, serial: String, stamp_line: String) -> void:
	_rows_box.visible = expanded
	_footer_label.visible = expanded
	_fold_button.visible = expanded
	_open_button.visible = not expanded
	_completion_box.visible = complete and expanded
	_completion_stamp.text = stamp_line
	# Folded + complete: the summary line IS the stamp (the posted-record
	# slip; the red stamp class escorts the wording, never carries it).
	if complete and not expanded:
		_serial_label.theme_type_variation = "PaperStamp"
		_serial_label.text = stamp_line
	else:
		_serial_label.theme_type_variation = "PlateSerialNavy"
		_serial_label.text = "%s · %s" % [FORM_SERIAL, serial]


# ------------------------------------------------------------------ state --
func is_expanded() -> bool:
	return _expanded


func is_complete() -> bool:
	return _completion_stamp.text != "" and int(_summary.get("stamped", 0)) >= int(_summary.get("total", 0)) \
		and int(_summary.get("total", 0)) > 0


func fold() -> void:
	_expanded = false
	if not _summary.is_empty():
		apply_summary(_summary)


func expand() -> void:
	_expanded = true
	if not _summary.is_empty():
		apply_summary(_summary)


## The mounted row controls (tests walk them; posted order).
func rows() -> Array[RegisterRow]:
	return _rows


func summary_text() -> String:
	return _serial_label.text


func completion_stamp_text() -> String:
	return _completion_stamp.text


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


# ================================================================== row ==
## One register row — the O-1 step row at scale: [empty box / red
## stamp_check][objective line (wrapped, the sole EXPAND_FILL child — T15
## discipline)][mono progress readout] over a reward segment flow. Flat
## paper styling like the O-1 StepRow; the theme's amber Button focus ring
## is inherited untouched (keyboard-reachable with a visible ring).
## Restyle is signature-guarded: a 4 Hz flush with unchanged truth writes
## nothing (the perf-idle budget).
class RegisterRow:
	extends "res://scripts/ui/docket.gd".CardButton

	var objective_id := ""
	var stamp: TextureRect
	var empty_box: Control
	var title: Label
	var progress: Label
	var reward_line: HFlowContainer

	var _applied := {}  # last-applied state signature (no-change guard)


	func _init() -> void:
		name = "ObjectiveRow"
		focus_mode = Control.FOCUS_ALL
		_flat_stylebox("normal", Color(0, 0, 0, 0.0))
		_flat_stylebox("hover", Color(SignageTokens.INSTITUTIONAL_NAVY, 0.07))
		_flat_stylebox("pressed", Color(SignageTokens.INSTITUTIONAL_NAVY, 0.13))
		_flat_stylebox("disabled", Color(0, 0, 0, 0.0))

		var col := VBoxContainer.new()
		col.name = "RowColumn"
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 2)

		# Line 1 — the O-1 row shape: fixed glyph, the objective line as the
		# sole EXPAND_FILL child, fixed mono readout. NO autowrap: the loader
		# caps descriptions at 6 words (≤ ~22 chars), and a wrapped label
		# inside CardButton's manual layout computes a runaway minimum height
		# (the O-1 StepRow precedent — unwrap the bounded line instead; the
		# T15 collapse class needs wrapping to exist at all).
		var line1 := HBoxContainer.new()
		line1.name = "RowLine"
		line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line1.add_theme_constant_override("separation", 8)
		stamp = _glyph("stamp_check", 18)
		stamp.name = "StampGlyph"
		stamp.visible = false
		line1.add_child(stamp)
		empty_box = EmptyBox.new()
		empty_box.name = "EmptyBox"
		empty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line1.add_child(empty_box)
		title = Label.new()
		title.name = "ObjectiveLine"
		title.theme_type_variation = "PaperText"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line1.add_child(title)
		progress = Label.new()
		progress.name = "ProgressReadout"
		progress.theme_type_variation = "PlateSerialNavy"
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line1.add_child(progress)
		col.add_child(line1)

		# Line 2 — the reward segments (T19 flow idiom: no autowrap inside a
		# flow; the crowns glyph rides the crowns leg — icon-grammar rule).
		reward_line = HFlowContainer.new()
		reward_line.name = "RewardLine"
		reward_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reward_line.add_theme_constant_override("h_separation", 10)
		reward_line.add_theme_constant_override("v_separation", 2)
		col.add_child(reward_line)

		add_child(col)


	## Apply one dossier_summary row: {id, description, stamped, current,
	## target, reward_line, reward_crowns, reward_xp}. Signature-guarded.
	func apply(row: Dictionary) -> void:
		var stamped := bool(row.get("stamped", false))
		var progress_text := "%s/%s" % [SignageFmt.num(int(row.get("current", 0))),
			SignageFmt.num(int(row.get("target", 0)))]
		var reward_crowns := int(row.get("reward_crowns", 0))
		var reward_xp := int(row.get("reward_xp", 0))
		var sig := "%s|%s|%s|%s|%d|%d" % [String(row.get("id", "")), String(row.get("description", "")),
			progress_text, String(row.get("reward_line", "")), reward_crowns, reward_xp]
		if str(_applied.get("sig", "")) == sig:
			return
		_applied["sig"] = sig
		_applied["stamped"] = stamped
		objective_id = String(row.get("id", ""))
		# Unique sibling name (Godot auto-renames duplicate names, which
		# breaks name-based lookups in tests/probes).
		var row_name := "ObjectiveRow_" + objective_id
		if name != row_name:
			name = row_name
		visible = true
		stamp.visible = stamped
		empty_box.visible = not stamped
		title.text = String(row.get("description", ""))
		progress.text = progress_text
		_reward_segments(stamped, reward_crowns, reward_xp)
		# Stamped rows dim to the registered NAVY_DIM-on-paper pair (T8's
		# contrast table); unstamped rows carry the variation's own ink.
		var dim := SignageTokens.NAVY_DIM
		if stamped:
			title.add_theme_color_override("font_color", dim)
			progress.add_theme_color_override("font_color", dim)
		else:
			title.remove_theme_color_override("font_color")
			progress.remove_theme_color_override("font_color")
		var reward := String(row.get("reward_line", ""))
		tooltip_text = ("Stamped: %s — %s posted." % [title.text, reward.to_lower()]) if stamped \
			else "Objective: %s — %s of %s. Reward: %s." % [title.text,
				SignageFmt.num(int(row.get("current", 0))),
				SignageFmt.num(int(row.get("target", 0))), reward.to_lower()]


	func _reward_segments(stamped: bool, crowns: int, xp: int) -> void:
		for child in reward_line.get_children():
			reward_line.remove_child(child)
			child.queue_free()
		var ink: Color = SignageTokens.NAVY_DIM if stamped else SignageTokens.INSTITUTIONAL_NAVY
		if crowns > 0:
			var mark := TextureRect.new()
			var tex: Texture2D = load("res://assets/icons/crowns.svg")
			if tex != null:
				mark.texture = tex
			mark.custom_minimum_size = Vector2(16.0, 16.0)
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			reward_line.add_child(mark)
			reward_line.add_child(_reward_label("MERIT PAY · %s CROWNS" % SignageFmt.num(crowns), ink))
		if xp > 0:
			reward_line.add_child(_reward_label("COMMENDATION · %s XP" % SignageFmt.num(xp), ink))


	func _reward_label(text: String, ink: Color) -> Label:
		var l := Label.new()
		l.theme_type_variation = "PlateSerialNavy"
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if ink != SignageTokens.INSTITUTIONAL_NAVY:
			l.add_theme_color_override("font_color", ink)
		return l


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
	## it), so the 24 px WCAG hit-target floor is re-asserted on top of the
	## content-derived minimum (the T15 discipline).
	func _sync_min() -> void:
		super._sync_min()
		custom_minimum_size = Vector2(
			custom_minimum_size.x, maxf(custom_minimum_size.y, 24.0))


	## The unstamped slot: a drawn navy outline box — the empty half of the
	## stamp_check state pair (the fill is the state, never color alone).
	class EmptyBox:
		extends Control

		func _init() -> void:
			custom_minimum_size = Vector2(14.0, 14.0)

		func _draw() -> void:
			draw_rect(Rect2(Vector2.ZERO, size),
				Color(SignageTokens.INSTITUTIONAL_NAVY, 0.8), false, 2.0)
