class_name DeputyDef
extends RefCounted
## DeputyDef — one run-2 staffing purchase line (T17 content schema).
##
## The personnel ladder: buying the record at index `n` (0-based, in file
## order) raises `staffing.deputies` from n to n+1, opening posting n+2 (the
## resident's own hands staff posting 1). Prices are balance data, never
## hardcoded in scripts (T20 owns the tuning); the loader pins the ladder at
## exactly MAX_DEPUTIES (4) non-decreasing prices so 1 + 4 = 5 postings = all
## five skills concurrent (town-hall Scope Amendment 1).
## Field contract: docs/content-schema.md.

var id: String  ## Descriptive machine id ("second_deputy"...).
var price: int  ## Crowns charged by the DEPUTIZE RESIDENT button at this rung (>= 1).


static func hydrate(d: Dictionary) -> DeputyDef:
	var def := DeputyDef.new()
	def.id = String(d["id"])
	def.price = int(d["price"])
	return def
