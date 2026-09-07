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


# ---------- Hitstop ----------
# Freezes gameplay motion for `duration` real seconds (Engine.time_scale
# set to 0, so physics/animation don't advance) without pausing _process
# callbacks themselves — input polling and flag-setting code (like the
# player's parry) keep running every real frame, they just see delta ~= 0.
# That's what lets a parry pressed *during* a hitstop still register.
# Counter-based so overlapping calls (e.g. two hits landing back to back)
# don't have the shorter one prematurely un-freeze the longer one.
var _hitstop_count := 0

func hitstop(duration: float) -> void:
	if duration <= 0.0:
		return
	_hitstop_count += 1
	Engine.time_scale = 0.0
	var timer := get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	_hitstop_count = maxi(_hitstop_count - 1, 0)
	if _hitstop_count == 0:
		Engine.time_scale = 1.0
