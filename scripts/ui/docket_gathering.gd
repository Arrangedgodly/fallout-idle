class_name DocketGathering
extends DocketSkill
## DocketGathering — T10a Scavenging / Foraging docket: tier cards from data
## (icon, name, xp/action, interval, drop rates VISIBLE per the honest-math
## principle), clearance gates as CLEARANCE REQUIRED plates while locked,
## start/stop through the engine façade, energized running state, enamel XP
## gauge, and drop lines stamped from the batched inventory flushes.


func _list_header() -> String:
	return "POSTED SHIFTS · SELECT A FORM LINE"


func _log_serial() -> String:
	return "SHIFT LOG · YIELD STAMPS POSTED BY THE ENGINE ROOM"


func _start_stamp_text(content_id: String) -> String:
	return "SHIFT POSTED — " + _content_name(content_id).to_upper()


func _nothing_startable_text() -> String:
	return "NOTHING TO POST. THE PILE AWAITS."


## The running activity's yield items — the only inventory deltas this log
## claims (attribution filter; the Manifest stays the source of truth).
func _watched_items(slot) -> Dictionary:
	var out := {}
	var l := lib()
	var adef: ActivityDef = l.activity(str(slot.get("content_id")))
	if adef == null:
		return out
	var table: DropTableDef = l.drop_table(adef.drop_table)
	if table == null:
		return out
	for entry in table.entries:
		out[entry.item] = true
	return out
