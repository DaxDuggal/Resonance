extends Node

# Tracks per-level object state (currently: enemy deaths; designed to extend
# to chests, switches, breakable walls, etc. later) that must survive a
# scene reload — which happens on every player death and just re-instances
# the whole level fresh from its .tscn, wiping anything not tracked here.
#
# Two separate buckets, because "stays resolved forever" and "resets when
# you rest" are genuinely different lifetimes, not just two categories of
# the same thing:
#   - resettable: cleared by reset_resettable(), called on checkpoint
#     activation (Hollow Knight-style: dying alone doesn't bring enemies
#     back, but resting at a checkpoint does). Use for enemy deaths.
#   - permanent: never auto-cleared. Use for one-time pickups, opened
#     chests, permanently unlocked doors, etc. — things that should stay
#     resolved even across a checkpoint rest.
#
# IDs are arbitrary strings. Callers should use a stable, globally-unique
# ID — see Enemy._get_world_state_id() for the auto-derived
# scene-path + node-path pattern any future object can reuse as-is.

var resettable: Dictionary = {}
var permanent: Dictionary = {}


func is_resolved(id: String, is_permanent: bool = false) -> bool:
	var bucket := permanent if is_permanent else resettable
	return bucket.get(id, false)


func set_resolved(id: String, is_permanent: bool = false, value: bool = true) -> void:
	var bucket := permanent if is_permanent else resettable
	if value:
		bucket[id] = true
	else:
		bucket.erase(id)


func reset_resettable() -> void:
	resettable.clear()


func reset_all() -> void:
	resettable.clear()
	permanent.clear()
