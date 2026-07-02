extends CharacterBody2D

# Movement constants
@onready var sprite := $AnimatedSprite2D
const MAX_SPEED = 150.0
const MAX_AIR_SPEED = 140.0
const ACCELERATION = 1200.0
const AIR_ACCELERATION = 900.0
const FRICTION = 1200.0
const JUMP_VELOCITY = -300.0
const GRAVITY = 750.0
const MAX_FALL_SPEED = 400.0  # Maximum downward velocity

# Dash
const DASH_SPEED = 350.0
const DASH_DURATION = 0.2
const DASH_END_SPEED = 180.0   # Carry-over momentum
var dash_available: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var facing_direction: int = 1  # 1 for right, -1 for left
var was_dashing_on_land: bool = false
var dash_speed: float = DASH_SPEED # Balance supers and hypers

# Wavedash
const WAVEDASH_INPUT_WINDOW = 0.20  # Percent of a second
var wavedash_window_timer: float = 0.0
var wavedash_input_direction: float = 0.0
const WAVEDASH_BUFFER_TIME = 0.2  # Extra buffer time after wavedash
var wavedash_just_performed: bool = false

# Post-dash recovery (smooth upward momentum after up-diagonal dash)
const POST_DASH_GRAVITY_MULT = 1.0
const POST_DASH_RECOVERY_TIME = 0.3
var post_dash_recovery_timer: float = 0.0

# Variable Jump Height
const JUMP_CUT_MULTIPLIER = 0.4  # Lower = shorter min jump

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
const LANDING_LAG_TIME = 0.2
const LANDING_MIN_FALL_SPEED = 200.0
const LANDING_CONTROL_FACTOR = 0.4    # Control during lag (0=none, 1=full)
var landing_lag_timer: float = 0.0
var was_on_floor: bool = false
var fall_speed: float = 0.0

# Wall Cling
const WALL_CLING_GRAVITY_MULT = 0.4  # Slows fall speed when on wall
var is_next_to_wall: bool = false
var wall_normal: Vector2 = Vector2.ZERO 

# Wall Bounce
const WALL_BOUNCE_VELOCITY = -500.0  # Upward velocity
const WALL_BOUNCE_PUSH_FORCE = 300.0  # Push away from wall
var wall_bounce_window_timer: float = 0.0

func _physics_process(delta: float) -> void:
	
	# ========== DASH ==========
	if Input.is_action_just_pressed("ui_shift") and dash_available and not is_dashing:
		# Read both axes for 8-direction dash
		var dx := Input.get_axis("ui_left", "ui_right")
		var dy := Input.get_axis("ui_up", "ui_down")  # up is negative in Godot
		var dir := Vector2(dx, dy)
		
		if dir == Vector2.ZERO:
			# No input: dash in the direction you're facing
			dir = Vector2(facing_direction, 0)
		elif dx != 0:
			# Update facing direction when moving horizontally
				facing_direction = int(sign(dx))
		
		dash_direction = dir.normalized()  # normalize diagonals aren't faster
		is_dashing = true
		dash_timer = DASH_DURATION
		dash_available = false
		landing_lag_timer = 0.0
	
	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * dash_speed
		
	# ========== WAVEDASH ==========
		if dash_direction.y > 0 and dash_direction.x != 0 and is_on_floor():
			wavedash_window_timer = WAVEDASH_INPUT_WINDOW
			wavedash_input_direction = Input.get_axis("ui_left", "ui_right")
	
			# Wavedash triggers if jump is pressed within the window
		if wavedash_window_timer > 0 and Input.is_action_just_pressed("ui_accept"):
			is_dashing = false
			
			var wavedash_speed = dash_speed * 1.3
			var wavedash_jump_velocity = -250.0
			
			var input_x = Input.get_axis("ui_left", "ui_right")
			var wavedash_direction = input_x if input_x != 0 else dash_direction.x
			
			velocity.x = wavedash_direction * wavedash_speed
			velocity.y = wavedash_jump_velocity
			post_dash_recovery_timer = POST_DASH_RECOVERY_TIME 
			coyote_timer = 0.0
			dash_available = true
			wavedash_window_timer = 0.0
			wavedash_just_performed = true
			
	# ========== DASH ==========
		elif dash_timer <= 0:
			is_dashing = false
			velocity.x = dash_direction.x * DASH_END_SPEED
			if dash_direction.y < 0:
				velocity.y *= 0.5
				post_dash_recovery_timer = POST_DASH_RECOVERY_TIME
	else:
		
		# ========== HORIZONTAL MOVEMENT ==========
		var direction := Input.get_axis("ui_left", "ui_right")
		var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
		var fric := FRICTION if is_on_floor() else AIR_ACCELERATION
		
		# Update facing direction when moving
		if direction != 0:
			facing_direction = int(sign(direction))
		
		# During landing lag, soften control instead of forcing a stop
		if landing_lag_timer > 0:
			accel *= LANDING_CONTROL_FACTOR
			fric *= LANDING_CONTROL_FACTOR
		
		var max_spd: float = MAX_SPEED if is_on_floor() else MAX_AIR_SPEED
		if direction != 0:
			velocity.x = move_toward(velocity.x, direction * max_spd, accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, fric * delta)
	
	# ========== JUMP EXECUTION ==========
	# Execute immediately if we land/can jump, regardless of when buffered
	if jump_buffered and (is_on_floor() or coyote_timer > 0) and not (is_dashing and not is_on_floor()):
		velocity.y = JUMP_VELOCITY
		jump_buffered = false
		coyote_timer = 0.0
		landing_lag_timer = 0.0
		dash_available = true
		is_dashing = false
	# Variable Jump Height
	if Input.is_action_just_released("ui_accept") and velocity.y < 0 and not is_dashing and velocity.y < -100:
		velocity.y *= JUMP_CUT_MULTIPLIER
	
	# ========== GRAVITY ==========
	if not is_on_floor():
		var gravity_mult := 1.0
		if post_dash_recovery_timer > 0:
			gravity_mult = POST_DASH_GRAVITY_MULT
			post_dash_recovery_timer -= delta
		elif abs(velocity.y) < APEX_THRESHOLD:
			gravity_mult = APEX_GRAVITY_MULT
		elif velocity.y > 0:
			gravity_mult = FALL_GRAVITY_MULT
		
		# ========== WALL CLING ==========
		if is_next_to_wall and velocity.y > 0 and ((wall_normal.x < 0 and velocity.x > 0) or (wall_normal.x > 0 and velocity.x < 0)): # +
			gravity_mult *= WALL_CLING_GRAVITY_MULT # +
			velocity.y = min(velocity.y, 120.0)
			
		velocity.y += GRAVITY * gravity_mult * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
		
	# ========== LANDING LAG ==========
	
	if is_on_floor() and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED and not is_dashing:
			landing_lag_timer = LANDING_LAG_TIME
			velocity.x *= 0.5   # shave horizontal speed on impact — THIS is what you feel
			
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
	
	was_on_floor = is_on_floor()
	
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
	if Input.is_action_just_pressed("ui_accept") and is_next_to_wall and not is_on_floor() and is_dashing and dash_direction.y < 0:
		wall_bounce_window_timer = 0.2
		var push_direction = int(sign(wall_normal.x))
		velocity.x = push_direction * WALL_BOUNCE_PUSH_FORCE
		velocity.y = WALL_BOUNCE_VELOCITY
		jump_buffered = false
		dash_available = true
		is_dashing = false
		coyote_timer = 0.0
	
	# ========== COYOTE TIME ==========
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		dash_available = true
	else:
		coyote_timer -= delta
	
	# ========== JUMP BUFFER ==========
	if Input.is_action_just_pressed("ui_accept"):
		if not (is_dashing and not is_on_floor()) or is_next_to_wall:
			jump_buffered = true
			jump_buffer_timer = WAVEDASH_BUFFER_TIME if wavedash_just_performed else JUMP_BUFFER_TIME
	
	if jump_buffered:
		jump_buffer_timer -= delta
		if jump_buffer_timer <= 0:
			jump_buffered = false
			wavedash_just_performed = false
	
	if wavedash_window_timer > 0:
		wavedash_window_timer -= delta
	
	# ========== SPRITE FLIP ==========
	sprite.flip_h = facing_direction == -1
	
	# ========== APPLY MOVEMENT ==========
	fall_speed = velocity.y
	move_and_slide()
