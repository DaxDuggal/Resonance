extends DashAbility
class_name JumpInterruptDash

@export var dash_speed: float = 350.0
@export var dash_duration: float = 0.2
@export var dash_end_speed: float = 180.0

@export var allows_jump_interrupt: bool = true

var timer: float = 0.0

func start_dash(player: Player, dir: Vector2) -> void:
	super.start_dash(player, dir)

	timer = dash_duration
	dash_velocity = dash_direction * dash_speed

	player.velocity = dash_velocity
	player.dash_available = false
	player.dash_buffer_timer = 0.0
	player.landing_lag_timer = 0.0

func update_dash(player: Player, delta: float) -> void:
	timer -= delta

	dash_velocity = dash_direction * dash_speed
	player.velocity = dash_velocity

	if timer <= 0.0:
		finish_dash(player)

func finish_dash(player: Player) -> void:
	is_active = false

	player.velocity.x = dash_direction.x * dash_end_speed

	if dash_direction.y < 0.0:
		player.velocity.y *= 0.5

	player.exit_dash_state()
	dash_finished.emit()

func cancel_dash(player: Player) -> void:
	is_active = false
	player.exit_dash_state()
	dash_finished.emit()

# Helper to interrupt the dash with an immediate jump. Player script can call this
# when jump is pressed during an active dash to apply the jump and cancel the dash.
@export var horizontal_bounce_force: float = 320.0
@export var horizontal_interrupt_multiplier: float = 0.6
@export var horizontal_interrupt_clamp_speed: float = 260.0
@export var horizontal_reverse_speed: float = 220.0
# More upward momentum when cancelling a downward dash, less downward momentum when cancelling an upward dash.
@export var vertical_bounce_force_down_dash: float = 700.0  # used when dir.y > 0 (down dash)
@export var vertical_bounce_force_up_dash: float = 420.0    # used when dir.y < 0 (up dash)
@export var axis_threshold: float = 0.7

# Burst/clamp settings: short, fast impulse then clamp to reduce travel distance
@export var burst_duration: float = 0.04
@export var clamp_upward_after_burst: float = 320.0
@export var clamp_downward_after_burst: float = 220.0

# Disable variable jump-height temporarily after down-dash interrupt
@export var disable_jump_cut_time: float = 0.2

func interrupt_with_jump(player: Player) -> void:
	# Cancel the dash and apply a bounce if the dash was primarily horizontal or vertical.
	# Diagonal dashes fall back to a normal jump for now.
	cancel_dash(player)

	var dir: Vector2 = dash_direction.normalized()
	var absx: float = abs(dir.x)
	var absy: float = abs(dir.y)

	# Horizontal dash (mostly x)
	if absx >= axis_threshold and absy <= (1.0 - axis_threshold):
		# Interrupt: reduce horizontal speed sharply and apply standard jump impulse.
		# If player holds the opposite direction, reverse momentum to a set reverse speed.
		var current_h: float = player.velocity.x
		var base_dir_sign: int = int(sign(current_h)) if current_h != 0.0 else int(sign(dir.x))
		var input_x: float = Input.get_axis("move_left", "move_right")
		if abs(input_x) > 0.1 and int(sign(input_x)) == -base_dir_sign:
			# Reverse momentum
			player.velocity.x = -base_dir_sign * horizontal_reverse_speed
		else:
			var reduced_h: float = base_dir_sign * min(abs(current_h) * horizontal_interrupt_multiplier, horizontal_interrupt_clamp_speed)
			player.velocity.x = reduced_h
		player.velocity.y = player.jump_velocity
		return

	# Vertical dash (mostly y)
	if absy >= axis_threshold and absx <= (1.0 - axis_threshold):
		# Bounce vertically in the opposite direction. Clear horizontal velocity.
		player.velocity.x = 0.0
		if dir.y > 0.0:
			# Down dash -> stronger upward burst
			player.velocity.y = -vertical_bounce_force_down_dash
				# Disable variable jump height for a short window so the bounce isn't cut
			player.jump_cut_disabled_timer = disable_jump_cut_time
			# After a short burst, clamp upward speed to reduce distance
			await get_tree().create_timer(burst_duration).timeout
			if not player.is_on_floor() and player.velocity.y < -clamp_upward_after_burst:
				player.velocity.y = -clamp_upward_after_burst
		else:
			# Up dash -> weaker downward burst
			player.velocity.y = vertical_bounce_force_up_dash
			# After a short burst, clamp downward speed to reduce distance
			await get_tree().create_timer(burst_duration).timeout
			if not player.is_on_floor() and player.velocity.y > clamp_downward_after_burst:
				player.velocity.y = clamp_downward_after_burst
		return

	# Up-diagonal dash -> perform a wall bounce (reverse x push and upward bounce)
	if dir.y < 0.0 and absx > 0.1 and absy > 0.1:
		# emulate wall bounce: push opposite horizontal direction
		cancel_dash(player)
		var push_direction := -int(sign(dir.x))
		player.velocity.x = push_direction * player.wall_bounce_push_force
		player.velocity.y = player.wall_bounce_velocity

		# apply wall bounce timers/control locks
		player.jump_cut_disabled_timer = player.WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		player.wall_bounce_control_lock_timer = player.wall_bounce_control_lock_time

		player.jump_buffered = false
		player.state = 2 # PlayerState.WALL_BOUNCING
		player.coyote_timer = 0.0
		# Only refresh dash if this was a real wall bounce (player is next to a wall)
		if player.is_next_to_wall:
			player.dash_available = true
		return

	# Down-diagonal dash -> start a wavedash
	if dir.y > 0.0 and absx > 0.1 and absy > 0.1:
		var dash_dir := dash_direction
		var input_x_axis: float = Input.get_axis("move_left", "move_right")
		var wavedash_direction := input_x_axis if abs(input_x_axis) > 0.1 else dash_dir.x
		var wavedash_speed := dash_velocity.length() * player.wavedash_speed_mult

		player.velocity.x = wavedash_direction * wavedash_speed
		player.velocity.y = player.wavedash_jump_velocity

		player.coyote_timer = 0.0
		player.wavedash_window_timer = 0.0
		player.wavedash_buffer_timer = player.wavedash_buffer_time
		return

	# Fallback: just do a normal jump
	player.velocity.y = player.jump_velocity
