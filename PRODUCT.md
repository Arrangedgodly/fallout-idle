# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop (native Godot game; macOS primary dev target, Windows/Linux export configs included)

## Stack

Godot 4.7.2.stable + GDScript. User's explicit choice ("godot idle game"). Headless binary: `"$HOME/Library/Application Support/Steam/steamapps/common/Godot Engine/Godot.app/Contents/MacOS/Godot"` for CI-style validation.

## Users

Idle/incremental-genre players on desktop who love Melvor Idle's loop. Primary user is the developer themselves (hobby project); design targets players who value transparent math, visible drop tables, and honest offline gains.

## Product Purpose

Valued Resident — An Idle Wasteland: a desktop idle game replicating the Melvor Idle gameplay loop (trainable skills, XP levels, gathering → processing → gear → combat, level-gated unlocks, offline progress) re-themed as a goofy post-apocalyptic atompunk parody. Success for the MVP vertical slice: the game feels like Melvor within the first five minutes, all five slice skills are trainable, the zone boss is beatable with slice-crafted gear, saves and uncapped offline gains work flawlessly, and a headless test suite passes.

## Positioning

The full Melvor-style idle loop — not a clicker — wrapped in an original atompunk wasteland parody that is legally distinct from both Melvor (no copied art/text/names; mechanics only) and Fallout (slant parody: original names, original art, zero trademarks). Fully local, no accounts, no telemetry, uncapped full-rate offline progress.

## Operating Context

Player picks an activity per skill category and lets it run; sessions are short check-ins between long away periods. On relaunch a "While You Were Away" modal grants uncapped full-rate gains for elapsed time. Min window 1280×720, resizable, mouse + full keyboard navigation. English only.

## Capabilities and Constraints

MVP vertical slice (approved scoping brief at `docs/ultron/town-hall.md` is the contract):

- Skills (5): Scavenging, Foraging (gathering); Junksmithing, Cooking (processing); Wasteland Combat (one zone, ~4 monsters + boss; tick-based auto-battle: attack speed, accuracy, max hit; weapon+armor slots; food auto-eat; death stops combat, no losses).
- Systems: per-skill XP/levels with level-gated unlocks; inventory; shop with parody bottle-cap currency; equipment; uncapped full-rate offline progress; atomic versioned local saves with backup rotation; settings (font scale, fullscreen).
- Non-goals (fence): no prestige, no second combat zone/dungeons, no mastery, no minigames, no cloud/accounts/telemetry/network, no mobile/web in MVP, no monetization, no asset-sourced music.
- Constraints: all art original (code-drawn/SVG) or verified CC0 with provenance log; naming gated by trademark-proximity checklist; data-driven content (skills/items/monsters as data, not code); content schema separate from versioned save schema.

## Brand Commitments

- Title: **Valued Resident — An Idle Wasteland** (plate form: VALUED RESIDENT). Renamed from RADLANDS 2026-09-15 per trademark conflict (U.S. reg. serial 90506045, class 28, live); unattended-halt resolution, user override open. Conflict scan + full shortlist: `docs/ultron/production-log.md` → Title Change Record. A future title swap touches: PRODUCT.md, naming-bible.md §0/§10, `project.godot` `config/name`, plan.md title line, content/save-schema doc headers, future T9 title screen.
- Tone: goofy parody — cheerful corporate-dystopia satire, pre-war ads for impossible products, chirpy apocalypse propaganda, pun-heavy item names.
- Binding: no trademarks or protected iconography from Fallout (incl. Fallout, Vault-Tec, Nuka-Cola, Pip-Boy, Vault Boy, G.E.C.K., Deathclaw, Stimpak, RadAway) or Melvor; no copied assets or text.

## Evidence on Hand

No code, assets, or content exist yet (greenfield). Approved scoping brief: `docs/ultron/town-hall.md` (all ten assembly heroes individually thumbs-upped). Engine verified installed (Godot 4.7.2.stable). Do not fabricate testimonials, players, or media.

## Product Principles

1. The loop is the product: every screen answers "what fills next, and what does it unlock?"
2. Honest math: rates, drop tables, and offline gains visible and exact — no hidden multipliers in the slice.
3. Parody without infringement: every name, icon, and line of flavor is original and checklist-cleared.
4. Fully local and durable: the save is sacred — atomic writes, versioned format, backup rotation.
5. Data over code: content lives in data files tuned by hand; the engine reads, never hardcodes.

## Accessibility & Inclusion

WCAG-AA contrast theme tokens (CRT-terminal palette must be checked, not assumed); scalable fonts; full keyboard navigation with visible focus indicators.
