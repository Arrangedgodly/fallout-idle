class_name DocketDepot
extends Docket
## DocketDepot — T10a requisition docket: stock lines with buy prices in
## Crowns (mono), buy 1 / buy max, a disposals counter selling at each
## item's one honest value, clearance gates on gated lines, and the currency
## plate posted at the top of the docket at all times. Transactions run
## through the TickManager depot façade (wallet rules stay engine-side).

var crowns_read: Label
var crowns_serial: Label
var stock_box: VBoxContainer
var sell_box: VBoxContainer
var sell_vent: PanelContainer
var log: ItemList

var _buy_rows: Dictionary = {}  # item_id -> {max_button, line_label}
var _sell_rows: Dictionary = {} # item_id -> {row, count_label, sell1, sell_all}
var _last_sell_ids: Array[String] = []


func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	# The currency plate — always visible on the Depot docket.
	var wallet := panel_box("EnergizedPlate")
	var wrow := hbox(14)
	wrow.add_child(icon_rect("crowns", 34))
	var wcol := vbox(2)
	# T15 fix round: the column EXPANDS to the plate's full width — without
	# the flag the HBox sized it to its widest minimum (the "0" read, ~16 px)
	# and the wrapped crowns serial stacked two characters per line (the
	# same autowrap-starvation class the retry pin guards).
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crowns_serial = label("PlateBodyEnergized", "CROWNS ON HAND · TENDERS EXACT · NO CREDIT")
	crowns_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(crowns_serial)
	crowns_read = label("MonoBig", "0")
	wcol.add_child(crowns_read)
	wrow.add_child(wcol)
	wallet.add_child(wrow)
	add_child(wallet)

	add_child(micro("REQUISITIONS · STOCK POSTED AT THE COUNTER"))
	var vent := panel_box("VentHousing")
	stock_box = vbox(6)
	vent.add_child(stock_box)
	add_child(vent)

	add_child(micro("DISPOSALS · THE COUNTER BUYS AT ONE HONEST RATE"))
	sell_vent = panel_box("VentHousing")
	sell_box = vbox(6)
	sell_vent.add_child(sell_box)
	add_child(sell_vent)

	log = build_log("DEPOT LEDGER · TENDERS POSTED", 5)


func _on_bound() -> void:
	# Stock lines are static content — build once, never rebuild (a rebuild
	# while the previous rows are queue_free'd would name-shadow: Godot
	# auto-renames colliding children, breaking name-based lookups).
	if stock_box.get_child_count() == 0:
		_build_stock_rows()
	_rebuild_sell_rows()


func _refresh(changes: Dictionary) -> void:
	if tm == null or state() == null:
		return
	if changes.has("inventory"):
		crowns_read.text = SignageFmt.num(state().crowns)
		_update_stock_affordability()
		_rebuild_sell_rows()


# ------------------------------------------------------------------ helpers
## Detach + free: queue_free alone leaves name-shadowing zombies until idle,
## which force-renames same-named replacements (Godot auto-deduplicates
## child names). Detaching first keeps names stable for lookups.
func _purge_children(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# ------------------------------------------------------------------ stock (buy)
func _build_stock_rows() -> void:
	_purge_children(stock_box)
	_buy_rows.clear()
	var entries := lib().shop_entries()
	for i in entries.size():
		var entry: ShopEntryDef = entries[i]
		if i > 0:
			var sep := HSeparator.new()
			stock_box.add_child(sep)
		stock_box.add_child(_make_stock_row(entry))


func _make_stock_row(entry: ShopEntryDef) -> Control:
	var item: ItemDef = lib().item(entry.item)
	var row := hbox(10)
	row.name = "BuyRow_" + entry.item

	row.add_child(icon_rect(item.icon if item != null else "", 24))
	var col := vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label("SectionLabel", item.name.to_upper() if item != null else entry.item))
	# T19: the Crowns mark posts beside every price (the wrapped serial stays
	# the sole EXPAND_FILL child of the row).
	var price_row := hbox(8)
	price_row.add_child(icon_rect("crowns", 18))
	var line := label("MonoValue", "%s CROWNS EA · SELL RATE %s" % [
		SignageFmt.num(entry.buy_price),
		SignageFmt.num(item.value if item != null else 0)])
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(line)
	col.add_child(price_row)

	if entry.is_gated():
		# The clearance plate stacks under the price (full column width) —
		# never a side-by-side overflow risk at 1280. T19: it carries the
		# clearance staircase glyph beside the required grade (never a padlock).
		var gate := panel_box("DangerPlate")
		var gate_line := label("MonoValue", "CLEARANCE %d REQUIRED · %s" % [
			entry.gate_level, String(lib().skill(entry.gate_skill).name).to_upper()])
		gate_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gate.add_child(glyph_beside(GLYPH_CLEARANCE, gate_line))
		col.add_child(gate)
		row.add_child(col)
		_buy_rows[entry.item] = {"gated": true}
		return row
	row.add_child(col)

	# Tender buttons stacked vertically at the right — narrow by design.
	var buttons := vbox(4)
	var buy1 := Button.new()
	buy1.name = "Buy1_" + entry.item
	buy1.text = "BUY 1"
	buy1.tooltip_text = "Tender %s Crowns for one %s" % [
		SignageFmt.num(entry.buy_price), item.name if item != null else entry.item]
	buy1.pressed.connect(_on_buy_pressed.bind(entry.item, 1))
	buttons.add_child(buy1)

	var buy_max := Button.new()
	buy_max.name = "BuyMax_" + entry.item
	buy_max.tooltip_text = "Tender for as many as the wallet allows"
	buy_max.pressed.connect(_on_buy_max_pressed.bind(entry.item))
	buttons.add_child(buy_max)
	row.add_child(buttons)

	_buy_rows[entry.item] = {"gated": false, "max_button": buy_max, "line_label": line}
	return row


func _update_stock_affordability() -> void:
	for item_id in _buy_rows:
		var info: Dictionary = _buy_rows[item_id]
		if bool(info.get("gated", false)):
			continue
		var entry := _entry_for(item_id)
		if entry == null:
			continue
		var max_n: int = tm.depot_max_affordable(item_id)
		var max_button: Button = info["max_button"]
		max_button.text = "BUY ×%d" % max_n if max_n > 0 else "BUY ×0"
		max_button.disabled = max_n < 1
		max_button.tooltip_text = ("Tender %s Crowns for %d" % [
			SignageFmt.num(entry.buy_price * max_n), max_n]) if max_n > 0 \
			else "INSUFFICIENT CROWNS"


func _entry_for(item_id: String) -> ShopEntryDef:
	for entry in lib().shop_entries():
		if entry.item == item_id:
			return entry
	return null


func _on_buy_pressed(item_id: String, qty: int) -> void:
	var result: Dictionary = tm.depot_buy(item_id, qty)
	if bool(result["ok"]):
		var item: ItemDef = lib().item(item_id)
		var entry := _entry_for(item_id)
		stamp(log, "REQUISITIONED ×%d — %s (%s CROWNS)" % [
			qty, item.name.to_upper() if item != null else item_id,
			SignageFmt.num(entry.buy_price * qty)], item_icon_texture(item_id))
	else:
		stamp(log, "REFUSED · %s" % str(result["reason"]).to_upper())


func _on_buy_max_pressed(item_id: String) -> void:
	var max_n: int = tm.depot_max_affordable(item_id)
	if max_n < 1:
		stamp(log, "REFUSED · INSUFFICIENT CROWNS")
		return
	_on_buy_pressed(item_id, max_n)


# ------------------------------------------------------------------ disposal (sell)
func _rebuild_sell_rows() -> void:
	var ids := _sellable_ids()
	if ids == _last_sell_ids and sell_box.get_child_count() > 0:
		_update_sell_counts()
		return
	_purge_children(sell_box)
	_sell_rows.clear()
	_last_sell_ids = ids.duplicate()
	if ids.is_empty():
		sell_box.add_child(label("MonoValue", "NOTHING TO TENDER. THE COUNTER REMAINS CHEERFUL."))
		return
	for i in ids.size():
		var item_id := ids[i]
		if i > 0:
			sell_box.add_child(HSeparator.new())
		sell_box.add_child(_make_sell_row(item_id))
	_update_sell_counts()


func _sellable_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id in state().inventory:
		var item: ItemDef = lib().item(item_id)
		if item != null and item.value > 0 and int(state().inventory[item_id]) > 0:
			ids.append(String(item_id))
	ids.sort()
	return ids


func _make_sell_row(item_id: String) -> Control:
	var item: ItemDef = lib().item(item_id)
	var row := hbox(10)
	row.name = "SellRow_" + item_id
	row.add_child(icon_rect(item.icon, 24))
	var col := vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label("SectionLabel", item.name.to_upper()))
	# T19: the count/tender serial — the Crowns mark sits beside the per-unit
	# price, segment flow (no autowrap anywhere in the flow).
	var count_flow := segment_flow(8)
	var count_label := add_segment(count_flow, "", "", "MonoValue")
	add_segment(count_flow, "crowns", "%s CROWNS EA" % SignageFmt.num(item.value), "MonoValue")
	col.add_child(count_flow)
	row.add_child(col)

	var sell1 := Button.new()
	sell1.name = "Sell1_" + item_id
	sell1.text = "SELL 1"
	sell1.tooltip_text = "Tender one %s for %s Crowns" % [item.name, SignageFmt.num(item.value)]
	sell1.pressed.connect(_on_sell_pressed.bind(item_id, 1))
	row.add_child(sell1)

	var sell_all := Button.new()
	sell_all.name = "SellAll_" + item_id
	sell_all.text = "SELL ALL"
	sell_all.tooltip_text = "Tender the whole stack"
	sell_all.pressed.connect(_on_sell_pressed.bind(item_id, 0))
	row.add_child(sell_all)

	_sell_rows[item_id] = {"count_label": count_label, "sell1": sell1, "sell_all": sell_all}
	return row


func _update_sell_counts() -> void:
	for item_id in _sell_rows:
		var info: Dictionary = _sell_rows[item_id]
		var item: ItemDef = lib().item(item_id)
		var have := state().item_count(item_id)
		# T19: count segment leads the flow; the Crowns glyph + per-unit
		# tender follow it (joined read: "×N ON HAND · M CROWNS EA").
		(info["count_label"] as Label).text = "×%s ON HAND ·" % SignageFmt.num(have)


func _on_sell_pressed(item_id: String, qty: int) -> void:
	var item: ItemDef = lib().item(item_id)
	var result: Dictionary = tm.depot_sell(item_id, qty)
	if bool(result["ok"]):
		# T19: tenders post the Crowns mark (currency in), requisitions the
		# item's mark (goods in).
		stamp(log, "TENDERED ×%d — %s (%s CROWNS)" % [
			int(result.get("qty", 0)), item.name.to_upper(),
			SignageFmt.num(int(result.get("crowns", 0)))], icon_texture("crowns"))
	else:
		stamp(log, "REFUSED · %s" % str(result["reason"]).to_upper())
