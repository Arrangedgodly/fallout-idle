class_name DocketSkill
extends Docket
## DocketSkill — T10a shared skeleton for the four workshop dockets
## (Scavenging, Foraging: DocketGathering; Junksmithing, Cooking:
## DocketProcessing). One skill, one active slot, one enamel gauge, a posted
## list of form lines (tier cards), and a stamped log.
##
## Card states are never color-alone (Daredevil floor): the running card
## carries the Energized variation AND a ">> " prefix on its title; a locked
## card posts a red CLEARANCE plate whose text names the required grade and
## the earning path (refinement 2, critique P2#4: working this department's
## posted shifts is what elevates the gate).
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
var gauge_vent: Control  # T33 deep-link target: the clearance gauge block
var cards_box: VBoxContainer
var log: ItemList
var primary_button: Button  # the shell's BEGIN/END SHIFT plate (shell assigns)
var register: DossierRegister  # T26 the DEPARTMENTAL DOSSIER section

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
	var rate_line: HFlowContainer
	var yields_line: HFlowContainer
	var gate_plate: PanelContainer
	var gate_text: Label

	func rate_text() -> String:
		return Docket.flow_text(rate_line)

	func yields_text() -> String:
		return Docket.flow_text(yields_line)


func _init(p_skill_id: String) -> void:
	skill_id = p_skill_id
	super()  # Docket._init -> _build_content() with skill_id set


const BEGIN_TEXT := "BEGIN SHIFT"
const END_TEXT := "END SHIFT"
const STAMP_CAP := 60


# ------------------------------------------------------------------ build
func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	# T31: the refusal strip posts at the TOP of the docket (child index 0,
	# in-flow — the run-5 amendment: refused clicks answer where the resident
	# is looking, never below the fold).
	add_child(build_refusal_strip())

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
	vent.name = "ClearanceGaugeVent"
	gauge_vent = vent
	var vcol := vbox(8)
	vcol.add_child(micro("CLEARANCE GAUGE · POSTED RATES ARE THE HONEST RATES"))
	gauge = ProgressBar.new()
	gauge.show_percentage = false
	gauge.min_value = 0.0
	gauge.max_value = 100.0
	gauge.value = 0.0
	# T30: the docket XP meters slim to 12 px (the run-5 amendment — the big
	# enamel bars read as decoration at this height; the mono readout below
	# keeps every digit). 20 -> 12 px, ~40% off, no clipping at 200% (the
	# gauge carries no text of its own; the track scales not at all).
	gauge.custom_minimum_size = Vector2(0.0, 12.0)
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

	# T17: the POSTING REFUSED directive plate — posted exactly while the
	# establishment is full (refresh_refusal_plate gates it on engine truth).
	add_child(build_refusal_plate())

	# T26: the DEPARTMENTAL DOSSIER (FORM R-1) — the per-skill objectives
	# register, posted below the working regions (a section of this docket,
	# never a ninth plate; folds to its summary line per the O-1 precedent).
	register = DossierRegister.new(skill_id)
	add_child(register)


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


## T33 reveal target: the first card the resident can actually work (gate
## order — the tier ladder's teaching order). Tier 1 gates at clearance 1,
## so a fresh resident always resolves a card.
func first_unlocked_card() -> Control:
	if tm == null or state() == null:
		return null
	for id in _content_order:
		if tm.engine.is_unlocked(state(), id):
			return (_cards[id] as Card).button
	return null


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

	# T15: rate/yields serials stack below the title row at full card width;
	# T19 renders them as glyph segment flows (stat glyph before its stat's
	# mono number, item icon beside each yield rate) — no autowrap anywhere
	# inside a flow, so nothing side-by-side can starve a wrapped serial.
	card.rate_line = segment_flow(12)
	set_segments(card.rate_line, _rate_segments(def), "PlateSerialNavy")
	col.add_child(card.rate_line)

	card.yields_line = segment_flow(12)
	set_segments(card.yields_line, _yields_segments(def), "PlateSerialNavy")
	col.add_child(card.yields_line)

	# T19: the gate plate carries the clearance staircase glyph beside the
	# required grade (never a padlock — voice rule 3); the wrapped gate text
	# stays the sole EXPAND_FILL child of the row.
	card.gate_plate = panel_box("DangerPlate")
	card.gate_text = label("MonoValue", "")
	card.gate_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.gate_plate.add_child(glyph_beside(GLYPH_CLEARANCE, card.gate_text))
	col.add_child(card.gate_plate)

	b.add_child(col)
	return card


func _card_icon(def: RefCounted) -> String:
	return str(def.get("icon"))


## Rate segments: XP per action (no commissioned glyph — XP is not one of the
## five instrumented stats) and the interval stat, whose stopwatch glyph
## posts inline before its mono number (icon-grammar rule).
func _rate_segments(def: RefCounted) -> Array:
	return [
		{"icon": "", "text": "+%s XP / ACTION" % SignageFmt.num(int(def.get("xp_per_action")))},
		{"icon": GLYPH_INTERVAL, "text": "%s S INTERVAL" % SignageFmt.seconds(int(def.get("interval_ms")))},
	]


## Yield segments (gathering): one segment per drop-table entry, each carrying
## the item's icon beside its exact rate (icon-grammar: item marks are legal
## wherever the item's number posts).
func _yields_segments(def: RefCounted) -> Array:
	var l := lib()
	var table: DropTableDef = l.drop_table(str(def.get("drop_table")))
	if table == null:
		return [{"icon": "", "text": "NO YIELD TABLE POSTED"}]
	var out: Array = [{"icon": "", "text": "YIELDS:"}]
	for entry in table.entries:
		var item: ItemDef = l.item(entry.item)
		var item_name: String = item.name.to_upper() if item != null else entry.item
		out.append({"icon": item.icon if item != null else "",
			"text": "%s %s%% %s" % [item_name,
				SignageFmt.pct(entry.weight, table.total_weight()),
				SignageFmt.qty(entry.qty_min, entry.qty_max)]})
	return out


# ------------------------------------------------------------------ interaction
func _on_card_pressed(content_id: String) -> void:
	select_content(content_id)


## Post a shift: select + start through the engine façade (the engine owns
## every rule; the docket only renders results). EVERY refusal answers in
## three places at once (T31 — the run-5 amendment: feedback the resident
## cannot miss): the notice strip at the docket's top states the REASON in
## voice with truthful attribution (the result's actual kind), the clicked
## card flashes its "× " denial cue at the click point, and the log carries
## the stamp. A successful post clears any standing strip.
func select_content(content_id: String) -> void:
	selected_id = content_id
	var result: Dictionary = tm.start_activity(content_id)
	if bool(result["ok"]):
		stamp(log, _start_stamp_text(content_id), _start_stamp_icon(content_id))
		clear_refusal_strip()
	elif str(result.get("kind", "")) == "posting_refused":
		present_refusal(result)
		_flash_card_denial(content_id)
		stamp(log, "POSTING REFUSED — ALL POSTINGS ASSIGNED. THE NOTICE ABOVE OFFERS REASSIGN.",
			icon_texture(GLYPH_BADGE))
	else:
		present_refusal(result)
		_flash_card_denial(content_id)
		stamp(log, _denied_stamp_text(str(result["reason"])), icon_texture(GLYPH_CLEARANCE))
	_refresh({"activity": true, "inventory": true, "xp": true})


func _start_stamp_text(content_id: String) -> String:
	return "SHIFT POSTED — " + _content_name(content_id).to_upper()


## T19: the posted-shift stamp carries the posting's own mark (activity icon,
## or the output item for recipes — the same resolution the card title uses).
func _start_stamp_icon(content_id: String) -> Texture2D:
	var def: RefCounted = tm.engine.def_of(content_id)
	if def == null:
		return null
	var icon := str(def.get("icon"))
	if icon.is_empty() and def is RecipeDef:
		var r := def as RecipeDef
		var item: ItemDef = lib().item(r.output.item)
		icon = item.icon if item != null else ""
	return icon_texture(icon)


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
	# T26: the register's FIRST read rides the bind (the boot flush's regions
	# predate the gating below; folded registers re-read on stamps only).
	register.refresh(tm)
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
	if changes.has("activity") or changes.has("xp") or changes.has("staffing"):
		_refresh_activity()
	if changes.has("inventory"):
		_stamp_inventory_deltas()
		_refresh_inventory_dependent()
	refresh_refusal_plate()
	refresh_refusal_strip()
	# T26: the dossier register re-reads engine truth when its rows can have
	# moved — ALWAYS on a stamp (the objectives region: summary + dimming),
	# and while EXPANDED on the live-counter regions (the row readouts read
	# live while the resident reads them). A FOLDED register shows only
	# N/23 STAMPED, which no gather/craft flush can change — the 4 Hz façade
	# call is skipped (the perf-idle discipline; guarded restyle regardless).
	if changes.has("objectives") or (register.is_expanded()
			and (changes.has("inventory") or changes.has("xp"))):
		register.refresh(tm)


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
	var deny_live: bool = bool(_deny_active.get(card.id, false))
	if energized:
		card.button.theme_type_variation = "Energized"
		card.title.theme_type_variation = "FormTitleEnergized"
		card.title.text = ">> " + display_name
		set_flow_variation(card.rate_line, "MonoValueEnergized")
		set_flow_variation(card.yields_line, "MonoValueEnergized")
	else:
		card.button.theme_type_variation = ""
		card.title.theme_type_variation = "FormTitle"
		card.title.text = display_name
		set_flow_variation(card.rate_line, "PlateSerialNavy")
		set_flow_variation(card.yields_line, "PlateSerialNavy")
	if deny_live:
		# T31: a live denial flash owns the title (the click point is
		# answering); the canonical re-write happens at the flash's revert.
		card.title.theme_type_variation = "FormTitleDanger"
		card.title.text = "× " + display_name.to_upper()
	card.gate_text.text = _gate_text(card.id)
	card.gate_plate.visible = locked


# ------------------------------------------------------- T31 denial flash
## The clicked card answers AT the click point: its title carries a "× "
## prefix in red ink (FormTitleDanger — the registered red-on-bone pair; the
## prefix is the non-color cue) for one bounded flash, then the card reverts
## to its canonical state. Token-guarded: a second refusal restarts one
## flash, never stacks. While the flash is live, _apply_card_state leaves the
## title alone (a 4 Hz flush must not cut the answer short).
const DENIAL_FLASH_S := 0.45

var _deny_active := {}  # content_id -> true while the flash is live


func _flash_card_denial(content_id: String) -> void:
	var card: Card = _cards.get(content_id)
	if card == null or not card.button.is_inside_tree():
		return
	_deny_active[content_id] = true
	card.title.theme_type_variation = "FormTitleDanger"
	card.title.text = "× " + _content_name(content_id).to_upper()
	var token := _deny_token(content_id) + 1
	card.button.set_meta("deny_token", token)
	get_tree().create_timer(DENIAL_FLASH_S).timeout.connect(func() -> void:
		if not is_inside_tree():
			_deny_active.erase(content_id)
			return
		if int(card.button.get_meta("deny_token", -1)) != token:
			return  # superseded by a newer flash
		_deny_active.erase(content_id)
		var slot = state().active.get(skill_id) if state() != null else null
		var running := slot != null and String(slot.get("content_id")) == content_id
		_apply_card_state(card, running, not tm.engine.is_unlocked(state(), content_id)))


func _deny_token(content_id: String) -> int:
	return int(_cards[content_id].button.get_meta("deny_token", -1)) if _cards.has(content_id) else -1


func _gate_text(content_id: String) -> String:
	# On a skill's own docket the gating skill is self-evident — the plate
	# names only the grade (the Depot, where gates span skills, names both).
	# Refinement 2 (critique P2#4): the plate also teaches the earning path —
	# the gate is the level of THIS docket's skill, and working its posted
	# shifts is what grants the XP that elevates it. Plate idiom, no tooltip.
	var gate: Dictionary = tm.engine.gate_of(content_id)
	return "CLEARANCE %d REQUIRED · EARNED BY WORKING THIS DEPARTMENT'S POSTED SHIFTS" % int(gate["level"])


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
			stamp(log, _delta_stamp_text(item_id, now_qty - was_qty), item_icon_texture(item_id))
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
	# T19: the clearance fanfare carries the staircase glyph beside the grade.
	stamp(log, "CLEARANCE %02d EARNED · %s" % [
		new_level, String(lib().skill(skill_id).name).to_upper()],
		icon_texture(GLYPH_CLEARANCE))


# ------------------------------------------------------------- T26 dossier notices
## One objective of THIS department stamped: the auto-grant notice rides the
## existing stamp idiom — a docket log stamp in the naming-bible verbatim
## format (the console flash is the concourse's hook). No claim button ever.
func _on_objective_stamped(payload: Dictionary) -> void:
	if str(payload.get("skill", "")) != skill_id:
		return
	if log != null:
		stamp(log, str(payload.get("notice_line", "")), icon_texture(GLYPH_STAMP))
	register.refresh(tm)


## The dossier's full stamp: the register posts the ALL N STAMPED · FORM R-1
## plate (expanded, so the win moment is on the wall) and the log carries
## the line once.
func _on_dossier_completed(payload: Dictionary) -> void:
	if str(payload.get("skill", "")) != skill_id:
		return
	register.expand()
	register.refresh(tm)
	if log != null:
		stamp(log, str(payload.get("stamp_line", "")), icon_texture(GLYPH_STAMP))


## T31: a successful REASSIGN through the strip — the log carries the fact
## (the strip carries the confirmation).
func _on_reassign_success(result: Dictionary) -> void:
	if log == null:
		return
	stamp(log, _start_stamp_text(_strip_content_id), _start_stamp_icon(_strip_content_id))
	var ceased: Dictionary = result.get("ceased", {})
	if ceased.is_empty():
		return
	var ceased_id := str(ceased.get("content_id", ""))
	var ceased_name: String = _content_name(ceased_id).to_upper() if not ceased_id.is_empty() \
		else "WASTELAND PATROL"
	stamp(log, "ROOM MADE — %s CEASED BY REASSIGNMENT." % ceased_name,
		icon_texture(GLYPH_BADGE))


func _on_activity_stopped(skill: String, _content_id: String, reason: String) -> void:
	if skill != skill_id:
		return
	match reason:
		"inputs_exhausted":
			stamp(log, "SUPPLIES EXHAUSTED · SHIFT ENDED. REQUISITION MORE.")
		"content_missing":
			stamp(log, "POSTING WITHDRAWN BY THE DEPARTMENT.")
		ActivityEngine.STOP_REASSIGNED:
			stamp(log, "POSTING CEASED BY REASSIGNMENT — ROOM MADE FOR ANOTHER DEPARTMENT.",
				icon_texture(GLYPH_BADGE))
	super._on_activity_stopped(skill, _content_id, reason)
