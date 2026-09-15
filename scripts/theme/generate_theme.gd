extends SceneTree
## scripts/theme/generate_theme.gd — one-shot dev tool (T8).
##
## Rebuilds the committed Theme resource from SignageTheme.build():
##   "$GODOT" --headless --path . -s res://scripts/theme/generate_theme.gd
## Output: res://assets/theme/signage_theme.tres (committed, generated —
## regenerate after editing SignageTheme/SignageTokens, never hand-edit).

func _initialize() -> void:
	var theme := SignageTheme.build()
	var err := ResourceSaver.save(theme, "res://assets/theme/signage_theme.tres")
	if err != OK:
		printerr("THEME_GEN FAILED err=%d" % err)
		quit(1)
		return
	# Prove the saved resource round-trips with fonts + styleboxes intact.
	var reloaded := load("res://assets/theme/signage_theme.tres") as Theme
	if reloaded == null or reloaded.get_font("font", "PlateTitle") == null \
			or reloaded.get_stylebox("panel", "EnamelPlate") == null:
		printerr("THEME_GEN FAILED round-trip check")
		quit(1)
		return
	var plate_font := reloaded.get_font("font", "PlateTitle") as FontVariation
	if plate_font == null or plate_font.base_font == null:
		printerr("THEME_GEN FAILED plate FontVariation lost its base font")
		quit(1)
		return
	print("THEME_GEN OK registered_font_sizes=%d" % SignageTheme.FONT_SIZE_BASES.size())
	quit(0)
