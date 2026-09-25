@tool
extends Area2D
class_name CameraTargetTrigger

## A reusable Phantom Camera trigger for sections that need a fixed camera
## position on one or both axes.

enum AxisLock {
	NONE = 0,
	X = 1,
	Y = 2,
	BOTH = 3,
}

@export_enum("None", "X", "Y", "Both") var axis_lock: int = AxisLock.NONE
@export var activation_priority: int = 20
@export_node_path("Node2D") var camera_target_path: NodePath = NodePath("CameraTarget")
@export var trigger_size: Vector2 = Vector2(256, 256):
	set(value):
		trigger_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_apply_trigger_size()
		queue_redraw()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var phantom_camera: PhantomCamera2D = $PhantomCamera2D
@onready var camera_target: Node2D = get_node(camera_target_path)

var _active_player: Player
var _follow_target: Node2D
var _entry_offset := Vector2.ZERO


func _draw() -> void:
	var half_size := trigger_size * 0.5
	draw_rect(Rect2(-half_size, trigger_size), Color(0.35, 0.85, 1.0, 0.15), false, 2.0)

	var target_position := Vector2.ZERO
	if is_instance_valid(camera_target):
		target_position = camera_target.position

	draw_line(Vector2.ZERO, target_position, Color(0.35, 0.85, 1.0, 0.9), 2.0)
	draw_circle(target_position, 6.0, Color(0.35, 0.85, 1.0, 0.9))


func _process(_delta: float) -> void:
	if not is_instance_valid(_active_player) or not is_instance_valid(_follow_target):
		return

	var player_position := _active_player.global_position + _entry_offset
	var target_position := camera_target.global_position

	match axis_lock:
		AxisLock.X:
			player_position.x = target_position.x
		AxisLock.Y:
			player_position.y = target_position.y
		AxisLock.BOTH:
			player_position = target_position

	_follow_target.global_position = player_position


func _ready() -> void:
	_apply_trigger_size()
	if Engine.is_editor_hint():
		return

	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	phantom_camera.set_priority(0)
	_follow_target = Node2D.new()
	_follow_target.name = "RuntimeFollowTarget"
	_follow_target.top_level = true
	add_child(_follow_target)


func _apply_trigger_size() -> void:
	if not is_instance_valid(collision_shape):
		return
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle:
		rectangle.size = trigger_size


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	if is_instance_valid(_active_player):
		return

	_active_player = body as Player
	_entry_offset = camera_target.global_position - _active_player.global_position
	_follow_target.global_position = camera_target.global_position
	phantom_camera.set_follow_target(_follow_target)

	phantom_camera.set_priority(activation_priority)


func _on_body_exited(body: Node2D) -> void:
	if body != _active_player:
		return

	phantom_camera.set_priority(0)
	phantom_camera.set_follow_target(null)
	_active_player = null
