extends CharacterBody2D
class_name Player


enum Flag {
	DASHING = 1 << 0,
	WALL_CLINGING = 1 << 1,
	HURT = 1 << 2,
	DEAD = 1 << 3,
	ATTACKING = 1 << 4,
	PARRYING = 1 << 5,
	SPECIAL = 1 << 6,
}

var flags: int = 0

func has_flag(mask: int) -> bool:
	return (flags & mask) != 0

func set_flag(flag: int, value: bool) -> void:
	if value:
		flags |= flag
	else:
		flags &= ~flag

func is_invulnerable() -> bool:
	return invulnerability_timer > 0.0 or dash_grace_timer > 0.0

func is_airborne() -> bool:
	return not is_on_floor()

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer

@onready var attack_hitbox: DamageHitbox = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var attack_hitbox_visual: ColorRect = $AttackHitbox/CollisionShape2D/Visual
@onready var special_hitbox: DamageHitbox = $SpecialHitbox
@onready var special_hitbox_shape: CollisionShape2D = $SpecialHitbox/CollisionShape2D
@onready var special_hitbox_visual: ColorRect = $SpecialHitbox/CollisionShape2D/Visual

func _ready() -> void:
	Global.player = self

	if Global.has_checkpoint:
		global_position = Global.last_checkpoint_position

	if Global.saved_current_health >= 0:
		current_health = Global.saved_current_health
		Global.saved_current_health = -1
	else:
		current_health = max_health

	Global.last_safe_position = global_position

	attack_hitbox.damage = attack_damage
	attack_hitbox.knockback_force = attack_knockback_force
	special_hitbox.damage = special_damage

	_sync_hitbox_visual_to_shape(attack_hitbox_shape, attack_hitbox_visual)
	_sync_hitbox_visual_to_shape(special_hitbox_shape, special_hitbox_visual)

	if Global.did_just_die:
		invulnerability_timer = invulnerability_duration
		respawn_lock_timer = respawn_lock_time
		Global.did_just_die = false

	if has_node("Hurtbox"):
		$Hurtbox.add_to_group("player_hitbox")
		if not $Hurtbox.is_connected("area_entered", Callable(self, "_on_hazard_area_entered")):
			$Hurtbox.connect("area_entered", Callable(self, "_on_hazard_area_entered"))
		if not $Hurtbox.is_connected("area_exited", Callable(self, "_on_hazard_area_exited")):
			$Hurtbox.connect("area_exited", Callable(self, "_on_hazard_area_exited"))
		if not $Hurtbox.is_connected("body_entered", Callable(self, "_on_hazard_body_entered")):
			$Hurtbox.connect("body_entered", Callable(self, "_on_hazard_body_entered"))
		if not $Hurtbox.is_connected("body_exited", Callable(self, "_on_hazard_body_exited")):
			$Hurtbox.connect("body_exited", Callable(self, "_on_hazard_body_exited"))


@export_group("Health")
@export var max_health := 3
var current_health := 3
var invulnerability_timer := 0.0
@export var invulnerability_duration := 0.75
var hit_flash_timer := 0.0
@export var hit_flash_duration := 0.4
@export var knockback_control_lock_time := 0.15

const ENEMY_HURTBOX_LAYER := 64  # project.godot layer_7 "EnemyHurtbox"

@export_group("Attack")
@export var attack_damage := 1
@export var attack_duration := 0.15
@export var attack_cooldown := 0.15
@export var attack_hitbox_horizontal_offset := 12.0
@export var attack_hitbox_vertical_offset := 14.0
@export var attack_recoil_force := 40.0
@export var attack_knockback_force := 250.0
@export var attack_hitstop_duration := 0.09  # landing a hit on an enemy — kept a bit above enemy_hit_hitstop_duration below

@export_group("Hurt")
# Resolving an incoming enemy hit is delayed by this long (real time, not
# game time — see Global.hitstop) before damage actually applies. Input
# keeps being read during that freeze, so a parry pressed right as the hit
# lands (even a frame or two "late") still gets caught by
# take_enemy_damage()'s parry check once the delay ends, instead of losing
# a same-instant race. Kept very short since it delays all incoming hits,
# not just ones that end up parried.
@export var enemy_hit_hitstop_duration := 5.0 / 60.0  # ~5 frames @ 60fps

var attack_state_timer := 0.0
var attack_cooldown_timer := 0.0
var attack_direction := Vector2.RIGHT
var _attack_recoil_applied := false

@export_group("Parry")
@export var parry_window_duration := 0.18
@export var parry_cooldown := 0.5
@export var parry_heal_amount := 0.25
@export var parry_damage := 0.5
@export var parry_knockback_force := 270.0

var parry_state_timer := 0.0
var parry_cooldown_timer := 0.0
var _parry_heal_accumulator := 0.0

var parry_flash_timer := 0.0
const PARRY_FLASH_DURATION := 0.15

@export_group("Meter")
@export var max_meter := 3
var current_meter := 0

@export_group("Special")
@export var special_damage := 3
@export var special_duration := 0.4

var special_state_timer := 0.0

@export_group("Movement")
@export var max_speed := 240.0
@export var max_air_speed := 240.0
@export var acceleration := 1200.0
@export var air_acceleration := 1150.0
@export var friction := 1800.0
@export var air_friction := 900.0
@export var run_jump_speed_boost := 70.0
@export var run_jump_boost_ease_duration := 0.3

var run_jump_boost_timer := 0.0
var run_jump_boost_start_speed := 0.0
var run_jump_boost_direction := 0


@export_group("Jump / Gravity")
@export var jump_velocity := -300.0
@export var gravity := 980.0
@export var max_fall_speed := 600.0
@export var jump_cut_multiplier := 0.6
@export var apex_threshold := 120.0
@export var apex_gravity_mult := 0.75
@export var fall_gravity_mult := 1.2

var jump_cut_disabled_timer := 0.0

const WALL_JUMP_CUT_DISABLE_TIME := 0.2


@export_group("Coyote / Buffer")
@export var coyote_time := 0.05
@export var jump_buffer_time := 0.1
@export var dash_buffer_time := 0.1

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_buffered := false
var dash_buffer_timer := 0.0


@export_group("Dash")
@export var dash_speed := 700.0
@export var dash_duration := 0.07
@export var dash_cooldown := 0.3
@export var dash_land_cooldown := 0.05
@export var dash_grace_time := 0.05
@export var dash_gravity_mult := 0.75
@export var dash_tail_speed_mult := 0.6
@export var dash_start_ease_window := 0.15
@export var dash_animation_speed_mult := 4.0
@export var dash_ledge_refill_window := 0.3
@export var dash_ledge_check_distance := 10.0

var dash_available := true
var dash_direction := Vector2.ZERO
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_grace_timer := 0.0
var facing_direction := 1

var wall_jump_buffered := false
var wall_jump_buffer_timer := 0.0
@export var wall_jump_buffer_time := 0.1


var was_on_floor := false
var was_grounded_for_dash := true


@export_group("Wall")
@export var wall_cling_gravity_mult := 0.4
@export var wall_cling_max_fall_speed := 120.0

var is_next_to_wall := false
var was_wall_clinging := false
var wall_normal := Vector2.ZERO
var last_wall_normal := Vector2.ZERO


@export var wall_jump_push_force := 260.0
@export var wall_climb_jump_push_force := 140.0
@export var wall_jump_control_lock_time := 0.12

@export_group("Wall Jump Forgiveness")
@export var wall_coyote_time := 0.03
@export var wall_jump_redirect_window := 0.1
@export_group("")

var wall_jump_control_lock_timer := 0.0
var control_lock_timer := 0.0
var wall_coyote_timer := 0.0
var wall_jump_redirect_timer := 0.0
var wall_jump_redirect_push_direction := 0
var wall_jump_redirect_was_climb := false

var hazard_overlap_count := 0

@export var respawn_lock_time := 0.4
var respawn_lock_timer := 0.0


@export_group("Assists")
@export var corner_correction_pixels := 4


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var jump_released := Input.is_action_just_released("jump")
	var dash_pressed := Input.is_action_just_pressed("dash")
	var attack_pressed := Input.is_action_just_pressed("attack")
	var parry_pressed := Input.is_action_just_pressed("parry")
	var special_pressed := Input.is_action_just_pressed("special")

	var grounded := is_on_floor()

	if has_flag(Flag.DEAD) or respawn_lock_timer > 0.0:
		dash_pressed = false
		jump_pressed = false
		jump_released = false
		attack_pressed = false
		parry_pressed = false
		special_pressed = false
		input_x = 0.0
		input_y = 0.0

	var jump_consumed = _handle_invulnerability(delta)
	_handle_input_buffers(jump_pressed, dash_pressed, grounded)
	_handle_dash_start(input_x, input_y)
	_handle_attack_start(attack_pressed, input_y)
	_handle_parry_start(parry_pressed)
	_handle_special_start(special_pressed)
	_handle_checkpoint(grounded)

	var was_dashing := has_flag(Flag.DASHING)
	jump_consumed = _handle_dash_state(delta, jump_consumed)
	_handle_normal_movement(input_x, grounded, delta, was_dashing)

	jump_consumed = _handle_jump_execution(jump_pressed, jump_released, grounded, jump_consumed)
	_handle_run_jump_boost(input_x, delta)

	_handle_wall_cling_state(input_x, grounded)
	_handle_gravity(input_x, input_y, grounded, delta)

	was_on_floor = grounded

	jump_consumed = _handle_wall_jump(input_x, jump_pressed, grounded, jump_consumed)
	_handle_wall_jump_redirect(input_x)
	_handle_coyote_and_dash_refresh(input_x, input_y, grounded, delta)
	_update_timers(delta)

	sprite.flip_h = facing_direction == -1
	_update_animation()
	_update_attack_hitboxes()
	apply_corner_correction(delta, input_x)
	_handle_hazard_overlap()
	_apply_movement(delta)


func _sync_hitbox_visual_to_shape(shape: CollisionShape2D, visual: ColorRect) -> void:
	var rect_shape := shape.shape as RectangleShape2D
	if rect_shape == null:
		return
	visual.position = -rect_shape.size / 2.0
	visual.size = rect_shape.size


func _update_attack_hitboxes() -> void:
	var attacking := has_flag(Flag.ATTACKING)
	attack_hitbox_shape.disabled = not attacking
	attack_hitbox_visual.visible = attacking
	if attack_direction == Vector2.UP:
		attack_hitbox.position = Vector2(0.0, -attack_hitbox_vertical_offset)
		attack_hitbox.rotation = deg_to_rad(90.0)
	elif attack_direction == Vector2.DOWN:
		attack_hitbox.position = Vector2(0.0, attack_hitbox_vertical_offset)
		attack_hitbox.rotation = deg_to_rad(90.0)
	else:
		attack_hitbox.position = Vector2(attack_hitbox_horizontal_offset * facing_direction, 0.0)
		attack_hitbox.rotation = 0.0
	attack_hitbox.knockback_direction_override = attack_direction

	var specialing := has_flag(Flag.SPECIAL)
	special_hitbox_shape.disabled = not specialing
	special_hitbox_visual.visible = specialing
	special_hitbox.position.x = absf(special_hitbox.position.x) * facing_direction
	special_hitbox.knockback_direction_override = Vector2(facing_direction, 0.0)


func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if area.collision_layer & ENEMY_HURTBOX_LAYER:
		current_meter = mini(current_meter + 1, max_meter)
		Global.hitstop(attack_hitstop_duration)
	_apply_attack_hit_recoil()


func _on_attack_hitbox_body_entered(_body: Node) -> void:
	_apply_attack_hit_recoil()


func _apply_attack_hit_recoil() -> void:
	if _attack_recoil_applied:
		return
	_attack_recoil_applied = true

	if attack_direction == Vector2.DOWN:
		velocity.y = jump_velocity
	else:
		velocity += -attack_direction * attack_recoil_force


func _update_animation() -> void:
	if hit_flash_timer > 0.0:
		if sprite.animation != "hit":
			sprite.play("hit")
		return

	if sprite.animation == "dash" and sprite.is_playing():
		return

	var target := "idle"
	if abs(velocity.x) > 1.0:
		target = "run"

	if sprite.animation != target:
		sprite.play(target)


func _handle_invulnerability(delta: float) -> int:
	var invuln_color := Color.WHITE
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta
		invuln_color = Color.BLACK
	elif has_flag(Flag.HURT):
		set_flag(Flag.HURT, false)

	if sprite.self_modulate != invuln_color:
		sprite.self_modulate = invuln_color
	return 0


func _handle_input_buffers(jump_pressed: bool, dash_pressed: bool, grounded: bool) -> void:
	if dash_pressed:
		dash_buffer_timer = dash_buffer_time

	if jump_pressed:
		jump_buffered = true
		jump_buffer_timer = jump_buffer_time
		if not grounded:
			wall_jump_buffered = true
			wall_jump_buffer_timer = wall_jump_buffer_time


func _handle_dash_start(input_x: float, _input_y: float) -> void:
	if dash_buffer_timer <= 0.0 or not dash_available or dash_cooldown_timer > 0.0 or has_flag(Flag.DASHING | Flag.HURT):
		return

	var dash_dir := Vector2(sign(input_x), 0.0) if input_x != 0.0 else Vector2(facing_direction, 0.0)

	facing_direction = int(dash_dir.x)

	dash_direction = dash_dir
	dash_timer = dash_duration
	velocity.y = max(velocity.y, 0.0)
	velocity.x = dash_direction.x * dash_speed
	dash_available = false
	dash_buffer_timer = 0.0
	run_jump_boost_timer = 0.0
	set_flag(Flag.DASHING, true)
	sprite.play("dash", dash_animation_speed_mult)


func _handle_attack_start(attack_pressed: bool, input_y: float) -> void:
	if not attack_pressed or attack_cooldown_timer > 0.0 or has_flag(Flag.ATTACKING):
		return

	if has_flag(Flag.HURT | Flag.DEAD):
		return

	if input_y < -0.5:
		attack_direction = Vector2.UP
	elif input_y > 0.5 and not is_on_floor():
		attack_direction = Vector2.DOWN
	else:
		attack_direction = Vector2(facing_direction, 0.0)

	set_flag(Flag.ATTACKING, true)
	attack_state_timer = attack_duration
	attack_cooldown_timer = attack_cooldown
	_attack_recoil_applied = false


func _handle_parry_start(parry_pressed: bool) -> void:
	if not parry_pressed or parry_cooldown_timer > 0.0 or has_flag(Flag.PARRYING):
		return

	if has_flag(Flag.HURT | Flag.DEAD | Flag.DASHING | Flag.ATTACKING):
		return

	set_flag(Flag.PARRYING, true)
	parry_state_timer = parry_window_duration
	parry_cooldown_timer = parry_cooldown


func _handle_special_start(special_pressed: bool) -> void:
	if not special_pressed or has_flag(Flag.SPECIAL):
		return

	if current_meter < max_meter:
		return

	if has_flag(Flag.HURT | Flag.DEAD | Flag.DASHING | Flag.ATTACKING | Flag.PARRYING):
		return

	current_meter = 0
	set_flag(Flag.SPECIAL, true)
	special_state_timer = special_duration


func _handle_checkpoint(grounded: bool) -> void:
	if grounded and not has_flag(Flag.HURT | Flag.DEAD) and hazard_overlap_count == 0:
		Global.last_safe_position = global_position


func _handle_dash_state(delta: float, jump_consumed: int) -> int:
	if not has_flag(Flag.DASHING):
		return jump_consumed

	dash_timer -= delta

	var t: float = 1.0 - (dash_timer / dash_duration)
	var start_ease: float = smoothstep(0.0, dash_start_ease_window, t)
	var tail_ease: float = lerp(1.0, dash_tail_speed_mult, smoothstep(0.5, 1.0, t))
	var speed_mult: float = start_ease * tail_ease
	velocity.x = dash_direction.x * dash_speed * speed_mult

	if not dash_available and dash_timer <= dash_duration * dash_ledge_refill_window:
		_check_ledge_refill()

	if dash_timer <= 0.0:
		_end_dash()

	return jump_consumed


func _check_ledge_refill() -> void:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.new()
	params.from = global_position
	params.to = global_position + Vector2(0.0, dash_ledge_check_distance)
	params.exclude = [self]
	if space.intersect_ray(params):
		dash_available = true


func _end_dash() -> void:
	if not has_flag(Flag.DASHING):
		return

	set_flag(Flag.DASHING, false)
	dash_cooldown_timer = dash_cooldown
	dash_grace_timer = dash_grace_time


func _handle_normal_movement(input_x: float, grounded: bool, delta: float, was_dashing: bool) -> void:
	if has_flag(Flag.DASHING) or was_dashing:
		return

	if has_flag(Flag.PARRYING) and grounded:
		velocity.x = 0.0
		return

	var direction := input_x
	var accel := acceleration if grounded else air_acceleration
	var fric := friction if grounded else air_friction

	if direction != 0.0 and not has_flag(Flag.ATTACKING):
		facing_direction = int(sign(direction))

	var max_spd := max_speed if grounded else max_air_speed
	var target_speed := direction * max_spd

	if wall_jump_control_lock_timer > 0.0 or control_lock_timer > 0.0 or respawn_lock_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		return

	if direction != 0.0:
		if abs(velocity.x) > max_spd and sign(velocity.x) == sign(direction):
			velocity.x = move_toward(velocity.x, target_speed, fric * delta)
		else:
			velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


func _handle_jump_execution(_jump_pressed: bool, jump_released: bool, grounded: bool, jump_consumed: int) -> int:
	if jump_released and velocity.y < -100.0 and not has_flag(Flag.DASHING) and jump_cut_disabled_timer <= 0.0:
		velocity.y *= jump_cut_multiplier

	if not jump_buffered or jump_consumed:
		return jump_consumed

	if (grounded or coyote_timer > 0.0 or has_flag(Flag.DASHING)) and not has_flag(Flag.HURT):
		velocity.y = jump_velocity
		jump_buffered = false
		if not grounded and coyote_timer > 0.0:
			coyote_timer = 0.0

		if not has_flag(Flag.DASHING):
			var takeoff_speed_ratio: float = clampf(abs(velocity.x) / max_speed, 0.0, 1.0)
			var boost_amount := run_jump_speed_boost * takeoff_speed_ratio
			if boost_amount > 0.0:
				run_jump_boost_direction = int(sign(velocity.x)) if velocity.x != 0.0 else facing_direction
				run_jump_boost_start_speed = abs(velocity.x) + boost_amount
				run_jump_boost_timer = run_jump_boost_ease_duration

		set_flag(Flag.WALL_CLINGING, false)
		return 1

	return jump_consumed


func _handle_run_jump_boost(input_x: float, delta: float) -> void:
	if run_jump_boost_timer <= 0.0:
		return

	if has_flag(Flag.DASHING | Flag.HURT):
		run_jump_boost_timer = 0.0
		return

	if int(sign(input_x)) != run_jump_boost_direction:
		run_jump_boost_timer = 0.0
		return

	run_jump_boost_timer = maxf(run_jump_boost_timer - delta, 0.0)
	var t: float = 1.0 - (run_jump_boost_timer / run_jump_boost_ease_duration)
	var eased_speed: float = lerp(run_jump_boost_start_speed, max_air_speed, smoothstep(0.0, 1.0, t))
	velocity.x = run_jump_boost_direction * eased_speed


func _handle_wall_cling_state(input_x: float, grounded: bool) -> void:
	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	var locomotion_free := not has_flag(Flag.DASHING | Flag.WALL_CLINGING | Flag.HURT | Flag.DEAD | Flag.ATTACKING | Flag.PARRYING | Flag.SPECIAL) and wall_jump_control_lock_timer <= 0.0

	if not grounded and is_next_to_wall and velocity.y > 0.0 and pushing_into_wall and locomotion_free:
		set_flag(Flag.WALL_CLINGING, true)
	elif has_flag(Flag.WALL_CLINGING) and (grounded or not is_next_to_wall or not pushing_into_wall):
		set_flag(Flag.WALL_CLINGING, false)



func _handle_gravity(_input_x: float, _input_y: float, grounded: bool, delta: float) -> void:
	if has_flag(Flag.DASHING):
		var dash_grav_mult := dash_gravity_mult if velocity.y >= 0.0 else 1.0
		velocity.y += gravity * dash_grav_mult * delta
		return

	if grounded:
		return

	var gravity_mult := 1.0

	if abs(velocity.y) < apex_threshold:
		gravity_mult = apex_gravity_mult
	elif velocity.y > 0.0:
		gravity_mult = fall_gravity_mult

	if has_flag(Flag.WALL_CLINGING):
		gravity_mult *= wall_cling_gravity_mult
		velocity.y = min(velocity.y, wall_cling_max_fall_speed)

	velocity.y += gravity * gravity_mult * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _handle_wall_jump(input_x: float, _jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	var wall_available := is_next_to_wall or wall_coyote_timer > 0.0
	if not wall_jump_buffered or jump_consumed or not wall_available or grounded or has_flag(Flag.DASHING):
		return jump_consumed

	var effective_wall_normal := wall_normal if is_next_to_wall else last_wall_normal
	var push_direction := int(sign(effective_wall_normal.x))

	var pushing_into_wall := (
		(effective_wall_normal.x < 0.0 and input_x > 0.0)
		or
		(effective_wall_normal.x > 0.0 and input_x < 0.0)
	)

	var is_climb := has_flag(Flag.WALL_CLINGING) and pushing_into_wall

	if is_climb:
		velocity.x = push_direction * wall_climb_jump_push_force
		velocity.y = jump_velocity
	else:
		velocity.x = push_direction * wall_jump_push_force
		velocity.y = jump_velocity * 0.8

	wall_jump_redirect_timer = wall_jump_redirect_window
	wall_jump_redirect_push_direction = push_direction
	wall_jump_redirect_was_climb = is_climb

	jump_cut_disabled_timer = WALL_JUMP_CUT_DISABLE_TIME
	wall_jump_control_lock_timer = wall_jump_control_lock_time

	wall_jump_buffered = false
	jump_buffered = false
	jump_buffer_timer = 0.0
	run_jump_boost_timer = 0.0
	set_flag(Flag.WALL_CLINGING, false)
	coyote_timer = 0.0
	wall_coyote_timer = 0.0
	return 1


func _handle_wall_jump_redirect(input_x: float) -> void:
	if wall_jump_redirect_timer <= 0.0:
		return

	var held_dir := int(sign(input_x))
	if held_dir == 0:
		return

	if wall_jump_redirect_was_climb and held_dir == wall_jump_redirect_push_direction:
		velocity.x = wall_jump_redirect_push_direction * wall_jump_push_force
		velocity.y = jump_velocity * 0.8
		wall_jump_redirect_timer = 0.0
	elif not wall_jump_redirect_was_climb and held_dir == -wall_jump_redirect_push_direction:
		velocity.x = wall_jump_redirect_push_direction * wall_climb_jump_push_force
		velocity.y = jump_velocity
		wall_jump_redirect_timer = 0.0


func _handle_coyote_and_dash_refresh(_input_x: float, _input_y: float, grounded: bool, delta: float) -> void:
	if grounded:
		coyote_timer = coyote_time
		if not has_flag(Flag.DASHING):
			dash_available = true
		if not was_grounded_for_dash:
			dash_cooldown_timer = minf(dash_cooldown_timer, dash_land_cooldown)
	else:
		coyote_timer = tick_timer(coyote_timer, delta)

	was_grounded_for_dash = grounded

	if has_flag(Flag.WALL_CLINGING) and not was_wall_clinging:
		dash_available = true

	was_wall_clinging = has_flag(Flag.WALL_CLINGING)


func _update_timers(delta: float) -> void:
	if jump_buffered:
		jump_buffer_timer = tick_timer(jump_buffer_timer, delta)
		if jump_buffer_timer <= 0.0:
			jump_buffered = false

	if wall_jump_buffered:
		wall_jump_buffer_timer = tick_timer(wall_jump_buffer_timer, delta)
		if wall_jump_buffer_timer <= 0.0:
			wall_jump_buffered = false

	jump_cut_disabled_timer = tick_timer(jump_cut_disabled_timer, delta)
	dash_buffer_timer = tick_timer(dash_buffer_timer, delta)
	dash_cooldown_timer = tick_timer(dash_cooldown_timer, delta)
	dash_grace_timer = tick_timer(dash_grace_timer, delta)
	hit_flash_timer = tick_timer(hit_flash_timer, delta)

	wall_jump_control_lock_timer = tick_timer(wall_jump_control_lock_timer, delta)
	wall_coyote_timer = tick_timer(wall_coyote_timer, delta)
	wall_jump_redirect_timer = tick_timer(wall_jump_redirect_timer, delta)

	if control_lock_timer > 0.0:
		control_lock_timer = tick_timer(control_lock_timer, delta)

	if respawn_lock_timer > 0.0:
		respawn_lock_timer = tick_timer(respawn_lock_timer, delta)

	if attack_state_timer > 0.0:
		attack_state_timer = tick_timer(attack_state_timer, delta)
		if attack_state_timer <= 0.0:
			set_flag(Flag.ATTACKING, false)

	attack_cooldown_timer = tick_timer(attack_cooldown_timer, delta)

	if parry_state_timer > 0.0:
		parry_state_timer = tick_timer(parry_state_timer, delta)
		if parry_state_timer <= 0.0:
			set_flag(Flag.PARRYING, false)

	parry_cooldown_timer = tick_timer(parry_cooldown_timer, delta)
	parry_flash_timer = tick_timer(parry_flash_timer, delta)

	if special_state_timer > 0.0:
		special_state_timer = tick_timer(special_state_timer, delta)
		if special_state_timer <= 0.0:
			set_flag(Flag.SPECIAL, false)


func _apply_movement(delta: float) -> void:
	if has_flag(Flag.DASHING) and velocity.length() > 1.0:
		var next_pos := global_position + velocity * delta
		var space = get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = next_pos
		params.exclude = [self]
		params.collision_mask = 1  # world only — dash is invulnerable, shouldn't be stopped by enemies
		var hit = space.intersect_ray(params)
		if hit and hit.has("position"):
			var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
			var hit_is_wall: bool = abs(hit_normal.x) > 0.5 and abs(hit_normal.y) < 0.5
			if hit_is_wall:
				var hit_pos: Vector2 = hit.get("position")
				var safe_pos := hit_pos - velocity.normalized() * 2.0
				global_position = safe_pos
				velocity = Vector2.ZERO

				is_next_to_wall = true
				wall_normal = hit_normal
				last_wall_normal = hit_normal

				_end_dash()
				return

	if has_flag(Flag.DASHING):
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
		move_and_slide()
		motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	else:
		move_and_slide()
	update_wall_detection()

	if has_flag(Flag.DASHING):
		for i in range(get_slide_collision_count()):
			var collision := get_slide_collision(i)
			if not collision:
				continue
			var normal: Vector2 = collision.get_normal()
			var is_wall: bool = abs(normal.x) > 0.5 and abs(normal.y) < 0.5
			if is_wall and dash_direction.dot(normal) < -0.3:
				velocity = Vector2.ZERO
				_end_dash()
				break

	var target_modulate := Color.RED
	if parry_flash_timer > 0.0:
		target_modulate = Color.GREEN
	elif has_flag(Flag.PARRYING):
		target_modulate = Color(1.0, 0.85, 0.2)
	elif dash_available:
		target_modulate = Color.WHITE

	if sprite.modulate != target_modulate:
		sprite.modulate = target_modulate


func update_wall_detection() -> void:
	var was_next_to_wall := is_next_to_wall

	is_next_to_wall = false
	wall_normal = Vector2.ZERO

	var collision_count := get_slide_collision_count()

	for i in range(collision_count):
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		if abs(normal.x) > 0.5 and abs(normal.y) < 0.5:
			is_next_to_wall = true
			wall_normal = normal
			last_wall_normal = normal
			return

	if was_next_to_wall:
		wall_coyote_timer = wall_coyote_time


func apply_corner_correction(delta: float, input_x: float) -> void:
	if velocity.y >= 0.0:
		return

	var vertical_motion := Vector2(0.0, velocity.y * delta)

	if not test_move(global_transform, vertical_motion):
		return

	var preferred_dir := int(sign(input_x))

	if preferred_dir == 0:
		preferred_dir = int(sign(velocity.x))

	var directions := [1, -1]

	if preferred_dir != 0:
		directions = [preferred_dir, -preferred_dir]

	for amount in range(1, corner_correction_pixels + 1):
		for dir in directions:
			var offset := Vector2(dir * amount, 0.0)

			if test_move(global_transform, offset):
				continue

			var corrected_transform := global_transform
			corrected_transform.origin += offset

			if not test_move(corrected_transform, vertical_motion):
				global_position.x += offset.x
				return


func take_damage(amount: int = 1, knockback: Vector2 = Vector2.ZERO, lock_actions: bool = true) -> void:
	current_health = maxi(current_health - amount, 0)
	invulnerability_timer = invulnerability_duration
	if lock_actions:
		set_flag(Flag.HURT, true)
	hit_flash_timer = hit_flash_duration

	if knockback != Vector2.ZERO:
		velocity += knockback
		control_lock_timer = knockback_control_lock_time

	if current_health <= 0:
		dead()

func take_enemy_damage(amount: int = 1, knockback: Vector2 = Vector2.ZERO, source_hitbox: Area2D = null) -> void:
	if is_invulnerable():
		return

	var hitbox := source_hitbox as DamageHitbox
	var parryable := hitbox == null or hitbox.is_parryable

	if has_flag(Flag.PARRYING) and parryable:
		_on_parry_success(source_hitbox)
		return

	take_damage(amount, knockback, false)

func _on_parry_success(source_hitbox: Area2D = null) -> void:
	_parry_heal_accumulator += parry_heal_amount
	while _parry_heal_accumulator >= 1.0 and current_health < max_health:
		_parry_heal_accumulator -= 1.0
		current_health += 1

	parry_flash_timer = PARRY_FLASH_DURATION

	current_meter = mini(current_meter + 1, max_meter)

	if source_hitbox:
		var enemy := source_hitbox.get_parent() as Enemy
		if enemy:
			var knockback := Vector2.ZERO
			if parry_knockback_force > 0.0:
				var away_x := enemy.global_position.x - global_position.x
				var horizontal_dir := signf(away_x) if absf(away_x) > 1.0 else float(facing_direction)
				knockback = Vector2(horizontal_dir, -0.3) * parry_knockback_force
			enemy.take_damage(parry_damage, knockback)

func _on_hitbox_body_entered(_body: Node2D) -> void:
	hazard_hit()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is DamageHitbox:
		_resolve_enemy_hit(area)
	else:
		hazard_hit()


# Delayed by a brief hitstop (see Global.hitstop) before damage actually
# applies — that freeze doesn't stop this function's own frame from still
# running each real frame, so a parry pressed during it still sets
# Flag.PARRYING in time for take_enemy_damage()'s check below.
func _resolve_enemy_hit(hitbox: DamageHitbox) -> void:
	if is_invulnerable():
		return

	await Global.hitstop(enemy_hit_hitstop_duration)

	var knockback := Vector2.ZERO
	if hitbox.knockback_force > 0.0:
		var away_x := global_position.x - hitbox.global_position.x
		var horizontal_dir := signf(away_x) if absf(away_x) > 1.0 else float(-facing_direction)
		knockback = Vector2(horizontal_dir, -hitbox.knockback_vertical_ratio) * hitbox.knockback_force
	take_enemy_damage(hitbox.damage, knockback, hitbox)

func hazard_hit() -> void:
	if is_invulnerable():
		return

	take_damage(1)

	if not has_flag(Flag.DEAD):
		respawn()

func _handle_hazard_overlap() -> void:
	if hazard_overlap_count > 0 and not is_invulnerable():
		hazard_hit()

func respawn() -> void:
	global_position = Global.last_safe_position
	velocity = Vector2.ZERO
	set_flag(Flag.HURT, false)

	invulnerability_timer = invulnerability_duration

	jump_buffered = false
	jump_buffer_timer = 0.0
	wall_jump_buffered = false
	wall_jump_buffer_timer = 0.0
	dash_buffer_timer = 0.0
	dash_cooldown_timer = 0.0

	respawn_lock_timer = respawn_lock_time

	Engine.time_scale = 0.85
	await get_tree().create_timer(0.15 / Engine.time_scale).timeout
	Engine.time_scale = 1.0

func dead() -> void:
	if has_flag(Flag.DEAD):
		return

	set_flag(Flag.DEAD, true)
	set_flag(Flag.HURT, false)
	current_health = max_health
	Global.death_count += 1
	Global.did_just_die = true
	Engine.time_scale = 0.7
	timer.start()

func _on_timer_timeout() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func tick_timer(time_value: float, delta: float) -> float:
	return maxf(time_value - delta, 0.0)

func _on_hazard_area_entered(_area: Area2D) -> void:
	if _area is DamageHitbox:
		return
	hazard_overlap_count += 1

func _on_hazard_area_exited(_area: Area2D) -> void:
	if _area is DamageHitbox:
		return
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)

func _on_hazard_body_entered(_body: Node2D) -> void:
	hazard_overlap_count += 1

func _on_hazard_body_exited(_body: Node2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)
