---
name: Valued Resident — An Idle Wasteland
description: A bomb shelter's institutional signage system — bone enamel over rolled steel, amber the only energized signal, every gameplay number posted in mono.
colors:
  bone-enamel: "#F2EDE3"
  rolled-steel: "#4E5560"
  steel-deep: "#3A404A"
  steel-hi: "#6B7482"
  steel-lo: "#2E333C"
  institutional-navy: "#20334F"
  navy-hi: "#33507A"
  signal-amber: "#FFB000"
  safety-red: "#B3261E"
  bone-dim: "#D0CEC9"
  navy-dim: "#546480"
  paper-notice: "#F2E7CF"
typography:
  display:
    fontFamily: "Big Shoulders Stencil Display, Arial Narrow, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    letterSpacing: "1.25px"
  headline:
    fontFamily: "Big Shoulders Stencil Display, Arial Narrow, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    letterSpacing: "1.25px"
  title:
    fontFamily: "Big Shoulders Stencil Display, Arial Narrow, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    letterSpacing: "1px"
  body:
    fontFamily: "Public Sans, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
  label:
    fontFamily: "Public Sans, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    letterSpacing: "2.5px"
  mono:
    fontFamily: "Courier Prime, monospace"
    fontSize: "17px"
    fontWeight: 400
rounded:
  gauge-fill: "1px"
  paper: "2px"
  plate: "3px"
  scroll-grabber: "4px"
  focus-ring: "5px"
spacing:
  column: "16px"
  row: "20px"
  vent-inset: "6px"
  plate: "14px 10px"
  button: "18px 10px"
  riveted-frame: "22px"
  docket-margin: "24px 18px"
  shell-margin: "56px 24px 28px 18px"
components:
  plate-enamel:
    backgroundColor: "{colors.bone-enamel}"
    textColor: "{colors.institutional-navy}"
    rounded: "{rounded.plate}"
    padding: "14px 10px"
  plate-energized:
    backgroundColor: "{colors.institutional-navy}"
    textColor: "{colors.signal-amber}"
    rounded: "{rounded.plate}"
    padding: "16px 12px"
  plate-danger:
    backgroundColor: "{colors.safety-red}"
    textColor: "{colors.bone-enamel}"
    rounded: "{rounded.plate}"
    padding: "16px 12px"
  paper-notice:
    backgroundColor: "{colors.paper-notice}"
    textColor: "{colors.institutional-navy}"
    rounded: "{rounded.paper}"
    padding: "16px 12px"
  vent-housing:
    backgroundColor: "{colors.steel-lo}"
    rounded: "{rounded.paper}"
    padding: "6px"
  panel-riveted:
    padding: "{spacing.riveted-frame}"
  button:
    backgroundColor: "{colors.bone-enamel}"
    textColor: "{colors.institutional-navy}"
    typography: "{typography.title}"
    rounded: "{rounded.plate}"
    padding: "18px 10px"
  button-energized:
    backgroundColor: "{colors.institutional-navy}"
    textColor: "{colors.signal-amber}"
    typography: "{typography.title}"
    rounded: "{rounded.plate}"
    padding: "18px 10px"
  button-danger:
    backgroundColor: "{colors.safety-red}"
    textColor: "{colors.bone-enamel}"
    typography: "{typography.title}"
    rounded: "{rounded.plate}"
    padding: "18px 10px"
  input-recessed:
    backgroundColor: "{colors.steel-deep}"
    textColor: "{colors.bone-enamel}"
    typography: "{typography.body}"
    rounded: "{rounded.paper}"
    padding: "10px 7px"
  gauge-track:
    backgroundColor: "{colors.steel-deep}"
    rounded: "{rounded.paper}"
  gauge-fill:
    backgroundColor: "{colors.signal-amber}"
    rounded: "{rounded.gauge-fill}"
---

# Design System: Valued Resident — An Idle Wasteland

## Overview

**Creative North Star: "The Shelter Signage System"**

The whole game is a bomb shelter's institutional signage system — a bureaucracy that survived the apocalypse and never stopped issuing cheerful directives. The player reads the shelter like a resident following signage: department plates direct to skills, clearance levels gate content, offline gains arrive as a posted MAIL CALL notice, and combat death posts a red RETURN TO SHELTER plate. Voice: institutional bureaucratic cheer (PRODUCT.md's "cheerful corporate-dystopia satire"); audience: idle-genre desktop players who value transparent math and honest offline gains; register: Operate. The system deliberately refuses two looks: the idle-category default (dark admin dashboard, green XP bars) and its predictable opposite (glowing green CRT terminal). No glow, no scanlines, no neon — light comes from posted paper, amber signal enamel, and one slit of wasteland daylight at the concourse's left edge.

Materials do the branding: bone-white enamel plates over a rolled-steel ground, institutional navy as the structural ink, riveted panel frames, recessed vent housings, and paper notices taped to the steel. Exactly two colors carry meaning — amber (active/energized) and red (danger/cancel/locked); everything else is ground and ink. Copy is all-caps stencil signage on plates and rubber-stamp bureaucratic cheer on paper. Every gameplay number prints exactly, in mono digits. The system is recognizable with all content removed: strip every label and the concourse still reads as a shelter wall.

Depth is physical, not optical: plates lift off the steel on hard drop shadows, recesses sink into darker ground, the riveted frame bevels its edges. State is never color-alone — the energized plate is amber AND swells forward AND carries a `>> ` text prefix; combat phases render distinct wording, not just distinct colors. Everything ships a Default + Active state pair.

**Key Characteristics:**

- Bone enamel over rolled steel; institutional navy ink; two signal colors only (amber = energized, red = danger).
- Three typefaces: Big Shoulders Stencil Display (signage caps), Public Sans (body), Courier Prime (all gameplay numbers).
- Near-square corners (1–3 px) — institutional form language, never soft UI roundedness.
- WCAG-AA on every registered text-on-ground pair, machine-verified at test time.
- Physical depth: drop-shadow plates, recessed inputs/vents, beveled riveted frames — no glow, no gradients.
- One authored motion: the bulkhead-slide department transition plus the energized swell; log lines stamp in on batched engine flushes, never per-frame.
- Full keyboard navigation with a visible amber focus ring; font scale 100/150/200% re-sizes every registered size from one call.

**Recorded departures from the brief (as built).** The direction contract (`scripts/theme/signage_theme.gd` header, `docs/ultron/design-brief.md`) is law; where the build differs, the build is what shipped:

- Title plate reads **VALUED RESIDENT / AN IDLE WASTELAND · A D.O.C.S. FACILITY** — the brief predates the RADLANDS → Valued Resident rename (2026-09-15, trademark conflict; PRODUCT.md Brand Commitments).
- The brief's "Depot/Shop" shipped as **REQUISITION DEPOT** (serial D-06) and "Manifest/Inventory" as **MANIFEST** (D-07).
- The brief's "enamel gloss" shipped as matte: enamel plates are flat bone fill + ink border + drop shadow, with no gloss or sheen treatment.
- Level-ups: the brief's "swap an enamel plate's stenciled clearance grade" shipped as the mono gauge readout (`CLEARANCE 02 · 20/65 XP TO NEXT`), a stamped log line (`CLEARANCE %02d EARNED`), and MAIL CALL crossing lines (`CLEARANCE 02 » 03`).
- Vent grids: the perforated `vent_tile.svg` texture was authored, but the shipped VentHousing is a flat recessed panel (steel-lo ground, steel-hi lower edge); the theme references no vent texture.
- Serial layout: wrapped serial lines stack as full-width VBox rows — a WORD_SMART label never sits beside a foreign EXPAND_FILL sibling (the T15 collapse guard; see Layout).

## Colors

A survivalist institutional palette: warm bone and paper against steel blues, with exactly two meaning-carrying signals — amber for energized, red for danger. Source of truth: `scripts/theme/signage_tokens.gd`; every registered text-on-ground pair is re-verified by `tests/probe_theme.gd` and recorded in `docs/theme-contrast-table.md`.

### Primary

- **Bone Enamel** (`colors.bone-enamel`): the enamel plate ground and the primary text ink on every dark ground (steel, steel recesses, navy, red). Warm off-white, the shelter's issued signage finish.
- **Institutional Navy** (`colors.institutional-navy`): the structural ink — stencil text on bone and paper, plate borders on enamel — and the ground of energized plates and menu-selected rows. A desaturated uniform blue that reads as "government issue," never as corporate tech-blue.

### Secondary

- **Signal Amber** (`colors.signal-amber`): the only energized color. Energized plate grounds' border and text, gauge fills, focus rings, interaction-lit borders, the daylight slit's warm wash, and large stencil caps on steel (3:1 class only — never body-size text on rolled steel). Rarity is the point: amber means "this is live."

### Tertiary

- **Safety Red** (`colors.safety-red`): the only danger color — danger plates (with bone text), rubber stamps on paper, red ink on bone. Never appears as text or border on rolled steel or navy (1.15:1 / 1.95:1 — fails AA); danger always posts as a plate or a stamp, never as red type on a dark ground.

### Neutral

- **Rolled Steel** (`colors.rolled-steel`): the concourse ground — every screen's default background.
- **Steel Deep** (`colors.steel-deep`): recesses — vent housings, gauge tracks, input fields, disabled button grounds, unselected tabs.
- **Steel Hi** (`colors.steel-hi`): bevel highlights, separators, scrollbar grabbers, vent housing edges (non-text).
- **Steel Lo** (`colors.steel-lo`): bevel shadows, bore darks, vent housing ground, inset borders (non-text).
- **Navy Hi** (`colors.navy-hi`): the energized plate's bevel highlight (non-text). Deliberately NOT used as an energized-button hover ground — amber text on it measures 4.46:1, under the 4.5:1 body floor (T15 contrast audit).
- **Bone Dim** (`colors.bone-dim`): secondary text on steel grounds — bone tinted toward the steel's hue, never neutral gray.
- **Navy Dim** (`colors.navy-dim`): disabled ink on paper and bone.
- **Paper Notice** (`colors.paper-notice`): the posted-paper ground (notices, tooltips, popup menus, the MAIL CALL card), edged with a `#D9CBA8` hairline border.

### Registered AA pairs (all verified)

| Pair (foreground on ground) | Ratio | Class |
|---|---|---|
| bone enamel on rolled steel | 6.45:1 | body |
| bone dim on rolled steel | 4.78:1 | body |
| bone enamel on steel deep | 8.94:1 | body |
| bone dim on steel deep | 6.64:1 | body |
| bone enamel on institutional navy | 10.92:1 | body |
| institutional navy on bone enamel | 10.92:1 | body |
| signal amber on institutional navy | 6.96:1 | body |
| signal amber on steel deep | 5.70:1 | body |
| signal amber on rolled steel | 4.10:1 | large only (≥24 px regular / ≥18.66 px bold, UI accents) |
| bone enamel on safety red | 5.60:1 | body |
| safety red on bone enamel | 5.60:1 | body |
| institutional navy on paper notice | 10.38:1 | body |
| safety red on paper notice | 5.32:1 | body |
| navy dim on paper notice | 4.87:1 | body |

Forbidden (must stay unregistered): bone text on paper (1.05:1), red text on rolled steel (1.15:1), red text on navy (1.95:1).

### Named Rules

**The One Signal Rule.** Amber is the only energized color in the system and it means exactly one thing: live/active. Interaction, focus, gauges, and the energized state all draw from it. Never introduce a second accent, a green success, or a blue info color.

**The Paper Takes Navy Ink Rule.** Paper notices carry navy ink (or a red stamp) — never bone text. Paper is the one light ground where the navy ink does the talking.

**The Red Never Speaks on Dark Rule.** Red never appears as text or border on rolled steel or navy. Danger posts as a red enamel plate carrying bone text, or as a red rubber stamp on paper.

**The Registered Pair Rule.** Any new text-on-ground combination must be added to `CONTRAST_PAIRS` in `scripts/theme/signage_tokens.gd` with its AA class and must pass the recomputation in `tests/probe_theme.gd`. An unverified pair does not ship.

## Typography

**Display Font:** Big Shoulders Stencil Display (SemiBold 600 + Bold 700, OFL, bundled)
**Body Font:** Public Sans (Regular 400 / SemiBold 600 / Bold 700, OFL, bundled)
**Label/Mono Font:** Courier Prime (Regular + Bold, OFL, bundled) — all gameplay numbers

**Character:** Condensed stencil caps give every plate its issued-signage authority; the grotesk workhorse keeps directives effortlessly readable; mono digits make the honest math visually distinct from flavor text. Three faces, three jobs, no crossover.

### Hierarchy

All sizes at 100% font scale; every size below is registered in `SignageTheme.FONT_SIZE_BASES` and scales with `apply_font_scale()` (see Layout).

- **Display** (stencil Bold 700, 26 px, glyph-tracking +1.25): `PlateTitle` — department docket headers and the facility title plate.
- **Headline** (stencil Bold 700, 24 px, glyph-tracking +1.25): `PaperTitle` — posted-notice headlines (MAIL CALL, ZONE SECURED).
- **Title** (stencil SemiBold 600, 18 px, glyph-tracking +1.0): `FormTitle` (form-line / tier-card / fauna-card titles), button labels, tab labels. A section label rung above it (`SectionLabel`, stencil SemiBold 19 px, +1.0) heads major docket sections.
- **Body** (Public Sans Regular 400, 15 px default; `BodyCopy` 15 / `BodyCopyDim` 14 / `PlateBody` 13 navy-on-bone / `PlateBodyEnergized` 13 amber-on-navy): directives, plate sub-copy, modal prose.
- **Label** (Public Sans SemiBold 600, 12 px, glyph-tracking +2.5, uppercase): `MicroLabel` — vent serials and section eyebrows ("CLEARANCE GAUGE · POSTED RATES ARE THE HONEST RATES").
- **Mono** (Courier Prime, 17 px `MonoValue` / 26 px bold `MonoBig` / 13 px `PlateSerial` serials / 15 px list + input text): every number, serial, rate, and log line. Bold (`MonoValueEnergized`) marks energized values on navy.

Energized twins exist for on-plate roles: `PlateTitleEnergized` (amber), `FormTitleEnergized` (amber stencil), `MonoValueEnergized` (amber bold mono), `PlateSerialNavy` (navy mono on light grounds), `PaperStamp` (Public Sans Bold 700, 13 px, +1.5 tracking, safety red — the rubber stamp).

### Named Rules

**The Mono Digits Rule.** Every gameplay number — XP, rates, currency, stack counts, percentages, gauges, log lines — renders in Courier Prime via `MonoValue` / `PlateSerialNavy` / `MonoBig` / the mono `ItemList`. If it is a number the player can act on, it is mono.

**The Stencil Means Signage Rule.** Stencil caps appear only on issued signage: plate titles, section labels, buttons, tabs. Body copy, paper notices, and directives use Public Sans; the stencil never sets a sentence.

**The Honest Number Rule.** Numbers print exactly (integer grouping, no rounding) via `SignageFmt`; the one sanctioned departure is the ≥10^15 suffix form, which truncates so a displayed value can understate but never overstate the true integer.

## Layout

Desktop-native Godot Control layout; minimum window 1280×720, resizable up; mouse + full keyboard navigation in one tab cycle. No web-style grid — the spatial model is a physical wall.

**Concourse topology** (`scenes/main.gd`, the single game shell): a full-rect rolled-steel wall; a 160 px half-open bulkhead mouth at the left edge (daylight slit, drawn in code); a shell margin (56/24/28/18) holding one column (16 px separation) of: **header row** (20 px separation — the bone facility plate expanding, beside a 380 px posted paper notice) → **body row** (20 px separation — the plate wall plus the docket region) → **console bar** (a riveted steel panel; its row is an HFlow that wraps to two lines at 200% font scale).

- **Plate wall** (left ~third): vertical scroll only, 10 px separation, seven department plates at 340×56 minimum each — Buttons with stencil caps and word-smart autowrap, each posting its designation digit after the name (`SCAVENGING · 1` … `MANIFEST · 7` — the digit of the plate's D-0n serial and the key that selects it).
- **Docket region** (right ~two-thirds): scrollable riveted-steel housing (`SteelPanel`, clipped) with a 24/18 inner margin. A department change always opens the docket at its content top — the scroll offset resets so the enamel header plate leads (pinned by the concourse probe's R1 geometry checks). Each department's docket is a VBox (16 px separation): enamel header plate (title + serial) → posted paper directive → live content controller (VBox, 14 px separation) → the big stencled BEGIN SHIFT button (300×64, energized) → a wrapping footer serial.
- **Docket internals** (skill dockets): hidden-at-rest energized status plate → vent housing with the clearance gauge + mono readout → micro section header → cards VBox (8 px separation) → vent-housed stamped log.
- **Bulkhead transitions**: department changes slide a riveted shutter across the docket (bounded — 0.24 s close, 0.34 s open; see Components), the daylight mouth pulses, and the new docket settles out of the door's shadow (28 px offset + 0.35 alpha → home, 0.30 s).
- **Focus-follows-scroll**: on every focus change the shell calls `ensure_control_visible` on each ancestor ScrollContainer, so keyboard focus is always on screen (Godot's ScrollContainer does not follow focus into nested content).
- **Font-scale mechanism**: the settings slider carries three detents (100/150/200%); `UiTheme.apply_font_scale()` re-sets every registered font size (base × scale) inside the one shared Theme — one call resizes all text, no per-control work. The step is persisted in save settings.

**Density**: institutional and generous — plates and panels breathe through their stylebox content margins (10–22 px), serials and micro labels pack tight inside vents. Long serial lines wrap (`AUTOWRAP_WORD_SMART`) rather than ever demanding horizontal scrolling.

### Named Rules

**The Stacked Serial Rule.** A wrapped serial label stacks as a full-width VBox row. A WORD_SMART autowrap label never sits beside a foreign EXPAND_FILL sibling — Godot starves it to a 1 px vertical column (the T15 collapse, pinned by `tests/test_a11y.gd` and `probe_a11y.gd`'s collapse sweep at both font scales).

**The Two-Thirds Rule.** The docket owns the right two-thirds of the concourse; the plate wall never competes with it. The primary action of any docket is its big stencled button, never a toolbar.

## Elevation & Depth

Physical material depth, no optical effects: no gradients, no glow, no blur. Plates lift, recesses sink, and the steel ground stays flat. Shadows are hard-edged, downward, and small — enamel signage bolted to a wall, not floating cards over a backdrop.

### Shadow Vocabulary

- **Enamel lift** (`0 4px 8px rgba(16,24,41,0.35)`): default plate and button shadow — the signage lifts slightly off the steel.
- **Energized lift** (`0 6px 12px rgba(10,18,28,0.55)`): energized plates; the amber-bordered navy plate sits furthest forward.
- **Danger lift** (`0 5px 10px rgba(24,5,5,0.4)`): danger plates.
- **Hover lift** (`0 6px 10px rgba(16,24,41,0.45)`): hovered enamel plates and buttons — border goes amber, shadow deepens.
- **Pressed settle** (`0 2px 4px rgba(10,15,26,0.3)`): pressed buttons; content margins shift down 2 px. Buttons physically depress.
- **Amber halo** (`0 4px 8px rgba(255,176,0,0.25)`): the energized button's normal shadow — the one warm shadow in the system.
- **Paper cast** (`3px 5px 6px rgba(0,0,0,0.32)`): posted paper — asymmetric, like a sheet taped to steel rather than a floating card.

### Named Rules

**The Plate Lifts, The Steel Recedes Rule.** Raised surfaces get a downward drop shadow; sunken surfaces (vents, inputs, gauge tracks) get a darker ground plus a heavier top/left border and never a shadow. The rolled-steel wall itself is perfectly flat.

## Shapes

Near-square, machined rectangles — the form language of issued signage. Corners run 1–3 px (gauge fill 1, paper/inset/vent 2, plates and buttons 3), with the focus ring at 5 px only because it expands 3 px beyond its control. No pill buttons, no large radii, no circles as containers.

Borders carry structure: enamel plates wear a 2 px navy ink border (3 px amber when energized, 2 px bone on danger); paper wears a 1 px `#D9CBA8` hairline. Recesses use the machined edge — an asymmetric border (2 px top/left, 1 px bottom/right) that reads as a stamped-in pocket. The riveted frame is a 64 px nine-patch (16 px texture margins) with bevel highlight top/left, bevel shadow bottom/right, and four corner rivets (ring, crown, specular).

Icon plates (see Components) are the one soft-ish shape: a 128-unit bone rounded square (rx 14) with an 8-unit navy border — a stamped enamel tile.

## Components

Every component ships Default + Active state pairs. Active never rides on color alone: energized states pair amber with the `>> ` text prefix (plates, cards, status lines) or with re-worded text (combat phases); the swell animation (below) is the third cue.

### Plate (the core surface)

- **Shape:** machined rectangle (3 px radius), ink border, enamel lift shadow.
- **Enamel (default):** bone ground, 2 px navy border, 14/10 padding; carries stencil title + mono serial (navy ink on bone).
- **Energized (active):** navy ground, 3 px amber border, amber title, 16/12 padding, deeper shadow — the live department.
- **Danger:** safety-red ground, 2 px bone border, bone text, 16/12 padding — gates, death, recall, CLOCK OUT.

### Riveted Steel Panel

The structural housing (docket housing, console bar, transition shutter): nine-patch riveted texture, 22 px content margins. Never carries text color of its own — it frames other components.

### Vent Housing

Recessed instrument grouping for gauges, logs, and stat reads: steel-lo ground, 1 px steel-hi edge on bottom/right, 2 px radius, 6 px inset. Contents: a `MicroLabel` serial eyebrow, then the instrument.

### Paper Notice

Posted bureaucracy: paper ground, `#D9CBA8` hairline, 2 px radius, asymmetric paper-cast shadow. Carries `PaperText` navy body (word-smart wrapped), an optional `PaperStamp` red rubber stamp ("POSTED — SECTOR B"), and `PaperTitle` headlines. Also the tooltip (10/6 padding, 13 px navy) and the popup-menu ground (14/8 padding, navy hover rows with bone text).

### Buttons

- **Shape:** 3 px radius; stencil SemiBold 18 px caps; 18/10 padding; plates sized by content (primary actions 300×64 / 320×56 minimum).
- **Default (bone):** bone ground, navy stencil text, 2 px navy border. **Hover:** border lights amber, shadow deepens (ground stays bone). **Pressed:** amber border, pressed settle shadow, content shifts down 2 px. **Disabled:** recessed steel-deep plate, bone-dim stencil.
- **Energized (primary action):** navy ground, amber stencil, 3 px amber border, amber halo. **Hover keeps the navy ground** — the earlier navy-hi hover step measured 4.46:1 for amber 18 px text, under the 4.5 floor; hover stays perceivable through the enlarged amber shadow, the always-amber border, and the cursor.
- **Danger:** red ground, bone stencil, 2 px bone border; hover brightens the ground (`#C22F28`).
- **Focus:** the amber focus ring (below) on all variants.

### CardButton (form-line / tier / fauna cards)

A button carrying a label stack (Godot Buttons ignore child minimums, so `CardButton` sizes itself to its stack, laid out inside the stylebox margins — keeping hit targets above the 24 px WCAG 2.5.8 floor). Stack: title row (icon 30 px + `FormTitle`), then full-width wrapped serial rows — rate line ("+10 XP / ACTION · 3.0 S INTERVAL") and yields line ("YIELDS: SCRAP METAL 70% ×1-2 · COPPER WIRING 15% ×1"). **Default:** bone plate, navy ink. **Active:** Energized button variation + `>> ` title prefix + amber mono serials. **Locked:** a nested danger plate posts "CLEARANCE n REQUIRED" (on the Depot, where gates span skills, the plate names both skill and grade).

### Gauges (enamel gauges)

Progress with the recessed-track + amber-fill material: track = machined inset (steel-deep, 2/1 px border, 3 px inner margin), fill = amber at 1 px radius; 20 px minimum height; no percentage text — the exact numbers sit in the mono readout line beneath ("CLEARANCE 02 · 20/65 XP TO NEXT"). Gauges also back both combat HP reads (RESIDENT / fauna) and the settings font-scale slider (recessed track, amber grabber area, enamel grabber disc; amber when lit).

### Phase Plates (combat state)

One plate component, four worded states — the color only escorts the wording: **FIGHTING** = energized plate, ">> PATROL ENGAGED — {FAUNA}"; **DEAD** = danger plate, "DECEASED — RETURN TO SHELTER" + zero-loss serial; **RECALLED** = danger plate, "PATROL RECALLED — RETURN TO SHELTER"; **VICTORY** = enamel plate, "VICTORY POSTED — {FAUNA} DECEASED". A persistent paper **ZONE SECURED** certificate posts once the boss falls.

### Stamped Logs

The vent-housed ItemList ("stamped drop lines"): mono 15 px bone on the recessed ground, 18 px inline icons, fixed 24 px row height per reserved line. Lines arrive only from batched engine signals, newest last, selected and scrolled into view, capped (60 skill / 160 patrol). Level-ups stamp "CLEARANCE %02d EARNED". A bloodless patrol window words its truth: every swing whiffed stamps MISS, a swing that connected and drew no blood (fauna min_hit 0) stamps NO DAMAGE — the engine's per-engagement hit counters (`combat.p_hits`/`m_hits`, ticked at the connect, before the damage roll) carry the distinction the HP diff cannot.

### MAIL CALL Modal (offline gains)

An interruption notice earns protected focus: a full-rect dim backdrop (`rgba(14,19,28,0.55)`) over the concourse, one centered paper card (620 px minimum width, scrollable body) posting PaperTitle "MAIL CALL" / "AWAY 2H 14M", navy mono gain lines with 18 px item icons, a nested danger plate for patrol recalls, honest disclosure lines (truncation, "NO SHIFTS WERE RUNNING…"), and the energized ACKNOWLEDGE RECEIPT button (320×56) which grabs focus on open; the modal traps the focus chain and Esc acknowledges.

### Inputs / Fields

Recessed pockets: steel-deep ground, machined 2/1 px border, 2 px radius, 10/7 padding; bone text, bone-dim placeholder, amber caret and 30%-amber selection. **Focus:** the border goes amber all around at 2 px. Read-only fields render as disabled recessed plates.

### Navigation

Department plates (the wall) + TabBar where tabs exist: selected tab = bone plate with 2 px navy border and navy stencil; unselected = steel-deep with a 2 px steel-lo underline; hover tints steel-hi at 35%. The plate's posted digit is a live accelerator: keys 1–7 (digit row and keypad) select their department from anywhere in the concourse — no Tab walk — with focus following to the destination plate so the tab chain resumes into the new docket; a posted MAIL CALL owns the input while it is up, and modifier combos (Cmd/Ctrl/Alt + digit) stay with the OS. Scrollbars are thin steel (4 px radius grabber, steel-hi) going amber when highlighted, bone when pressed. Full keyboard reachability is part of the navigation contract: every visible enabled control is focusable, and the shell scrolls focus into view.

### Focus Ring

The one system-wide focus treatment: a 2 px amber border, no fill, 5 px radius, expanded 3 px beyond the control's rect — visible against every ground it can sit on (4.10:1 vs steel, 6.96:1 vs navy, 5.70:1 vs steel-deep). Sliders, which draw no focus stylebox of their own, light their track border amber via an override on focus enter.

### Icon Plates (stencil icon set)

41 original SVGs, all `viewBox="0 0 128 128"`, self-contained primitives only (no text, images, gradients). Discipline: a bone enamel tile (116-unit rounded square, rx 14) with an 8-unit navy border; interior linework in navy round-capped/round-joined strokes (widths 4–7, closed forms filled bone). Palette is exactly the four semantic tokens — bone, navy, amber (13 uses: the crowns currency disc and glow-themed items/activities), red (3 uses: iodine root, roach meat, sewer landlord). Monsters are mundane objects, never mascot figures. Rendered at 18 px (log/mail rows), 26 px (docket reads), 30 px (card titles), keep-aspect-centered.

### Motion Grammar

- **Bulkhead slide** (the signature transition): a riveted shutter slides across the docket — close 0.24 s quad ease-in, open 0.34 s quint ease-out — while the daylight mouth's energy pulses up and back; the new docket settles from a 28 px offset / 0.35 alpha over 0.30 s quint ease-out. Bounded and infrequent: it marks a department change, nothing else.
- **Energized swell**: the energized plate scales to 1.05 from its left-center pivot over 0.22 s with a back ease-out — signage leaning toward the resident.
- **Stamp cadence**: log lines appear only on batched engine flushes (4 Hz ceiling) and immediate discrete signals (level-ups, combat ends, stops) — nothing updates per frame.
- **Micro-motions**: first-run chalk dismisses over 0.45 s; console serial flashes revert after 2.0 s.

## Do's and Don'ts

### Do:

- **Do** build every surface from the theme's StyleBox variations (EnamelPlate, EnergizedPlate, DangerPlate, SteelPanel, VentHousing, PaperNotice) — the concourse probe rejects ad-hoc panels.
- **Do** give every state a non-color cue: `>> ` prefixes, distinct wording, swell, stamp text.
- **Do** render every gameplay number in Courier Prime via `SignageFmt` (exact integers; truncating suffix form only ≥10^15).
- **Do** post rates and drop tables on the cards themselves ("POSTED RATES ARE THE HONEST RATES") — exact fractions, one decimal only when needed.
- **Do** register any new text-on-ground pair in `CONTRAST_PAIRS` and re-run the theme probe before shipping it.
- **Do** set label minimums through containers (PanelContainer content margins, CardButton stacks) and wrap long serials with WORD_SMART as full-width rows.
- **Do** keep paper copy in the institutional-bureaucratical-cheer voice, all caps, with rubber stamps ("THE DEPARTMENT THANKS YOU FOR BREATHING ATTENTIVELY.").

### Don't:

- **Don't** use amber as body-size text on rolled steel (4.10:1 — large stencil caps and UI accents only) or introduce any second accent color.
- **Don't** set red text on steel or navy, or bone text on paper — danger posts as a plate or stamp.
- **Don't** use the stencil face for sentences, body copy, or paper notices; never set gameplay numbers in Public Sans.
- **Don't** add glow, gradients, scanlines, or large radii — depth comes from lift shadows and recessed grounds only.
- **Don't** place a wrapped autowrap label beside a foreign EXPAND_FILL sibling (the 1 px collapse class).
- **Don't** update UI per frame; mutate only inside batched flushes and discrete signals.
- **Don't** hand-edit `assets/theme/signage_theme.tres` — regenerate it via `scripts/theme/generate_theme.gd` after changing `SignageTheme`/`SignageTokens`.
- **Don't** invent untracked colors in scenes or icons; all colors resolve through `SignageTokens` (the one-off `#D9CBA8` paper hairline and `#C22F28` danger hover live in the theme builder).

## As-Built Addendum — Run 2: Personnel, Orientation, Icon Grammar (2026-09-17)

Scan-and-confirm against the shipped build (T17/T18/T19/T20, closed by T21 acceptance). The contract above is unchanged and remains binding; this section records what run 2 shipped on top of it, in the same spirit as the recorded departures in Overview. Where a number above is superseded, it is named here.

### Personnel — the eighth department (D-08)

- The plate wall carries an **eighth plate: PERSONNEL · 8** (hotkey 8, row + keypad). This supersedes the Layout section's "seven department plates at 340×56 with 10 px separation": plates re-fit to 50 px height / 6 px separation so the 8-plate wall never scrolls at 1280×720 (a scrollable wall broke Godot's arrow-neighbor focus walk — the fix is structural, not cosmetic). Designation digits 1–8 ride the plate text as live accelerators.
- The Personnel docket posts the **POSTING BOARD**: one row per posting (1 + deputies, five at full strength). **ASSIGNED** rows = filled `deputy_badge` + skill icon + "POSTING N · ASSIGNED" + skill — activity — rate serial on energized ground; **AVAILABLE** rows = the `deputy_badge_outline` sibling + "YOUR OWN TWO HANDS" / "DEPUTY DESK VACANT" on bone enamel. The badge's fill IS the state — never color alone. A wallet plate (Depot idiom) and a stamped staffing log complete the docket.
- The purchase line: **DEPUTIZE RESIDENT · N CROWNS** (energized button, `btn_deputize` verb glyph beside the word, crowns mark beside the price; ladder 250 / 2,000 / 9,500 / 25,000 in `data/staffing.json`). It retires into a **FULL ESTABLISHMENT** completion line at 4 deputies. Buying without funds refuses in the Depot's voice ("INSUFFICIENT CROWNS"); the button stays enabled so the refusal is reachable and voiced.
- **Refusal, never preemption.** Starting any activity or engaging the patrol with no free posting posts the shared directive plate — head **POSTING REFUSED**, serial "ALL DEPUTIES ARE ASSIGNED. CEASE A POSTING, OR DEPUTIZE ANOTHER RESIDENT AT THE PERSONNEL PLATE. EITHER REMEDY IS CHEERFULLY SUPPORTED." — truth-gated on `free_postings() == 0` so it withdraws the moment a posting frees. The patrol occupies a posting like any skill (coordinator decision, rationale in the design-brief addendum).
- **v1 → v2 saves:** over-subscribed records (run-1 saves running more skills than the establishment holds) keep the most-recently-started posting; the losers park in `staffing.suspended` with full slot state and a **POSTINGS SUSPENDED — PERSONNEL SHORTAGE** notice rides the MAIL CALL (posted even at a zero offline gap), with a standing shortage plate until re-posted. Nothing is silently dropped.

### Orientation — ORIENTATION FORM O-1

- The tutorial is a **posted paper notice on the concourse, never a modal**: "POSTED AT INTAKE · D.O.C.S. FORM O-1", seven stencil rows with the naming-bible titles (WORK A POSTED SHIFT · EARN A CLEARANCE · FILE A CROWNS CLAIM · PROCESS A PRODUCT · PROVISION THE PATROL · CLEAR A NUISANCE · DEPUTIZE A RESIDENT).
- Row states are shapes, never color: empty drawn box (future) / `orient_arrow` aimed at the plate wall (current) / red `stamp_check` (done, title dims to the registered navy-dim-on-paper pair). Rows are keyboard-focusable buttons; pressing a row opens its department (wayfinding).
- First run opens expanded with step 1 cued and the **orient_arrow plate cue beside the destination plate** — this replaces the run-1 START HERE chalk, which is retired with run 2 (the walking cue subsumes the one-shot chalk). The cue walks plate-to-plate as steps stamp and retires with the tutorial. Cue targets are engine-owned (PROVISION THE PATROL points at Cooking — the earliest reachable qualifying path).
- Lifecycle: expanded at 0 stamps; the FOLD control posts at ≥ 5; the seventh stamp swaps the checklist for the record — **DULY ORIENTED · FORM O-1** + "ORIENTATION STIPEND — 150 CROWNS · THANK YOU FOR YOUR PROMPT COMPLIANCE." — holds a restrained 2.6 s beat, then settles into a permanent slip with an OPEN control (posted records never vanish). The stipend posts at the seventh stamp, i.e. immediately after the first deputize (T20 ruling, recorded in balance-notes §5.2).
- Low-text is a pinned budget: ≤ 40 words in every state (measured 32 fresh / 18 completed record / 5 slip). Placement: the expanded form posts over the intake notice slot at the header's right margin — a measured 9.3 % occlusion of the docket's flavor header only, folds at ≥ 5 and auto-slips at completion (papers-taped-to-steel is the world's own idiom).

### Icon grammar — as shipped (54 SVGs)

- Supersedes the Components count of 41: the set is now **54 original SVGs** — the run-1 set plus the 12 grammar glyphs (five navy stat instruments, the `clearance_step` staircase, the FILLED `deputy_badge`, `orient_arrow`, `stamp_check`, three amber verb glyphs `btn_engage`/`btn_withdraw`/`btn_deputize`) and the T17 `deputy_badge_outline` state sibling. Every grammar glyph is consumed by shipped UI (the reserved list emptied as T17/T18 landed their consumers).
- The contracted semantic rules hold as shipped: a stat glyph names exactly its own stat, inline before the mono number, wherever that stat posts; the staircase — never a padlock — marks every gated card beside the required grade; the badge fill is the ASSIGNED/AVAILABLE state pair; the arrow exists only while orientation is incomplete; stamps are red on paper (PaperStamp idiom); a button glyph echoes its verb and never replaces the word.
- The crowns mark sits beside every price: all Depot stock and disposal lines, the DEPUTIZE RESIDENT price, the O-1 stipend line, and both wallet plates (the T21 acceptance suite sweeps these exhaustively).
- One recorded note (T19 verifier): the amber verb/cue glyphs draw accent strokes at width 8–9 — the addendum's width clause binds navy interior strokes (4–7 set-wide), and the accent sits within the letter of the contract.

## As-Built Addendum — Run 3: Dossiers, Depth, Second Zone (2026-09-17)

Scan-and-confirm against the shipped build (T22–T27, closed by T28 acceptance). The contract and the run-2 addendum are unchanged and remain binding; this section records what run 3 shipped on top of them. Where a number above is superseded, it is named here.

### DossierRegister — the DEPARTMENTAL DOSSIER (Form R-1) component

- Each of the five skill dockets carries a **DossierRegister section** (`PaperNotice` idiom): a titled posted-paper register — RECLAMATION / GROUNDSKEEPING / FABRICATION / MESS / EXTERIOR DOSSIER — under the serial "D.O.C.S. FORM R-1". It is a section of the docket, never a ninth plate and never an overlay; the plate wall, bulkhead transitions, and the R1 geometry pins are untouched.
- **Fold discipline (the documented T26 choice, generalizing the O-1 slip):** 23 rows cannot fit a 720p docket beside the working regions, and a dossier is a RECORD, not a tutorial — so the register **mounts folded** to its summary line (title + serial + "N/23 STAMPED", ~10 words) with an OPEN/FOLD toggle. Unlike the O-1 form (which meets the resident expanded because the tutorial IS the priority), the docket's working regions stay first. A completed register folds to "ALL 23 STAMPED · FORM R-1" — the folded slip IS the stamp. Completion also expands the register once for the win moment; stamped rows stay stamped through every fold.
- **Row idiom** (Addendum 2): the O-1 row at scale — empty drawn checkbox → red `stamp_check` glyph when stamped; objective line in the stencil plate idiom (≤ 6 words, verb-first); mono progress readout "12/40" from engine counters; reward line "MERIT PAY · N CROWNS" and/or "COMMENDATION · N XP" with the crowns mark. Stamped rows dim to the registered navy-dim-on-paper pair and keep their stamps — the glyph is the state, never color alone; unstamped rows carry no state word.
- **Rewards post themselves.** There is no claim button anywhere in the register; row presses are pinned inert. The standing footer says so once per register: "MERIT PAY POSTS ITSELF. NO CLAIM IS REQUIRED. NONE HAS EVER BEEN." Auto-grant notices ride the existing stamp idiom — a docket log stamp plus a console serial flash, both "FORM R-1 STAMPED · N CROWNS POSTED" shaped — and a completed dossier posts the ALL 23 STAMPED plate with its "DOSSIER DULY STAMPED…" serial.
- **Update discipline:** rows build at FIRST EXPANSION (5 dockets × 23 rows is a one-time frame that never rides the boot) and restyle only through guarded no-change setters on the 4 Hz batched regions plus the two immediate discrete signals; the register renders only what the mounted docket hands it (it never infers progress). One engine-side note: `dossier_completed` is arm-guarded to emit exactly once even under re-entrant reward cascades (a T26 fix, pinned in test_objectives).

### Zone tabs — the Patrol docket's second board (Addendum 2's recorded direction)

- The Wasteland Patrol docket now posts a **radio tab pair above the fauna board**: ">> THE SUNNY EXCLUSION ZONE" / "THE GIFT COURT". The `>>` prefix is the active-zone cue (non-color); the zone serial swaps per board ("DESIGNATED OUTDOOR AMENITY AREA" vs "GIFT COURT — DESIGNATED RETAIL AMENITY AREA"); exactly one zone's fauna (5 Sunny / 6 Gift Court cards) posts at a time. Tabs are focusable, arrow-wired left/right, and ride the tab chain.
- Zone certificates stay zone-scoped: the Sunny Z-9 certificate mounts on the persisted `zone_clear` flag, the Gift Court's ("POSTED — SECTOR G · D.O.C.S. FORM Z-9") on the `zone:gift_court` lifetime counter — engine truth, repeat-kill safe, one zone's certificate at a time.

### Cross-lane fixes that shipped with T26

- **The O-1 slip fix:** the run-2 orientation slip's FOLD control did not actually hide its rows (a latent T18 defect — the word-count ceiling could not catch it); T26's one-line fix is pinned by the a11y probe's pre-snap StepRows-hidden check. The slip now folds for real.
- The dossier completion arm guard (above) was the other cross-lane fix, found by the register's own completion path.

### Content scale, as shipped

- **Icon set: 96 original SVGs** (supersedes the run-2 count of 54 — T24's new materials, fauna, activities, and gear glyphs join the set; ASSETS.md rows match 96 ↔ 96). The grammar contract is unchanged and set-wide (viewBox 128, tile rx 14, navy-8 borders, token-only hexes; navy interior strokes 4–9 with the T19 amber-accent note the lone exception).
- **Gear T1–T4 never on plates:** the four-tier equipment ladder (T1 shiv/vest → T2 whip/carapace → T3 filibuster-class → T4 veto/cloture/mantle/aegis) renders as Manifest serials, equip rungs, and stat bonuses — tier names stay off the docket plates (the Addendum 2 note; clearance numbers remain the only progression vocabulary on plates).
- Roughly 2× the run-1 content: 9 activity tiers per gathering skill (from 4), 20 recipes per processing skill (from 7/4), 47 items (from 21), 11 monsters across 2 zones (from 5 across 1), 12 equipment pieces (from 4), and the 115-line dossier set (23 per skill).
