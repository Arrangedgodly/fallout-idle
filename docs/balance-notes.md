# Balance Notes — Valued Resident vertical slice

Authored by T5 (Data lane, Mr. Fantastic; carrying Professor X's
genre-conventions claims); §5.1–§5.3 (personnel economy) authored by T20
(same lane, same lens, 2026-09-17). Source of truth for every number lives in
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

## 5. Economy rules (Crowns) + the personnel economy (T20)

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

### 5.1 The earning curve (T20 derivation — every number recomputed
from `data/*.json` by `tests/probe_balance.gd` `_check_personnel_economy`)

**Per-action expected value** of a drop table = Σ P(entry) × avg_qty ×
`value`, where P = weight/total and avg_qty = (qty_min+qty_max)/2 (the
engine draws qty uniformly, `randi_range` inclusive). **Gross rate** per
posting = EV/action × 60,000/interval_ms, sold raw at the Depot:

| Activity | Gate | EV/action | Gross cr/min |
|---|---|---|---|
| Sort the Scrap Pile (Scav T1) | 1 | 2.850 | **57.0** |
| Walk the Glow Rows (Forage T1) | 1 | 3.000 | **60.0** |
| Strip a Wreck (Scav T2) | 5 | 5.450 | **65.4** |
| Harvest the 6:14 Plot (Forage T2) | 5 | 6.225 | **74.7** |
| Drain the Sump (Scav T3) | 10 | 7.300 | **73.0** |
| Dig the Iodine Beds (Forage T3) | 10 | 7.725 | **77.25** |
| Unbuild the Overpass (Scav T4) | 16 | 11.600 | **92.8** |
| Forage the Far Fence (Forage T4) | 16 | 11.150 | **89.2** |

Skill blend (mean of the two gathering skills): T1 58.5 · T2 70.05 ·
T3 75.125 · T4 91.0 cr/min per full-time posting. (This reconciles the
older "tier-1 surplus ≈ 25–40 cr/min" sketch: gross 57–60 minus the
self-provisioning share.) Combat drops, per kill: Litterbug 2.65 · Dust
Bunny 5.18 · Fizzard 8.40 · Dispenser 6.60 · Superintendent 26.60 cr —
combat pays in XP and food-sustain materials, not Crowns; it is not an
income tier.

**Tier timing** (drives the phase boundaries): at T1's 200 XP/min, with
one posting split across both gathering skills (~70% of attention on
gathering → ~70 XP/min per skill), clearance 5 (425 XP) lands ≈ minute 6,
clearance 10 (3,226 XP) ≈ minute 46 — so the first session is T1-then-T2
rates, T3 is an hours-scale unlock once deputies double the XP stream,
T4 (12,113 XP) sits past the first hour.

**The T20 earning model** (wall-clock from a fresh save; all factors
documented assumptions, deliberately conservative so probe margins are
real):

| Phase | Minutes | Postings | Disposable cr/min | Assumptions |
|---|---|---|---|---|
| A1 | 0–6 | 1 | 0.7 × 0.5 × 58.5 = **20.48** | one posting; gathering holds ~70% of attention (grits, ingots, the Litterbug, the Depot trips take the rest); 50% of the take self-provisions (food + gear materials banked, not sold) |
| A2 | 6–15 | 1 | 0.7 × 0.5 × 70.05 = **24.52** | same, at T2 blends after both skills cross 425 XP ≈ min 6 |
| B | 15–60 | 2 | 0.75 × 1.5 × 70.05 = **78.81** | deputy 1 (~min 11) opens a second concurrent posting; 1.5 effective gathering streams (the resident still rotates Cooking/Junksmithing through a slot); 75% retention — stockpiles are built, processing now adds value |
| C | 60–180 | 3 | 0.75 × 2.2 × 75.125 = **123.96** | deputy 2 (~min 39) + a Cooking posting converting gathered + combat drops into meals (value-add) → 2.2 streams at T3 |
| D | 180–480 | 4 | 0.75 × 3.0 × 91.0 = **204.75** | deputy 3 (~min 123); 3.0 streams at T4 (both gatherings + cooking/combat value-add) |

Cumulative modeled earnings (before purchases): min 10 → 220.9 · min 12
→ 270.0 · min 15 → 343.5 · min 30 → 1,525.6 · min 45 → 2,707.7 · min 60
→ 3,889.8 · min 90 → 7,608.5 · min 135 → 13,186.2 · min 180 → 18,764.5
· min 240 → 31,049.5 · min 270 → 37,192.0 · min 480 → 80,189.5.

### 5.2 The deputy ladder (T20 prices — data/staffing.json)

| Purchase | Price | Window | Modeled crossing | Probe pins |
|---|---|---|---|---|
| DEPUTIZE RESIDENT #1 | **250** | first session, 10–15 min | minute ≈ 11.2 | not affordable at min 10 (220.9 < 250); affordable at min 12 (270.0 ≥ 250) and min 15 (343.5, 1.37×); a pure T1 seller cannot own it inside 3 min (250 > 3 × 60) |
| #2 | **2,000** | early-mid, 30–60 min | minute ≈ 39 | not at min 30 (1,275.6 spendable < 2,000); at min 60 spendable 3,639.8 ≥ 1.15× |
| #3 | **9,500** | mid, 1.5–3 h | minute ≈ 123 | not at min 90 (5,358.5 < 9,500); at min 180 spendable 16,514.5 ≥ 1.15× |
| #4 | **25,000** | late-mid, 4–8 h | minute ≈ 268 (4.5 h) | not at min 240 (19,299.5 < 25,000); at min 480 spendable 68,439.5 ≥ 1.15× |

Spendable = modeled cumulative − prices of deputies already bought
(purchase minutes assumed 12/45/130/270). Growth ratio softens
(8×/4.75×/2.6×) as each posting's marginal yield shrinks (posting 3–5
add cooking value-add and combat convenience, not another full gathering
stream) — later deputies are long-payback conveniences, Melvor-style.
The placeholder T17 ladder (75/400/2500/12000) was priced blind to this
curve: at real rates 75 crowns is ~1.5 min of tier-1 selling, which
would make the first unlock a non-event and the ladder a speed bump.

**ORIENTATION STIPEND = 150.** Sizing rules (probe-pinned): stipend +
modeled minute-12 earnings (150 + 270.0 = 420) ≥ price #1; price #1 >
stipend alone (250 > 150 — the resident must still sell something:
≥ 100 cr ≈ 2 min of tier-1 selling before the first deputize, so FILE A
CROWNS CLAIM is a real lesson, not a formality); stipend ≥ half of
price #1 (150 = 60% — "the stipend funds most of the first deputy").
As-built timing (T18 engine, unchanged): the stipend posts at the
SEVENTH stamp — i.e. immediately after the first DEPUTIZE RESIDENT
purchase completes the form — so in play it lands as the DULY ORIENTED
windfall that seeds deputy #2 (150 of 2,000) rather than pre-funding
deputy #1; this is why the probe also pins deputy #1 affordable from
minute-12 earnings ALONE.

### 5.3 Boss-gate integrity (prices must not trivialize §2/§4)

- **Deputies buy postings, not power.** The staffing namespace carries
  no combat stat anywhere; a deputy never touches accuracy, evasion, HP,
  or damage. The §2 boss sims are content-driven and unchanged by this
  task — the probe's seeded sweeps re-run byte-identically (verified
  below).
- **Crowns and gear are separate economies.** The boss's critical path
  is Wasteland Combat 14 + Junksmith 15 + a CRAFTED Majority Whip +
  Carpool Carapace + Chef's Regret — every piece built from drops and
  gathering, none of it Crown-gated on the intended path (the Depot's
  1,200/1,500 gear lines are the optional impatience tax at Combat 16).
  Buying deputies consumes zero gear materials, so deputy spending
  cannot slow the boss path, and gear crafting cannot be skipped with
  crowns on any path that matters: mid gear + no food still never wins
  (§2), whatever the wallet holds.
- **Deputy-first cannot soft-lock.** Worst case: every Crown ever earned
  goes into deputies, zero Depot purchases. The resident still owns
  posting 1 forever (refusal never blocks the resident's own hands),
  every gathering action yields sellable EV > 0 (income floor ≈ 20–25
  cr/min even in phase A), deputies never expire or drain, and the boss
  path above needs no Crowns at all. No state of the game has the player
  stuck: income is unconditional, the ladder is optional, and the single
  free posting suffices for every system (combat, cooking, gear).
- **Deputies accelerate income, not the gate.** The boss's real gates
  are XP/drop-bound (Combat 14 = 8,340 XP; whip/carapace materials from
  bunny lint + girderlings). Deputy-accelerated income can buy stews
  (200 cr, Cooking 12 gate) — the pre-existing impatience tax, still
  clearance-gated — but the intended path (craft gear + food, clear the
  ladder, ~60–90 min mixed play per §4) remains the fast lane: on the
  modeled curve a deputy-first optimizer holds 4 postings by ~4.5 h
  having skipped nothing the boss checks.

## 6. No-orphan contract

Every item has a source **and** a sink (probe-enforced): sources = drop
tables, recipe outputs, Depot stock; sinks = recipe inputs, edibility
(all 4 foods), equippability (all 4 equipment). Notable wiring: Lint Pelt
→ Carpool Carapace (combat feeds crafting), Fizz Gland → Reheat Chef's
Regret, Vintage Snack Cake → edible without Cooking (pre-cooking combat
sustain), Girderling → both tier-4 gear pieces, the boss's table feeds
tier-4 crafting after clear.
