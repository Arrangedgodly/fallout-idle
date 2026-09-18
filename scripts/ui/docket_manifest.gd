class_name DocketManifest
extends Docket
## DocketManifest — T10a inventory docket: every owned item with icon, name
## and mono count; equipment slots (weapon/armor) with UNEQUIP; equipping
## gear from the Manifest per the Melvor convention (Wasteland Patrol shows
## the resulting stats — T10b owns that screen). Selling lives at the Depot
## (D-06), not here.

var slots_row: HBoxContainer
var weapon_plate: PanelContainer
var weapon_name: Label
var weapon_serial: HFlowContainer
var weapon_unequip: Button
var armor_plate: PanelContainer
var armor_name: Label
var armor_serial: HFlowContainer
var armor_unequip: Button
var list: ItemList
var equip_button: Button
var status_line: Label


func weapon_serial_text() -> String:
	return flow_text(weapon_serial)


func armor_serial_text() -> String:
	return flow_text(armor_serial)

var _row_items: Array[String] = []  # row index -> item id
var _selected_item := ""
var _last_rows: Array[String] = []

const CATEGORY_ORDER := ["equipment", "material", "food", "resource"]


func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	add_child(micro("EQUIPMENT ON PERSON · BOTH SLOTS POSTED"))
	slots_row = hbox(10)
	add_child(slots_row)
	weapon_plate = _slot_plate("WEAPON")
	armor_plate = _slot_plate("ARMOR")
	slots_row.add_child(weapon_plate)
	slots_row.add_child(armor_plate)

	add_child(micro("MANIFEST · COUNTED WEEKLY, REMEMBERED ALWAYS"))
	var vent := panel_box("VentHousing")
	var vcol := vbox(8)
	list = ItemList.new()
	list.name = "ManifestLines"
	list.custom_minimum_size = Vector2(0.0, 168.0)
	list.focus_mode = Control.FOCUS_ALL
	list.fixed_icon_size = Vector2i(20, 20)
	list.tooltip_text = "Arrow keys walk the Manifest; Enter selects a line"
	list.item_selected.connect(_on_line_selected)
	vcol.add_child(list)
	equip_button = Button.new()
	equip_button.name = "EquipSelected"
	equip_button.text = "EQUIP · SELECT A GEAR LINE"
	equip_button.disabled = true
	equip_button.tooltip_text = "Move the selected equipment line onto your person"
	equip_button.pressed.connect(_on_equip_pressed)
	vcol.add_child(equip_button)
	status_line = label("PlateSerial", "THE MANIFEST REMEMBERS WHAT YOU FORGET.")
	vcol.add_child(status_line)
	vent.add_child(vcol)
	add_child(vent)

	# T15: the long mixed-case note wraps — at 200% font scale it is the
	# docket's widest line and must never demand horizontal scrolling.
	var note := label("BodyCopyDim", "Disposals are tendered at the REQUISITION DEPOT (D-06). The Manifest only counts.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func _slot_plate(slot_label: String) -> PanelContainer:
	var plate := panel_box("EnamelPlate")
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := vbox(4)
	col.add_child(label("PlateSerialNavy", slot_label))
	# T19: the gear serial is a [stat glyph][bonus] segment flow — every stat
	# number its gear posts carries its own stat's glyph.
	if slot_label == "WEAPON":
		weapon_name = label("FormTitle", "— VACANT —")
		weapon_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(weapon_name)
		weapon_serial = segment_flow(12)
		set_segments(weapon_serial, [{"icon": "", "text": "NO SIDEARM FILED"}], "PlateSerialNavy")
		col.add_child(weapon_serial)
		weapon_unequip = Button.new()
		weapon_unequip.name = "UnequipWeapon"
		weapon_unequip.text = "UNEQUIP"
		weapon_unequip.tooltip_text = "Return the weapon to the Manifest"
		weapon_unequip.pressed.connect(_on_unequip_pressed.bind("weapon"))
		col.add_child(weapon_unequip)
	else:
		armor_name = label("FormTitle", "— VACANT —")
		armor_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(armor_name)
		armor_serial = segment_flow(12)
		set_segments(armor_serial, [{"icon": "", "text": "NO PLATING FILED"}], "PlateSerialNavy")
		col.add_child(armor_serial)
		armor_unequip = Button.new()
		armor_unequip.name = "UnequipArmor"
		armor_unequip.text = "UNEQUIP"
		armor_unequip.tooltip_text = "Return the armor to the Manifest"
		armor_unequip.pressed.connect(_on_unequip_pressed.bind("armor"))
		col.add_child(armor_unequip)
	plate.add_child(col)
	return plate


# ------------------------------------------------------------------ refresh
func _refresh(changes: Dictionary) -> void:
	if tm == null or state() == null:
		return
	if changes.has("inventory") or changes.has("combat"):
		_refresh_slots()
	if changes.has("inventory"):
		_refresh_list()


func _refresh_slots() -> void:
	_fill_slot(weapon_plate, weapon_name, weapon_serial, weapon_unequip, "weapon", "NO SIDEARM FILED")
	_fill_slot(armor_plate, armor_name, armor_serial, armor_unequip, "armor", "NO PLATING FILED")


func _fill_slot(_plate: PanelContainer, name_label: Label, serial_flow: HFlowContainer,
		unequip_button: Button, slot_key: String, vacant_serial: String) -> void:
	var equipped := str(state().combat.get(slot_key, ""))
	if equipped == "":
		name_label.text = "— VACANT —"
		set_segments(serial_flow, [{"icon": "", "text": vacant_serial}], "PlateSerialNavy")
		unequip_button.disabled = true
		return
	var item: ItemDef = lib().item(equipped)
	var eq: EquipmentDef = lib().equipment_for(equipped)
	name_label.text = item.name.to_upper() if item != null else equipped
	set_segments(serial_flow,
		_gear_segments(eq) if eq != null else [{"icon": "", "text": equipped.to_upper()}],
		"PlateSerialNavy")
	unequip_button.disabled = false


## One [stat glyph][bonus] segment per stat the gear posts (T19 gear lines).
func _gear_segments(eq: EquipmentDef) -> Array:
	var out: Array = []
	if eq.attack_speed_ms > 0:
		out.append({"icon": GLYPH_INTERVAL, "text": "SWING %s S" % SignageFmt.seconds(eq.attack_speed_ms)})
	if eq.accuracy_bonus != 0:
		out.append({"icon": GLYPH_ACCURACY, "text": "ACC +%d" % eq.accuracy_bonus})
	if eq.max_hit_bonus != 0:
		out.append({"icon": GLYPH_MAX_HIT, "text": "MAX HIT +%d" % eq.max_hit_bonus})
	if eq.evasion_bonus != 0:
		out.append({"icon": GLYPH_EVADE, "text": "EVA +%d" % eq.evasion_bonus})
	if eq.max_hp_bonus != 0:
		out.append({"icon": GLYPH_CONDITION, "text": "HP +%d" % eq.max_hp_bonus})
	if out.is_empty():
		out.append({"icon": "", "text": "STANDARD ISSUE"})
	return out


func _refresh_list() -> void:
	var rows := _sorted_rows()
	if rows == _last_rows:
		_update_counts()
		return
	_last_rows = rows.duplicate()
	list.clear()
	_row_items = rows
	var keep := _selected_item
	for item_id in rows:
		var item: ItemDef = lib().item(item_id)
		var tex: Texture2D = load(ICON_DIR + item.icon + ".svg") if item != null else null
		list.add_item("%s ×%s" % [
			item.name.to_upper() if item != null else item_id,
			SignageFmt.num(state().item_count(item_id))], tex)
	# Re-select the same line if it survived the rebuild.
	for i in _row_items.size():
		if _row_items[i] == keep:
			list.select(i)
			_selected_item = keep
			_update_equip_button()
			return
	_selected_item = ""
	_update_equip_button()


## Rows changed but order stable: patch the counts in place (keeps selection).
func _update_counts() -> void:
	for i in _row_items.size():
		var item_id := _row_items[i]
		var item: ItemDef = lib().item(item_id)
		list.set_item_text(i, "%s ×%s" % [
			item.name.to_upper() if item != null else item_id,
			SignageFmt.num(state().item_count(item_id))])


func _sorted_rows() -> Array[String]:
	var rows: Array[String] = []
	for item_id in state().inventory:
		if int(state().inventory[item_id]) > 0:
			rows.append(String(item_id))
	rows.sort_custom(func(a: String, b: String) -> bool:
		var da: ItemDef = lib().item(a)
		var db: ItemDef = lib().item(b)
		var ca := CATEGORY_ORDER.find(da.category) if da != null else 99
		var cb := CATEGORY_ORDER.find(db.category) if db != null else 99
		if ca != cb:
			return ca < cb
		var na := da.name if da != null else a
		var nb := db.name if db != null else b
		return na < nb)
	return rows


# ------------------------------------------------------------------ interaction
func _on_line_selected(index: int) -> void:
	if index >= 0 and index < _row_items.size():
		_selected_item = _row_items[index]
		_update_equip_button()


func _update_equip_button() -> void:
	if _selected_item == "" or lib().equipment_for(_selected_item) == null \
			or state().item_count(_selected_item) < 1:
		equip_button.disabled = true
		equip_button.text = "EQUIP · SELECT A GEAR LINE"
		return
	equip_button.disabled = false
	var item: ItemDef = lib().item(_selected_item)
	equip_button.text = "EQUIP · %s" % item.name.to_upper()


func _on_equip_pressed() -> void:
	if _selected_item == "":
		return
	# Capture the name FIRST: equip_item force-flushes, which synchronously
	# rebuilds the list below (the equipped unit leaves the Manifest) and can
	# clear _selected_item before this handler resumes.
	var item := lib().item(_selected_item)
	var display := item.name.to_upper() if item != null else _selected_item.to_upper()
	var result: Dictionary = tm.equip_item(_selected_item)
	if bool(result["ok"]):
		status_line.text = "EQUIPPED · %s NOW ON PERSON" % display
	else:
		status_line.text = "NOT EQUIPPED · %s" % str(result["reason"]).to_upper()


func _on_unequip_pressed(slot_key: String) -> void:
	var result: Dictionary = tm.unequip_slot(slot_key)
	if bool(result["ok"]):
		status_line.text = "RETURNED TO MANIFEST · SLOT %s VACANT" % slot_key.to_upper()
	else:
		status_line.text = "NOT RETURNED · %s" % str(result["reason"]).to_upper()


## Test/probe seam: select a row by item id (same path as the keyboard/Enter
## selection).
func select_line_for(item_id: String) -> bool:
	for i in _row_items.size():
		if _row_items[i] == item_id:
			list.select(i)
			_on_line_selected(i)
			return true
	return false


## T33 reveal: the first equipment line the resident could actually equip
## (category order, count on hand). "" when no gear is held — the honest
## prerequisite path cues the gear's or a meal's source instead.
func first_equippable_id() -> String:
	if tm == null or state() == null:
		return ""
	for item_id in _row_items:
		if lib().equipment_for(item_id) != null and state().item_count(item_id) >= 1:
			return String(item_id)
	return ""
