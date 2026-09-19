# Valued Resident — An Idle Wasteland

A desktop idle game in the spirit of Melvor Idle, set inside a bomb shelter's institutional signage. Train skills, watch exact drop rates, earn clearances, gear up, and send yourself on patrol — then close the window and let the wasteland file your paperwork. Fully local: no accounts, no telemetry, no network.

The shelter never stopped issuing cheerful directives. You are the resident they address.

## Why this exists

Idle games too often hide their math. This one posts it: every rate, drop table, and offline gain is visible and exact — no hidden multipliers. The Melvor-style loop (gathering → processing → gear → combat, with level-gated unlocks) is wrapped in an original atompunk corporate-dystopia parody, with its own names, art, and voice. All assets are original or openly licensed; no trademarks, no copied content.

## Quickstart

Requires [Godot 4.7](https://godotengine.org/download) (developed and tested with 4.7.2.stable). No prebuilt binaries yet — run from source.

1. Install Godot 4.7.
2. In Godot, import the project folder (`project.godot`) and let it import assets.
3. Press **F5** (Run Project). The main scene is already configured.

First import from the command line instead:

```bash
godot --headless --path . --import
```

The game window opens at 1280x720, uses the GL Compatibility renderer, and is playable with mouse or keyboard alone. A first run opens on the **ORIENTATION FORM O-1** — a posted seven-line checklist that walks you to your first shift, clearance, sale, craft, patrol provision, victory, and deputy. Saves live in Godot's per-user `user://` data directory, never in the repo.

## Run the tests

```bash
./run_tests.sh
```

The runner imports the project headless once, then runs the full [GUT](https://github.com/bitwes/Gut) suite from `tests/` and exits non-zero on any failure. By default it looks for the Steam macOS Godot binary; point it elsewhere with:

```bash
GODOT=/path/to/godot ./run_tests.sh
```

## Features

- **Eight departments, five skills** — Scavenging, Foraging, Junksmithing, Cooking, and Wasteland Patrol (auto-battle combat), plus the Requisition Depot shop, the Manifest (inventory and equipment), and the Personnel office.
- **Departmental Dossiers (Form R-1)** — every skill carries a 23-line objectives register posted in its docket: level ladders, gather/craft/kill counts, equips, zone clears, economy rungs, and a set-completion capstone. Progress stamps itself as you play ("12/23 STAMPED"), rewards post automatically (MERIT PAY in Crowns, COMMENDATION in XP — no claim buttons anywhere), and a completed dossier posts its ALL 23 STAMPED plate. 115 objectives in all, authored against the shipped content.
- **Depth at every tier** — each gathering skill runs 9 activity tiers (up from 4) with new materials trickling through the tables; Junksmithing and Cooking each carry 20 recipes; equipment spans four tiers (T1 shiv and vest to the T4 Line-Item Veto, Cloture, Motorcade Mantle, and Turnpike Aegis); food climbs to the 230-heal Court Feast. Roughly twice the run-1 content.
- **Two zones, two bosses** — clear the Sunny Exclusion Zone's fauna and The Superintendent (clearance 14, slice-max gear + stews), then step through the zone tabs into The Gift Court: five more stands of fauna and The Regional Manager at clearance 40, who wants the crafted T4 ladder and a thermos of Court Feast.
- **ORIENTATION FORM O-1** — a low-text first-run checklist posted on the concourse: seven stencil lines, each stamped as you do it (work a shift, earn a clearance, file a claim, process a product, provision the patrol, clear a nuisance, deputize a resident). A walking arrow cue points at the next department, and every step now REVEALS its target — the right department, the right tab, the control scrolled into view and pulse-marked. Completing the form posts the DULY ORIENTED stamp and an orientation stipend.
- **Personnel postings** — you start with one posting (your own two hands) and deputize residents at the PERSONNEL plate (D-08) to run more skills at once, up to all five. Starting a shift with no free posting is refused with a posted directive — nothing is silently stopped. The patrol occupies a posting like any skill.
- **An icon language, not decoration** — every stat has its own instrument glyph, clearance gates carry a rising three-step staircase (never a padlock), log and mail lines carry their subject's mark, and every price carries the crown mark. 96 original SVGs, one stencil grammar.
- **Honest math** — drop tables and success rates are posted on screen; every gameplay number renders in mono digits.
- **Clearance gates** — skill levels unlock new activities and recipes as numbered clearances.
- **Auto-battle patrols** — attack speed, accuracy, max hit; weapon and armor slots; food is auto-eaten at half health, best first. Death ends the patrol with zero losses.
- **Crowns economy** — buy and sell at the Depot, with both prices posted per line and a full sell ladder (1 / 10% / 25% / 50% / 100% / custom) on your own holdings. Objective merit pay is part of the same wallet: it is sized to stay under 20% of duty income at every deputy rung, and the first deputy (300 Crowns) wants a stamped rung or two beside your selling.
- **Uncapped offline progress** — full-rate gains for all elapsed time, including survivable offline combat: a patrol that would fail is recalled at the instant of death, and a posted **MAIL CALL** notice reports everything you earned while away — dossier stamps included.
- **Durable saves** — atomic writes, a versioned format (currently v3, migrating run-1 and run-2 records forward), and rotating backups; a killed process cannot corrupt a save.
- **Keyboard-first accessibility** — the whole game is playable without a mouse, with visible focus, font scaling to 200%, and a WCAG-AA-checked theme.

## Controls

| Key | Action |
| --- | --- |
| `1`–`8` | Jump to a department (digit row or numpad) — `8` is PERSONNEL. The digit rides the card's own stencil (`SCAV · 1`) |
| `Tab` / `Shift+Tab` | Move focus through the concourse (the eight compact cards sit in one tab cycle, in grid order) |
| Arrow keys | Walk the 2-column card grid; hop between the Patrol's zone tabs **and** the Depot's BUY/SELL tabs |
| `Enter` / `Space` | Activate the focused control |
| `Esc` | Acknowledge a MAIL CALL notice, or step back to the department a tutorial jump departed from |
| Any key | While a text field is focused (the Depot's CUSTOM amount), the typing goes to the field — department hotkeys hold off |

Every control is also reachable by mouse. Modifier combos (`Cmd`/`Ctrl`/`Alt` + digit) are left to the OS.

## Reading the concourse

- **Compact cards** — the left wall is a 2-column grid of eight department cards: the department mark, the short stencil name with its hotkey digit, a mono readout (clearance grade + XP on skills; wallet, holdings, or posting count on the Depot/Manifest/Personnel), a hairline XP gauge, and a filled deputy badge that burns exactly while the department holds a posting. The active department's card is amber, swells, and takes the `>> ` prefix — state never rides on color alone.
- **Depot tabs & the sell ladder** — the Depot docket posts BUY (the shop) and SELL (your own sellables — never the shop's stock) as two tabs; SELL lines lead with the full quantity ladder: `SELL 1 · SELL 10% · SELL 25% · SELL 50% · SELL 100% · CUSTOM…`. Counts post on the buttons (a rung whose share floors to zero disables, at its honest `0`), percentages floor exactly, and CUSTOM validates `1–stack` with a live exact `TENDER N · N CROWNS` preview — out-of-range amounts are refused in voice, never clamped.
- **Tutorial reveal cues** — when an O-1 step becomes current, the game walks you to the control: it selects the department, posts the right tab (FILE A CROWNS CLAIM opens the Depot on SELL), scrolls the target fully into view, and marks it with one brief settle pulse. A step you can't act on yet states so on its own line (`— WORK FOR INVENTORY FIRST` / `— GATHER SUPPLIES FIRST`) and the arrow cues the source department instead; the suffix withdraws the moment you can act. `Esc` steps back.
- **Refusal feedback** — a refused posting (board full, clearance short, supplies missing) stamps a red notice strip at the top of the docket in the Department's voice, naming the reason; posting refusals carry a one-press REASSIGN that ceases the named posting and starts yours — validated before anything ceases.
- **The status line** — `CONSOLE 09 · FORM 9-A` in the bottom console is the shell's status line: objective stamps, record filings (`RECORD FILED · HH:MM:SS`), and the orientation completion (`FORM O-1 FILED · DULY ORIENTED`) flash there for two seconds, then the standing serial returns.

## Content is data, not code

All game content — items, skills, activities, recipes, drop tables, monsters, zones, equipment, shop stock, XP curves, staffing prices, and the 115 dossier objectives — lives in `data/*.json`. A validating loader hydrates it into typed classes at boot and fails loudly on any malformed record, so the game never hardcodes balance numbers. The contract for every record is documented in [`docs/content-schema.md`](docs/content-schema.md), and the combat/economy math behind the numbers in [`docs/balance-notes.md`](docs/balance-notes.md).

## Assets & licenses

Project code and original assets are MIT-licensed — see [`LICENSE`](LICENSE).

Every shipped file under `assets/` has a provenance row in [`ASSETS.md`](ASSETS.md):

- Fonts (Big Shoulders Stencil Display, Public Sans, Courier Prime) are SIL OFL-1.1 licensed from [google/fonts](https://github.com/google/fonts), with each family's `OFL.txt` bundled beside it.
- All theme textures and game icons are original SVGs authored for this project.
- GUT, the test framework, is an MIT-licensed editor plugin used in development only; Godot strips editor plugins from exported builds.

## Status

Hobby project; vertical slice, the run-2 systems (orientation form, personnel postings, expanded icon language), the run-3 depth + objectives expansion, and the run-5 UX overhaul (compact card wall, refusal feedback with one-press REASSIGN, Depot BUY/SELL tabs with the sell ladder, tutorial deep-linking) complete, pre-release. The subtitle word "Wasteland" is queued for a naming/licensing review before any wider distribution.

## Documentation

- [`docs/content-schema.md`](docs/content-schema.md) — content data contract
- [`docs/save-schema.md`](docs/save-schema.md) — save file format
- [`docs/balance-notes.md`](docs/balance-notes.md) — combat and economy math
- [`docs/theme-contrast-table.md`](docs/theme-contrast-table.md) — theme contrast evidence
- [`ASSETS.md`](ASSETS.md) — asset provenance log
