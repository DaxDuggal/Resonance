extends CharacterBody2D

# Movement constants
const MAX_SPEED = 120.0
<<<<<<< HEAD
const ACCELERATION = 1200.0  # High = snappy response (Celeste-like)
<<<<<<< HEAD
const AIR_ACCELERATION = 1500.0  # Lower than ground = less control in air
const FRICTION = 1200.0      # High = stops quickly (grounded feel)
const JUMP_VELOCITY = -280.0  # Slightly lower = less floaty


# Landong lag: Unless the player dashes into the groun, they'll suffer a short bit of landing lag
const LANDING_LAG_TIME = 0.10 # How long the lag lasts (~100ms)
const LANDING_MIN_FALL_SPEED = 200.0  # Only lag if falling faster than this
var landing_lag_timer: float = 0.0
var was_on_floor: bool = false     # Tracks floor state from last frame
var fall_speed: float = 0.0

# Coyote Time: Allows jumping for a short time AFTER leaving the platform
# Celeste uses ~0.04-0.06 for tight feel (not too forgiving)
const COYOTE_TIME = 0.15 # Tighter than ori/smb (0.05 = 50ms)
=======
const FRICTION = 1200.0      # High = stops quickly (grounded feel)
const JUMP_VELOCITY = -280.0  # Slightly lower = less floaty

# Coyote Time: Allows jumping for a short time AFTER leaving the platform
# Celeste uses ~0.04-0.06 for tight feel (not too forgiving)
const COYOTE_TIME = 0.15  # Tighter than ori/smb (0.05 = 50ms)
>>>>>>> e174ccc (First commit, add player movement)
var coyote_timer: float = 0.0  # Tracks how long it's been since we left the floor
=======
const ACCELERATION = 1200.0
const AIR_ACCELERATION = 1000.0
const FRICTION = 1200.0
const JUMP_VELOCITY = -300.0
const GRAVITY = 600.0

# Variable Jump Height
const JUMP_CUT_MULTIPLIER = 0.6  # Lower = shorter min jump (0.0–0.5)
>>>>>>> 1fd9559 (Add basic dash and improve player physics)

# Assymetric Gravity
const FALL_GRAVITY_MULT = 1.5  # Higher = snappier falls (1.5–2.2)

<<<<<<< HEAD
# Dash variables
<<<<<<< HEAD
const DASH_SPEED = 400.0  # Punchy dash speed
const DASH_DURATION = 0.10  # Shorter dash = tighter feel
=======
const DASH_SPEED = 350.0  # Punchy dash speed
const DASH_DURATION = 0.20  # Shorter dash = tighter feel
>>>>>>> e174ccc (First commit, add player movement)
=======
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
>>>>>>> 1fd9559 (Add basic dash and improve player physics)
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
	
<<<<<<< HEAD
<<<<<<< HEAD
	# ========== LANDING LAG ==========
	if is_on_floor() and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED:
			landing_lag_timer = LANDING_LAG_TIME
	
=======
	# ========== LANDING LAG ==========
	
	if is_on_floor() and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED and not is_dashing:
			landing_lag_timer = LANDING_LAG_TIME
			velocity.x *= 0.5   # shave horizontal speed on impact — THIS is what you feel
			
>>>>>>> 1fd9559 (Add basic dash and improve player physics)
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
	
	was_on_floor = is_on_floor()
	
<<<<<<< HEAD
=======
>>>>>>> e174ccc (First commit, add player movement)
	# ========== COYOTE TIME LOGIC ==========
	# Coyote time allows you to jump briefly after walking off a platform
	# This is a common feature in games like Celeste and makes platforming feel better
=======
	# ========== COYOTE TIME ==========
>>>>>>> 1fd9559 (Add basic dash and improve player physics)
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
			# Carry-over: keep momentum instead of snapping to walk speed
			velocity.x = dash_direction.x * DASH_END_SPEED
			coyote_timer = COYOTE_TIME
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
		
<<<<<<< HEAD
		# Use different accel/friction depending on whether we're grounded
		var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
		var fric := FRICTION if is_on_floor() else AIR_ACCELERATION
		
		if landing_lag_timer > 0:
			# During landing recovery, damp movement for that "thud"
			velocity.x = move_toward(velocity.x, 0, fric * delta)
		elif direction != 0:
			velocity.x = move_toward(velocity.x, direction * MAX_SPEED, accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, fric * delta)
		
	# ========== APPLY MOVEMENT ==========
	# This actually moves the player and handles collisions with walls/floors
	fall_speed = velocity.y
=======
		if direction != 0:
			velocity.x = move_toward(velocity.x, direction * MAX_SPEED, accel * delta)
		else:
			velocity.x = move_toward(velocity.x, 0, fric * delta)
	
	# ========== APPLY MOVEMENT ==========
<<<<<<< HEAD
	# This actually moves the player and handles collisions with walls/floors
>>>>>>> e174ccc (First commit, add player movement)
=======
	fall_speed = velocity.y
>>>>>>> 1fd9559 (Add basic dash and improve player physics)
	move_and_slide()
