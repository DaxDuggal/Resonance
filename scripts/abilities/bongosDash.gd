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
@export var clamp_upward_after_burst: float = 320.0
@export var clamp_downward_after_burst: float = 220.0

# Prevent jump height cut during bounce
@export var disable_jump_cut_time: float = 0.2

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
		player.velocity.x = 0.0
		if dir.y > 0.0:
			# Down dash → strong upward burst, then clamp
			player.velocity.y = -vertical_bounce_force_down_dash
			player.jump_cut_disabled_timer = disable_jump_cut_time
			player.velocity_clamp_timer = burst_duration
			player.velocity_clamp_value = -clamp_upward_after_burst
		else:
			# Up dash → weaker downward burst, then clamp
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
