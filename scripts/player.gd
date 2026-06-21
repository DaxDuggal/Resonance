extends CharacterBody2D

# Movement constants - Tuned for Celeste/Hollow Knight tight feel
const MAX_SPEED = 120.0
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

# Jump Buffering: Stores jump input for a short time so it executes when you land
# Keep it tight like Celeste - not too forgiving
const JUMP_BUFFER_TIME = 0.06  # 60ms (tighter than ori/smb)
var jump_buffer_timer: float = 0.0  # Tracks how long the jump input has been buffered
var jump_buffered: bool = false  # Whether a jump is currently buffered

# Dash variables
<<<<<<< HEAD
const DASH_SPEED = 400.0  # Punchy dash speed
const DASH_DURATION = 0.10  # Shorter dash = tighter feel
=======
const DASH_SPEED = 350.0  # Punchy dash speed
const DASH_DURATION = 0.20  # Shorter dash = tighter feel
>>>>>>> e174ccc (First commit, add player movement)
var dash_available: bool = true
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_direction: float = 0.0


func _physics_process(delta: float) -> void:
	# ========== GRAVITY ==========
	# Always apply gravity when not on the floor
	if not is_on_floor():
		velocity += get_gravity() * delta
	
<<<<<<< HEAD
	# ========== LANDING LAG ==========
	if is_on_floor() and not was_on_floor:
		if fall_speed >= LANDING_MIN_FALL_SPEED:
			landing_lag_timer = LANDING_LAG_TIME
	
	if landing_lag_timer > 0:
		landing_lag_timer -= delta
	
	was_on_floor = is_on_floor()
	
=======
>>>>>>> e174ccc (First commit, add player movement)
	# ========== COYOTE TIME LOGIC ==========
	# Coyote time allows you to jump briefly after walking off a platform
	# This is a common feature in games like Celeste and makes platforming feel better
	if is_on_floor():
		# We're on the floor, so reset coyote timer to full
		coyote_timer = COYOTE_TIME
	else:
		# We're in the air, so count down coyote time
		coyote_timer -= delta
	
	# ========== JUMP BUFFER LOGIC ==========
	# Jump buffering: if you press jump just before landing, it will execute immediately
	# This makes the game feel responsive even with imperfect timing
	
	# Check if jump button was just pressed
	if Input.is_action_just_pressed("ui_accept"):
		jump_buffered = true
		jump_buffer_timer = JUMP_BUFFER_TIME
	
	# Count down the jump buffer timer
	if jump_buffered:
		jump_buffer_timer -= delta
		# If buffer time runs out, clear the buffered jump
		if jump_buffer_timer <= 0:
			jump_buffered = false
	
	# ========== JUMP EXECUTION ==========
	# Execute jump if:
	# 1. A jump is buffered AND (we're on floor OR coyote time is active)
	# 2. This ensures we can use coyote time AND jump buffering together
	if jump_buffered and (is_on_floor() or coyote_timer > 0):
		velocity.y = JUMP_VELOCITY
		jump_buffered = false  # Consume the buffered jump
		coyote_timer = 0.0  # Use up coyote time (can't jump again until landing)
		dash_available = true  # Refresh dash on jump
	
	# ========== DASH LOGIC ==========
	if Input.is_action_just_pressed("ui_shift") and dash_available and not is_dashing:
		# Start a dash
		is_dashing = true
		dash_timer = DASH_DURATION
		dash_available = false
		# Get dash direction from input
		var input_direction = Input.get_axis("ui_left", "ui_right")
		dash_direction = 1.0 if input_direction >= 0 else -1.0
	
	# Handle ongoing dash
	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction * DASH_SPEED
		velocity.y = 0  # No gravity during dash
		
		if dash_timer <= 0:
			is_dashing = false
	else:
		# ========== HORIZONTAL MOVEMENT WITH ACCELERATION ==========
		# Instead of instant speed changes, we accelerate smoothly
		# This is more realistic and feels better for platformers
		var direction := Input.get_axis("ui_left", "ui_right")
		
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
			# Player is pressing left or right
			# Accelerate toward max speed in that direction
			# move_toward(current, target, amount) smoothly moves current toward target
			velocity.x = move_toward(velocity.x, direction * MAX_SPEED, ACCELERATION * delta)
		else:
			# No input - apply friction to slow down
			velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
	
	# ========== APPLY MOVEMENT ==========
	# This actually moves the player and handles collisions with walls/floors
>>>>>>> e174ccc (First commit, add player movement)
	move_and_slide()
