extends Node
## Game — root autoload (T1 placeholder).
##
## Autoload registry plan; each entry lands with its owning task, never before:
##   Game        (T1) — this node; stays first so later singletons can reach it.
##   ContentDB   (T2) — LIVE: validates res://data/*.json per R1 and hydrates
##               typed records (scripts/content/); boot fails on any error.
##   SaveStore   (T3) — LIVE: atomic versioned JSON saves under user:// with a
##               3-slot backup ring, corruption-notice states, 60 s autosave +
##               quit/window-close filing (scripts/autoload/save_store.gd).
##   UiTheme     (T8) — LIVE: signage Theme + font-scale setting
##               (scripts/theme/, assets/theme/signage_theme.tres).
##   TickManager (T6) — LIVE: budgeted 10 Hz sim loop + activity engine +
##               offline catch-up, and — since T7 — the combat engine
##               (CombatSession: tick auto-battle, gear, auto-eat, drops)
##               driven by the same funnel (scripts/engine/, UI UPDATE
##               CONTRACT in scripts/autoload/tick_manager.gd).
##
## Tests (R2): GUT 9.7.1 under res://tests, wired by T12. Until then the plain
## --script probe tests/probe_content.gd covers content validation headless.
