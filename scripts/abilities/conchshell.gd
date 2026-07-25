extends DashAbility
class_name ConchShellDash

@export var dash_speed: float = 350.0
@export var max_dash_duration: float = 0.5  # How long you can hold it
@export var turn_speed: float = 7.0  # How quickly to turn toward input direction
@export var dash_end_speed: float = 200.0  # Momentum preserved on release

var timer: float = 0.0

func start_dash(player: Player, dir: Vector2) -> void:
	super.start_dash(player, dir)

	timer = 0.0
	dash_velocity = dash_direction * dash_speed

	player.velocity = dash_velocity
	player.dash_available = false
	player.dash_buffer_timer = 0.0

func update_dash(player: Player, delta: float) -> void:
	timer += delta

	# Check if dash button is still held
	var dash_held := Input.is_action_pressed("dash")

	# Allow steering with full 360 movement
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")
	var input_dir := Vector2(input_x, input_y).normalized()

	# Smoothly turn toward input direction
	if input_dir.length() > 0.1:
		dash_direction = dash_direction.lerp(input_dir, turn_speed * delta).normalized()

	# Update velocity based on current dash direction
	dash_velocity = dash_direction * dash_speed
	player.velocity = dash_velocity

	# End dash if button released or max duration reached
	if not dash_held or timer >= max_dash_duration:
		finish_dash(player)

func finish_dash(player: Player) -> void:
	is_active = false

	# Preserve some momentum in the direction we were moving
	player.velocity = dash_direction * dash_end_speed

	player.exit_dash_state()
	dash_finished.emit()

func cancel_dash(player: Player) -> void:
	is_active = false
	player.exit_dash_state()
	dash_finished.emit()

# End the dash when we run into geometry, and open the wall bounce window
# if we hit a wall while moving upward (matches the other dash abilities).
func handle_slide_collision(player: Player, collision) -> void:
	var normal: Vector2 = Vector2.ZERO
	if typeof(collision) == TYPE_DICTIONARY:
		if collision.has("normal"):
			normal = collision.get("normal")
	elif collision and collision.has_method("get_normal"):
		normal = collision.get_normal()

	if abs(normal.x) > 0.5 and dash_direction.y < 0.0:
		player.wall_bounce_window_timer = player.wall_bounce_window_time
		player.wall_bounce_normal = normal

	finish_dash(player)
