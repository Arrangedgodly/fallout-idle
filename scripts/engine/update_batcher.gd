class_name UpdateBatcher
extends RefCounted
## UpdateBatcher — T6 dirty-flag aggregation keeping UI signals off the hot path.
##
## Engine code calls mark(reason) whenever a state region changes; a flush
## collapses every accumulated reason into ONE `flushed(changes)` emission.
## Flushes are gated on the sim clock (min_interval_ms = 250 → at most ~4 Hz
## while continuously dirty). Discrete events (level-up, activity stopped,
## mail call) bypass this batcher entirely — they are emitted immediately by
## ActivityEngine/TickManager (see the UI UPDATE CONTRACT in
## scripts/autoload/tick_manager.gd).
##
## emission_count exists so tests (and T13's perf budget) can assert the 4 Hz
## ceiling without wiring extra probes.

signal flushed(changes: Dictionary)

const DEFAULT_MIN_INTERVAL_MS := 250  ## 4 Hz bulk ceiling (T6 contract).

var min_interval_ms: int = DEFAULT_MIN_INTERVAL_MS
var emission_count: int = 0  ## lifetime flush count (perf assertions read this)

var _dirty: Dictionary = {}  ## reason -> true
var _last_flush_sim_ms: int = -1


func mark(reason: String) -> void:
	_dirty[reason] = true


func is_dirty() -> bool:
	return not _dirty.is_empty()


## Flush only if dirty AND the sim-clock gate has opened. Returns true when a
## flush happened. Call once per sim tick (cheap no-op when clean/gated).
func flush_due(sim_time_ms: int) -> bool:
	if _dirty.is_empty():
		return false
	if _last_flush_sim_ms >= 0 and sim_time_ms - _last_flush_sim_ms < min_interval_ms:
		return false
	return force_flush(sim_time_ms)


## Flush now (user-initiated actions call this so the UI reacts to the click
## itself, not up to 250 ms later). Returns true when there was anything dirty.
func force_flush(sim_time_ms: int) -> bool:
	if _dirty.is_empty():
		return false
	var changes := _dirty
	_dirty = {}
	_last_flush_sim_ms = sim_time_ms
	emission_count += 1
	flushed.emit(changes)
	return true
