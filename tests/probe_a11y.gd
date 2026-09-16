extends SceneTree
## tests/probe_a11y.gd — T15 accessibility audit probe (plain --script, like
## tests/probe_concourse.gd).
##
## Run (assertions only, headless):
##   "$GODOT" --headless --path . -s res://tests/probe_a11y.gd
## Run with captures (needs a real renderer; windowed per the T8 fallback):
##   "$GODOT" --path . -s res://tests/probe_a11y.gd -- capture
##
## Proves the T15 acceptance criteria that need a runtime pass:
##   1. CONTRAST RE-AUDIT OF THE FINAL SCREENS (not just tokens): walk every
##      visible text-bearing control on every department (in locked/running/
##      fighting/poor-wallet states), the header, the console, the bulkhead
##      shutter, the MAIL CALL modal and the save-notice board — resolving
##      each label's ACTUAL rendered ink + ground (theme colors + widget
##      styleboxes, including hover/pressed/disabled button states) and
##      recomputing WCAG ratios via SignageTokens (body >= 4.5:1, large
##      >= 3:1, large = >=24px regular / >=19px true-bold). The amber-on-
##      rolled-steel class is asserted LARGE-ONLY (the registered 3:1 class);
##      the energized hover pair (amber on navy) is pinned >= 4.5.
##   2. FONT SCALE 200% ACROSS ALL SCREENS: at 200% the shell column fits
##      1280 (nothing clipped off-window), every docket fits its column
##      without horizontal growth past the bulkhead, every focusable is
##      reachable in one tab chain AND scrolled into view when focused
##      (keyboard-scrollable bulkhead regions), the console CLOCK OUT stays
##      on screen, and the MAIL CALL modal stays trapped + acknowledged.
##   3. MOTION: the two authored durations are bounded constants, a real
##      keyboard-driven bulkhead slide completes well under a second, and no
##      UI source loops a tween (no >3 Hz flashing of any kind).
##   4. COLLAPSE GUARD (T15 fix round): every visible Label, on every
##      department at BOTH 100% and 200%, renders at least as wide as its
##      longest word — the autowrap-in-an-HBox collapse class (1 px vertical
##      character columns) can never pass silently again.
##   5. (capture mode) 200% PNGs of three departments + the modal, plus
##      scavenging at 100%, under .impeccable/review/t15/ — validated for
##      dimensions + real content.

const REVIEW_DIR := "res://.impeccable/review/t15"
const CAPTURE_UNSUPPORTED_EXIT := 42
const DEPT_IDS := ["scavenging", "foraging", "junksmithing", "cooking",
	"wasteland_patrol", "requisition_depot", "manifest", "personnel"]
const SOURCE_SCAN := [
	"res://scenes/main.gd",
	"res://scripts/ui/docket.gd",
	"res://scripts/ui/docket_skill.gd",
	"res://scripts/ui/docket_gathering.gd",
	"res://scripts/ui/docket_processing.gd",
	"res://scripts/ui/docket_manifest.gd",
	"res://scripts/ui/docket_depot.gd",
	"res://scripts/ui/docket_patrol.gd",
	"res://scripts/ui/mail_call_modal.gd",
	"res://scripts/ui/save_notice_board.gd",
	"res://scripts/ui/orientation_form.gd",
]

var checks := 0
var failures: Array[String] = []
var _pairs := {}  # "fg|bg|class" -> true (the sampled-pair report)
var _capture_mode := false
var _capture_unsupported := false
var _done := false
var _vp: SubViewport
var _concourse: Concourse

func _initialize() -> void:
	_capture_mode = "capture" in OS.get_cmdline_user_args()
	_run()

func _process(_delta: float) -> bool:
	return _done

func _run() -> void:
	if not _setup():
		_report_and_quit()
		return
	await _frames(2)
	_check(_concourse.bound_tick_manager() != null, "engine bound (production autoload)")
	await _contrast_audit()
	await _font_scale_200_sweep()
	await _motion_audit()
	if _capture_mode:
		await _capture_set()
		if _capture_unsupported:
			_done = true
			return
	_report_and_quit()

# ------------------------------------------------------------------ setup
func _setup() -> bool:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var packed := load("res://scenes/main.tscn") as PackedScene
	_concourse = packed.instantiate() as Concourse
	if _concourse == null:
		_check(false, "concourse instantiates")
		return false
	_vp.add_child(_concourse)
	return true

func _tm() -> Node:
	# Bound in Concourse._ready after its boot-swell await — callers run post-
	# frames (probe_concourse's ordering).
	return _concourse.bound_tick_manager()

func _seed() -> void:
	var tm := _tm()
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("copper_wiring", 20)
	tm.state.add_item("glowshroom", 3)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_crowns(5)  # glowshroom costs 6: BUY x0 renders DISABLED
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)

# ------------------------------------------------------------------ 1. contrast
## Walk the live tree and recompute WCAG math from the ACTUAL rendered
## ink/ground pairs (theme colors + widget styleboxes at runtime).
func _contrast_audit() -> void:
	_seed()
	await _frames(1)

	# Per department, in a state that exercises its every variation:
	# scavenging RUNNING (energized card + status plate), junksmithing
	# RUNNING (craft), patrol FIGHTING (+ all four phase wordings), the rest
	# idle (gates visible at low clearances; depot poor-wallet BUY x0
	# disabled; manifest with an equipped weapon + vacant armor slot).
	# T17: the sweep's concurrency (scavenging + junksmithing + an engaged
	# patrol = 3 postings) staffs through the engine seam — the purchase flow
	# itself is tests/test_staffing.gd's subject.
	_tm().engine.ensure_staffing(_tm().state)
	_tm().state.staffing["deputies"] = 4
	_tm().start_activity("sort_scrap_pile")
	for id in DEPT_IDS:
		if id == "junksmithing":
			_tm().start_activity("smelt_scrap_ingot")
		_concourse.select_department(id, true)
		await _frames(2)
		if id == "wasteland_patrol":
			(_concourse.docket_controller("wasteland_patrol") as DocketPatrol) \
				._engage("junkyard_roach")
			await _frames(1)
		if id == "manifest":
			_tm().equip_item("scrap_shiv")
			await _frames(1)
		_sweep_contrast(_concourse, "dept " + id)
		_collapse_sweep(_concourse, "dept " + id)
		if id == "wasteland_patrol":
			# Phase plates: the four wordings swap label variations — sweep
			# each rendering (the wording cue itself is pinned in test_a11y).
			var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
			var boss: MonsterDef = _tm().engine.lib.monster("sewer_landlord")
			for phase in ["dead", "victory", "recalled"]:
				patrol._apply_phase_plate(phase, boss)
				_sweep_contrast(patrol.phase_plate, "patrol phase " + phase)
			patrol._apply_phase_plate("fighting", null)
	_tm().stop_skill("scavenging")
	_tm().stop_skill("junksmithing")
	_tm().stop_combat()

	# Shell chrome: header + console + the bulkhead shutter mid-transition.
	_concourse.select_department("scavenging", true)
	await _frames(2)
	_sweep_contrast(_concourse.find_child("HeaderRow", true, false), "header")
	_sweep_contrast(_concourse.find_child("ConsoleBar", true, false), "console")
	_concourse.shutter.visible = true
	await _frames(1)
	_sweep_contrast(_concourse.shutter, "bulkhead shutter")
	_concourse.shutter.visible = false

	# MAIL CALL modal: a payload exercising every line class incl. the red
	# recall plate inside the paper card.
	_concourse.mail_call.present({
		"elapsed_ms": 7_200_000,
		"skills_xp": {"scavenging": 1_240, "wasteland_combat": 8_340},
		"items": {"scrapnel": 34},
		"levels": {"scavenging": {"from": 3, "to": 4}},
		"actions": {"scavenging": 112},
		"stopped": [{"skill_id": "wasteland_combat", "content_id": "",
			"reason": "patrol_recalled"}],
		"combat": {"kills": 2, "monster_id": "junkyard_roach", "outcome": "recalled",
			"truncated": true, "zone_cleared": false},
	}, _tm().engine.lib)
	await _frames(1)
	_sweep_contrast(_concourse.mail_call, "mail call modal")
	_collapse_sweep(_concourse.mail_call, "mail call modal")
	_concourse.mail_call.acknowledge()

	# Save-notice board posting.
	_concourse.save_board.post("refused_newer_save_version",
		{"found_save_version": 99, "supported_save_version": 1})
	await _frames(2)
	_sweep_contrast(_concourse.save_board, "save notice")
	_collapse_sweep(_concourse.save_board, "save notice")
	_concourse.save_board.ack_button.pressed.emit()

	# The tooltip pair (posted paper): navy ink on paper via the theme.
	var theme: Theme = _concourse.theme
	_pair_check("tooltip navy on paper",
		theme.get_color("font_color", "TooltipLabel"), SignageTokens.PAPER_NOTICE, null)

	# Registered UI component boundaries (non-text, 3:1 class).
	_check(SignageTokens.contrast_ratio(SignageTokens.SIGNAL_AMBER, SignageTokens.ROLLED_STEEL) >= 3.0,
		"focus-ring amber vs rolled steel >= 3:1 (component boundary)")
	_check(SignageTokens.contrast_ratio(SignageTokens.SIGNAL_AMBER, SignageTokens.STEEL_DEEP) >= 3.0,
		"gauge-fill amber vs steel-deep track >= 3:1 (component boundary)")

	# The energized hover pair specifically (the T15 fix: hover keeps navy).
	var begin := _concourse.begin_button_for("scavenging")
	var hover := begin.get_theme_stylebox("hover") as StyleBoxFlat
	_check(hover.bg_color.is_equal_approx(SignageTokens.INSTITUTIONAL_NAVY),
		"energized hover keeps the navy ground (no 4.46:1 NAVY_HI pair)")
	_check(SignageTokens.contrast_ratio(
			begin.get_theme_color("font_hover_color"), hover.bg_color) >= 4.5,
		"energized hover amber-on-navy >= 4.5:1")


## Sweep one subtree: every visible Label / BaseButton / ItemList, every
## applicable state (normal/hover/pressed/disabled), actual ink + ground.
func _sweep_contrast(node: Node, where: String) -> void:
	for c in _text_controls(node):
		if c is Label:
			var l := c as Label
			if l.text.strip_edges() == "":
				continue
			_pair_check("%s label %s" % [where, l.name],
				l.get_theme_color("font_color"), _ground_of(l), l)
		elif c is BaseButton:
			var b := c as BaseButton
			var states := ["normal", "hover", "pressed"]
			if b.disabled:
				states = ["disabled"]
			for state in states:
				# The theme's color name for the resting state is font_color
				# (there is no font_normal_color).
				var color_name := "font_color" if state == "normal" \
					else "font_%s_color" % state
				_pair_check("%s button %s [%s]" % [where, b.name, state],
					b.get_theme_color(color_name),
					_button_ground(b, state), b)
		elif c is ItemList:
			var il := c as ItemList
			_pair_check("%s list %s" % [where, il.name],
				il.get_theme_color("font_color"),
				_stylebox_ground(il.get_theme_stylebox("panel")), il)
			_pair_check("%s list %s [selected]" % [where, il.name],
				il.get_theme_color("font_selected_color"),
				_stylebox_ground(il.get_theme_stylebox("selected")), il)


## T15 fix-round COLLAPSE GUARD: every visible text-bearing Label must render
## at least as wide as its widest unbreakable word (its own font, its own
## theme-scaled size). An autowrapped Label's minimum width collapses to ~1
## px, so an HBox starves it into a vertical one-character column — the
## skill-docket serial collapse this pin exists to catch, at any scale.
func _collapse_sweep(node: Node, where: String) -> void:
	for c in _text_controls(node):
		if c is Label:
			var l := c as Label
			if l.text.strip_edges() == "":
				continue
			var floor := _longest_word_width(l)
			_check(l.size.x >= floor - 1.0,
				"%s label %s not collapsed (%.1f wide >= longest word %.1f)" % [
					where, l.name, l.size.x, floor])
			_check(not (l.size.x < 8.0 and l.size.y > 40.0),
				"%s label %s is a vertical column (%.1fx%.1f)" % [
					where, l.name, l.size.x, l.size.y])


func _longest_word_width(l: Label) -> float:
	var font: Font = l.get_theme_font("font")
	if font == null:
		return 0.0
	var fs := l.get_theme_font_size("font_size")
	var widest := 0.0
	for word in l.text.split(" ", false):
		widest = maxf(widest, font.get_string_size(
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return widest


## One sampled pair -> WCAG verdict. Class chosen by size/weight at runtime.
func _pair_check(label: String, fg: Color, bg: Color, source: Control) -> void:
	var large := _is_large_text(source)
	var need := 3.0 if large else 4.5
	var ratio := SignageTokens.contrast_ratio(fg, bg)
	_pairs["%s>%s:%s" % [fg.to_html(false), bg.to_html(false), "L" if large else "B"]] = true
	_check(ratio >= need, "%s: %s on %s = %.2f < %.1f" % [
		label, fg.to_html(false), bg.to_html(false), ratio, need])
	# The registered class rule: amber ink on rolled steel is LARGE-ONLY.
	if fg.is_equal_approx(SignageTokens.SIGNAL_AMBER) \
			and bg.is_equal_approx(SignageTokens.ROLLED_STEEL) and not large:
		_check(false, "%s: amber body-size text on rolled steel (large-caps class only)" % label)


func _is_large_text(c: Control) -> bool:
	if c == null:
		return false
	var size := 16
	if c is Label:
		size = (c as Label).get_theme_font_size("font_size")
	elif c is BaseButton:
		size = (c as BaseButton).get_theme_font_size("font_size")
	if size >= 24:
		return true
	return size >= 19 and _is_true_bold(c)


## True-bold only (WCAG 14pt-bold); SemiBold display faces stay body class —
## the conservative reading.
func _is_true_bold(c: Control) -> bool:
	var f: Font = null
	if c is Label:
		f = (c as Label).get_theme_font("font")
	elif c is BaseButton:
		f = (c as BaseButton).get_theme_font("font")
	if f == null:
		return false
	var path := f.resource_path
	if path == "" and f is FontVariation:
		var base: Font = (f as FontVariation).base_font
		path = base.resource_path if base != null else ""
	return "bold" in path.to_lower() and "semibold" not in path.to_lower()


## The ground a control's text actually sits on: the nearest ancestor panel
## (theme variation -> token) or a button ancestor's own plate.
func _ground_of(c: Control) -> Color:
	var cur: Node = c.get_parent()
	while cur != null and cur is Control:
		if cur is BaseButton:
			return _button_ground(cur as BaseButton, "normal")
		if cur is PanelContainer or cur is Panel:
			return _panel_ground(cur as Control)
		cur = cur.get_parent()
	return SignageTokens.ROLLED_STEEL


func _panel_ground(p: Control) -> Color:
	match p.theme_type_variation:
		"EnamelPlate": return SignageTokens.BONE_ENAMEL
		"EnergizedPlate": return SignageTokens.INSTITUTIONAL_NAVY
		"DangerPlate": return SignageTokens.SAFETY_RED
		"PaperNotice": return SignageTokens.PAPER_NOTICE
		"VentHousing": return SignageTokens.STEEL_LO
		"SteelPanel": return SignageTokens.ROLLED_STEEL  # drawn on #4E5560 steel
		_: return SignageTokens.ROLLED_STEEL  # plain Panel = the steel wall


func _button_ground(b: BaseButton, state: String) -> Color:
	var bg := _stylebox_ground(b.get_theme_stylebox(state))
	if bg.a < 0.999:  # transparent chrome (CheckButton) -> parent ground
		return _ground_of(b)
	return bg


func _stylebox_ground(sb: StyleBox) -> Color:
	if sb is StyleBoxFlat:
		return (sb as StyleBoxFlat).bg_color
	if sb is StyleBoxTexture:
		return SignageTokens.ROLLED_STEEL  # the riveted panel texture base
	return Color(0, 0, 0, 0)


func _text_controls(node: Node) -> Array:
	var out: Array = []
	_collect_text(node, out)
	return out

func _collect_text(node: Node, out: Array) -> void:
	if node is Label or node is BaseButton or node is ItemList:
		if (node as Control).is_visible_in_tree():
			out.append(node)
	for child in node.get_children():
		_collect_text(child, out)

# ------------------------------------------------------------------ 2. font 200%
func _font_scale_200_sweep() -> void:
	_seed()
	_concourse.font_slider.value = 2.0
	await _frames(3)
	_check(_concourse.theme.get_font_size("font_size", "PlateTitle") == 52,
		"theme is at 200% for the sweep")

	# The shell column itself fits the 1280 window (nothing off-screen).
	var layout: Control = _concourse.find_child("Layout", true, false)
	var col_min: Vector2 = layout.get_combined_minimum_size()
	_check(col_min.x <= 1196.0, "shell column min width %.0f <= 1196 at 200%%" % col_min.x)

	# Every docket fits its column; every focusable reachable + focus brings
	# it into view (keyboard-scrollable bulkhead regions).
	for id in DEPT_IDS:
		_concourse.select_department(id, true)
		await _frames(2)
		var scroll: ScrollContainer = _concourse.find_child("DocketScroll", true, false) as ScrollContainer
		var budget: float = scroll.size.x - 44.0 - 48.0
		var need: float = _concourse.docket_controller(id).get_combined_minimum_size().x
		_check(need <= budget, "200%% docket %s fits (%.0f <= %.0f)" % [id, need, budget])
		_collapse_sweep(_concourse, "200%% dept %s" % id)
		var focusables := _concourse.focusable_controls()
		var visited := {}
		var cur: Control = _concourse.initial_focus()
		var guard := 0
		while guard < 256 and not visited.has(cur):
			visited[cur] = true
			cur = cur.find_next_valid_focus()
			guard += 1
		var unreachable := 0
		for f in focusables:
			if not visited.has(f):
				unreachable += 1
		_check(unreachable == 0, "200%% %s: every focusable reachable (%d)" % [id, focusables.size()])
		var offscreen := 0
		for f in focusables:
			f.grab_focus()
			await _frames(3)
			var r := f.get_global_rect()
			var ok := r.end.x <= 1280.5 and r.position.x >= -0.5 and r.position.y < 720.0
			var anc: Node = f
			while anc != null and ok:
				if anc is ScrollContainer:
					if not r.intersects((anc as ScrollContainer).get_global_rect()):
						ok = false
				anc = anc.get_parent()
			if not ok:
				offscreen += 1
				printerr("  200%% %s focus not visible: %s %s" % [id, f.name, r])
		_check(offscreen == 0, "200%% %s: focus scrolls every control into view" % id)

	# The console stays fully on window (the flow-wrap fix).
	var quit: Control = _concourse.quit_button
	_check(quit.get_global_rect().end.x <= 1280.0 and quit.get_global_rect().position.y < 720.0,
		"200%%: CLOCK OUT on screen (%s)" % quit.get_global_rect())

	# The modal at 200%: presents, traps, acknowledges; ack on screen.
	_tm().start_activity("sort_scrap_pile")
	_tm().advance_wall_ms(3_000)
	_tm().apply_offline_elapsed(3_600_000)
	await _frames(3)
	_check(_concourse.mail_call.is_presenting(), "200%: MAIL CALL presents")
	_collapse_sweep(_concourse.mail_call, "200% mail call modal")
	var ack := _concourse.mail_call.ack_button
	_check(ack.get_global_rect().end.x <= 1280.0 and ack.get_global_rect().end.y <= 720.0,
		"200%%: acknowledge on screen (%s)" % ack.get_global_rect())
	for i in 12:
		_push_action("ui_focus_next")
		await _frames(1)
	_check(_concourse.mail_call.is_ancestor_of(_vp.gui_get_focus_owner()),
		"200%: modal still traps focus")
	_push_action("ui_cancel")
	await _frames(1)
	_check(not _concourse.mail_call.is_presenting(), "200%: Esc acknowledges at 200%")
	_tm().stop_skill("scavenging")

	# Back to 100%: the shell fits trivially and the theme follows.
	_concourse.font_slider.value = 0.0
	await _frames(2)
	_check(_concourse.theme.get_font_size("font_size", "PlateTitle") == 26,
		"theme returns to 100%")

# ------------------------------------------------------------------ 3. motion
func _motion_audit() -> void:
	_check(Concourse.TRANSITION_CLOSE_S + Concourse.TRANSITION_OPEN_S <= 0.7,
		"bulkhead slide constants bounded (%.2f + %.2f s)" % [
			Concourse.TRANSITION_CLOSE_S, Concourse.TRANSITION_OPEN_S])
	# A real keyboard-driven transition, wall-clock bounded.
	(_concourse.plates()["manifest"] as Button).grab_focus()
	await _frames(1)
	var t0 := Time.get_ticks_msec()
	_push_action("ui_accept")
	var n := 0
	while n < 600 and (_concourse.is_transitioning()
			or _concourse.active_department() != "manifest"):
		await _frames(1)
		n += 1
	var elapsed := Time.get_ticks_msec() - t0
	_check(_concourse.active_department() == "manifest",
		"keyboard-driven bulkhead slide completes")
	_check(elapsed <= 1_000, "keyboard-driven slide bounded (%d ms)" % elapsed)
	# Nothing loops: no looping/infinite tweens anywhere in the UI sources
	# (the only authored motions are the 0.24/0.34 s slide, the 0.22 s swell,
	# the 0.30 s settle, the O-1 stamp swell + arrival swell (T18) — all
	# one-shot).
	for path in SOURCE_SCAN:
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			_check(false, "motion scan reads %s" % path)
			continue
		var src := fa.get_as_text()
		fa.close()
		_check(not src.contains("set_loops(") and not src.contains("Tween.LOOP_INFINITE"),
			"no looping motion in %s" % path)

# ------------------------------------------------------------------ 4. captures
func _capture_set() -> void:
	if DirAccess.make_dir_recursive_absolute(REVIEW_DIR) != OK:
		_check(false, "t15 review dir created")
		return
	_concourse.font_slider.value = 2.0
	await _frames(3)
	var tm := _tm()
	tm.new_game(20260915)
	tm.state.add_item("scrap_shiv", 2)
	tm.state.add_item("scrap_metal", 30)
	tm.state.add_item("majority_whip", 1)
	tm.state.add_item("carpool_carapace", 1)
	tm.state.add_item("radstag_stew", 10)
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	_concourse.set_first_run(false)

	# Scavenging at 200%: a running shift with stamped yield lines. The
	# scroll shows the energized status plate — the previously-collapsed
	# control the verifier's evidence was about.
	_concourse.select_department("scavenging", true)
	await _frames(2)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 12_500)
	await _frames(2)
	await _docket_show((_concourse.docket_controller("scavenging") as DocketSkill).status_plate)
	if not _snap("a11y200_scavenging_1280x720.png"):
		return
	tm.stop_skill("scavenging")

	# Manifest at 200%: owned goods + an equipped weapon.
	tm.equip_item("majority_whip")
	tm.batcher.mark("inventory")
	tm.batcher.force_flush(tm.sim_time_ms)
	_concourse.select_department("manifest", true)
	await _frames(4)
	await _docket_show(_concourse.docket_controller("manifest"))
	if not _snap("a11y200_manifest_1280x720.png"):
		return

	# Patrol at 200%: mid-fight with gauges partially drained.
	tm.equip_item("carpool_carapace")
	_concourse.select_department("wasteland_patrol", true)
	await _frames(2)
	await _docket_show(_concourse.docket_controller("wasteland_patrol"))
	var patrol := _concourse.docket_controller("wasteland_patrol") as DocketPatrol
	((patrol.get("_cards") as Dictionary)["junkyard_roach"].button as Button).pressed.emit()
	_pump(tm, 20_000)
	await _frames(2)
	if not _snap("a11y200_patrol_1280x720.png"):
		return

	# MAIL CALL at 200% over the concourse.
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 3_000)
	tm.apply_offline_elapsed(3_600_000)
	await _frames(4)
	if not _snap("a11y200_mail_call_1280x720.png"):
		return
	_concourse.mail_call.acknowledge()
	tm.stop_skill("scavenging")

	# T15 fix round: scavenging at 100% too — the serial collapse was
	# verifier-measured at BOTH scales, so the horizontal reading is pinned
	# by capture at both scales (running shift + stamped yields, like 200%).
	_concourse.font_slider.value = 0.0
	await _frames(3)
	_concourse.select_department("scavenging", true)
	await _frames(2)
	tm.start_activity("sort_scrap_pile")
	_pump(tm, 12_500)
	await _frames(2)
	await _docket_show((_concourse.docket_controller("scavenging") as DocketSkill).status_plate)
	if not _snap("a11y100_scavenging_1280x720.png"):
		return
	tm.stop_skill("scavenging")
	_validate_pngs()


## Deterministic capture state: scroll the docket viewport to the docket's
## own content (the housing chrome above it fills the whole 200% viewport),
## so the previously-collapsed serials are IN the frame — the status plate
## for the skill docket, the docket top for the others.
func _docket_show(control: Control) -> void:
	var scroll: ScrollContainer = _concourse.find_child("DocketScroll", true, false) as ScrollContainer
	if scroll != null and control != null:
		scroll.ensure_control_visible(control)
		await _frames(1)


func _snap(file_name: String) -> bool:
	var img := _vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		_capture_unsupported = true
		return false
	var err := img.save_png(REVIEW_DIR + "/" + file_name)
	_check(err == OK, "captured %s (err=%d)" % [file_name, err])
	return true


func _validate_pngs() -> void:
	var expects := {
		"a11y200_scavenging_1280x720.png": Vector2i(1280, 720),
		"a11y200_manifest_1280x720.png": Vector2i(1280, 720),
		"a11y200_patrol_1280x720.png": Vector2i(1280, 720),
		"a11y200_mail_call_1280x720.png": Vector2i(1280, 720),
		"a11y100_scavenging_1280x720.png": Vector2i(1280, 720),
	}
	for file_name: String in expects:
		var path := REVIEW_DIR + "/" + file_name
		var fa := FileAccess.open(path, FileAccess.READ)
		_check(fa != null and fa.get_length() > 0, "%s saved with size > 0" % file_name)
		if fa == null:
			continue
		fa.close()
		var img := Image.load_from_file(path)
		_check(img != null, "%s is a loadable image" % file_name)
		if img == null:
			continue
		_check(Vector2i(img.get_width(), img.get_height()) == expects[file_name],
			"%s dimensions %dx%d" % [file_name, img.get_width(), img.get_height()])
		var colors := {}
		for x in range(0, img.get_width(), 16):
			for y in range(0, img.get_height(), 16):
				colors[img.get_pixel(x, y).to_html(true)] = true
		_check(colors.size() >= 8, "%s renders real content (%d distinct sampled colors)" % [
			file_name, colors.size()])

# ------------------------------------------------------------------ helpers
func _pump(tm: Node, total_ms: int) -> void:
	var fed := 0
	while fed < total_ms:
		var step := mini(500, total_ms - fed)
		tm.advance_wall_ms(step)
		fed += step

func _push_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	_vp.push_input(ev)
	ev.pressed = false
	_vp.push_input(ev)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("  FAIL: " + label)

func _report_and_quit() -> void:
	_done = true
	if failures.is_empty():
		print("PROBE_OK checks=%d (contrast re-audit of final screens: %d distinct rendered pairs, all AA, amber-on-steel large-only, energized hover >= 4.5; font 200%%: column fits 1280, all %d dockets fit, every focusable reachable + scrolled into view, CLOCK OUT on screen, modal trapped + escaped; collapse guard: every visible Label >= its longest word at 100%% and 200%% on all departments + the modal; motion bounded, no looping tweens)" % [checks, _pairs.size(), DEPT_IDS.size()])
		quit(0)
	else:
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for f in failures:
			printerr("  - " + f)
		quit(1)
