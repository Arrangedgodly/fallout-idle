class_name SignageFmt
extends RefCounted
## SignageFmt — T10a number formatting for docket copy.
##
## Honest-math principle: every value prints EXACTLY (integers, no rounding,
## no hidden multipliers); gameplay numbers render in mono digits via the
## MonoValue/PlateSerialNavy/ItemList theme types. Comma grouping keeps
## 9,999,999-range currency readable until T14's big-number pass owns
## suffixes (this helper is the single swap point).


## 1234567 -> "1,234,567" (exact int, grouped).
static func num(value: int) -> String:
	var negative := value < 0
	var n := absi(value)
	var parts: Array[String] = []
	while n >= 1000:
		parts.push_front("%03d" % (n % 1000))
		n /= 1000
	parts.push_front(str(n))
	return ("-" if negative else "") + ",".join(parts)


## Interval ms -> seconds with one decimal ("3.0", "7.5") for rate lines.
static func seconds(ms: int) -> String:
	return "%.1f" % (float(ms) / 1000.0)


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
## weights stay visible in content and the manifest of record).
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
