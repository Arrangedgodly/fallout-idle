extends Node
## UiTheme — T8 autoload: owns the signage Theme + the font-scale setting.
##
## The theme resource is the committed assets/theme/signage_theme.tres built
## by scripts/theme/signage_theme.gd. Font scale is Daredevil's claim: one
## call re-sizes every registered font size (base x scale) inside the Theme,
## so all text that inherits the theme scales — 100% / 150% / 200%, no
## per-control work. Screens attach the theme by setting Control.theme =
## UiTheme.theme (or inheriting from a root that did); T9 wires the settings
## control; T3 persists the chosen step in save settings.

const THEME_PATH := "res://assets/theme/signage_theme.tres"
const FONT_SCALE_STEPS := [1.0, 1.5, 2.0]

var theme: Theme
var font_scale := 1.0

func _ready() -> void:
	theme = load(THEME_PATH)
	if theme == null:
		push_error("[ui] signage theme missing at %s — regenerate via generate_theme.gd" % THEME_PATH)
		return
	apply_font_scale(1.0)

func apply_font_scale(scale: float) -> void:
	if theme == null:
		return
	if not FONT_SCALE_STEPS.has(scale):
		push_error("[ui] unsupported font scale %s (steps: %s)" % [str(scale), str(FONT_SCALE_STEPS)])
		return
	SignageTheme.apply_font_scale(theme, scale)
	font_scale = scale

func install(control: Control) -> void:
	if theme != null and control != null:
		control.theme = theme
