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

The game window opens at 1280x720, uses the GL Compatibility renderer, and is playable with mouse or keyboard alone. Saves live in Godot's per-user `user://` data directory, never in the repo.

## Run the tests

```bash
./run_tests.sh
```

The runner imports the project headless once, then runs the full [GUT](https://github.com/bitwes/Gut) suite from `tests/` and exits non-zero on any failure. By default it looks for the Steam macOS Godot binary; point it elsewhere with:

```bash
GODOT=/path/to/godot ./run_tests.sh
```

## Features

- **Seven departments, five skills** — Scavenging, Foraging, Junksmithing, Cooking, and Wasteland Patrol (auto-battle combat), plus the Requisition Depot shop and the Manifest (inventory and equipment).
- **Honest math** — drop tables and success rates are posted on screen; every gameplay number renders in mono digits.
- **Clearance gates** — skill levels unlock new activities and recipes as numbered clearances.
- **Auto-battle patrols** — attack speed, accuracy, max hit; weapon and armor slots; food is auto-eaten at half health, best first. Death ends the patrol with zero losses.
- **One zone, one boss** — the Litterbug, Greater Dust Bunny, Fizzard, and Feral Snack Dispenser stand between you and The Superintendent.
- **Crowns economy** — buy and sell at the Depot, with both prices posted per line.
- **Uncapped offline progress** — full-rate gains for all elapsed time, including survivable offline combat: a patrol that would fail is recalled at the instant of death, and a posted **MAIL CALL** notice reports everything you earned while away.
- **Durable saves** — atomic writes, a versioned format, and rotating backups; a killed process cannot corrupt a save.
- **Keyboard-first accessibility** — the whole game is playable without a mouse, with visible focus, font scaling to 200%, and a WCAG-AA-checked theme.

## Controls

| Key | Action |
| --- | --- |
| `1`–`7` | Jump to a department (digit row or numpad) |
| `Tab` / `Shift+Tab` | Move focus through the concourse |
| `Enter` / `Space` | Activate the focused control |
| `Esc` | Acknowledge a MAIL CALL notice |

Every control is also reachable by mouse. Modifier combos (`Cmd`/`Ctrl`/`Alt` + digit) are left to the OS.

## Content is data, not code

All game content — items, skills, activities, recipes, drop tables, monsters, equipment, shop stock, XP curves — lives in `data/*.json`. A validating loader hydrates it into typed classes at boot and fails loudly on any malformed record, so the game never hardcodes balance numbers. The contract for every record is documented in [`docs/content-schema.md`](docs/content-schema.md), and the combat/economy math behind the numbers in [`docs/balance-notes.md`](docs/balance-notes.md).

## Assets & licenses

Every shipped file under `assets/` has a provenance row in [`ASSETS.md`](ASSETS.md):

- Fonts (Big Shoulders Stencil Display, Public Sans, Courier Prime) are SIL OFL-1.1 licensed from [google/fonts](https://github.com/google/fonts), with each family's `OFL.txt` bundled beside it.
- All theme textures and game icons are original SVGs authored for this project.
- GUT, the test framework, is an MIT-licensed editor plugin used in development only; Godot strips editor plugins from exported builds.

## Status

Hobby project; vertical slice complete, pre-release. The code itself has no distribution license yet (all rights reserved for now). The subtitle word "Wasteland" is queued for a naming/licensing review before any wider distribution.

## Documentation

- [`docs/content-schema.md`](docs/content-schema.md) — content data contract
- [`docs/save-schema.md`](docs/save-schema.md) — save file format
- [`docs/balance-notes.md`](docs/balance-notes.md) — combat and economy math
- [`docs/theme-contrast-table.md`](docs/theme-contrast-table.md) — theme contrast evidence
- [`ASSETS.md`](ASSETS.md) — asset provenance log
