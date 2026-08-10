extends DashAbility
class_name ConchShellDash

@export var dash_speed: float = 350.0
# Matches BasicDash's dash_duration so a quick tap covers the same distance
# as a normal dash. Holding past this extends the dash up to max_dash_duration.
@export var min_dash_duration: float = 0.18
@export var max_dash_duration: float = 0.3  # How long you can hold it
# Extra time allowed, on top of max_dash_duration, once the player has
# actively redirected the dash — so turning doesn't just eat into an
# already-short window. Kept small on purpose; this isn't meant to make
# the dash meaningfully longer, just give turning room to matter.
@export var turn_max_duration_bonus: float = 0.05
@export var turn_speed: float = 10.0  # How quickly to turn toward input direction
@export var dash_end_speed: float = 200.0  # Momentum preserved on release

var timer: float = 0.0
var has_turned: bool = false
var initial_dash_direction: Vector2 = Vector2.RIGHT

func start_dash(player: Player, dir: Vector2) -> void:
	super.start_dash(player, dir)

	timer = 0.0
	has_turned = false
	initial_dash_direction = dash_direction
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

		# Once the player has meaningfully redirected away from where the dash
		# started (not just held the same direction), grant the small bonus
		# window so the turn has time to actually matter.
		if not has_turned and initial_dash_direction.dot(dash_direction) < 0.9:
			has_turned = true

	# Update velocity based on current dash direction
	dash_velocity = dash_direction * dash_speed
	player.velocity = dash_velocity

	var effective_max_duration := max_dash_duration
	if has_turned:
		effective_max_duration += turn_max_duration_bonus

	# Always dash for at least min_dash_duration, even on a quick tap, so the
	# distance matches a normal dash. Holding past that extends the dash
	# (with steering) up to effective_max_duration.
	if timer >= min_dash_duration and (not dash_held or timer >= effective_max_duration):
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

	# Arm the wavedash window here, at the moment of collision, rather than
	# relying on player.gd's generic post-landing check. finish_dash() below
	# flips state to NORMAL immediately, so by the time that generic check
	# runs, state != DASHING anymore and the window never gets armed — the
	# same issue panflute already works around this same way. Only counts as
	# a wavedash candidate if there's a horizontal component (matches the
	# other wavedash-arming checks elsewhere).
	var is_ground_hit: bool = normal.y < -0.5 and dash_direction.y > 0.1 and abs(dash_direction.x) > 0.1
	if is_ground_hit:
		player.wavedash_window_timer = player.wavedash_input_window

	finish_dash(player)
