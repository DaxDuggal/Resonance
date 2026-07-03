extends CharacterBody2D

# States

enum Player {
	NORMAL,
	DASHING,
	WALL_BOUNCING,
}

var state: Player = Player.NORMAL

# Movement constants
@onready var sprite := $AnimatedSprite2D
const MAX_SPEED = 150.0
const MAX_AIR_SPEED = 140.0
const ACCELERATION = 1200.0
const AIR_ACCELERATION = 900.0
const FRICTION = 1200.0
const AIR_FRICTION = 300.0
const JUMP_VELOCITY = -300.0
const CORNER_CORRECTION_PIXELS := 4
const GRAVITY = 750.0
const MAX_FALL_SPEED = 350.0  # Maximum downward velocity
const FAST_FALL_GRAVITY_MULT := 1.5
var can_fast_fall: bool = false

# Dash
const DASH_SPEED = 350.0
const DASH_DURATION = 0.2
const DASH_END_SPEED = 180.0   # Carry-over momentum
var dash_available: bool = true
var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var facing_direction: int = 1  # 1 for right, -1 for left
var dash_speed: float = DASH_SPEED # Balance supers and hypers
const DASH_BUFFER_TIME = 0.1
var dash_buffer_timer: float = 0.0

# Wavedash
const WAVEDASH_INPUT_WINDOW = 0.20  # Percent of a second
var wavedash_window_timer: float = 0.0
const WAVEDASH_BUFFER_TIME = 0.2  # Extra buffer time after wavedash
var wavedash_buffer_timer: float = 0.0

# Variable Jump Height
const JUMP_CUT_MULTIPLIER = 0.4  # Lower = shorter min jump
var jump_cut_disabled_timer: float = 0.0
const WALL_BOUNCE_JUMP_CUT_DISABLE_TIME = 0.2

# Coyote Time
const COYOTE_TIME = 0.15
var coyote_timer: float = 0.0
 
# Jump Buffering
const JUMP_BUFFER_TIME = 0.1
var jump_buffer_timer: float = 0.0
var jump_buffered: bool = false

# Apex Hang
const APEX_THRESHOLD = 40.0     # How close to the top of the jump counts as "apex"
const APEX_GRAVITY_MULT = 0.75   # Lower = floatier apex

# Assymetric Gravity
const FALL_GRAVITY_MULT = 1.2  # Higher = snappier falls (1.5–2.2)

# Landing lag
const LANDING_LAG_TIME = 0.25
const LANDING_MIN_FALL_SPEED = 325.0
const LANDING_CONTROL_FACTOR = 0.33    # Control during lag (0=none, 1=full)
var landing_lag_timer: float = 0.0
var was_on_floor: bool = false
var fall_speed: float = 0.0

# Wall Cling
const WALL_CLING_GRAVITY_MULT = 0.4  # Slows fall speed when on wall
var is_next_to_wall: bool = false
var wall_normal: Vector2 = Vector2.ZERO


# Wall Bounce
const WALL_BOUNCE_VELOCITY = -325.0  # Upward velocity
const WALL_BOUNCE_PUSH_FORCE = 200.0  # Push away from wall
const WALL_BOUNCE_WINDOW_TIME = 0.2
const wall_bounce_control_lock_time := 0.12
var wall_bounce_control_lock_timer: float = 0.0
var wall_bounce_window_timer: float = 0.0
var wall_bounce_normal: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_up", "move_down")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var jump_released := Input.is_action_just_released("jump")
	var dash_pressed := Input.is_action_just_pressed("dash")
	var grounded := is_on_floor()
	
	var jump_consumed := false
	
	if dash_pressed:
		dash_buffer_timer = DASH_BUFFER_TIME
	
	# ========== DASH ==========
	if dash_buffer_timer > 0.0 and dash_available and state != Player.DASHING:
		start_dash(Vector2(input_x, input_y))
	
	if state == Player.DASHING:
		dash_timer -= delta
		velocity = dash_direction * dash_speed
		
	# ========== WAVEDASH ==========
		if dash_direction.y > 0 and dash_direction.x != 0 and grounded:
			wavedash_window_timer = WAVEDASH_INPUT_WINDOW
	
			# Wavedash triggers if jump is pressed within the window
		if wavedash_window_timer > 0 and jump_pressed and not jump_consumed:
			state = Player.NORMAL
			
			var wavedash_speed = dash_speed * 1.1
			var wavedash_jump_velocity = -250.0
			
			var wavedash_direction = input_x if input_x != 0 else dash_direction.x
			
			velocity.x = wavedash_direction * wavedash_speed
			velocity.y = wavedash_jump_velocity
			coyote_timer = 0.0
			dash_available = true
			wavedash_window_timer = 0.0
			wavedash_buffer_timer = WAVEDASH_BUFFER_TIME
			jump_consumed = true
			jump_buffered = false
	
	# ========== DASH ==========
		elif dash_timer <= 0:
			end_dash()
	else:
		
		# ========== HORIZONTAL MOVEMENT ==========
		var direction := input_x
		var accel := ACCELERATION if grounded else AIR_ACCELERATION
		var fric := FRICTION if grounded else AIR_FRICTION
		
		# Update facing direction when moving
		if direction != 0:
			facing_direction = int(sign(direction))
		
		# During landing lag, soften control instead of forcing a stop
		if landing_lag_timer > 0:
			accel *= LANDING_CONTROL_FACTOR
			fric *= LANDING_CONTROL_FACTOR
		
		var max_spd: float = MAX_SPEED if grounded else MAX_AIR_SPEED
		var target_speed := direction * max_spd
		
		if wall_bounce_control_lock_timer <= 0.0:
			if direction != 0:
				if abs(velocity.x) > max_spd and sign(velocity.x) == sign(direction):
					velocity.x = move_toward(velocity.x, target_speed, accel * 0.25 * delta)
				else:
					velocity.x = move_toward(velocity.x, target_speed, accel * delta)
			else:
				velocity.x = move_toward(velocity.x, 0, fric * delta)
	
	# ========== JUMP BUFFER ==========
	if jump_pressed and not jump_consumed:
		if not (state == Player.DASHING and not grounded) or is_next_to_wall:
			jump_buffered = true
			jump_buffer_timer = WAVEDASH_BUFFER_TIME if wavedash_buffer_timer > 0.0 else JUMP_BUFFER_TIME
	
	# ========== JUMP EXECUTION ==========
	# Execute immediately if we land/can jump, regardless of when buffered
	if jump_buffered and (grounded or coyote_timer > 0) and not (state == Player.DASHING and not grounded):
		velocity.y = JUMP_VELOCITY
		jump_buffered = false
		coyote_timer = 0.0
		landing_lag_timer = 0.0
		state = Player.NORMAL
	# Variable Jump Height
	if jump_released and velocity.y < -100 and state != Player.DASHING and jump_cut_disabled_timer <= 0.0:
		velocity.y *= JUMP_CUT_MULTIPLIER
	
	# ========== GRAVITY ==========
	if not grounded:
		var gravity_mult := 1.0
		if abs(velocity.y) < APEX_THRESHOLD:
			gravity_mult = APEX_GRAVITY_MULT
		elif velocity.y > 0:
			gravity_mult = FALL_GRAVITY_MULT
			if can_fast_fall and input_y > 0 and abs(input_x) < 0.1:
				gravity_mult *= FAST_FALL_GRAVITY_MULT
		
		var pushing_into_wall = (
			(wall_normal.x < 0 and input_x > 0) or
			(wall_normal.x > 0 and input_x < 0)
		)
		
		# ========== WALL CLING ==========
		if is_next_to_wall and velocity.y > 0 and pushing_into_wall:
			gravity_mult *= WALL_CLING_GRAVITY_MULT # +
			velocity.y = min(velocity.y, 120.0)
			
		velocity.y += GRAVITY * gravity_mult * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
		
	# ========== LANDING LAG ==========
	
	if grounded and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED and state != Player.DASHING:
			landing_lag_timer = LANDING_LAG_TIME
			
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
	
	was_on_floor = grounded
	
	# ========== WALL DETECTION ==========
	# Check if next to a wall
	var collision_count = get_slide_collision_count()
	is_next_to_wall = false
	if collision_count > 0:
		for i in range(collision_count):
			var collision = get_slide_collision(i)
			var normal = collision.get_normal()
			# Wall collision is when normal is mostly horizontal
			if abs(normal.x) > 0.5 and abs(normal.y) < 0.5:
				is_next_to_wall = true
				wall_normal = normal
				break
	
	# ========== WALL BOUNCE ==========
	if is_next_to_wall and not grounded and state == Player.DASHING and dash_direction.y < 0 and jump_pressed:
		wall_bounce_window_timer = WALL_BOUNCE_WINDOW_TIME
		wall_bounce_normal = wall_normal
		var push_direction = int(sign(wall_normal.x))
		velocity.x = push_direction * WALL_BOUNCE_PUSH_FORCE
		velocity.y = WALL_BOUNCE_VELOCITY
		
		jump_cut_disabled_timer = WALL_BOUNCE_JUMP_CUT_DISABLE_TIME
		wall_bounce_control_lock_timer = wall_bounce_control_lock_time
		state = Player.WALL_BOUNCING
		
		jump_buffered = false
		dash_available = true
		state = Player.NORMAL
		coyote_timer = 0.0
		wall_bounce_window_timer = 0.0
		jump_consumed = true
	
	# ========== COYOTE TIME ==========
	if grounded:
		dash_available = true
		coyote_timer = COYOTE_TIME
		can_fast_fall = true
	else:
		coyote_timer -= delta
		if input_y <= 0:
			can_fast_fall = true
		
	
	if jump_buffered:
		jump_buffer_timer -= delta
		if jump_buffer_timer <= 0:
			jump_buffered = false
	
	if wall_bounce_control_lock_timer > 0.0:
		wall_bounce_control_lock_timer -= delta
		if wall_bounce_control_lock_timer <= 0.0 and state == Player.WALL_BOUNCING:
			state = Player.NORMAL
	
	if dash_buffer_timer > 0.0:
		dash_buffer_timer -= delta
	
	if wavedash_buffer_timer > 0.0:
		wavedash_buffer_timer -= delta
	
	if wavedash_window_timer > 0:
		wavedash_window_timer -= delta
	
	if wall_bounce_window_timer > 0.0:
		wall_bounce_window_timer -= delta
	
	if jump_cut_disabled_timer > 0.0:
		jump_cut_disabled_timer -= delta
	
	# ========== SPRITE FLIP ==========
	sprite.flip_h = facing_direction == -1
	
	# ========== APPLY MOVEMENT ==========
	fall_speed = velocity.y
	move_and_slide()

func start_dash(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		dir = Vector2(facing_direction, 0)
	elif dir.x != 0:
		facing_direction = int(sign(dir.x))
	
	dash_direction = dir.normalized()
	state = Player.DASHING
	dash_timer = DASH_DURATION
	dash_available = false
	dash_buffer_timer = 0.0
	landing_lag_timer = 0.0

func end_dash() -> void:
	state = Player.NORMAL
	velocity.x = dash_direction.x * DASH_END_SPEED
	
	if dash_direction.y < 0:
		velocity.y *= 0.5

func apply_corner_correction(delta: float, input_x: float) -> void:
	# Only correct while moving upward.
	if velocity.y >= 0.0:
		return
	
	var vertical_motion := Vector2(0.0, velocity.y * delta)
	
	# Only try correction if our upward motion would hit something.
	if not test_move(global_transform, vertical_motion):
		return
	
	var preferred_dir := int(sign(input_x))
	
	if preferred_dir == 0:
		preferred_dir = int(sign(velocity.x))
	
	var directions := [1, -1]
	
	if preferred_dir != 0:
		directions = [preferred_dir, -preferred_dir]
	
	for amount in range(1, CORNER_CORRECTION_PIXELS + 1):
		for dir in directions:
			var offset := Vector2(dir * amount, 0.0)
	
			# First check that we can move sideways into this correction position.
			if test_move(global_transform, offset):
				continue
	
			# Then check that upward movement would be clear from that corrected position.
			var corrected_transform := global_transform
			corrected_transform.origin += offset
	
			if not test_move(corrected_transform, vertical_motion):
				global_position.x += offset.x
				return
