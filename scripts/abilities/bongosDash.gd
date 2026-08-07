# Extends BasicDash with specialized jump interrupt: bounces on pure vertical dashes,
# wall bounces on up-diagonals, wavedashes on down-diagonals.
extends BasicDash
class_name BongosDash

func _init() -> void:
	allows_jump_interrupt = true

# Interrupt parameters for horizontal bounce
@export var horizontal_bounce_force: float = 320.0
@export var horizontal_interrupt_multiplier: float = 0.6
@export var horizontal_interrupt_clamp_speed: float = 260.0
@export var horizontal_reverse_speed: float = 220.0

# Vertical bounce parameters (down-dash is stronger)
@export var vertical_bounce_force_down_dash: float = 700.0
@export var vertical_bounce_force_up_dash: float = 420.0
@export var axis_threshold: float = 0.7

# Burst clamp settings for limiting bounce height
@export var burst_duration: float = 0.04
@export var clamp_upward_after_burst: float = 370.0
@export var clamp_downward_after_burst: float = 220.0

# Prevent jump height cut during bounce
@export var disable_jump_cut_time: float = 0.2

# How long after a down dash hits the floor the player still has to press jump
# for the big bounce, before the dash just gives up and ends normally.
# Needed because the dash's own duration (from BasicDash) is too short (0.18s)
# for a human to react to landing and press jump within it.
@export var ground_bounce_grace_window: float = 0.15

# -1 while not resting on the floor from a down dash. >= 0 while in the grace
# window counting down after landing.
var _ground_bounce_timer: float = -1.0

# True if the dash is pointed mostly straight down (or straight up), not diagonal.
func _is_vertical_dash() -> bool:
	var dir := dash_direction.normalized()
	return abs(dir.y) >= axis_threshold and abs(dir.x) <= (1.0 - axis_threshold)

func _is_downward_dash() -> bool:
	return _is_vertical_dash() and dash_direction.y > 0.0

func start_dash(player: Player, dir: Vector2) -> void:
	_ground_bounce_timer = -1.0
	super.start_dash(player, dir)

# While resting in the post-landing grace window, hold still instead of letting
# BasicDash's update_dash keep forcing full dash speed into the floor every
# frame (that's what caused the player to get stuck re-triggering the
# anti-tunneling raycast in player.gd and never actually registering as grounded).
func update_dash(player: Player, delta: float) -> void:
	if _ground_bounce_timer >= 0.0:
		player.velocity = Vector2.ZERO
		_ground_bounce_timer -= delta
		if _ground_bounce_timer <= 0.0:
			finish_dash(player)
		return
	super.update_dash(player, delta)

# Called when the dash collides with something (floor, wall, etc.), whether
# from the normal move_and_slide collision list or the anti-tunneling raycast
# pre-check in player.gd. For a down dash hitting the floor, stop and open the
# grace window instead of letting the dash keep pinning itself into the floor.
func handle_slide_collision(player: Player, collision) -> void:
	if not _is_downward_dash() or _ground_bounce_timer >= 0.0:
		return

	var normal: Vector2 = Vector2.ZERO
	if typeof(collision) == TYPE_DICTIONARY:
		normal = collision.get("normal", Vector2.ZERO)
	elif collision and collision.has_method("get_normal"):
		normal = collision.get_normal()

	# Only treat floor-like surfaces (normal pointing up) as a landing
	if normal.y < -0.5:
		_ground_bounce_timer = ground_bounce_grace_window
		player.velocity = Vector2.ZERO

# Down-dash → upward bounce. Fires the instant jump is pressed while the dash
# is still active — whether that's mid-air, mid-landing-grace-window, or
# already pressed against the floor. A pure vertical dash always skips the
# wavedash gate in player.gd, so this works regardless of grounded state.
# Clamped after a brief burst so the height is big but not unbounded.
func _apply_ground_bounce(player: Player) -> void:
	player.velocity.x = 0.0
	player.velocity.y = -vertical_bounce_force_down_dash
	player.jump_cut_disabled_timer = disable_jump_cut_time
	player.velocity_clamp_timer = burst_duration
	player.velocity_clamp_value = -clamp_upward_after_burst

func interrupt_with_jump(player: Player) -> void:
	# Cancel the dash and apply a bounce based on dash direction.
	cancel_dash(player)

	var dir: Vector2 = dash_direction.normalized()
	var absx: float = abs(dir.x)
	var absy: float = abs(dir.y)

	# Horizontal dash (mostly x)
	if absx >= axis_threshold and absy <= (1.0 - axis_threshold):
		var current_h: float = player.velocity.x
		var base_dir_sign: int = int(sign(current_h)) if current_h != 0.0 else int(sign(dir.x))
		var input_x: float = Input.get_axis("move_left", "move_right")
		if abs(input_x) > 0.1 and int(sign(input_x)) == -base_dir_sign:
			# Player holds opposite direction: reverse momentum
			player.velocity.x = -base_dir_sign * horizontal_reverse_speed
		else:
			# Reduce horizontal speed on interrupt
			var reduced_h: float = base_dir_sign * min(abs(current_h) * horizontal_interrupt_multiplier, horizontal_interrupt_clamp_speed)
			player.velocity.x = reduced_h
		player.velocity.y = player.jump_velocity
		return

	# Vertical dash (mostly y) — bounces with brief clamping to limit distance
	if absy >= axis_threshold and absx <= (1.0 - axis_threshold):
		if dir.y > 0.0:
			# Down dash → strong upward burst, then clamp (same as the automatic floor bounce)
			_apply_ground_bounce(player)
		else:
			# Up dash → weaker downward burst, then clamp
			player.velocity.x = 0.0
			player.velocity.y = vertical_bounce_force_up_dash
			player.velocity_clamp_timer = burst_duration
			player.velocity_clamp_value = clamp_downward_after_burst
		return

	# Up-diagonal dash → wall bounce (push away from wall, bounce upward)
	if dir.y < 0.0 and absx > 0.1 and absy > 0.1:
		var push_direction := -int(sign(dir.x))
		player.velocity.x = push_direction * player.wall_bounce_push_force
		player.velocity.y = player.wall_bounce_velocity

		player.jump_cut_disabled_timer = player.WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		player.wall_bounce_control_lock_timer = player.wall_bounce_control_lock_time

		player.jump_buffered = false
		player.state = player.PlayerState.WALL_BOUNCING
		player.coyote_timer = 0.0
		return

	# Down-diagonal dash → wavedash into the ground
	if dir.y > 0.0 and absx > 0.1 and absy > 0.1:
		var input_x_axis: float = Input.get_axis("move_left", "move_right")
		var wavedash_direction := input_x_axis if abs(input_x_axis) > 0.1 else dash_direction.x
		var wavedash_speed := dash_velocity.length() * player.wavedash_speed_mult

		player.velocity.x = wavedash_direction * wavedash_speed
		player.velocity.y = player.wavedash_jump_velocity

		player.coyote_timer = 0.0
		player.wavedash_window_timer = 0.0
		player.wavedash_buffer_timer = player.wavedash_buffer_time
		return

	# Fallback: normal jump
	player.velocity.y = player.jump_velocity
