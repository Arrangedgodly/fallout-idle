extends SceneTree
## tests/probe_icons.gd — T11 icon-set probe (plain --script; R2/T8 pattern).
##
## Run (assertions only, headless):
##   "$GODOT" --headless --path . -s res://tests/probe_icons.gd
## Run with the gallery capture (needs a real renderer — headless dummy driver
## returns null viewport images; retry windowed on exit 42, per T8's fallback):
##   "$GODOT" --path . -s res://tests/probe_icons.gd -- capture
##
## Proves the T11 acceptance criteria:
##   1. every icon id referenced by content (items, skills, activities,
##      monsters, recipes) resolves to a shipped res://assets/icons/<id>.svg —
##      checked twice: directly from the JSON source AND through the
##      production loader, whose icon gate is STRICT since T11 (an
##      unresolvable icon is a boot error carrying id + field + reason);
##   2. every assets/icons/*.svg parses as valid SVG: angle-bracket structure
##      (balanced < >, a <svg ...> root, a closing </svg>) and at least one
##      draw element;
##   3. no SVG contains external references: no http(s) URLs beyond the W3C
##      xmlns namespace declaration (a namespace id, never fetched), no href /
##      xlink references, no <image> elements (self-contained paths only);
##   4. signage grammar holds set-wide: 128x128 viewBox, colors drawn ONLY
##      from the SignageTokens palette (bone/navy/amber/red), no gradients,
##      no <text> (stencil glyphs only);
##   5. ASSETS.md no-row-no-ship gate for icons: every icon file has exactly
##      one row; every icon row resolves to a real file and sources original;
##   6. the set covers the commissioned surface: 5 skills, 21 items, 5
##      monsters, 8 activities, plus the Crowns currency mark, the food
##      category mark and the 12 T19 grammar glyphs (53 SVGs);
##   6b. the T19 icon-grammar contract (naming-bible §14 + design-brief
##      addendum): all 12 reserved ids ship, class ink rules hold (navy
##      stat/clearance linework, amber verb/cue ink, red stamp ink, the
##      FILLED deputy badge), the staircase is a staircase — never a padlock —
##      and every UI-consumed glyph is referenced from shipped UI source;
##   7. every icon imports as a 128x128 texture;
##   8. (capture mode) the gallery composite (every icon) saved to
##      .impeccable/review/t11/icons.png AND the T19 legibility board (the 12
##      grammar glyphs at 48 px and 20 px plus the inline [glyph][value]
##      idiom) saved to .impeccable/review/t11/t19_glyph_sizes.png — both
##      validated.

const ProbeContent := preload("res://tests/probe_content.gd")

const ICONS_DIR := "res://assets/icons"
const REVIEW_DIR := "res://.impeccable/review/t11"
const CAPTURE_PNG := "icons.png"
const T19_CAPTURE_PNG := "t19_glyph_sizes.png"
const CAPTURE_UNSUPPORTED_EXIT := 42
const W3C_SVG_NAMESPACE := "http://www.w3.org/2000/svg"

const TOKEN_HEXES := ["F2EDE3", "20334F", "FFB000", "B3261E"]  # SignageTokens: BONE_ENAMEL, INSTITUTIONAL_NAVY, SIGNAL_AMBER, SAFETY_RED
const CONTENT_ICON_FILES := ["items.json", "skills.json", "activities.json", "monsters.json", "recipes.json"]
const EXTRA_IDS := ["crowns", "category_food"]  # commissioned non-content marks: currency + food category
# T19 icon-grammar classes (naming-bible §14 ids; design-brief addendum
# "Icon grammar additions" is the binding silhouette contract). The first
# eight are consumed by shipped UI today; the last four are reserved for the
# run-2 tasks that own their consumers (T17 posting board / DEPUTIZE button,
# T18 orientation form) and must still ship + prove now.
const T19_IDS := ["stat_condition", "stat_accuracy", "stat_evade", "stat_max_hit",
	"stat_interval", "clearance_step", "deputy_badge", "orient_arrow",
	"stamp_check", "btn_engage", "btn_withdraw", "btn_deputize"]
const T19_UI_CONSUMED := ["stat_condition", "stat_accuracy", "stat_evade", "stat_max_hit",
	"stat_interval", "clearance_step", "btn_engage", "btn_withdraw",
	# T17 shipped the posting board: the badge pair + the deputize verb glyph
	# are live consumers now (moved off the reserved list).
	"deputy_badge", "btn_deputize"]
const T19_RESERVED := ["orient_arrow", "stamp_check"]
# T17: the badge's outline sibling (AVAILABLE state — the posting board's
# empty rows). Authored this task per the grammar's state-pair rule.
const T17_IDS := ["deputy_badge_outline"]
const EXPECTED_COUNT := 54

var checks := 0
var failures: Array[String] = []
var _capture_mode := false
var _done := false
var _icon_files: Array[String] = []


func _initialize() -> void:
	_capture_mode = "capture" in OS.get_cmdline_user_args()
	_list_icon_files()
	_check_content_icons_resolve()
	_check_loader_gate_is_strict()
	_check_svg_validity_and_self_containment()
	_check_grammar_tokens()
	_check_assets_gate()
	_check_commissioned_surface()
	_check_t19_surface()
	_check_textures_import()
	if _capture_mode:
		_capture_flow()  # coroutine: build gallery -> settle -> snap -> validate -> report
	else:
		_report_and_quit()


func _process(_delta: float) -> bool:
	return _done


# ------------------------------------------------------------------ discovery

func _list_icon_files() -> void:
	var d := DirAccess.open(ICONS_DIR)
	check(d != null, "assets/icons/ exists")
	if d == null:
		return
	d.list_dir_begin()
	var file := d.get_next()
	while not file.is_empty():
		if file.get_extension() == "svg":
			_icon_files.append(file.get_basename())
		file = d.get_next()
	d.list_dir_end()
	_icon_files.sort()
	check(_icon_files.size() == EXPECTED_COUNT,
		"icon set size is %d (got %d)" % [EXPECTED_COUNT, _icon_files.size()])


# ---------------------------------------------------- 1. content icon resolution

func _check_content_icons_resolve() -> void:
	var refs: Dictionary = {}  # icon id -> Array of record pointers
	for file_name in CONTENT_ICON_FILES:
		var path := "res://data/%s" % file_name
		var text := FileAccess.get_file_as_string(path)
		check(text != "", "content file readable: %s" % file_name)
		if text == "":
			continue
		var parsed: Variant = JSON.parse_string(text)
		check(typeof(parsed) == TYPE_DICTIONARY, "content file parses: %s" % file_name)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var doc: Dictionary = parsed
		var records: Variant = doc.values()[1] if doc.size() > 1 else null
		check(typeof(records) == TYPE_ARRAY, "content records array found: %s" % file_name)
		if typeof(records) != TYPE_ARRAY:
			continue
		for i in records.size():
			var rec: Dictionary = records[i]
			var pointer := "%s[%d]" % [file_name, i]
			if rec.has("id"):
				pointer = "%s (id=%s)" % [file_name, str(rec["id"])]
			elif rec.has("item"):
				pointer = "%s (item=%s)" % [file_name, str(rec["item"])]
			if rec.has("icon"):
				var icon := str(rec["icon"])
				if not refs.has(icon):
					refs[icon] = []
				refs[icon].append(pointer)
				check(FileAccess.file_exists("%s/%s.svg" % [ICONS_DIR, icon]),
					"icon resolves: '%s' referenced by %s -> %s/%s.svg" % [icon, pointer, ICONS_DIR, icon])
	check(refs.size() > 0, "content icon references collected (%d distinct ids)" % refs.size())
	for icon in refs:
		check(_icon_files.has(icon), "referenced icon '%s' is among shipped files" % icon)


# ------------------------------------------------- 2. loader strict-gate behavior

func _check_loader_gate_is_strict() -> void:
	# The live authored set must sail through the strict gate.
	var result := ContentLoader.load_all()
	check(result.ok(), "authored set passes the STRICT icon gate (errors: %s)" % str(result.errors))
	check(result.library != null, "authored set hydrates under the strict gate")

	# A dangling icon id must be rejected through the exact production path,
	# with an error naming record id + icon field + reason (T2 error grammar).
	var fixture := "user://t11_probe/dangling_icon"
	DirAccess.make_dir_recursive_absolute(fixture)
	for file_name in ProbeContent.DOMAIN_FILES:
		var text := FileAccess.get_file_as_string("res://data/%s" % file_name)
		check(text != "", "fixture source readable: %s" % file_name)
		if file_name == "monsters.json":
			var doc: Dictionary = JSON.parse_string(text)
			doc["monsters"][0]["icon"] = "trademark_infringing_mascot"
			text = JSON.stringify(doc, "\t")
		var write := FileAccess.open("%s/%s" % [fixture, file_name], FileAccess.WRITE)
		if write == null:
			check(false, "fixture writable: %s" % file_name)
			return
		write.store_string(text)
		write.close()
	var bad := ContentLoader.load_all(fixture)
	var cleanup := DirAccess.open(fixture)
	if cleanup != null:
		for file_name in ProbeContent.DOMAIN_FILES:
			cleanup.remove(file_name)
	var parent := DirAccess.open("user://t11_probe")
	if parent != null:
		parent.remove("dangling_icon")
	check(bad != null and not bad.ok(), "dangling icon id is rejected (ok() == false)")
	check(bad != null and bad.library == null, "dangling icon id hydrates no library")
	if bad != null:
		for err in bad.errors:
			print("    mutated-set error: " + err)
		check_contains(bad.errors, "monsters[junkyard_roach]", "icon-gate error names the record id")
		check_contains(bad.errors, "icon: does not resolve", "icon-gate error names the icon field + reason")
		check_contains(bad.errors, "assets/icons/trademark_infringing_mascot.svg", "icon-gate error names the expected asset path")


# ------------------------------------------- 3+4. SVG validity + grammar + safety

func _check_svg_validity_and_self_containment() -> void:
	for icon in _icon_files:
		var path := "%s/%s.svg" % [ICONS_DIR, icon]
		var text := FileAccess.get_file_as_string(path)
		check(text != "", "%s.svg readable" % icon)
		if text == "":
			continue
		var trimmed := text.strip_edges()

		# Angle-bracket structure + closing svg tag (minimum parse bar).
		check(trimmed.begins_with("<svg"), "%s.svg opens with a <svg root tag" % icon)
		check(trimmed.ends_with("</svg>"), "%s.svg closes with </svg>" % icon)
		check(count_occurrences(trimmed, "<") == count_occurrences(trimmed, ">"),
			"%s.svg angle brackets balance" % icon)
		check(count_occurrences(trimmed, "<svg") == 1, "%s.svg has exactly one <svg root" % icon)
		var has_draw := false
		for tag in ["<path", "<rect", "<circle", "<ellipse", "<line", "<polyline", "<polygon"]:
			if tag in text:
				has_draw = true
				break
		check(has_draw, "%s.svg contains at least one draw element" % icon)

		# No external references: self-contained paths only. The W3C xmlns
		# namespace declaration is a namespace identifier, never fetched —
		# it is the one http string allowed in a standalone SVG.
		var lower := text.to_lower()
		var http_free := text.replace(W3C_SVG_NAMESPACE, "").to_lower()
		check(not ("http://" in http_free or "https://" in http_free),
			"%s.svg contains no external http(s) URLs (only the xmlns namespace id)" % icon)
		check(not ("href" in lower), "%s.svg contains no href references" % icon)
		check(not ("xlink" in lower), "%s.svg contains no xlink references" % icon)
		check(not ("<image" in lower), "%s.svg contains no <image> elements" % icon)


func _check_grammar_tokens() -> void:
	var re := RegEx.new()
	re.compile("#[0-9A-Fa-f]{6}\\b")
	for icon in _icon_files:
		var path := "%s/%s.svg" % [ICONS_DIR, icon]
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			continue
		check('viewBox="0 0 128 128"' in text, "%s.svg uses the shared 128x128 viewBox" % icon)
		check(not ("gradient" in text.to_lower()), "%s.svg uses no gradients" % icon)
		check(not ("<text" in text.to_lower()), "%s.svg contains no <text> (stencil glyphs only)" % icon)
		var used: Array[String] = []
		for m in re.search_all(text):
			var hex := String(m.get_string()).substr(1).to_upper()
			if not used.has(hex):
				used.append(hex)
		check(used.size() >= 2 and used.size() <= 4,
			"%s.svg uses 2-4 token colors (got %d: %s)" % [icon, used.size(), ", ".join(used)])
		for hex in used:
			check(TOKEN_HEXES.has(hex),
				"%s.svg color #%s is a SignageTokens palette hex (bone/navy/amber/red)" % [icon, hex])
		# Set identity: every icon carries the enamel platelet (bone ground + navy ink).
		check("#F2EDE3" in text and "#20334F" in text,
			"%s.svg carries bone enamel + navy ink (shared plate grammar)" % icon)


# ------------------------------------------------------- 5. ASSETS.md gate

func _check_assets_gate() -> void:
	var text := FileAccess.get_file_as_string("res://ASSETS.md")
	check(text != "", "ASSETS.md exists at repo root")
	if text == "":
		return
	# No row, no ship: every icon file has exactly one row.
	for icon in _icon_files:
		var rel := "assets/icons/%s.svg" % icon
		var row_count := count_occurrences(text, "| %s |" % rel)
		check(row_count == 1, "ASSETS.md has exactly one row for %s (got %d)" % [rel, row_count])
	# Every icon row is an original-source row and resolves to a real file.
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if not line.begins_with("| assets/icons/"):
			continue
		var rel := String(line.split("|")[1]).strip_edges()
		check(FileAccess.file_exists("res://" + rel), "ASSETS.md icon row resolves: %s" % rel)
		check("| original | original |" in line, "ASSETS.md icon row sources %s as original" % rel)


# ------------------------------------------------ 6. commissioned surface

func _check_commissioned_surface() -> void:
	var surface := {
		"skill plate": ["scavenging", "foraging", "junksmithing", "cooking", "wasteland_combat"],
		"currency": ["crowns"],
		"category mark": ["category_food"],
	}
	for kind in surface:
		for icon in surface[kind]:
			check(_icon_files.has(icon), "%s '%s' ships in the set" % [kind, icon])
	# 21 items / 5 monsters / 8 activities come from content (check 1); assert
	# their counts against the loader's hydrated library.
	var lib := ContentLoader.load_all().library
	if lib != null:
		check(lib.items.size() == 21, "21 item icons commissioned (library items: %d)" % lib.items.size())
		check(lib.monsters.size() == 5, "5 monster icons commissioned (library monsters: %d)" % lib.monsters.size())
		check(lib.activities.size() == 8, "8 activity icons commissioned (library activities: %d)" % lib.activities.size())


# ------------------------------------------- 6b. T19 icon-grammar surface
## The five glyph classes of the design-brief addendum: every reserved id
## ships, the ink rules hold per class (navy stat/clearance linework, amber
## verb/cue ink, red stamp ink, FILLED deputy badge), and the ids the shipped
## UI consumes are actually referenced from the UI source.
func _check_t19_surface() -> void:
	for icon in T19_IDS:
		check(_icon_files.has(icon), "T19 glyph '%s' ships in the set" % icon)

	for icon in T19_IDS:
		var text := FileAccess.get_file_as_string("%s/%s.svg" % [ICONS_DIR, icon])
		if text == "":
			continue
		if icon.begins_with("stat_") or icon == "clearance_step":
			check(not ("#FFB000" in text) and not ("#B3261E" in text),
				"%s carries navy-only linework (stat/clearance classes)" % icon)
		if icon.begins_with("btn_") or icon == "orient_arrow":
			check("#FFB000" in text, "%s carries amber ink (verb/cue class)" % icon)
		if icon == "stamp_check":
			check("#B3261E" in text, "stamp_check carries red stamp ink (PaperStamp idiom)")
		if icon == "deputy_badge":
			check('fill="#20334F"' in text,
				"deputy_badge ships the FILLED state (ASSIGNED — fill, not color)")
		if icon == "deputy_badge_outline":
			# The state pair is the FILL on an otherwise identical silhouette:
			# the tag body must be bone (outline), never navy-filled.
			var body := 'd="M 38 42 H 90 L 96 48 V 96 Q 96 102 90 102 H 38 Q 32 102 32 96 V 48 Z"'
			check(body in text and 'fill="#F2EDE3"' in text,
				"deputy_badge_outline ships the OUTLINE state (bone body = AVAILABLE)")
			check(not ('<path d="M 38 42 H 90 L 96 48 V 96 Q 96 102 90 102 H 38 Q 32 102 32 96 V 48 Z" fill="#20334F"' in text),
				"deputy_badge_outline never navy-fills the tag body (that is the ASSIGNED glyph)")
		# The clearance glyph is a staircase, NEVER a padlock: the silhouette
		# contract pins the three-step rise as the file's only closed form.
		if icon == "clearance_step":
			check(text.count("<path") == 1 and "L 52 82" in text and "L 78 64" in text,
				"clearance_step is the rising three-step staircase (no padlock silhouette)")

	# The consumed half must be wired into shipped UI source (grep the id).
	var ui_sources := ""
	for dir_path in ["res://scripts/ui", "res://scenes"]:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var file := d.get_next()
		while not file.is_empty():
			if file.get_extension() == "gd":
				ui_sources += FileAccess.get_file_as_string("%s/%s" % [dir_path, file])
			file = d.get_next()
		d.list_dir_end()
	for icon in T19_UI_CONSUMED:
		check(ui_sources.contains("\"%s\"" % icon),
			"T19 glyph '%s' is referenced by shipped UI source" % icon)
	for icon in T19_RESERVED:
		check(not ui_sources.contains("\"%s\"" % icon),
			"T19 reserved glyph '%s' waits for its T17/T18 consumer (no stray wiring)" % icon)


# ------------------------------------------------ 7. import as textures

func _check_textures_import() -> void:
	for icon in _icon_files:
		var tex := load("%s/%s.svg" % [ICONS_DIR, icon]) as Texture2D
		check(tex != null, "%s.svg imports as a Texture2D" % icon)
		if tex == null:
			continue
		check(Vector2i(tex.get_width(), tex.get_height()) == Vector2i(128, 128),
			"%s.svg texture is 128x128 (got %dx%d)" % [icon, tex.get_width(), tex.get_height()])


# ------------------------------------------------------------------ capture

func _capture_flow() -> void:
	await _frames(2)  # let the tree settle before composing the gallery
	if not _build_gallery():
		return  # already reporting failure
	await _frames(6)  # render target settles after resize/layout
	if not _snap_gallery():
		return  # already quitting CAPTURE_UNSUPPORTED_EXIT for the runner
	_validate_saved_png()
	if not _build_t19_size_board():
		return
	await _frames(6)
	if not _snap_t19_sizes():
		return
	_validate_t19_sizes_png()
	_report_and_quit()


func _build_gallery() -> bool:
	if DirAccess.make_dir_recursive_absolute(REVIEW_DIR) != OK:
		check(false, "review dir created: %s" % REVIEW_DIR)

	# Composite gallery on a steel-deep ground so the enamel platelets read.
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = SignageTokens.STEEL_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	root_ctrl.add_child(margin)

	var col := VBoxContainer.new()
	margin.add_child(col)
	var title := Label.new()
	title.text = "ICON SET - %d ORIGINAL SVG (%d CONTENT-REFERENCED + CROWNS + FOOD MARK + 12 T19 GLYPHS + 1 T17 OUTLINE SIBLING)" % [
		_icon_files.size(), _icon_files.size() - EXTRA_IDS.size() - T19_IDS.size() - T17_IDS.size()]
	title.add_theme_color_override("font_color", SignageTokens.BONE_ENAMEL)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for icon in _icon_files:
		var cell := TextureRect.new()
		cell.texture = load("%s/%s.svg" % [ICONS_DIR, icon]) as Texture2D
		cell.custom_minimum_size = Vector2(140, 86)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.tooltip_text = icon
		check(cell.texture != null, "gallery cell has a texture: %s" % icon)
		grid.add_child(cell)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(root_ctrl)
	_gallery_vp = vp
	return true


var _gallery_vp: SubViewport


func _snap_gallery() -> bool:
	if _gallery_vp == null:
		check(false, "gallery viewport was built")
		return false
	var img := _gallery_vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		return false
	var err := img.save_png("%s/%s" % [REVIEW_DIR, CAPTURE_PNG])
	check(err == OK, "captured %s/%s (err=%d)" % [REVIEW_DIR, CAPTURE_PNG, err])
	return true


func _validate_saved_png() -> void:
	var path := "%s/%s" % [REVIEW_DIR, CAPTURE_PNG]
	var fa := FileAccess.open(path, FileAccess.READ)
	check(fa != null and fa.get_length() > 0, "%s saved with size > 0" % CAPTURE_PNG)
	if fa == null:
		return
	fa.close()
	var img := Image.load_from_file(path)
	check(img != null, "%s is a loadable image" % CAPTURE_PNG)
	if img == null:
		return
	check(Vector2i(img.get_width(), img.get_height()) == Vector2i(1280, 720),
		"%s dimensions %dx%d" % [CAPTURE_PNG, img.get_width(), img.get_height()])
	var colors := {}
	for x in range(0, img.get_width(), 8):
		for y in range(0, img.get_height(), 8):
			colors[img.get_pixel(x, y).to_html(true)] = true
	check(colors.size() >= 8, "%s renders real content (%d distinct sampled colors)" % [
		CAPTURE_PNG, colors.size()])
	check(colors.has(SignageTokens.STEEL_DEEP.to_html(true)), "%s shows the steel-deep gallery ground" % CAPTURE_PNG)
	check(colors.has(SignageTokens.BONE_ENAMEL.to_html(true)), "%s shows bone enamel platelets" % CAPTURE_PNG)
	# Every icon must be fully on-canvas: detect the bone-enamel badge rows and
	# require complete grid rows (54 icons / 8 columns = 7 rows), none clipped
	# at the bottom edge. The title band (text, not badges) is the first run.
	var bone_rows: Array[int] = []
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).is_equal_approx(SignageTokens.BONE_ENAMEL):
				bone_rows.append(y)
				break
	check(bone_rows.size() > 0, "%s shows badge rows (bone pixels found)" % CAPTURE_PNG)
	if not bone_rows.is_empty():
		var runs: Array = []  # [start, end] index pairs into bone_rows
		var run_start := 0
		for i in range(1, bone_rows.size()):
			if bone_rows[i] - bone_rows[i - 1] > 10:
				runs.append([bone_rows[run_start], bone_rows[i - 1]])
				run_start = i
		runs.append([bone_rows[run_start], bone_rows[bone_rows.size() - 1]])
		var grid_rows := runs.size() - 1  # minus the title text band
		check(grid_rows == 7, "%s shows 7 complete badge rows (got %d bands incl. title)" % [
			CAPTURE_PNG, runs.size()])
		var last_end: int = runs[runs.size() - 1][1]
		check(last_end <= img.get_height() - 8,
			"%s last badge row ends %dpx from the bottom edge — nothing clipped" % [
				CAPTURE_PNG, img.get_height() - 8 - last_end])


# --------------------------------------------- T19 legibility capture (48 + 20 px)
## The T19 acceptance: the twelve grammar glyphs must read at their inline
## size. One board, three bands: 48 px (glyph study), 20 px (inline size),
## and the real inline idiom ([glyph][mono value] segments on steel-deep,
## exactly how the dockets render them).
func _build_t19_size_board() -> bool:
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = SignageTokens.STEEL_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	root_ctrl.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(_board_label("T19 GLYPH LEGIBILITY - %d GLYPHS AT 48 PX AND 20 PX" % T19_IDS.size(), true))

	col.add_child(_board_label("GLYPHS AT 48 PX", false))
	var flow48 := HFlowContainer.new()
	flow48.add_theme_constant_override("h_separation", 14)
	flow48.add_theme_constant_override("v_separation", 8)
	col.add_child(flow48)
	for icon in T19_IDS:
		flow48.add_child(_glyph_cell(icon, 48))

	col.add_child(_board_label("GLYPHS AT 20 PX (INLINE SIZE)", false))
	var flow20 := HFlowContainer.new()
	flow20.add_theme_constant_override("h_separation", 14)
	flow20.add_theme_constant_override("v_separation", 8)
	col.add_child(flow20)
	for icon in T19_IDS:
		flow20.add_child(_glyph_cell(icon, 20))

	col.add_child(_board_label("INLINE IDIOM - GLYPH BEFORE ITS MONO VALUE (AS THE DOCKETS POST IT)", false))
	var demo := HFlowContainer.new()
	demo.add_theme_constant_override("h_separation", 18)
	demo.add_theme_constant_override("v_separation", 10)
	col.add_child(demo)
	for pair in [["stat_condition", "HP 18"], ["stat_accuracy", "ACC 15"],
			["stat_evade", "EVA 4"], ["stat_max_hit", "HIT 0-2"],
			["stat_interval", "EVERY 2.8 S"], ["clearance_step", "CLEARANCE 5 REQUIRED"],
			["crowns", "24 CROWNS"]]:
		var seg := HBoxContainer.new()
		seg.add_theme_constant_override("separation", 6)
		seg.add_child(_glyph_cell(String(pair[0]), 20))
		var l := Label.new()
		l.text = String(pair[1])
		l.add_theme_color_override("font_color", SignageTokens.BONE_ENAMEL)
		seg.add_child(l)
		demo.add_child(seg)

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(root_ctrl)
	_t19_vp = vp
	return true


func _board_label(text: String, big := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color",
		SignageTokens.SIGNAL_AMBER if big else SignageTokens.BONE_DIM)
	if big:
		l.add_theme_font_size_override("font_size", 22)
	return l


func _glyph_cell(icon: String, px: int) -> TextureRect:
	var cell := TextureRect.new()
	cell.name = "Glyph%d_%s" % [px, icon]
	cell.texture = load("%s/%s.svg" % [ICONS_DIR, icon]) as Texture2D
	cell.custom_minimum_size = Vector2(float(px), float(px))
	cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cell.tooltip_text = icon
	check(cell.texture != null, "T19 board cell has a texture: %s @%dpx" % [icon, px])
	return cell


var _t19_vp: SubViewport


func _snap_t19_sizes() -> bool:
	if _t19_vp == null:
		check(false, "T19 size board was built")
		return false
	var img := _t19_vp.get_texture().get_image()
	if img == null:
		print("HEADLESS_CAPTURE_UNSUPPORTED (dummy rasterizer returned no image)")
		quit(CAPTURE_UNSUPPORTED_EXIT)
		_done = true
		return false
	var err := img.save_png("%s/%s" % [REVIEW_DIR, T19_CAPTURE_PNG])
	check(err == OK, "captured %s/%s (err=%d)" % [REVIEW_DIR, T19_CAPTURE_PNG, err])
	return true


func _validate_t19_sizes_png() -> void:
	var path := "%s/%s" % [REVIEW_DIR, T19_CAPTURE_PNG]
	var img := Image.load_from_file(path)
	check(img != null, "%s is a loadable image" % T19_CAPTURE_PNG)
	if img == null:
		return
	check(Vector2i(img.get_width(), img.get_height()) == Vector2i(1280, 720),
		"%s dimensions %dx%d" % [T19_CAPTURE_PNG, img.get_width(), img.get_height()])
	# Both size bands must render real platelets: classify COLUMNS by their
	# bone + navy content — a tile column carries a bone run plus the navy
	# top/bottom borders (text columns carry bone but no navy; the ground
	# carries neither). 48 px tiles yield tall bone columns, 20 px tiles
	# short ones, so both bands are proven present and distinct.
	var saw_48 := false
	var saw_20 := false
	var cols_48 := 0
	var cols_20 := 0
	for x in range(img.get_width()):
		var bone := 0
		var navy := 0
		for y in range(img.get_height()):
			var px := img.get_pixel(x, y)
			if px.is_equal_approx(SignageTokens.BONE_ENAMEL):
				bone += 1
			elif px.is_equal_approx(SignageTokens.INSTITUTIONAL_NAVY):
				navy += 1
		if bone >= 30 and bone <= 52 and navy >= 3:
			cols_48 += 1
		elif bone >= 10 and bone <= 26 and navy >= 2:
			cols_20 += 1
	check(cols_48 >= 24, "%s renders the 48 px glyph band (%d tile columns found)" % [T19_CAPTURE_PNG, cols_48])
	check(cols_20 >= 24, "%s renders the 20 px glyph band (%d tile columns found)" % [T19_CAPTURE_PNG, cols_20])
	var colors := {}
	for x in range(0, img.get_width(), 6):
		for y in range(0, img.get_height(), 6):
			colors[img.get_pixel(x, y).to_html(true)] = true
	check(colors.has(SignageTokens.STEEL_DEEP.to_html(true)),
		"%s shows the steel-deep board ground" % T19_CAPTURE_PNG)
	check(colors.has(SignageTokens.INSTITUTIONAL_NAVY.to_html(true)),
		"%s shows navy stencil ink" % T19_CAPTURE_PNG)


# ------------------------------------------------------------------ helpers

func count_occurrences(haystack: String, needle: String) -> int:
	var count := 0
	var idx := haystack.find(needle)
	while idx != -1:
		count += 1
		idx = haystack.find(needle, idx + needle.length())
	return count


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("  FAIL: " + label)


func check_contains(haystack: Array[String], needle: String, label: String) -> void:
	check(haystack.any(func(e: String) -> bool: return e.contains(needle)),
		"%s — expected an entry containing: %s" % [label, needle])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _report_and_quit() -> void:
	_done = true
	if failures.is_empty():
		print("PROBE_OK checks=%d (content icons resolve through the strict gate; SVGs valid + self-contained; tokens + grammar hold; ASSETS.md gate clean; T19 grammar surface verified; %d icons import)" % [
			checks, _icon_files.size()])
		quit(0)
	else:
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for f in failures:
			printerr("  - " + f)
		quit(1)
