# Valued Resident Naming Bible — T4 (+ T16 run-2 extension)

Status: awaiting approval (T16 extension; T4 body previously verified PASS).
Owner: Data lane (Mr. Fantastic) carrying Doctor Strange's risk gate. Scope:
every proper noun in the vertical slice, the flavor-copy voice rules, and the
per-name trademark-proximity verdicts. **Run 2 (2026-09-16): T16 extends this
bible to the personnel system, the orientation form, and the run-2 icon
grammar** (town-hall.md Scope Amendment 1) — §10 T16 rows + §14 systems
vocabulary.
Inputs: `docs/ultron/town-hall.md` (protected-terms contract),
`docs/ultron/design-brief.md` (Shelter Signage System voice),
`docs/content-schema.md` (fields the names fill), `PRODUCT.md` (brand
commitments). Consumers: T5 (authors content with these display names), T9/T10
(plate + docket copy), T11 (icon silhouettes), T13 (criterion 7 evidence);
run-2 consumers: T17 (staffing engine/UI copy + save fields), T18
(orientation copy), T19 (icon ids + silhouettes).

Voice in one line: **a shelter bureaucracy that survived the apocalypse and
never stopped issuing cheerful directives.** Names read like institutional
signage — stencil plates, clearance grades, requisition forms — while staying
pun-heavy and goofy.

---

## 0. Title — **Valued Resident — An Idle Wasteland** (renamed from RADLANDS 2026-09-15)

**Outcome: RADLANDS superseded; new title selected from a checklist-cleared shortlist and applied.**

History, kept for the record: RADLANDS passed the town-hall criterion-7 checklist
(zero shared terms/patterns with Fallout, Vault-Tec, Nuka-Cola, Pip-Boy, Vault Boy,
G.E.C.K., T-51, Deathclaw, RadAway, Stimpak, RadRoach/Radroach, or Melvor), but a
web-verified scan (2026-09-15) found **RADLANDS** — U.S. trademark, serial 90506045,
filed 2021-02-02, registered 2024-09-10, status Live, International Class 28, held by
the publisher of *Radlands* (designer Daniel Piechnick, 2021) — an identical word mark
in an adjacent entertainment category with a similar genre skin. The coordinator
halted on the question; with the user unavailable, the halt was resolved unattended
(ultron-supreme recommended path): **rename now via a checklist-cleared shortlist;
user override remains open.**

Re-verification (2026-09-15, same date): nine candidates were scanned across general
web, Steam (direct store search), BoardGameGeek (via web search; direct fetch blocked),
and USPTO/trademark aggregators (trademarkia/justia references). Five passed, three
failed on real conflicts, one was dropped pre-scan for an internal collision. Full
per-candidate table with sources: `production-log.md` → **Title Change Record**.
Summary of failures: "D.O.C.S." (Steam game *The DOCS: Department of Creatures*,
app 674200, same channel + adjacent premise), "Requisition" (*REQUISITION VR* + 2025
sequel on Steam, post-apocalyptic), "Bureau of Wastelands" (leading element sits on
inXile's registered **WASTELAND** mark for computer games, which has a documented
C&D enforcement history against small developers).

**Selected: VALUED RESIDENT — An Idle Wasteland.** Construction: the institutional
form of address from this bible's own voice system (Depot plate: "WELCOME, VALUED
RESIDENT", §7) — the title is the shelter addressing the player, which is the
design-brief thesis in one phrase. Scan verdict **PASS**: no game, board game,
software product, or registered mark by this name in any channel scanned
(2026-09-15); the phrase exists in the wild only as generic apartment-marketing
English, i.e., no famous-mark overlap — and that mundane provenance is itself the
parody. Subtitle "An Idle Wasteland" retained per coordinator instruction; it stays
cleared as generic descriptive English per its §10 row, with one honest flag
recorded for the user's override review: inXile's WASTELAND registration covers the
bare word in games class, so the subtitle rides on descriptive-use mitigants
(non-commercial hobby project, descriptive phrase, subordinate position). If the
project is ever commercially distributed, re-convene Town Hall on title *and*
subtitle before doing so.

A future title swap touches exactly: PRODUCT.md (purpose line + brand commitments),
this file (§0 + §10 title row), `project.godot` `config/name`, plan.md title line,
content-schema/save-schema doc headers, and the future T9 title-screen plate in
theme data. Everything below §0 is unchanged original coinage or generic-word
construction.

---

## 1. World frame nouns

| Noun | Use | Notes |
|---|---|---|
| **The Department of Continued Sheltering** | The pre-war agency whose signage runs the shelter; signage short form **D.O.C.S.** | The corporate-dystopia voice source. Copy signs itself "A D.O.C.S. FACILITY". |
| The Shelter | The game's home | Always the generic word "Shelter" — never "Vault" (see lexicon, §9). |
| RESIDENT | The player | Never "dweller" (see §9). |

The agency name is the parody spine: it promises continuation, it issues
directives, it is not currently answering questions.

## 2. Currency — Crowns

- Display name: **Crowns** (plate text "CROWNS", mono digits).
- Signage-formal: **Beverage Crowns** — the money is pressed metal bottle
  crowns, strung and counted, exactly as ridiculous as it sounds.
- Copy usage: "TENDERS EXACT. 30 CROWNS." The Depot never says "caps" (§9).
- Icon note (T11): a crown cork seen face-on — plain crimped edge, three
  rectangular punch-notches. **No star roundel, no lettering, no cola bottle,
  no label-glass bottle silhouettes.**

Why it works: "crown" is the real-world technical name for a bottle cap
(crown cork), so the parody lands for anyone who knows, and reads as a goofy
royal currency for everyone else — an original construction either way.

## 3. Combat zone — The Sunny Exclusion Zone

- Display name: **The Sunny Exclusion Zone** (machine id `dusty_flats`,
  stable per T4 instructions).
- Signage form: "SUNNY EXCLUSION ZONE — DESIGNATED OUTDOOR AMENITY AREA".
  The zone plate pairs a cheerful sun pictogram with a fence pictogram.
- Copy: "PLEASE ENJOY THE WASTELAND RESPONSIBLY." / "PLEASE SUPERVISE CHILDREN
  AND GEIGERS."
- The skill that patrols it keeps its approved name: **Wasteland Combat**.

### Monsters (4 + boss)

| # | Name | Machine id | Concept | Tier intent (T5) |
|---|---|---|---|---|
| 1 | **Litterbug** | `junkyard_roach` (stable) | A scatterbug stitched from foil wrappers; leaves gum wrappers as tracks | T1 pest, level gate 1 |
| 2 | **Greater Dust Bunny** | `greater_dust_bunny` (T5) | What accumulates when nobody sweeps for 200 years; mostly lint, mostly grudge | T2 |
| 3 | **Fizzard** | `fizzard` (T5) | A lizard that carbonates; hisses foam when cross; drops Fizz Gland | T3 |
| 4 | **Feral Snack Dispenser** | `feral_snack_dispenser` (T5) | A snack machine gone feral; rattles violently, dispenses at threats | T4 tank-y |
| Boss | **The Superintendent** | `sewer_landlord` (stable) | Senior Fauna, Exterior Division. Hard hat, clipboard, far too many keys. Collects rent in teeth | Boss, gates the zone clear |

Signage treats these as classifications, not characters: monster plates read
"FAUNA CLASS: PEST (LITTERING)" etc.; the boss plate reads "SENIOR FAUNA —
ESCORT NOT PROVIDED."

## 4. Item catalog (~21 display names across the chains)

Ids are machine-y and descriptive; only display names carry the comedy
(`scrap_metal` → "Scrapnel"). Golden-set ids are stable; T5 ids are
suggestions T5 may keep.

**Scavenging yields (gathering):**

| Display name | Id | Chain role |
|---|---|---|
| **Scrapnel** | `scrap_metal` (stable) | Tier-1 metal; everything is made of this eventually |
| **Copper Snarl** | `copper_wiring` (stable) | Stripped wire, angry about it |
| **Tattercloth** | `cloth_scraps` (stable) | Cloth of former things |
| **Girderling** | `girderling` (T5 spare) | A small, aspiring girder |

**Foraging yields (flora — replaces town-hall provisionals):**

| Display name | Id | Chain role |
|---|---|---|
| **Nightlight Cap** | `glowshroom` (stable) | Glowing fungus cap; do not stare; replaces provisional "Glowshroom" |
| **Duskcorn** | `duskcorn` (T5) | Grain that ripens at 6:14 PM sharp (provisional name confirmed — it was clean) |
| **Iodine Root** | `iodine_root` (T5) | Root with civil-defense vitamins; replaces provisional "Radroot" (breaks the Fallout "Rad-" pattern) |

**Monster drops:**

| Display name | Id | Chain role |
|---|---|---|
| **Grade-D Bugmeat** | `roach_meat` (stable) | Butchered Litterbug; the grade is honest |
| **Lint Pelt** | `lint_pelt` (T5) | Greater Dust Bunny drop; tailor-grade almost |
| **Fizz Gland** | `fizz_gland` (T5) | Fizzard organ; still faintly carbonated |
| **Vintage Snack Cake** | `vintage_snack_cake` (T5) | Dispensed by the Feral Snack Dispenser; vintage means "old" |

**Junksmithing outputs (processing):**

| Display name | Id | Chain role |
|---|---|---|
| **Almost Bullion** | `scrap_ingot` (stable) | Smelted Scrapnel; resembles treasure at distance |
| **Compliant Wire** | `compliant_wire` (T5) | Copper Snarl, re-educated straight |
| **Patchwork Bolt** | `patchwork_bolt` (T5) | A bolt of Tattercloth; also a bolt, technically |

**Cooking outputs (food):** see §6.

**Equipment:** see §5.

## 5. Equipment (2 weapons + 2 armors)

| Display name | Id | Slot | Notes |
|---|---|---|---|
| **Point of Order** | `scrap_shiv` (stable) | Weapon 1 | A procedural jab. Raised, then lowered, then raised again quickly |
| **Majority Whip** | `majority_whip` (T5) | Weapon 2 | Counts votes by touch |
| **Pedestrian Plating** | `hubcap_vest` (stable) | Armor 1 | Hubcaps over the vitals; you are the vehicle now |
| **Carpool Carapace** | `carpool_carapace` (T5) | Armor 2 | Panels of a sedan that carried four to safety; now carries one |

## 6. Food (Cooking chain)

| Display name | Id | Notes |
|---|---|---|
| **Chef's Regret** | `radstag_stew` (stable) | Soup of the day, every day. Replaces placeholder "Radstag Stew" (Radstag is Fallout 4 fauna — hard reject) |
| **Mandatory Grits** | `mandatory_grits` (T5) | Duskcorn, ground, non-negotiable |
| **Compliant Casserole** | `compliant_casserole` (T5) | Nightlight Cap + Grade-D Bugmeat, baked until obedient |

Cafeteria-menu voice: "TODAY'S MENU IS YESTERDAY'S MENU. BON APPETIT."

## 7. Shop — The Requisition Depot

- Display name: **The Requisition Depot**; plate short form stays **DEPOT**
  (per design-brief first viewport).
- Copy: "WELCOME, VALUED RESIDENT." / "TENDERS EXACT." / "RETURNS ARE A
  FUTURE DEPARTMENT."
- Selling is always quoted in Crowns at the item's one honest `value`.

---

## 8. Flavor-copy voice rules (5 rules, 2 examples each)

### Rule 1 — Directive voice: the signage issues instructions; the institution never stopped.
The shelter is always telling you to do one more compliant thing.
- Scavenging docket: "SORT PROMPTLY. THE PILE IS PATIENT. THE PILE IS NOT, STRICTLY SPEAKING, SAFE."
- Foraging docket: "GATHER ONLY WHAT GLOWS BACK. THANK YOU FOR YOUR COMPLIANCE."

### Rule 2 — Cheer–threat pairing: every warm word is escorted by a quiet warning in the same breath.
Never cruel, never loud — the menace is administrative.
- Depot: "WELCOME, VALUED RESIDENT. TENDERS EXACT. THE DESK DOES NOT MAKE CHANGE FOR FEELINGS."
- Zone plate: "PLEASE ENJOY THE WASTELAND RESPONSIBLY. THE WASTELAND HAS NOT AGREED TO RECIPROCATE."

### Rule 3 — Clearance language, never "locked".
Gates are clearances; progress is elevation. Locked content says what grade is required, kindly.
- Locked recipe: "CLEARANCE 3 REQUIRED. ELEVATION IS EARNED, NOT REQUESTED."
- Boss plate: "SENIOR FAUNA DETECTED. ESCORT IS NOT PROVIDED. REFUNDS ARE NOT EITHER."

### Rule 4 — Cheer lives in word choice, not punctuation.
Enamel plates are calm ALL-CAPS. No exclamation points on signage (chalk scrawl may use one, sheepishly, at most).
- Correct: "YOUR BUSINESS IS APPRECIATED."
- Wrong: "YOUR BUSINESS IS APPRECIATED!!!"

### Rule 5 — Systems are forms: every mechanic is paperwork.
Offline gains are mail; saves are records; death is a posted notice. The mechanic's UI name comes from the bureau.
- Offline modal: "MAIL CALL — GAINS ACCRUED IN YOUR ABSENCE. NO ACTION WAS TAKEN WITHOUT YOU. NONE WAS NEEDED."
- Death plate: "RETURN TO SHELTER — THE ZONE THANKS YOU FOR YOUR CONTRIBUTIONS (PARTIAL)."

## 9. Do-not-use lexicon and pattern gate (binding on T5/T9/T10/T11; run 2: T17/T18/T19)

**Words never used, in any construction:**
- **vault** (any prefix/suffix/compound — evokes Vault-Tec). The game's refuge is the *Shelter*.
- **dweller / overseer** (Fallout-loaded roles). We say *RESIDENT*; the boss is the *Superintendent*, never an Overseer.
- **"war never changes"** and similar Fallout signature phrasings.
- **nuka-, cola-brand echoes, -boy mascots** — no "-Boy" anything, no mascot figures, no thumbs-up silhouettes.
- **"Rad-" coinages** (RadAway/RadRoach/Radstag pattern) — including the provisional "Radroot", replaced. Radiation humor uses real generic vocabulary: Geiger, iodine, clicks ("PLEASE SUPERVISE CHILDREN AND GEIGERS").
- **caps** as the currency word (use *Crowns*).
- **stimpak/stim, pip, G.E.C.K.-style punctuated acronyms, letter-dash-number model designations (T-51 style)** — gear gets titles, not serial numbers.
- **Smash-brand food portmanteaus** in the Cram/BlamCo style — our food is institutional-menu language ("Chef's Regret", "Mandatory Grits").
- **Deathclaw-adjacent creature naming** (menacing compound of violent word + body part). Our fauna are domestic pests misclassified by bureaucracy.
- **Melvor terms** — no skill, item, or monster name from Melvor Idle (Golbin, etc.); mechanics only, per town-hall.

**Icon silhouette rules for T11 (no protected silhouettes described):**
- Crowns: plain crimped crown cork with three punch-notches — no star roundel, no cap lettering, no cola bottles.
- No mascot figures in any pose (Vault Boy pattern); pictograms are objects and signage glyphs only.
- Monsters are drawn as the mundane objects they are (wrapper-beetle, lint-mass, fizzing lizard, dented dispenser, hard-hat silhouette with clipboard) — no creature design referencing protected game concept art.

---

## 10. Per-name checklist verdict table — coined names

Checklist = protected terms (Fallout, Vault-Tec, Nuka-Cola, Pip-Boy, Vault
Boy, G.E.C.K., T-51, Deathclaw, RadAway, Stimpak, RadRoach/Radroach, Melvor)
plus the pattern gate (§9) plus a proximity scan (one line: nearest protected
term and why this name is distinct). Verdicts: PASS = clears every item.

| Name | Construction | Proximity analysis | Verdict |
|---|---|---|---|
| **Valued Resident** (title; plate form VALUED RESIDENT) | Institutional form of address from our own voice system (§7 Depot plate copy); adjective + generic noun | No game, board game, software product, or registered mark by this name (web + Steam direct store search + BGG via search + trademark aggregators, 2026-09-15 — see §0); nearest phrase use is generic apartment-lease marketing — no famous-mark overlap; superseded RADLANDS (third-party class-28 mark, §0) | **PASS** |
| **An Idle Wasteland** (subtitle) | Generic descriptive English | "Wasteland" and "idle" are genre vocabulary; no protected term appears; not distinctive to any single mark | **PASS** |
| **Crowns** (currency) | Real-world "crown cork" (the technical name for a bottle cap) reused as royal-sounding money | Parody is structural (cap-money), name is a generic word with different roots entirely; nearest protected concept is Nuka-Cola's caps — different word, no brand echo, icon has no star roundel | **PASS** |
| **The Department of Continued Sheltering (D.O.C.S.)** | Ordinary bureaucratic phrase; agency acronym | No protected term; "Shelter" is generic civil-defense vocabulary, deliberately not "Vault"; acronym is original, unpunctuated-GECK-style banned pattern avoided | **PASS** |
| **The Sunny Exclusion Zone** | Cheerful adjective + real-world civil-defense term | Generic words; distinct construction from Fallout location names (Glowing Sea, the Divide); no protected pattern | **PASS** |
| **Litterbug** | Real English word (one who litters) recast as a creature | Generic word, no Fallout/Melvor roots; nearest protected term RadRoach — different word entirely (no "rad", no "roach"), different roots (litter vs. radiation) | **PASS** |
| **Greater Dust Bunny** | Domestic word pair + taxonomy modifier | Two generic household words; no protected term shares either root; taxonomy naming is naturalist-generic, not Fallout creature style | **PASS** |
| **Fizzard** | Invented compound: fizz + lizard | Both morphemes generic; no Fallout/Melvor creature shares the construction or roots; not a letter-dash-number designation | **PASS** |
| **Feral Snack Dispenser** | Three generic words, noun phrase | Deliberately brand-free (no "Vend-O-Matic"-style brand echo); no protected term; Fallout has no analog by name or root | **PASS** |
| **The Superintendent** | Ordinary job title | Generic title; deliberately chosen over the banned "Overseer" (Fallout-loaded); no protected term or pattern | **PASS** |
| **Scrapnel** | Pun compound: scrap + shrapnel | Both generic morphemes; no protected item in either game by this name or construction; not a protected phrase | **PASS** |
| **Copper Snarl** | Generic element + tangle word | Generic words; no protected item; distinct from any Fallout junk-item naming | **PASS** |
| **Tattercloth** | Generic compound (tatter + cloth) | No protected item by name; different construction from Fallout's "clothing scrap"-style generic labels only in that it is coined; no mark adjacency | **PASS** |
| **Girderling** | Girder + diminutive -ling | Coined from generic industrial word; no protected term or pattern | **PASS** |
| **Nightlight Cap** | Domestic object + mushroom "cap" | Generic words; replaces provisional "Glowshroom" to sit farther from Fallout's glowing-fungus/Glowing Sea glow- cluster; distinct roots (domestic lamp vs. radiation glow) | **PASS** |
| **Duskcorn** | Dusk + corn; provisional town-hall name confirmed | Generic morphemes; no Fallout/Melvor flora by this name; no pattern hit | **PASS** |
| **Iodine Root** | Periodic-table element + root | Generic words with real-world civil-defense resonance; replaces "Radroot" specifically to break the Fallout "Rad-" pattern; distinct roots (chemistry vs. "rad") | **PASS** |
| **Grade-D Bugmeat** | USDA-style grade pun + generic words | Generic grading comedy; nearest protected pattern is Fallout's Cram-style smash-brands — different construction (bureaucratic grade, not brand portmanteau) | **PASS** |
| **Lint Pelt** | Two generic nouns | No protected term; no pattern hit | **PASS** |
| **Fizz Gland** | Generic onomatopoeia + anatomy word | No protected term; "fizz" is beverage-generic, not a Nuka- compound; no pattern hit | **PASS** |
| **Vintage Snack Cake** | Generic words; "vintage" = expired | No brand referenced; avoids Cram/BlamCo smash-brand pattern by construction; no protected term | **PASS** |
| **Almost Bullion** | Pun on bullion (precious-metal bulk) | Generic word pun; no protected item; no pattern hit | **PASS** |
| **Compliant Wire** | Institutional adjective + generic noun | Generic words echoing our own voice system, not any external mark | **PASS** |
| **Patchwork Bolt** | Fabric "bolt" / hardware "bolt" pun + generic word | Generic-word double meaning; no protected item; no pattern hit | **PASS** |
| **Chef's Regret** | Cafeteria-menu phrase | Generic words; replaces "Radstag Stew" (Radstag = Fallout 4 creature — hard reject); no mark adjacency | **PASS** |
| **Mandatory Grits** | Institutional adjective + generic dish | Generic words; no protected term; parody is bureaucratic, not brand-referencing | **PASS** |
| **Compliant Casserole** | Institutional adjective + generic dish | Generic words; voice-system echo only; no pattern hit | **PASS** |
| **Point of Order** | Generic parliamentary phrase as a weapon name | Common procedural term; no protected term; no game-mark adjacency in the protected list | **PASS** |
| **Majority Whip** | Generic parliamentary office as a weapon name | Common procedural term; distinct construction from Fallout weapon naming (no model numbers, no brand prefixes) | **PASS** |
| **Pedestrian Plating** | Traffic-signage register: pedestrian + armor plating | Generic words; hubcar/hubcap concept is generic automotive scrap; no protected armor naming pattern (no T-series designations) | **PASS** |
| **Carpool Carapace** | Alliterative generic triple (carpool + carapace) | Generic words; no protected term; no pattern hit | **PASS** |
| **The Requisition Depot** | Military-bureaucratic generic phrase | No protected term; "Depot" was already the design-brief's generic plate word; no Vault-/brand prefix | **PASS** |

### T5-authored record names (applied 2026-09-15 under the §13 protocol)

The 4-tier content structure required records the bible had not named (tier-3/4
activities, the new drop-table headers, the tier-2+ recipes). Per §13 these are
coined here, run through the same checklist, and recorded — **zero new
item/monster/equipment/skill/zone names** (all 21 items, 5 monsters, 4 gear
pieces, 5 skills use §4–§6 names verbatim). Constructions are either
generic-word institutional phrases or `<institutional verb> + <bible item
name>` (the pattern T4 itself used: "Smelt Almost Bullion").

| Name | Kind | Construction / proximity | Verdict |
|---|---|---|---|
| Drain the Sump | activity | Generic plumbing noun + definite article; no protected root; signage-task voice | **PASS** |
| Unbuild the Overpass | activity | Bureaucratic inversion of generic words (unbuild + overpass); no protected pattern | **PASS** |
| Walk the Glow Rows | activity | Generic domestic phrase; "glow" follows the Nightlight Cap rename away from radiation-glow clusters | **PASS** |
| Harvest the 6:14 Plot | activity | Generic verb + time-stamped plot number (institutional specificity, not a model designation — no letter-dash-number pattern) | **PASS** |
| Dig the Iodine Beds | activity | Generic civil-defense vocabulary, matches Iodine Root's roots | **PASS** |
| Forage the Far Fence | activity | Two generic words; skill-verb + zone-edge phrase | **PASS** |
| Sump Slurry Yields | drop header | Generic words; follows the established "X Yields" header pattern | **PASS** |
| Overpass Span Yields | drop header | Generic; established pattern | **PASS** |
| Glow Row Yields | drop header | Generic; established pattern | **PASS** |
| Dusk Plot Yields | drop header | Generic; established pattern (Duskcorn roots) | **PASS** |
| Iodine Bed Yields | drop header | Generic; established pattern | **PASS** |
| Far Fence Yields | drop header | Generic; established pattern | **PASS** |
| Dust Bunny Yields | drop header | Follows its monster's cleared name (§3) | **PASS** |
| Fizzard Yields | drop header | Follows its monster's cleared name (§3) | **PASS** |
| Snack Dispenser Yields | drop header | Follows its monster's cleared name minus "Feral" (the table lists what it dispenses, not its temperament) | **PASS** |
| Superintendent's Receipts | drop header (boss) | Possessive of the cleared boss name (§3) + generic financial noun — rent collected, as the bible's concept line says; not a Nuka-/brand echo | **PASS** |
| Draw Compliant Wire | recipe | Verb + bible item name (Compliant Wire) | **PASS** |
| Braid Patchwork Bolt | recipe | Verb + bible item name (Patchwork Bolt) | **PASS** |
| Forge Majority Whip | recipe | Verb + bible item name (Majority Whip) | **PASS** |
| Press Carpool Carapace | recipe | Verb + bible item name (Carpool Carapace) | **PASS** |
| Grind Mandatory Grits | recipe | Verb + bible item name (Mandatory Grits) | **PASS** |
| Bake Compliant Casserole | recipe | Verb + bible item name (Compliant Casserole) | **PASS** |
| Simmer Chef's Regret | recipe | Verb + bible item name (Chef's Regret) | **PASS** |
| Reheat Chef's Regret | recipe | Verb + bible item name; "reheat" is the §6 joke ("TODAY'S MENU IS YESTERDAY'S MENU") made mechanical | **PASS** |

### T16-authored systems vocabulary (Run 2, applied 2026-09-16 under the §13 protocol)

Scope Amendment 1 added three systems (personnel slots, orientation
tutorial, expanded icon grammar) that needed player-facing names. Coined
here, run through the same checklist, recorded — **zero new names for
existing entities** (RESIDENT, Crowns, clearance language, Docket/Depot/
Manifest/Concourse, MAIL CALL, and all §3–§7 names are reused verbatim).
Codebase grepped before assignment: no display term below collides with any
shipped string (PERSONNEL/DEPUTY/deputize/ORIENTATION/DULY/STIPEND/NUISANCE
had zero hits in scripts/data/scenes/tests); the word "posting" already
appears in shipped docket copy ("PROVISIONAL POSTING",
"POSTING WITHDRAWN BY THE DEPARTMENT") — precedent for the slot noun, not a
collision. Form designations verified in code: `FORM M-1` (mail-call notice,
`scripts/ui/mail_call_modal.gd`), `D.O.C.S. FORM Z-9` (zone-secured
certificate, `scripts/ui/docket_patrol.gd`), `FORM 9-A` (provisional docket
posting footer, `scenes/main.gd`), docket serials `D-01…D-07` — the
orientation form takes the unused **O** letter (letter-first series, like
M/Z, unlike 9-A's digit-first): **O-1** collides with nothing shipped.

| Name | Kind | Construction / proximity | Verdict |
|---|---|---|---|
| **DEPUTY** (worker noun; verb **deputize**) | personnel | Ordinary civilian job title, the natural subordinate of our own RESIDENT/Superintendent role ladder; chosen over "STAFF BADGE" (an object, not a person — it becomes the badge *glyph* instead) and "ASSIGNEE" (cold legalese, no cheer). Nearest real-world adjacency: Deputy.com, a B2B workforce-scheduling SaaS — different channel, generic dictionary word in its ordinary sense, non-commercial parody project; no Fallout/Melvor term (Fallout's "deputy" NPCs are generic labels, unprotectable); no §9 pattern (the opposite of the banned overseer/dweller roles: a civilian administrative title) | **PASS** |
| **PERSONNEL** (concourse plate + docket) | personnel | Generic administrative department word, single-plate form matching DEPOT/MANIFEST on the wall; no game, board game, or registered mark adjacency; no protected root | **PASS** |
| **POSTING** (slot noun) · **ASSIGNED** / **AVAILABLE** (slot states) | personnel | Generic workplace vocabulary already the engine's own idiom ("POSTED SHIFTS", "POSTING WITHDRAWN BY THE DEPARTMENT" — shipped docket copy); one concurrent activity occupies one posting; no protected term or pattern in any of the three words | **PASS** |
| **POSTING REFUSED** (refusal directive plate) | personnel | Generic bureaucratic refusal phrase; the directive serial states the fact + both remedies (cease a posting / deputize another resident) per the amendment; no protected term; clearance-not-locked voice (§8 R3) — refusal, never denial of service | **PASS** |
| **DEPUTIZE RESIDENT** (purchase action label; button reads `DEPUTIZE RESIDENT · N CROWNS`) | personnel | Cleared verb (DEPUTY row) + our own RESIDENT noun; supersedes plan T17's provisional "ASSIGN" button wording (ASSIGN survives inside the slot-state word ASSIGNED); no protected term | **PASS** |
| **ORIENTATION FORM O-1** (the tutorial's official name) | orientation | Bureau paperwork designation continuing the in-world series (M=Mail, Z=Zone, D=Docket; **O=Orientation**, next unused letter — grep-verified). Letter-dash-number ban (§9) scopes to *gear model designations* (T-51 style); the bible's "Harvest the 6:14 Plot" row already reasons institutional paperwork numbering ≠ model designation, and M-1/Z-9 shipped under that reading. No famous real form collided (the famous set W-2/I-9/W-4/1040/1099 is avoided; "O-1" exists only as a US visa category and a military pay grade — different domains, generic letter-number, ours always prefixed FORM, never applied to gear); no Fallout/Melvor term | **PASS** |
| **WORK A POSTED SHIFT** (orientation step 1) | orientation | Generic words over the docket's own cleared idiom (BEGIN SHIFT, POSTED SHIFTS); maps to the shipped primary action | **PASS** |
| **EARN A CLEARANCE** (step 2) | orientation | Clearance language per §8 R3, echoing the shipped stamp "CLEARANCE %02d EARNED"; generic words | **PASS** |
| **FILE A CROWNS CLAIM** (step 3) | orientation | Bureau verb + our own cleared currency noun (Crowns §2); "claims" already the zone's posted-drop idiom ("CLAIMS:" on fauna cards); generic construction | **PASS** |
| **PROCESS A PRODUCT** (step 4) | orientation | Generic processing-chain words (recipes consume yields, output products); no protected term | **PASS** |
| **PROVISION THE PATROL** (step 5) | orientation | Military-administrative generic verb + our own PATROL noun (Wasteland Patrol is a carried-over cleared name); covers both qualifying actions (equip gear / cook food); no protected term | **PASS** |
| **CLEAR A NUISANCE** (step 6) | orientation | Civil-complaint generic words; fauna are classified pests ("FAUNA CLASS: PEST"), so a nuisance is exactly what the bureaucracy calls them; no protected root, no Deathclaw-style violent compound | **PASS** |
| **DEPUTIZE A RESIDENT** (step 7) | orientation | Cleared verb + own noun (see DEPUTY row); teaches the run-2 system it exists to teach | **PASS** |
| **DULY ORIENTED · FORM O-1** (completion stamp) | orientation | Stock bureaucratic phrase ("duly noted") + the form's own designation; rubber-stamp idiom matches "POSTED — SECTOR Z · D.O.C.S. FORM Z-9"; generic words, no mark adjacency | **PASS** |
| **ORIENTATION STIPEND** (reward line; `{N} CROWNS · THANK YOU FOR YOUR PROMPT COMPLIANCE.`, N set by T20) | orientation | Generic administrative-fee words + own currency noun; cheer per §8 R2; no protected term | **PASS** |

## 11. Carried-over descriptive names — re-verified (all PASS)

These pre-existing approved/generic names were re-run through the same
checklist; all clear with no changes needed. Construction: plain generic
English; proximity: no protected term shares any word or root; verdict PASS
for each.

- Skills: **Scavenging**, **Foraging**, **Junksmithing**, **Cooking**,
  **Wasteland Combat**.
- Golden activities: **Sort the Scrap Pile**, **Strip a Wreck**.
- Golden drop-table headers: **Scrap Pile Yields**, **Wreck Locker Yields**;
  renamed this task: `roach_nest` → **Litterbug Yields** (follows its
  monster's rename).
- XP curve display name: **Standard 99** (internal-facing).
- Signage system names already fixed by the design brief: **MAIL CALL**,
  **RETURN TO SHELTER**, **CLEARANCE N REQUIRED**, **START HERE**, **Docket**,
  **Manifest**, **Concourse** — generic institutional vocabulary, no mark
  adjacency.

## 12. Golden-set application record (ids stable, display names only)

Per T4 instructions, machine ids stay snake_case-descriptive; only `name`
fields changed. `data/equipment.json` and `data/shop_stock.json` expose no
display names; `data/skills.json`, `data/activities.json` (2 of 2), and
`data/drop_tables.json` (2 of 3) names were re-verified and kept as-is.

| Record (id) | Field | Old (placeholder) | Final |
|---|---|---|---|
| items `scrap_metal` | name | Scrap Metal | **Scrapnel** |
| items `copper_wiring` | name | Copper Wiring | **Copper Snarl** |
| items `cloth_scraps` | name | Cloth Scraps | **Tattercloth** |
| items `glowshroom` | name | Glowshroom | **Nightlight Cap** |
| items `roach_meat` | name | Roach Meat | **Grade-D Bugmeat** |
| items `scrap_ingot` | name | Scrap Ingot | **Almost Bullion** |
| items `radstag_stew` | name | Radstag Stew | **Chef's Regret** |
| items `scrap_shiv` | name | Scrap Shiv | **Point of Order** |
| items `hubcap_vest` | name | Hubcap Vest | **Pedestrian Plating** |
| monsters `junkyard_roach` | name | Junkyard Roach | **Litterbug** |
| monsters `sewer_landlord` | name | The Sewer Landlord | **The Superintendent** |
| recipes `smelt_scrap_ingot` | name | Smelt Scrap Ingot | **Smelt Almost Bullion** |
| recipes `forge_scrap_shiv` | name | Forge Scrap Shiv | **Forge Point of Order** |
| recipes `forge_hubcap_vest` | name | Forge Hubcap Vest | **Press Pedestrian Plating** |
| drop_tables `roach_nest` | name | Roach Nest Yields | **Litterbug Yields** |

The placeholder names that carried identifiable Fallout roots ("Radstag
Stew") or sat near protected terms ("Junkyard Roach" one modifier away from
RadRoach) are gone from the content set entirely.

## 13. Method and scope notes

- Checklist scope is the town-hall contract (criterion 7) plus the broader
  pattern gate the risk lane holds: "Vault" prefixes, "Nuka-" compounds,
  "-Boy" mascots, protected silhouettes, "Rad-" coinages, letter-dash-number
  designations, smash-brand food portmanteaus, Fallout-loaded roles
  (overseer/dweller), and all Melvor terms.
- Per-name proximity scan = one line on construction and the nearest
  protected term with the distinctness reason (§10).
- The title additionally received a web-verified third-party scan
  (2026-09-15); content names are checked against the protected list and
  patterns as above. Generic-word puns ("Litterbug", "Chef's Regret") are
  intentionally non-exclusive vocabulary: their protection risk is nil for a
  non-commercial parody project, and their construction avoids every
  protected pattern.
- New display names for T5-authored records (Girderling, Iodine Root,
  Mandatory Grits, etc.) are binding suggestions: T5 uses them or brings
  replacements back through this checklist before shipping (add rows to §10).
- Voice rules (§8) and lexicon (§9) bind all player-facing copy in T5 (item
  flavor), T9/T10 (plates, dockets, notices), and T11 (icon silhouettes);
  run 2 extends the binding to T17 (staffing plates + refusal copy), T18
  (orientation form copy), and T19 (icon silhouettes + ids).

## 14. Run 2 systems vocabulary — display terms ↔ machine ids (T16, 2026-09-16)

The §13 protocol requires new display names to be checklist-cleared and
recorded (done, §10 T16 table); this section additionally pins the machine-id
side so T17/T18/T19 bind display term to field without re-coinage. Machine
ids follow the existing conventions exactly: **snake_case English** for save
fields and content/icon ids (`save_version`, `skills_xp`, `anchor_unix_ms`,
`scrap_metal` precedent) — the codebase has no kebab-case namespace, so
"English machine ids per existing data conventions" resolves to snake_case.

**Personnel (T17; save_version 2):**

| Display term | Machine id | Notes |
|---|---|---|
| staffing state namespace | `engine.staffing` | sibling of `active`/`combat` in the PlayerState dict |
| DEPUTY purchases | `staffing.deputies` | int 0–4 (purchased deputies; total postings = 1 + deputies; cap 4 → 5 concurrent per the amendment's "all 5 skills concurrent" target). v1→v2 migration `_migrate_1_to_2` seeds 0 |
| POSTING REFUSED notice kind | `posting_refused` | engine/UI refusal payload kind string; payload carries the requested content id — T17 owns mechanics, the kind string is binding |
| personnel docket script | `docket_personnel.gd` | suggested (follows `docket_depot.gd`); non-binding, collision-checked |

**Orientation (T18; rides the same save_version 2):**

| Display term | Machine id | Notes |
|---|---|---|
| orientation namespace | `engine.orientation` | with `steps_done: Array[String]`, `completed: bool`, `stipend_claimed: bool` (T18 owns mechanics; names binding) |
| WORK A POSTED SHIFT | `work_shift` | step id; fires on first completed gathering/processing action (BEGIN SHIFT exists in `docket_skill.gd`) |
| EARN A CLEARANCE | `earn_clearance` | step id; fires on the shipped "CLEARANCE %02d EARNED" level-up stamp path |
| FILE A CROWNS CLAIM | `file_crowns_claim` | step id; fires on first Depot sale (SELL 1/SELL ALL → `add_crowns`) |
| PROCESS A PRODUCT | `process_product` | step id; fires on first recipe completion (processing chain) |
| PROVISION THE PATROL | `provision_patrol` | step id; fires on first equip (Manifest EQUIP) OR first cooked food — either qualifies, per the amendment's "[equip or cook]" |
| CLEAR A NUISANCE | `clear_nuisance` | step id; fires on first combat victory (VICTORY POSTED path) |
| DEPUTIZE A RESIDENT | `deputize_resident` | step id; fires on first `staffing.deputies` increase (the DEPUTIZE RESIDENT button, T17) |

All 7 steps verified against shipped actions (engine/UI grepped 2026-09-16):
BEGIN SHIFT (`docket_skill.gd`), clearance stamps (stamped logs), Depot sell
(`docket_depot.gd` SELL 1/SELL ALL), recipe execution (processing docket),
EQUIP (`docket_manifest.gd`), ENGAGE PATROL → victory (`docket_patrol.gd` /
`combat_session.gd`); step 7 targets the T17 machinery by design — the
tutorial teaches the new system.

**Icon ids (T19; 12 new SVGs, none colliding with the 41 shipped —
directory-listed 2026-09-16):** `stat_condition`, `stat_accuracy`,
`stat_evade`, `stat_max_hit`, `stat_interval`, `clearance_step`,
`deputy_badge`, `orient_arrow`, `stamp_check`, `btn_engage`, `btn_withdraw`,
`btn_deputize`. Silhouette semantics live in `docs/ultron/design-brief.md` →
"## Addendum: Personnel, Orientation, Icon Grammar", which is the binding
silhouette contract, including the §9-derived rules: no padlock silhouette
for gates, no mascot figures.
