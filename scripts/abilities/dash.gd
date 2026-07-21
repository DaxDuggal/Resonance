extends Node
class_name DashAbility


signal dash_finished


@export var allows_wavedash := true
@export var allows_wall_bounce := true
# Default recoil force applied when a dash hits a surface and the ability doesn't implement its own reaction
@export var default_recoil_force: float = 80.0

var is_active := false
var dash_direction := Vector2.RIGHT
var dash_velocity := Vector2.ZERO


func can_start(_player: Player) -> bool:
	return true


func start_dash(player: Player, dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		dir = Vector2(player.facing_direction, 0)

	dash_direction = dir.normalized()
	dash_velocity = Vector2.ZERO
	is_active = true

	player.enter_dash_state()


func update_dash(_player: Player, _delta: float) -> void:
	pass


func finish_dash(player: Player) -> void:
	is_active = false
	player.exit_dash_state()
	dash_finished.emit()


func cancel_dash(player: Player) -> void:
	is_active = false
	player.exit_dash_state()
	dash_finished.emit()


func get_wavedash_direction() -> Vector2:
	return dash_direction


func get_wall_bounce_direction() -> Vector2:
	return dash_direction


# Called by Player after move_and_slide when a slide collision occurs while dashing.
# Default implementation does nothing. Abilities that want custom behavior should override this method.
func handle_slide_collision(_player: Player, _collision) -> void:
	pass
