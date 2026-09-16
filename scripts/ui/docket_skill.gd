class_name DocketSkill
extends Docket
## DocketSkill — T10a shared skeleton for the four workshop dockets
## (Scavenging, Foraging: DocketGathering; Junksmithing, Cooking:
## DocketProcessing). One skill, one active slot, one enamel gauge, a posted
## list of form lines (tier cards), and a stamped log.
##
## Card states are never color-alone (Daredevil floor): the running card
## carries the Energized variation AND a ">> " prefix on its title; a locked
## card posts a red CLEARANCE plate whose text names the required grade.
## The shell's big stencled button retexts BEGIN SHIFT <-> END SHIFT.
##
## Update discipline: gauge/cards/log mutate ONLY inside bulk_state_changed
## flushes and the immediate discrete signals (level_up, activity_stopped).
## Cards are built at bind() time (content lives behind ContentDB).

var skill_id := ""

var status_plate: PanelContainer
var status_line: Label
var status_serial: Label
var gauge: ProgressBar
var gauge_read: Label
var cards_box: VBoxContainer
var log: ItemList
var primary_button: Button  # the shell's BEGIN/END SHIFT plate (shell assigns)

var selected_id := ""  # content id the resident last posted ("" = none)

var _cards: Dictionary = {}        # content_id -> Card
var _content_order: Array[String] = []
var _inv_snapshot: Dictionary = {}  # attribution baseline for stamped deltas
var _last_completed := -1
var _completed_advance := 0  # completions this flush (attribution gate)


class Card:
	extends RefCounted
	var id := ""
	var button: Button
	var title: Label
	var rate_line: Label
	var yields_line: Label
	var gate_plate: PanelContainer
	var gate_text: Label


func _init(p_skill_id: String) -> void:
	skill_id = p_skill_id
	super()  # Docket._init -> _build_content() with skill_id set


const BEGIN_TEXT := "BEGIN SHIFT"
const END_TEXT := "END SHIFT"
const STAMP_CAP := 60


# ------------------------------------------------------------------ build
func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	status_plate = panel_box("EnergizedPlate")
	status_plate.visible = false
	# T15 fix round: the running-status line + serial STACK as full-width
	# VBox rows (the patrol phase plate's pattern). As HBox siblings beside
	# an EXPAND_FILL label, their WORD_SMART autowrap collapsed the minimum
	# width to ~1 px and the HBox starved each serial into a vertical
	# one-character column (verifier-measured at BOTH font scales).
	var srow := vbox(4)
	status_line = label("MonoValueEnergized", "")
	# T15: the long running-status serials wrap (mono, the plate's widest
	# lines at 200% font scale).
	status_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	srow.add_child(status_line)
	status_serial = label("PlateBodyEnergized", "")
	status_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	srow.add_child(status_serial)
	status_plate.add_child(srow)
	add_child(status_plate)

	var vent := panel_box("VentHousing")
	var vcol := vbox(8)
	vcol.add_child(micro("CLEARANCE GAUGE · POSTED RATES ARE THE HONEST RATES"))
	gauge = ProgressBar.new()
	gauge.show_percentage = false
	gauge.min_value = 0.0
	gauge.max_value = 100.0
	gauge.value = 0.0
	gauge.custom_minimum_size = Vector2(0.0, 20.0)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vcol.add_child(gauge)
	gauge_read = label("MonoValue", "CLEARANCE 01 · 0/0 XP TO NEXT")
	gauge_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vcol.add_child(gauge_read)
	vent.add_child(vcol)
	add_child(vent)

	add_child(micro(_list_header()))
	cards_box = vbox(8)
	add_child(cards_box)

	log = build_log(_log_serial(), 7)


func _list_header() -> String:
	return "POSTED SHIFTS · SELECT A FORM LINE"


func _log_serial() -> String:
	return "SHIFT LOG · STAMPS POSTED BY THE ENGINE ROOM"


## Content defs for this skill, display order (ascending clearance).
## Gathering returns ActivityDefs; processing overrides with RecipeDefs.
func _content_defs() -> Array:
	var out: Array = []
	var l := lib()
	if l == null:
		return out
	for id in l.activities:
		var a: ActivityDef = l.activities[id]
		if a.skill == skill_id:
			out.append(a)
	out.sort_custom(func(a, b) -> bool:
		return int(a.get("level_gate")) < int(b.get("level_gate")))
	return out


func _build_cards() -> void:
	for def in _content_defs():
		var card := _make_card(def)
		_cards[card.id] = card
		_content_order.append(card.id)
		cards_box.add_child(card.button)


func _make_card(def: RefCounted) -> Card:
	var card := Card.new()
	card.id = str(def.get("id"))
	# T15: CardButton — the button's minimum size includes its label stack.
	var b := Docket.CardButton.new()
	b.name = "Card_" + card.id
	b.pressed.connect(_on_card_pressed.bind(card.id))
	b.tooltip_text = "Post this shift — %s" % str(def.get("name"))
	card.button = b

	# Full-width stacked rows: the title row keeps icon + name on one line;
	# the rate/yields serials stack below at full card width — nothing
	# side-by-side can outgrow the docket (no horizontal overflow), and a
	# wrapped serial must never sit beside an EXPAND_FILL sibling (T15 fix
	# round: that placement starved it to a 1 px vertical column).
	var col := vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_row := hbox(10)
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(icon_rect(_card_icon(def), 30))
	card.title = label("FormTitle", str(def.get("name")))
	card.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(card.title)
	col.add_child(title_row)

	# T15 fix round: the serial rate line sits BELOW the title row as a
	# full-width wrapped row — one horizontal line at 100%, wrapping within
	# the card at 200% (unwrapped it was the docket's widest line at 200%,
	# but as a wrapped HBox sibling its ~1 px minimum collapsed it).
	card.rate_line = label("PlateSerialNavy", _rate_line(def))
	card.rate_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card.rate_line)

	card.yields_line = label("PlateSerialNavy", _yields_line(def))
	card.yields_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card.yields_line)

	card.gate_plate = panel_box("DangerPlate")
	card.gate_text = label("MonoValue", "")
	card.gate_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.gate_plate.add_child(card.gate_text)
	col.add_child(card.gate_plate)

	b.add_child(col)
	return card


func _card_icon(def: RefCounted) -> String:
	return str(def.get("icon"))


func _rate_line(def: RefCounted) -> String:
	return "+%s XP / ACTION · %s S INTERVAL" % [
		SignageFmt.num(int(def.get("xp_per_action"))),
		SignageFmt.seconds(int(def.get("interval_ms")))]


func _yields_line(def: RefCounted) -> String:
	var l := lib()
	var table: DropTableDef = l.drop_table(str(def.get("drop_table")))
	if table == null:
		return "NO YIELD TABLE POSTED"
	var parts: Array[String] = []
	for entry in table.entries:
		var item: ItemDef = l.item(entry.item)
		var item_name: String = item.name.to_upper() if item != null else entry.item
		parts.append("%s %s%% %s" % [item_name,
			SignageFmt.pct(entry.weight, table.total_weight()),
			SignageFmt.qty(entry.qty_min, entry.qty_max)])
	return "YIELDS: " + " · ".join(parts)


# ------------------------------------------------------------------ interaction
func _on_card_pressed(content_id: String) -> void:
	select_content(content_id)


## Post a shift: select + start through the engine façade (the engine owns
## every rule; the docket only renders results). A gate denial stamps the
## clearance line instead of starting.
func select_content(content_id: String) -> void:
	selected_id = content_id
	var result: Dictionary = tm.start_activity(content_id)
	if bool(result["ok"]):
		stamp(log, _start_stamp_text(content_id))
	else:
		stamp(log, _denied_stamp_text(str(result["reason"])))
	_refresh({"activity": true, "inventory": true, "xp": true})


func _start_stamp_text(content_id: String) -> String:
	return "SHIFT POSTED — " + _content_name(content_id).to_upper()


func _denied_stamp_text(reason: String) -> String:
	return reason.to_upper() + " · ELEVATION IS EARNED, NOT REQUESTED"


func _content_name(content_id: String) -> String:
	var def: RefCounted = tm.engine.def_of(content_id)
	return String(def.get("name")) if def != null and def.get("name") != null else content_id


## BEGIN/END SHIFT: the primary action on the docket (per FIRST VIEWPORT).
func primary_action() -> void:
	if tm == null or state() == null:
		return
	if state().active.has(skill_id):
		tm.stop_skill(skill_id)
		stamp(log, "SHIFT ENDED BY RESIDENT.")
		return
	var target := selected_id
	if target == "" or not tm.engine.is_unlocked(state(), target):
		target = _first_unlocked()
	if target == "":
		stamp(log, _nothing_startable_text())
		_refresh({"activity": true})
		return
	select_content(target)


func _first_unlocked() -> String:
	for id in _content_order:
		if tm.engine.is_unlocked(state(), id):
			return id
	return ""


func _nothing_startable_text() -> String:
	return "NOTHING TO POST. THE PILE AWAITS."


# ------------------------------------------------------------------ bind + refresh
func _on_bound() -> void:
	if cards_box.get_child_count() == 0:
		_build_cards()
	var slot = state().active.get(skill_id) if state() != null else null
	_last_completed = int(slot.get("completed")) if slot != null else -1
	_inv_snapshot = state().inventory.duplicate() if state() != null else {}
	if slot != null:
		selected_id = String(slot.get("content_id"))


func _refresh(changes: Dictionary) -> void:
	if tm == null or state() == null:
		return
	_completed_advance = 0
	if changes.has("xp"):
		_refresh_gauge()
	if changes.has("activity") or changes.has("xp"):
		_refresh_activity()
	if changes.has("inventory"):
		_stamp_inventory_deltas()
		_refresh_inventory_dependent()


func _refresh_gauge() -> void:
	var l := lib()
	var skill := l.skill(skill_id)
	var curve := l.xp_curve(skill.xp_curve)
	var level := int(state().skills_level.get(skill_id, 1))
	var xp := int(state().skills_xp.get(skill_id, 0))
	if level >= curve.max_level:
		gauge.max_value = 1.0
		gauge.value = 1.0
		gauge_read.text = "CLEARANCE %02d · MAXIMUM GRADE · %s XP LIFETIME" % [
			level, SignageFmt.num(xp)]
		return
	var floor_xp := curve.total_xp_to_reach(level)
	var to_next := curve.xp_to_next(level)
	var into_level := xp - floor_xp
	gauge.max_value = float(maxi(to_next, 1))
	gauge.value = float(clampi(into_level, 0, to_next))
	gauge_read.text = "CLEARANCE %02d · %s/%s XP TO NEXT" % [
		level, SignageFmt.num(into_level), SignageFmt.num(to_next)]


func _refresh_activity() -> void:
	var slot = state().active.get(skill_id)
	var running := slot != null
	var running_id := String(slot.get("content_id")) if running else ""
	for id in _content_order:
		_apply_card_state(_cards[id], running and id == running_id,
			not tm.engine.is_unlocked(state(), id))
	if running:
		status_plate.visible = true
		status_line.text = ">> SHIFT IN PROGRESS — " + _content_name(running_id).to_upper()
		status_serial.text = "ONE ACTION EVERY %s S" % SignageFmt.seconds(int(slot.get("interval_ms")))
		var completed := int(slot.get("completed"))
		if _last_completed >= 0 and completed > _last_completed:
			_completed_advance = completed - _last_completed
			_stamp_completed_actions(slot, _completed_advance)
		_last_completed = completed
	else:
		status_plate.visible = false
		_last_completed = -1
	if primary_button != null:
		primary_button.text = END_TEXT if running else BEGIN_TEXT


func _apply_card_state(card: Card, energized: bool, locked: bool) -> void:
	var def: RefCounted = tm.engine.def_of(card.id)
	var display_name: String = str(def.get("name")) if def != null else card.id
	if energized:
		card.button.theme_type_variation = "Energized"
		card.title.theme_type_variation = "FormTitleEnergized"
		card.title.text = ">> " + display_name
		card.rate_line.theme_type_variation = "MonoValueEnergized"
		card.yields_line.theme_type_variation = "MonoValueEnergized"
	else:
		card.button.theme_type_variation = ""
		card.title.theme_type_variation = "FormTitle"
		card.title.text = display_name
		card.rate_line.theme_type_variation = "PlateSerialNavy"
		card.yields_line.theme_type_variation = "PlateSerialNavy"
	card.gate_text.text = _gate_text(card.id)
	card.gate_plate.visible = locked


func _gate_text(content_id: String) -> String:
	# On a skill's own docket the gating skill is self-evident — the plate
	# names only the grade (the Depot, where gates span skills, names both).
	var gate: Dictionary = tm.engine.gate_of(content_id)
	return "CLEARANCE %d REQUIRED" % int(gate["level"])


## Subclass hook: refresh lines that read live inventory (craftable counts).
func _refresh_inventory_dependent() -> void:
	pass


# ------------------------------------------------------------------ stamps
## Inventory deltas ride the 4 Hz bulk flush. Attribution filter: only items
## on the RUNNING content's own yield list stamp here, and only on flushes
## where this skill's slot completed actions — the Manifest stays the truth.
func _stamp_inventory_deltas() -> void:
	var current := state().inventory
	var slot = state().active.get(skill_id)
	if slot == null or _completed_advance <= 0:
		_inv_snapshot = current.duplicate()
		return
	var watch: Dictionary = _watched_items(slot)
	for item_id in watch:
		var now_qty := int(current.get(item_id, 0))
		var was_qty := int(_inv_snapshot.get(item_id, 0))
		if now_qty != was_qty:
			stamp(log, _delta_stamp_text(item_id, now_qty - was_qty))
	_inv_snapshot = current.duplicate()


func _delta_stamp_text(item_id: String, diff: int) -> String:
	var item := lib().item(item_id)
	var item_name: String = item.name.to_upper() if item != null else item_id.to_upper()
	return "%s %s" % [item_name, SignageFmt.delta(diff)]


## Items this docket's log may speak for while its slot runs (gathering
## overrides with the running activity's yield items).
func _watched_items(_slot) -> Dictionary:
	return {}


## Per-completed-action stamps — recipes override (deterministic craft
## lines); gathering stamps its rolled deltas via _stamp_inventory_deltas.
func _stamp_completed_actions(_slot, _count: int) -> void:
	pass


func _on_level_up(skill: String, _old_level: int, new_level: int) -> void:
	if skill != skill_id or log == null:
		return
	stamp(log, "CLEARANCE %02d EARNED · %s" % [
		new_level, String(lib().skill(skill_id).name).to_upper()])


func _on_activity_stopped(skill: String, _content_id: String, reason: String) -> void:
	if skill != skill_id:
		return
	match reason:
		"inputs_exhausted":
			stamp(log, "SUPPLIES EXHAUSTED · SHIFT ENDED. REQUISITION MORE.")
		"content_missing":
			stamp(log, "POSTING WITHDRAWN BY THE DEPARTMENT.")
	super._on_activity_stopped(skill, _content_id, reason)
