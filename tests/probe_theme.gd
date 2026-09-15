extends SceneTree
## tests/probe_theme.gd — T8 signage-theme probe (plain --script; R2 pattern).
##
## Run (assertions only, headless):
##   "$GODOT" --headless --path . -s res://tests/probe_theme.gd
## Run with gallery captures (needs a real renderer — headless dummy driver
## returns null viewport images; the runner retries windowed on exit 42):
##   "$GODOT" --path . -s res://tests/probe_theme.gd -- capture
##
## Proves the T8 acceptance criteria:
##   1. the Theme resource loads and its token values match SignageTokens;
##   2. every registered text-on-ground pair passes WCAG-AA (4.5:1 body,
##      3:1 large) with the math recomputed here and printed as a table
##      (mirrors docs/theme-contrast-table.md); forbidden pairs stay failing;
##   3. font scale: every registered font size re-scales (100% -> 200%);
##   4. ASSETS.md provenance covers every bundled font/theme asset file;
##   5. the component gallery instantiates with every demo wired;
##   6. (capture mode) gallery PNGs at 1280x720, 1920x1080, and 200% font
##      scale are written under .impeccable/review/t8/ and validated
##      (non-empty, correct dimensions, non-blank).

const THEME_PATH := "res://assets/theme/signage_theme.tres"
const GALLERY_PATH := "res://scenes/dev/theme_gallery.tscn"
const REVIEW_DIR := "res://.impeccable/review/t8"
const CAPTURE_UNSUPPORTED_EXIT := 42

var checks := 0
var failures: Array[String] = []
var _frame := 0
var _capture_mode := false
var _theme: Theme
var _gallery: Control
var _vp: SubViewport

func _initialize() -> void:
	_capture_mode = "capture" in OS.get_cmdline_user_args()
	_check_theme_tokens()
	_check_contrast_table()
	_check_font_scale()
	_check_assets_provenance()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup_viewport_and_gallery()
		return false
	if not _capture_mode:
		_report_and_quit()
		return true
	# Prepare at one frame, snap several frames later: resizing a live
	# SubViewport invalidates its render target for a few frames.
	if _frame == 12:
		return not _snap("gallery_1280x720.png")
	if _frame == 14:
		_prepare(Vector2i(1920, 1080), 1.0)
		return false
	if _frame == 26:
		return not _snap("gallery_1920x1080.png")
	if _frame == 28:
		_prepare(Vector2i(1280, 720), 2.0)
		return false
	if _frame == 40:
		if _snap("gallery_200_1280x720.png"):
			SignageTheme.apply_font_scale(_theme, 1.0)  # leave clean for later runs
			_validate_saved_pngs()
		_report_and_quit()
		return true
	if _frame > 48:
		_check(false, "capture pipeline stalled")
		_report_and_quit()
		return true
	return false

# ------------------------------------------------------------------ checks
func _check_theme_tokens() -> void:
	_theme = load(THEME_PATH) as Theme
	_check(_theme != null, "theme resource loads from %s" % THEME_PATH)
	if _theme == null:
		return
	var t := SignageTokens

	# Token values exist and are wired into the stylebox library.
	_assert_sb_color("Button", "normal", "bg_color", t.BONE_ENAMEL)
	_assert_sb_color("Button", "normal", "border_color", t.INSTITUTIONAL_NAVY)
	_assert_sb_color("Energized", "normal", "bg_color", t.INSTITUTIONAL_NAVY)
	_assert_sb_color("Energized", "normal", "border_color", t.SIGNAL_AMBER)
	_assert_sb_color("Danger", "normal", "bg_color", t.SAFETY_RED)
	_assert_sb_color("DangerPlate", "panel", "bg_color", t.SAFETY_RED)
	_assert_sb_color("EnamelPlate", "panel", "bg_color", t.BONE_ENAMEL)
	_assert_sb_color("EnergizedPlate", "panel", "bg_color", t.INSTITUTIONAL_NAVY)
	_assert_sb_color("PaperNotice", "panel", "bg_color", t.PAPER_NOTICE)
	_assert_sb_color("Panel", "panel", "bg_color", t.ROLLED_STEEL)

	# Component state pairs: Default + Active + Disabled + focus for Button.
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		_check(_theme.get_stylebox(state_name, "Button") != null,
			"Button has '%s' stylebox" % state_name)
		_check(_theme.get_stylebox(state_name, "Energized") != null,
			"Energized has '%s' stylebox" % state_name)

	# Fonts: all three roles load; tracked variations keep their base font.
	for role in ["Label", "PlateTitle", "BodyCopy", "MonoValue", "PaperText"]:
		_check(_theme.get_font("font", role) != null, "font for '%s' loads" % role)
	var plate_font := _theme.get_font("font", "PlateTitle") as FontVariation
	_check(plate_font != null and plate_font.base_font != null,
		"PlateTitle is a tracked FontVariation with a live base font")
	var plate_names := plate_font.get_font_name().to_lower() if plate_font != null else ""
	_check("stencil" in plate_names, "plate face is the stencil family (got '%s')" % plate_names)

	# StyleBox material library completeness.
	for material in ["EnamelPlate", "EnergizedPlate", "DangerPlate", "SteelPanel",
			"VentHousing", "PaperNotice"]:
		_check(_theme.get_stylebox("panel", material) != null,
			"material '%s' present in StyleBox library" % material)

func _assert_sb_color(type_name: String, item: String, prop: String, expected: Color) -> void:
	var sb := _theme.get_stylebox(item, type_name)
	if sb == null:
		_check(false, "%s/%s stylebox exists" % [type_name, item])
		return
	if prop == "bg_color" and sb is StyleBoxFlat:
		_check((sb as StyleBoxFlat).bg_color.is_equal_approx(expected),
			"%s/%s bg_color == %s" % [type_name, item, expected.to_html(false)])
	elif prop == "border_color" and sb is StyleBoxFlat:
		_check((sb as StyleBoxFlat).border_color.is_equal_approx(expected),
			"%s/%s border_color == %s" % [type_name, item, expected.to_html(false)])
	else:
		_check(false, "%s/%s prop %s unexpected" % [type_name, item, prop])

func _check_contrast_table() -> void:
	var t := SignageTokens
	print("AA_TABLE_BEGIN pairs=%d" % t.CONTRAST_PAIRS.size())
	for pair in t.CONTRAST_PAIRS:
		var name: String = pair[0]
		var fg: Color = pair[1]
		var bg: Color = pair[2]
		var kind: String = pair[3]
		var ratio := t.contrast_ratio(fg, bg)
		var need := t.threshold_for(kind)
		var ok := ratio >= need
		print("AA_TABLE %-42s %s/%s  L(%.4f/%.4f)  ratio=%.2f  need>=%.1f  %s" % [
			name, fg.to_html(false), bg.to_html(false),
			t.relative_luminance(fg), t.relative_luminance(bg),
			ratio, need, "PASS" if ok else "FAIL"])
		_check(ok, "contrast: %s (%.2f:1 < %.1f:1)" % [name, ratio, need])
	for pair in t.FORBIDDEN_PAIRS:
		var name: String = pair[0]
		var fg: Color = pair[1]
		var bg: Color = pair[2]
		var ratio := t.contrast_ratio(fg, bg)
		print("AA_FORBIDDEN %-46s %s/%s  ratio=%.2f (must stay below 3.0)" % [
			name, fg.to_html(false), bg.to_html(false), ratio])
		_check(ratio < 3.0, "forbidden pair stays failing: %s (%.2f)" % [name, ratio])
		# A forbidden combo must never be registered as usable.
		for reg in t.CONTRAST_PAIRS:
			_check(not (reg[1] == fg and reg[2] == bg),
				"forbidden combo not registered: %s" % name)

func _check_font_scale() -> void:
	var th := SignageTheme.build()
	for scale_step in [1.5, 2.0]:
		SignageTheme.apply_font_scale(th, scale_step)
		for entry in SignageTheme.FONT_SIZE_BASES:
			var want: int = roundi(entry[2] * scale_step)
			var got: int = th.get_font_size("font_size", entry[0])
			_check(got == want, "font scale %.1f: %s %d -> %d" % [scale_step, entry[0], entry[2], got])
	SignageTheme.apply_font_scale(th, 1.0)
	_check(th.get_font_size("font_size", "PlateTitle") == 26, "font scale resets to base")

func _check_assets_provenance() -> void:
	var f := FileAccess.get_file_as_string("res://ASSETS.md")
	_check(not f.is_empty(), "ASSETS.md exists at repo root")
	if f.is_empty():
		return
	# Every bundled asset file must have a provenance row; every row must resolve.
	var asset_paths: Array[String] = []
	for dir in ["res://assets/fonts", "res://assets/theme"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var file := d.get_next()
		while not file.is_empty():
			if file.get_extension() in ["ttf", "svg"]:
				asset_paths.append(dir.path_join(file))
			file = d.get_next()
		d.list_dir_end()
	for path in asset_paths:
		_check(path.trim_prefix("res://") in f, "ASSETS.md row exists for %s" % path)
	for line: String in f.split("\n"):
		line = line.strip_edges()
		if not line.begins_with("| assets/"):
			continue
		var path := "res://" + String(line.split("|")[1]).strip_edges()
		_check(FileAccess.file_exists(path), "ASSETS.md row resolves: %s" % path)

func _setup_viewport_and_gallery() -> void:
	# Gallery goes straight into its SubViewport (reparenting a live Control
	# into a viewport leaves it on the old canvas — renders blank).
	if _capture_mode:
		DirAccess.make_dir_recursive_absolute(REVIEW_DIR)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	var packed := load(GALLERY_PATH) as PackedScene
	_check(packed != null, "gallery scene loads")
	if packed == null:
		return
	_gallery = packed.instantiate() as Control
	_check(_gallery != null and _gallery.theme != null, "gallery root carries the signage theme")
	_vp.add_child(_gallery)
	var drop_lines := _gallery.get_node("%DropLines") as ItemList
	_check(drop_lines != null and drop_lines.item_count == 5, "gallery drop lines populated (5)")
	var dots := _gallery.get_node("%MailDots") as HBoxContainer
	_check(dots != null and dots.get_child_count() == 12, "mail counter has 12 dot cells")
	var tabs := _gallery.get_node("%DepartmentTabs") as TabContainer
	_check(tabs != null and tabs.get_tab_title(0) == "SCAVENGING", "tab titles are stencil caps")
	_check(_gallery.get_viewport().gui_get_focus_owner() != null,
		"focus demo grabbed focus (visible focus ring)")

# ------------------------------------------------------------------ capture
func _prepare(size: Vector2i, scale: float) -> void:
	SignageTheme.apply_font_scale(_theme, scale)
	_vp.size = size

func _snap(file_name: String) -> bool:
	var img := _vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		quit(CAPTURE_UNSUPPORTED_EXIT)
		return false
	var path := REVIEW_DIR + "/" + file_name
	var err := img.save_png(path)
	_check(err == OK, "captured %s (err=%d)" % [path, err])
	return true

func _validate_saved_pngs() -> void:
	var expects := {
		"gallery_1280x720.png": Vector2i(1280, 720),
		"gallery_1920x1080.png": Vector2i(1920, 1080),
		"gallery_200_1280x720.png": Vector2i(1280, 720),
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

# ------------------------------------------------------------------ report
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("  FAIL: " + label)

func _report_and_quit() -> void:
	if failures.is_empty():
		print("PROBE_OK checks=%d (tokens live; all AA pairs pass; font scale proven; provenance gate clean; gallery wired)" % checks)
		quit(0)
	else:
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for f in failures:
			printerr("  - " + f)
		quit(1)
