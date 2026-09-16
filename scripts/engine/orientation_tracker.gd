class_name OrientationTracker
extends RefCounted
## OrientationTracker — T18 the ORIENTATION FORM O-1 engine (Design lane,
## carrying Daredevil's accessibility claims).
##
## The UI NEVER infers step completion from rendered state — this tracker owns
## the seven step booleans (naming-bible §14 binding machine ids, order =
## the form's display order) inside `state.orientation`, detects the shipped
## events through the real engines, and stamps steps idempotently:
##
##   work_shift         a gathering activity is successfully STARTED (the
##                      BEGIN SHIFT path — coordinator contract "shift
##                      started (any gathering)"; T16's §14 note pointed at
##                      the same BEGIN SHIFT anchor)
##   earn_clearance     any level_up emission (the "CLEARANCE %02d EARNED"
##                      stamp path) — a level-up always crosses to grade >= 2
##   file_crowns_claim  a Depot sale settles (SELL 1 / SELL ALL -> add_crowns)
##   process_product    one recipe action completes (processing chain)
##   provision_patrol   first equip OR first cooked food — either qualifies
##                      (amendment "[equip or cook]"; the form does not
##                      legislate which)
##   clear_nuisance     first combat victory (VICTORY POSTED path)
##   deputize_resident  first staffing.deputies increase (T17's DEPUTIZE
##                      RESIDENT button — the tutorial teaches the new system)
##
## Completion (all seven stamped) sets `completed`, grants the ORIENTATION
## STIPEND exactly once (`stipend_claimed` guard; amount from
## data/staffing.json `orientation_stipend`, never hardcoded — T20 retunes),
## and emits orientation_completed. Existing saves (post-migration) stamp
## already-satisfied steps instantly on the first evaluation: evaluate()
## derives lifetime evidence from the state itself (gathering xp, any grade
## above 1, crowns ever earned, processing xp, gear worn or food cooked,
## combat xp, deputies). It is idempotent and only ever ADDS stamps.
##
## Signals (re-emitted by TickManager — the UI binds there):
##   step_done(step_id)              once per step, when it stamps
##   orientation_completed(payload)  once ever; payload {"stipend": int}
##
## Bulk region: every stamp marks "orientation" (4 Hz flush discipline); the
## stipend grant additionally marks "inventory" (wallet-class, Depot
## precedent).

signal step_done(step_id: String)
signal orientation_completed(payload: Dictionary)

const STEP_WORK_SHIFT := "work_shift"
const STEP_EARN_CLEARANCE := "earn_clearance"
const STEP_FILE_CROWNS_CLAIM := "file_crowns_claim"
const STEP_PROCESS_PRODUCT := "process_product"
const STEP_PROVISION_PATROL := "provision_patrol"
const STEP_CLEAR_NUISANCE := "clear_nuisance"
const STEP_DEPUTIZE_RESIDENT := "deputize_resident"

const STEPS := [
	STEP_WORK_SHIFT,
	STEP_EARN_CLEARANCE,
	STEP_FILE_CROWNS_CLAIM,
	STEP_PROCESS_PRODUCT,
	STEP_PROVISION_PATROL,
	STEP_CLEAR_NUISANCE,
	STEP_DEPUTIZE_RESIDENT,
]

## The current step's destination DEPARTMENT plate (concourse ids). Documented
## choices: EARN A CLEARANCE points at Scavenging (working its posted shifts
## is the first elevator — the gate plate's own earning-path copy); PROVISION
## THE PATROL points at Cooking (the earliest reachable qualifying path:
## foraging tier 1 yields Duskcorn and Grind Mandatory Grits posts at
## clearance 1, while the first equippable weapon gates behind Junksmithing
## clearance 8 — the form does not legislate which action counts, the cue
## shows the nearest one).
const STEP_TARGETS := {
	STEP_WORK_SHIFT: "scavenging",
	STEP_EARN_CLEARANCE: "scavenging",
	STEP_FILE_CROWNS_CLAIM: "requisition_depot",
	STEP_PROCESS_PRODUCT: "junksmithing",
	STEP_PROVISION_PATROL: "cooking",
	STEP_CLEAR_NUISANCE: "wasteland_patrol",
	STEP_DEPUTIZE_RESIDENT: "personnel",
}

var lib: ContentLibrary
var batcher: UpdateBatcher


func _init(p_lib: ContentLibrary, p_batcher: UpdateBatcher = null) -> void:
	lib = p_lib
	batcher = p_batcher if p_batcher != null else UpdateBatcher.new()


# ---------------------------------------------------------------- namespace --

## Repair/seed the orientation namespace in place (idempotent, Hulk lens: a
## mangled field never crashes a save that holds real progress).
func ensure_orientation(state: PlayerState) -> void:
	if not (state.orientation is Dictionary):
		state.orientation = {}
	var steps = state.orientation.get("steps_done", [])
	if not (steps is Array):
		steps = []
	var clean: Array[String] = []
	for s in steps:
		var sid := String(s)
		if STEPS.has(sid) and not clean.has(sid):
			clean.append(sid)
	state.orientation["steps_done"] = clean
	state.orientation["completed"] = bool(state.orientation.get("completed", false))
	state.orientation["stipend_claimed"] = bool(state.orientation.get("stipend_claimed", false))


func is_step_done(state: PlayerState, step_id: String) -> bool:
	var steps = state.orientation.get("steps_done", [])
	return steps is Array and (steps as Array).has(step_id)


func steps_done_count(state: PlayerState) -> int:
	var steps = state.orientation.get("steps_done", [])
	return (steps as Array).size() if steps is Array else 0


func is_complete(state: PlayerState) -> bool:
	return bool(state.orientation.get("completed", false))


## The form's current step: the first unstamped step in display order ("" at
## completion). Steps are order-agnostic mechanically — any may complete
## first; the form's emphasis walks the posted order.
func current_step(state: PlayerState) -> String:
	for step_id in STEPS:
		if not is_step_done(state, step_id):
			return String(step_id)
	return ""


## The concourse department plate the current step's cue points at ("" at
## completion — the arrow class retires with the tutorial).
func current_target(state: PlayerState) -> String:
	var step := current_step(state)
	return String(STEP_TARGETS.get(step, "")) if step != "" else ""


static func step_target(step_id: String) -> String:
	return String(STEP_TARGETS.get(step_id, ""))


## Sort comparator: the posted (display) order of the form's seven lines.
static func _posted_order(a, b) -> bool:
	return STEPS.find(String(a)) < STEPS.find(String(b))


# ------------------------------------------------------------------ events --

## A gathering activity started (BEGIN SHIFT). Recipes do not stamp this —
## PROCESS A PRODUCT is their own step.
func note_activity_started(state: PlayerState, slot: PlayerState.ActiveSlot) -> void:
	if slot != null and not slot.is_recipe:
		_mark(state, STEP_WORK_SHIFT)


func note_level_up(state: PlayerState, _skill_id: String) -> void:
	_mark(state, STEP_EARN_CLEARANCE)


## One completed recipe action: PRODUCT stamps always; a food output also
## stamps the patrol's provisions (either leg qualifies).
func note_recipe_completed(state: PlayerState, rdef: RecipeDef) -> void:
	if rdef == null:
		return
	_mark(state, STEP_PROCESS_PRODUCT)
	var item: ItemDef = lib.item(rdef.output.item) if lib != null else null
	if item != null and item.is_food():
		_mark(state, STEP_PROVISION_PATROL)


func note_sale(state: PlayerState) -> void:
	_mark(state, STEP_FILE_CROWNS_CLAIM)


func note_equip(state: PlayerState) -> void:
	_mark(state, STEP_PROVISION_PATROL)


func note_victory(state: PlayerState) -> void:
	_mark(state, STEP_CLEAR_NUISANCE)


func note_deputize(state: PlayerState) -> void:
	_mark(state, STEP_DEPUTIZE_RESIDENT)


# ------------------------------------------------------- state evaluation --

## LIFETIME-evidence back-fill — the VETERAN path only (a v1 run-1 record
## migrating up, or a T17-window v2 record that predates the namespace):
## SaveStore calls this once when a loaded record arrived with no orientation
## of its own, so a progressed player's already-satisfied steps stamp
## instantly on the first session. It is deliberately NOT run on every load:
## a genuine v2 record IS its own truth, and the acceptance suite pins
## live-twin/reloaded-twin state dicts byte-equal (evidence heuristics can
## only ever run where no stamped record exists to diverge from).
func evaluate(state: PlayerState) -> void:
	if lib == null:
		return
	ensure_orientation(state)
	for skill_id: String in lib.skills:
		var skill: SkillDef = lib.skills[skill_id]
		var xp := int(state.skills_xp.get(skill_id, 0))
		if xp <= 0:
			continue
		if skill.kind == "gathering":
			_mark(state, STEP_WORK_SHIFT)
		elif skill.kind == "processing":
			_mark(state, STEP_PROCESS_PRODUCT)
			if skill_id == "cooking":
				_mark(state, STEP_PROVISION_PATROL)
		elif skill.kind == "combat":
			_mark(state, STEP_CLEAR_NUISANCE)
		if int(state.skills_level.get(skill_id, 1)) > 1:
			_mark(state, STEP_EARN_CLEARANCE)
	if state.crowns > 0:
		_mark(state, STEP_FILE_CROWNS_CLAIM)
	var weapon := str(state.combat.get("weapon", ""))
	var armor := str(state.combat.get("armor", ""))
	if weapon != "" or armor != "":
		_mark(state, STEP_PROVISION_PATROL)
	for item_id in state.inventory:
		var item: ItemDef = lib.item(String(item_id))
		if item != null and item.is_food():
			_mark(state, STEP_PROVISION_PATROL)
			break
	if int(state.staffing.get("deputies", 0)) > 0:
		_mark(state, STEP_DEPUTIZE_RESIDENT)


## OFFLINE settlement — DELTA evidence from the MAIL CALL payload (what the
## away window actually did), never lifetime state: the live twin of the same
## window stamps the same steps through its event hooks, so the
## offline-twin/live-twin deep-equal pin holds exactly (payload facts:
## levels crossed, processing actions done, kills landed).
func settle_offline(state: PlayerState, payload: Dictionary) -> void:
	ensure_orientation(state)
	if bool(state.orientation.get("completed", false)):
		return
	var levels: Dictionary = payload.get("levels", {})
	if not levels.is_empty():
		_mark(state, STEP_EARN_CLEARANCE)
	var actions: Dictionary = payload.get("actions", {})
	var combat_skill := ""
	for skill_id: String in lib.skills:
		if (lib.skills[skill_id] as SkillDef).kind == "combat":
			combat_skill = skill_id
	if actions.has(combat_skill) and int(actions[combat_skill]) > 0:
		_mark(state, STEP_CLEAR_NUISANCE)
	for skill_id: String in lib.skills:
		var skill: SkillDef = lib.skills[skill_id]
		if skill.kind != "processing":
			continue
		if actions.has(skill_id) and int(actions[skill_id]) > 0:
			_mark(state, STEP_PROCESS_PRODUCT)
			if skill_id == "cooking":
				_mark(state, STEP_PROVISION_PATROL)


# ------------------------------------------------------------------ stamp --

## Stamp one step (idempotent, once ever). The seventh stamp completes the
## form: completed = true, the ORIENTATION STIPEND posts once (crowns += the
## data/staffing.json orientation_stipend amount; stipend_claimed guards
## reloads and re-evaluations), and orientation_completed fires.
func _mark(state: PlayerState, step_id: String) -> void:
	ensure_orientation(state)
	if bool(state.orientation.get("completed", false)):
		return
	var steps: Array = state.orientation["steps_done"]
	if steps.has(step_id):
		return
	steps.append(step_id)
	# steps_done always sits in POSTED order (canonical set semantics): a
	# live stamp and a later reload's evaluation must converge bit-for-bit —
	# the acceptance suite deep-equals whole PlayerState dicts across a real
	# save/load round-trip, and stamp ORDER carries no information (the form
	# renders the posted order; completion is order-agnostic).
	steps.sort_custom(_posted_order)
	if batcher != null:
		batcher.mark("orientation")
	if steps.size() < STEPS.size():
		step_done.emit(step_id)
		return
	# The seventh stamp: full state mutation first, then the two signals in
	# walked order (the final row stamps, then the form posts DULY ORIENTED).
	state.orientation["completed"] = true
	var stipend := 0
	if not bool(state.orientation.get("stipend_claimed", false)):
		stipend = maxi(int(lib.orientation_stipend) if lib != null else 0, 0)
		if stipend > 0:
			state.add_crowns(stipend)
			if batcher != null:
				batcher.mark("inventory")
		state.orientation["stipend_claimed"] = true
	step_done.emit(step_id)
	orientation_completed.emit({"stipend": stipend})
