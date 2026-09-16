class_name DocketPersonnel
extends Docket
## DocketPersonnel — T17 the staffing office: the POSTING BOARD.
##
## One row per posting in the establishment (1 + staffing.deputies, five at
## full strength): ASSIGNED rows carry the filled deputy badge + the skill on
## post (icon + name + rate, Energized — the running idiom), AVAILABLE rows
## carry the OUTLINE badge sibling (icon-grammar state pair: the fill IS the
## state, never color alone). The purchase line posts DEPUTIZE RESIDENT · N
## CROWNS (naming-bible §10 label, verbatim) with the btn_deputize verb glyph
## and the price in content data (data/staffing.json — never hardcoded);
## buying without funds refuses with the Depot's in-voice tender wording.
## Postings suspended by a v1 migration park in staffing.suspended and post
## a standing shortage notice until re-posted (never silently dropped).
##
## Update discipline: same contract as every docket — rows rebuild only on a
## signature change (the T14/T19 no-churn rule: refreshes run on every 4 Hz
## flush and must not touch controls for static content), labels re-text only
## through guarded setters, everything else re-reads tm.state on signal.

const BOARD_HEADER := "POSTING BOARD · ONE POSTING PER CONCURRENT SHIFT · THE PATROL COUNTS"
const LOG_SERIAL := "STAFFING LOG · ACTIONS POSTED BY THE PERSONNEL DESK"
const WALLET_SERIAL := "CROWNS ON HAND · TENDERS EXACT · NO CREDIT"
const DEPUTIZE_LABEL := "DEPUTIZE RESIDENT · %s CROWNS"
const CAP_LABEL := "ESTABLISHMENT AT FULL STRENGTH"
const SUSPENDED_HEAD := "POSTINGS SUSPENDED — PERSONNEL SHORTAGE"
const GLYPH_DEPUTIZE := "btn_deputize"  # T19 verb-echo mark (icon + label together)

var primary_button: Button  # the shell's big stencled plate (shell assigns)
var crowns_read: Label
var summary_line: Label
var board_box: VBoxContainer
var purchase_plate: PanelContainer
var purchase_flow: HFlowContainer
var deputize_button: Button
var cap_line: Label
var shortage_plate: PanelContainer
var shortage_serial: Label
var log: ItemList

var _board_sig := ""
var _purchase_sig := ""


# ------------------------------------------------------------------ build
func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	# The wallet plate — the Depot's energized idiom (crowns mark + mono read).
	var wallet := panel_box("EnergizedPlate")
	wallet.name = "PersonnelWallet"
	var wrow := hbox(12)
	wrow.add_child(icon_rect("crowns", 34))
	var wcol := vbox(2)
	# T15 discipline: the column EXPANDS to the plate's full width — without
	# the flag the HBox sizes it to the "0" read's minimum (~16 px) and the
	# wrapped serial starves (the Depot's own fix round, copied faithfully).
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wallet_serial := label("PlateBodyEnergized", WALLET_SERIAL)
	wallet_serial.name = "WalletSerial"
	wallet_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(wallet_serial)
	crowns_read = label("MonoBig", "0")
	crowns_read.name = "CrownsRead"
	wcol.add_child(crowns_read)
	wrow.add_child(wcol)
	wallet.add_child(wrow)
	add_child(wallet)

	add_child(micro(BOARD_HEADER))
	summary_line = label("MonoValue", "")
	summary_line.name = "SummaryLine"
	summary_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary_line)

	board_box = vbox(8)
	board_box.name = "PostingRows"
	add_child(board_box)

	# The purchase line: price segments (crowns mark beside the number, T19
	# idiom) + the DEPUTIZE RESIDENT button (btn_deputize verb glyph + the
	# naming-bible label, verbatim). Hidden at the full establishment.
	purchase_plate = panel_box("PaperNotice")
	purchase_plate.name = "DeputizeLine"
	var pcol := vbox(8)
	purchase_flow = segment_flow(12)
	pcol.add_child(purchase_flow)
	deputize_button = Button.new()
	deputize_button.name = "DeputizeResident"
	deputize_button.theme_type_variation = "Energized"
	deputize_button.icon = icon_texture(GLYPH_DEPUTIZE)
	deputize_button.custom_minimum_size = Vector2(320.0, 56.0)
	deputize_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	deputize_button.expand_icon = true
	deputize_button.tooltip_text = "Deputize another resident — one more concurrent posting opens on purchase"
	deputize_button.pressed.connect(_on_deputize_pressed)
	pcol.add_child(deputize_button)
	purchase_plate.add_child(pcol)
	add_child(purchase_plate)

	cap_line = label("PlateSerial", "FULL ESTABLISHMENT · FIVE POSTINGS · THE BOARD IS COMPLETE.")
	cap_line.name = "CapLine"
	cap_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap_line.visible = false
	add_child(cap_line)

	# Standing shortage notice: postings parked by the v1 migration, kept
	# until the player re-posts them (state never silently dropped).
	shortage_plate = panel_box("DangerPlate")
	shortage_plate.name = "ShortagePlate"
	shortage_plate.visible = false
	var scol := vbox(4)
	var head_row := hbox(10)
	head_row.add_child(icon_rect(GLYPH_BADGE_OUTLINE, GLYPH_READ))
	var head := label("MonoValue", SUSPENDED_HEAD)
	head.name = "ShortageHead"
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(head)
	scol.add_child(head_row)
	shortage_serial = label("BodyCopy", "")
	shortage_serial.name = "ShortageSerial"
	shortage_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scol.add_child(shortage_serial)
	shortage_plate.add_child(scol)
	add_child(shortage_plate)

	log = build_log(LOG_SERIAL, 5)


# ------------------------------------------------------------------ interaction
func _on_deputize_pressed() -> void:
	if tm == null or state() == null:
		return
	var result: Dictionary = tm.deputize_resident()
	if bool(result["ok"]):
		stamp(log, "RESIDENT DEPUTIZED — POSTING %d OPEN · WELCOME ABOARD." % int(result["posting_opened"]),
			icon_texture(GLYPH_BADGE))
	elif str(result["reason"]).begins_with("INSUFFICIENT CROWNS"):
		stamp(log, "%s · THE ESTABLISHMENT ACCEPTS TENDERS EXACT. NO CREDIT." % str(result["reason"]),
			icon_texture("crowns"))
	else:
		stamp(log, str(result["reason"]).to_upper() + ".", icon_texture(GLYPH_BADGE))
	_refresh({"staffing": true, "inventory": true})


## The shell's big stencled plate IS the department's primary action here:
## DEPUTIZE RESIDENT · N CROWNS while a rung is purchasable, a standing
## completion line at the full establishment.
func primary_action() -> void:
	if tm == null or state() == null:
		return
	if tm.next_deputy_price() > 0:
		_on_deputize_pressed()
	else:
		stamp(log, "FULL ESTABLISHMENT · ALL FIVE POSTINGS STAFFED. THE BOARD IS COMPLETE.",
			icon_texture(GLYPH_BADGE))


# ------------------------------------------------------------------ refresh
func _refresh(changes: Dictionary) -> void:
	if tm == null or state() == null:
		return
	# The board reads every region: postings change through "activity",
	# "combat", "staffing" AND the wallet through "inventory" — the internals
	# are signature-gated, so a superfluous pass costs nothing.
	_refresh_board()


func _on_bound() -> void:
	_board_sig = ""  # force one rebuild against the newly bound twin
	_purchase_sig = ""


## One board pass: summary serial, posting rows (signature-gated rebuild —
## refreshes ride every 4 Hz flush and must not churn controls), purchase
## line, shortage notice, and the shell's primary plate. Every line re-reads
## the engine; the docket owns no staffing truth of its own.
func _refresh_board() -> void:
	var slots: int = tm.posting_slots()
	var occupied: int = tm.occupied_postings()
	_set_label(summary_line, "ESTABLISHMENT · %d POSTINGS · %d ASSIGNED · %d AVAILABLE" % [
		slots, occupied, maxi(slots - occupied, 0)])
	_set_label(crowns_read, SignageFmt.num(state().crowns))

	# -- posting rows (rebuild only when the assignment signature changes) --
	var rows: Array = []
	var fighting := str(state().combat.get("phase", "idle")) == "fighting"
	for skill_id: String in lib().skills:
		var skill: SkillDef = lib().skills[skill_id]
		if skill.is_combat():
			if fighting:
				var mdef: MonsterDef = lib().monster(str(state().combat.get("monster_id", "")))
				rows.append({"kind": "combat", "skill_id": skill_id,
					"name": String(skill.name).to_upper(),
					"detail": (String(mdef.name).to_upper() if mdef != null else "") + " · PATROL ENGAGED"})
			continue
		if state().active.has(skill_id):
			var slot: PlayerState.ActiveSlot = state().active[skill_id]
			var def: RefCounted = tm.engine.def_of(slot.content_id)
			rows.append({"kind": "skill", "skill_id": skill_id,
				"name": String(skill.name).to_upper(),
				"detail": (String(def.get("name")).to_upper() if def != null else slot.content_id.to_upper())
					+ " · ONE ACTION EVERY %s S" % SignageFmt.seconds(slot.interval_ms)})
	while rows.size() < slots:
		rows.append({"kind": "available"})
	var sig := str(slots) + "|" + str(fighting)
	for r in rows:
		sig += str(r.get("kind", "")) + str(r.get("skill_id", "")) + str(r.get("detail", "")) + "||"
	if sig != _board_sig:
		_board_sig = sig
		_rebuild_rows(rows)

	# -- purchase line (hidden at the full establishment) --
	var price: int = tm.next_deputy_price()
	var purchasable := price > 0
	var purchase_sig := "%d|%s" % [price, SignageFmt.num(state().crowns)]
	if purchase_sig != _purchase_sig:
		_purchase_sig = purchase_sig
		if purchasable:
			set_segments(purchase_flow, [
				{"icon": "", "text": "NEXT DEPUTY ·"},
				{"icon": "crowns", "text": "%s CROWNS" % SignageFmt.num(price)},
				{"icon": "", "text": "· POSTING %d OPENS ON PURCHASE" % (tm.posting_slots() + 1)},
			], "MonoValue")
			_set_button_text(deputize_button, DEPUTIZE_LABEL % SignageFmt.num(price))
			if primary_button != null:
				_set_button_text(primary_button, DEPUTIZE_LABEL % SignageFmt.num(price))
				primary_button.icon = icon_texture(GLYPH_DEPUTIZE)
		else:
			set_segments(purchase_flow, [], "MonoValue")
			_set_button_text(deputize_button, CAP_LABEL)
			if primary_button != null:
				_set_button_text(primary_button, CAP_LABEL)
	purchase_plate.visible = purchasable
	cap_line.visible = not purchasable

	# -- suspended postings (v1-migration parking) --
	var suspended: Dictionary = tm.suspended_postings()
	shortage_plate.visible = not suspended.is_empty()
	if not suspended.is_empty():
		var names: Array[String] = []
		for skill_id in suspended:
			var skill: SkillDef = lib().skill(String(skill_id))
			names.append(String(skill.name).to_upper() if skill != null else String(skill_id).to_upper())
		_set_label(shortage_serial, "PARKED AT MIGRATION: %s. RE-POST FROM ITS DEPARTMENT WHEN A POSTING FREES, OR DEPUTIZE ANOTHER RESIDENT. NOTHING HAS BEEN LOST." % " · ".join(PackedStringArray(names)))


func _rebuild_rows(rows: Array) -> void:
	for child in board_box.get_children():
		board_box.remove_child(child)
		child.queue_free()
	for i in rows.size():
		var r: Dictionary = rows[i]
		board_box.add_child(_make_row(i + 1, r))


## One posting row. ASSIGNED = filled badge + skill mark + Energized ground
## (the running idiom); AVAILABLE = outline badge + bone enamel (the state
## pair is the FILL, never color alone — icon-grammar addendum).
func _make_row(posting_no: int, r: Dictionary) -> Control:
	var assigned := str(r.get("kind", "")) != "available"
	var plate := panel_box("EnergizedPlate" if assigned else "EnamelPlate")
	plate.name = "Posting%d" % posting_no
	var row := hbox(12)
	if assigned:
		row.add_child(icon_rect(GLYPH_BADGE, 26))
		var skill: SkillDef = lib().skill(String(r.get("skill_id", "")))
		row.add_child(icon_rect(skill.icon if skill != null else GLYPH_BADGE, 30))
	else:
		row.add_child(icon_rect(GLYPH_BADGE_OUTLINE, 26))
	var col := vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ASSIGNED rides the Energized pair; AVAILABLE posts navy FormTitle ink on
	# the bone enamel platelet (MonoValue is bone ink for steel/vent grounds —
	# bone on bone fails contrast).
	var head := label("MonoValueEnergized" if assigned else "FormTitle",
		"POSTING %d · %s" % [posting_no, "ASSIGNED" if assigned else "AVAILABLE"])
	head.name = "PostingHead%d" % posting_no
	col.add_child(head)
	var serial_text := ""
	if assigned:
		serial_text = "%s — %s" % [str(r.get("name", "")), str(r.get("detail", ""))]
	elif posting_no == 1:
		serial_text = "YOUR OWN TWO HANDS · POST FROM ANY DEPARTMENT"
	else:
		serial_text = "DEPUTY DESK VACANT · POST FROM ANY DEPARTMENT"
	var serial := label("PlateBodyEnergized" if assigned else "PlateSerialNavy", serial_text)
	serial.name = "PostingSerial%d" % posting_no
	serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	serial.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(serial)
	row.add_child(col)
	plate.add_child(row)
	plate.tooltip_text = "Posting %d — %s" % [posting_no,
		("assigned: " + str(r.get("name", "")) + " on post") if assigned else "available for any department"]
	return plate


# ------------------------------------------------------------------ churn guards
## Text setters that no-op on unchanged content (the T14/T19 idle-budget
## discipline: a 4 Hz flush must not even re-layout a static label).
func _set_label(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text


func _set_button_text(b: Button, text: String) -> void:
	if b.text != text:
		b.text = text
