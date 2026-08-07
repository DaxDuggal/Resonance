extends Node

var player
var is_paused: bool = false
var last_safe_position: Vector2 = Vector2.ZERO
var current_dash_type: int = 0  # Persists across scene reloads (see Player.DashType)

# Checkpoint state. Separate from last_safe_position (which is for hazard
# respawns and updates constantly) — this only changes when the player
# actually touches a checkpoint, and is what death reloads back to.
var last_checkpoint_position: Vector2 = Vector2.ZERO
var has_checkpoint: bool = false

# Scene the last checkpoint was activated in. Unused while there's a single
# scene, but SaveManager (and eventually death/respawn) will need it once
# more scenes exist — see checkpoint.gd's activate().
var last_checkpoint_scene: String = "res://scenes/game.tscn"

# One-time value consumed by Player._ready() right after a save is loaded.
# -1 means "no load in progress, use default max health."
var saved_current_health: int = -1

# ---------- Save-file progress (not yet implemented, placeholders) ----------
var currency: int = 0
var xp: int = 0
var death_count: int = 0

# Health is stored in player, but we can reference it here for convenience
func get_current_health() -> int:
	if player:
		return player.current_health
	return 0

func get_max_health() -> int:
	if player:
		return player.max_health
	return 3
