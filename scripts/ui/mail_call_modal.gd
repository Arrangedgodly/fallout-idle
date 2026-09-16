class_name MailCallModal
extends Control
## MailCallModal — T10a offline-gains notice: a posted paper MAIL CALL card
## over a dimmed concourse, presented once per load with a positive offline
## gap (TickManager.mail_call_ready; the concourse also presents
## state.last_mail_call at bind time — the signal can fire before the scene
## exists, since SaveStore loads inside its own _ready).
##
## Payload shape (T6/T7 contract):
##   elapsed_ms, skills_xp {skill: gained}, items {item: gained},
##   levels {skill: {from, to}}, actions {skill: count},
##   stopped [{skill_id, content_id, reason}], and — when a mid-fight save
##   replayed — combat {kills, monster_id, outcome, notice?, zone_cleared?}.
## The PATROL RECALLED plate posts when the patrol hit its survivability
## bound (stopped reason "patrol_recalled" / combat.notice "PATROL RECALLED").
##
## Accessibility: the stamped ACKNOWLEDGE RECEIPT button grabs focus on open
## and the modal traps the focus chain (focus landing outside is pushed
## back) — an interruption notice earns protected focus. Esc acknowledges.

signal acknowledged(payload: Dictionary)

const ICON_DIR := "res://assets/icons/"

var card: PanelContainer
var body_box: VBoxContainer
var ack_button: Button
var backdrop: ColorRect

var lib: ContentLibrary = null  # injected by the concourse (tests use twins)

var _payload: Dictionary = {}
var _trap := false
var _focus_hooked := false


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.055, 0.075, 0.11, 0.55)
	backdrop.set_anchors_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CardCenter"
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card = PanelContainer.new()
	card.name = "MailCallCard"
	card.theme_type_variation = "PaperNotice"
	card.custom_minimum_size = Vector2(620.0, 0.0)
	var margins := MarginContainer.new()
	margins.add_theme_constant_override("margin_left", 12)
	margins.add_theme_constant_override("margin_right", 12)
	margins.add_theme_constant_override("margin_top", 6)
	margins.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margins)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.name = "CardScroll"
	scroll.custom_minimum_size = Vector2(0.0, 480.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body_box = VBoxContainer.new()
	body_box.name = "CardBody"
	body_box.add_theme_constant_override("separation", 8)
	body_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_box)
	ack_button = Button.new()
	ack_button.name = "Acknowledge"
	ack_button.theme_type_variation = "Energized"
	ack_button.text = "ACKNOWLEDGE RECEIPT"
	ack_button.custom_minimum_size = Vector2(320.0, 56.0)
	ack_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ack_button.tooltip_text = "Take receipt of everything posted (Esc)"
	ack_button.pressed.connect(acknowledge)
	col.add_child(ack_button)
	margins.add_child(col)
	center.add_child(card)
	add_child(center)


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.gui_focus_changed.connect(_on_focus_changed)
		_focus_hooked = true


# ------------------------------------------------------------------ present
## Present a payload (the concourse routes the engine signal here). Every
## line renders from the LIVE payload + content defs — no mocked text.
func present(payload: Dictionary, p_lib: ContentLibrary = null) -> void:
	if p_lib != null:
		lib = p_lib
	_payload = payload
	for child in body_box.get_children():
		child.queue_free()
	_build_lines()
	visible = true
	_trap = true
	ack_button.grab_focus()


func acknowledge() -> void:
	_trap = false
	visible = false
	var payload := _payload
	_payload = {}
	acknowledged.emit(payload)


func is_presenting() -> bool:
	return visible


func payload() -> Dictionary:
	return _payload


# ------------------------------------------------------------------ lines
func _build_lines() -> void:
	if lib == null:
		return
	_line("PaperStamp", "POSTED AT THE BULKHEAD · FORM M-1")
	_line("PaperTitle", "MAIL CALL")
	_line("PaperTitle", "AWAY %s" % SignageFmt.duration(int(_payload.get("elapsed_ms", 0))))
	var intro := _line("PaperText",
		"GAINS ACCRUED IN YOUR ABSENCE. NO ACTION WAS TAKEN WITHOUT YOU. NONE WAS NEEDED.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_box.add_child(HSeparator.new())

	var skills_xp: Dictionary = _payload.get("skills_xp", {})
	var levels: Dictionary = _payload.get("levels", {})
	var actions: Dictionary = _payload.get("actions", {})
	var combat_skill := _combat_skill_id()
	for skill_id in skills_xp:
		var line := "%s +%s XP" % [
			_skill_display_name(String(skill_id)),
			SignageFmt.num(int(skills_xp[skill_id]))]
		if levels.has(skill_id):
			var crossing: Dictionary = levels[skill_id]
			line += " · CLEARANCE %02d » %02d" % [int(crossing["from"]), int(crossing["to"])]
		if actions.has(skill_id) and String(skill_id) != combat_skill:
			line += " · %s ACTIONS" % SignageFmt.num(int(actions[skill_id]))
		# T19: each gain line carries its department's mark at small size.
		body_box.add_child(_serial_with_icon(_skill_icon(String(skill_id)), line))

	var items: Dictionary = _payload.get("items", {})
	for item_id in items:
		var item := lib.item(String(item_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tex: Texture2D = load(ICON_DIR + item.icon + ".svg") if item != null else null
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.custom_minimum_size = Vector2(18, 18)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
		# T15 fix round: the wrapped gain serial EXPANDS to the row's leftover
		# width — as a plain HBox child its ~1 px autowrap minimum starved it
		# to a vertical one-character column (caught by the retry collapse
		# pin; the same class as the skill-docket serial collapse).
		var gain_serial := _paper_serial("%s %s" % [
			String(item.name).to_upper() if item != null else String(item_id).to_upper(),
			SignageFmt.delta(int(items[item_id]))])
		gain_serial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gain_serial)
		body_box.add_child(row)

	if skills_xp.is_empty() and items.is_empty():
		body_box.add_child(_paper_serial(
			"NO SHIFTS WERE RUNNING. THE SHELTER KEPT YOUR CHAIR WARM."))

	var combat: Dictionary = _payload.get("combat", {})
	if not combat.is_empty():
		body_box.add_child(HSeparator.new())
		var monster := lib.monster(str(combat.get("monster_id", "")))
		var kills := int(combat.get("kills", 0))
		if kills > 0:
			# T19: the patrol line carries the engaged fauna's posting mark.
			body_box.add_child(_serial_with_icon(
				_icon_texture(monster.icon if monster != null else ""),
				"WASTELAND PATROL · %s KILLS — %s" % [
					SignageFmt.num(kills),
					String(monster.name).to_upper() if monster != null
						else str(combat.get("monster_id", "")).to_upper()]))
		if bool(combat.get("truncated", false)):
			# T7's honest-truncation flag (replay budget exhausted): the gains
			# posted stop at the recording limit and the fight resumes live —
			# stated, never silently dropped.
			body_box.add_child(_paper_serial(
				"PATROL LEDGER TRUNCATED · THE RECORD STOPS AT THE POSTING LIMIT · FIGHT RESUMES LIVE."))
		if str(combat.get("notice", "")) != "" or _has_recall_stop():
			var recall := PanelContainer.new()
			recall.name = "RecallPlate"
			recall.theme_type_variation = "DangerPlate"
			var rl := Label.new()
			rl.theme_type_variation = "MonoValue"
			rl.text = "PATROL RECALLED · WITHDRAWN ALIVE AT THE LIMIT. ZERO LOSSES."
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			recall.add_child(rl)
			body_box.add_child(recall)
		if bool(combat.get("zone_cleared", false)):
			body_box.add_child(_paper_serial(
				"ZONE CLEARED · THE SUPERINTENDENT HAS BEEN EVICTED."))
		if str(combat.get("outcome", "")) == "resumed" and kills == 0:
			body_box.add_child(_paper_serial(
				"WASTELAND PATROL · FIGHT RESUMED ON YOUR RETURN."))

	for stop in _payload.get("stopped", []):
		var s: Dictionary = stop
		var reason := str(s.get("reason", ""))
		if reason == "patrol_recalled":
			continue  # already posted as the red plate above
		if reason == "inputs_exhausted":
			body_box.add_child(_paper_serial("SUPPLIES EXHAUSTED · %s SHIFT ENDED ITSELF." %
				_skill_display_name(str(s.get("skill_id", "")))))

	body_box.add_child(HSeparator.new())
	_line("PaperStamp", "THE DEPARTMENT THANKS YOU FOR BREATHING ATTENTIVELY.")


func _line(variation: String, text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	body_box.add_child(l)
	return l


func _paper_serial(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "PlateSerialNavy"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## T19: [icon][wrapped serial] row — the wrapped serial stays the sole
## EXPAND_FILL child beside the fixed-min-size icon (T15 discipline holds).
func _serial_with_icon(icon: Texture2D, text: String) -> Control:
	if icon == null:
		return _paper_serial(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var mark := TextureRect.new()
	mark.texture = icon
	mark.custom_minimum_size = Vector2(18, 18)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var serial := _paper_serial(text)
	serial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(serial)
	return row


func _icon_texture(icon_id: String) -> Texture2D:
	if icon_id.is_empty():
		return null
	var path := ICON_DIR + icon_id + ".svg"
	return load(path) as Texture2D if FileAccess.file_exists(path) else null


func _skill_icon(skill_id: String) -> Texture2D:
	var skill := lib.skill(skill_id) if lib != null else null
	return _icon_texture(skill.icon) if skill != null else null


# ------------------------------------------------------------------ focus trap
func _on_focus_changed(node: Node) -> void:
	if not _trap or not visible or not is_inside_tree():
		return
	var inside := node == null or node == self
	if node is Control:
		var c := node as Control
		inside = is_ancestor_of(c) or c.is_ancestor_of(self)
	if not inside:
		ack_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		acknowledge()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ helpers
func _combat_skill_id() -> String:
	if lib == null:
		return ""
	for skill_id: String in lib.skills:
		if (lib.skills[skill_id] as SkillDef).is_combat():
			return skill_id
	return ""


func _skill_display_name(skill_id: String) -> String:
	var skill := lib.skill(skill_id) if lib != null else null
	return String(skill.name).to_upper() if skill != null else skill_id.to_upper()


func _has_recall_stop() -> bool:
	for stop in _payload.get("stopped", []):
		if str((stop as Dictionary).get("reason", "")) == "patrol_recalled":
			return true
	return false
