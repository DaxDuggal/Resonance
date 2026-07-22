extends CharacterBody2D
class_name Player


enum PlayerState {
	NORMAL,
	DASHING,
	WALL_BOUNCING,
	HURT,
	DEAD
}

enum DashType {
	BASIC,
	PANFLUTE,
	BONGOS
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
	set_dash_ability(current_dash)

	# Ensure a GrappleRay RayCast2D exists for the player (used by panflute dash)
	if not has_node("GrappleRay"):
		var rc := RayCast2D.new()
		rc.name = "GrappleRay"
		rc.enabled = false
		add_child(rc)
		# Optional: set collision mask/layers in editor if needed


func set_dash_ability(dash_type: DashType) -> void:
	var dash_script: GDScript

	match dash_type:
		DashType.BASIC:
			dash_script = preload("res://scripts/abilities/basicDash.gd")
		DashType.PANFLUTE:
			dash_script = preload("res://scripts/abilities/panfluteDash.gd")
		DashType.BONGOS:
			dash_script = preload("res://scripts/abilities/bongosDash.gd")

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
@export var jump_velocity := -300.0
@export var gravity := 750.0
@export var max_fall_speed := 400.0
@export var jump_cut_multiplier := 0.4
@export var apex_threshold := 40.0
@export var apex_gravity_mult := 0.85
@export var fall_gravity_mult := 1.2
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


# ========== LANDING LAG ==========

@export_group("Landing Lag")
@export var landing_lag_time := 0.18
@export var landing_min_fall_speed := 350.0
@export var landing_control_factor := 0.5

var landing_lag_timer := 0.0
var was_on_floor := false
var fall_speed := 0.0


# ========== WALL CLING ==========

@export_group("Wall")
@export var wall_cling_gravity_mult := 0.4
@export var wall_cling_max_fall_speed := 120.0

var is_next_to_wall := false
var wall_normal := Vector2.ZERO


# ========== WALL BOUNCE ==========

@export var wall_bounce_velocity := -270.0
@export var wall_bounce_push_force := 190.0
@export var wall_jump_push_force := 190.0
@export var wall_bounce_window_time := 0.2
@export var wall_bounce_control_lock_time := 0.12

var wall_bounce_window_timer := 0.0
var wall_bounce_normal := Vector2.ZERO
var wall_bounce_control_lock_timer := 0.0
var control_lock_timer := 0.0  # general purpose input/control lock (used by panflute recoil, etc.)


# ========== ASSISTS ==========

@export_group("Assists")
@export var corner_correction_pixels := 4


func _physics_process(delta: float) -> void:
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")

	var jump_pressed := Input.is_action_just_pressed("jump")
	var jump_released := Input.is_action_just_released("jump")
	var dash_pressed := Input.is_action_just_pressed("dash")

	var jump_consumed := false
	var grounded := is_on_floor()

	# Prevent input while dead
	if state == PlayerState.DEAD:
		dash_pressed = false
		jump_pressed = false
		input_x = 0.0

	# ========== INPUT BUFFERS ==========

	if dash_pressed:
		dash_buffer_timer = dash_buffer_time

	if jump_pressed:
		if not (state == PlayerState.DASHING and not grounded) or is_next_to_wall:
			jump_buffered = true
			jump_buffer_timer = wavedash_buffer_time if wavedash_buffer_timer > 0.0 else jump_buffer_time
		# Buffer wall jump if next to wall and not grounded
		if is_next_to_wall and not grounded:
			wall_jump_buffered = true
			wall_jump_buffer_timer = wall_jump_buffer_time


	# ========== DASH START ==========

	if dash_buffer_timer > 0.0 and dash_available and state != PlayerState.DASHING:
		var dash_dir := Vector2(input_x, input_y)

		if dash_dir == Vector2.ZERO:
			dash_dir = Vector2(facing_direction, 0)

		if dash_dir.x != 0.0:
			facing_direction = int(sign(dash_dir.x))

		if dash_ability.can_start(self):
			dash_ability.start_dash(self, dash_dir)
			dash_buffer_timer = 0.0


	# ========== DASH / NORMAL MOVEMENT ==========

	if state == PlayerState.DASHING:
		dash_ability.update_dash(self, delta)

		# Compute wavedash possibility first so a jump press this frame triggers wavedash
		var wavedash_possible := false
		if dash_ability.allows_wavedash:
			var wavedash_dir := dash_ability.get_wavedash_direction()
			if wavedash_dir.y > 0.0 and wavedash_dir.x != 0.0 and grounded:
				wavedash_window_timer = wavedash_input_window
				wavedash_possible = true

		# Allow interrupting the dash with a jump if the dash ability supports it,
		# but don't interrupt if a grounded wavedash is possible this frame.
		if jump_pressed and not jump_consumed:
			if dash_ability.has_method("interrupt_with_jump") and dash_ability.allows_jump_interrupt and not wavedash_possible:
				dash_ability.interrupt_with_jump(self)
				jump_consumed = true
				jump_buffered = false

	else:
		var direction := input_x
		var accel := acceleration if grounded else air_acceleration
		var fric := friction if grounded else air_friction

		if direction != 0.0:
			facing_direction = int(sign(direction))

		if landing_lag_timer > 0.0:
			accel *= landing_control_factor
			fric *= landing_control_factor

		var max_spd := max_speed if grounded else max_air_speed
		var target_speed := direction * max_spd

		if wall_bounce_control_lock_timer <= 0.0 and control_lock_timer <= 0.0:
			if direction != 0.0:
				if abs(velocity.x) > max_spd and sign(velocity.x) == sign(direction):
					velocity.x = move_toward(velocity.x, target_speed, accel * 0.25 * delta)
				else:
					velocity.x = move_toward(velocity.x, target_speed, accel * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, fric * delta)
		else:
			# Controls are locked; apply friction toward current facing or zero
			velocity.x = move_toward(velocity.x, 0.0, fric * delta)


	# ========== WAVEDASH ==========

	if wavedash_window_timer > 0.0 and jump_pressed and not jump_consumed:
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

		jump_consumed = true
		jump_buffered = false


	# ========== JUMP EXECUTION ==========

	if jump_buffered and (grounded or coyote_timer > 0.0) and not (state == PlayerState.DASHING and not grounded):
		velocity.y = jump_velocity

		jump_buffered = false
		# Only clear coyote if it was actually used (grace jump)
		if not grounded and coyote_timer > 0.0:
			coyote_timer = 0.0
		landing_lag_timer = 0.0
		state = PlayerState.NORMAL


	# ========== VARIABLE JUMP HEIGHT ==========

	if jump_released and velocity.y < -100.0 and state != PlayerState.DASHING and jump_cut_disabled_timer <= 0.0:
		velocity.y *= jump_cut_multiplier


	# ========== GRAVITY ==========
	
	# Skip gravity while DASHING so dash velocity isn't pulled down slightly
	if not grounded and state != PlayerState.DASHING:
		var gravity_mult := 1.0
	
		if abs(velocity.y) < apex_threshold:
			gravity_mult = apex_gravity_mult
	
		elif velocity.y > 0.0:
			gravity_mult = fall_gravity_mult
	
			if can_fast_fall and input_y > 0.0 and abs(input_x) < 0.1:
				gravity_mult *= fast_fall_gravity_mult
	
		var pushing_into_wall := (
			(wall_normal.x < 0.0 and input_x > 0.0)
			or
			(wall_normal.x > 0.0 and input_x < 0.0)
		)
	
		if is_next_to_wall and velocity.y > 0.0 and pushing_into_wall:
			gravity_mult *= wall_cling_gravity_mult
			velocity.y = min(velocity.y, wall_cling_max_fall_speed)
	
		velocity.y += gravity * gravity_mult * delta
		velocity.y = min(velocity.y, max_fall_speed)
	

	# ========== LANDING LAG ==========

	if grounded and not was_on_floor:
		if fall_speed >= landing_min_fall_speed and state != PlayerState.DASHING:
			landing_lag_timer = landing_lag_time

	was_on_floor = grounded


	# ========== WALL DETECTION ==========
	# (moved to after movement so slide collisions are from the current move_and_slide)

	if dash_ability.allows_wall_bounce and is_next_to_wall and not grounded:
		if state == PlayerState.DASHING:
			var wall_bounce_dir := dash_ability.get_wall_bounce_direction()
			if wall_bounce_dir.y < 0.0:
				wall_bounce_window_timer = wall_bounce_window_time
				wall_bounce_normal = wall_normal
		else:
			# Even after dash ends, keep window open if still next to wall
			if wall_bounce_window_timer <= 0.0:
				wall_bounce_window_timer = 0.15
				wall_bounce_normal = wall_normal


	# ========== WALL JUMP ==========

	if wall_jump_buffered and not jump_consumed and is_next_to_wall and not grounded and state != PlayerState.DASHING:
		var push_direction := int(sign(wall_normal.x))
		velocity.x = push_direction * wall_jump_push_force
		velocity.y = jump_velocity * 0.9

		jump_cut_disabled_timer = WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		wall_bounce_control_lock_timer = wall_bounce_control_lock_time

		wall_jump_buffered = false
		state = PlayerState.WALL_BOUNCING
		coyote_timer = 0.0
		jump_consumed = true


	# ========== WALL BOUNCE ==========

	# Check both active dash bounce window and post-dash bounce window
	var can_wall_bounce := (wall_bounce_window_timer > 0.0 and dash_ability.dash_direction.y < 0.0) or post_dash_bounce_timer > 0.0

	if jump_pressed and not jump_consumed and can_wall_bounce and is_next_to_wall:
		dash_ability.cancel_dash(self)

		var push_direction := int(sign(wall_bounce_normal.x))
		velocity.x = push_direction * wall_bounce_push_force
		# Boost upward velocity for diagonal bounces to make them feel better
		var bounce_vel := wall_bounce_velocity
		if abs(dash_ability.dash_direction.x) > 0.1:
			bounce_vel -= 150.0  # Extra upward boost for diagonal
		velocity.y = bounce_vel

		jump_cut_disabled_timer = WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		wall_bounce_control_lock_timer = wall_bounce_control_lock_time

		jump_buffered = false
		dash_available = true
		state = PlayerState.WALL_BOUNCING
		coyote_timer = 0.0
		wall_bounce_window_timer = 0.0
		post_dash_bounce_timer = 0.0
		jump_consumed = true


	# ========== COYOTE / DASH REFRESH ==========

	if grounded:
		coyote_timer = coyote_time
		dash_available = true
		can_fast_fall = false

	else:
		coyote_timer = tick_timer(coyote_timer, delta)

		if input_y <= 0.0:
			can_fast_fall = true


	# ========== TIMERS ==========

	if jump_buffered:
		jump_buffer_timer = tick_timer(jump_buffer_timer, delta)

		if jump_buffer_timer <= 0.0:
			jump_buffered = false

	if wall_jump_buffered:
		wall_jump_buffer_timer = tick_timer(wall_jump_buffer_timer, delta)

		if wall_jump_buffer_timer <= 0.0:
			wall_jump_buffered = false

	landing_lag_timer = tick_timer(landing_lag_timer, delta)
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

	# general control lock timer (used by panflute recoil and others)
	if control_lock_timer > 0.0:
		control_lock_timer = tick_timer(control_lock_timer, delta)


	# ========== SPRITE ==========

	sprite.flip_h = facing_direction == -1


	# ========== CORNER CORRECTION ==========

	apply_corner_correction(delta, input_x)


	# ========== APPLY MOVEMENT ==========

	fall_speed = velocity.y
	# Before moving, perform a segment check ahead for dash movement to avoid sliding past thin platforms
	if state == PlayerState.DASHING and dash_ability and is_instance_valid(dash_ability) and dash_ability.is_active and velocity.length() > 1.0:
		var next_pos := global_position + velocity * get_physics_process_delta_time()
		var space = get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = next_pos
		params.exclude = [self]
		var hit = space.intersect_ray(params)
		if hit and hit.has("position"):
			# Move the player to just before the collision point to avoid passing through
			var hit_pos: Vector2 = hit.get("position")
			var safe_pos := hit_pos - velocity.normalized() * 2.0
			global_position = safe_pos
			# Zero velocity immediately
			velocity = Vector2.ZERO
			# Let ability handle the collision; it accepts either a Dictionary (from intersect_ray) or a slide collision
			if dash_ability.has_method("handle_slide_collision"):
				dash_ability.handle_slide_collision(self, hit)
			# Skip calling move_and_slide this frame since we've already positioned the body
			return

	move_and_slide()

	# After movement, update wall detection (uses slide collisions just generated)
	update_wall_detection()

	# If we just slid into something while DASHING, let certain dash abilities react immediately.
	if state == PlayerState.DASHING and dash_ability and is_instance_valid(dash_ability) and dash_ability.is_active:
		var collision_count := get_slide_collision_count()
		if collision_count > 0:
			for i in range(collision_count):
				var collision := get_slide_collision(i)
				if collision and dash_ability.has_method("handle_slide_collision"):
					var normal := collision.get_normal()
					# Use the actual movement vector (dash_velocity when available) so collisions
					# that oppose the player's motion trigger even if the dash target lies beyond.
					var mdir := Vector2.ZERO
					if dash_ability.dash_velocity.length() > 0.001:
						mdir = dash_ability.dash_velocity.normalized()
					else:
						mdir = dash_ability.dash_direction.normalized()
					# Trigger if the collision surface opposes the movement direction
					if mdir.dot(normal) < -0.3:
						# For grapple dash (PanfluteDash), zero momentum immediately so player
						# doesn't slide past the surface, then let the ability handle recoil.
						if dash_ability is PanfluteDash:
							velocity = Vector2.ZERO
							dash_ability.handle_slide_collision(self, collision)
						else:
							dash_ability.handle_slide_collision(self, collision)
						break

	# Set wavedash window if landed from downward dash (after move_and_slide so is_on_floor() is updated)
	if is_on_floor() and not was_on_floor and state == PlayerState.DASHING and dash_ability.dash_direction.y > 0.0:
		wavedash_window_timer = wavedash_input_window

	# Color sprite based on dash state
	if state == PlayerState.DASHING:
		sprite.modulate = Color.CYAN
	elif dash_available:
		sprite.modulate = Color.WHITE
	else:
		sprite.modulate = Color.RED


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

# ============ Death ==========
func _on_hitbox_body_entered(_body):
		state = PlayerState.DEAD
		dead()

func _on_hurtbox_area_entered(_area):
		state = PlayerState.DEAD
		dead()

func dead() -> void:
	Engine.time_scale = 0.7
	timer.start()

func _on_timer_timeout():
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
