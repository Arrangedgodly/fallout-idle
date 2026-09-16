class_name SignageFmt
extends RefCounted
## SignageFmt — T10a number formatting for docket copy, hardened by T14.
##
## Honest-math principle: every value prints EXACTLY (integers, no rounding,
## no hidden multipliers); gameplay numbers render in mono digits via the
## MonoValue/PlateSerialNavy/ItemList theme types. The T14 big-number pass
## (this file is the single swap point) adds the one sanctioned departure:
## at 10^15 and above, num() switches to int-math suffix form ("2.470Q")
## because exact grouping of a quadrillion is 19+ characters no gauge can
## carry. The suffix form TRUNCATES (never rounds up): a displayed value
## can understate, never overstate, the true integer. Below 10^15 — every
## reachable content number, and the 999,999,999-Crown class — grouping
## stays exact. All paths are pure int arithmetic (no float coercion, so
## no 0.30000000004-class artifacts can appear in mono digits).


const _SUFFIX_AT := 1_000_000_000_000_000  ## 10^15 — quadrillion scale
const _SUFFIX_BIG_AT := 1_000_000_000_000_000_000  ## 10^18 — quintillion scale


## 1234567 -> "1,234,567" (exact int, grouped). At |value| >= 10^15 the
## T14 suffix form takes over: 2_470_123_456_789_012 -> "2.470Q",
## 9_223_372_036_854_775_807 -> "9.223QI" (truncated, never rounded up).
## Handles the full int64 range including the absi() overflow edge at
## INT64_MIN (threshold tests run on the signed value, never on absi()).
static func num(value: int) -> String:
	if value >= _SUFFIX_BIG_AT or value <= -_SUFFIX_BIG_AT:
		return _suffix(value, _SUFFIX_BIG_AT, "QI")
	if value >= _SUFFIX_AT or value <= -_SUFFIX_AT:
		return _suffix(value, _SUFFIX_AT, "Q")
	var negative := value < 0
	var n := absi(value)
	var parts: Array[String] = []
	while n >= 1000:
		parts.push_front("%03d" % (n % 1000))
		n /= 1000
	parts.push_front(str(n))
	return ("-" if negative else "") + ",".join(parts)


## Suffix form, pure int math. `unit` is 10^15 (Q) or 10^18 (QI); the
## mantissa is value/unit (1..999 by threshold construction) and the three
## displayed decimals are (value % unit) / (unit / 1000), TRUNCATED toward
## zero — an understatement, never an overstatement.
static func _suffix(value: int, unit: int, suffix: String) -> String:
	var mant := value / unit  # int division truncates toward zero
	var frac: int = value % unit / (unit / 1000)
	var negative := value < 0
	return "%s%d.%03d%s" % [
		"-" if negative else "", mant if not negative else -mant,
		frac if not negative else -frac, suffix]


## Interval ms -> seconds with one decimal ("3.0", "7.5") for rate lines.
## Int math (T14: no float division — exact for every int64 input).
static func seconds(ms: int) -> String:
	if ms == -9223372036854775807 - 1:  # absi() would overflow
		return "-9223372036854775.8"
	var negative := ms < 0
	var n := absi(ms)
	return "%s%d.%d" % ["-" if negative else "", n / 1000, (n % 1000) / 100]


## Elapsed ms -> "2H 14M" / "14M 05S" / "45S" (leading units omitted, always
## two units unless under a minute). Used by MAIL CALL and status plates.
static func duration(ms: int) -> String:
	var total := maxi(ms, 0) / 1000
	var h := total / 3600
	var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%dH %02dM" % [h, m]
	if m > 0:
		return "%dM %02dS" % [m, s]
	return "%dS" % s


## Drop-rate fraction as an honest percent: weight/total, one decimal only
## when the exact value needs it ("70", "6.3"). Per-mille first, then
## round-half-away to the displayed tenth (display rounding only — the raw
## weights stay visible in content and the manifest of record). total <= 0
## guards the division (T14 zero sweep).
static func pct(weight: int, total: int) -> String:
	if total <= 0:
		return "0"
	var bp := roundi(float(weight) * 1000.0 / float(total))
	if bp % 10 == 0:
		return str(bp / 10)
	return "%.1f" % (float(bp) / 10.0)


## Quantity bounds -> "×1-2" / "×3" (Latin-1 × and hyphen only: mono-safe).
static func qty(p_min: int, p_max: int) -> String:
	if p_max > p_min:
		return "×%d-%d" % [p_min, p_max]
	return "×%d" % p_min


## Count with sign for stamped delta lines: "+12" / "-3".
static func delta(value: int) -> String:
	return ("+" if value > 0 else "") + str(value)
