class_name DocketPatrol
extends Docket
## DocketPatrol — T10b Wasteland Patrol docket: the live battle board for
## The Sunny Exclusion Zone. Everything renders from the T7 engine through
## the T6 signal contract: engage/withdraw route through the TickManager
## façade (engage_monster / stop_combat), the HP gauges, phase plate, fauna
## cards, loadout stats and ration queue re-read state.combat / state on
## batched flushes, and the discrete combat_ended / zone_cleared / level_up
## signals stamp their lines immediately (combat events may be immediate per
## the TickManager contract). NOTHING updates per frame.
##
## Honest math: every fauna card posts the engine's exact stats (HP, accuracy,
## evasion, hit bounds, interval, XP) and its drop table's exact fractions;
## the loadout panel posts derived chassis stats straight from
## CombatSession.derived_stats(); the ration queue posts the auto-eat rule
## (one unit of the highest-heal food at or below half condition) in the
## engine's deterministic best-first order with live counts.
##
## Phase states are never color-alone (Daredevil floor): each phase renders a
## plate with distinct wording — FIGHTING (energized ">> PATROL ENGAGED"),
## DEAD ("DECEASED — RETURN TO SHELTER" + zero-loss line + recovery
## directive — refinement 2, critique P1#2: the genre's most vulnerable
## moment posts the next step: re-engagement is immediate, the designation is
## kept, and a fresh engagement restores full condition per balance-notes
## §1.4 addendum 1), VICTORY (enamel plate + claim stamps), RECALLED
## ("PATROL RECALLED" — withdrawn alive, zero loss), plus the persistent
## ZONE SECURED certificate once the boss falls (state.combat.zone_clear
## survives save/load).
## (state.combat.zone_clear survives save/load).
##
## Swing attribution without per-swing signals: the engine marks "combat" per
## resolved attack but emits none per swing, so the docket diffs
## (p_next_ms / m_next_ms / HP / eaten_total / food counts) between batched
## flushes — swings from pending-time advances, damage from HP deltas with
## heal accounting, misses from swings that drew no blood, meals from ration
## count decreases. Phase, engage or EQUIPMENT changes reset the snapshot
## instead of diffing (their own lines arrive from the immediate signals /
## engage path) — a mid-window weapon swap invalidates the swing arithmetic
## (pendings ÷ current speed) and the HP baseline (armor moves max_hp), so
## that one window stays silent rather than stamping a wrong ×N count
## (T10b verifier corner, fixed at T13).
##
## Two display seams, one retired (refinement 3, critique P3#5): (1) ACCEPTED
## (T13, bounded) — heal accounting adds each meal's FULL heal value, but a
## ration eaten at the max-condition cap restores less — a clamped meal in the
## same window as fauna damage can overstate that window's resident DAMAGE
## line by the clamped-off remainder (bounded by heal − max_hp/2: ≤ 5 HP at
## max gear, ≤ 20 HP at mid gear); the RESIDENT gauge beside it is exact.
## (2) RETIRED (R3 supersedes the T13 accepted corner): a hit that rolls 0
## damage (Litterbug-class fauna, min_hit 0) used to render MISS — the state
## diff could not separate it from a true miss. The engine now keeps
## per-engagement hit counters (combat.p_hits / m_hits, incremented at the
## connect, before the damage roll), and a bloodless window words itself by
## its truth: every swing whiffed reads MISS, a swing that CONNECTED and drew
## no blood reads NO DAMAGE.

const ENGAGE_TEXT := "ENGAGE PATROL"
const WITHDRAW_TEXT := "WITHDRAW PATROL"
const STAMP_CAP := 160
const ZONE_NAME := "THE SUNNY EXCLUSION ZONE"
const GLYPH_ENGAGE := "btn_engage"      # T19 verb-echo marks (icon + label
const GLYPH_WITHDRAW := "btn_withdraw"  # together — never wordless buttons)


func stats_text() -> String:
	return flow_text(stats_line)


func weapon_serial_text() -> String:
	return flow_text(weapon_serial)


func armor_serial_text() -> String:
	return flow_text(armor_serial)

var primary_button: Button  # the shell's big stencled plate (shell assigns)

var zone_plate: PanelContainer
var phase_plate: PanelContainer
var phase_line: Label
var phase_serial: Label
var phase_directive: Label
var p_gauge: ProgressBar
var p_read: Label
var m_gauge: ProgressBar
var m_read: Label
var ration_read: Label
var gauge: ProgressBar
var gauge_read: Label
var cards_box: VBoxContainer
var log: ItemList
var weapon_name: Label
var weapon_serial: HFlowContainer
var armor_name: Label
var armor_serial: HFlowContainer
var stats_line: HFlowContainer
var food_rule: Label
var food_box: VBoxContainer

var _cards := {}  # monster_id -> FaunaCard
var _content_order: Array[String] = []
var _food_lines: Array[HFlowContainer] = []
var _snap := {}  # last-flush combat snapshot (swing/eat attribution)


class FaunaCard:
	extends RefCounted
	var id := ""
	var button: Button
	var title: Label
	var tag_line: Label
	var stats_line: HFlowContainer
	var drops_line: HFlowContainer
	var gate_plate: PanelContainer
	var gate_text: Label
	# T24 perf guard (the T19 no-change-signature precedent): _refresh_cards
	# re-applies every card's state on every combat event (kills, level-ups,
	# inventory flushes at 4 Hz); with the run-3 fauna count the redundant
	# text/tooltip writes re-shaped text every pass and pushed the worst
	# frame past the T13 hard ceiling. The signature below records what was
	# last APPLIED; identical state writes nothing (behavior-identical —
	# same renders, same focus/a11y surface, zero redundant layout).
	var _applied := {}

	func stats_text() -> String:
		return Docket.flow_text(stats_line)

	func drops_text() -> String:
		return Docket.flow_text(drops_line)


# ------------------------------------------------------------------ build
func _build_content() -> void:
	add_theme_constant_override("separation", 14)

	# ZONE SECURED — the win-moment certificate, posted once the boss falls
	# (state.combat.zone_clear; persistent through save/load).
	zone_plate = panel_box("PaperNotice")
	zone_plate.name = "ZoneSecuredPlate"
	zone_plate.visible = false
	var zcol := vbox(6)
	zcol.add_child(label("PaperStamp", "POSTED — SECTOR Z · D.O.C.S. FORM Z-9"))
	zcol.add_child(label("PaperTitle", "ZONE SECURED"))
	var zbody := label("PaperText", "THE SUPERINTENDENT HAS BEEN EVICTED. %s IS HEREBY DECLARED SAFE-ISH. REPEAT PATROLS REMAIN ENCOURAGED. RENT IS NO LONGER COLLECTED." % ZONE_NAME)
	zbody.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zcol.add_child(zbody)
	zone_plate.add_child(zcol)
	add_child(zone_plate)

	# Phase plate — one distinct rendering per combat phase (wording carries
	# the state; the plate color only escorts it). Stacked rows with wrapped
	# serials: the long directive lines must never push the docket wide.
	# Third row: the DECEASED plate's recovery directive (refinement 2) —
	# BodyCopy, the same registered label/plate pair the death serial already
	# uses; hidden in every other phase.
	phase_plate = panel_box("EnergizedPlate")
	phase_plate.name = "PhasePlate"
	phase_plate.visible = false
	var prow := vbox(4)
	phase_line = label("MonoValueEnergized", "")
	prow.add_child(phase_line)
	phase_serial = label("PlateBodyEnergized", "")
	phase_serial.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prow.add_child(phase_serial)
	phase_directive = label("BodyCopy", "")
	phase_directive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_directive.visible = false
	prow.add_child(phase_directive)
	phase_plate.add_child(prow)
	add_child(phase_plate)

	# T17: the POSTING REFUSED directive plate — an ENGAGE with no free
	# posting is refused, never preempted; the directive stands exactly while
	# the establishment is full (refresh_refusal_plate gates on engine truth).
	add_child(build_refusal_plate())

	# The battle board: player + monster HP as enamel gauges with mono reads.
	# T15: the long serial MicroLabels wrap — at 200% font scale they are the
	# vent's widest lines and must never demand horizontal scrolling.
	var vent := panel_box("VentHousing")
	vent.name = "BattleBoard"
	var vcol := vbox(8)
	var board_label := label("MicroLabel", "ENGAGEMENT GAUGES · CONDITION AND HP POSTED BY THE ENGINE ROOM")
	board_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vcol.add_child(board_label)
	p_gauge = _make_gauge()
	vcol.add_child(p_gauge)
	# T19: each gauge read carries the condition stat's glyph beside the
	# condition number (stat glyphs name exactly their own stat).
	p_read = label("MonoValue", "RESIDENT · —")
	p_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vcol.add_child(glyph_beside(GLYPH_CONDITION, p_read))
	m_gauge = _make_gauge()
	vcol.add_child(m_gauge)
	m_read = label("MonoValue", "NO FAUNA ENGAGED")
	m_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vcol.add_child(glyph_beside(GLYPH_CONDITION, m_read))
	ration_read = label("PlateSerial", "RATIONS CONSUMED THIS ENGAGEMENT · 0")
	ration_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vcol.add_child(ration_read)
	vent.add_child(vcol)
	add_child(vent)

	# Wasteland Combat clearance gauge (victory XP rides the shared pipeline).
	var xvent := panel_box("VentHousing")
	xvent.name = "ClearanceGauge"
	var xcol := vbox(8)
	var gauge_label := label("MicroLabel", "WASTELAND COMBAT CLEARANCE · ELEVATION OPENS FAUNA POSTINGS")
	gauge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	xcol.add_child(gauge_label)
	gauge = _make_gauge()
	xcol.add_child(gauge)
	gauge_read = label("MonoValue", "CLEARANCE 01 · 0/0 XP TO NEXT")
	gauge_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	xcol.add_child(gauge_read)
	xvent.add_child(xcol)
	add_child(xvent)

	# The stamped battle log.
	log = build_log("PATROL LOG · STAMPS POSTED BY THE ENGINE ROOM", 7)

	# Fauna posting list (the monster picker).
	add_child(micro("FAUNA POSTINGS · SELECT A DESIGNATION"))
	cards_box = vbox(8)
	add_child(cards_box)

	# Equipment on person + derived patrol stats.
	add_child(micro("EQUIPMENT ON PERSON · DERIVED PATROL STATS"))
	var slots_row := hbox(10)
	slots_row.name = "LoadoutRow"
	add_child(slots_row)
	weapon_name = _slot_plate(slots_row, "WEAPON", "NO SIDEARM FILED")
	armor_name = _slot_plate(slots_row, "ARMOR", "NO PLATING FILED")

	var stats_vent := panel_box("VentHousing")
	stats_vent.name = "StatsHousing"
	var scol := vbox(6)
	# T19: the derived-stats panel — one [stat glyph][mono value] segment per
	# instrumented stat (glyphs name exactly their stat, inline at 18 px).
	stats_line = segment_flow(12)
	scol.add_child(stats_line)
	var gear_note := label("PlateSerial",
		"GEAR IS ISSUED AND RETURNED AT THE MANIFEST (D-07). MID-PATROL SWAPS APPLY ON THE NEXT SWING.")
	gear_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scol.add_child(gear_note)
	stats_vent.add_child(scol)
	add_child(stats_vent)

	# Rations: the auto-eat rule + the best-first queue with live counts.
	# T15: the rule line wraps (mono serial, longest unwrapped line at 200%)
	# and prints as a bone-dim serial — it sits directly on the steel docket
	# ground, where navy ink reads 1.69:1 (bone-dim on steel: 4.78:1, the
	# on-steel serial class).
	add_child(micro("RATIONS · AUTO-EAT · BEST MEND FIRST"))
	food_rule = label("PlateSerial", "ONE RATION IS CONSUMED AT OR BELOW HALF CONDITION.")
	food_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(food_rule)
	food_box = vbox(4)
	add_child(food_box)


func _make_gauge() -> ProgressBar:
	var g := ProgressBar.new()
	g.show_percentage = false
	g.min_value = 0.0
	g.max_value = 1.0
	g.value = 0.0
	g.custom_minimum_size = Vector2(0.0, 20.0)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## One equipment slot plate; returns the name label (serial kept in members).
## T19: the gear serial is a [stat glyph][value] segment flow — each bonus
## number carries its own stat's glyph (icon-grammar gear-line rule).
func _slot_plate(row: BoxContainer, slot_label: String, vacant_serial: String) -> Label:
	var plate := panel_box("EnamelPlate")
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := vbox(4)
	col.add_child(label("PlateSerialNavy", slot_label))
	var name_l := label("FormTitle", "— VACANT —")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_l)
	var serial_flow := segment_flow(12)
	set_segments(serial_flow, [{"icon": "", "text": vacant_serial}], "PlateSerialNavy")
	col.add_child(serial_flow)
	plate.add_child(col)
	row.add_child(plate)
	if slot_label == "WEAPON":
		weapon_serial = serial_flow
	else:
		armor_serial = serial_flow
	return name_l


# ------------------------------------------------------------------ fauna cards
## All zone fauna ascending by clearance gate (the ladder's teaching order).
func _content_defs() -> Array:
	var out: Array = []
	var l := lib()
	if l == null:
		return out
	for id in l.monsters:
		out.append(l.monsters[id])
	out.sort_custom(func(a, b) -> bool:
		return int(a.get("level_gate")) < int(b.get("level_gate")))
	return out


func _build_cards() -> void:
	for def in _content_defs():
		var card := _make_card(def)
		_cards[card.id] = card
		_content_order.append(card.id)
		cards_box.add_child(card.button)


func _make_card(mdef: MonsterDef) -> FaunaCard:
	var card := FaunaCard.new()
	card.id = mdef.id
	# T15: CardButton — the button's minimum size includes its label stack.
	var b := Docket.CardButton.new()
	b.name = "Fauna_" + card.id
	b.pressed.connect(_on_card_pressed.bind(card.id))
	b.tooltip_text = "Designate this fauna for patrol — %s" % mdef.name
	card.button = b

	var col := vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title_row := hbox(10)
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(icon_rect(mdef.icon, 30))
	card.title = label("FormTitle", mdef.name.to_upper())
	card.title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(card.title)
	col.add_child(title_row)

	if mdef.is_boss:
		card.tag_line = label("PlateSerialNavy",
			"SENIOR FAUNA — ESCORT NOT PROVIDED. REFUNDS ARE NOT EITHER.")
	else:
		card.tag_line = label("PlateSerialNavy", "FAUNA CLASS: PEST (LITTERING-ADJACENT)")
	card.tag_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card.tag_line)

	# T19: fauna stats post as [stat glyph][mono value] segments (honest math
	# unchanged — the glyphs name exactly the stats their numbers post; XP is
	# not one of the five instrumented stats and stays bare text).
	card.stats_line = segment_flow(12)
	set_segments(card.stats_line, _stats_segments(mdef), "PlateSerialNavy")
	col.add_child(card.stats_line)

	# T19: claim-table entries carry their item's icon beside the exact rate.
	card.drops_line = segment_flow(12)
	set_segments(card.drops_line, _drops_segments(mdef), "PlateSerialNavy")
	col.add_child(card.drops_line)

	# T19: the gate plate carries the clearance staircase beside the grade.
	card.gate_plate = panel_box("DangerPlate")
	card.gate_text = label("MonoValue", "")
	card.gate_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.gate_plate.add_child(glyph_beside(GLYPH_CLEARANCE, card.gate_text))
	col.add_child(card.gate_plate)

	b.add_child(col)
	return card


## The engine's exact combat math as glyph segments (honest-math principle;
## segment texts join to the same serial the tests pin).
func _stats_segments(mdef: MonsterDef) -> Array:
	return [
		{"icon": GLYPH_CONDITION, "text": "HP %s" % SignageFmt.num(mdef.max_hp)},
		{"icon": GLYPH_ACCURACY, "text": "ACC %d" % mdef.accuracy},
		{"icon": GLYPH_EVADE, "text": "EVA %d" % mdef.evasion},
		{"icon": GLYPH_MAX_HIT, "text": "HIT %d-%d" % [mdef.min_hit, mdef.max_hit]},
		{"icon": GLYPH_INTERVAL, "text": "EVERY %s S" % SignageFmt.seconds(mdef.attack_speed_ms)},
		{"icon": "", "text": "%s XP ON KILL" % SignageFmt.num(mdef.xp_reward)},
	]


func _drops_segments(mdef: MonsterDef) -> Array:
	var l := lib()
	var table: DropTableDef = l.drop_table(mdef.drop_table)
	if table == null:
		return [{"icon": "", "text": "NO CLAIM TABLE POSTED"}]
	var out: Array = [{"icon": "", "text": "CLAIMS:" if table.rolls == 1
		else "CLAIMS: (ROLLED %d TIMES)" % table.rolls}]
	for entry in table.entries:
		var item: ItemDef = l.item(entry.item)
		var item_name: String = item.name.to_upper() if item != null else entry.item
		out.append({"icon": item.icon if item != null else "",
			"text": "%s %s%% %s" % [item_name,
				SignageFmt.pct(entry.weight, table.total_weight()),
				SignageFmt.qty(entry.qty_min, entry.qty_max)]})
	return out


# ------------------------------------------------------------------ bind
## Cap-aware stamp into the battle log (combat logs are chatty — a swing every
## ~2–3 s per side keeps a long fight well past the base cap of 60). The icon
## carries the line's subject at small size (T19): the resident's lines wear
## the condition dial (the same glyph that posts beside the resident gauge),
## the fauna's lines wear its own posting mark, claims and rations wear the
## item's mark, and clearance lines wear the staircase.
func _stamp(text: String, icon: Texture2D = null) -> void:
	stamp(log, text, icon, STAMP_CAP)


func _on_bound() -> void:
	if tm == null or state() == null:
		return
	# The T7 discrete signals, connected idempotently (bind may re-run).
	for pair in [["combat_ended", _on_combat_ended], ["zone_cleared", _on_zone_cleared]]:
		var sig: Signal = tm.get(pair[0])
		if not sig.is_connected(pair[1]):
			sig.connect(pair[1])
	if cards_box.get_child_count() == 0:
		_build_cards()
	_take_snapshot()
	_stamp_resume_lines()


func unbind() -> void:
	if tm != null:
		for pair in [["combat_ended", _on_combat_ended], ["zone_cleared", _on_zone_cleared]]:
			var sig: Signal = tm.get(pair[0])
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
	super.unbind()


## A loaded session resumes mid-state; the log says so once (fresh log only —
## rebinding a twin must not repeat the resume stamps).
func _stamp_resume_lines() -> void:
	if log.item_count > 0:
		return
	var c: Dictionary = state().combat
	var phase := str(c.get("phase", CombatSession.PHASE_IDLE))
	var mdef: MonsterDef = lib().monster(str(c.get("monster_id", "")))
	var mname := mdef.name.to_upper() if mdef != null else ""
	match phase:
		CombatSession.PHASE_FIGHTING:
			_stamp("PATROL RESUMED — ENGAGEMENT IN PROGRESS.")
		CombatSession.PHASE_DEAD:
			_stamp("RETURN TO SHELTER ON RECORD · ZERO LOSS POSTED.",
				icon_texture(GLYPH_CONDITION))
		CombatSession.PHASE_RECALLED:
			_stamp("PATROL RECALLED · WITHDRAWN ALIVE · ZERO LOSS.",
				icon_texture(GLYPH_CONDITION))
		CombatSession.PHASE_VICTORY:
			if mname != "":
				_stamp("VICTORY ON RECORD — %s DECEASED." % mname, icon_texture(mdef.icon))


# ------------------------------------------------------------------ interaction
func _on_card_pressed(monster_id: String) -> void:
	_engage(monster_id)


func _engage(monster_id: String) -> void:
	if tm == null or state() == null:
		return
	var result: Dictionary = tm.engage_monster(monster_id)
	var mdef: MonsterDef = lib().monster(monster_id)
	var mname := mdef.name.to_upper() if mdef != null else monster_id.to_upper()
	if bool(result["ok"]):
		_stamp("PATROL ENGAGED — %s" % mname,
			icon_texture(mdef.icon) if mdef != null else null)
	elif str(result.get("kind", "")) == "posting_refused":
		_stamp("POSTING REFUSED — ALL DEPUTIES ARE ASSIGNED. THE DIRECTIVE IS POSTED BELOW.",
			icon_texture(GLYPH_BADGE))
	else:
		_stamp("%s · ELEVATION IS EARNED, NOT REQUESTED" % str(result["reason"]).to_upper(),
			icon_texture(GLYPH_CLEARANCE))
	_refresh({"combat": true, "inventory": true, "xp": true})


## The shell's big stencled button: ENGAGE PATROL <-> WITHDRAW PATROL.
func primary_action() -> void:
	if tm == null or state() == null:
		return
	var c: Dictionary = state().combat
	if str(c.get("phase", CombatSession.PHASE_IDLE)) == CombatSession.PHASE_FIGHTING:
		tm.stop_combat()
		_stamp("PATROL WITHDRAWN BY RESIDENT.")
		_refresh({"combat": true})
		return
	var target := str(c.get("monster_id", ""))
	if target == "" or not _gate_ok(target):
		target = _first_designatable()
	if target == "":
		_stamp("NO FAUNA POSTED TO YOUR CLEARANCE. ELEVATION OPENS POSTINGS.")
		_refresh({"combat": true})
		return
	_engage(target)


func _gate_ok(monster_id: String) -> bool:
	var mdef: MonsterDef = lib().monster(monster_id)
	return mdef != null and _combat_level() >= mdef.level_gate


func _first_designatable() -> String:
	for id in _content_order:
		if _gate_ok(id):
			return id
	return ""


func _combat_level() -> int:
	return int(state().skills_level.get(_combat_skill_id(), 1))


func _combat_skill_id() -> String:
	var l := lib()
	if l == null:
		return ""
	for skill_id: String in l.skills:
		if (l.skills[skill_id] as SkillDef).is_combat():
			return skill_id
	return ""


# ------------------------------------------------------------------ refresh
func _refresh(changes: Dictionary) -> void:
	if tm == null or state() == null:
		return
	if changes.has("combat") or changes.has("inventory") or changes.has("staffing"):
		_refresh_battle()
	if changes.has("xp"):
		_refresh_gauge()
	if changes.has("inventory"):
		_refresh_food()
	refresh_refusal_plate()


## The battle board: swing/eat attribution stamps, gauges, phase plate, cards,
## loadout, ration counter — one pass, re-reading the engine's state only.
func _refresh_battle() -> void:
	var c: Dictionary = state().combat
	var phase := str(c.get("phase", CombatSession.PHASE_IDLE))
	var monster_id := str(c.get("monster_id", ""))
	var engage_ms := int(c.get("engage_ms", 0))

	# Attribution: diff only while the SAME fight keeps fighting. Any phase,
	# target, engage or EQUIPMENT change resets the baseline (those moments
	# stamp their own lines through the immediate signals / engage path — and a
	# mid-window gear swap breaks the swing-count division and the HP baseline)
	# — except the offline recall, whose only surfacing is this flush. Meals
	# eaten in the window the fight ENDED still count: ration decreases are
	# diffable on every exit from fighting.
	var gear_swapped := str(c.get("weapon", "")) != str(_snap.get("weapon", "")) \
			or str(c.get("armor", "")) != str(_snap.get("armor", ""))
	if phase != str(_snap.get("phase", "")) or monster_id != str(_snap.get("monster_id", "")) \
			or engage_ms != int(_snap.get("engage_ms", -1)) or gear_swapped:
		if str(_snap.get("phase", "")) == CombatSession.PHASE_FIGHTING:
			if phase == CombatSession.PHASE_RECALLED:
				_stamp("PATROL RECALLED · WITHDRAWN ALIVE AT THE LIMIT · ZERO LOSS",
					icon_texture(GLYPH_CONDITION))
			_stamp_meals()
		_take_snapshot()
	elif phase == CombatSession.PHASE_FIGHTING:
		_stamp_fight_deltas()
		_take_snapshot()

	# Gauges (idle shows the posting condition: every engage starts both
	# sides at full — balance-notes §1.4 addendum 1).
	var stats: Dictionary = tm.combat.derived_stats(state())
	var cap := int(stats["max_hp"])
	var mdef: MonsterDef = lib().monster(monster_id) if monster_id != "" else null
	var p_now := int(c.get("p_hp", 0))
	var m_now := 0
	if phase == CombatSession.PHASE_IDLE:
		p_now = cap
		m_now = mdef.max_hp if mdef != null else 0
	else:
		m_now = int(c.get("m_hp", 0))
	p_gauge.max_value = float(maxi(cap, 1))
	p_gauge.value = float(clampi(p_now, 0, cap))
	p_read.text = "RESIDENT · %s/%s CONDITION" % [SignageFmt.num(clampi(p_now, 0, cap)), SignageFmt.num(cap)]
	if mdef == null:
		m_gauge.max_value = 1.0
		m_gauge.value = 0.0
		m_read.text = "NO FAUNA ENGAGED"
	else:
		m_gauge.max_value = float(maxi(mdef.max_hp, 1))
		m_gauge.value = float(clampi(m_now, 0, mdef.max_hp))
		m_read.text = "%s · %s/%s HP" % [mdef.name.to_upper(),
			SignageFmt.num(clampi(m_now, 0, mdef.max_hp)), SignageFmt.num(mdef.max_hp)]
	ration_read.text = "RATIONS CONSUMED THIS ENGAGEMENT · %d" % int(c.get("eaten_total", 0))

	_apply_phase_plate(phase, mdef)
	_refresh_cards(phase, monster_id)
	_refresh_slots(stats)
	zone_plate.visible = bool(c.get("zone_clear", false))
	if primary_button != null:
		var fighting := phase == CombatSession.PHASE_FIGHTING
		primary_button.text = WITHDRAW_TEXT if fighting else ENGAGE_TEXT
		# T19: the verb-echo glyph rides the label (icon + word together).
		primary_button.expand_icon = true
		primary_button.icon = icon_texture(GLYPH_WITHDRAW if fighting else GLYPH_ENGAGE)


func _apply_phase_plate(phase: String, mdef: MonsterDef) -> void:
	var mname := mdef.name.to_upper() if mdef != null else "FAUNA"
	phase_directive.visible = false
	match phase:
		CombatSession.PHASE_FIGHTING:
			phase_plate.theme_type_variation = "EnergizedPlate"
			phase_line.theme_type_variation = "MonoValueEnergized"
			phase_serial.theme_type_variation = "PlateBodyEnergized"
			phase_line.text = ">> PATROL ENGAGED — %s" % mname
			phase_serial.text = "FIRST SWING LANDS ONE FULL INTERVAL OUT · RATIONS AUTO-CONSUMED AT HALF CONDITION"
			phase_plate.visible = true
		CombatSession.PHASE_DEAD:
			phase_plate.theme_type_variation = "DangerPlate"
			phase_line.theme_type_variation = "MonoValue"
			phase_serial.theme_type_variation = "BodyCopy"
			phase_line.text = "DECEASED — RETURN TO SHELTER"
			phase_serial.text = "NOTHING WAS LOST · THE ZONE THANKS YOU FOR YOUR CONTRIBUTIONS (PARTIAL)"
			# Recovery directive (refinement 2, critique P1#2): every clause is
			# engine fact — engage() is callable immediately (no cooldown, no
			# penalty), the designation persists in state.combat.monster_id, and
			# every engage resets condition to full (balance-notes §1.4 addendum
			# 1). Naming-bible §8: directive voice, calm ALL-CAPS, no promises.
			phase_directive.visible = true
			phase_directive.text = "RE-ENGAGE WHEN READY · YOUR DESIGNATION IS PRESERVED · THE NEXT ENGAGEMENT BEGINS AT FULL CONDITION"
			phase_plate.visible = true
		CombatSession.PHASE_VICTORY:
			phase_plate.theme_type_variation = "EnamelPlate"
			phase_line.theme_type_variation = "FormTitle"
			phase_serial.theme_type_variation = "PlateSerialNavy"
			phase_line.text = "VICTORY POSTED — %s DECEASED" % mname
			phase_serial.text = "CLAIMS FILED TO THE MANIFEST · CLEARANCE GAUGE UPDATED"
			phase_plate.visible = true
		CombatSession.PHASE_RECALLED:
			phase_plate.theme_type_variation = "DangerPlate"
			phase_line.theme_type_variation = "MonoValue"
			phase_serial.theme_type_variation = "BodyCopy"
			phase_line.text = "PATROL RECALLED — RETURN TO SHELTER"
			phase_serial.text = "WITHDRAWN ALIVE AT THE SURVIVABILITY LIMIT · ZERO LOSS · THE MAIL ROOM HAS BEEN NOTIFIED"
			phase_plate.visible = true
		_:
			phase_plate.visible = false


func _refresh_cards(phase: String, monster_id: String) -> void:
	var level := _combat_level()
	var fighting := phase == CombatSession.PHASE_FIGHTING
	for id in _content_order:
		var card: FaunaCard = _cards[id]
		var mdef: MonsterDef = lib().monster(id)
		# The designated target stays energized (state.combat.monster_id
		# persists as the designation; engaging a card sets it).
		var energized := id == monster_id
		var locked := mdef != null and level < mdef.level_gate
		_apply_card_state(card, mdef, energized, locked)
		if mdef != null:
			var tooltip := "Designate this fauna for patrol — %s%s" % [
				mdef.name, " (engaged)" if energized and fighting else ""]
			if str(card._applied.get("tooltip", "")) != tooltip:
				card.button.tooltip_text = tooltip
				card._applied["tooltip"] = tooltip


func _apply_card_state(card: FaunaCard, mdef: MonsterDef, energized: bool, locked: bool) -> void:
	var display := mdef.name.to_upper() if mdef != null else card.id.to_upper()
	var gate_line := "CLEARANCE %d REQUIRED · EARNED BY PATROLLING THIS ZONE" % (
		mdef.level_gate if mdef != null else 0)
	# T24 perf guard: identical state writes nothing (see FaunaCard._applied).
	if str(card._applied.get("display", "")) == display \
			and str(card._applied.get("gate", "")) == gate_line \
			and bool(card._applied.get("energized", false)) == energized \
			and bool(card._applied.get("locked", false)) == locked:
		return
	card._applied["display"] = display
	card._applied["gate"] = gate_line
	card._applied["energized"] = energized
	card._applied["locked"] = locked
	if energized:
		card.button.theme_type_variation = "Energized"
		card.title.theme_type_variation = "FormTitleEnergized"
		card.title.text = ">> " + display
		card.tag_line.theme_type_variation = "MonoValueEnergized"
		set_flow_variation(card.stats_line, "MonoValueEnergized")
		set_flow_variation(card.drops_line, "MonoValueEnergized")
	else:
		card.button.theme_type_variation = ""
		card.title.theme_type_variation = "FormTitle"
		card.title.text = display
		card.tag_line.theme_type_variation = "PlateSerialNavy"
		set_flow_variation(card.stats_line, "PlateSerialNavy")
		set_flow_variation(card.drops_line, "PlateSerialNavy")
	# Refinement 2 (critique P2#4): the gate plate teaches the earning path —
	# Wasteland Combat clearance rises on kills while patrolling this zone
	# (victory XP rides the shared pipeline). Same plate idiom as the workshop
	# dockets' "EARNED BY WORKING THIS DEPARTMENT'S POSTED SHIFTS".
	card.gate_text.text = gate_line
	card.gate_plate.visible = locked


func _refresh_slots(stats: Dictionary) -> void:
	_fill_slot(weapon_name, weapon_serial, "weapon", "NO SIDEARM FILED")
	_fill_slot(armor_name, armor_serial, "armor", "NO PLATING FILED")
	set_segments(stats_line, [
		{"icon": GLYPH_ACCURACY, "text": "ACCURACY %d" % int(stats["accuracy"])},
		{"icon": GLYPH_EVADE, "text": "EVADE %d" % int(stats["evasion"])},
		{"icon": GLYPH_MAX_HIT, "text": "MAX HIT %d-%d" % [int(stats["min_hit"]), int(stats["max_hit"])]},
		{"icon": GLYPH_INTERVAL, "text": "SWING EVERY %s S" % SignageFmt.seconds(int(stats["speed"]))},
		{"icon": GLYPH_CONDITION, "text": "CONDITION %d" % int(stats["max_hp"])},
	], "MonoValue")


func _fill_slot(name_label: Label, serial_flow: HFlowContainer, slot_key: String, vacant_serial: String) -> void:
	var equipped := str(state().combat.get(slot_key, ""))
	if equipped == "":
		name_label.text = "— VACANT —"
		set_segments(serial_flow, [{"icon": "", "text": vacant_serial}], "PlateSerialNavy")
		return
	var item: ItemDef = lib().item(equipped)
	var eq: EquipmentDef = lib().equipment_for(equipped)
	name_label.text = item.name.to_upper() if item != null else equipped.to_upper()
	set_segments(serial_flow,
		_gear_segments(eq) if eq != null else [{"icon": "", "text": equipped.to_upper()}],
		"PlateSerialNavy")


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


func _refresh_gauge() -> void:
	var skill_id := _combat_skill_id()
	if skill_id == "":
		return
	var skill := lib().skill(skill_id)
	var curve := lib().xp_curve(skill.xp_curve)
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


## The auto-eat queue: owned rations in the engine's exact order (heal desc,
## id asc — CombatSession._best_food) with live counts, plus the threshold
## rule computed from the live derived max condition.
func _refresh_food() -> void:
	var l := lib()
	if l == null:
		return
	var stats: Dictionary = tm.combat.derived_stats(state())
	food_rule.text = "ONE RATION IS CONSUMED AT OR BELOW %d CONDITION (HALF)." % (int(stats["max_hp"]) / 2)
	var foods: Array = []
	for item_id: String in l.items:
		var def: ItemDef = l.items[item_id]
		if def.is_food() and def.heal > 0 and state().item_count(item_id) > 0:
			foods.append(def)
	foods.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.heal != b.heal:
			return a.heal > b.heal
		return a.id < b.id)
	while _food_lines.size() < foods.size():
		# T19: each ration line carries its food's mark beside the count.
		var line := segment_flow(8)
		_food_lines.append(line)
		food_box.add_child(line)
	for i in _food_lines.size():
		var line: HFlowContainer = _food_lines[i]
		if i >= foods.size():
			line.visible = false
			continue
		var def: ItemDef = foods[i]
		line.visible = true
		set_segments(line, [{"icon": def.icon, "text": "%d. %s ×%s · MENDS %d" % [
			i + 1, def.name.to_upper(),
			SignageFmt.num(state().item_count(def.id)), def.heal]}], "MonoValue")
	if foods.is_empty() and not _food_lines.is_empty():
		_food_lines[0].visible = true
		set_segments(_food_lines[0], [{"icon": "",
			"text": "NO RATIONS FILED · THE PATROL FIGHTS ONWARD, HUNGRILY."}], "MonoValue")


# ------------------------------------------------------------------ attribution
func _take_snapshot() -> void:
	var c: Dictionary = state().combat
	var foods := {}
	for item_id: String in lib().items:
		var def: ItemDef = lib().items[item_id]
		if def.is_food() and def.heal > 0:
			foods[item_id] = state().item_count(item_id)
	_snap = {
		"phase": str(c.get("phase", CombatSession.PHASE_IDLE)),
		"monster_id": str(c.get("monster_id", "")),
		"engage_ms": int(c.get("engage_ms", 0)),
		"weapon": str(c.get("weapon", "")),
		"armor": str(c.get("armor", "")),
		"p_hp": int(c.get("p_hp", 0)),
		"m_hp": int(c.get("m_hp", 0)),
		"p_next_ms": int(c.get("p_next_ms", 0)),
		"m_next_ms": int(c.get("m_next_ms", 0)),
		"eaten_total": int(c.get("eaten_total", 0)),
		"p_hits": int(c.get("p_hits", 0)),
		"m_hits": int(c.get("m_hits", 0)),
		"foods": foods,
	}


## Stamp the swings and meals resolved since the last flush (same fight).
## Player-first presentation mirrors the engine's same-tick ordering rule.
func _stamp_fight_deltas() -> void:
	var c: Dictionary = state().combat
	var mdef: MonsterDef = lib().monster(str(c.get("monster_id", "")))
	if mdef == null:
		return
	var stats: Dictionary = tm.combat.derived_stats(state())
	var mname := mdef.name.to_upper()
	var p_swings := maxi(0, int(c["p_next_ms"]) - int(_snap["p_next_ms"])) / maxi(1, int(stats["speed"]))
	var m_swings := maxi(0, int(c["m_next_ms"]) - int(_snap["m_next_ms"])) / maxi(1, mdef.attack_speed_ms)

	# Heal accounting keeps the resident-damage delta honest (meals are not
	# damage; a Cooking slot banking food mid-fight is not a meal either).
	var heal_total := _heal_since_snapshot()
	var dmg_to_fauna := int(_snap["m_hp"]) - int(c["m_hp"])
	var dmg_to_resident := int(_snap["p_hp"]) + heal_total - int(c["p_hp"])
	# R3 (critique P3#5): the engine's hit counters carry the connect-truth
	# the HP diff cannot — landed deltas separate a whiffed window (MISS) from
	# one where a swing CONNECTED and drew no blood (NO DAMAGE).
	var p_landed := maxi(0, int(c["p_hits"]) - int(_snap["p_hits"]))
	var m_landed := maxi(0, int(c["m_hits"]) - int(_snap["m_hits"]))
	if p_swings > 0:
		var tag := "RESIDENT » %s" % mname
		if p_swings > 1:
			tag += " ×%d SWINGS" % p_swings
		_stamp("%s · %s" % [tag, ("%s DAMAGE" % SignageFmt.num(dmg_to_fauna))
			if dmg_to_fauna > 0 else _bloodless_wording(p_landed)],
			icon_texture(GLYPH_CONDITION))
	if m_swings > 0:
		var mtag := "%s » RESIDENT" % mname
		if m_swings > 1:
			mtag += " ×%d SWINGS" % m_swings
		_stamp("%s · %s" % [mtag, ("%s DAMAGE" % SignageFmt.num(dmg_to_resident))
			if dmg_to_resident > 0 else _bloodless_wording(m_landed)],
			icon_texture(mdef.icon))
	_stamp_meals()


## A window that drew no blood words itself by its truth (R3, critique P3#5):
## nothing connected reads MISS (the honest whiff); something connected and
## failed to draw reads NO DAMAGE (the landed 0-damage hit — Litterbug-class
## min_hit 0). Naming-bible §8: calm ALL-CAPS form outcome, no exclamation.
func _bloodless_wording(landed: int) -> String:
	return "NO DAMAGE" if landed > 0 else "MISS"


## Total HP mended by rations consumed since the snapshot (decreases only).
func _heal_since_snapshot() -> int:
	var heal := 0
	var snap_foods: Dictionary = _snap.get("foods", {})
	for item_id in snap_foods:
		var was := int(snap_foods[item_id])
		var now := state().item_count(str(item_id))
		if now >= was:
			continue
		var def: ItemDef = lib().item(str(item_id))
		if def != null:
			heal += (was - now) * def.heal
	return heal


## Stamp ration-count decreases since the snapshot as consumed meals.
func _stamp_meals() -> void:
	var snap_foods: Dictionary = _snap.get("foods", {})
	for item_id in snap_foods:
		var was := int(snap_foods[item_id])
		var now := state().item_count(str(item_id))
		if now >= was:
			continue
		var def: ItemDef = lib().item(str(item_id))
		if def == null:
			continue
		var n := was - now
		_stamp("RATION CONSUMED · %s ×%d (+%d CONDITION)" % [
			def.name.to_upper(), n, n * def.heal], icon_texture(def.icon))


# ------------------------------------------------------------------ engine events
func _on_combat_ended(result: Dictionary) -> void:
	if log == null:
		return
	var mdef: MonsterDef = lib().monster(str(result["monster_id"]))
	var mname := mdef.name.to_upper() if mdef != null else str(result["monster_id"]).to_upper()
	if str(result["outcome"]) == "victory":
		_stamp("VICTORY — %s DECEASED · +%s XP" % [mname, SignageFmt.num(int(result["xp"]))],
			icon_texture(mdef.icon) if mdef != null else null)
		var drops: Dictionary = result["drops"]
		for item_id in drops:
			var item: ItemDef = lib().item(str(item_id))
			_stamp("CLAIM · %s ×%s" % [
				item.name.to_upper() if item != null else str(item_id).to_upper(),
				SignageFmt.num(int(drops[item_id]))], item_icon_texture(str(item_id)))
	else:
		_stamp("DECEASED — RETURN TO SHELTER · ZERO LOSS POSTED",
			icon_texture(GLYPH_CONDITION))
	_refresh({"combat": true, "inventory": true, "xp": true})


func _on_zone_cleared(_monster_id: String) -> void:
	if log == null:
		return
	_stamp("ZONE SECURED · %s HAS BEEN DECLARED SAFE-ISH." % ZONE_NAME)
	_refresh({"combat": true})


func _on_level_up(skill_id: String, _old_level: int, new_level: int) -> void:
	if skill_id != _combat_skill_id() or log == null:
		return
	_stamp("CLEARANCE %02d EARNED · %s" % [
		new_level, String(lib().skill(skill_id).name).to_upper()],
		icon_texture(GLYPH_CLEARANCE))
	_refresh({"xp": true, "combat": true})


func _on_activity_stopped(skill_id: String, _content_id: String, reason: String) -> void:
	if skill_id == _combat_skill_id() and reason == "patrol_recalled":
		_stamp("PATROL RECALLED · WITHDRAWN ALIVE AT THE LIMIT · ZERO LOSS",
			icon_texture(GLYPH_CONDITION))
		_refresh({"combat": true})
		return
	super._on_activity_stopped(skill_id, _content_id, reason)
