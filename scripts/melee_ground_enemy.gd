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
@export var normal_attack_range := 50.0
@export var lunge_min_range := 70.0
@export var lunge_speed := 520.0
@export var lunge_jump_velocity := -110.0
@export var lunge_range_margin := 6.0
@export var lunge_vertical_tolerance := 24.0
@export var lunge_below_tolerance := 40.0
@export var retreat_speed := 70.0

@export_group("Attack/Overhead")
@export var overhead_attack_range := 40.0
@export var overhead_attack_max_height := 150.0

@export_group("Parry")
@export var max_consecutive_parries := 3
@export var parry_reaction_range := 75.0
@export var parry_vertical_tolerance := 40.0
var consecutive_parries := 0

var jump_cooldown_timer := 0.0
var turn_lock_timer := 0.0
var _lunge_launched := false
var _attack_hitbox_editor_position := Vector2.ZERO
var _lunge_hitbox_editor_position := Vector2.ZERO
var _attack_shape_editor_position := Vector2.ZERO
var _lunge_shape_editor_position := Vector2.ZERO

enum MeleeAttack { NORMAL, LUNGE }
var selected_attack := MeleeAttack.NORMAL

@onready var forward_ray: RayCast2D = $ForwardRay
@onready var ledge_ray: RayCast2D = $LedgeRay
@onready var obstacle_top_ray: RayCast2D = $ObstacleTopRay
@onready var bt_player: BTPlayer = $BTPlayer
@onready var visual: AnimatedSprite2D = $AnimatedSprite2D
@onready var lunge_hitbox: DamageHitbox = $LungeHitbox
@onready var lunge_hitbox_shape: CollisionShape2D = $LungeHitbox/CollisionShape2D
@onready var attack_hitbox_visual: ColorRect = $AttackHitbox/CollisionShape2D/Visual
@onready var lunge_hitbox_visual: ColorRect = $LungeHitbox/CollisionShape2D/Visual


func _ready() -> void:
	super._ready()
	_attack_hitbox_editor_position = attack_hitbox.position
	_lunge_hitbox_editor_position = lunge_hitbox.position
	_attack_shape_editor_position = attack_hitbox_shape.position
	_lunge_shape_editor_position = lunge_hitbox_shape.position
	if attack_hitbox and lunge_hitbox:
		lunge_hitbox.damage = attack_hitbox.damage
		lunge_hitbox.knockback_force = attack_hitbox.knockback_force
		lunge_hitbox.knockback_vertical_ratio = attack_hitbox.knockback_vertical_ratio
		lunge_hitbox.is_parryable = attack_hitbox.is_parryable
	_update_attack_hitbox()
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Same reasoning as Player._physics_process()'s own guard: a NaN/Inf
	# velocity here would otherwise feed into a knockback vector computed
	# from this enemy's position on the player's next hit, propagating the
	# corruption onto the player instead of staying contained to this enemy.
	if not velocity.is_finite():
		velocity = Vector2.ZERO

	_update_awareness(delta)

	if _tick_stun(delta):
		_apply_gravity(delta)
		velocity.x = 0.0
		move_and_slide()
		_apply_player_overlap_push()
		return

	jump_cooldown_timer = maxf(jump_cooldown_timer - delta, 0.0)
	turn_lock_timer = maxf(turn_lock_timer - delta, 0.0)

	_apply_gravity(delta)
	_tick_attack(delta)
	_update_attack_hitbox()
	_update_attack_visual()

	if _tick_knockback_stun(delta):
		move_and_slide()
		_apply_player_overlap_push()
		return

	if is_attacking():
		_process_attack_movement(delta)
		move_and_slide()
		_apply_player_overlap_push()
		return

	_update_facing()
	visual.flip_h = facing_direction == -1
	_update_rays()

	bt_player.update(delta)

	move_and_slide()
	_apply_player_overlap_push()


func _update_attack_hitbox() -> void:
	if attack_hitbox:
		attack_hitbox.position = _mirrored_hitbox_position(_attack_hitbox_editor_position)
	if lunge_hitbox:
		lunge_hitbox.position = _mirrored_hitbox_position(_lunge_hitbox_editor_position)
	if attack_hitbox_shape:
		attack_hitbox_shape.position = _mirrored_hitbox_position(_attack_shape_editor_position)
	if lunge_hitbox_shape:
		lunge_hitbox_shape.position = _mirrored_hitbox_position(_lunge_shape_editor_position)
	if lunge_hitbox_shape:
		lunge_hitbox_shape.disabled = selected_attack != MeleeAttack.LUNGE or attack_phase != AttackPhase.ACTIVE
	if attack_hitbox_shape:
		attack_hitbox_shape.disabled = selected_attack != MeleeAttack.NORMAL or attack_phase != AttackPhase.ACTIVE
	if attack_hitbox_visual:
		attack_hitbox_visual.visible = not attack_hitbox_shape.disabled
	if lunge_hitbox_visual:
		lunge_hitbox_visual.visible = not lunge_hitbox_shape.disabled


func _mirrored_hitbox_position(editor_position: Vector2) -> Vector2:
	var mirrored := editor_position
	mirrored.x = absf(editor_position.x) * facing_direction
	return mirrored


func _cancel_attack() -> void:
	super._cancel_attack()
	if lunge_hitbox_shape:
		lunge_hitbox_shape.disabled = true
	if attack_hitbox_visual:
		attack_hitbox_visual.visible = false
	if lunge_hitbox_visual:
		lunge_hitbox_visual.visible = false


func can_start_parry() -> bool:
	if not super.can_start_parry() or consecutive_parries >= max_consecutive_parries:
		return false
	if not Global.player or not Global.player.has_flag(Player.Flag.ATTACKING):
		return false
	var offset: Vector2 = Global.player.global_position - global_position
	return offset.length() <= parry_reaction_range and absf(offset.y) <= parry_vertical_tolerance


func _consume_parry_hit() -> bool:
	var parry_is_open := super._consume_parry_hit()
	if consecutive_parries >= max_consecutive_parries:
		return false
	if not parry_is_open:
		return false
	consecutive_parries += 1
	return true


func _can_auto_parry_player_hit() -> bool:
	return not is_parrying() \
		and not is_attacking() \
		and stun_timer <= 0.0 \
		and knockback_stun_timer <= 0.0 \
		and consecutive_parries < max_consecutive_parries


func _on_auto_parry_player_hit() -> void:
	consecutive_parries += 1
	parry_flash_timer = parry_flash_duration


func _on_parry_sequence_break() -> void:
	consecutive_parries = 0


# Charging telegraph: flash red during STARTUP so the swing is readable
# (and parryable) before it lands, otherwise back to normal.
func _update_attack_visual() -> void:
	if is_parrying() or is_parry_flashing():
		visual.modulate = Color(1.0, 0.9, 0.15)
	else:
		visual.modulate = Color(1.0, 0.3, 0.3) if attack_phase == AttackPhase.STARTUP else Color.WHITE


# STARTUP = freeze in place (the telegraph is just stopping, no color flash).
# ACTIVE = a mostly-horizontal pounce (a one-time small upward impulse at the
# moment the lunge launches, then gravity arcs it back down over the rest of
# the active window — Silksong Needle Strike style, not a flat ground-slide).
# This is the same attack regardless of whether the player is level or
# perched above (see _is_attack_ready) — no separate overhead move, it just
# throws the usual pounce, which the small upward hop gives it a real
# chance of connecting with.
# RECOVERY = back up a bit before the loop repeats.
func _process_attack_movement(_delta: float) -> void:
	match attack_phase:
		AttackPhase.STARTUP:
			velocity.x = 0.0
			_lunge_launched = false
		AttackPhase.ACTIVE:
			if selected_attack == MeleeAttack.LUNGE:
				if not _lunge_launched:
					velocity.y = lunge_jump_velocity
					_lunge_launched = true
				velocity.x = lunge_speed * facing_direction
			else:
				velocity.x = 0.0
		AttackPhase.RECOVERY:
			velocity.x = -retreat_speed * facing_direction if selected_attack == MeleeAttack.LUNGE else 0.0


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
	var distance_x := absf(to_player.x)
	_face_player()

	# Player perched above, beyond the normal lunge's reach: it still throws
	# the same pounce rather than just waiting, as long as they're not so
	# high or so far to the side that the hop has no real chance of
	# connecting.
	if to_player.y < -lunge_vertical_tolerance:
		if to_player.y < -overhead_attack_max_height:
			return false
		if absf(to_player.x) > overhead_attack_range:
			return false
		selected_attack = MeleeAttack.LUNGE
		return true

	if to_player.y > lunge_below_tolerance:
		return false
	if distance_x > _attack_trigger_range():
		return false
	if to_player.x != 0.0 and sign(to_player.x) != facing_direction:
		return false
	if distance_x <= normal_attack_range:
		selected_attack = MeleeAttack.NORMAL
	elif distance_x >= lunge_min_range:
		selected_attack = MeleeAttack.LUNGE
	else:
		return false
	return true


func start_normal_attack() -> bool:
	if not can_start_attack():
		return false
	selected_attack = MeleeAttack.NORMAL
	start_attack()
	return is_attacking()


func start_lunge() -> bool:
	if not can_start_attack():
		return false
	selected_attack = MeleeAttack.LUNGE
	start_attack()
	return is_attacking()


func _is_basic_attack_ready() -> bool:
	if not _is_attack_ready():
		return false
	return selected_attack == MeleeAttack.NORMAL


func start_basic_attack() -> bool:
	return start_normal_attack()


func _is_special_attack_ready() -> bool:
	if not _is_attack_ready():
		return false
	return selected_attack == MeleeAttack.LUNGE


func start_special_attack() -> bool:
	return start_lunge()


# True when the player is detected but genuinely out of reach — either below
# a ledge the agent is standing above, or perched above but too high/too far
# sideways for the pounce (see _is_attack_ready) to have a chance.
# Distinct from "can't attack yet" — this means "can't attack at all from
# here," so the tree should just wait rather than trying to chase/turn
# toward a target it can't get level with either way.
func _face_player() -> void:
	if not Global.player:
		return
	var to_player_x := Global.player.global_position.x - global_position.x
	if absf(to_player_x) <= 1.0:
		return
	facing_direction = int(signf(to_player_x))
	visual.flip_h = facing_direction == -1
	_update_attack_hitbox()


func _is_player_overhead() -> bool:
	if not _player_in_range():
		return false
	var to_player: Vector2 = Global.player.global_position - global_position
	if to_player.y < -lunge_vertical_tolerance:
		return to_player.y < -overhead_attack_max_height or absf(to_player.x) > overhead_attack_range
	return to_player.y > lunge_below_tolerance


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
