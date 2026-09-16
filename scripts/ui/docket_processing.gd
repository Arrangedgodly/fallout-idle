class_name DocketProcessing
extends DocketSkill
## DocketProcessing — T10a Junksmithing / Cooking docket: recipe form lines
## (inputs » outputs, counts craftable from LIVE inventory, gates), crafting
## through the engine's recipe slot (selecting a recipe and pressing the big
## stencled button posts the shift; each interval consumes inputs and stamps
## the output; the engine stops it with SUPPLIES EXHAUSTED when the stockpile
## runs dry). Single-craft interaction only: no queues, no repeat-N, no
## auto-craft system (explicit non-goal) — one press posts, END SHIFT stops.


func _list_header() -> String:
	return "POSTED RECIPES · SELECT A FORM LINE"


func _log_serial() -> String:
	return "CRAFT LOG · STAMPS POSTED BY THE ENGINE ROOM"


func _content_defs() -> Array:
	var out: Array = []
	var l := lib()
	if l == null:
		return out
	for id in l.recipes:
		var r: RecipeDef = l.recipes[id]
		if r.skill == skill_id:
			out.append(r)
	out.sort_custom(func(a, b) -> bool:
		return int(a.get("level_gate")) < int(b.get("level_gate")))
	return out


func _card_icon(def: RefCounted) -> String:
	var icon := str(def.get("icon"))
	if not icon.is_empty():
		return icon
	var r := def as RecipeDef
	var item: ItemDef = lib().item(r.output.item)
	return item.icon if item != null else ""


func _rate_line(def: RefCounted) -> String:
	return "+%s XP / CRAFT · %s S PER CRAFT" % [
		SignageFmt.num(int(def.get("xp_per_action"))),
		SignageFmt.seconds(int(def.get("interval_ms")))]


## Inputs » outputs with the live craftable count (honest stock math).
func _yields_line(def: RefCounted) -> String:
	var r := def as RecipeDef
	var parts: Array[String] = []
	for input in r.inputs:
		var item: ItemDef = lib().item(input.item)
		var name: String = item.name.to_upper() if item != null else input.item
		parts.append("%d × %s" % [input.qty, name])
	var out_item: ItemDef = lib().item(r.output.item)
	var out_name: String = out_item.name.to_upper() if out_item != null else r.output.item
	var line := " · ".join(parts) + " » %d × %s" % [r.output.qty, out_name]
	return line + " · CRAFTABLE %s" % SignageFmt.num(craftable_count(r))


## Max crafts the CURRENT inventory affords (multi-input min, int division —
## the same math ActivityEngine._affordable_actions applies offline).
func craftable_count(r: RecipeDef) -> int:
	if r.inputs.is_empty() or state() == null:
		return 0
	var affordable := -1
	for input in r.inputs:
		var can := state().item_count(input.item) / input.qty
		affordable = can if affordable < 0 else mini(affordable, can)
	return maxi(affordable, 0)


## Live craftable counts refresh with every inventory flush.
func _refresh_inventory_dependent() -> void:
	if tm == null or state() == null:
		return
	for id in _content_order:
		var card: Card = _cards[id]
		var r: RecipeDef = lib().recipe(id)
		if r == null:
			continue
		card.yields_line.text = _yields_line(r)


## Refuse to post a dry recipe BEFORE the engine spins a doomed slot — the
## stamp names exactly which lines came up short (mono counts).
func select_content(content_id: String) -> void:
	var r: RecipeDef = lib().recipe(content_id)
	if r != null and craftable_count(r) < 1:
		var gate: Dictionary = tm.engine.gate_of(content_id)
		if int(state().skills_level.get(gate["skill"], 1)) >= int(gate["level"]):
			selected_id = content_id
			stamp(log, "NOTHING TO WORK WITH · " + _inputs_missing_text(r))
			_refresh({"activity": true, "inventory": true, "xp": true})
			return
	super.select_content(content_id)


func _inputs_missing_text(r: RecipeDef) -> String:
	var missing: Array[String] = []
	for input in r.inputs:
		if state().item_count(input.item) < input.qty:
			var item: ItemDef = lib().item(input.item)
			var name: String = item.name.to_upper() if item != null else input.item
			missing.append("%s %s/%s" % [name,
				SignageFmt.num(state().item_count(input.item)), SignageFmt.num(input.qty)])
	return "CHECK THE MANIFEST: " + " · ".join(missing)


func _nothing_startable_text() -> String:
	return "NOTHING TO WORK WITH. GATHER FIRST — THE FORGE FILES NO WISHES."


## Recipes stamp deterministically per completed craft (no roll involved):
## one line per craft, batched with a "+N MORE" summary inside one flush.
func _stamp_completed_actions(_slot, count: int) -> void:
	var r: RecipeDef = lib().recipe(str(_slot.get("content_id")))
	if r == null:
		return
	var out_item: ItemDef = lib().item(r.output.item)
	var out_name: String = out_item.name.to_upper() if out_item != null else r.output.item
	var per := mini(count, 5)
	for i in per:
		stamp(log, "CRAFT — %d × %s" % [r.output.qty, out_name])
	if count > per:
		stamp(log, ". . . %d MORE CRAFTS IN THIS POSTING" % (count - per))


## Processing consumes its own inputs deterministically — the craft stamps
## above carry the story, so no raw inventory delta lines here.
func _watched_items(_slot) -> Dictionary:
	return {}
