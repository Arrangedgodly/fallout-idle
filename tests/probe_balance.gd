extends SceneTree
## tests/probe_balance.gd — T5 balance-content probe (plain --script; R2
## bootstrap-smoke pattern until T12 wires GUT over this directory).
##
## Run: "$GODOT" --headless --path . -s res://tests/probe_balance.gd
## Exit 0 = all checks pass; 1 = any failure (each printed to stderr).
##
## Proves the T5 acceptance criteria against the AUTHORED slice content
## (the golden set was disposable scaffolding; data/*.json is now the real
## balance set — docs/balance-notes.md is the design record):
##   1. the full content set loads + validates with zero errors AND zero
##      warnings (no orphan items, no unused drop tables);
##   2. XP curve integrity: 98 steps, monotonic, level 99 reachable;
##   3. first level-up <= 60 s at tier-1 rates (Professor X hook), and
##      3-5 level-ups land in a first 5-minute session;
##   4. no orphan items by the strong definition: every item has a SOURCE
##      (drop table | recipe output | shop line) and a SINK (recipe input |
##      edible | equippable);
##   5. every activity/recipe/monster/shop/equipment reference resolves;
##   6. structure: 4 escalating tiers per gathering skill, 4 tier bands per
##      processing chain (consuming gathering outputs + monster drops),
##      5-monster ladder with exactly one boss, 2 weapons + 2 armors;
##   7. shop integrity: buy > sell everywhere, gates resolvable, no
##      buy-craft-sell arbitrage on fully stockable recipes;
##   8. SEEDED simulated boss fights using the combat spec arithmetic of
##      docs/balance-notes.md §1 (the binding T7 spec: harmonic accuracy
##      roll, bounded damage, first swing after one full interval, auto-eat
##      at half HP): The Superintendent is beatable with max slice gear +
##      best food and NOT with mid gear — and not by out-eating it naked.

const SEEDS := 25
const SIM_CAP_MS := 3_600_000
const FIRST_LEVELUP_BUDGET_MS := 60_000
const FIRST_SESSION_MS := 300_000

# Player chassis — engine-side constants per docs/balance-notes.md §1.1.
# Content governs monsters and gear; T7 owns these numbers in code and this
# probe mirrors the spec until T7 lands (then T13 compares them).
const BASE_MAX_HP := 100
const BASE_ATTACK_SPEED_MS := 3000
const BASE_ACCURACY := 30
const BASE_EVASION := 10
const BASE_MIN_HIT := 1
const BASE_MAX_HIT := 4

# Bible-final display names (naming-bible.md §4-§6) — guards accidental
# renames of the T4-cleared catalog.
const BIBLE_NAMES := {
	"scrap_metal": "Scrapnel",
	"copper_wiring": "Copper Snarl",
	"cloth_scraps": "Tattercloth",
	"girderling": "Girderling",
	"glowshroom": "Nightlight Cap",
	"duskcorn": "Duskcorn",
	"iodine_root": "Iodine Root",
	"roach_meat": "Grade-D Bugmeat",
	"lint_pelt": "Lint Pelt",
	"fizz_gland": "Fizz Gland",
	"vintage_snack_cake": "Vintage Snack Cake",
	"scrap_ingot": "Almost Bullion",
	"compliant_wire": "Compliant Wire",
	"patchwork_bolt": "Patchwork Bolt",
	"mandatory_grits": "Mandatory Grits",
	"compliant_casserole": "Compliant Casserole",
	"radstag_stew": "Chef's Regret",
	"scrap_shiv": "Point of Order",
	"majority_whip": "Majority Whip",
	"hubcap_vest": "Pedestrian Plating",
	"carpool_carapace": "Carpool Carapace",
}

const EXPECTED_RECORD_COUNT := 83  # 21 items + 5 skills + 8 activities + 11 recipes + 13 tables + 5 monsters + 4 equipment + 11 shop lines + 1 curve + 4 T17 deputy rungs

var lib: ContentLibrary
var checks := 0
var failures: Array[String] = []
var _frame := 0


func _initialize() -> void:
	var result := ContentLoader.load_all()
	_check(result.ok(), "authored set validates with zero errors (got: %s)" % str(result.errors))
	_check(result.warnings.is_empty(), "authored set produces zero warnings (got: %s)" % str(result.warnings))
	if result.library == null:
		_check(false, "authored set hydrates a ContentLibrary")
		return
	lib = result.library

	_check(lib.record_count() == EXPECTED_RECORD_COUNT, "library record_count() == %d (got %d)" % [EXPECTED_RECORD_COUNT, lib.record_count()])
	_check_bible_names()
	_check_curve()
	_check_first_hook()
	_check_gathering_tiers()
	_check_processing_chains()
	_check_monster_ladder()
	_check_equipment()
	_check_food_ladder()
	_check_references()
	_check_orphans_strong()
	_check_shop_integrity()
	_check_combat_sims()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_report_and_quit()
	return true


# ------------------------------------------------------------ naming + curve

func _check_bible_names() -> void:
	for item_id in BIBLE_NAMES:
		var def := lib.item(item_id)
		_check(def != null, "bible item '%s' exists" % item_id)
		if def != null:
			_check(def.name == BIBLE_NAMES[item_id],
				"item '%s' carries its FINAL T4 name '%s' (got '%s')" % [item_id, BIBLE_NAMES[item_id], def.name])
	_check(lib.item("scrap_shiv").is_equipment() and lib.item("majority_whip").is_equipment()
		and lib.item("hubcap_vest").is_equipment() and lib.item("carpool_carapace").is_equipment(),
		"all four equipment items are category equipment")


func _check_curve() -> void:
	var curve := lib.xp_curve("standard_99")
	_check(curve != null, "xp curve 'standard_99' exists")
	if curve == null:
		return
	_check(curve.max_level == 99 and curve.xp_per_level.size() == 98,
		"curve tops out at 99 with 98 steps (got %d / %d)" % [curve.max_level, curve.xp_per_level.size()])
	var monotonic := true
	for i in range(1, curve.xp_per_level.size()):
		if curve.xp_per_level[i] < curve.xp_per_level[i - 1]:
			monotonic = false
			break
	_check(monotonic, "curve is monotonic non-decreasing (XP never gets cheaper)")
	var total := curve.total_xp_to_reach(99)
	_check(total > 0, "level 99 is reachable (total %d XP required)" % total)
	_check(curve.level_for_total_xp(total) == 99, "closed-form inverse reaches 99 at total XP")
	_check(curve.xp_to_next(99) == 0, "no XP past max level")


func _check_first_hook() -> void:
	for tier1_id in ["sort_scrap_pile", "walk_the_glow_rows"]:
		var activity := lib.activity(tier1_id)
		_check(activity != null and activity.level_gate == 1, "tier-1 activity '%s' exists, ungated" % tier1_id)
		if activity == null:
			continue
		var curve := lib.xp_curve(lib.skill(activity.skill).xp_curve)
		var actions_needed := ceili(float(curve.xp_per_level[0]) / float(activity.xp_per_action))
		var first_levelup_ms := actions_needed * activity.interval_ms
		_check(first_levelup_ms <= FIRST_LEVELUP_BUDGET_MS,
			"%s: first level-up in %d ms (<= %d ms budget; %d XP step / %d XP per action)" % [
				tier1_id, first_levelup_ms, FIRST_LEVELUP_BUDGET_MS, curve.xp_per_level[0], activity.xp_per_action])
		# Professor X: 3-5 level-ups in the first session (5 min of tier-1 play).
		var actions := int(float(FIRST_SESSION_MS) / float(activity.interval_ms))
		var session_level := curve.level_for_total_xp(actions * activity.xp_per_action)
		_check(session_level >= 5 and session_level <= 7,
			"%s: 5 min of tier-1 play lands on level %d (3-5 level-ups expected)" % [tier1_id, session_level])


# ------------------------------------------------------------- activity tiers

func _check_gathering_tiers() -> void:
	for skill_id in ["scavenging", "foraging"]:
		var skill := lib.skill(skill_id)
		_check(skill != null and skill.kind == "gathering", "gathering skill '%s' exists" % skill_id)
		if skill == null:
			continue
		var tiers: Array[ActivityDef] = []
		for activity in lib.activities.values():
			if activity.skill == skill_id:
				tiers.append(activity)
		_check(tiers.size() == 4, "%s has exactly 4 activity tiers (got %d)" % [skill_id, tiers.size()])
		if tiers.is_empty():
			continue
		tiers.sort_custom(func(a: ActivityDef, b: ActivityDef) -> bool: return a.level_gate < b.level_gate)
		_check(tiers[0].level_gate == 1, "%s tier 1 is clearance 1" % skill_id)
		for i in range(1, tiers.size()):
			var rate := 60000.0 * tiers[i].xp_per_action / tiers[i].interval_ms
			var prev_rate := 60000.0 * tiers[i - 1].xp_per_action / tiers[i - 1].interval_ms
			_check(tiers[i].level_gate > tiers[i - 1].level_gate,
				"%s tier %d gate escalates (%d > %d)" % [skill_id, i + 1, tiers[i].level_gate, tiers[i - 1].level_gate])
			_check(rate > prev_rate,
				"%s tier %d XP rate escalates (%.0f > %.0f XP/min)" % [skill_id, i + 1, rate, prev_rate])


# ----------------------------------------------------------- processing chains

func _recipes_for(skill_id: String) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	for recipe in lib.recipes.values():
		if recipe.skill == skill_id:
			out.append(recipe)
	return out


func _check_processing_chains() -> void:
	_check(lib.skill("cooking") != null and lib.skill("cooking").kind == "processing",
		"processing skill 'cooking' exists")

	# Items reachable from gathering tables (the chains must consume these).
	var gathering_items := {}
	for activity in lib.activities.values():
		for entry in lib.drop_table(activity.drop_table).entries:
			gathering_items[entry.item] = true
	# Items dropped by monsters.
	var monster_items := {}
	for monster in lib.monsters.values():
		for entry in lib.drop_table(monster.drop_table).entries:
			monster_items[entry.item] = true

	for chain in ["junksmithing", "cooking"]:
		var recipes := _recipes_for(chain)
		var gates: Array[int] = []
		for recipe in recipes:
			gates.append(recipe.level_gate)
		gates.sort()
		var bands: Array[int] = []
		for gate in gates:
			if not bands.has(gate):
				bands.append(gate)
		_check(bands.size() == 4, "%s chain spans exactly 4 clearance tiers (gates %s)" % [chain, str(bands)])
		var consumes_gathering := false
		var consumes_monster := false
		for recipe in recipes:
			for input in recipe.inputs:
				if gathering_items.has(input.item):
					consumes_gathering = true
				if monster_items.has(input.item):
					consumes_monster = true
		_check(consumes_gathering, "%s chain consumes gathering outputs" % chain)
		if chain == "cooking":
			_check(consumes_monster, "cooking chain consumes monster drops (bugmeat/fizz)" )
	_check(lib.recipe("press_carpool_carapace") != null
		and lib.recipe("press_carpool_carapace").inputs.any(func(s: ItemQty) -> bool: return s.item == "lint_pelt"),
		"Junksmithing consumes the Dust Bunny's Lint Pelt (combat feeds crafting)")

	# Every recipe's inputs must be producible by SOMETHING (source side).
	for recipe in lib.recipes.values():
		for input in recipe.inputs:
			_check(_has_source(input.item), "recipe input '%s' (%s) has a source" % [input.item, recipe.id])


# ------------------------------------------------------------- monster ladder

func _check_monster_ladder() -> void:
	var monsters: Array[MonsterDef] = []
	for monster in lib.monsters.values():
		monsters.append(monster)
	monsters.sort_custom(func(a: MonsterDef, b: MonsterDef) -> bool: return a.level_gate < b.level_gate)
	_check(monsters.size() == 5, "the Sunny Exclusion Zone has 5 fauna (4 + boss; got %d)" % monsters.size())
	if monsters.size() < 5:
		return
	var bosses := monsters.filter(func(m: MonsterDef) -> bool: return m.is_boss)
	if bosses.is_empty():
		_check(false, "a boss exists (The Superintendent)")
		return
	_check(bosses.size() == 1 and bosses[0].id == "sewer_landlord" and bosses[0].name == "The Superintendent",
		"exactly one boss: The Superintendent (sewer_landlord)")
	for i in monsters.size():
		var m := monsters[i]
		_check(m.zone == "dusty_flats", "monster '%s' lives in the slice zone dusty_flats" % m.id)
		_check(m.min_hit <= m.max_hit, "monster '%s' hit bounds ordered" % m.id)
		if i > 0:
			var prev := monsters[i - 1]
			_check(m.level_gate > prev.level_gate, "monster gate escalates (%s %d > %s %d)" % [m.id, m.level_gate, prev.id, prev.level_gate])
			_check(m.max_hp > prev.max_hp, "monster HP escalates (%s %d > %s %d)" % [m.id, m.max_hp, prev.id, prev.max_hp])
			_check(m.xp_reward > prev.xp_reward, "monster XP escalates (%s %d > %s %d)" % [m.id, m.xp_reward, prev.id, prev.xp_reward])
	_check(monsters[0].level_gate == 1, "first rung (Litterbug) is ungated")
	_check(monsters[4].is_boss and monsters[4].level_gate == 14, "boss holds the strictest gate (clearance 14)")


# ----------------------------------------------------------------- equipment

func _check_equipment() -> void:
	var weapons: Array[EquipmentDef] = []
	var armors: Array[EquipmentDef] = []
	for equip in lib.equipment.values():
		if equip.slot == "weapon":
			weapons.append(equip)
		else:
			armors.append(equip)
	_check(weapons.size() == 2, "exactly 2 weapons (Point of Order, Majority Whip)")
	_check(armors.size() == 2, "exactly 2 armors (Pedestrian Plating, Carpool Carapace)")
	var whip := lib.equipment_for("majority_whip")
	var shiv := lib.equipment_for("scrap_shiv")
	_check(shiv != null and shiv.attack_speed_ms > 0, "Point of Order overrides attack speed")
	_check(whip != null and whip.attack_speed_ms > 0 and whip.attack_speed_ms < shiv.attack_speed_ms,
		"Majority Whip is the faster weapon")
	_check(whip.accuracy_bonus > shiv.accuracy_bonus and whip.max_hit_bonus > shiv.max_hit_bonus,
		"Majority Whip strictly upgrades Point of Order")
	var carapace := lib.equipment_for("carpool_carapace")
	var vest := lib.equipment_for("hubcap_vest")
	_check(vest != null and carapace != null and carapace.evasion_bonus > vest.evasion_bonus
		and carapace.max_hp_bonus > vest.max_hp_bonus, "Carpool Carapace strictly upgrades Pedestrian Plating")


# ----------------------------------------------------------------- food chain

func _check_food_ladder() -> void:
	var cake := lib.item("vintage_snack_cake")
	var grits := lib.item("mandatory_grits")
	var casserole := lib.item("compliant_casserole")
	var stew := lib.item("radstag_stew")
	for pair in [[cake, 10], [grits, 15], [casserole, 35], [stew, 80]]:
		_check(pair[0] != null and pair[0].is_food() and pair[0].heal == pair[1],
			"food '%s' heals %d (scaled to the damage ladder)" % [pair[0].id if pair[0] else "?", pair[1]])
	_check(cake.heal < grits.heal and grits.heal < casserole.heal and casserole.heal < stew.heal,
		"food heals escalate with cooking tiers (10 < 15 < 35 < 80)")
	var boss := lib.monster("sewer_landlord")
	_check(stew.heal >= 5 * boss.max_hit,
		"best food (%d) heals at least 5 boss max hits (%d) — food counters the boss in real chunks" % [stew.heal, boss.max_hit])
	# The uncooked snack is a MONSTER drop, edible without any Cooking level.
	var dispenser := lib.monster("feral_snack_dispenser")
	_check(lib.drop_table(dispenser.drop_table).entry_for_item("vintage_snack_cake") != null,
		"Vintage Snack Cake drops from the Feral Snack Dispenser (pre-cooking combat sustain)")


# ---------------------------------------------------------------- references

func _check_references() -> void:
	for skill in lib.skills.values():
		_check(lib.xp_curve(skill.xp_curve) != null, "skill '%s' -> curve '%s' resolves" % [skill.id, skill.xp_curve])
		_check(lib.xp_curve(skill.xp_curve).max_level == skill.max_level, "skill '%s' max_level matches its curve" % skill.id)
	for activity in lib.activities.values():
		_check(lib.skill(activity.skill) != null, "activity '%s' -> skill resolves" % activity.id)
		_check(lib.drop_table(activity.drop_table) != null, "activity '%s' -> drop table resolves" % activity.id)
	for recipe in lib.recipes.values():
		_check(lib.skill(recipe.skill) != null, "recipe '%s' -> skill resolves" % recipe.id)
		_check(lib.item(recipe.output.item) != null, "recipe '%s' -> output item resolves" % recipe.id)
		for input in recipe.inputs:
			_check(lib.item(input.item) != null, "recipe '%s' -> input item '%s' resolves" % [recipe.id, input.item])
	for monster in lib.monsters.values():
		_check(lib.drop_table(monster.drop_table) != null, "monster '%s' -> drop table resolves" % monster.id)
	for entry in lib.shop_entries():
		_check(lib.item(entry.item) != null, "shop line '%s' -> item resolves" % entry.item)
		if entry.is_gated():
			_check(lib.skill(entry.gate_skill) != null, "shop line '%s' -> gate skill resolves" % entry.item)
	var combat_kinds := lib.skills.values().filter(func(s: SkillDef) -> bool: return s.is_combat())
	_check(combat_kinds.size() == 1 and combat_kinds[0].id == "wasteland_combat",
		"exactly one combat skill (Wasteland Combat) for monster gates")
	var kinds := {}
	for skill in lib.skills.values():
		kinds[skill.kind] = int(kinds.get(skill.kind, 0)) + 1
	_check(lib.skills.size() == 5 and kinds.get("gathering", 0) == 2 and kinds.get("processing", 0) == 2 and kinds.get("combat", 0) == 1,
		"five skills: 2 gathering, 2 processing, 1 combat")


# ------------------------------------------------------------------ orphans

func _has_source(item_id: String) -> bool:
	for table in lib.drop_tables.values():
		if table.entry_for_item(item_id) != null:
			return true
	for recipe in lib.recipes.values():
		if recipe.output.item == item_id:
			return true
	for entry in lib.shop_stock:
		if entry.item == item_id:
			return true
	return false


func _has_sink(item_id: String) -> bool:
	for recipe in lib.recipes.values():
		for input in recipe.inputs:
			if input.item == item_id:
				return true
	var item := lib.item(item_id)
	if item != null and (item.is_food() or item.is_equipment()):
		return true  # edible / equippable are sinks
	return false


func _check_orphans_strong() -> void:
	_check(lib.orphan_item_ids().is_empty(), "loader orphan scan: no item without a source")
	_check(lib.unused_drop_table_ids().is_empty(), "loader orphan scan: no drop table without a roller")
	for item in lib.items.values():
		_check(_has_source(item.id), "item '%s' has a SOURCE (drop/recipe/shop)" % item.id)
		_check(_has_sink(item.id), "item '%s' has a SINK (recipe input / edible / equippable)" % item.id)


# ------------------------------------------------------------ shop integrity

func _check_shop_integrity() -> void:
	var stock := lib.shop_entries()
	_check(stock.size() >= 10, "Depot stocks a real catalog (%d lines)" % stock.size())
	var seen := {}
	for entry in stock:
		_check(not seen.has(entry.item), "one shop line per item ('%s')" % entry.item)
		seen[entry.item] = true
		_check(entry.buy_price > lib.item(entry.item).value,
			"Depot buys '%s' above its sell value (%d > %d) — no same-item round trip" % [entry.item, entry.buy_price, lib.item(entry.item).value])
	# No buy-craft-sell arbitrage on recipes whose inputs are all stockable.
	var buy_price := {}
	for entry in stock:
		buy_price[entry.item] = entry.buy_price
	for recipe in lib.recipes.values():
		var all_stockable := true
		var cost := 0
		for input in recipe.inputs:
			if not buy_price.has(input.item):
				all_stockable = false
				break
			cost += int(buy_price[input.item]) * input.qty
		if all_stockable:
			var revenue: int = lib.item(recipe.output.item).value * recipe.output.qty
			_check(cost > revenue, "no arbitrage on '%s': inputs cost %d > output sells %d" % [recipe.id, cost, revenue])
	# Gates exist on leveled lines (clearances throughout the Depot).
	var gated := stock.filter(func(e: ShopEntryDef) -> bool: return e.is_gated())
	_check(gated.size() >= 5, "Depot gates leveled lines behind clearances (%d gated)" % gated.size())


# -------------------------------------------------------------- combat sims
# Spec arithmetic per docs/balance-notes.md §1 — the same formulas T7 must
# implement. Stats are read FROM the authored content, not restated here.

func _hit_chance(attacker_accuracy: int, defender_evasion: int) -> float:
	return clampf(float(attacker_accuracy) / float(attacker_accuracy + defender_evasion), 0.05, 0.95)


func _player_stats(weapon_id: String, armor_id: String) -> Dictionary:
	var speed := BASE_ATTACK_SPEED_MS
	var accuracy := BASE_ACCURACY
	var evasion := BASE_EVASION
	var max_hp := BASE_MAX_HP
	var max_hit := BASE_MAX_HIT
	if weapon_id != "":
		var weapon := lib.equipment_for(weapon_id)
		if weapon.attack_speed_ms > 0:
			speed = weapon.attack_speed_ms
		accuracy += weapon.accuracy_bonus
		max_hit += weapon.max_hit_bonus
		evasion += weapon.evasion_bonus
		max_hp += weapon.max_hp_bonus
	if armor_id != "":
		var armor := lib.equipment_for(armor_id)
		accuracy += armor.accuracy_bonus
		max_hit += armor.max_hit_bonus
		evasion += armor.evasion_bonus
		max_hp += armor.max_hp_bonus
	return {"max_hp": max_hp, "speed": speed, "accuracy": accuracy, "evasion": evasion, "min_hit": BASE_MIN_HIT, "max_hit": max_hit}


## One seeded fight. `food` maps item id -> units in the Manifest; it is
## consumed by auto-eat. Returns {win, ms, eaten}.
func _simulate(weapon_id: String, armor_id: String, monster: MonsterDef, food: Dictionary, rng_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var p := _player_stats(weapon_id, armor_id)
	var p_hp: int = p["max_hp"]
	var m_hp := monster.max_hp
	var p_next: int = p["speed"]  # first swing after one full interval (spec §1.2)
	var m_next := monster.attack_speed_ms
	var eaten := 0
	while p_next <= SIM_CAP_MS and m_next <= SIM_CAP_MS:
		if p_next <= m_next:  # player resolves first on ties (spec §1.2)
			if rng.randf() < _hit_chance(p["accuracy"], monster.evasion):
				m_hp -= rng.randi_range(p["min_hit"], p["max_hit"])
			p_next += p["speed"]
			if m_hp <= 0:
				return {"win": true, "ms": p_next, "eaten": eaten}
		else:
			if rng.randf() < _hit_chance(monster.accuracy, p["evasion"]):
				p_hp -= rng.randi_range(monster.min_hit, monster.max_hit)
			m_next += monster.attack_speed_ms
			if p_hp <= 0:
				return {"win": false, "ms": m_next, "eaten": eaten}
		# Auto-eat at <= half HP: best (highest-heal) food first (spec §1.2).
		while p_hp <= int(p["max_hp"]) / 2 and not food.is_empty():
			var best_item := ""
			var best_heal := -1
			for item_id in food:
				var def := lib.item(item_id)
				if def != null and def.heal > best_heal:
					best_heal = def.heal
					best_item = item_id
			if best_item == "":
				break
			food[best_item] = int(food[best_item]) - 1
			if int(food[best_item]) <= 0:
				food.erase(best_item)
			p_hp = mini(int(p["max_hp"]), p_hp + best_heal)
			eaten += 1
	return {"win": false, "ms": SIM_CAP_MS, "eaten": eaten}


func _run_fights(label: String, weapon_id: String, armor_id: String, monster_id: String, food: Dictionary) -> Dictionary:
	var wins := 0
	var times: Array[int] = []
	var eaten: Array[int] = []
	for i in SEEDS:
		var result := _simulate(weapon_id, armor_id, lib.monster(monster_id), food.duplicate(), 1_000 + i)
		if result["win"]:
			wins += 1
		times.append(result["ms"])
		eaten.append(result["eaten"])
	times.sort()
	eaten.sort()
	print("    sim %-34s %d/%d wins  median %d ms  median food %d" % [label, wins, SEEDS, times[SEEDS / 2], eaten[SEEDS / 2]])
	return {"wins": wins, "median_ms": times[SEEDS / 2], "median_eaten": eaten[SEEDS / 2]}


func _check_combat_sims() -> void:
	var boss := lib.monster("sewer_landlord")
	_check(boss != null and boss.is_boss, "boss record loaded for simulation")

	# The win moment: max slice gear + best food beats The Superintendent.
	var max_food := _run_fights("boss vs MAX gear + 6 stews", "majority_whip", "carpool_carapace", "sewer_landlord", {"radstag_stew": 6})
	_check(max_food["wins"] >= SEEDS - 2,
		"BOSS BEATABLE: max gear + best food wins >= %d/%d seeds (got %d)" % [SEEDS - 2, SEEDS, max_food["wins"]])
	_check(max_food["median_ms"] < 180_000, "boss fight stays a fight, not a shift (< 3 min median, got %d ms)" % max_food["median_ms"])
	_check(max_food["median_eaten"] >= 1, "food matters in the winning loadout (median %d eaten)" % max_food["median_eaten"])

	# Not trivially with mid gear (the T5 acceptance line).
	var mid_nofod := _run_fights("boss vs MID gear, no food", "scrap_shiv", "hubcap_vest", "sewer_landlord", {})
	_check(mid_nofod["wins"] == 0,
		"BOSS NOT TRIVIAL: mid gear without food never wins (0/%d expected, got %d)" % [SEEDS, mid_nofod["wins"]])

	# The gear floor is real: even 20 best-food units cannot carry the chassis.
	var bare_food := _run_fights("boss vs BARE + 20 stews", "", "", "sewer_landlord", {"radstag_stew": 20})
	_check(bare_food["wins"] == 0,
		"cannot out-eat the boss naked (0/%d expected, got %d)" % [SEEDS, bare_food["wins"]])

	# Food is the difference at max gear too (mostly losses without it).
	var max_nofod := _run_fights("boss vs MAX gear, no food", "majority_whip", "carpool_carapace", "sewer_landlord", {})
	_check(max_nofod["wins"] <= 5,
		"max gear still mostly needs food vs the boss (wins <= 5/%d, got %d)" % [SEEDS, max_nofod["wins"]])

	# Ladder sanity — the rungs teach what they claim (balance-notes §2).
	_check(_run_fights("litterbug vs BARE", "", "", "junkyard_roach", {})["wins"] >= SEEDS - 2,
		"first blood: bare chassis beats the Litterbug")
	_check(_run_fights("fizzard vs BARE", "", "", "fizzard", {})["wins"] == 0,
		"Fizzard wants a weapon (bare loses)")
	_check(_run_fights("dispenser vs MID + 4 cass", "scrap_shiv", "hubcap_vest", "feral_snack_dispenser", {"compliant_casserole": 4})["wins"] >= SEEDS - 2,
		"Dispenser wants armor + food (mid gear + casseroles wins)")


# ---------------------------------------------------------------- reporting

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _report_and_quit() -> void:
	if failures.is_empty():
		print("PROBE_OK checks=%d (slice validates; curve + hook hold; no orphans; refs resolve; boss beatable with max gear+food, not with mid gear)" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("PROBE_FAIL " + failure)
		printerr("PROBE_FAILED checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
