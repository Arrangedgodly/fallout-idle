# Theme Contrast Table — The Shelter Signage System (T8)

Committed record of the WCAG 2.x AA verification for every text-on-ground pair
the signage theme registers. Source of truth for the values:
`scripts/theme/signage_tokens.gd` (`CONTRAST_PAIRS` / `FORBIDDEN_PAIRS`).
The math is recomputed independently at validation time by
`tests/probe_theme.gd`, which re-derives relative luminance and ratios from
the token constants and fails the build if any pair drifts below its
threshold. Palette law: docs/ultron/design-brief.md (OWN-WORLD).

Relative luminance: linearized sRGB (c/12.92 or ((c+0.055)/1.055)^2.4),
L = 0.2126R + 0.7152G + 0.0722B; ratio = (L1+0.05)/(L2+0.05).
AA: body text >= 4.5:1; large text (>= 24 px regular / >= 18.66 px bold) and
UI component boundaries >= 3:1.

## Registered pairs — all pass

| Pair (usage) | Foreground | Ground | L(fg) | L(bg) | Ratio | AA class | Verdict |
|---|---|---|---|---|---|---|---|
| primary text on rolled steel | #F2EDE3 | #4E5560 | 0.8499 | 0.0896 | 6.45:1 | ≥4.5:1 | PASS |
| secondary text on rolled steel | #D0CEC9 | #4E5560 | 0.6177 | 0.0896 | 4.78:1 | ≥4.5:1 | PASS |
| primary text in steel recesses | #F2EDE3 | #3A404A | 0.8499 | 0.0506 | 8.94:1 | ≥4.5:1 | PASS |
| secondary text in steel recesses | #D0CEC9 | #3A404A | 0.6177 | 0.0506 | 6.64:1 | ≥4.5:1 | PASS |
| bone plate text on navy | #F2EDE3 | #20334F | 0.8499 | 0.0324 | 10.92:1 | ≥4.5:1 | PASS |
| stencil ink on bone enamel | #20334F | #F2EDE3 | 0.0324 | 0.8499 | 10.92:1 | ≥4.5:1 | PASS |
| energized text on navy | #FFB000 | #20334F | 0.5231 | 0.0324 | 6.96:1 | ≥4.5:1 | PASS |
| energized text in steel recesses | #FFB000 | #3A404A | 0.5231 | 0.0506 | 5.70:1 | ≥4.5:1 | PASS |
| large stencil caps + UI accents on steel | #FFB000 | #4E5560 | 0.5231 | 0.0896 | 4.10:1 | ≥3.0:1 | PASS |
| danger plate text | #F2EDE3 | #B3261E | 0.8499 | 0.1106 | 5.60:1 | ≥4.5:1 | PASS |
| red ink on bone enamel | #B3261E | #F2EDE3 | 0.1106 | 0.8499 | 5.60:1 | ≥4.5:1 | PASS |
| posted notice text | #20334F | #F2E7CF | 0.0324 | 0.8053 | 10.38:1 | ≥4.5:1 | PASS |
| rubber stamp on paper | #B3261E | #F2E7CF | 0.1106 | 0.8053 | 5.32:1 | ≥4.5:1 | PASS |
| disabled ink on paper notices | #546480 | #F2E7CF | 0.1256 | 0.8053 | 4.87:1 | ≥4.5:1 | PASS |

Token names (scripts/theme/signage_tokens.gd): #F2EDE3 bone enamel ·
#4E5560 rolled steel · #3A404A steel deep · #20334F institutional navy ·
#FFB000 signal amber · #B3261E safety red · #D0CEC9 bone dim (secondary) ·
#546480 navy dim (disabled ink) · #F2E7CF paper notice.

## Forbidden pairs — must stay unregistered

| Combo | Foreground | Ground | Ratio | Rule |
|---|---|---|---|---|
| bone text on paper | #F2EDE3 | #F2E7CF | 1.05:1 | paper takes navy ink only |
| red text on rolled steel | #B3261E | #4E5560 | 1.15:1 | danger posts as a red plate (bone text) or a red stamp on paper |
| red text on navy | #B3261E | #20334F | 1.95:1 | red never appears as text on navy |

Design decisions encoded above:

- **Amber body-size text only on navy or steel-deep** (6.96 / 5.70). On rolled
  steel amber is the 3:1 class: large stencil caps, borders, focus rings —
  the single interaction signal, one meaning.
- **Secondary text is tinted from the ground's hue** (bone dimmed toward
  steel-blue), never neutral gray, per the craft floor.
- **Focus ring is amber** — >= 3:1 against every ground it can sit on
  (4.10 vs steel, 6.96 vs navy, 5.70 vs steel-deep).

Re-verify after any token change:
`"$GODOT" --headless --path . -s res://tests/probe_theme.gd`
(the probe prints the recomputed table; the committed numbers above must match).
