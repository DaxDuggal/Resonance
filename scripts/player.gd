extends CharacterBody2D
class_name Player


enum PlayerState {
	NORMAL,
	DASHING,
	WALL_BOUNCING,
	WALL_CLINGING,
	HURT,
	DEAD
}

enum DashType {
	BASIC,
	PANFLUTE,
	BONGOS,
	CONCHSHELL
}

var state: PlayerState = PlayerState.NORMAL
@export var current_dash: DashType = DashType.BASIC

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var dash_ability: DashAbility = $Abilities/DashAbility
@onready var timer: Timer = $Timer

# Debug drawing for dash raycasts using a Line2D child named DashDebugLine
func show_dash_debug(target: Vector2) -> void:
	var local_target := to_local(target)
	var line: Line2D = null
	if has_node("DashDebugLine"):
		line = $DashDebugLine
	else:
		line = Line2D.new()
		line.name = "DashDebugLine"
		line.width = 2
		line.default_color = Color(1.0, 1.0, 1.0, 1.0)
		add_child(line)

	line.visible = true
	line.points = [Vector2.ZERO, local_target]

func clear_dash_debug() -> void:
	if has_node("DashDebugLine"):
		$DashDebugLine.visible = false

func _ready() -> void:
	Global.player = self
	current_health = max_health
	Global.last_safe_position = global_position
	# Restore dash type from global (persists across deaths)
	current_dash = Global.current_dash_type
	set_dash_ability(current_dash)

	# Add hurtbox to player_hitbox group so respawn zones can detect it
	if has_node("Hurtbox"):
		$Hurtbox.add_to_group("player_hitbox")
		# Track if we're overlapping any hazards (for safe-position checkpointing)
		if not $Hurtbox.is_connected("area_entered", Callable(self, "_on_hazard_area_entered")):
			$Hurtbox.connect("area_entered", Callable(self, "_on_hazard_area_entered"))
		if not $Hurtbox.is_connected("area_exited", Callable(self, "_on_hazard_area_exited")):
			$Hurtbox.connect("area_exited", Callable(self, "_on_hazard_area_exited"))


func set_dash_ability(dash_type: DashType) -> void:
	var dash_script: GDScript

	match dash_type:
		DashType.BASIC:
			dash_script = preload("res://scripts/abilities/basicDash.gd")
		DashType.PANFLUTE:
			dash_script = preload("res://scripts/abilities/panfluteDash.gd")
		DashType.BONGOS:
			dash_script = preload("res://scripts/abilities/bongosDash.gd")
		DashType.CONCHSHELL:
			dash_script = preload("res://scripts/abilities/conchshell.gd")

	# Remove old dash ability if it exists
	if dash_ability and is_instance_valid(dash_ability):
		var parent := dash_ability.get_parent()
		parent.remove_child(dash_ability)
		dash_ability.queue_free()

	# Instantiate and add the new dash ability
	dash_ability = dash_script.new()
	$Abilities.add_child(dash_ability)
	dash_ability.name = "DashAbility"
	current_dash = dash_type
	Global.current_dash_type = dash_type  # Save for persistence across deaths



# ========== HEALTH ==========

@export_group("Health")
@export var max_health := 3
var current_health := 3
var invulnerability_timer := 0.0
@export var invulnerability_duration := 1.0

# ========== MOVEMENT ==========

@export_group("Movement")
@export var max_speed := 150.0
@export var max_air_speed := 140.0
@export var acceleration := 1200.0
@export var air_acceleration := 900.0
@export var friction := 1800.0
@export var air_friction := 300.0


# ========== JUMP / GRAVITY ==========

@export_group("Jump / Gravity")
@export var jump_velocity := -320.0
@export var gravity := 880.0
@export var max_fall_speed := 400.0
@export var jump_cut_multiplier := 0.4
@export var apex_threshold := 40.0
@export var apex_gravity_mult := 0.85
@export var fall_gravity_mult := 1.0
@export var fast_fall_gravity_mult := 1.5

var jump_cut_disabled_timer := 0.0
var can_fast_fall := false

const WALL_BOUNCE_JUMP_CUT_DISABLE_TIME := 0.2


# ========== COYOTE / BUFFER ==========

@export_group("Coyote / Buffer")
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.1
@export var dash_buffer_time := 0.1

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_buffered := false
var dash_buffer_timer := 0.0


# ========== DASH ==========

var dash_available := true
var facing_direction := 1

# ========== WALL JUMP BUFFER ==========
var wall_jump_buffered := false
var wall_jump_buffer_timer := 0.0
@export var wall_jump_buffer_time := 0.1

# ========== POST-DASH WALL BOUNCE ==========
var post_dash_bounce_timer := 0.0
const POST_DASH_BOUNCE_WINDOW := 0.15  # Window after upward dash ends to allow wall bounce


# ========== WAVEDASH ==========

@export_group("Wavedash")
@export var wavedash_input_window := 0.2
@export var wavedash_buffer_time := 0.2
@export var wavedash_speed_mult := 1.2
@export var wavedash_jump_velocity := -250.0

var wavedash_window_timer := 0.0
var wavedash_buffer_timer := 0.0


var was_on_floor := false


# ========== WALL CLING ==========

@export_group("Wall")
@export var wall_cling_gravity_mult := 0.4
@export var wall_cling_max_fall_speed := 120.0

var is_next_to_wall := false
var wall_normal := Vector2.ZERO


# ========== WALL BOUNCE ==========

@export var wall_bounce_velocity := -300.0
@export var wall_bounce_push_force := 210.0
@export var wall_jump_push_force := 200.0
@export var wall_bounce_window_time := 0.2
@export var wall_bounce_control_lock_time := 0.12

var wall_bounce_window_timer := 0.0
var wall_bounce_normal := Vector2.ZERO
var wall_bounce_control_lock_timer := 0.0
var control_lock_timer := 0.0  # general purpose input/control lock (used by panflute recoil, etc.)
# Delayed boost back into the wall so the player can climb (Hollow Knight style)
@export var wall_climb_boost_force := 80.0
@export var wall_climb_boost_delay := 0.08

var wall_climb_boost_timer := 0.0
var wall_climb_boost_direction := 0

# Track if we're currently overlapping any hazards (for safe checkpoint logic)
var hazard_overlap_count := 0

# Delayed velocity clamp (used by bongosDash interrupt for clamping bounce height)
var velocity_clamp_timer := 0.0
var velocity_clamp_value := 0.0

# Lock input for a moment after respawning (Hollow Knight style)
@export var respawn_lock_time := 0.2
var respawn_lock_timer := 0.0


# ========== ASSISTS ==========

@export_group("Assists")
@export var corner_correction_pixels := 4


func _physics_process(delta: float) -> void:
	# Read input once per frame
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var jump_released := Input.is_action_just_released("jump")
	var dash_pressed := Input.is_action_just_pressed("dash")

	var grounded := is_on_floor()

	# Prevent input while dead
	if state == PlayerState.DEAD:
		dash_pressed = false
		jump_pressed = false
		jump_released = false
		input_x = 0.0
		input_y = 0.0

	# Execution order matters: wall bounce → dash/wavedash → jump → movement → gravity
	var jump_consumed = _handle_invulnerability(delta)
	_handle_input_buffers(jump_pressed, dash_pressed, grounded)
	_handle_dash_start(input_x, input_y)
	_handle_checkpoint(grounded)

	jump_consumed = _handle_dash_state(delta, input_x, input_y, jump_pressed, grounded, jump_consumed)
	_handle_normal_movement(input_x, grounded, delta)

	jump_consumed = _handle_wavedash(input_x, jump_pressed, grounded, jump_consumed)
	jump_consumed = _handle_jump_execution(jump_pressed, jump_released, grounded, jump_consumed)

	_handle_wall_cling_state(input_x, grounded)
	_handle_wall_climb_boost(delta)
	_handle_velocity_clamp(delta)
	_handle_gravity(input_x, input_y, grounded, delta)

	was_on_floor = grounded

	jump_consumed = _handle_wall_jump(input_x, jump_pressed, grounded, jump_consumed)
	_handle_coyote_and_dash_refresh(input_x, input_y, grounded, delta)
	_update_timers(delta)

	# Update visuals
	sprite.flip_h = facing_direction == -1
	apply_corner_correction(delta, input_x)
	_apply_movement(delta)


func _handle_invulnerability(delta: float) -> int:
	var invuln_color := Color.WHITE
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta
		invuln_color = Color.BLACK
	elif state == PlayerState.HURT:
		state = PlayerState.NORMAL

	if sprite.self_modulate != invuln_color:
		sprite.self_modulate = invuln_color
	return 0


func _handle_input_buffers(jump_pressed: bool, dash_pressed: bool, grounded: bool) -> void:
	if dash_pressed:
		dash_buffer_timer = dash_buffer_time

	if jump_pressed:
		if not (state == PlayerState.DASHING and not grounded) or is_next_to_wall:
			jump_buffered = true
			jump_buffer_timer = wavedash_buffer_time if wavedash_buffer_timer > 0.0 else jump_buffer_time
		if is_next_to_wall and not grounded:
			wall_jump_buffered = true
			wall_jump_buffer_timer = wall_jump_buffer_time


func _handle_dash_start(input_x: float, input_y: float) -> void:
	if dash_buffer_timer > 0.0 and dash_available and state != PlayerState.DASHING and state != PlayerState.HURT:
		var dash_dir := Vector2(input_x, input_y)

		if dash_dir == Vector2.ZERO:
			dash_dir = Vector2(facing_direction, 0)

		if dash_dir.x != 0.0:
			facing_direction = int(sign(dash_dir.x))

		if dash_ability.can_start(self):
			dash_ability.start_dash(self, dash_dir)
			dash_buffer_timer = 0.0


func _handle_checkpoint(grounded: bool) -> void:
	if grounded and state != PlayerState.HURT and state != PlayerState.DEAD and hazard_overlap_count == 0:
		Global.last_safe_position = global_position


func _handle_dash_state(delta: float, input_x: float, input_y: float, jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	if state != PlayerState.DASHING:
		return jump_consumed

	dash_ability.update_dash(self, delta)

	# Wall bounce takes priority
	var wall_bounce_from_window := wall_bounce_window_timer > 0.0 or post_dash_bounce_timer > 0.0
	if jump_pressed and not jump_consumed and wall_bounce_from_window and dash_ability.dash_direction.y < 0.0:
		dash_ability.cancel_dash(self)
		var push_direction := int(sign(wall_bounce_normal.x))
		velocity.x = push_direction * wall_bounce_push_force
		var bounce_vel := wall_bounce_velocity
		if abs(dash_ability.dash_direction.x) > 0.1:
			bounce_vel -= 20.0
		velocity.y = bounce_vel
		jump_cut_disabled_timer = WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		wall_bounce_control_lock_timer = wall_bounce_control_lock_time
		jump_buffered = false
		state = PlayerState.WALL_BOUNCING
		coyote_timer = 0.0
		wall_bounce_window_timer = 0.0
		post_dash_bounce_timer = 0.0
		return 1

	# Check if wavedash is possible
	var wavedash_possible := false
	if dash_ability.allows_wavedash:
		var wavedash_dir := dash_ability.get_wavedash_direction()
		if wavedash_dir.y > 0.0 and abs(wavedash_dir.x) > 0.1 and grounded:
			wavedash_window_timer = wavedash_input_window
			wavedash_possible = true

	# Allow jump interrupt if able
	if jump_pressed and not jump_consumed:
		if dash_ability.has_method("interrupt_with_jump") and dash_ability.allows_jump_interrupt and not wavedash_possible:
			dash_ability.interrupt_with_jump(self)
			return 1

	return jump_consumed


func _handle_normal_movement(input_x: float, grounded: bool, delta: float) -> void:
	if state == PlayerState.DASHING:
		return

	var direction := input_x
	var accel := acceleration if grounded else air_acceleration
	var fric := friction if grounded else air_friction

	if direction != 0.0:
		facing_direction = int(sign(direction))

	var max_spd := max_speed if grounded else max_air_speed
	var target_speed := direction * max_spd

	if wall_bounce_control_lock_timer <= 0.0 and control_lock_timer <= 0.0 and respawn_lock_timer <= 0.0:
		if direction != 0.0:
			if abs(velocity.x) > max_spd and sign(velocity.x) == sign(direction):
				velocity.x = move_toward(velocity.x, target_speed, accel * 0.25 * delta)
			else:
				velocity.x = move_toward(velocity.x, target_speed, accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, fric * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fric * delta)


func _handle_wavedash(input_x: float, jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	if wavedash_window_timer <= 0.0 or not jump_pressed or jump_consumed:
		return jump_consumed

	dash_ability.cancel_dash(self)

	var dash_dir := dash_ability.get_wavedash_direction()
	var wavedash_direction := input_x if input_x != 0.0 else dash_dir.x
	var capped_dash_vel: float = min(dash_ability.dash_velocity.length(), 350.0)
	var wavedash_speed := capped_dash_vel * wavedash_speed_mult

	velocity.x = wavedash_direction * wavedash_speed
	velocity.y = wavedash_jump_velocity

	coyote_timer = 0.0
	dash_available = true
	wavedash_window_timer = 0.0
	wavedash_buffer_timer = wavedash_buffer_time

	jump_buffered = false
	return 1


func _handle_jump_execution(jump_pressed: bool, jump_released: bool, grounded: bool, jump_consumed: int) -> int:
	if jump_released and velocity.y < -100.0 and state != PlayerState.DASHING and jump_cut_disabled_timer <= 0.0:
		velocity.y *= jump_cut_multiplier

	if not jump_buffered or jump_consumed:
		return jump_consumed

	if (grounded or coyote_timer > 0.0) and not (state == PlayerState.DASHING and not grounded) and state != PlayerState.HURT:
		velocity.y = jump_velocity
		jump_buffered = false
		if not grounded and coyote_timer > 0.0:
			coyote_timer = 0.0
		state = PlayerState.NORMAL
		return 1

	return jump_consumed


func _handle_wall_cling_state(input_x: float, grounded: bool) -> void:
	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	if not grounded and is_next_to_wall and velocity.y > 0.0 and pushing_into_wall and state == PlayerState.NORMAL:
		state = PlayerState.WALL_CLINGING
	elif state == PlayerState.WALL_CLINGING and (grounded or not is_next_to_wall or not pushing_into_wall):
		state = PlayerState.NORMAL


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
	if grounded or state == PlayerState.DASHING:
		return

	var gravity_mult := 1.0

	if abs(velocity.y) < apex_threshold:
		gravity_mult = apex_gravity_mult
	elif velocity.y > 0.0:
		gravity_mult = fall_gravity_mult
		if can_fast_fall and input_y > 0.0 and abs(input_x) < 0.1:
			gravity_mult *= fast_fall_gravity_mult

	if state == PlayerState.WALL_CLINGING:
		gravity_mult *= wall_cling_gravity_mult
		velocity.y = min(velocity.y, wall_cling_max_fall_speed)

	velocity.y += gravity * gravity_mult * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _handle_wall_jump(input_x: float, jump_pressed: bool, grounded: bool, jump_consumed: int) -> int:
	if not wall_jump_buffered or jump_consumed or not is_next_to_wall or grounded or state == PlayerState.DASHING:
		return jump_consumed

	var push_direction := int(sign(wall_normal.x))
	velocity.x = push_direction * wall_jump_push_force
	velocity.y = jump_velocity * 0.8

	var pushing_into_wall := (
		(wall_normal.x < 0.0 and input_x > 0.0)
		or
		(wall_normal.x > 0.0 and input_x < 0.0)
	)

	if state == PlayerState.WALL_CLINGING and pushing_into_wall:
		velocity.y = jump_velocity
		wall_climb_boost_timer = wall_climb_boost_delay
		wall_climb_boost_direction = push_direction

	jump_cut_disabled_timer = WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
	wall_bounce_control_lock_timer = wall_bounce_control_lock_time

	wall_jump_buffered = false
	state = PlayerState.WALL_BOUNCING
	coyote_timer = 0.0
	return 1


func _handle_coyote_and_dash_refresh(input_x: float, input_y: float, grounded: bool, delta: float) -> void:
	if grounded:
		coyote_timer = coyote_time
		var dashing_upward := state == PlayerState.DASHING and dash_ability.dash_direction.y < 0.0
		if not dashing_upward:
			dash_available = true
		can_fast_fall = false
		wall_climb_boost_timer = 0.0
	else:
		coyote_timer = tick_timer(coyote_timer, delta)
		if input_y <= 0.0:
			can_fast_fall = true


func _update_timers(delta: float) -> void:
	if jump_buffered:
		jump_buffer_timer = tick_timer(jump_buffer_timer, delta)
		if jump_buffer_timer <= 0.0:
			jump_buffered = false

	if wall_jump_buffered:
		wall_jump_buffer_timer = tick_timer(wall_jump_buffer_timer, delta)
		if wall_jump_buffer_timer <= 0.0:
			wall_jump_buffered = false

	wavedash_window_timer = tick_timer(wavedash_window_timer, delta)
	wavedash_buffer_timer = tick_timer(wavedash_buffer_timer, delta)
	wall_bounce_window_timer = tick_timer(wall_bounce_window_timer, delta)
	post_dash_bounce_timer = tick_timer(post_dash_bounce_timer, delta)
	jump_cut_disabled_timer = tick_timer(jump_cut_disabled_timer, delta)
	dash_buffer_timer = tick_timer(dash_buffer_timer, delta)

	if wall_bounce_control_lock_timer > 0.0:
		wall_bounce_control_lock_timer = tick_timer(wall_bounce_control_lock_timer, delta)
		if wall_bounce_control_lock_timer <= 0.0 and state == PlayerState.WALL_BOUNCING:
			state = PlayerState.NORMAL

	if control_lock_timer > 0.0:
		control_lock_timer = tick_timer(control_lock_timer, delta)

	if respawn_lock_timer > 0.0:
		respawn_lock_timer = tick_timer(respawn_lock_timer, delta)


func _apply_movement(delta: float) -> void:
	# Early exit for dash collision check
	if state == PlayerState.DASHING and is_instance_valid(dash_ability) and dash_ability.is_active and velocity.length() > 1.0:
		var next_pos := global_position + velocity * delta
		var space = get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = next_pos
		params.exclude = [self]
		var hit = space.intersect_ray(params)
		if hit and hit.has("position"):
			var hit_pos: Vector2 = hit.get("position")
			var safe_pos := hit_pos - velocity.normalized() * 2.0
			global_position = safe_pos
			velocity = Vector2.ZERO

			var hit_normal: Vector2 = hit.get("normal", Vector2.ZERO)
			if abs(hit_normal.x) > 0.5 and abs(hit_normal.y) < 0.5:
				is_next_to_wall = true
				wall_normal = hit_normal
			else:
				is_next_to_wall = false
				wall_normal = Vector2.ZERO

			dash_ability.handle_slide_collision(self, hit)
			return

	move_and_slide()
	update_wall_detection()

	# Handle dash collisions after movement
	if state == PlayerState.DASHING and is_instance_valid(dash_ability) and dash_ability.is_active:
		var mdir := dash_ability.dash_direction.normalized()
		if dash_ability.dash_velocity.length() > 0.001:
			mdir = dash_ability.dash_velocity.normalized()

		for i in range(get_slide_collision_count()):
			var collision := get_slide_collision(i)
			if not collision:
				continue
			if mdir.dot(collision.get_normal()) < -0.3:
				if dash_ability is PanfluteDash:
					velocity = Vector2.ZERO
				dash_ability.handle_slide_collision(self, collision)
				break

	# Wavedash window on landing
	if is_on_floor() and not was_on_floor and state == PlayerState.DASHING and dash_ability.dash_direction.y > 0.0:
		wavedash_window_timer = wavedash_input_window

	# Update sprite color
	var target_modulate := Color.RED
	if state == PlayerState.DASHING:
		target_modulate = Color.CYAN
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
	state = PlayerState.HURT

	if current_health <= 0:
		dead()

func take_enemy_damage(amount: int = 1) -> void:
	# Enemy damage is blocked by invulnerability, hazard damage is not.
	# Used when you add enemies to the game.
	if invulnerability_timer > 0.0:
		return
	take_damage(amount)

func _on_hitbox_body_entered(_body: Node2D) -> void:
	hazard_hit()

func _on_hurtbox_area_entered(_area: Area2D) -> void:
	hazard_hit()

func hazard_hit() -> void:
	# Hazards deal 1 damage and respawn at last safe checkpoint.
	# Dying only happens when health hits zero (Hollow Knight / Nine Sols style).
	if invulnerability_timer > 0.0:
		return

	take_damage(1)

	# If the player survives the hit, respawn at the last safe position.
	# If health reached zero, take_damage() already called dead().
	if current_health > 0:
		respawn()

func respawn() -> void:
	# Teleport to last safe position, reset state but keep health
	global_position = Global.last_safe_position
	velocity = Vector2.ZERO
	state = PlayerState.NORMAL

	# Clear invulnerability so the player can be hit again if they fall back into the hazard
	invulnerability_timer = 0.0

	# Lock input for a moment so the player can reorient (Hollow Knight style)
	respawn_lock_timer = respawn_lock_time

	# Brief slow-motion effect on respawn (like death, but less severe)
	Engine.time_scale = 0.85
	await get_tree().create_timer(0.15 / Engine.time_scale).timeout
	Engine.time_scale = 1.0

func dead() -> void:
	# Guard against re-entry (e.g. two hazards overlapping in the same frame)
	if state == PlayerState.DEAD:
		return

	state = PlayerState.DEAD
	current_health = max_health
	Engine.time_scale = 0.7
	timer.start()

func _on_timer_timeout() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func tick_timer(time_value: float, delta: float) -> float:
	return maxf(time_value - delta, 0.0)

func enter_dash_state() -> void:
	state = PlayerState.DASHING

func exit_dash_state() -> void:
	if state == PlayerState.DASHING:
		state = PlayerState.NORMAL
		# If dash was upward, open a window for wall bounces after dash ends
		if dash_ability.dash_direction.y < 0.0:
			# Longer window for panflute to make wall bounces easier
			if dash_ability is PanfluteDash:
				post_dash_bounce_timer = 0.5
			else:
				post_dash_bounce_timer = POST_DASH_BOUNCE_WINDOW

func _on_hazard_area_entered(_area: Area2D) -> void:
	hazard_overlap_count += 1

func _on_hazard_area_exited(_area: Area2D) -> void:
	hazard_overlap_count = maxi(hazard_overlap_count - 1, 0)
