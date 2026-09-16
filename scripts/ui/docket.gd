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

var tm: Node = null  # TickManager instance (soft-typed: script compiles under --check-only)

const TM_SIGNALS := ["bulk_state_changed", "level_up", "activity_stopped"]
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


func _init() -> void:
	_build_content()
