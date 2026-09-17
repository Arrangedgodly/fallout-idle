class_name Docket
extends VBoxContainer
## Docket — T10a base for department docket content mounted inside the T9
## concourse shell (Concourse._build_docket swaps the placeholder internals
## for one of these; the shell keeps the header plate, posted directive,
## primary-action button and serial footer).
##
## BINDING CONTRACT (tests + production share it): bind(tick_manager) wires
## the docket to a TickManager instance — the production autoload, or a
## never-in-tree twin a GUT test drives through advance_wall_ms(). Rebinding
## to a different manager disconnects the old one first. Everything rendered
## is re-read from tm.state / content defs on signal; NOTHING updates per
## frame (the T6 UI UPDATE CONTRACT is the only update surface):
##   bulk_state_changed(changes) — re-read the regions the docket shows;
##   level_up / activity_stopped — immediate discrete stamps in the log.
##
## Subclasses implement _build_content(), _refresh(changes), and optionally
## primary_action() (the shell's big stencled button routes here).

const ICON_DIR := "res://assets/icons/"

## T19 icon-grammar glyph ids (naming-bible §14; silhouettes per the
## design-brief addendum "Icon grammar additions"). A stat glyph names
## EXACTLY its own stat and posts inline before that stat's mono number;
## the clearance staircase marks gated cards beside the grade number.
const GLYPH_CONDITION := "stat_condition"
const GLYPH_ACCURACY := "stat_accuracy"
const GLYPH_EVADE := "stat_evade"
const GLYPH_MAX_HIT := "stat_max_hit"
const GLYPH_INTERVAL := "stat_interval"
const GLYPH_CLEARANCE := "clearance_step"

## T17 worker-badge glyphs (icon-grammar addendum: the state pair is the FILL —
## filled badge = ASSIGNED, outline badge = AVAILABLE).
const GLYPH_BADGE := "deputy_badge"
const GLYPH_BADGE_OUTLINE := "deputy_badge_outline"

## T26 the DEPARTMENTAL DOSSIER's state mark (the O-1 check-stamp family —
## a red stamp rides every FORM R-1 notice line).
const GLYPH_STAMP := "stamp_check"

## T17 POSTING REFUSED directive (naming-bible §10 — verbatim, binding):
## the plate head + the fact-and-both-remedies serial. Refusal, never denial
## of service (voice rule R3); a notice, not a modal gate.
const REFUSAL_HEAD := "POSTING REFUSED"
const REFUSAL_SERIAL := "ALL DEPUTIES ARE ASSIGNED. CEASE A POSTING, OR DEPUTIZE ANOTHER RESIDENT AT THE PERSONNEL PLATE. EITHER REMEDY IS CHEERFULLY SUPPORTED."

## T19 inline sizes (16-24 px legibility band, capture-reviewed).
const GLYPH_INLINE := 18
const GLYPH_READ := 20

var tm: Node = null  # TickManager instance (soft-typed: script compiles under --check-only)

const TM_SIGNALS := ["bulk_state_changed", "level_up", "activity_stopped",
	"objective_stamped", "dossier_completed"]
var _handlers := {}


## T15 audit fix: a Button's built-in minimum size covers only its own text +
## stylebox — child content is ignored (Button is not a container), so the
## tier/recipe/fauna cards (text-less buttons carrying label stacks) collapsed
## to ~22 px with their yields/gate lines spilling onto the next card, the
## focus ring wrapping a sliver, and the hit target under the 24 px WCAG
## 2.5.8 floor. CardButton sizes to its child stack and lays the stack out
## inset by the button stylebox's content margins (Button never positions
## children of its own).
class CardButton:
	extends Button

	func _init() -> void:
		child_entered_tree.connect(_on_child_entered)

	func _on_child_entered(child: Node) -> void:
		if child is Control:
			(child as Control).minimum_size_changed.connect(_sync_min)
			_sync_min()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_READY or what == NOTIFICATION_RESIZED \
				or what == NOTIFICATION_THEME_CHANGED:
			_layout_children()
			_sync_min()

	## custom_minimum_size replaces the control's own minimum (it does not
	## max with it), so the sync seeds from the stylebox base — cards carry no
	## text of their own, making the stylebox the entire native contribution.
	func _sync_min() -> void:
		if not is_inside_tree():
			return
		var sb := get_theme_stylebox("normal")
		var ms: Vector2 = sb.get_minimum_size()
		for child in get_children():
			if child is Control:
				var cmin: Vector2 = (child as Control).get_combined_minimum_size()
				ms.x = maxf(ms.x, cmin.x + sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT))
				ms.y = maxf(ms.y, cmin.y + sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM))
		custom_minimum_size = ms

	func _layout_children() -> void:
		if not is_inside_tree():
			return
		var sb := get_theme_stylebox("normal")
		var ofs := Vector2(sb.get_margin(SIDE_LEFT), sb.get_margin(SIDE_TOP))
		var avail := size - ofs - Vector2(sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_BOTTOM))
		for child in get_children():
			if child is Control:
				var c := child as Control
				c.position = ofs
				c.size = avail


## Wire to a TickManager (production autoload or test twin). Idempotent per
## instance; switching instances disconnects every prior signal first.
func bind(p_tm: Node) -> void:
	if tm == p_tm and p_tm != null:
		return
	unbind()
	tm = p_tm
	if tm == null:
		return
	_handlers = {
		"bulk_state_changed": _on_bulk_state_changed,
		"level_up": _on_level_up,
		"activity_stopped": _on_activity_stopped,
		"objective_stamped": _on_objective_stamped,
		"dossier_completed": _on_dossier_completed,
	}
	for s in TM_SIGNALS:
		(tm.get(s) as Signal).connect(_handlers[s])
	_on_bound()
	_refresh({"xp": true, "inventory": true, "activity": true, "combat": true})


func unbind() -> void:
	if tm != null and not _handlers.is_empty():
		for s in TM_SIGNALS:
			var sig: Signal = tm.get(s)
			if sig.is_connected(_handlers[s]):
				sig.disconnect(_handlers[s])
	tm = null
	_handlers = {}


func lib() -> ContentLibrary:
	return tm.engine.lib if tm != null else null


func state() -> PlayerState:
	return tm.state if tm != null else null


## The shell's primary-action button press (BEGIN/END SHIFT). Default no-op.
func primary_action() -> void:
	pass


# ------------------------------------------------------------------ overridables
func _build_content() -> void:
	pass


func _refresh(_changes: Dictionary) -> void:
	pass


## First wire-up after bind (subclasses snapshot engine state, e.g. inventory
## baselines for stamped delta lines).
func _on_bound() -> void:
	pass


# ------------------------------------------------------------------ shared helpers
## Content-bearing plate / vent / paper shells (T8 variations only — the
## concourse probe rejects ad-hoc panels).
func panel_box(variation: String) -> PanelContainer:
	var p := PanelContainer.new()
	if not variation.is_empty():
		p.theme_type_variation = variation
	return p


func label(variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	return l


## Micro section serial. T15: section headers wrap — the long institutional
## serials were each docket's widest line at 200% font scale.
func micro(text: String) -> Label:
	var l := label("MicroLabel", text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func icon_rect(icon_id: String, size := 26) -> TextureRect:
	var t := TextureRect.new()
	var tex: Texture2D = load(ICON_DIR + icon_id + ".svg")
	if tex != null:
		t.texture = tex
	t.custom_minimum_size = Vector2(float(size), float(size))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


## Texture for one log-stamp icon (content item / skill / monster marks and
## the T19 grammar glyphs). Returns null when unknown — callers pass null
## through to Docket.stamp, which renders an un-iconed line.
func icon_texture(icon_id: String) -> Texture2D:
	if icon_id.is_empty():
		return null
	var path := ICON_DIR + icon_id + ".svg"
	return load(path) as Texture2D if FileAccess.file_exists(path) else null


func item_icon_texture(item_id: String) -> Texture2D:
	if lib() == null:
		return null
	var item: ItemDef = lib().item(item_id)
	return icon_texture(item.icon) if item != null else null


# ---------------------------------------------------------- T19 segment flows
## A wrapping row of [glyph][text] segments (T19 inline-icon idiom). Every
## segment is short and UNWRAPPED, so the flow replaces the T15 wrapped-serial
## discipline with something strictly safer: no autowrap label exists anywhere
## inside a flow (the collapse class cannot occur), and the flow's minimum
## width is one segment, never the whole line.
func segment_flow(sep := 10) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", 2)
	return f


## Append one [glyph][text] segment; glyph_id "" = bare text segment.
## Returns the segment's label (variation switching keeps the reference).
func add_segment(flow: HFlowContainer, glyph_id: String, text: String,
		variation: String, glyph_size := GLYPH_INLINE) -> Label:
	if not glyph_id.is_empty():
		flow.add_child(icon_rect(glyph_id, glyph_size))
	var l := label(variation, text)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.add_child(l)
	return l


## Rebuild a flow from segments [{icon: String, text: String}] (T19 update
## path for live-refreshing serials). Returns the labels in order. No-op when
## the content is unchanged — refresh paths run on every 4 Hz bulk flush and
## must not churn controls (the T6/T14 idle budget) for static serials.
func set_segments(flow: HFlowContainer, segments: Array, variation: String,
		glyph_size := GLYPH_INLINE) -> Array[Label]:
	var sig := variation + "|" + str(glyph_size)
	for seg in segments:
		sig += str(seg.get("icon", "")) + "||" + str(seg.get("text", "")) + "::"
	if String(flow.get_meta("segments_sig", "")) == sig:
		var existing: Array[Label] = []
		for child in flow.get_children():
			if child is Label:
				existing.append(child)
		return existing
	flow.set_meta("segments_sig", sig)
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	var labels: Array[Label] = []
	for seg in segments:
		labels.append(add_segment(flow, str(seg.get("icon", "")),
			str(seg.get("text", "")), variation, glyph_size))
	return labels


## Joined segment text ("A · B · C") — the tests' honest-math readout.
## Static: inner Card classes (no Docket inheritance) call it through the
## class itself.
static func flow_text(flow: Node) -> String:
	var parts: Array[String] = []
	for child in flow.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return " · ".join(parts)


## Switch every label in a flow between state variations (energized toggle).
func set_flow_variation(flow: Node, variation: String) -> void:
	for child in flow.get_children():
		if child is Label:
			(child as Label).theme_type_variation = variation


# ------------------------------------------------- T17 posting-refusal plate
## The POSTING REFUSED directive plate (shared by every docket that can
## request a posting — skill dockets and the patrol). Energized ground +
## filled deputy badge + the verbatim naming-bible serial; the caller mounts
## it and keeps `refusal_plate.visible = (engine.free_postings() == 0)` in
## its refresh, so the directive is posted exactly while it is TRUE (the
## board is full) and withdraws the moment a posting frees or a deputy is
## deputized — refinement-2 discipline: copy never outlives its fact.
var refusal_plate: PanelContainer
var refusal_head: Label
var refusal_serial: Label


func build_refusal_plate() -> PanelContainer:
	refusal_plate = panel_box("EnergizedPlate")
	refusal_plate.name = "PostingRefusedPlate"
	refusal_plate.visible = false
	var col := vbox(4)
	var head_row := hbox(10)
	head_row.add_child(icon_rect(GLYPH_BADGE, GLYPH_READ))
	refusal_head = label("MonoValueEnergized", REFUSAL_HEAD)
	refusal_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(refusal_head)
	col.add_child(head_row)
	refusal_serial = label("PlateBodyEnergized", REFUSAL_SERIAL)
	refusal_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(refusal_serial)
	refusal_plate.add_child(col)
	refusal_plate.tooltip_text = "The posting board is full. Cease a posting, or deputize another resident at the Personnel plate (press 8)."
	return refusal_plate


## Truth-gated visibility (call from _refresh): the directive stands exactly
## while the establishment has no free posting.
func refresh_refusal_plate() -> void:
	if refusal_plate == null or tm == null or state() == null:
		return
	refusal_plate.visible = tm.free_postings() == 0


## [glyph][wrapped serial] row: the one sanctioned HBox shape for a glyph
## beside a WRAPPED label — the label is the sole EXPAND_FILL child and the
## glyph is fixed-min-size (never starves it; T15 discipline holds).
func glyph_beside(glyph_id: String, wrapped: Label, glyph_size := GLYPH_READ) -> HBoxContainer:
	var row := hbox(8)
	row.add_child(icon_rect(glyph_id, glyph_size))
	wrapped.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wrapped)
	return row


func vbox(sep: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


func hbox(sep: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


func margins_box(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


## The stamped log inset: a vent housing carrying a mono ItemList (T8's
## "stamped drop lines" component). Lines arrive from batched signals only.
func build_log(serial: String, min_lines := 6) -> ItemList:
	var vent := panel_box("VentHousing")
	var col := vbox(6)
	col.add_child(micro(serial))
	var log := ItemList.new()
	log.name = "LogLines"
	log.custom_minimum_size = Vector2(0.0, 24.0 * float(min_lines))
	log.focus_mode = Control.FOCUS_ALL
	# T15: the log is keyboard-focusable, so it carries an accessible name
	# (ItemList renders no self-describing text of its own).
	log.tooltip_text = "%s — arrow keys review the stamps, newest line selected" % serial.to_lower()
	log.fixed_icon_size = Vector2i(18, 18)
	col.add_child(log)
	vent.add_child(col)
	add_child(vent)
	return log


## Stamp one line into a log, newest last, scrolled into view, capped. The
## newest stamp carries the selected-row highlight (the "current" line).
func stamp(log: ItemList, text: String, icon: Texture2D = null, cap := 60) -> void:
	log.add_item(text, icon)
	while log.item_count > cap:
		log.remove_item(0)
	if log.item_count > 0:
		var last := log.item_count - 1
		log.select(last)
		log.ensure_current_is_visible()


# ------------------------------------------------------------------ engine events
func _on_bulk_state_changed(changes: Dictionary) -> void:
	_refresh(changes)


func _on_level_up(_skill_id: String, _old_level: int, _new_level: int) -> void:
	pass  # subclasses stamp the clearance fanfare


func _on_activity_stopped(_skill_id: String, _content_id: String, _reason: String) -> void:
	_refresh({"activity": true})


## T23 immediate notices (once per objective ever / once per completion):
## skill dockets + the patrol override these to stamp their logs and refresh
## the mounted DossierRegister; the other dockets no-op (every docket hears
## the contract's signals, only the paper-bearing ones answer).
func _on_objective_stamped(_payload: Dictionary) -> void:
	pass


func _on_dossier_completed(_payload: Dictionary) -> void:
	pass


func _init() -> void:
	_build_content()
