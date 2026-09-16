class_name ZoneDef
extends RefCounted
## ZoneDef — one Wasteland Patrol zone record (T23 content schema).
##
## Zones become a first-class content domain in run 3: monsters.json's `zone`
## field gains a real cross-checked reference, and objectives.json
## `zone_clear` conditions reference these ids. The domain ships MINIMAL by
## design (id + display name) — the T23 set carries both run-3 zone ids
## (`dusty_flats` The Sunny Exclusion Zone + `gift_court` The Gift Court) so
## the reserved Gift Court id resolves from day one; T24 authors the Gift
## Court fauna (monsters referencing the zone) and any zone content beyond
## the display name. A zone with no monsters is NOT an orphan (the Gift Court
## deliberately ships fauna-less until T24 — no loader warning fires).
## Field contract: docs/content-schema.md → "zones.json".

var id: String  ## snake_case machine id ("dusty_flats", "gift_court").
var name: String  ## Display name ("The Sunny Exclusion Zone" — naming-bible §3).


static func hydrate(d: Dictionary) -> ZoneDef:
	var def := ZoneDef.new()
	def.id = String(d["id"])
	def.name = String(d["name"])
	return def
