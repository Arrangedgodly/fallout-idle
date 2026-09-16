class_name SignageTheme
extends RefCounted
# ------------------------------------------------------------------------------
# DIRECTION CONTRACT (impeccable new-work section 5)
#
# THESIS: The whole game is a bomb shelter's institutional signage system — a
# bureaucracy that survived the apocalypse and never stopped issuing cheerful
# directives. Refuses the idle-category default (dark admin dashboard, green
# XP bars) and its predictable opposite (glowing green CRT terminal).
#
# OWN-WORLD: Bone-white enamel over rolled steel; institutional navy as the
# structural ink; amber the only energized signal, red the only danger.
# Riveted steel panels, perforated vent grids, posted paper notices, stenciled
# caps, mono serials. Recognizable with all content removed.
#
# STORY: The player reads the shelter like a resident following signage.
# Clearances gate content; offline gains post as a MAIL CALL notice; combat
# death posts a red RETURN TO SHELTER plate and the fight stops.
#
# FIRST VIEWPORT: The concourse — a wall of department plates behind a
# half-open bulkhead, the active plate energized (amber, swells forward), its
# docket filling the right two-thirds; the big stenciled button starts the work.
#
# FORM: Institutional signage — position 1 of 7, seed key 48bdddd6, user pick
# over roll.
#
# FINISH: unreviewed and undocumented is unfinished; this build ends with the
# finish review, the verdict, DESIGN.md, and every shipping raster carrying
# its provenance.
# ------------------------------------------------------------------------------
#
## T8 — The Shelter Signage System, theme builder.
##
## build() returns the complete Theme (fonts, StyleBox library, component
## states, type variations). The generated resource is committed at
## assets/theme/signage_theme.tres (via scripts/theme/generate_theme.gd);
## scenes reference that .tres. Font-scale support: every font size the theme
## sets is registered in FONT_SIZE_BASES; apply_font_scale() re-sets them all
## (base x scale), so one call resizes every text element (Daredevil claim).

# --- font files (OFL; provenance in /ASSETS.md) ------------------------------
const F_STENCIL_SEMIBOLD := "res://assets/fonts/big-shoulders-stencil-display/BigShouldersStencilDisplay-SemiBold.ttf"
const F_STENCIL_BOLD := "res://assets/fonts/big-shoulders-stencil-display/BigShouldersStencilDisplay-Bold.ttf"
const F_BODY_REGULAR := "res://assets/fonts/public-sans/PublicSans-Regular.ttf"
const F_BODY_SEMIBOLD := "res://assets/fonts/public-sans/PublicSans-SemiBold.ttf"
const F_BODY_BOLD := "res://assets/fonts/public-sans/PublicSans-Bold.ttf"
const F_MONO_REGULAR := "res://assets/fonts/courier-prime/CourierPrime-Regular.ttf"
const F_MONO_BOLD := "res://assets/fonts/courier-prime/CourierPrime-Bold.ttf"

const TEXTURES := "res://assets/theme/"

# Every theme font size, [type_or_variation, base_control_type, base_size].
# base_control_type "" = real engine type. apply_font_scale() walks this table.
const FONT_SIZE_BASES := [
	["Label", "", 16],
	["PlateTitle", "Label", 26],
	["PlateTitleEnergized", "Label", 26],
	["PlateTitleDanger", "Label", 26],
	["PlateSerial", "Label", 13],
	["PlateSerialNavy", "Label", 13],
	["SectionLabel", "Label", 19],
	["MicroLabel", "Label", 12],
	["BodyCopy", "Label", 15],
	["BodyCopyDim", "Label", 14],
	["PlateBody", "Label", 13],
	["PlateBodyEnergized", "Label", 13],
	["PaperText", "Label", 14],
	["PaperStamp", "Label", 13],
	["MonoValue", "Label", 17],
	["MonoValueEnergized", "Label", 17],
	["MonoBig", "Label", 26],
	["Button", "", 18],
	["Energized", "Button", 18],
	["Danger", "Button", 18],
	["CheckButton", "", 15],
	["OptionButton", "", 15],
	["LineEdit", "", 15],
	["PopupMenu", "", 14],
	["ItemList", "", 15],
	["ProgressBar", "", 13],
	["TooltipLabel", "", 13],
	["TabContainer", "", 18],
]

static func build() -> Theme:
	var t := SignageTokens
	var th := Theme.new()

	# -- fonts ---------------------------------------------------------------
	var f_plate := _tracked(load(F_STENCIL_SEMIBOLD), 1.0)
	var f_plate_title := _tracked(load(F_STENCIL_BOLD), 1.25)
	var f_body := load(F_BODY_REGULAR) as Font
	var f_body_b := load(F_BODY_BOLD) as Font
	var f_micro := _tracked(load(F_BODY_SEMIBOLD), 2.5)
	var f_stamp := _tracked(load(F_BODY_BOLD), 1.5)
	var f_mono := load(F_MONO_REGULAR) as Font
	var f_mono_b := load(F_MONO_BOLD) as Font

	th.default_font = f_body
	th.default_font_size = 15

	# -- Label base + variations ---------------------------------------------
	th.set_font("font", "Label", f_body)
	th.set_color("font_color", "Label", t.BONE_ENAMEL)
	_label_var(th, "PlateTitle", f_plate_title, t.INSTITUTIONAL_NAVY)
	_label_var(th, "PlateTitleEnergized", f_plate_title, t.SIGNAL_AMBER)
	_label_var(th, "PlateTitleDanger", f_plate_title, t.BONE_ENAMEL)
	_label_var(th, "PlateSerial", f_mono, t.BONE_DIM)
	_label_var(th, "PlateSerialNavy", f_mono, t.INSTITUTIONAL_NAVY)
	_label_var(th, "SectionLabel", f_plate, t.BONE_ENAMEL)
	_label_var(th, "MicroLabel", f_micro, t.BONE_DIM)
	_label_var(th, "BodyCopy", f_body, t.BONE_ENAMEL)
	_label_var(th, "BodyCopyDim", f_body, t.BONE_DIM)
	_label_var(th, "PlateBody", f_body, t.INSTITUTIONAL_NAVY)
	_label_var(th, "PlateBodyEnergized", f_body, t.SIGNAL_AMBER)
	_label_var(th, "PaperText", f_body, t.INSTITUTIONAL_NAVY)
	_label_var(th, "PaperStamp", f_stamp, t.SAFETY_RED)
	_label_var(th, "MonoValue", f_mono, t.BONE_ENAMEL)
	_label_var(th, "MonoValueEnergized", f_mono_b, t.SIGNAL_AMBER)
	_label_var(th, "MonoBig", f_mono_b, t.BONE_ENAMEL)

	# -- Panel + variations (the material library) ----------------------------
	th.set_stylebox("panel", "Panel", _steel_flat())
	th.set_stylebox("panel", "EnamelPlate", _enamel_plate())
	th.set_stylebox("panel", "EnergizedPlate", _energized_plate())
	th.set_stylebox("panel", "DangerPlate", _danger_plate())
	th.set_stylebox("panel", "SteelPanel", _riveted_panel())
	th.set_stylebox("panel", "VentHousing", _vent_housing())
	th.set_stylebox("panel", "PaperNotice", _paper_notice())
	th.set_type_variation("EnamelPlate", "Panel")
	th.set_type_variation("EnergizedPlate", "Panel")
	th.set_type_variation("DangerPlate", "Panel")
	th.set_type_variation("SteelPanel", "Panel")
	th.set_type_variation("VentHousing", "Panel")
	th.set_type_variation("PaperNotice", "Panel")

	# -- Button (stenciled button plate) + variations -------------------------
	_button_states(th, "Button", {
		normal_bg = t.BONE_ENAMEL, border = t.INSTITUTIONAL_NAVY, border_w = 2,
		font_color = t.INSTITUTIONAL_NAVY,
		shadow = Color(0.063, 0.094, 0.161, 0.35),
	})
	_button_states(th, "Energized", {
		normal_bg = t.INSTITUTIONAL_NAVY, border = t.SIGNAL_AMBER, border_w = 3,
		font_color = t.SIGNAL_AMBER,
		shadow = Color(t.SIGNAL_AMBER, 0.25),
		hover_bg = t.NAVY_HI,
	})
	_button_states(th, "Danger", {
		normal_bg = t.SAFETY_RED, border = t.BONE_ENAMEL, border_w = 2,
		font_color = t.BONE_ENAMEL,
		shadow = Color(0.094, 0.02, 0.02, 0.4),
		hover_bg = Color("#C22F28"),
	})
	th.set_type_variation("Energized", "Button")
	th.set_type_variation("Danger", "Button")
	th.set_font("font", "Button", f_plate)
	th.set_font("font", "Energized", f_plate)
	th.set_font("font", "Danger", f_plate)

	# -- CheckButton (toggle) --------------------------------------------------
	th.set_font("font", "CheckButton", f_body)
	th.set_color("font_color", "CheckButton", t.BONE_ENAMEL)
	th.set_color("font_hover_color", "CheckButton", t.BONE_ENAMEL)
	th.set_color("font_pressed_color", "CheckButton", t.BONE_ENAMEL)
	th.set_color("font_disabled_color", "CheckButton", t.BONE_DIM)
	th.set_stylebox("normal", "CheckButton", _chrome())
	th.set_stylebox("hover", "CheckButton", _chrome(Color(t.BONE_ENAMEL, 0.05)))
	th.set_stylebox("pressed", "CheckButton", _chrome(Color(t.BONE_ENAMEL, 0.08)))
	th.set_stylebox("disabled", "CheckButton", _chrome())
	th.set_stylebox("focus", "CheckButton", _focus_ring())
	th.set_icon("unchecked", "CheckButton", load(TEXTURES + "toggle_off.svg"))
	th.set_icon("checked", "CheckButton", load(TEXTURES + "toggle_on.svg"))

	# -- OptionButton + PopupMenu (posted-form dropdown) ------------------------
	th.set_font("font", "OptionButton", f_body)
	th.set_color("font_color", "OptionButton", t.INSTITUTIONAL_NAVY)
	th.set_color("font_hover_color", "OptionButton", t.INSTITUTIONAL_NAVY)
	th.set_color("font_pressed_color", "OptionButton", t.INSTITUTIONAL_NAVY)
	th.set_color("font_disabled_color", "OptionButton", t.BONE_DIM)
	th.set_stylebox("normal", "OptionButton", _enamel_plate(16, 8))
	th.set_stylebox("hover", "OptionButton", _hover_plate(16, 8))
	th.set_stylebox("pressed", "OptionButton", _pressed_plate(16, 8))
	th.set_stylebox("disabled", "OptionButton", _disabled_plate(16, 8))
	th.set_stylebox("focus", "OptionButton", _focus_ring())
	th.set_icon("arrow", "OptionButton", null)

	th.set_font("font", "PopupMenu", f_body)
	th.set_color("font_color", "PopupMenu", t.INSTITUTIONAL_NAVY)
	th.set_color("font_hover_color", "PopupMenu", t.BONE_ENAMEL)
	th.set_color("font_pressed_color", "PopupMenu", t.BONE_ENAMEL)
	th.set_color("font_disabled_color", "PopupMenu", t.NAVY_DIM)
	th.set_font_size("font_size", "PopupMenu", 14)
	th.set_stylebox("panel", "PopupMenu", _paper_notice(14, 8))
	th.set_stylebox("hover", "PopupMenu", _menu_hover())
	th.set_stylebox("pressed", "PopupMenu", _menu_hover())
	th.set_stylebox("focus", "PopupMenu", _focus_ring())
	th.set_stylebox("separator", "PopupMenu", _separator())

	# -- LineEdit / TextEdit (recessed input) -----------------------------------
	th.set_font("font", "LineEdit", f_body)
	th.set_font_size("font_size", "LineEdit", 15)
	th.set_color("font_color", "LineEdit", t.BONE_ENAMEL)
	th.set_color("font_placeholder_color", "LineEdit", t.BONE_DIM)
	th.set_color("caret_color", "LineEdit", t.SIGNAL_AMBER)
	th.set_color("selection_color", "LineEdit", Color(t.SIGNAL_AMBER, 0.30))
	th.set_color("font_selected_color", "LineEdit", t.BONE_ENAMEL)
	th.set_stylebox("normal", "LineEdit", _inset())
	th.set_stylebox("focus", "LineEdit", _inset_focus())
	th.set_stylebox("read_only", "LineEdit", _disabled_plate(12, 8))
	th.set_font("font", "TextEdit", f_body)
	th.set_color("font_color", "TextEdit", t.BONE_ENAMEL)
	th.set_color("caret_color", "TextEdit", t.SIGNAL_AMBER)
	th.set_stylebox("normal", "TextEdit", _inset())
	th.set_stylebox("focus", "TextEdit", _inset_focus())

	# -- ProgressBar (enamel gauge) ---------------------------------------------
	th.set_stylebox("background", "ProgressBar", _gauge_track())
	th.set_stylebox("fill", "ProgressBar", _gauge_fill())
	th.set_font("font", "ProgressBar", f_mono)
	th.set_font_size("font_size", "ProgressBar", 13)
	th.set_color("font_color", "ProgressBar", t.BONE_DIM)

	# -- ItemList (stamped drop lines) ------------------------------------------
	th.set_font("font", "ItemList", f_mono)
	th.set_font_size("font_size", "ItemList", 15)
	th.set_color("font_color", "ItemList", t.BONE_ENAMEL)
	th.set_color("font_selected_color", "ItemList", t.BONE_ENAMEL)
	th.set_color("font_hovered_color", "ItemList", t.BONE_ENAMEL)
	th.set_color("guide_color", "ItemList", Color(t.STEEL_HI, 0.5))
	th.set_stylebox("panel", "ItemList", _inset(2))
	th.set_stylebox("focus", "ItemList", _focus_ring())
	th.set_stylebox("selected", "ItemList", _menu_hover())
	th.set_stylebox("selected_focus", "ItemList", _menu_hover())
	th.set_stylebox("hovered", "ItemList", _hover_row())

	# -- Tabs (department dockets) ------------------------------------------------
	th.set_font("font", "TabContainer", f_plate)
	th.set_font_size("font_size", "TabContainer", 18)
	th.set_font("font", "TabBar", f_plate)
	th.set_color("font_color", "TabBar", t.BONE_DIM)
	th.set_color("font_selected_color", "TabBar", t.INSTITUTIONAL_NAVY)
	th.set_color("font_hover_color", "TabBar", t.BONE_ENAMEL)
	th.set_stylebox("tab_selected", "TabBar", _tab_selected())
	th.set_stylebox("tab_unselected", "TabBar", _tab_unselected())
	th.set_stylebox("tab_hovered", "TabBar", _tab_unselected(Color(t.STEEL_HI, 0.35)))
	th.set_stylebox("tab_disabled", "TabBar", _tab_unselected())
	th.set_stylebox("panel", "TabContainer", _steel_flat())
	th.set_stylebox("content", "TabContainer", _steel_flat())

	# -- ScrollBars (thin steel; amber when grabbed) -------------------------------
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = t.STEEL_HI
	grabber.corner_radius_bottom_left = 4
	grabber.corner_radius_bottom_right = 4
	grabber.corner_radius_top_left = 4
	grabber.corner_radius_top_right = 4
	grabber.content_margin_left = 2
	grabber.content_margin_right = 2
	var grabber_hi := grabber.duplicate() as StyleBoxFlat
	grabber_hi.bg_color = t.SIGNAL_AMBER
	var grabber_pr := grabber.duplicate() as StyleBoxFlat
	grabber_pr.bg_color = t.BONE_ENAMEL
	var bar_bg := _chrome()
	for sb_type in ["HScrollBar", "VScrollBar"]:
		th.set_stylebox("scroll", sb_type, bar_bg)
		th.set_stylebox("grabber", sb_type, grabber)
		th.set_stylebox("grabber_highlight", sb_type, grabber_hi)
		th.set_stylebox("grabber_pressed", sb_type, grabber_pr)

	# -- Sliders (settings console gauge; added by T9, same material rules) ------
	# The font-scale control reads as a recessed gauge: steel-deep inset track,
	# amber fill behind the grabber (the registered UI-accent pair), enamel
	# grabber plate with navy border; amber when lit.
	for sb_type in ["HSlider", "VSlider"]:
		th.set_stylebox("slider", sb_type, _slider_track())
		th.set_stylebox("grabber_area", sb_type, _gauge_fill())
		th.set_stylebox("grabber_area_highlight", sb_type, _gauge_fill())
		th.set_icon("grabber", sb_type, load(TEXTURES + "slider_grabber.svg"))
		th.set_icon("grabber_highlight", sb_type, load(TEXTURES + "slider_grabber_lit.svg"))
		th.set_icon("grabber_pressed", sb_type, load(TEXTURES + "slider_grabber_lit.svg"))
	# Slider draws no focus stylebox of its own; screens light the track border
	# via an override on focus enter (T9 concourse does this, probe asserts it).

	# -- Tooltips (posted paper) ----------------------------------------------------
	th.set_stylebox("panel", "TooltipPanel", _paper_notice(10, 6))
	th.set_font("font", "TooltipLabel", f_body)
	th.set_font_size("font_size", "TooltipLabel", 13)
	th.set_color("font_color", "TooltipLabel", t.INSTITUTIONAL_NAVY)

	# -- separators --------------------------------------------------------------------
	th.set_stylebox("separator", "HSeparator", _separator())
	th.set_stylebox("separator", "VSeparator", _separator(true))

	# -- font sizes from the registry (single source for scaling) -----------------------
	for entry in FONT_SIZE_BASES:
		th.set_font_size("font_size", entry[0], entry[2])
	return th

## Re-set every registered font size at base x scale. Call via UiTheme.
static func apply_font_scale(th: Theme, scale: float) -> void:
	for entry in FONT_SIZE_BASES:
		th.set_font_size("font_size", entry[0], roundi(entry[2] * scale))

# ------------------------------------------------------------------ fonts
static func _tracked(base: Font, glyph_spacing: float) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = glyph_spacing
	return fv

# ------------------------------------------------------------------ labels
static func _label_var(th: Theme, variant: String, font: Font, color: Color) -> void:
	th.set_type_variation(variant, "Label")
	th.set_font("font", variant, font)
	th.set_color("font_color", variant, color)

# ------------------------------------------------------------------ panels
static func _margins(sb: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb

static func _steel_flat() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.ROLLED_STEEL
	return sb

static func _enamel_plate(h: int = 14, v: int = 10) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.BONE_ENAMEL
	sb.border_color = t.INSTITUTIONAL_NAVY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0.063, 0.094, 0.161, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return _margins(sb, h, v)

static func _hover_plate(h: int = 14, v: int = 10) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := _enamel_plate(h, v)
	sb.border_color = t.SIGNAL_AMBER
	sb.shadow_color = Color(0.063, 0.094, 0.161, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	return sb

static func _pressed_plate(h: int = 14, v: int = 10) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := _enamel_plate(h, v)
	sb.border_color = t.SIGNAL_AMBER
	sb.shadow_color = Color(0.04, 0.06, 0.1, 0.3)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_top = v + 2
	sb.content_margin_bottom = v - 2
	return sb

static func _disabled_plate(h: int = 14, v: int = 10) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_DEEP
	sb.border_color = t.STEEL_LO
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	return _margins(sb, h, v)

static func _energized_plate() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.INSTITUTIONAL_NAVY
	sb.border_color = t.SIGNAL_AMBER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(3)
	sb.draw_center = true
	sb.shadow_color = Color(0.039, 0.07, 0.11, 0.55)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 6)
	return _margins(sb, 16, 12)

static func _danger_plate() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.SAFETY_RED
	sb.border_color = t.BONE_ENAMEL
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.shadow_color = Color(0.094, 0.02, 0.02, 0.4)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 5)
	return _margins(sb, 16, 12)

static func _riveted_panel() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(TEXTURES + "panel_steel_riveted.svg")
	sb.texture_margin_left = 16
	sb.texture_margin_right = 16
	sb.texture_margin_top = 16
	sb.texture_margin_bottom = 16
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb

static func _vent_housing() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_LO
	sb.border_color = t.STEEL_HI
	sb.border_width_bottom = 1
	sb.border_width_right = 1
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func _paper_notice(h: int = 16, v: int = 12) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.PAPER_NOTICE
	sb.border_color = Color("#D9CBA8")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 5)
	return _margins(sb, h, v)

# ------------------------------------------------------------------ inputs
static func _inset(extra: int = 0) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_DEEP
	sb.border_color = t.STEEL_LO
	sb.border_width_top = 2 + extra
	sb.border_width_left = 2 + extra
	sb.border_width_bottom = 1
	sb.border_width_right = 1
	sb.set_corner_radius_all(2)
	return _margins(sb, 10, 7)

static func _inset_focus() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := _inset()
	sb.border_color = t.SIGNAL_AMBER
	sb.set_border_width_all(2)
	return sb

static func _chrome(bg: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.draw_center = bg.a > 0.0
	return _margins(sb, 8, 4)

static func _focus_ring() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = t.SIGNAL_AMBER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_expand_margin_all(3)
	return sb

# ------------------------------------------------------------------ gauges
static func _gauge_track() -> StyleBoxFlat:
	var sb := _inset(1)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

static func _gauge_fill() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.SIGNAL_AMBER
	sb.set_corner_radius_all(1)
	return sb

# ------------------------------------------------------------------ sliders
static func _slider_track() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_DEEP
	sb.border_color = t.STEEL_LO
	sb.border_width_top = 2
	sb.border_width_left = 2
	sb.border_width_bottom = 1
	sb.border_width_right = 1
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

# ------------------------------------------------------------------ lists/tabs
static func _menu_hover() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.INSTITUTIONAL_NAVY
	return _margins(sb, 12, 5)

static func _hover_row() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(SignageTokens.INSTITUTIONAL_NAVY, 0.45)
	return _margins(sb, 10, 4)

static func _separator(vertical: bool = false) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_HI
	sb.draw_center = true
	if vertical:
		sb.content_margin_left = 1
		sb.content_margin_right = 1
	else:
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
	return sb

static func _tab_selected() -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.BONE_ENAMEL
	sb.border_color = t.INSTITUTIONAL_NAVY
	sb.set_border_width_all(2)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func _tab_unselected(bg: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var t := SignageTokens
	var sb := StyleBoxFlat.new()
	sb.bg_color = t.STEEL_DEEP if bg.a == 0.0 else bg
	sb.border_color = t.STEEL_LO
	sb.border_width_bottom = 2
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# ------------------------------------------------------------------ buttons
## Default/Active(hover+pressed)/Disabled/focus state set for one button class.
static func _button_states(th: Theme, type_name: String, cfg: Dictionary) -> void:
	var t := SignageTokens
	var normal := StyleBoxFlat.new()
	normal.bg_color = cfg.normal_bg
	normal.border_color = cfg.border
	normal.set_border_width_all(cfg.border_w)
	normal.set_corner_radius_all(3)
	normal.shadow_color = cfg.shadow
	normal.shadow_size = 8
	normal.shadow_offset = Vector2(0, 4)
	_margins(normal, 18, 10)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = cfg.get("hover_bg", cfg.normal_bg)
	# Interaction lights the border amber everywhere: one signal, one meaning.
	hover.border_color = t.SIGNAL_AMBER
	hover.shadow_size = 10
	hover.shadow_offset = Vector2(0, 6)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = cfg.normal_bg
	pressed.border_color = t.SIGNAL_AMBER
	pressed.shadow_size = 4
	pressed.shadow_offset = Vector2(0, 2)
	pressed.content_margin_top = 12
	pressed.content_margin_bottom = 8

	var disabled := _disabled_plate(18, 10)

	th.set_stylebox("normal", type_name, normal)
	th.set_stylebox("hover", type_name, hover)
	th.set_stylebox("pressed", type_name, pressed)
	th.set_stylebox("disabled", type_name, disabled)
	th.set_stylebox("focus", type_name, _focus_ring())
	th.set_color("font_color", type_name, cfg.font_color)
	th.set_color("font_hover_color", type_name, cfg.font_color)
	th.set_color("font_pressed_color", type_name, cfg.font_color)
	th.set_color("font_focus_color", type_name, cfg.font_color)
	th.set_color("font_disabled_color", type_name, t.BONE_DIM)
