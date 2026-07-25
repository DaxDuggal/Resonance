extends DashAbility
class_name BasicDash

@export var dash_speed := 350.0
@export var dash_duration := 0.18
@export var dash_end_speed := 180.0

var timer := 0.0


func start_dash(player: Player, dir: Vector2) -> void:
	super.start_dash(player, dir)

	timer = dash_duration
	dash_velocity = dash_direction * dash_speed

	player.velocity = dash_velocity
	player.dash_available = false
	player.dash_buffer_timer = 0.0


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
