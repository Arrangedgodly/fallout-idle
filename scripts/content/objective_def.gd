class_name ObjectiveDef
extends RefCounted
## ObjectiveDef — one DEPARTMENTAL DOSSIER line (T23 content schema; the run-3
## objectives system, naming-bible §15 machine-id contract).
##
## One tracked duty with an auto-granted reward: the moment its condition
## holds against the lifetime counters (ObjectivesTracker), the objective
## STAMPS exactly once and its MERIT PAY / COMMENDATION legs post themselves
## (no claim buttons anywhere — design-brief Addendum 2). Field contract:
## docs/content-schema.md → "objectives.json".
##
## Condition kinds (§15; T23 final set — `stamped_count` supersedes the
## suggested id `set_complete`, per the T23 dispatch):
##   level_reach    objective.skill reaches clearance `target` (2..max_level)
##   gather_count   `ref` = an ACTIVITY id (completed actions) or an ITEM id
##                  (units gained from activity drop rolls) — which one is
##                  resolved at load time into gather_ref_is_activity
##   craft_count    `ref` = a RECIPE id (completed crafts)
##   kill_count     `ref` = a MONSTER id (victories)
##   sell_count     `ref` = an ITEM id (units tendered at the Depot)
##   equip_item     `ref` = an EQUIPMENT item id (times equipped)
##   zone_clear     `ref` = a ZONE id (times that zone's boss was defeated)
##   stamped_count  `target` objectives of objective.skill are STAMPED (the
##                  count excludes this objective itself while it is open —
##                  the set-completion meta kind)
##   crowns_total   `target` Crowns earned lifetime (posted, never spent)
##
## The `skill` field is the dossier grouping (one of the five skills); the
## loader enforces kind-specific ownership (kills/zones/equips belong to the
## combat skill's EXTERIOR DOSSIER; crafts/level lines belong to their own
## skill) — see ContentLoader._cross_check.
##
## Rewards: at least one leg, always (`crowns` and/or `xp {skill, amount}`);
## amounts are balance data — T25 authors, T27 tunes, never hardcoded.

const KIND_LEVEL_REACH := "level_reach"
const KIND_GATHER_COUNT := "gather_count"
const KIND_CRAFT_COUNT := "craft_count"
const KIND_KILL_COUNT := "kill_count"
const KIND_SELL_COUNT := "sell_count"
const KIND_EQUIP_ITEM := "equip_item"
const KIND_ZONE_CLEAR := "zone_clear"
const KIND_STAMPED_COUNT := "stamped_count"
const KIND_CROWNS_TOTAL := "crowns_total"

const KINDS := [
	KIND_LEVEL_REACH, KIND_GATHER_COUNT, KIND_CRAFT_COUNT, KIND_KILL_COUNT,
	KIND_SELL_COUNT, KIND_EQUIP_ITEM, KIND_ZONE_CLEAR, KIND_STAMPED_COUNT,
	KIND_CROWNS_TOTAL,
]

## Kinds whose condition carries a `ref` (the rest are meta/whole-scope).
const REF_KINDS := [
	KIND_GATHER_COUNT, KIND_CRAFT_COUNT, KIND_KILL_COUNT, KIND_SELL_COUNT,
	KIND_EQUIP_ITEM, KIND_ZONE_CLEAR,
]

var id: String  ## Stable snake_case id (one per objective, duplicates rejected).
var skill: String  ## SkillDef id — the dossier this line posts in.
var description: String  ## Plate-idiom line, <= 6 words, no "!" (Addendum 2 voice rules).
var kind: String  ## One of KINDS.
var target: int  ## The threshold the lifetime counter must reach (>= 1).
var ref: String  ## Content id for REF_KINDS, "" otherwise.
var gather_ref_is_activity := false  ## gather_count only: ref resolved to an activity (vs an item).
var counter_key := ""  ## Loader-computed (T25): the exact lifetime-counter key this condition reads ("activity:<id>", "level:<skill>", "crowns", ...). Hydrated in ContentLoader._cross_check alongside gather_ref_is_activity — keeps ObjectivesTracker.count_for a single dict get and builds the tracker's key->objectives index (no per-action full-set walk).
var reward_crowns := 0  ## MERIT PAY leg (0 = no leg).
var reward_xp_skill := ""  ## COMMENDATION leg skill id ("" = no leg).
var reward_xp_amount := 0  ## COMMENDATION leg XP amount.


func has_crowns_reward() -> bool:
	return reward_crowns > 0


func has_xp_reward() -> bool:
	return reward_xp_skill != "" and reward_xp_amount > 0
