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
##   6. structure: 9 escalating tiers per gathering skill (T24 depth: gates
##      1-70), 20 recipes per processing chain (gear ladder + food tiers +
##      batch lines), a 5+boss ladder in EACH zone, 6 weapons + 6 armors;
##   7. shop integrity: buy > sell everywhere, gates resolvable, no
##      buy-craft-sell arbitrage on fully stockable recipes;
##   8. SEEDED simulated boss fights using the combat spec arithmetic of
##      docs/balance-notes.md §1 (the binding T7 spec: harmonic accuracy
##      roll, bounded damage, first swing after one full interval, auto-eat
##      at half HP): The Superintendent is beatable with max slice gear +
##      best food and NOT with mid gear — and not by out-eating it naked.
##      T24 adds the Gift Court: The Regional Manager (the new apex) is
##      beatable with the tier-4 ladder + Court Feast, NOT with tier-3 gear
##      (even out-fed) — and the zone-2 rungs teach their lessons;
##   9. T20 PERSONNEL ECONOMY — the deputy ladder + orientation stipend in
##      data/staffing.json are priced against an earning curve RECOMPUTED
##      here from the authored content (per-table EV = Σ P x avg_qty x
##      value; gross rate = EV x 60000/interval_ms), not hardcoded: the
##      curve checkpoints hold, each deputy is affordable inside its window
##      on the conservative documented model (and NOT before the window
##      opens), the stipend's sizing rules hold, and the boss sims above
##      still pass unchanged (deputies buy postings, not power).
##      Derivation + assumptions: docs/balance-notes.md §5.1-§5.3.
##  10. T24 DEPTH INTEGRITY — XP-curve coverage (every skill trains from
##      clearance 1 with a next unlock never further than 16 grades away,
##      ladders reaching 40-92; 93-99 is the documented long-tail cap
##      grind), processing XP discipline (per-band best rate never falls as
##      gates rise), every craftable gear piece has a recipe, and the new
##      materials flow both ways (gathering/drop source -> recipe sink).
##  11. T27 OBJECTIVE REWARD ECONOMY — the dossier MERIT PAY ladder
##      (data/objectives.json) modeled into the §5.1 curve: every objective
##      carries a documented expected stamp MINUTE (below), the deputy
##      windows hold with objective income folded in (with-merit crossing
##      inside every window; merit pay never exceeds 20% of duty income at
##      a rung's crossing; not owned at window open; 1.15x margin at close),
##      COMMENDATION XP legs never exceed 20% of one clearance step at their
##      landing level, the boss gate stays crown-proof (T4 Depot impulse
##      lines clearance-gated, merit pay bounded at the deep boundary), and
##      the ladder back-loads past the deputy-4 window. Derivation:
##      docs/balance-notes.md §6.4 (the §6.3 placeholders are superseded).

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
	# T24 depth set (naming-bible §10 T24 table — Class A rows).
	"directive_cord": "Directive Cord",
	"survey_lens": "Survey Lens",
	"heritage_hardware": "Heritage Hardware",
	"counterweight": "Counterweight",
	"quarantine_quince": "Quarantine Quince",
	"notary_nettle": "Notary Nettle",
	"fountain_mint": "Fountain Mint",
	"skylight_bloom": "Skylight Bloom",
	"bagged_ice": "Bagged Ice",
	"foodcourt_tray": "Foodcourt Tray",
	"quorum_alloy": "Quorum Alloy",
	"unanimous_steel": "Unanimous Steel",
	"grade_d_fritters": "Grade-D Fritters",
	"quarantine_compote": "Quarantine Compote",
	"cornmeal": "Mandated Cornmeal",
	"notary_tea": "Notary Tea",
	"fountain_sherbet": "Fountain Sherbet",
	"court_feast": "Court Feast",
	"filibuster": "Filibuster",
	"quorum_gavel": "Quorum Gavel",
	"line_item_veto": "Line-Item Veto",
	"cloture": "Cloture",
	"crosswalk_cage": "Crosswalk Cage",
	"loading_dock_shell": "Loading Dock Shell",
	"motorcade_mantle": "Motorcade Mantle",
	"turnpike_aegis": "Turnpike Aegis",
}

const EXPECTED_RECORD_COUNT := 318  # 47 items + 5 skills + 18 activities + 40 recipes + 29 tables + 11 monsters + 12 equipment + 34 shop lines + 1 curve + 4 T17 deputy rungs + 2 T23 zones + 115 T25 objectives (23/skill)

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
	_check_personnel_economy()
	_check_objective_economy()
	_check_xp_coverage()


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
		_check(tiers.size() == 9, "%s has exactly 9 activity tiers (T24 depth; got %d)" % [skill_id, tiers.size()])
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
		_check(tiers[tiers.size() - 1].level_gate == 70,
			"%s ladder reaches clearance 70 (the L71-99 long-tail is the cap grind)" % skill_id)


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
		_check(recipes.size() == 20, "%s chain grows to 20 recipes (T24 depth; got %d)" % [chain, recipes.size()])
		var gates: Array[int] = []
		for recipe in recipes:
			gates.append(recipe.level_gate)
		gates.sort()
		var bands: Array[int] = []
		for gate in gates:
			if not bands.has(gate):
				bands.append(gate)
		_check(bands.size() >= 10, "%s chain spans >= 10 clearance bands (got %d: %s)" % [chain, bands.size(), str(bands)])
		_check(bands[0] == 1, "%s chain trains from clearance 1" % chain)
		_check(bands[bands.size() - 1] >= 45, "%s chain keeps unlocking deep (%d)" % [chain, bands[bands.size() - 1]])
		# T24 discipline: the best XP rate a band offers never FALLS as the
		# gate rises (batch/reissue lines may trail within a band, never below
		# every cheaper band's best).
		var best_so_far := 0.0
		for gate in bands:
			var best := 0.0
			for recipe in recipes:
				if recipe.level_gate == gate:
					best = maxf(best, 60000.0 * recipe.xp_per_action / recipe.interval_ms)
			_check(best >= best_so_far, "%s band %d best XP rate %.0f never falls below a cheaper band's %.0f" % [chain, gate, best, best_so_far])
			best_so_far = best
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

	# T24: the new materials flow both ways — Junksmithing eats the deep
	# scavenging haul + Gift Court salvage, Cooking eats the new flora and
	# the Gift Court food-court drops.
	for material in ["counterweight", "directive_cord", "survey_lens", "heritage_hardware"]:
		_check(_recipe_consumes("junksmithing", material), "Junksmithing consumes '%s' (the deep haul has a smithing sink)" % material)
	for flora in ["quarantine_quince", "notary_nettle", "fountain_mint", "skylight_bloom"]:
		_check(_recipe_consumes("cooking", flora), "Cooking consumes '%s' (the new flora has a Mess sink)" % flora)
	_check(_recipe_consumes("cooking", "bagged_ice") and _recipe_consumes("cooking", "foodcourt_tray"),
		"Cooking consumes the Gift Court drops (Bagged Ice + Foodcourt Tray)")
	_check(_recipe_consumes("junksmithing", "quorum_alloy") and _recipe_consumes("junksmithing", "unanimous_steel"),
		"Junksmithing consumes both new alloys (the ingot chain extension has gear sinks)")

	# Every equipment item is CRAFTABLE (a recipe outputs it) — the Depot
	# impatience lines are a shortcut, never the only source.
	for equip in lib.equipment.values():
		var craftable := false
		for recipe in lib.recipes.values():
			if recipe.output.item == equip.item:
				craftable = true
				break
		_check(craftable, "equipment '%s' is craftable (a recipe outputs it)" % equip.item)

	# Every recipe's inputs must be producible by SOMETHING (source side).
	for recipe in lib.recipes.values():
		for input in recipe.inputs:
			_check(_has_source(input.item), "recipe input '%s' (%s) has a source" % [input.item, recipe.id])


func _recipe_consumes(skill_id: String, item_id: String) -> bool:
	for recipe in _recipes_for(skill_id):
		for input in recipe.inputs:
			if input.item == item_id:
				return true
	return false


# ------------------------------------------------------------- monster ladder

func _zone_monsters(zone_id: String) -> Array[MonsterDef]:
	var out: Array[MonsterDef] = []
	for monster in lib.monsters.values():
		if monster.zone == zone_id:
			out.append(monster)
	out.sort_custom(func(a: MonsterDef, b: MonsterDef) -> bool: return a.level_gate < b.level_gate)
	return out


func _check_monster_ladder() -> void:
	# -- The Sunny Exclusion Zone: the T5 ladder, unchanged (byte-intent) --
	var sunny := _zone_monsters("dusty_flats")
	_check(sunny.size() == 5, "the Sunny Exclusion Zone has 5 fauna (4 + boss; got %d)" % sunny.size())
	if sunny.size() >= 5:
		var bosses := sunny.filter(func(m: MonsterDef) -> bool: return m.is_boss)
		if bosses.is_empty():
			_check(false, "a boss exists (The Superintendent)")
		else:
			_check(bosses.size() == 1 and bosses[0].id == "sewer_landlord" and bosses[0].name == "The Superintendent",
				"exactly one Sunny boss: The Superintendent (sewer_landlord)")
		for i in sunny.size():
			var m := sunny[i]
			_check(m.zone == "dusty_flats", "monster '%s' lives in the slice zone dusty_flats" % m.id)
			_check(m.min_hit <= m.max_hit, "monster '%s' hit bounds ordered" % m.id)
			if i > 0:
				var prev := sunny[i - 1]
				_check(m.level_gate > prev.level_gate, "monster gate escalates (%s %d > %s %d)" % [m.id, m.level_gate, prev.id, prev.level_gate])
				_check(m.max_hp > prev.max_hp, "monster HP escalates (%s %d > %s %d)" % [m.id, m.max_hp, prev.id, prev.max_hp])
				_check(m.xp_reward > prev.xp_reward, "monster XP escalates (%s %d > %s %d)" % [m.id, m.xp_reward, prev.id, prev.xp_reward])
		_check(sunny[0].level_gate == 1, "first rung (Litterbug) is ungated")
		_check(sunny[4].is_boss and sunny[4].level_gate == 14, "boss holds the strictest gate (clearance 14)")

	# -- The Gift Court (T24): the second zone, gated above the Sunny set --
	var court := _zone_monsters("gift_court")
	_check(court.size() == 6, "the Gift Court has 6 fauna (5 + boss; got %d)" % court.size())
	if court.size() >= 6:
		var bosses := court.filter(func(m: MonsterDef) -> bool: return m.is_boss)
		if bosses.is_empty():
			_check(false, "a Gift Court boss exists (The Regional Manager)")
		else:
			_check(bosses.size() == 1 and bosses[0].id == "regional_manager" and bosses[0].name == "The Regional Manager",
				"exactly one Gift Court boss: The Regional Manager (regional_manager)")
		for i in court.size():
			var m := court[i]
			_check(m.min_hit <= m.max_hit, "monster '%s' hit bounds ordered" % m.id)
			if i > 0:
				var prev := court[i - 1]
				_check(m.level_gate > prev.level_gate, "court gate escalates (%s %d > %s %d)" % [m.id, m.level_gate, prev.id, prev.level_gate])
				_check(m.max_hp > prev.max_hp, "court HP escalates (%s %d > %s %d)" % [m.id, m.max_hp, prev.id, prev.max_hp])
				_check(m.xp_reward > prev.xp_reward, "court XP escalates (%s %d > %s %d)" % [m.id, m.xp_reward, prev.id, prev.xp_reward])
		_check(court[0].level_gate > 14, "the Gift Court opens ABOVE the Sunny boss (first rung gate %d > 14)" % court[0].level_gate)
		_check(court[5].is_boss and court[5].level_gate == 40, "the Regional Manager holds the strictest gate (clearance 40)")
		_check(court[5].xp_reward == 3500, "the Regional Manager pays apex XP (3500)")
	# Zone references resolve for every monster (the loader also enforces).
	for monster in lib.monsters.values():
		_check(lib.zone(monster.zone) != null, "monster '%s' zone '%s' resolves" % [monster.id, monster.zone])


# ----------------------------------------------------------------- equipment

func _check_equipment() -> void:
	var weapons: Array[EquipmentDef] = []
	var armors: Array[EquipmentDef] = []
	for equip in lib.equipment.values():
		if equip.slot == "weapon":
			weapons.append(equip)
		else:
			armors.append(equip)
	_check(weapons.size() == 6, "exactly 6 weapons (2 per tier bracket, T1-T4; got %d)" % weapons.size())
	_check(armors.size() == 6, "exactly 6 armors (2 per tier bracket, T1-T4; got %d)" % armors.size())
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

	# -- T24 gear ladder above the slice set (tier brackets by recipe gate):
	#    T3 (clearance 22-24) and T4 (34-36), each a fast/light pair and a
	#    heavy pair; the fast weapon strictly upgrades on every axis, the
	#    heavy pair trades swing speed for accuracy + max hit.
	var filibuster := lib.equipment_for("filibuster")
	var gavel := lib.equipment_for("quorum_gavel")
	var veto := lib.equipment_for("line_item_veto")
	var cloture := lib.equipment_for("cloture")
	_check(filibuster != null and filibuster.attack_speed_ms < whip.attack_speed_ms
			and filibuster.accuracy_bonus > whip.accuracy_bonus and filibuster.max_hit_bonus > whip.max_hit_bonus,
		"Filibuster strictly upgrades the Majority Whip (faster, truer, harder)")
	_check(gavel != null and gavel.accuracy_bonus > whip.accuracy_bonus and gavel.max_hit_bonus > whip.max_hit_bonus,
		"Quorum Gavel out-hits the Majority Whip (the heavy T3 trade)")
	_check(veto != null and veto.attack_speed_ms < filibuster.attack_speed_ms
			and veto.accuracy_bonus > filibuster.accuracy_bonus and veto.max_hit_bonus > filibuster.max_hit_bonus,
		"Line-Item Veto strictly upgrades the Filibuster")
	_check(cloture != null and cloture.accuracy_bonus > gavel.accuracy_bonus and cloture.max_hit_bonus > gavel.max_hit_bonus,
		"Cloture out-hits the Quorum Gavel (the heavy T4 trade)")
	var crosswalk := lib.equipment_for("crosswalk_cage")
	var dock := lib.equipment_for("loading_dock_shell")
	var mantle := lib.equipment_for("motorcade_mantle")
	var aegis := lib.equipment_for("turnpike_aegis")
	_check(crosswalk != null and dock != null and crosswalk.evasion_bonus > carapace.evasion_bonus
			and crosswalk.max_hp_bonus > carapace.max_hp_bonus,
		"Crosswalk Cage strictly upgrades the Carpool Carapace")
	_check(dock != null and dock.max_hp_bonus > carapace.max_hp_bonus,
		"Loading Dock Shell out-tanks the Carpool Carapace (heavy T3)")
	_check(crosswalk.evasion_bonus >= dock.evasion_bonus and dock.max_hp_bonus >= crosswalk.max_hp_bonus,
		"T3 armor pair splits roles (light evades, heavy tanks)")
	_check(mantle != null and aegis != null and mantle.evasion_bonus > crosswalk.evasion_bonus
			and mantle.max_hp_bonus > crosswalk.max_hp_bonus,
		"Motorcade Mantle strictly upgrades the Crosswalk Cage")
	_check(aegis.max_hp_bonus > dock.max_hp_bonus,
		"Turnpike Aegis out-tanks the Loading Dock Shell (heavy T4)")
	_check(mantle.evasion_bonus >= aegis.evasion_bonus and aegis.max_hp_bonus >= mantle.max_hp_bonus,
		"T4 armor pair splits roles (light evades, heavy tanks)")


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

	# -- T24 food tiers: the heal ladder scales with ingredient rarity, and
	#    the heal VALUES form a strictly increasing ladder. Gate order
	#    interleaves by design (Chef's Regret 80 @10 precedes Grade-D
	#    Fritters 55 @13 — the apex soup early, the mid-tier Fritters as the
	#    cheap filler beneath it); auto-eat best-first always picks the
	#    highest heal unlocked, so effective sustain still only climbs.
	var fritters := lib.item("grade_d_fritters")
	var compote := lib.item("quarantine_compote")
	var tea := lib.item("notary_tea")
	var sherbet := lib.item("fountain_sherbet")
	var feast := lib.item("court_feast")
	for pair in [[fritters, 55], [compote, 120], [tea, 160], [sherbet, 190], [feast, 230]]:
		_check(pair[0] != null and pair[0].is_food() and pair[0].heal == pair[1],
			"T24 food '%s' heals %d (scaled to the Gift Court damage ladder)" % [pair[0].id if pair[0] else "?", pair[1]])
	_check(casserole.heal < fritters.heal and fritters.heal < stew.heal and stew.heal < compote.heal
			and compote.heal < tea.heal and tea.heal < sherbet.heal and sherbet.heal < feast.heal,
		"the heal values form a strictly increasing ladder (10 < 15 < 35 < 55 < 80 < 120 < 160 < 190 < 230); gate order interleaves (Chef's Regret 80 @10 before Grade-D Fritters 55 @13), auto-eat best-first unaffected")
	var rm := lib.monster("regional_manager")
	_check(feast.heal >= 2 * rm.max_hit,
		"the apex food (%d) heals at least 2 Regional Manager max hits (%d) — real chunks vs the burst ladder" % [feast.heal, rm.max_hit])
	var mantle := lib.equipment_for("motorcade_mantle")
	_check(feast.heal * 100 >= 90 * (100 + mantle.max_hp_bonus),
		"the apex food (%d) heals >= 90%% of the T4 light-armor HP pool (%d) — out-eating stays plausible" % [feast.heal, 100 + mantle.max_hp_bonus])
	# Every food tier is the OUTPUT of at least one recipe (edibility is the
	# sink; crafting is the honest source — the snack cake stays the lone
	# monster-drop exception).
	var food_outputs := {}
	for recipe in lib.recipes.values():
		var item := lib.item(recipe.output.item)
		if item != null and item.is_food():
			food_outputs[item.id] = true
	for food_id in ["mandatory_grits", "compliant_casserole", "radstag_stew", "grade_d_fritters",
			"quarantine_compote", "notary_tea", "fountain_sherbet", "court_feast"]:
		_check(food_outputs.has(food_id), "food '%s' is craftable (a recipe outputs it)" % food_id)


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

	# -- The Gift Court (T24; balance-notes §2.1). The Regional Manager is
	#    the slice's new apex: tier-4 ladder + apex food wins, tier-3 gear
	#    does not (even out-fed 20 deep), and no food is no chance.
	var rm := lib.monster("regional_manager")
	_check(rm != null and rm.is_boss, "Regional Manager record loaded for simulation")

	var rm_t4_fast := _run_fights("reg.manager vs T4 fast + 16 feast", "line_item_veto", "motorcade_mantle", "regional_manager", {"court_feast": 16})
	_check(rm_t4_fast["wins"] >= SEEDS - 2,
		"NEW APEX BEATABLE: T4 fast pair + Court Feast wins >= %d/%d (got %d)" % [SEEDS - 2, SEEDS, rm_t4_fast["wins"]])
	var rm_t4_heavy := _run_fights("reg.manager vs T4 heavy + 16 feast", "cloture", "turnpike_aegis", "regional_manager", {"court_feast": 16})
	_check(rm_t4_heavy["wins"] >= SEEDS - 2,
		"T4 heavy pair + Court Feast also wins (>= %d/%d, got %d)" % [SEEDS - 2, SEEDS, rm_t4_heavy["wins"]])
	_check(rm_t4_heavy["median_ms"] < 180_000, "the apex fight stays a fight (< 3 min median, got %d ms)" % rm_t4_heavy["median_ms"])
	_check(rm_t4_heavy["median_eaten"] >= 1, "food matters in the winning loadout (median %d eaten)" % rm_t4_heavy["median_eaten"])

	var rm_t3_heavy := _run_fights("reg.manager vs T3 heavy + 20 feast", "quorum_gavel", "loading_dock_shell", "regional_manager", {"court_feast": 20})
	_check(rm_t3_heavy["wins"] == 0,
		"NOT WITH T3: even out-fed 20 deep the heavy T3 pair never wins (0/%d, got %d)" % [SEEDS, rm_t3_heavy["wins"]])
	var rm_t3_light := _run_fights("reg.manager vs T3 light + 20 feast", "filibuster", "crosswalk_cage", "regional_manager", {"court_feast": 20})
	_check(rm_t3_light["wins"] == 0,
		"NOT WITH T3: the light T3 pair bursts down under 45-99 swings (0/%d, got %d)" % [SEEDS, rm_t3_light["wins"]])
	var rm_t4_nofood := _run_fights("reg.manager vs T4 fast, no food", "line_item_veto", "motorcade_mantle", "regional_manager", {})
	_check(rm_t4_nofood["wins"] == 0,
		"T4 without food never wins (0/%d, got %d) — provisioning is a real lesson" % [SEEDS, rm_t4_nofood["wins"]])
	var rm_t2 := _run_fights("reg.manager vs T2 max + 20 feast", "majority_whip", "carpool_carapace", "regional_manager", {"court_feast": 20})
	_check(rm_t2["wins"] == 0,
		"slice-max gear cannot out-eat the Regional Manager (0/%d, got %d) — burst damage is the gate" % [SEEDS, rm_t2["wins"]])

	# Gift Court rung lessons — the zone-2 ladder teaches in order: T2
	# clears the cart + kiosk, T3 + tea clears the sentinel/escalator/flock.
	_check(_run_fights("cart vs T2, no food", "majority_whip", "carpool_carapace", "runaway_cart", {})["wins"] >= SEEDS - 2,
		"Runaway Cart wants slice-max gear (T2 clears it dry)")
	_check(_run_fights("cart vs T1, no food", "scrap_shiv", "hubcap_vest", "runaway_cart", {})["wins"] == 0,
		"T1 gear loses to the Runaway Cart (zone 2 means business)")
	_check(_run_fights("kiosk vs T2 + 4 regret", "majority_whip", "carpool_carapace", "directory_kiosk", {"radstag_stew": 4})["wins"] >= SEEDS - 2,
		"Directory Kiosk is a T2 tank fight (stews carry it)")
	_check(_run_fights("sentinel vs T3 heavy + 3 tea", "quorum_gavel", "loading_dock_shell", "wet_floor_sentinel", {"notary_tea": 3})["wins"] >= SEEDS - 2,
		"Wet Floor Sentinel wants T3 + tea")
	_check(_run_fights("sentinel vs T2 + 6 regret", "majority_whip", "carpool_carapace", "wet_floor_sentinel", {"radstag_stew": 6})["wins"] <= 5,
		"T2 + slice food mostly FAILS the sentinel (wins <= 5/%d)" % SEEDS)
	_check(_run_fights("escalator vs T3 heavy + 5 tea", "quorum_gavel", "loading_dock_shell", "restless_escalator", {"notary_tea": 5})["wins"] >= SEEDS - 2,
		"Restless Escalator wants T3 + a thermos")
	_check(_run_fights("escalator vs T2 + 10 regret", "majority_whip", "carpool_carapace", "restless_escalator", {"radstag_stew": 10})["wins"] <= 3,
		"T2 + a boatload of stews still fails the escalator (wins <= 3/%d)" % SEEDS)
	_check(_run_fights("flock vs T3 heavy + 7 tea", "quorum_gavel", "loading_dock_shell", "hanger_flock", {"notary_tea": 7})["wins"] >= SEEDS - 2,
		"Hanger Flock wants full T3 + plenty of tea")
	_check(_run_fights("flock vs T2 + 10 regret", "majority_whip", "carpool_carapace", "hanger_flock", {"radstag_stew": 10})["wins"] <= 3,
		"T2 + stews fails the flock (wins <= 3/%d)" % SEEDS)


# -------------------------------------------------------- personnel economy
# T20: the deputy ladder + orientation stipend (data/staffing.json) are
# priced against an earning curve RECOMPUTED here from the authored tables.
# Factors are the documented conservative model of balance-notes §5.1 —
# if you twiddle the content economy, these checkpoints trip before the
# ladder silently mis-paces:
#   phase A (1 posting, minutes 0-15): gathering holds ~70% of attention
#     (grits/ingots/the Litterbug/the Depot trips), retention 0.50 (the
#     other half of the take self-provisions); tier-2 blends from minute 6
#     (both gathering skills cross L5's 425 XP at ~70 XP/min split);
#   phases B-D (2/3/4 postings): retention 0.75 (stockpiles built,
#     processing adds value) and 1.5/2.2/3.0 effective gathering streams —
#     a posting beyond the two gatherings runs cooking/combat value-add,
#     never a third full gathering stream.
const PERSONNEL_ATTENTION := 0.70
const PERSONNEL_RETAIN_NEW := 0.50
const PERSONNEL_RETAIN := 0.75
const PERSONNEL_STREAMS := [1.5, 2.2, 3.0]
const DEPUTY1_FAST_GUARD_MIN := 3  # a pure tier-1 seller cannot own rung 1 inside this

# ------------------------------------------------------ T27 objective economy
# The documented stamp-minute model (balance-notes §6.4): when each dossier
# line is EXPECTED to stamp on the conservative §5.1 phase curve. Derivation
# keys (all in the doc):
#   - level_reach rungs sit at their per-skill clearance-crossing minute
#     (OBJ_LEVEL_MINUTES below — gathering from the phase XP model at the
#     T20 tier schedule: per-skill XP/min = tier XP/min x streams x
#     retention / 2; processing + combat anchored to §4's stage table);
#   - count rungs sit at gate minute + (count x interval / 60) divided by
#     the phase's per-skill posting share, feed-limited where materials
#     lag (e.g. SMELT 250 waits on 750 Scrapnel);
#   - economy rungs sit on the combined curve (crowns_total crosses with
#     merit pay itself folded in), stamped_22 capstones at their dossier's
#     last other rung.
# Minutes are modeled expectations, rounded to the minute — pins compare
# against them deterministically, so a reward retune that breaks a window
# trips HERE before it ships.
const OBJ_MERIT_SHARE := 0.20  # merit pay <= 20% of duty income at a crossing
const OBJ_STAMP_MINUTES := {
	# scavenging
	"scav_clearance_2": 1, "scav_clearance_5": 6, "scav_clearance_10": 27, "scav_clearance_16": 69,
	"scav_clearance_30": 200, "scav_clearance_41": 348, "scav_clearance_54": 552, "scav_clearance_70": 810,
	"scav_sort_25": 4, "scav_sort_250": 28, "scav_strip_50": 17, "scav_sump_40": 32,
	"scav_overpass_60": 78, "scav_corridors_75": 125, "scav_lockers_100": 215, "scav_signal_150": 374,
	"scav_foundation_200": 590, "scav_strongroom_250": 865, "scav_girderling_100": 108,
	"scav_counterweight_250": 430, "scav_sell_scrap_1000": 90, "scav_crowns_5000": 74,
	"scav_stamped_22": 865,
	# foraging
	"forage_clearance_2": 1, "forage_clearance_5": 6, "forage_clearance_10": 27, "forage_clearance_16": 69,
	"forage_clearance_30": 200, "forage_clearance_41": 348, "forage_clearance_54": 552, "forage_clearance_70": 810,
	"forage_glow_25": 4, "forage_glow_250": 28, "forage_plot_50": 17, "forage_beds_40": 32,
	"forage_fence_60": 78, "forage_atrium_75": 125, "forage_relay_100": 215, "forage_hydro_150": 374,
	"forage_greenhouse_200": 590, "forage_canopy_250": 865, "forage_duskcorn_250": 26,
	"forage_bloom_150": 610, "forage_sell_caps_400": 65, "forage_crowns_10000": 100,
	"forage_stamped_22": 865,
	# junksmithing
	"junk_clearance_2": 2, "junk_clearance_8": 20, "junk_clearance_15": 65, "junk_clearance_26": 300,
	"junk_clearance_36": 470, "junk_clearance_45": 750, "junk_clearance_60": 1600,
	"junk_smelt_25": 7, "junk_smelt_250": 45, "junk_wire_50": 30, "junk_bolt_50": 32,
	"junk_shiv_15": 35, "junk_vest_5": 40, "junk_whip_15": 85, "junk_alloy_100": 130,
	"junk_steel_50": 330, "junk_gavel_5": 320, "junk_veto_5": 520, "junk_batch_alloy_50": 800,
	"junk_batch_steel_25": 1700, "junk_sell_bullion_200": 60, "junk_crowns_25000": 240,
	"junk_stamped_22": 1700,
	# cooking
	"cook_clearance_2": 2, "cook_clearance_5": 15, "cook_clearance_13": 55, "cook_clearance_21": 160,
	"cook_clearance_32": 330, "cook_clearance_55": 900, "cook_clearance_85": 2300,
	"cook_grits_25": 7, "cook_grits_250": 45, "cook_casserole_50": 35, "cook_regret_20": 75,
	"cook_fritters_30": 70, "cook_compote_40": 130, "cook_cornmeal_50": 180, "cook_tea_40": 260,
	"cook_sherbet_30": 320, "cook_feast_25": 380, "cook_reissue_25": 450, "cook_bulk_tea_50": 800,
	"cook_mass_regret_15": 2400, "cook_sell_stew_100": 120, "cook_crowns_2500": 48,
	"cook_stamped_22": 2400,
	# wasteland combat (the EXTERIOR DOSSIER)
	"combat_clearance_2": 3, "combat_clearance_4": 20, "combat_clearance_7": 45, "combat_clearance_10": 60,
	"combat_clearance_14": 62, "combat_clearance_22": 130, "combat_clearance_30": 240, "combat_clearance_40": 390,
	"combat_litterbug_10": 14, "combat_litterbug_100": 40, "combat_bunny_50": 40, "combat_fizzard_40": 68,
	"combat_dispenser_25": 85, "combat_escalator_25": 280, "combat_superintendent_5": 85,
	"combat_manager_3": 500, "combat_equip_whip": 66, "combat_equip_carapace": 66,
	"combat_equip_veto": 500, "combat_equip_aegis": 505, "combat_secure_flats": 68,
	"combat_secure_court": 500, "combat_stamped_22": 505,
}

# Per-skill clearance-crossing minutes (the level_reach stamp minutes; also
# the landing-level lookup for the COMMENDATION XP-leg rule). Gathering:
# phase XP model per balance-notes §6.4 (per-skill XP/min = tier rate x
# streams x retention / 2 at the T20 tier schedule, phases A1-D at T1-T4);
# processing/combat: §4's stage-table anchors extended up the ladder.
const OBJ_LEVEL_MINUTES := {
	"scavenging": {2: 1, 5: 6, 10: 27, 16: 69, 30: 200, 41: 348, 54: 552, 70: 810},
	"foraging": {2: 1, 5: 6, 10: 27, 16: 69, 30: 200, 41: 348, 54: 552, 70: 810},
	"junksmithing": {2: 2, 8: 20, 15: 65, 26: 300, 36: 470, 45: 750, 60: 1600},
	"cooking": {2: 2, 5: 15, 13: 55, 21: 160, 32: 330, 55: 900, 85: 2300},
	"wasteland_combat": {2: 3, 4: 20, 7: 45, 10: 60, 14: 62, 22: 130, 30: 240, 40: 390},
}


## EV per action of one table: sum of P(entry) x avg_qty x item value
## (qty uniform in [qty_min, qty_max], the engine's inclusive draw), times
## the table's rolls.
func _table_ev_per_action(table: DropTableDef) -> float:
	var total := 0
	for entry in table.entries:
		total += entry.weight
	var ev := 0.0
	for entry in table.entries:
		var avg_qty := (entry.qty_min + entry.qty_max) / 2.0
		ev += float(entry.weight) / float(total) * avg_qty * float(lib.item(entry.item).value)
	return ev * table.rolls


## Raw-sell gross Crowns/minute of one gathering activity.
func _gross_cr_per_min(activity_id: String) -> float:
	var activity := lib.activity(activity_id)
	return _table_ev_per_action(lib.drop_table(activity.drop_table)) * 60000.0 / float(activity.interval_ms)


## Mean gross of the two gathering skills at a tier (0-indexed).
func _tier_blend(tier_index: int) -> float:
	var tiers := [
		["sort_scrap_pile", "walk_the_glow_rows"],
		["strip_wreck", "harvest_the_614_plot"],
		["drain_the_sump", "dig_the_iodine_beds"],
		["unbuild_the_overpass", "forage_the_far_fence"],
	]
	return (_gross_cr_per_min(tiers[tier_index][0]) + _gross_cr_per_min(tiers[tier_index][1])) / 2.0


## Piecewise cumulative integral of a {end, rate} phase schedule from 0.
func _modeled_cumulative(t: float, phases: Array) -> float:
	var start := 0.0
	var total := 0.0
	for phase in phases:
		if t <= float(phase["end"]):
			return total + maxf(t - start, 0.0) * float(phase["rate"])
		total += (float(phase["end"]) - start) * float(phase["rate"])
		start = float(phase["end"])
	return total


func _check_personnel_economy() -> void:
	# -- curve checkpoints: the bands the ladder was priced on (§5.1 + T24
	#    §6 extension — tiers 5-9 are the depth bands; phases A-D below stay
	#    priced on tiers 1-4 because the new gates (22+) unlock past those
	#    windows on the conservative model) --
	var bands := [[45.0, 70.0], [55.0, 90.0], [60.0, 100.0], [75.0, 110.0],
		[95.0, 135.0], [115.0, 155.0], [140.0, 185.0], [170.0, 220.0], [205.0, 265.0]]
	var gross := {}
	for pair in [["sort_scrap_pile", 0], ["walk_the_glow_rows", 0],
			["strip_wreck", 1], ["harvest_the_614_plot", 1],
			["drain_the_sump", 2], ["dig_the_iodine_beds", 2],
			["unbuild_the_overpass", 3], ["forage_the_far_fence", 3],
			["sweep_service_corridors", 4], ["prune_atrium_thicket", 4],
			["pry_mezzanine_lockers", 5], ["reap_relay_garden", 5],
			["deconstruct_signal_tower", 6], ["tend_hydroponics_bay", 6],
			["excavate_foundation_grid", 7], ["gather_greenhouse_span", 7],
			["audit_archive_vault", 8], ["work_canopy_rows", 8]]:
		var rate := _gross_cr_per_min(pair[0])
		gross[pair[0]] = rate
		_check(rate >= bands[pair[1]][0] and rate <= bands[pair[1]][1],
			"%s gross %.2f cr/min sits in the tier-%d band [%s, %s] the ladder is priced on" % [
				pair[0], rate, int(pair[1]) + 1, str(bands[pair[1]][0]), str(bands[pair[1]][1])])
	var best_t1: float = maxf(gross["sort_scrap_pile"], gross["walk_the_glow_rows"])

	# -- the phase boundaries assume these curve costs (level gates 5/10/16) --
	var curve := lib.xp_curve("standard_99")
	_check(curve != null and curve.total_xp_to_reach(5) == 425
			and curve.total_xp_to_reach(10) == 3226 and curve.total_xp_to_reach(16) == 12113,
		"the curve costs the phase boundaries assume hold (L5 425 / L10 3226 / L16 12113 XP)")

	# -- the documented conservative model (§5.1) --
	var phases := _personnel_phases()
	print("    personnel curve  phase rates cr/min: A1 %.2f  A2 %.2f  B %.2f  C %.2f  D %.2f" % [
		PERSONNEL_ATTENTION * PERSONNEL_RETAIN_NEW * _tier_blend(0),
		PERSONNEL_ATTENTION * PERSONNEL_RETAIN_NEW * _tier_blend(1),
		PERSONNEL_RETAIN * PERSONNEL_STREAMS[0] * _tier_blend(1),
		PERSONNEL_RETAIN * PERSONNEL_STREAMS[1] * _tier_blend(2),
		PERSONNEL_RETAIN * PERSONNEL_STREAMS[2] * _tier_blend(3)])

	# -- the ladder itself (data/staffing.json; prices are T20's tuning) --
	_check(lib.deputies.size() == 4, "deputy ladder holds 4 rungs (got %d)" % lib.deputies.size())
	for i in range(1, lib.deputies.size()):
		_check(lib.deputies[i].price > lib.deputies[i - 1].price,
			"deputy price escalates at rung %d (%d > %d)" % [i + 1, lib.deputies[i].price, lib.deputies[i - 1].price])
	var p1: int = lib.deputies[0].price
	var p2: int = lib.deputies[1].price
	var p3: int = lib.deputies[2].price
	var p4: int = lib.deputies[3].price
	var stipend: int = lib.orientation_stipend
	print("    deputy ladder    %d / %d / %d / %d crowns + stipend %d" % [p1, p2, p3, p4, stipend])

	# -- deputy 1: the first-session unlock (~10-15 min window) --
	# The stipend posts at the SEVENTH stamp (after the first purchase — T18
	# engine), so rung 1 must be affordable from minute-12 first-session
	# income ALONE (duty + merit pay — merit pay is earned income; the T27
	# fold-in, §6.4); the stipend rules below still bind its proportion
	# (§5.2). Duty-alone at minute 12 is 270.0 < 300: the FIRST deputize
	# needs a merit-pay rung or two stamped beside the selling — priced so
	# on purpose (p1 250 -> 300 with the dossier cascade folded in).
	var cum10 := _modeled_cumulative(10.0, phases)
	var cum12 := _modeled_cumulative(12.0, phases)
	var cum15 := _modeled_cumulative(15.0, phases)
	var merit10 := _objective_income_by(10.0)
	var merit12 := _objective_income_by(12.0)
	var merit15 := _objective_income_by(15.0)
	_check(cum10 + merit10 < float(p1), "deputy 1 NOT owned before the window opens (min-10 duty+merit %.1f < %d)" % [cum10 + merit10, p1])
	_check(cum12 + merit12 >= float(p1), "deputy 1 affordable by minute 12 on first-session income (duty+merit %.1f >= %d)" % [cum12 + merit12, p1])
	_check(cum15 + merit15 >= 1.15 * float(p1), "deputy 1 reachable with margin by the window close (min-15 duty+merit %.1f >= 1.15 x %d)" % [cum15 + merit15, p1])
	_check(float(stipend) + cum12 >= float(p1),
		"stipend + modeled minute-12 duty income cover deputy 1 (%d + %.1f >= %d)" % [stipend, cum12, p1])
	_check(p1 > stipend, "deputy 1 costs more than the stipend alone (%d > %d — the resident must still sell)" % [p1, stipend])
	_check(float(stipend) >= 0.5 * float(p1), "stipend funds most of deputy 1 (%d >= %.1f)" % [stipend, 0.5 * float(p1)])
	_check(float(p1) > float(DEPUTY1_FAST_GUARD_MIN) * best_t1,
		"a pure tier-1 seller cannot own deputy 1 inside %d min (%d > %d x %.2f)" % [DEPUTY1_FAST_GUARD_MIN, p1, DEPUTY1_FAST_GUARD_MIN, best_t1])

	# -- deputies 2-4: not affordable when the window opens, comfortably
	# affordable by its close (spendable = modeled earnings minus earlier
	# rungs, bought at their modeled minutes 12/45/130/270 — §5.2).
	var cum30 := _modeled_cumulative(30.0, phases)
	var cum60 := _modeled_cumulative(60.0, phases)
	_check(cum30 - float(p1) < float(p2), "deputy 2 NOT owned at the window open (min-30 spendable %.1f < %d)" % [cum30 - p1, p2])
	_check(cum60 - float(p1) >= 1.15 * float(p2), "deputy 2 affordable by minute 60 with margin (%.1f >= 1.15 x %d)" % [cum60 - p1, p2])
	var cum90 := _modeled_cumulative(90.0, phases)
	var cum180 := _modeled_cumulative(180.0, phases)
	_check(cum90 - float(p1) - float(p2) < float(p3), "deputy 3 NOT owned at the window open (min-90 spendable %.1f < %d)" % [cum90 - p1 - p2, p3])
	_check(cum180 - float(p1) - float(p2) >= 1.15 * float(p3), "deputy 3 affordable by minute 180 with margin (%.1f >= 1.15 x %d)" % [cum180 - p1 - p2, p3])
	var cum240 := _modeled_cumulative(240.0, phases)
	var cum480 := _modeled_cumulative(480.0, phases)
	_check(cum240 - float(p1) - float(p2) - float(p3) < float(p4), "deputy 4 NOT owned at the window open (min-240 spendable %.1f < %d)" % [cum240 - p1 - p2 - p3, p4])
	_check(cum480 - float(p1) - float(p2) - float(p3) >= 1.15 * float(p4), "deputy 4 affordable by minute 480 with margin (%.1f >= 1.15 x %d)" % [cum480 - p1 - p2 - p3, p4])
	# Boss-gate integrity rides the SAME probe run: _check_combat_sims above
	# re-proves §2/§2.1 with content untouched by this ladder (deputies buy
	# postings, not power — §5.3).


## The §5.1 phase schedule, data-recomputed (shared by the personnel and
## objective-economy checks).
func _personnel_phases() -> Array:
	return [
		{"end": 6.0, "rate": PERSONNEL_ATTENTION * PERSONNEL_RETAIN_NEW * _tier_blend(0)},
		{"end": 15.0, "rate": PERSONNEL_ATTENTION * PERSONNEL_RETAIN_NEW * _tier_blend(1)},
		{"end": 60.0, "rate": PERSONNEL_RETAIN * PERSONNEL_STREAMS[0] * _tier_blend(1)},
		{"end": 180.0, "rate": PERSONNEL_RETAIN * PERSONNEL_STREAMS[1] * _tier_blend(2)},
		{"end": 480.0, "rate": PERSONNEL_RETAIN * PERSONNEL_STREAMS[2] * _tier_blend(3)},
	]


# ---------------------------------------------------- T27 objective economy
## Modeled MERIT PAY income (crowns) posted by minute `t` on the stamp table.
func _objective_income_by(t: float) -> float:
	var total := 0.0
	for obj in lib.objectives.values():
		if obj.reward_crowns > 0 and float(int(OBJ_STAMP_MINUTES.get(obj.id, 1_000_000))) <= t:
			total += float(obj.reward_crowns)
	return total


## Invert the (duty [+ merit]) wallet curve: the minute it first covers
## `price` on top of `spent` (bisection; the curve is monotone non-decreasing).
func _crossing_minute(phases: Array, spent: float, price: float, with_merit: bool) -> float:
	var lo := 0.0
	var hi := 4000.0
	for i in range(60):
		var mid := (lo + hi) / 2.0
		var wallet := _modeled_cumulative(mid, phases) - spent
		if with_merit:
			wallet += _objective_income_by(mid)
		if wallet < price:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## The skill's modeled clearance at minute `t` (the XP-leg landing level).
func _level_at_minute(skill_id: String, t: int) -> int:
	var best := 1
	for level in OBJ_LEVEL_MINUTES[skill_id]:
		if int(OBJ_LEVEL_MINUTES[skill_id][level]) <= t:
			best = maxi(best, int(level))
	return best


func _check_objective_economy() -> void:
	var phases := _personnel_phases()
	var curve := lib.xp_curve("standard_99")

	# -- the stamp table IS the shipped set (a content edit trips here) --
	_check(OBJ_STAMP_MINUTES.size() == lib.objectives.size(),
		"the stamp-minute model covers exactly the shipped set (%d entries vs %d objectives)" % [
			OBJ_STAMP_MINUTES.size(), lib.objectives.size()])
	var covered := true
	for obj in lib.objectives.values():
		if not OBJ_STAMP_MINUTES.has(obj.id):
			covered = false
	_check(covered, "every shipped objective id has a modeled stamp minute")

	# -- the deputy windows with merit pay folded in (§6.4) --
	var windows := [[10.0, 15.0], [30.0, 60.0], [90.0, 180.0], [240.0, 480.0]]
	var spent := 0.0
	for k in range(mini(lib.deputies.size(), windows.size())):
		var price := float(lib.deputies[k].price)
		var open_m: float = windows[k][0]
		var close_m: float = windows[k][1]
		var x_duty := _crossing_minute(phases, spent, price, false)
		var x_with := _crossing_minute(phases, spent, price, true)
		var duty_at := _modeled_cumulative(x_duty, phases)
		var merit_at := _objective_income_by(x_duty)
		_check(merit_at <= OBJ_MERIT_SHARE * duty_at,
			"deputy %d: merit pay %.0f cr <= %.0f%% of duty income at the crossing (min %.1f, %.0f cr)" % [
				k + 1, merit_at, OBJ_MERIT_SHARE * 100.0, x_duty, duty_at])
		_check(x_with >= open_m, "deputy %d with merit pay crosses at min %.1f — not before the window opens (%.0f)" % [k + 1, x_with, open_m])
		_check(x_with <= close_m, "deputy %d with merit pay crosses at min %.1f — inside the window (<= %.0f)" % [k + 1, x_with, close_m])
		_check(_modeled_cumulative(open_m, phases) + _objective_income_by(open_m) - spent < price,
			"deputy %d NOT owned at the window open (min-%.0f duty+merit-spendable %.1f < %.0f)" % [
				k + 1, open_m, _modeled_cumulative(open_m, phases) + _objective_income_by(open_m) - spent, price])
		_check(_modeled_cumulative(close_m, phases) + _objective_income_by(close_m) - spent >= 1.15 * price,
			"deputy %d affordable with margin at the window close (min-%.0f duty+merit-spendable %.1f >= 1.15 x %.0f)" % [
				k + 1, close_m, _modeled_cumulative(close_m, phases) + _objective_income_by(close_m) - spent, price])
		print("    objective economy deputy %d (%d cr): duty crossing min %.1f -> with-merit %.1f (merit %.0f cr = %.1f%% of duty)" % [
			k + 1, int(price), x_duty, x_with, merit_at, 100.0 * merit_at / duty_at])
		spent += price

	# -- first-session feel: the onboarding cascade pays, but recognition-scale --
	var merit15 := _objective_income_by(15.0)
	_check(merit15 >= 35.0, "first-session merit take >= 35 cr by minute 15 (got %.0f — early rungs still read as pay)" % merit15)
	var smallest := 1 << 30
	var early_cascade := 0
	for obj in lib.objectives.values():
		if obj.reward_crowns > 0:
			smallest = mini(smallest, obj.reward_crowns)
		if int(OBJ_STAMP_MINUTES[obj.id]) <= 7:
			early_cascade += 1
	_check(smallest >= 3, "every merit line pays at least 3 cr (smallest %d — no comedy rungs)" % smallest)
	_check(early_cascade >= 8, "the onboarding cascade posts >= 8 rungs inside minute 7 (got %d)" % early_cascade)

	# -- COMMENDATION XP legs: <= 20% of ONE step at the landing level --
	for obj in lib.objectives.values():
		if obj.reward_xp_skill != "":
			var landing := _level_at_minute(obj.reward_xp_skill, int(OBJ_STAMP_MINUTES[obj.id]))
			var step: int = curve.xp_per_level[landing - 1]
			_check(float(obj.reward_xp_amount) <= OBJ_MERIT_SHARE * float(step),
				"XP leg '%s' (%d %s XP) <= 20%% of one step at landing %s L%d (step %d)" % [
					obj.id, obj.reward_xp_amount, obj.reward_xp_skill, obj.reward_xp_skill, landing, step])

	# -- boss gate stays crown-proof (§5.3 with merit pay folded in) --
	# The intended T4 path is CRAFTED (clearances 34/36 + Unanimous Steel —
	# zero crowns in any recipe input); the Depot impulse lines stay
	# clearance-gated, so no wallet size skips the gate; and merit pay stays
	# bounded at the deep boundary (it can never out-pace duty income).
	for item_id in ["line_item_veto", "motorcade_mantle", "cloture", "turnpike_aegis"]:
		var line: ShopEntryDef = null
		for entry in lib.shop_entries():
			if entry.item == item_id:
				line = entry
		_check(line != null and line.is_gated() and line.gate_skill == "wasteland_combat" and line.gate_level >= 34,
			"Depot impulse line '%s' stays combat-clearance-gated >= 34 (crowns never buy past the boss gate)" % item_id)
	_check(_objective_income_by(480.0) <= OBJ_MERIT_SHARE * _modeled_cumulative(480.0, phases),
		"merit pay by minute 480 (%.0f cr) <= 20%% of duty income (%.0f cr) — no deputy-skip scale" % [
			_objective_income_by(480.0), _modeled_cumulative(480.0, phases)])

	# -- the ladder back-loads past the deputy-4 window (§6.3 intent, kept) --
	var lifetime := 0
	var per_skill := {}
	for obj in lib.objectives.values():
		lifetime += obj.reward_crowns
		per_skill[obj.skill] = int(per_skill.get(obj.skill, 0)) + obj.reward_crowns
	_check(_objective_income_by(480.0) <= 0.45 * float(lifetime),
		"the ladder back-loads: <= 45%% of lifetime merit posts by minute 480 (got %.0f of %d)" % [
			_objective_income_by(480.0), lifetime])
	for skill_id in per_skill:
		_check(int(per_skill[skill_id]) >= 5000 and int(per_skill[skill_id]) <= 12000,
			"dossier '%s' lifetime merit %d cr sits in the 5,000-12,000 spread band" % [skill_id, int(per_skill[skill_id])])
	print("    objective economy lifetime ladder %d cr (T25 placeholder 71,480); by min 480: %.0f cr" % [
		lifetime, _objective_income_by(480.0)])


# ------------------------------------------------------ T24 XP-curve coverage
## Every level 1-99 has something to train toward: each skill trains from
## clearance 1, its own ladder never leaves a dead band wider than 16 grades
## between rungs (the Professor X pacing discipline), every ladder reaches
## deep (gathering 70, smithing 60, cooking 92, combat 40), and the UNION of
## all posted gates keeps a next unlock within 16 grades of every level up
## to 92. L93-99 is the documented long-tail cap grind (balance-notes §3.1)
## — the curve tops at 99 by design and every level stays reachable.
func _check_xp_coverage() -> void:
	var ladders := {
		"scavenging": [], "foraging": [], "junksmithing": [], "cooking": [], "wasteland_combat": []}
	for activity in lib.activities.values():
		ladders[activity.skill].append(activity.level_gate)
	for recipe in lib.recipes.values():
		ladders[recipe.skill].append(recipe.level_gate)
	for monster in lib.monsters.values():
		ladders["wasteland_combat"].append(monster.level_gate)
	var minimums := {"scavenging": 40, "foraging": 40, "junksmithing": 45, "cooking": 60, "wasteland_combat": 40}
	var all_gates: Array[int] = []
	for skill_id in ladders:
		var gates: Array = ladders[skill_id]
		gates.sort()
		all_gates.append_array(gates)
		_check(gates.size() >= 9, "%s ladder has >= 9 rungs (got %d)" % [skill_id, gates.size()])
		_check(int(gates[0]) == 1, "%s trains from clearance 1 (first gate %d)" % [skill_id, gates[0]])
		var max_gap := 0
		for i in range(1, gates.size()):
			max_gap = maxi(max_gap, int(gates[i]) - int(gates[i - 1]))
		_check(max_gap <= 16, "%s ladder leaves no dead band wider than 16 grades between rungs (worst %d)" % [skill_id, max_gap])
		_check(int(gates[gates.size() - 1]) >= int(minimums[skill_id]),
			"%s ladder reaches at least clearance %d (tops at %d)" % [skill_id, minimums[skill_id], gates[gates.size() - 1]])
	all_gates.sort()
	var union_top := all_gates[all_gates.size() - 1]
	_check(union_top == 92, "the union of posted gates reaches clearance 92 (cooking's last batch line; got %d)" % union_top)
	var worst_wait := 0
	for level in range(1, 92):
		var next_gate := 99
		for gate in all_gates:
			if gate > level and gate < next_gate:
				next_gate = gate
		worst_wait = maxi(worst_wait, next_gate - level)
	_check(worst_wait <= 16, "every level 1-91 sees a next unlock within 16 grades (worst wait %d; 92-99 is the documented cap grind)" % worst_wait)


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
