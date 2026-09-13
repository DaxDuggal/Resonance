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

# ---------- Frame-based durations ----------
# Lets a timing value be authored as "N frames" (at the project's fixed
# physics tick rate) instead of hand-computing N/60 (etc.) inline wherever
# it's used. Pair with an @export var some_thing_frames: int on the script
# that needs it, and call Global.frames_to_seconds(some_thing_frames) at
# the point of use (NOT as the export's default value expression — that
# can get evaluated at edit-time before autoloads are guaranteed ready).
# Not `static` — Global is accessed as the autoload singleton instance, and
# Godot warns (STATIC_CALLED_ON_INSTANCE) about calling a static func that
# way.
func frames_to_seconds(frames: float) -> float:
	return frames / float(Engine.physics_ticks_per_second)


func hitstop(duration: float) -> void:
	# A NaN/Inf duration would otherwise sail past "duration <= 0.0" (NaN
	# comparisons are always false) and hand create_timer a value that can
	# never count down to zero — permanently stuck at time_scale = 0, which
	# then cascades into every other physics calculation in the game
	# (divisions by a frozen zero-ish delta, etc.). Clamp defensively.
	if not is_finite(duration) or duration <= 0.0:
		return
	duration = minf(duration, 2.0)  # sanity cap — no legitimate hitstop is this long

	_hitstop_count += 1
	# TEMP DEBUG (remove once the mutual-hit freeze is nailed down): if two
	# hits land the same frame, this should print two "start"s back to back
	# with count 1 then 2, and two "end"s bringing it back to 0. If count
	# ever stops decrementing back to 0, or time_scale gets set somewhere
	# else in between (dead()/respawn() in player.gd both write it directly,
	# outside this counter), that's the race.
	print("[hitstop] start count=%d duration=%.3f time_scale=%.2f->0.0" % [_hitstop_count, duration, Engine.time_scale])
	Engine.time_scale = 0.0
	var timer := get_tree().create_timer(duration, true, false, true)
	await timer.timeout
	_hitstop_count = maxi(_hitstop_count - 1, 0)
	print("[hitstop] end count=%d time_scale=%.2f" % [_hitstop_count, Engine.time_scale])
	if _hitstop_count == 0:
		Engine.time_scale = 1.0
		print("[hitstop] time_scale->1.0")


# Force-clears hitstop state and restores normal time flow — call this
# whenever the scene is about to be torn down/reloaded (see
# pauseMenu.gd's restart handler) so a hitstop that was mid-flight at that
# moment can't leave Engine.time_scale stuck at 0 for the next scene.
func reset_hitstop() -> void:
	_hitstop_count = 0
	Engine.time_scale = 1.0
