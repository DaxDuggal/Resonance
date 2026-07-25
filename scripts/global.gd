extends Node

var player
var is_paused: bool = false
var last_safe_position: Vector2 = Vector2.ZERO
var current_dash_type: int = 0  # Persists across scene reloads (see Player.DashType)

# Health is stored in player, but we can reference it here for convenience
func get_current_health() -> int:
	if player:
		return player.current_health
	return 0

func get_max_health() -> int:
	if player:
		return player.max_health
	return 3
