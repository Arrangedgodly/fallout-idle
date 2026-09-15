class_name SignageTokens
extends RefCounted
## T8 — The Shelter Signage System, color + material tokens.
##
## The palette is law from docs/ultron/design-brief.md (OWN-WORLD): bone-white
## enamel over rolled-steel ground, institutional navy as structural ink, and
## exactly two meaning-carrying signal colors — amber = active/energized,
## red = danger/cancel/locked. Every text-on-ground pair the theme registers
## is listed in CONTRAST_PAIRS with its WCAG class ("body" >= 4.5:1,
## "large" >= 3:1) and is re-verified at probe time by tests/probe_theme.gd,
## which recomputes the ratios from these constants (math must match
## docs/theme-contrast-table.md, the committed contrast table).
##
## Usage rules the table encodes:
##   - Red NEVER appears as text or border on rolled steel (1.15:1): danger
##     posts as a red enamel plate (bone text) or a red stamp on paper.
##   - Bone text NEVER appears on paper (1.05:1): paper takes navy ink.
##   - Amber as body-size text only on navy or steel-deep; on rolled steel
##     amber is reserved for large stencil caps and UI accents (3:1 class).

# --- ground + ink -----------------------------------------------------------
const BONE_ENAMEL := Color("#F2EDE3")        # plate ground / primary text on dark grounds
const ROLLED_STEEL := Color("#4E5560")       # the concourse ground
const STEEL_DEEP := Color("#3A404A")         # recesses: vents, gauge tracks, inputs
const STEEL_HI := Color("#6B7482")           # bevel highlight (non-text)
const STEEL_LO := Color("#2E333C")           # bevel shadow / bore (non-text)
const INSTITUTIONAL_NAVY := Color("#20334F") # structural ink / navy plate ground
const SIGNAL_AMBER := Color("#FFB000")       # active / energized
const SAFETY_RED := Color("#B3261E")         # danger / cancel / locked
const BONE_DIM := Color("#D0CEC9")           # secondary text (bone tinted toward steel)
const NAVY_DIM := Color("#546480")           # dimmed navy ink (disabled items on bone/paper)
const PAPER_NOTICE := Color("#F2E7CF")       # posted paper notices
const NAVY_HI := Color("#33507A")            # navy plate bevel highlight (non-text)

# --- registered text-on-ground pairs (fg, bg, class, usage) ------------------
# class: "body" must pass 4.5:1, "large" (>=24px regular / >=18.66px bold text,
# plus UI component boundaries) must pass 3:1 per WCAG 2.x AA.
const CONTRAST_PAIRS := [
	["primary text on rolled steel", BONE_ENAMEL, ROLLED_STEEL, "body"],
	["secondary text on rolled steel", BONE_DIM, ROLLED_STEEL, "body"],
	["primary text in steel recesses", BONE_ENAMEL, STEEL_DEEP, "body"],
	["secondary text in steel recesses", BONE_DIM, STEEL_DEEP, "body"],
	["bone plate text on navy", BONE_ENAMEL, INSTITUTIONAL_NAVY, "body"],
	["stencil ink on bone enamel", INSTITUTIONAL_NAVY, BONE_ENAMEL, "body"],
	["energized text on navy", SIGNAL_AMBER, INSTITUTIONAL_NAVY, "body"],
	["energized text in steel recesses", SIGNAL_AMBER, STEEL_DEEP, "body"],
	["large stencil caps + UI accents on steel", SIGNAL_AMBER, ROLLED_STEEL, "large"],
	["danger plate text", BONE_ENAMEL, SAFETY_RED, "body"],
	["red ink on bone enamel", SAFETY_RED, BONE_ENAMEL, "body"],
	["posted notice text", INSTITUTIONAL_NAVY, PAPER_NOTICE, "body"],
	["rubber stamp on paper", SAFETY_RED, PAPER_NOTICE, "body"],
	["disabled ink on paper notices", NAVY_DIM, PAPER_NOTICE, "body"],
]

# --- forbidden combinations (fail AA; rules above) ---------------------------
const FORBIDDEN_PAIRS := [
	["bone text on paper (paper takes navy ink only)", BONE_ENAMEL, PAPER_NOTICE],
	["red text on rolled steel (danger posts as plate/stamp)", SAFETY_RED, ROLLED_STEEL],
	["red text on navy (danger never as text there)", SAFETY_RED, INSTITUTIONAL_NAVY],
]

# --- WCAG 2.x relative luminance + contrast ratio ---------------------------
static func relative_luminance(c: Color) -> float:
	var r := _channel(c.r)
	var g := _channel(c.g)
	var b := _channel(c.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b

static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var hi := maxf(la, lb)
	var lo := minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)

static func threshold_for(kind: String) -> float:
	return 4.5 if kind == "body" else 3.0

static func _channel(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
