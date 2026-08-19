extends CharacterBody2D
class_name Player


# Bitflags instead of a single mutually-exclusive state: several of these can
# be true at once (e.g. ATTACKING while airborne, or HURT while DASHING was
# just true a moment ago). WALL_JUMPING isn't here — that was never a real
# state, just wall_jump_control_lock_timer wearing a costume; check the timer
# directly instead.
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

# Invulnerability has multiple sources (hit-flash, dash, dash grace) — one
# place to check all of them instead of repeating the combo everywhere.
func is_invulnerable() -> bool:
	return invulnerability_timer > 0.0 or dash_grace_timer > 0.0 or has_flag(Flag.DASHING)

func is_airborne() -> bool:
	return not is_on_floor()

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer

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
		# Tile-based hazards (TileMapLayer collision) enter as bodies, not
		# areas — area_entered/exited alone missed them entirely, so
		# hazard_overlap_count never saw tile spikes as "occupied."
		if not $Hurtbox.is_connected("body_entered", Callable(self, "_on_hazard_body_entered")):
			$Hurtbox.connect("body_entered", Callable(self, "_on_hazard_body_entered"))
		if not $Hurtbox.is_connected("body_exited", Callable(self, "_on_hazard_body_exited")):
			$Hurtbox.connect("body_exited", Callable(self, "_on_hazard_body_exited"))


# ========== HEALTH ==========

@export_group("Health")
@export var max_health := 3
var current_health := 3
var invulnerability_timer := 0.0
@export var invulnerability_duration := 1.0

# ========== ATTACK ==========

@export_group("Attack")
@export var attack_damage := 1
@export var attack_duration := 0.25
@export var attack_cooldown := 0.4

var attack_state_timer := 0.0
var attack_cooldown_timer := 0.0

# ========== PARRY ==========

@export_group("Parry")
@export var parry_window_duration := 0.2
@export var parry_cooldown := 0.5
@export var parry_heal_amount := 0.25

var parry_state_timer := 0.0
var parry_cooldown_timer := 0.0
var _parry_heal_accumulator := 0.0

var parry_flash_timer := 0.0
const PARRY_FLASH_DURATION := 0.15

# ========== METER ==========

@export_group("Meter")
@export var max_meter := 5
var current_meter := 0

# ========== SPECIAL ==========

@export_group("Special")
@export var special_damage := 3
@export var special_duration := 0.4

var special_state_timer := 0.0

# ========== MOVEMENT ==========

@export_group("Movement")
@export var max_speed := 200.0
@export var max_air_speed := 200.0
@export var acceleration := 1200.0
@export var air_acceleration := 1100.0
@export var friction := 1800.0
@export var air_friction := 300.0


# ========== JUMP / GRAVITY ==========

@export_group("Jump / Gravity")
@export var jump_velocity := -300.0
@export var gravity := 900.0
@export var max_fall_speed := 500.0
@export var jump_cut_multiplier := 0.4
@export var apex_threshold := 40.0
@export var apex_gravity_mult := 0.9
@export var fall_gravity_mult := 1.0
@export var fast_fall_gravity_mult := 1.5

var jump_cut_disabled_timer := 0.0
var can_fast_fall := false

const WALL_JUMP_CUT_DISABLE_TIME := 0.2


# ========== COYOTE / BUFFER ==========

@export_group("Coyote / Buffer")
@export var coyote_time := 0.05
@export var jump_buffer_time := 0.1
@export var dash_buffer_time := 0.1

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_buffered := false
var dash_buffer_timer := 0.0


# ========== DASH ==========
# Single horizontal dash. Refills on ground touch or wall-cling entry, plus a
# small fixed cooldown so a refill can't chain instantly into another dash.

@export_group("Dash")
@export var dash_speed := 700.0
@export var dash_duration := 0.1
@export var dash_cooldown := 0.05
@export var dash_grace_time := 0.1  # invuln grace after the dash ends
@export var dash_gravity_mult := 0.75  # slight softening of gravity during the dash
@export var dash_burst_speed_mult := 1.6  # speed multiplier right at dash start — the snap
@export var dash_burst_window := 0.15  # fraction of the dash where the burst decays back to normal
@export var dash_snap_power := 4.0  # higher = the burst decays back to normal faster
@export var dash_tail_speed_mult := 0.6  # horizontal speed eases to this fraction by dash end
@export var dash_ledge_refill_window := 0.3  # last fraction of the dash that checks for a ledge below
@export var dash_ledge_check_distance := 10.0  # pixels below the player to check

var dash_available := true
var dash_direction := Vector2.ZERO
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_grace_timer := 0.0
var facing_direction := 1

# ========== WALL JUMP BUFFER ==========
var wall_jump_buffered := false
var wall_jump_buffer_timer := 0.0
@export var wall_jump_buffer_time := 0.1


var was_on_floor := false


# ========== WALL CLING ==========

@export_group("Wall")
@export var wall_cling_gravity_mult := 0.4
@export var wall_cling_max_fall_speed := 120.0

var is_next_to_wall := false
var was_wall_clinging := false
var wall_normal := Vector2.ZERO


# ========== WALL JUMP ==========

@export var wall_jump_push_force := 200.0
@export var wall_jump_control_lock_time := 0.12

var wall_jump_control_lock_timer := 0.0
var control_lock_timer := 0.0
@export var wall_climb_boost_force := 80.0
@export var wall_climb_boost_delay := 0.08

var wall_climb_boost_timer := 0.0
var wall_climb_boost_direction := 0

var hazard_overlap_count := 0

var velocity_clamp_timer := 0.0
var velocity_clamp_value := 0.0

@export var respawn_lock_time := 0.4
var respawn_lock_timer := 0.0


# ========== ASSISTS ==========

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

	# Execution order matters: dash → jump → movement → gravity
	var jump_consumed = _handle_invulnerability(delta)
	_handle_input_buffers(jump_pressed, dash_pressed, grounded)
	_handle_dash_start(input_x, input_y)
	_handle_attack_start(attack_pressed)
	_handle_parry_start(parry_pressed)
	_handle_special_start(special_pressed)
	_handle_checkpoint(grounded)

	jump_consumed = _handle_dash_state(delta, jump_consumed)
	_handle_normal_movement(input_x, grounded, delta)

	jump_consumed = _handle_jump_execution(jump_pressed, jump_released, grounded, jump_consumed)

	_handle_wall_cling_state(input_x, grounded)
	_handle_wall_climb_boost(delta)
	_handle_velocity_clamp(delta)
	_handle_gravity(input_x, input_y, grounded, delta)

	was_on_floor = grounded

	jump_consumed = _handle_wall_jump(input_x, jump_pressed, grounded, jump_consumed)
	_handle_coyote_and_dash_refresh(input_x, input_y, grounded, delta)
	_update_timers(delta)

	sprite.flip_h = facing_direction == -1
	apply_corner_correction(delta, input_x)
	_handle_hazard_overlap()
	_apply_movement(delta)


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
		if not (has_flag(Flag.DASHING) and not grounded) or is_next_to_wall:
			jump_buffered = true
			jump_buffer_timer = jump_buffer_time
		if not grounded:
			wall_jump_buffered = true
			wall_jump_buffer_timer = wall_jump_buffer_time


func _handle_dash_start(input_x: float, _input_y: float) -> void:
	if dash_buffer_timer <= 0.0 or not dash_available or dash_cooldown_timer > 0.0 or has_flag(Flag.DASHING | Flag.HURT):
		return

	# Horizontal-only: vertical input is ignored for dash direction.
	var dash_dir := Vector2(sign(input_x), 0.0) if input_x != 0.0 else Vector2(facing_direction, 0.0)

	facing_direction = int(dash_dir.x)

	dash_direction = dash_dir
	dash_timer = dash_duration
	velocity = dash_direction * dash_speed
	dash_available = false
	dash_buffer_timer = 0.0
	set_flag(Flag.DASHING, true)


func _handle_attack_start(attack_pressed: bool) -> void:
	if not attack_pressed or attack_cooldown_timer > 0.0 or has_flag(Flag.ATTACKING):
		return

	if has_flag(Flag.HURT | Flag.DEAD):
		return

	# Attacking is allowed to overlap a dash (dash-slash) — it no longer
	# needs to check or touch the DASHING flag to coexist with it.
	set_flag(Flag.ATTACKING, true)
	attack_state_timer = attack_duration
	attack_cooldown_timer = attack_cooldown


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
	var speed_mult: float

	if t < dash_burst_window:
		# Elastic snap: decays quickly from the burst back down to normal
		# dash speed, all within the first dash_burst_window fraction.
		var burst_t: float = t / dash_burst_window
		var eased_burst: float = 1.0 - pow(1.0 - burst_t, dash_snap_power)
		speed_mult = lerp(dash_burst_speed_mult, 1.0, eased_burst)
	else:
		# Same as before the burst was added: holds full speed, then eases
		# toward dash_tail_speed_mult over the 2nd half.
		speed_mult = lerp(1.0, dash_tail_speed_mult, smoothstep(0.5, 1.0, t))

	velocity.x = dash_direction.x * dash_speed * speed_mult

	# Near the end of the dash only — not the whole thing, so dashing while
	# already grounded doesn't just refill instantly. This is what lets a
	# dash that ends right at/near a ledge keep its charge, without letting
	# two dashes chain across a gap that should only take one.
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


func _handle_normal_movement(input_x: float, grounded: bool, delta: float) -> void:
	if has_flag(Flag.DASHING):
		return

	var direction := input_x
	var accel := acceleration if grounded else air_acceleration
	var fric := friction if grounded else air_friction

	if direction != 0.0:
		facing_direction = int(sign(direction))

	var max_spd := max_speed if grounded else max_air_speed
	var target_speed := direction * max_spd

	if wall_jump_control_lock_timer > 0.0 or control_lock_timer > 0.0 or respawn_lock_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		return

	if direction != 0.0:
		velocity.x = move_toward(velocity.x, target_speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


func _handle_jump_execution(_jump_pressed: bool, jump_released: bool, grounded: bool, jump_consumed: int) -> int:
	if jump_released and velocity.y < -100.0 and not has_flag(Flag.DASHING) and jump_cut_disabled_timer <= 0.0:
		velocity.y *= jump_cut_multiplier

	if not jump_buffered or jump_consumed:
		return jump_consumed

	if (grounded or coyote_timer > 0.0) and not (has_flag(Flag.DASHING) and not grounded) and not has_flag(Flag.HURT):
		velocity.y = jump_velocity
		jump_buffered = false
		if not grounded and coyote_timer > 0.0:
			coyote_timer = 0.0
		# This is the only thing "state = NORMAL" was actually doing here —
		# ending a wall-cling on jump. Nothing else could be active at this
		# point (DASHING/HURT are excluded above; DEAD short-circuits earlier).
		set_flag(Flag.WALL_CLINGING, false)
		return 1

	return jump_consumed


func _handle_wall_cling_state(input_x: float, grounded: bool) -> void:
	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	# Equivalent to the old "state == NORMAL" gate: nothing else exclusive
	# is currently happening, including a wall-jump's control-lock window.
	var locomotion_free := not has_flag(Flag.DASHING | Flag.WALL_CLINGING | Flag.HURT | Flag.DEAD | Flag.ATTACKING | Flag.PARRYING | Flag.SPECIAL) and wall_jump_control_lock_timer <= 0.0

	if not grounded and is_next_to_wall and velocity.y > 0.0 and pushing_into_wall and locomotion_free:
		set_flag(Flag.WALL_CLINGING, true)
	elif has_flag(Flag.WALL_CLINGING) and (grounded or not is_next_to_wall or not pushing_into_wall):
		set_flag(Flag.WALL_CLINGING, false)


func _handle_wall_climb_boost(delta: float) -> void:
	if wall_climb_boost_timer > 0.0:
		wall_climb_boost_timer -= delta
		if wall_climb_boost_timer <= 0.0:
			velocity.x -= wall_climb_boost_direction * wall_climb_boost_force


func _handle_velocity_clamp(delta: float) -> void:
	if velocity_clamp_timer > 0.0:
		velocity_clamp_timer -= delta
		if velocity_clamp_timer <= 0.0 and not is_on_floor():
			if velocity_clamp_value < 0.0 and velocity.y < velocity_clamp_value:
				velocity.y = velocity_clamp_value
			elif velocity_clamp_value > 0.0 and velocity.y > velocity_clamp_value:
				velocity.y = velocity_clamp_value


func _handle_gravity(input_x: float, input_y: float, grounded: bool, delta: float) -> void:
	if has_flag(Flag.DASHING):
		# No upward kick — velocity.y starts at whatever the dash zeroed it
		# to. Gravity applies the whole dash, slightly softened.
		velocity.y += gravity * dash_gravity_mult * delta
		return

	if grounded:
		return

	var gravity_mult := 1.0

	if abs(velocity.y) < apex_threshold:
		gravity_mult = apex_gravity_mult
	elif velocity.y > 0.0:
		gravity_mult = fall_gravity_mult
		if can_fast_fall and input_y > 0.0 and abs(input_x) < 0.1:
			gravity_mult *= fast_fall_gravity_mult

	if has_flag(Flag.WALL_CLINGING):
		gravity_mult *= wall_cling_gravity_mult
		velocity.y = min(velocity.y, wall_cling_max_fall_speed)

	velocity.y += gravity * gravity_mult * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _handle_wall_jump(input_x: float, _jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	if not wall_jump_buffered or jump_consumed or not is_next_to_wall or grounded or has_flag(Flag.DASHING):
		return jump_consumed

	var push_direction := int(sign(wall_normal.x))
	velocity.x = push_direction * wall_jump_push_force
	velocity.y = jump_velocity * 0.8

	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	if has_flag(Flag.WALL_CLINGING) and pushing_into_wall:
		velocity.y = jump_velocity
		wall_climb_boost_timer = wall_climb_boost_delay
		wall_climb_boost_direction = push_direction

	jump_cut_disabled_timer = WALL_JUMP_CUT_DISABLE_TIME
	wall_jump_control_lock_timer = wall_jump_control_lock_time

	wall_jump_buffered = false
	set_flag(Flag.WALL_CLINGING, false)
	coyote_timer = 0.0
	return 1


func _handle_coyote_and_dash_refresh(_input_x: float, input_y: float, grounded: bool, delta: float) -> void:
	if grounded:
		coyote_timer = coyote_time
		if not has_flag(Flag.DASHING):
			dash_available = true
		can_fast_fall = false
		wall_climb_boost_timer = 0.0
	else:
		coyote_timer = tick_timer(coyote_timer, delta)
		if input_y <= 0.0:
			can_fast_fall = true

	# Refills on entering wall-cling specifically, not any wall touch.
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

	wall_jump_control_lock_timer = tick_timer(wall_jump_control_lock_timer, delta)

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
	# Only wall-like hits cut the dash short; floor/ceiling hits fall through to move_and_slide().
	if has_flag(Flag.DASHING) and velocity.length() > 1.0:
		var next_pos := global_position + velocity * delta
		var space = get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = next_pos
		params.exclude = [self]
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

				_end_dash()
				return

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
	elif has_flag(Flag.DASHING):
		target_modulate = Color.CYAN
	elif has_flag(Flag.PARRYING):
		target_modulate = Color(1.0, 0.85, 0.2)
	elif dash_available:
		target_modulate = Color.WHITE

	if sprite.modulate != target_modulate:
		sprite.modulate = target_modulate


func update_wall_detection() -> void:
	is_next_to_wall = false
	wall_normal = Vector2.ZERO

	var collision_count := get_slide_collision_count()

	for i in range(collision_count):
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()

		if abs(normal.x) > 0.5 and abs(normal.y) < 0.5:
			is_next_to_wall = true
			wall_normal = normal
			return


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

# ============ Death / Health ==========
func take_damage(amount: int = 1) -> void:
	current_health = maxi(current_health - amount, 0)
	invulnerability_timer = invulnerability_duration
	set_flag(Flag.HURT, true)

	if current_health <= 0:
		dead()

func take_enemy_damage(amount: int = 1) -> void:
	if is_invulnerable():
		return

	if has_flag(Flag.PARRYING):
		_on_parry_success()
		return

	take_damage(amount)

func _on_parry_success() -> void:
	_parry_heal_accumulator += parry_heal_amount
	while _parry_heal_accumulator >= 1.0 and current_health < max_health:
		_parry_heal_accumulator -= 1.0
		current_health += 1

	parry_flash_timer = PARRY_FLASH_DURATION

	current_meter = mini(current_meter + 1, max_meter)

func _on_hitbox_body_entered(_body: Node2D) -> void:
	hazard_hit()

func _on_hitbox_area_entered(_area: Area2D) -> void:
	hazard_hit()

func hazard_hit() -> void:
	if is_invulnerable():
		return

	take_damage(1)

	if not has_flag(Flag.DEAD):
		respawn()

# The enter signals only fire once, on first contact — if invulnerability
# was still active at that exact moment (e.g. dashing into a hazard), the
# hit was silently swallowed and nothing re-checked afterward. This catches
# hazards the player is still standing in the instant invulnerability ends.
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
	hazard_overlap_count += 1

func _on_hazard_area_exited(_area: Area2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)

func _on_hazard_body_entered(_body: Node2D) -> void:
	hazard_overlap_count += 1

func _on_hazard_body_exited(_body: Node2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)
