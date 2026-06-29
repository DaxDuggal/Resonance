extends CharacterBody2D

# Movement constants
const MAX_SPEED = 140.0
const MAX_AIR_SPEED = 120.0
const ACCELERATION = 1200.0
const AIR_ACCELERATION = 1000.0
const FRICTION = 1200.0
const JUMP_VELOCITY = -280.0
const GRAVITY = 600.0

# Variable Jump Height
const JUMP_CUT_MULTIPLIER = 0.6  # Lower = shorter min jump (0.0–0.5)

# Assymetric Gravity
const FALL_GRAVITY_MULT = 1.5  # Higher = snappier falls (1.5–2.2)

# Coyote Time
const COYOTE_TIME = 0.15
var coyote_timer: float = 0.0

# Jump Buffering
const JUMP_BUFFER_TIME = 0.1
var jump_buffer_timer: float = 0.0
var jump_buffered: bool = false

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

# Landing lag
const LANDING_LAG_TIME = 0.2
const LANDING_MIN_FALL_SPEED = 200.0
const LANDING_CONTROL_FACTOR = 0.4    # Control during lag (0=none, 1=full)
var landing_lag_timer: float = 0.0
var was_on_floor: bool = false
var fall_speed: float = 0.0


func _physics_process(delta: float) -> void:
	# ========== GRAVITY ==========
	if not is_on_floor():
		var gravity_mult := 1.0
		if velocity.y > 0:
			gravity_mult = FALL_GRAVITY_MULT
		velocity.y += GRAVITY * gravity_mult * delta
	
	# ========== LANDING LAG ==========
	
	if is_on_floor() and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED and not is_dashing:
			landing_lag_timer = LANDING_LAG_TIME
			velocity.x *= 0.5   # shave horizontal speed on impact — THIS is what you feel
			
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
	
	was_on_floor = is_on_floor()
	
	# ========== COYOTE TIME ==========
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		dash_available = true
	else:
		coyote_timer -= delta
	
	# ========== JUMP BUFFER ==========
	if Input.is_action_just_pressed("ui_accept"):
		if not (is_dashing and not is_on_floor()):
			jump_buffered = true
			jump_buffer_timer = JUMP_BUFFER_TIME
	
	if jump_buffered:
		jump_buffer_timer -= delta  # Timer runs down always (even during dash)
		if jump_buffer_timer <= 0:
			jump_buffered = false
			print("BUFFER EXPIRED")
	
	
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
	if Input.is_action_just_released("ui_accept") and velocity.y < 0 and not is_dashing:
		velocity.y *= JUMP_CUT_MULTIPLIER
	
	# ========== DASH ==========
	if Input.is_action_just_pressed("ui_shift") and dash_available and not is_dashing:
		# Read both axes for 8-direction dash
		var dx := Input.get_axis("ui_left", "ui_right")
		var dy := Input.get_axis("ui_up", "ui_down")  # up is negative in Godot
		var dir := Vector2(dx, dy)
		
		if dir == Vector2.ZERO:
			# No input: dash in the direction you're facing
			dir = Vector2(facing_direction, 0)
		else:
			# Update facing direction when moving horizontally
			if dx != 0:
				facing_direction = int(sign(dx))
		
		dash_direction = dir.normalized()  # normalize so diagonals aren't faster
		is_dashing = true
		dash_timer = DASH_DURATION
		dash_available = false
		landing_lag_timer = 0.0
	
	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * DASH_SPEED
		
		if dash_timer <= 0:
			is_dashing = false
			velocity.x = dash_direction.x * DASH_END_SPEED
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
	
	# ========== APPLY MOVEMENT ==========
	fall_speed = velocity.y
	move_and_slide()
