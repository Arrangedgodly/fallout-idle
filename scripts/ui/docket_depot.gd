class_name DocketDepot
extends Docket
## DocketDepot — T10a requisition docket, restructured by T32 (run-5 Scope
## Amendment 3, complaint #2: "for selling, we only have sell 1 or sell max.
# we need to make buttons for sell 1, 10%, 25%, 50%, 100% or a custom amount.
## I think sell screens should be on a separate screen from the buy screens.").
##
## The docket is a TAB PAIR in the T26 zone-tab grammar (one radio group,
## the active tab carries the ">> " prefix + the Energized variation — never
## color alone; explicit content swap, NOT one long combined board):
##   BUY  — the stock counter exactly as shipped (buy 1 / buy max, gates);
##   SELL — the PLAYER's sellable inventory (item icon, name, held count in
##          mono, unit tender, full-stack total), so filing a crowns claim no
##          longer scrolls past the entire stock list. Each line carries the
##          amendment's quantity row: SELL 1 / SELL 10% / SELL 25% /
##          SELL 50% / SELL 100% / CUSTOM (a validated inline field, 1..held,
##          with a live proceeds readout).
##
## Honest math (the amendment's own constraint): every quantity label is
## computed by pure int arithmetic — floor(stack × pct) via
## _pct_count()'s split div/mod form, exact across the full int64 range
## (no float coercion anywhere near a stack); a button whose count is 0 is
## disabled; 100% is the whole stack by construction; every button tooltip
## and the custom field's preview state the exact proceeds. CUSTOM validates
## 1..held — an out-of-range posting is REFUSED through the T31 refusal-strip
## idiom (the notice posts at the docket's top, in voice, and withdraws on
## the next successful tender), never silently clamped.
##
## Every sale routes through the REAL engine path (TickManager.depot_sell —
## wallet rules stay engine-side; the O-1 FILE A CROWNS CLAIM seam and the
## dossier sell counters fire inside it) and lands as a ledger stamp; the
## wallet plate and the Manifest re-read the batched flush live.
##
## Tab state persists across department switches within the session (the
## docket instance is built once by the shell and only re-shown) and resets
## sanely to BUY on boot. The SELL tab is a stable, queryable target for the
## O-1 deep link (T33): select_tab()/active_tab(), named DepotTab_Buy /
## DepotTab_Sell buttons, SellRow_<item_id> lines.
##
## Hotkey safety: the custom field is the docket's only text input — while it
## holds focus it consumes the digit keys (the GUI has its turn before
## Concourse._unhandled_input), so the department hotkeys 1-8 stay intact:
## typing an amount never teleports the resident to another department.

const TAB_BUY := "buy"
const TAB_SELL := "sell"
const TAB_LABELS := {TAB_BUY: "BUY", TAB_SELL: "SELL"}
## T32 quantity ladder (Scope Amendment 3 verbatim: 1 / 10% / 25% / 50% /
## 100% / custom). 100% is the SellAll_ node (it is the old SELL ALL —
## the whole stack, by construction).
const PCT_STEPS := [10, 25, 50, 100]

var crowns_read: Label
var crowns_serial: Label
var tab_buy: Button
var tab_sell: Button
var buy_region: VBoxContainer
var sell_region: VBoxContainer
var stock_box: VBoxContainer
var sell_box: VBoxContainer
var sell_vent: PanelContainer
var log: ItemList

var _buy_rows: Dictionary = {}  # item_id -> {max_button, line_label}
## item_id -> {count_label, stack_label, sell1, pct (pct -> Button), sell_all,
## custom_btn, custom_row, field, tender, preview, last_have}
var _sell_rows: Dictionary = {}
var _last_sell_ids: Array[String] = []
var _active_tab := TAB_BUY


func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	# T32: the T31 refusal strip mounts here too (child index 0, in-flow,
	# hidden until posted) — a refused custom amount answers at the docket's
	# top, exactly where the resident is looking.
	add_child(build_refusal_strip())

	# The currency plate — always visible on the Depot docket, above the tab
	# pair (both tabs tender against it).
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

	# T32: the BUY/SELL tab pair — the T26 zone-tab grammar (one radio group,
	# ">> " + Energized on the active tab, explicit content swap).
	var tabs_row := hbox(8)
	tabs_row.name = "DepotTabs"
	add_child(tabs_row)
	var tab_group := ButtonGroup.new()
	tab_buy = _make_depot_tab(tabs_row, TAB_BUY, tab_group)
	tab_sell = _make_depot_tab(tabs_row, TAB_SELL, tab_group)

	# BUY region — the stock counter exactly as shipped.
	buy_region = vbox(6)
	buy_region.name = "BuyRegion"
	buy_region.add_child(micro("REQUISITIONS · STOCK POSTED AT THE COUNTER"))
	var vent := panel_box("VentHousing")
	stock_box = vbox(6)
	vent.add_child(stock_box)
	buy_region.add_child(vent)
	add_child(buy_region)

	# SELL region — the player's sellable holdings with the quantity ladder.
	sell_region = vbox(6)
	sell_region.name = "SellRegion"
	sell_region.add_child(micro("DISPOSALS · THE COUNTER BUYS AT ONE HONEST RATE"))
	sell_vent = panel_box("VentHousing")
	sell_box = vbox(6)
	sell_vent.add_child(sell_box)
	sell_region.add_child(sell_vent)
	add_child(sell_region)

	log = build_log("DEPOT LEDGER · TENDERS POSTED", 5)

	# Honest boot default: the stock counter leads; the choice PERSISTS for
	# the session (the docket instance survives department switches) and
	# resets here on boot.
	select_tab(TAB_BUY)


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


# ------------------------------------------------------------------ tabs (T32)
## The queried tab id (TAB_BUY | TAB_SELL) — the O-1 deep link's stable
## handle (T33) and the tests' readout.
func active_tab() -> String:
	return _active_tab


## Post one tab's content. Idempotent + guarded (safe from refresh paths and
## from _build_content, before the tree exists). Order-preserving: BUY is the
## first tab, SELL the second — the tab row never reorders.
func select_tab(tab_id: String) -> void:
	if tab_id != TAB_BUY and tab_id != TAB_SELL:
		return
	_active_tab = tab_id
	_apply_depot_tab(tab_buy, String(TAB_LABELS[TAB_BUY]), tab_id == TAB_BUY)
	_apply_depot_tab(tab_sell, String(TAB_LABELS[TAB_SELL]), tab_id == TAB_SELL)
	if buy_region != null:
		buy_region.visible = tab_id == TAB_BUY
	if sell_region != null:
		sell_region.visible = tab_id == TAB_SELL


## The zone-tab state grammar, verbatim: the active tab carries BOTH
## non-color cues (">> " prefix + Energized variation) and the radio state.
func _apply_depot_tab(tab: Button, display: String, active: bool) -> void:
	if tab == null:
		return
	var text := (">> " + display) if active else display
	if tab.text != text:
		tab.text = text
	var variation := "Energized" if active else ""
	if tab.theme_type_variation != variation:
		tab.theme_type_variation = variation
	tab.button_pressed = active


## One tab: a toggle plate in the shared radio group (the T26 component
## grammar). Adjacent in one HBox, so the arrow keys hop between them and
## Tab/Shift-Tab walks in through either plate; reading order is BUY, SELL.
func _make_depot_tab(row: HBoxContainer, tab_id: String, group: ButtonGroup) -> Button:
	var display := String(TAB_LABELS[tab_id])
	var tab := Button.new()
	tab.name = "DepotTab_" + display.capitalize()
	tab.text = display
	tab.toggle_mode = true
	tab.button_group = group
	tab.focus_mode = Control.FOCUS_ALL
	tab.set_meta("tab_id", tab_id)
	tab.tooltip_text = "Post the stock counter — requisitions at the posted prices" \
		if tab_id == TAB_BUY \
		else "Post your holdings — file a crowns claim at the one honest rate"
	tab.pressed.connect(select_tab.bind(tab_id))
	row.add_child(tab)
	return tab


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
		_update_sell_lines()
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
	_update_sell_lines()


## Only what the resident OWNS and the counter actually buys (a positive
## honest value), in stable name order — the SELL tab is never the shop's
## stock list.
func _sellable_ids() -> Array[String]:
	var ids: Array[String] = []
	for item_id in state().inventory:
		var item: ItemDef = lib().item(item_id)
		if item != null and item.value > 0 and int(state().inventory[item_id]) > 0:
			ids.append(String(item_id))
	ids.sort()
	return ids


## One disposal line: [icon | name + counts] over the quantity ladder
## (the T32 amendment row), plus the CUSTOM field row (hidden until asked).
func _make_sell_row(item_id: String) -> Control:
	var item: ItemDef = lib().item(item_id)
	var row := vbox(4)
	row.name = "SellRow_" + item_id

	var top := hbox(10)
	top.add_child(icon_rect(item.icon, 24))
	var col := vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label("SectionLabel", item.name.to_upper()))
	# T19: the count/tender serial — the Crowns mark sits beside the per-unit
	# price, segment flow (no autowrap anywhere in the flow). T32 adds the
	# full-stack total as a third bare-mono segment.
	var count_flow := segment_flow(8)
	var count_label := add_segment(count_flow, "", "", "MonoValue")
	add_segment(count_flow, "crowns", "%s CROWNS EA" % SignageFmt.num(item.value), "MonoValue")
	var stack_label := add_segment(count_flow, "", "", "MonoValue")
	col.add_child(count_flow)
	top.add_child(col)
	row.add_child(top)

	# The T32 quantity ladder — 1 / 10% / 25% / 50% / 100% / custom. A flow
	# (never a fixed row): the buttons wrap at 200% font scale instead of
	# overflowing. Counts post ON the buttons (honest math at a glance) and
	# exact proceeds ride every tooltip.
	var qty_flow := HFlowContainer.new()
	qty_flow.name = "QtyFlow_" + item_id
	qty_flow.add_theme_constant_override("h_separation", 6)
	qty_flow.add_theme_constant_override("v_separation", 4)

	var sell1 := _qty_button(qty_flow, "Sell1_" + item_id, "SELL 1")
	sell1.pressed.connect(_on_sell_pressed.bind(item_id, 1))

	var pct_buttons := {}
	for pct in PCT_STEPS:
		var pct_id := int(pct)
		var control_name := "SellPct%d_%s" % [pct_id, item_id]
		if pct_id == 100:
			control_name = "SellAll_" + item_id  # 100% IS sell-all (the shipped node name)
		var b := _qty_button(qty_flow, control_name, "")
		b.pressed.connect(_on_sell_pct_pressed.bind(item_id, pct_id))
		pct_buttons[pct_id] = b

	var custom_btn := _qty_button(qty_flow, "SellCustom_" + item_id, "CUSTOM…")
	custom_btn.pressed.connect(_on_custom_toggled.bind(item_id))
	row.add_child(qty_flow)

	# The CUSTOM field row: a validated inline amount (1..held) with a live
	# proceeds readout. Hidden until CUSTOM is pressed.
	var custom_row := HFlowContainer.new()
	custom_row.name = "CustomRow_" + item_id
	custom_row.add_theme_constant_override("h_separation", 6)
	custom_row.add_theme_constant_override("v_separation", 4)
	custom_row.visible = false
	var field := LineEdit.new()
	field.name = "CustomField_" + item_id
	field.custom_minimum_size = Vector2(96.0, 0.0)
	field.max_length = 18  # posting width, not policy — validation owns the truth
	field.placeholder_text = "1"
	field.tooltip_text = "Post an exact amount of units to tender (1 up to the stack on hand)"
	var tender := Button.new()
	tender.name = "CustomTender_" + item_id
	tender.text = "TENDER"
	tender.focus_mode = Control.FOCUS_ALL
	tender.disabled = true
	tender.tooltip_text = "Post a valid amount first (1 up to the stack on hand)"
	tender.pressed.connect(_on_custom_tender_pressed.bind(item_id))
	var preview := label("MonoValue", "")
	preview.name = "CustomPreview_" + item_id
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_row.add_child(field)
	custom_row.add_child(tender)
	custom_row.add_child(preview)
	row.add_child(custom_row)
	field.text_changed.connect(_on_custom_text_changed.bind(item_id))
	field.text_submitted.connect(_on_custom_submitted.bind(item_id))

	_sell_rows[item_id] = {
		"count_label": count_label, "stack_label": stack_label,
		"sell1": sell1, "pct": pct_buttons, "custom_btn": custom_btn,
		"custom_row": custom_row, "field": field, "tender": tender,
		"preview": preview, "last_have": -1,
	}
	return row


func _qty_button(flow: FlowContainer, control_name: String, text: String) -> Button:
	var b := Button.new()
	b.name = control_name
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	flow.add_child(b)
	return b


## THE honest count: floor(have × pct ÷ 100) in pure int arithmetic — split
## div/mod so no product ever overflows int64 (a 10^18 stack cannot corrupt
## the ladder), no float ever rounds a stack. 100% is the whole stack by
## construction. A count of 0 disables its button.
static func _pct_count(have: int, pct: int) -> int:
	return have / 100 * pct + have % 100 * pct / 100


## Rows changed but order stable: patch in place (the manifest's rebuild/
## patch discipline). No-change signature guard: a flush that moved nothing
## writes nothing (the T6/T14 idle budget). A row with the CUSTOM field open
## re-reads every pass — its bounds and preview depend on the live stack.
func _update_sell_lines() -> void:
	for item_id in _sell_rows:
		var info: Dictionary = _sell_rows[item_id]
		var item: ItemDef = lib().item(item_id)
		var have := state().item_count(item_id)
		var custom_open: bool = (info["custom_row"] as Control).visible
		if int(info["last_have"]) == have and not custom_open:
			continue
		info["last_have"] = have
		# T19: count segment leads the flow; the Crowns glyph + per-unit
		# tender follow it; T32 appends the full-stack total (bare mono).
		(info["count_label"] as Label).text = "×%s ON HAND ·" % SignageFmt.num(have)
		(info["stack_label"] as Label).text = "%s FULL STACK" % SignageFmt.num(have * item.value)
		var sell1: Button = info["sell1"]
		sell1.disabled = have < 1
		sell1.tooltip_text = "Tender one %s for %s Crowns" % [
			item.name, SignageFmt.num(item.value)]
		var pcts: Dictionary = info["pct"]
		for pct_id in pcts:
			var n := _pct_count(have, int(pct_id))
			var b: Button = pcts[pct_id]
			b.text = "SELL %d%% · %s" % [int(pct_id), SignageFmt.num(n)]
			b.disabled = n < 1
			b.tooltip_text = ("Tender %s units for %s Crowns" % [
				SignageFmt.num(n), SignageFmt.num(n * item.value)]) if n > 0 \
				else "This share of the stack rounds to nothing"
		var custom_btn: Button = info["custom_btn"]
		custom_btn.tooltip_text = "Post an exact amount (1–%s) — the counter validates" \
			% SignageFmt.num(have)
		if custom_open:
			(info["field"] as LineEdit).placeholder_text = "1–%s" % SignageFmt.num(have)
			_refresh_custom_preview(item_id)


# ------------------------------------------------------------------ quantity presses
## The SELL 1 / SELL 100% presses (qty 0 = the whole stack, the engine's
## own whole-stack form — identical to 100% by construction).
func _on_sell_pressed(item_id: String, qty: int) -> void:
	_execute_sale(item_id, qty)


## A percentage press: compute the honest floor count from the LIVE stack at
## the moment of the press, then tender exactly that through the engine.
func _on_sell_pct_pressed(item_id: String, pct_id: int) -> void:
	var have := state().item_count(item_id)
	var n := _pct_count(have, pct_id)
	if n >= 1:
		_execute_sale(item_id, n)


## Every sale — pct buttons, SELL 1/100%, and the custom field — routes
## through the REAL engine sell path (wallet + O-1 + dossier counters stay
## engine-side) and posts the ledger stamp. A success withdraws any standing
## refusal strip (the T31 clearing rule: the next successful action clears).
func _execute_sale(item_id: String, qty: int) -> Dictionary:
	var item: ItemDef = lib().item(item_id)
	var result: Dictionary = tm.depot_sell(item_id, qty)
	if bool(result["ok"]):
		# T19: tenders post the Crowns mark (currency in), requisitions the
		# item's mark (goods in).
		stamp(log, "TENDERED ×%s — %s (%s CROWNS)" % [
			SignageFmt.num(int(result.get("qty", 0))), item.name.to_upper(),
			SignageFmt.num(int(result.get("crowns", 0)))], icon_texture("crowns"))
		clear_refusal_strip()
	else:
		stamp(log, "REFUSED · %s" % str(result["reason"]).to_upper())
	return result


# ------------------------------------------------------------------ custom amount
## CUSTOM toggles the validated inline field row. Opening parks focus in the
## field (the tab cycle walks in naturally too); the field consumes the digit
## keys while focused, so the department hotkeys never misfire mid-posting.
func _on_custom_toggled(item_id: String) -> void:
	var info: Dictionary = _sell_rows.get(item_id, {})
	if info.is_empty():
		return
	var custom_row: Control = info["custom_row"]
	custom_row.visible = not custom_row.visible
	if custom_row.visible:
		var field: LineEdit = info["field"]
		field.text = ""
		_refresh_custom_preview(item_id)
		field.grab_focus()
	else:
		info["last_have"] = -1  # force the next flush to re-dress the row
		_update_sell_lines()


## Live preview (typing): honest proceeds while the amount validates, the
## honest bounds when it does not. NO refusal strip while typing — the notice
## posts on the posting attempt, not on every keystroke. (Signal args precede
## bind args: text_changed emits new_text, the bound item id follows.)
func _on_custom_text_changed(_new_text: String, item_id: String) -> void:
	_refresh_custom_preview(item_id)


## Enter in the field posts the amount (the TENDER press's twin).
func _on_custom_submitted(_new_text: String, item_id: String) -> void:
	_on_custom_tender_pressed(item_id)


## The posting attempt: an out-of-range or non-numeric amount is REFUSED
## through the T31 strip idiom (the reason in voice at the docket's top —
## never a silent clamp); a valid one tenders exactly that many units.
func _on_custom_tender_pressed(item_id: String) -> void:
	var info: Dictionary = _sell_rows.get(item_id, {})
	if info.is_empty():
		return
	var field: LineEdit = info["field"]
	var check := _validate_custom_text(item_id, field.text)
	if not bool(check["ok"]):
		present_refusal({"reason": String(check["reason"])})
		stamp(log, "REFUSED · %s" % String(check["reason"]).to_upper())
		return
	_execute_sale(item_id, int(check["qty"]))
	field.text = ""
	_refresh_custom_preview(item_id)


func _refresh_custom_preview(item_id: String) -> void:
	var info: Dictionary = _sell_rows.get(item_id, {})
	if info.is_empty() or tm == null or state() == null:
		return
	var item: ItemDef = lib().item(item_id)
	var have := state().item_count(item_id)
	var field: LineEdit = info["field"]
	field.placeholder_text = "1–%s" % SignageFmt.num(have)
	var check := _validate_custom_text(item_id, field.text)
	var preview: Label = info["preview"]
	var tender: Button = info["tender"]
	if bool(check["ok"]):
		var n := int(check["qty"])
		preview.text = "TENDER %s · %s CROWNS" % [
			SignageFmt.num(n), SignageFmt.num(n * item.value)]
		tender.disabled = false
		tender.tooltip_text = "Tender %s units for %s Crowns" % [
			SignageFmt.num(n), SignageFmt.num(n * item.value)]
	else:
		preview.text = String(check["reason"])
		tender.disabled = true
		tender.tooltip_text = "Post a valid amount first (1 up to the stack on hand)"


## The counter's validation: a whole number, 1..held — refusal reasons in the
## counter's own voice, bounds stated honestly.
func _validate_custom_text(item_id: String, text: String) -> Dictionary:
	var have := state().item_count(item_id)
	var t := text.strip_edges()
	if t.is_empty() or not t.is_valid_int():
		return {"ok": false, "reason": "POST A WHOLE NUMBER OF UNITS (1–%s)" % SignageFmt.num(have)}
	var n := int(t)
	if n < 1 or n > have:
		return {"ok": false, "reason": "THE COUNTER TENDERS 1–%s UNITS OF THIS STACK" % SignageFmt.num(have)}
	return {"ok": true, "qty": n}
