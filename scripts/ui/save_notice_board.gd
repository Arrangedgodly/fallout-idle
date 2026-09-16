class_name SaveNoticeBoard
extends Control
## SaveNoticeBoard — T10a concourse posting for T3 SaveStore notice states:
## corruption fallbacks, backup-loaded restores, refused newer-save versions
## and failed filings. One posted plate at a time, anchored above the console
## bar; the resident acknowledges it away (SaveStore.clear_notice files the
## acknowledgment). Wiring: bind(save_store) reads any notice that was
## raised before the concourse existed and follows notice_raised after.

signal acknowledged(kind: String)

const COPY := {
	"primary_corrupt_backup_loaded": [
		"RECORD DAMAGED · LAST-GOOD BACKUP FILED INTO SERVICE",
		"THE RING HOLDS. THE WRECKAGE IS PRESERVED FOR INSPECTION."],
	"all_saves_corrupt_fresh_state": [
		"ALL RECORDS UNREADABLE · A FRESH LEDGER HAS BEEN OPENED",
		"NOTHING SURVIVED. THE ARCHIVE KEEPS WHAT IT KEEPS."],
	"refused_newer_save_version": [
		"RECORD FROM A NEWER BUILD · FILING SUSPENDED",
		"NO BYTES WERE HARMED AND NONE WILL BE OVERWRITTEN."],
	"save_write_failed": [
		"FILING FAILED · THE DESK REJECTED YOUR PAPER",
		"RETRY FROM THE CONSOLE. THE DEPARTMENT IS SORRY IN WRITING."],
}
const PAPER_KINDS := ["save_write_failed"]

var plate: PanelContainer
var title_line: Label
var detail_line: Label
var ack_button: Button

var store: Node = null  # SaveStore instance (production autoload or twin)
var _kind := ""
var _store_connections: Array[Signal] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	plate = PanelContainer.new()
	plate.name = "SaveNoticePlate"
	plate.theme_type_variation = "DangerPlate"
	plate.z_index = 30
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	title_line = Label.new()
	title_line.theme_type_variation = "MonoValue"
	title_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title_line)
	detail_line = Label.new()
	detail_line.theme_type_variation = "MonoValue"
	detail_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(detail_line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	ack_button = Button.new()
	ack_button.name = "AcknowledgeNotice"
	ack_button.text = "ACKNOWLEDGE"
	ack_button.tooltip_text = "File this notice away and carry on"
	ack_button.pressed.connect(_on_ack_pressed)
	row.add_child(ack_button)
	col.add_child(row)
	plate.add_child(col)
	add_child(plate)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_layout()


func _layout() -> void:
	if not is_inside_tree():
		return
	var window_w := get_viewport_rect().size.x
	var w := minf(560.0, window_w - 120.0)
	plate.custom_minimum_size = Vector2(w, 0.0)
	var console := get_parent().find_child("ConsoleBar", true, false) as Control if get_parent() != null else null
	var bottom: float = console.get_global_rect().position.y - 12.0 if console != null \
			else get_viewport_rect().size.y - 90.0
	plate.global_position = Vector2((window_w - w) * 0.5, bottom - plate.get_combined_minimum_size().y)


# ------------------------------------------------------------------ binding
## Follow one SaveStore (production autoload or test twin). Notices raised
## before the concourse existed are read from store.notice at bind.
func bind(p_store: Node) -> void:
	unbind()
	store = p_store
	if store == null:
		return
	if store.has_method("is_dormant") and bool(store.call("is_dormant")):
		return
	var raised: Signal = store.notice_raised
	raised.connect(_on_notice_raised)
	_store_connections.append(raised)
	var notice: Dictionary = store.get("notice")
	if not notice.is_empty():
		_post(str(notice.get("kind", "")), notice.get("detail", {}))


func unbind() -> void:
	for sig in _store_connections:
		if sig.is_connected(_on_notice_raised):
			sig.disconnect(_on_notice_raised)
	_store_connections.clear()
	store = null


func is_posting() -> bool:
	return visible


func kind() -> String:
	return _kind


# ------------------------------------------------------------------ posting
func _on_notice_raised(kind: String, detail: Dictionary) -> void:
	_post(kind, detail)


## Post one notice plate (public: tests and the concourse use it directly).
func post(kind: String, detail: Dictionary = {}) -> void:
	_post(kind, detail)


func _post(kind: String, detail: Dictionary) -> void:
	if not COPY.has(kind):
		return
	_kind = kind
	var copy: Array = COPY[kind]
	var is_paper: bool = PAPER_KINDS.has(kind)
	plate.theme_type_variation = "PaperNotice" if is_paper else "DangerPlate"
	title_line.theme_type_variation = "PlateSerialNavy" if is_paper else "MonoValue"
	detail_line.theme_type_variation = "PaperText" if is_paper else "MonoValue"
	title_line.text = copy[0]
	detail_line.text = copy[1] + _detail_suffix(kind, detail)
	visible = true
	_layout()
	_layout.call_deferred()  # console geometry settles after the pass


func _detail_suffix(kind: String, detail: Dictionary) -> String:
	match kind:
		"primary_corrupt_backup_loaded":
			var from := str(detail.get("restored_from", ""))
			return "" if from.is_empty() else " RESTORED FROM %s." % from.to_upper()
		"refused_newer_save_version":
			return " RECORD v%s · BUILD v%s." % [
				str(detail.get("found_save_version", "?")),
				str(detail.get("supported_save_version", "?"))]
		"save_write_failed":
			return "" if str(detail.get("reason", "")).is_empty() \
				else " %s." % str(detail["reason"]).to_upper()
		_:
			return ""


func _on_ack_pressed() -> void:
	var kind := _kind
	_kind = ""
	visible = false
	if store != null and store.has_method("clear_notice"):
		store.call("clear_notice")
	acknowledged.emit(kind)
