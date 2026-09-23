@tool
extends Area2D
class_name CameraBorder

## A placeable camera-limit rectangle. The same rectangle detects the Player
## and supplies the active Phantom Camera's limit_target.

@export var border_size: Vector2 = Vector2(640, 360):
	set(value):
		border_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_apply_border_size()
		queue_redraw()

@export var activation_priority: int = 10

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var phantom_camera: PhantomCamera2D = $PhantomCamera2D

var _active_player: Player


func _draw() -> void:
	var half_size := border_size * 0.5
	draw_rect(
		Rect2(-half_size, border_size),
		Color(0.25, 0.75, 1.0, 0.12),
		true
	)
	draw_rect(
		Rect2(-half_size, border_size),
		Color(0.25, 0.75, 1.0, 0.9),
		false,
		2.0
	)


func _ready() -> void:
	_apply_border_size()
	if Engine.is_editor_hint():
		return

	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	phantom_camera.set_priority(0)


func _apply_border_size() -> void:
	if not is_instance_valid(collision_shape):
		return

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle:
		rectangle.size = border_size


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if is_instance_valid(_active_player):
		return

	_active_player = body as Player
	phantom_camera.set_follow_target(_active_player)
	phantom_camera.set_limit_target(NodePath("../CollisionShape2D"))
	phantom_camera.set_priority(activation_priority)


func _on_body_exited(body: Node2D) -> void:
	if body != _active_player:
		return

	phantom_camera.set_priority(0)
	phantom_camera.reset_limit()
	phantom_camera.set_limit_target(NodePath(""))
	phantom_camera.set_follow_target(null)
	_active_player = null
