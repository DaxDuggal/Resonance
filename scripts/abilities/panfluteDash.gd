extends DashAbility
class_name PanfluteDash

@export var allows_jump_interrupt: bool = true
@export var dash_speed: float = 650.0
@export var speed_multiplier: float = 0.85  # make it slightly slower
@export var max_range: float = 800.0
@export var min_range: float = 8.0
@export var dash_end_speed: float = 180.0

# how close a hit must be to be considered (prevents zero-duration dashes)
@export var min_acceptable_distance: float = 4.0

# Pause before moving (frames)
@export var pause_frames: int = 8


var timer: float = 0.0
var _pause_timer: float = 0.0
var _moving: bool = false
var _pre_pause_velocity: Vector2 = Vector2.ZERO
var _abort_after_pause: bool = false
var _skip_consume: bool = false

func start_dash(player: Player, dir: Vector2) -> void:
	# Track whether the raycast found a valid target for grappling
	var found_hit: bool = false

	var local_dir: Vector2 = dir.normalized()

	# Cast a ray from the player in dash direction to find the first collision
	var from: Vector2 = player.global_position
	var to: Vector2 = from + local_dir * max_range
	var target: Vector2 = to

	# Prefer using a RayCast2D child named GrappleRay if present (editor-visible)
	if player.has_node("GrappleRay"):
		var rc_node: Node = player.get_node("GrappleRay")
		if rc_node is RayCast2D:
			var rc: RayCast2D = rc_node
			# set target_position in the RayCast2D's local space using the local_dir (we haven't called super.start_dash yet)
			var cast_vec: Vector2 = local_dir * max_range
			rc.target_position = cast_vec
			rc.enabled = true
			rc.force_raycast_update()
			if rc.is_colliding():
				target = rc.get_collision_point()
				found_hit = true
			# disable after query
			rc.enabled = false
		else:
			# Node exists but isn't a RayCast2D; fallback to space query
			var exclude: Array = [player]
			var space = player.get_world_2d().direct_space_state
			var params = PhysicsRayQueryParameters2D.new()
			params.from = from
			params.to = to
			params.exclude = exclude
			var hit = space.intersect_ray(params)
			if hit and hit.has("position"):
				target = hit.position
				found_hit = true
	else:
		var exclude: Array = [player]
		var space = player.get_world_2d().direct_space_state
		var params = PhysicsRayQueryParameters2D.new()
		params.from = from
		params.to = to
		params.exclude = exclude
		var hit = space.intersect_ray(params)
		if hit and hit.has("position"):
			target = hit.get("position")
			found_hit = true

	# If no hit was found, still do the pre-dash pause to allow animation, but don't move or consume the dash
	if not found_hit:
		# Activate ability so update_dash is called for the pause
		super.start_dash(player, dir)
		_abort_after_pause = true
		_skip_consume = true
		_pause_timer = float(pause_frames) / 60.0
		_moving = false
		_pre_pause_velocity = player.velocity
		# Show debug to indicate attempted grapple
		if player.has_method("show_dash_debug"):
			player.show_dash_debug(target)
		return


	# Commit to dash now that checks passed
	super.start_dash(player, dir)

	# Tell player to draw debug line to the hit/target (if they support it)
	if player.has_method("show_dash_debug"):
		player.show_dash_debug(target)

	var distance: float = (target - from).length()
	# clamp tiny distances
	if distance < min_acceptable_distance:
		distance = min_acceptable_distance

	# Compute travel time so the dash reaches the target exactly
	# Apply speed multiplier to slow the dash a bit
	var effective_speed: float = dash_speed * speed_multiplier
	timer = distance / effective_speed
	dash_velocity = dash_direction.normalized() * effective_speed

	# Start with a short pause so animation can play
	_pause_timer = float(pause_frames) / 60.0
	_moving = false
	# store current velocity to smoothly slide it down during pause
	_pre_pause_velocity = player.velocity

	# Consume dash but don't move until pause finishes (skip if this was an attempted miss)
	if not _skip_consume:
		player.dash_available = false
		player.dash_buffer_timer = 0.0
		player.landing_lag_timer = 0.0


func update_dash(player: Player, delta: float) -> void:
	# If we're in the pre-dash pause, keep player paused in the air
	if _pause_timer > 0.0:
		# smoothly slide velocity toward zero over the pause duration
		var pause_duration: float = float(pause_frames) / 60.0
		_pause_timer -= delta
		_moving = false
		var t: float = clamp(1.0 - (_pause_timer / max(pause_duration, 0.0001)), 0.0, 1.0)
		player.velocity = _pre_pause_velocity.lerp(Vector2.ZERO, t)
		return

	# Start movement when pause ends
	# If this was a no-hit attempt, we abort after the pause (animation only)
	if _abort_after_pause:
		# Cancel the dash ability cleanly so player regains control
		_abort_after_pause = false
		_skip_consume = false
		cancel_dash(player)
		return

	if not _moving:
		_moving = true

	# Maintain dash velocity until timer expires
	timer -= delta
	player.velocity = dash_velocity

	if timer <= 0.0:
		finish_dash(player)

func finish_dash(player: Player) -> void:
	is_active = false

	# End dash: apply a gentle horizontal end velocity and preserve vertical velocity behavior
	player.velocity.x = dash_direction.x * dash_end_speed

	# Soften upward component if dash had upward direction
	if dash_direction.y < 0.0:
		player.velocity.y *= 0.5

	# Clear debug drawing if player supports it
	if player.has_method("clear_dash_debug"):
		player.clear_dash_debug()

	player.exit_dash_state()
	dash_finished.emit()

func cancel_dash(player: Player) -> void:
	is_active = false
	player.exit_dash_state()
	dash_finished.emit()
	# Clear debug drawing
	if player.has_method("clear_dash_debug"):
		player.clear_dash_debug()


# Called from Player after move_and_slide when a slide collision occurred.
# For grapple dash, immediately finish the dash using the collision normal so recoil is accurate.
func handle_slide_collision(player: Player, collision) -> void:
	# Accept either a slide-collision object with get_normal() or a Dictionary from intersect_ray, but ignore normals
	# Zero momentum and finish dash cleanly (no recoil)
	player.velocity = Vector2.ZERO
	finish_dash(player)

# Allow jump to interrupt this dash (player.gd will call this when appropriate)
func interrupt_with_jump(player: Player) -> void:
	# Cancel the dash and apply a normal jump impulse; do not restore dash availability here
	cancel_dash(player)
	player.velocity.y = player.jump_velocity
