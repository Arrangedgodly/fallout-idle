class_name PlayerState
extends RefCounted
## PlayerState — the T6 idle engine's mutable player container (pure data).
##
## Zero logic lives here. ActivityEngine is the single writer and owns the
## invariants: skills_level is always the skill's XpCurveDef re-derivation of
## skills_xp (level is a cache, xp is the truth), inventory values are ints
## >= 0, and `active` holds at most one ActiveSlot per skill id.
##
## Extensibility (plan T6): combat/equipment/food state is NOT in this task —
## T7 owns combat and extends this container through the reserved `combat`
## dictionary namespace (hp/chassis/target/etc.). Do not repurpose it.
##
## Save round-trip: to_dict()/from_dict() emit plain JSON types only. T3
## (SaveManager) wraps these in its own envelope (docs/save-schema.md). Note
## for T3: the save-schema's activity_state sketch (one "gathering" line)
## predates T6's per-skill slot model — T6 persists one slot per non-combat
## skill; T3 owns the final save layout, including rng_state (store it as a
## string if JSON precision worries you; in memory it is an exact int).

var world_seed: int = 0
var crowns: int = 0
var skills_xp: Dictionary = {}  ## skill_id -> lifetime int xp (truth)
var skills_level: Dictionary = {}  ## skill_id -> derived int level (cache, repaired on load)
var inventory: Dictionary = {}  ## item_id -> int stack
var active: Dictionary = {}  ## skill_id -> ActiveSlot (gathering + processing; combat is T7's)
var last_mail_call: Dictionary = {}  ## last offline payload (presentation cache; not saved)

## Reserved namespace for T7 combat state (hp, equipped ids, food bar, ...) —
## LIVE since T7: the shape + semantics are owned by CombatSession
## (scripts/engine/combat_session.gd); pass-through only here (ints + rng
## int64-as-strings keep the JSON round-trip exact).
var combat: Dictionary = {}


## One running activity/recipe on one skill. Action k (0-based) completes at
## `anchor_ms + (k + 1) * interval_ms` on the sim clock — the closed-form
## anchor both the live tick loop and offline catch-up advance.
class ActiveSlot extends RefCounted:
	var skill_id: String = ""
	var content_id: String = ""  ## ActivityDef id or RecipeDef id
	var is_recipe: bool = false
	var interval_ms: int = 0
	var anchor_ms: int = 0  ## sim-time anchor (first action lands one full interval after it)
	var completed: int = 0  ## actions completed since the anchor
	var rng_seed: int = 0  ## per-slot deterministic drop-stream seed
	var rng_state: int = 0  ## RandomNumberGenerator.state, persisted for exact offline continuation
	var stream_started: bool = false  ## false until the first roll positions rng_state

	func next_action_at_ms() -> int:
		return anchor_ms + (completed + 1) * interval_ms

	func to_dict() -> Dictionary:
		return {
			"skill_id": skill_id,
			"content_id": content_id,
			"is_recipe": is_recipe,
			"interval_ms": interval_ms,
			"anchor_ms": anchor_ms,
			"completed": completed,
			"rng_seed": rng_seed,
			"rng_state": rng_state,
			"stream_started": stream_started,
		}

	static func from_dict(d: Dictionary) -> ActiveSlot:
		var slot := ActiveSlot.new()
		slot.skill_id = String(d["skill_id"])
		slot.content_id = String(d["content_id"])
		slot.is_recipe = bool(d["is_recipe"])
		slot.interval_ms = int(d["interval_ms"])
		slot.anchor_ms = int(d["anchor_ms"])
		slot.completed = int(d["completed"])
		slot.rng_seed = int(d["rng_seed"])
		slot.rng_state = int(d.get("rng_state", 0))
		slot.stream_started = bool(d.get("stream_started", false))
		return slot


# -- Inventory (int stacks) --

func add_item(item_id: String, qty: int) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + qty


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


## Atomic consume: takes `qty` only if the full amount is present.
func take_item(item_id: String, qty: int) -> bool:
	var have := item_count(item_id)
	if have < qty:
		return false
	var left := have - qty
	if left > 0:
		inventory[item_id] = left
	else:
		inventory.erase(item_id)
	return true


# -- Currency --

func add_crowns(amount: int) -> void:
	crowns += maxi(amount, 0)


func try_spend_crowns(amount: int) -> bool:
	if amount < 0 or crowns < amount:
		return false
	crowns -= amount
	return true


# -- Serialization (T3 consumes) --

func to_dict() -> Dictionary:
	var active_d := {}
	for skill_id in active:
		active_d[skill_id] = active[skill_id].to_dict()
	return {
		"world_seed": world_seed,
		"crowns": crowns,
		"skills_xp": skills_xp.duplicate(),
		"inventory": inventory.duplicate(),
		"active": active_d,
		"combat": combat.duplicate(true),
	}


## Levels are NOT read from `d` — they are re-derived and repaired from xp via
## each skill's curve (save-schema.md field note). `lib` is required.
static func from_dict(d: Dictionary, lib: ContentLibrary) -> PlayerState:
	var st := PlayerState.new()
	st.world_seed = int(d.get("world_seed", 0))
	st.crowns = int(d.get("crowns", 0))
	var xp_d: Dictionary = d.get("skills_xp", {})
	for skill_id: String in lib.skills:
		var skill: SkillDef = lib.skills[skill_id]
		var xp := int(xp_d.get(skill_id, 0))
		st.skills_xp[skill_id] = xp
		st.skills_level[skill_id] = lib.xp_curve(skill.xp_curve).level_for_total_xp(xp)
	var inv_d: Dictionary = d.get("inventory", {})
	for item_id in inv_d:
		st.inventory[String(item_id)] = int(inv_d[item_id])
	var active_d: Dictionary = d.get("active", {})
	for skill_id in active_d:
		st.active[String(skill_id)] = ActiveSlot.from_dict(active_d[skill_id])
	var combat_d: Dictionary = d.get("combat", {})
	st.combat = combat_d.duplicate(true)
	return st
