extends Enemy
class_name MeleeGroundEnemy

# Basic grounded chase-and-hop enemy. No attacks — contact damage only,
# handled entirely by the base Enemy class. Movement uses its own small,
# separate set of tunable values rather than reusing anything from player.gd.
#
# Written as plain GDScript for now (the behavior's simple enough not to need
# more), but kept as small, clearly-named, single-purpose functions
# (_should_jump-style checks, one _decide_movement() entry point) instead of
# one tangled _physics_process — each of those is a natural candidate to
# become a LimboAI condition/leaf later once more enemy types show up and a
# hand-written state stops being enough.

@export_group("Movement")
@export var move_speed := 60.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
@export var jump_velocity := -280.0

@export_group("AI")
@export var detection_range := 400.0  # how far the player can be and still get chased
@export var obstacle_check_height := 32.0  # how far above the ground the "can I jump over this" ray sits, and how far above the enemy the player has to be to trigger a jump — match this to your tile size
@export var jump_cooldown := 0.4  # minimum time between jumps so it doesn't spam-jump against a wall or a raised player

var facing_direction := 1
var jump_cooldown_timer := 0.0

@onready var forward_ray: RayCast2D = $ForwardRay
@onready var ledge_ray: RayCast2D = $LedgeRay
@onready var obstacle_top_ray: RayCast2D = $ObstacleTopRay


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	tick_lifetime(delta)
	if is_dead:
		return

	jump_cooldown_timer = maxf(jump_cooldown_timer - delta, 0.0)

	_apply_gravity(delta)
	_update_facing()
	_update_rays()
	_decide_movement()

	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _player_in_range() -> bool:
	return Global.player and global_position.distance_to(Global.player.global_position) <= detection_range


func _update_facing() -> void:
	if not _player_in_range():
		return
	facing_direction = 1 if Global.player.global_position.x > global_position.x else -1


# Raycast positions/directions are authored pointing right by default in the
# scene; this mirrors them to match whichever way the enemy is currently
# facing, then forces an immediate update so this frame's is_colliding()
# checks reflect the flip instead of lagging a frame behind.
func _update_rays() -> void:
	forward_ray.target_position.x = abs(forward_ray.target_position.x) * facing_direction
	ledge_ray.position.x = abs(ledge_ray.position.x) * facing_direction
	obstacle_top_ray.position.y = -obstacle_check_height
	obstacle_top_ray.target_position.x = abs(obstacle_top_ray.target_position.x) * facing_direction

	forward_ray.force_raycast_update()
	ledge_ray.force_raycast_update()
	obstacle_top_ray.force_raycast_update()


func _is_player_above() -> bool:
	if not _player_in_range():
		return false
	var above_by: float = global_position.y - Global.player.global_position.y
	var horizontal_dist: float = abs(global_position.x - Global.player.global_position.x)
	return above_by > obstacle_check_height and horizontal_dist < obstacle_check_height * 2.0


func _decide_movement() -> void:
	if not _player_in_range():
		velocity.x = 0.0
		return

	if _is_player_above() and jump_cooldown_timer <= 0.0 and is_on_floor():
		_jump()
		return

	if forward_ray.is_colliding():
		if obstacle_top_ray.is_colliding():
			# Blocked, and it's tall enough to also block the "can I jump
			# over this" ray — too tall to hop, turn around instead.
			facing_direction *= -1
			velocity.x = 0.0
		elif jump_cooldown_timer <= 0.0 and is_on_floor():
			_jump()
		return

	if is_on_floor() and not ledge_ray.is_colliding():
		# No ground ahead — about to walk off a ledge, turn around.
		facing_direction *= -1
		velocity.x = 0.0
		return

	velocity.x = move_speed * facing_direction


func _jump() -> void:
	velocity.y = jump_velocity
	jump_cooldown_timer = jump_cooldown
