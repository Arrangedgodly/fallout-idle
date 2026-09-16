# Balance Notes — Valued Resident vertical slice

Authored by T5 (Data lane, Mr. Fantastic; carrying Professor X's
genre-conventions claims). Source of truth for every number lives in
`data/*.json`; this file records the *reasoning*, the **combat spec T7 must
implement**, the intended progression timeline to the slice's win moment
(boss clear), and the economy rules the numbers obey. Balance is tunable
data (town-hall disposition) — change `data/`, then re-run
`tests/probe_balance.gd`; update this file when a design *intent* changes,
not when a number twiddles.

## 1. Combat spec (binding for T7)

Combat formulas were not defined anywhere before T5, so **this section is
the spec** T7 implements and `tests/probe_balance.gd` simulates against.
T7 owns the engine-side constants in code (content governs monsters and
gear, not the player chassis — `docs/content-schema.md`).

### 1.1 Player chassis (T7 engine constants)

| Constant | Value | Notes |
|---|---|---|
| `BASE_MAX_HP` | 100 | before armor `max_hp_bonus` |
| `BASE_ATTACK_SPEED_MS` | 3000 | replaced by equipped weapon's `attack_speed_ms` |
| `BASE_ACCURACY` | 30 | additive with weapon `accuracy_bonus` |
| `BASE_EVASION` | 10 | additive with armor `evasion_bonus` |
| `BASE_MIN_HIT` | 1 | player damage floor (not equipment-bonusable) |
| `BASE_MAX_HIT` | 4 | additive with weapon `max_hit_bonus` |

### 1.2 Formulas

- **Engage:** combat starts at `t = 0`; each combatant's first attack lands
  at `t = their attack_speed_ms` (one full interval of wind-up), then every
  subsequent interval. All integer milliseconds.
- **Hit roll:** attacker swings; `hit_chance = clamp(attacker_accuracy / (attacker_accuracy + defender_evasion), 0.05, 0.95)`.
  Harmonic ratio: equal stats = 50%, one-sided stats saturate at 5%/95%.
  Integer-exact when possible: compute as `acc * 10000 / (acc + eva)` basis
  points vs a d10000 roll (T14's int-math rule).
- **Damage:** on hit, `damage = randi_range(attacker_min_hit, attacker_max_hit)`.
- **Ordering:** when player and monster attacks land on the same tick, the
  player's attack resolves first; check victory/death after each attack.
- **Death:** player HP ≤ 0 → combat stops, RETURN TO SHELTER, zero item/XP
  loss (town-hall). Monster HP ≤ 0 → victory, `xp_reward` to Wasteland
  Combat, `drop_table` rolled.
- **Auto-eat:** after any monster damage, if `hp <= max_hp / 2` (integer
  division), eat one unit of the **highest-`heal` food in the Manifest**,
  instantly, `hp = min(max_hp, hp + heal)`. Repeat while at/below threshold
  and food remains. Eating is not an attack and costs no time.

### 1.3 Equipment application

Bonuses are additive onto the chassis (`content-schema.md`); a weapon's
`attack_speed_ms` **replaces** `BASE_ATTACK_SPEED_MS`. One weapon slot, one
armor slot. Equipping mid-fight recomputes stats next tick (T7 choice; the
probe equips before engage).

| Item (slot) | Speed | Acc + | Max hit + | Eva + | Max HP + |
|---|---|---|---|---|---|
| Point of Order (weapon, T3) | 2600 | 10 | 4 | — | — |
| Majority Whip (weapon, T4) | 2000 | 45 | 14 | — | — |
| Pedestrian Plating (armor, T3) | — | — | — | 12 | 20 |
| Carpool Carapace (armor, T4) | — | — | — | 30 | 50 |

Derived loadouts the sim uses (names per naming bible):

| Loadout | HP | Speed | Acc | Eva | Dmg |
|---|---|---|---|---|---|
| Bare (chassis) | 100 | 3000 | 30 | 10 | 1–4 (avg 2.5) |
| Mid = Point of Order + Pedestrian Plating | 120 | 2600 | 40 | 22 | 1–8 (avg 4.5) |
| Max = Majority Whip + Carpool Carapace | 150 | 2000 | 75 | 40 | 1–18 (avg 9.5) |

### 1.4 T7 spec addenda (choices where §1.1–§1.3 were silent — binding)

Authored by T7 (Game loop lane) 2026-09-15; each fills a gap the probe's sim
never had to cross. Live implementations: `scripts/engine/combat_session.gd`.

1. **HP reset between fights:** §1.2 did not say what HP carries across
   fights. Ruling: **player HP resets to full (derived max_hp) and monster
   HP to its max_hp on every engage.** Consequences: death has zero
   aftertaste (already zero loss, now zero limp), retreat-and-re-engage is a
   full reset for both sides, and no cross-fight HP state needs persisting
   except mid-fight saves.
2. **Offline combat progresses at full rate, bounded by survivability**
   (coordinator ruling 2026-09-15 — SUPERSEDES this addendum's original
   no-offline-combat disposition of the same day; the faithful reading of
   town-hall's "uncapped full-rate offline for all activities"). On load
   with mid-fight combat state, a **seeded event-ordered survivable replay**
   advances the fight exactly as the live tick would (same swing/auto-eat
   helpers, same roll order, same RNG stream) until either:
   **(a) the monster dies** → the normal victory chain: drops rolled, XP
   granted (level crossings ride the MAIL CALL payload, no immediate
   signals — T6's offline policy), first boss clear sets `zone_clear`;
   while a monster is selected the patrol **re-engages it at the kill
   instant and keeps farming** (each engage reseeds the combat stream, so
   the offline farm loop is the same deterministic loop live play
   produces: identical fight, identical drops, identical food cost per
   iteration); or **(b) a monster blow would reduce player HP to ≤ 0** →
   the blow **never lands**: the patrol is recalled at that instant
   (phase `"recalled"` — RETURN TO SHELTER presentation, player ALIVE at
   pre-blow HP, zero loss, pendings cleared). **A no-agency death can never
   occur offline.** Food exhaustion is the usual recall path: auto-eat
   extends survival exactly as live until the stack runs dry, then the next
   killing-blow-in-waiting recalls. Scope + bounds: the replay runs only
   when the save left a fight in progress (idle/victory/dead/recalled
   saves never auto-start fights); it is bounded by the gap's elapsed ms
   and the food stack (plus an O(events) catch-all far beyond any sane
   gap); activities replay first, so combat can eat food a Cooking slot
   banked during the same gap (the honest live-concurrency interplay);
   boss-clear is achievable offline only with sufficient food, at the
   bounded deterministic farm rate. A still-fighting resume mirrors T6's
   anchor rewind: pending attack times shift back by exactly the gap,
   preserving the wind-up phase. The MAIL CALL payload reports combat gains
   (kills, drops/XP deltas, level crossings) plus a **"PATROL RECALLED"**
   line when the survivability bound tripped. No divergence from
   "all activities" remains.
3. **Equipment is consumed from the Manifest on equip** (unequip returns
   it): equipped gear cannot also be sold or double-equipped; the Manifest
   is the single honest ledger. Slots: one weapon, one armor; the
   EquipmentDef decides which slot an item fills.
4. **Combat runs concurrently with all non-combat skill slots**
   (Melvor-style, matching T6's per-skill concurrency model). §4's "combat
   either runs as the activity or between sessions" assumption is therefore
   the conservative reading of a richer rule — a superset that only
   accelerates the timeline estimates.
5. **Mid-fight equip recomputes derived stats next tick** (§1.3 already
   chose recompute-next-tick): a pending attack keeps its scheduled time;
   the NEXT interval uses the new attack speed; HP clamps into a lowered
   max_hp. Engaging a new monster mid-fight abandons the old fight (both
   sides reset per addendum 1).
6. **Hit rolls are the integer form of §1.2:** basis points
   `clamp(acc * 10000 / (acc + eva), 500, 9500)` vs one d10000
   (`randi_range(0, 9999) < bp`) — the spec's prescribed int-exact
   representation (T14's int-math rule). The T5 probe's float sim
   (`randf() < clampf(...)`) remains the balance reference; the two agree in
   distribution to < 0.01% per roll (integer floor of the same ratio).
7. **RNG streams:** one combat stream per world seed, FNV-1a of
   `world_seed|wasteland_combat` (T6's formula over the combat skill id);
   engaging reseeds it, so the same seed + gear + monster reproduces the
   same fight bit-for-bit; mid-fight saves persist the stream state exactly
   (int64-as-string, T3's convention). Victory drops roll on the same
   stream in ActivityEngine's draw order (pick, then qty, entry order).

## 2. Monster ladder and the boss gate

One zone, The Sunny Exclusion Zone (`dusty_flats`). Gates are Wasteland
Combat clearances. The ladder teaches one lesson per rung:

| Monster | Gate | HP | Spd | Acc | Eva | Dmg | XP | The lesson |
|---|---|---|---|---|---|---|---|---|
| Litterbug | 1 | 18 | 2800 | 15 | 4 | 0–2 | 25 | first blood, bare hands fine (~27 s) |
| Greater Dust Bunny | 4 | 42 | 3000 | 22 | 8 | 1–4 | 90 | longer fight, still safe bare (~66 s) |
| Fizzard | 7 | 78 | 2600 | 30 | 14 | 2–7 | 260 | wants a weapon (bare loses; Point of Order wins) |
| Feral Snack Dispenser | 10 | 130 | 3400 | 40 | 18 | 4–12 | 550 | wants armor **and** food (mid gear no-food loses ~90%) |
| **The Superintendent** (boss) | 14 | 340 | 2400 | 60 | 36 | 4–13 | 1000 | wants max slice gear + best food |

**Boss intent (simulated, 200 seeds each, spec above):**

| Loadout | Result | Median |
|---|---|---|
| Max gear + 6 Chef's Regret | **200 W / 0 L** | 108 s, eats 2 |
| Max gear, no food | 9 W / 191 L | dies 74 s |
| Mid gear, no food | **0 W / 200 L** | dies 48 s |
| Mid gear + 20 stews | 200 W / 0 L | 377 s, eats 15 (possible, never trivial) |
| Bare + 20 stews | **0 W / 200 L** | dies ~394 s — gear floor is real |

So: the boss is beatable with max slice gear + food (reliably, in under two
minutes), not trivially with mid gear — mid gear without food always dies,
and even out-fooding the boss on mid gear costs 20 best-tier meals and six
minutes. You cannot out-eat the Superintendent naked: accuracy is the gate.

## 3. XP curve and the first-five-minutes hook (Professor X)

All five skills share `standard_99` (98 hand-tunable steps, total
1,786,225 XP to level 99; every level reachable, strictly increasing).

- **First level-up ≤ 60 s at tier-1 rates:** tier-1 activities grant
  10 XP / 3.0 s = 200 XP/min; `xp_per_level[0] = 20` → **6.0 s** to level 2.
- **3–5 level-ups in the first session:** 5 min of tier-1 gathering =
  1,000 XP → level 6 = **5 level-ups** (top of Professor X's band; first
  level-up at 6 s also satisfies "first XP + drops within ~10 seconds").
- Curve cost at the gates this slice uses: L4 214 · L5 425 · L8 1,702 ·
  L10 3,226 · L14 8,340 · L15 10,116 · L16 12,113 XP.
- Late-game reference: L50 = 278,656; L99 = 1,786,225 XP (≈ 33 h of pure
  tier-4 gathering at 560 XP/min — a long-tail idle target, not slice
  content).

### Activity rates (escalating per tier)

| Tier | Gate | Interval | XP/action | XP/min | Scavenging | Foraging |
|---|---|---|---|---|---|---|
| 1 | 1 | 3000 ms | 10 | 200 | Sort the Scrap Pile | Walk the Glow Rows |
| 2 | 5 | 5000 ms | 24 | 288 | Strip a Wreck | Harvest the 6:14 Plot |
| 3 | 10 | 6000 ms | 48 | 480 | Drain the Sump | Dig the Iodine Beds |
| 4 | 16 | 7500 ms | 70 | 560 | Unbuild the Overpass | Forage the Far Fence |

Tier-2 tables **trickle the tier-3 resource** (5% Girderling in Wreck
Locker, 10% Iodine Root in the Dusk Plot) so eager players can peek ahead;
tier-3+ tables are the efficient source. Melvor-style visible rates
everywhere: all tables total weight 100, one roll per action (the boss's
table rolls twice).

### Processing tiers

Junksmithing (ingots → gear): Smelt Almost Bullion @1 · Draw Compliant
Wire + Braid Patchwork Bolt @4 · gear tier 1 @8 (Forge Point of Order +
Press Pedestrian Plating) · gear tier 2 @15 (Forge Majority Whip + Press
Carpool Carapace — one clearance per gear set; max gear lands with the
boss's combat clearance 14).

Cooking (raw → food): Grind Mandatory Grits @1 · Bake Compliant Casserole
@5 · Simmer Chef's Regret @10 · Reheat Chef's Regret @15. The Reheat line
reissues the same soup from a casserole + Fizz Gland ("TODAY'S MENU IS
YESTERDAY'S MENU") — deliberately the same output; it is the deep-zone
recipe that turns Fizzard organs into top-tier food.

Food ladder vs monster damage (heal / boss avg hit 8.5 / boss max hit 13):

| Food | Heal | Source |
|---|---|---|
| Vintage Snack Cake | 10 | Feral Snack Dispenser drop (edible without Cooking) |
| Mandatory Grits | 15 | Cooking tier 1 |
| Compliant Casserole | 35 | Cooking tier 2 |
| Chef's Regret | 80 | Cooking tiers 3–4 (≈53% of max-gear HP; ~10 boss hits) |

## 4. Intended progression timeline (win moment = boss clear)

Assumptions: one non-combat activity at a time; combat either runs as the
activity or between sessions of it (T6/T7 own the exact concurrency rule —
stated here because the estimate depends on it). Estimates are active
attention; uncapped full-rate offline (town-hall user decision) compresses
every stage. First clear expected **≈ 60–90 min mixed active play**, or
≈ 2 h strictly sequential; overnight idle unlocks all tier-4 content.

| Stage | Est. minutes | What happens |
|---|---|---|
| 1. Compliance orientation | 0–5 | Sort the Scrap Pile: first XP at 3 s, first level-up at 6 s, level ~5 by minute 3; first Almost Bullion; one glow-row pass funds first Grits; first Litterbug kill (bare, ~27 s) — first blood + first monster drop table seen |
| 2. Issued equipment | 5–25 | Strip a Wreck @Scav 5; smelt/grind to Junksmith 4–8; Forge Point of Order (~min 18–22); Dust Bunnies @Combat 4 (bugmeat + lint); Bake Casseroles @Cook 5 |
| 3. Field certification | 20–45 | Fizzards @Combat 7 (want the weapon); Press Pedestrian Plating @Junksmith 10; Dispensers @Combat 10 (want armor + casseroles); Iodine Beds @Forage 10; Simmer Chef's Regret @Cook 10 |
| 4. Elevation | 45–70 | Combat 14 clears the boss clearance; Unbuild the Overpass @Scav 16 or boss-adjacent Girderling trickle funds gear tier 2 @Junksmith 15 (Forge Majority Whip + Press Carpool Carapace; Lint Pelts from bunnies); Reheat Chef's Regret @Cook 15; stock ~6+ stews |
| 5. **Win moment** | ~70–90 | The Superintendent falls in ~110 s with max gear + 2–3 stews eaten; zone clear + Superintendent's Receipts (2 rolls) make repeat clears the idle farm |

T13 should validate stages 1–2 headlessly; stages 3–5 are covered by the
probe's seeded sims (the same arithmetic, no UI).

## 5. Economy rules (Crowns)

- One honest sell price per item (`value`); Depot buy lines always cost
  **more** than they pay (`buy_price > value` — the Depot does not make
  change for feelings, or profit for you).
- **No arbitrage:** for every recipe whose inputs are all Depot-stockable,
  buying inputs costs more than selling the output (e.g. 3 Scrapnel = 24
  cr → Almost Bullion sells 8; Grits 2×9=18 → sells 10). The probe asserts
  this. Cooking for yourself is strictly cheaper than buying food (stew
  buy 200 vs ~43 cr of ingredients) — the loop pays.
- Crafted value-add is modest (scrap 3×2=6 → ingot 8) so selling raw
  surplus is always viable income without making processing a money
  printer.
- Deep Crown sinks: Majority Whip 1,200 / Carpool Carapace 1,500 Depot
  lines (Combat 16 gate) — impatience tax; crafting remains the sane path
  (~40–90 cr of materials each).
- Rough income: tier-1 scavenging surplus sells ≈ 25–40 cr/min; the whip
  costs a few hours of raw selling or ~15 min of ingot-and-surplus play.

## 6. No-orphan contract

Every item has a source **and** a sink (probe-enforced): sources = drop
tables, recipe outputs, Depot stock; sinks = recipe inputs, edibility
(all 4 foods), equippability (all 4 equipment). Notable wiring: Lint Pelt
→ Carpool Carapace (combat feeds crafting), Fizz Gland → Reheat Chef's
Regret, Vintage Snack Cake → edible without Cooking (pre-cooking combat
sustain), Girderling → both tier-4 gear pieces, the boss's table feeds
tier-4 crafting after clear.
