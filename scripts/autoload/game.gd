extends Node
## Game — root autoload (T1 placeholder).
##
## Autoload registry plan; each entry lands with its owning task, never before:
##   Game        (T1) — this node; stays first so later singletons can reach it.
##   ContentDB   (T2) — LIVE: validates res://data/*.json per R1 and hydrates
##               typed records (scripts/content/); boot fails on any error.
##   SaveManager (T3) — atomic versioned saves under user://.
##   TickManager (T6) — budgeted ~10 Hz simulation loop.
##
## Tests (R2): GUT 9.7.1 under res://tests, wired by T12. Until then the plain
## --script probe tests/probe_content.gd covers content validation headless.
