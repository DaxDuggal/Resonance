extends Node

var player: Player
var is_paused: bool = false
var last_safe_position: Vector2 = Vector2.ZERO

# Checkpoint state (separate from last_safe_position, which is for hazards).
var last_checkpoint_position: Vector2 = Vector2.ZERO
var has_checkpoint: bool = false
var last_checkpoint_scene: String = "res://scenes/game.tscn"

var saved_current_health: int = -1  # -1 = no load in progress
var did_just_die: bool = false  # consumed by Player._ready()

# ---------- Save-file progress ----------
var currency: int = 0
var xp: int = 0
var death_count: int = 0

func get_current_health() -> int:
	if player:
		return player.current_health
	return 0

func get_max_health() -> int:
	if player:
		return player.max_health
	return 3
