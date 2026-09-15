extends Control
## scenes/dev/theme_gallery.gd — T8 component gallery driver.
##
## The .tscn holds the static specimens (Default/Active/disabled per
## component class); this script populates the dynamic parts (list items,
## option items, dot-matrix cells, tab titles, focus demo) so every state
## is visible in one screenshot.

@onready var drop_lines: ItemList = %DropLines
@onready var font_scale_pick: OptionButton = %FontScalePick
@onready var mail_dots: HBoxContainer = %MailDots
@onready var tabs: TabContainer = %DepartmentTabs
@onready var focus_demo: Button = %FocusDemo

const MAIL_CELLS := 12
const MAIL_LIT := 9

func _ready() -> void:
	drop_lines.add_item("+3 SCRAPNEL")
	drop_lines.add_item("+1 COPPER SNARL")
	drop_lines.add_item("NOTHING OF VALUE")
	drop_lines.select(0)
	drop_lines.add_item("+2 NIGHTLIGHT CAP")
	drop_lines.add_item("+1 ALMOST BULLION")

	font_scale_pick.add_item("FONT SCALE — 100%")
	font_scale_pick.add_item("FONT SCALE — 150%")
	font_scale_pick.add_item("FONT SCALE — 200%")
	font_scale_pick.select(0)

	var dot := load("res://assets/theme/dot_tile.svg")
	for i in MAIL_CELLS:
		var cell := TextureRect.new()
		cell.texture = dot
		cell.stretch_mode = TextureRect.STRETCH_TILE
		cell.custom_minimum_size = Vector2(10, 10)
		cell.self_modulate = SignageTokens.SIGNAL_AMBER if i < MAIL_LIT else SignageTokens.STEEL_LO
		mail_dots.add_child(cell)

	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, tabs.get_tab_title(i).to_upper())

	# Focus ring specimen: amber ring visible in captures.
	focus_demo.grab_focus()
