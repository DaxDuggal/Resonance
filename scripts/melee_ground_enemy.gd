extends Enemy
class_name MeleeGroundEnemy

@export_group("Movement")
@export var move_speed := 150.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
@export var jump_velocity := -280.0

@export_group("AI")
@export var obstacle_check_height := 32.0
@export var jump_cooldown := 0.4
@export_group("AI/Turn Lock")
@export var turn_lock_time := 0.35

@export_group("Attack")
@export var attack_hitbox_offset := 20.0
@export var lunge_speed := 420.0
@export var lunge_jump_velocity := -110.0
@export var lunge_range_margin := 6.0
@export var lunge_vertical_tolerance := 24.0
@export var lunge_below_tolerance := 40.0
@export var retreat_speed := 70.0

var jump_cooldown_timer := 0.0
var turn_lock_timer := 0.0
var _lunge_launched := false

@onready var forward_ray: RayCast2D = $ForwardRay
@onready var ledge_ray: RayCast2D = $LedgeRay
@onready var obstacle_top_ray: RayCast2D = $ObstacleTopRay
@onready var bt_player: BTPlayer = $BTPlayer
@onready var visual: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	super._ready()
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_awareness(delta)

	jump_cooldown_timer = maxf(jump_cooldown_timer - delta, 0.0)
	turn_lock_timer = maxf(turn_lock_timer - delta, 0.0)

	_apply_gravity(delta)
	_tick_attack(delta)
	_update_attack_hitbox()
	_update_attack_visual()

	if _tick_knockback_stun(delta):
		move_and_slide()
		return

	if is_attacking():
		_process_attack_movement()
		move_and_slide()
		return

	_update_facing()
	visual.flip_h = facing_direction == -1
	_update_rays()

	bt_player.update(delta)

	move_and_slide()


func _update_attack_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.position.x = attack_hitbox_offset * facing_direction


# Charging telegraph: flash red during STARTUP so the swing is readable
# (and parryable) before it lands, otherwise back to normal.
func _update_attack_visual() -> void:
	visual.modulate = Color(1.0, 0.3, 0.3) if attack_phase == AttackPhase.STARTUP else Color.WHITE


# STARTUP = freeze in place (the telegraph is just stopping, no color flash).
# ACTIVE = a mostly-horizontal pounce (a one-time small upward impulse at the
# moment the lunge launches, then gravity arcs it back down over the rest of
# the active window — Silksong Needle Strike style, not a flat ground-slide).
# RECOVERY = back up a bit before the loop repeats.
func _process_attack_movement() -> void:
	match attack_phase:
		AttackPhase.STARTUP:
			velocity.x = 0.0
			_lunge_launched = false
		AttackPhase.ACTIVE:
			if not _lunge_launched:
				velocity.y = lunge_jump_velocity
				_lunge_launched = true
			velocity.x = lunge_speed * facing_direction
		AttackPhase.RECOVERY:
			velocity.x = -retreat_speed * facing_direction


# Trigger range is deliberately smaller than the lunge's total travel
# distance, so the lunge itself closes the remaining gap instead of the
# enemy needing to already be standing at melee range.
func _attack_trigger_range() -> float:
	if not attack_profile:
		return 0.0
	var lunge_distance := lunge_speed * attack_profile.active_duration
	return maxf(lunge_distance - lunge_range_margin, 0.0)


func _is_attack_ready() -> bool:
	if not can_start_attack():
		return false
	if not _player_in_range():
		return false
	var to_player: Vector2 = Global.player.global_position - global_position
	if to_player.y < -lunge_vertical_tolerance:
		return false
	if to_player.y > lunge_below_tolerance:
		return false
	if absf(to_player.x) > _attack_trigger_range():
		return false
	if to_player.x != 0.0 and sign(to_player.x) != facing_direction:
		return false
	return true


# True when the player is detected but standing above the lunge's reach
# (e.g. perched directly on top of the agent). Distinct from "can't attack
# yet" — this means "can't attack at all from here," so the tree should
# just wait rather than trying to chase/turn toward an unreachable target.
func _is_player_overhead() -> bool:
	if not _player_in_range():
		return false
	var to_player: Vector2 = Global.player.global_position - global_position
	return to_player.y < -lunge_vertical_tolerance


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _player_in_range() -> bool:
	return is_aware_of_player


func _update_facing() -> void:
	if turn_lock_timer > 0.0:
		return
	if not _player_in_range():
		return
	facing_direction = 1 if Global.player.global_position.x > global_position.x else -1


func _update_rays() -> void:
	forward_ray.target_position.x = abs(forward_ray.target_position.x) * facing_direction
	ledge_ray.position.x = abs(ledge_ray.position.x) * facing_direction
	obstacle_top_ray.position.y = -obstacle_check_height
	obstacle_top_ray.target_position.x = abs(obstacle_top_ray.target_position.x) * facing_direction

	forward_ray.force_raycast_update()
	ledge_ray.force_raycast_update()
	obstacle_top_ray.force_raycast_update()


func _jump() -> void:
	velocity.y = jump_velocity
	jump_cooldown_timer = jump_cooldown
