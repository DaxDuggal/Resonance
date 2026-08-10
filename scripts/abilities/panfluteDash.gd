extends DashAbility
class_name PanfluteDash

@export var dash_speed: float = 525.0
@export var speed_multiplier: float = 0.85  # make it slightly slower
@export var max_range: float = 175.0
@export var dash_end_speed: float = 180.0

# Pause before moving (frames)
@export var pause_frames: int = 3

# Speed ramp-up after pause (frames) - gradually accelerate to full speed.
# Only used by the tap (pull) path.
@export var ramp_frames: int = 15

# Wall bounce window after a PULL hits a wall (longer than default to allow
# buffering). Not used for swing collisions — those just end the swing.
@export var wall_bounce_window_time: float = 0.3

@export_group("Swing")
# Plain, symmetric pendulum physics — gravity is the sole restoring force
# (stronger the further you are from hanging straight down, zero right at
# the bottom, naturally reversing you at the top of each arc on its own).
# Multiplies player.gravity, which is tuned for normal falling and is far
# too strong once divided by a rope length of only ~100-175px, so keep this
# well under 1.0. Tune by feel.
@export var swing_gravity_scale: float = 0.75
# Small constant push while holding a direction — just an influence on top
# of gravity, the same way a person pumps their legs on a real swing, not a
# mechanic with its own rules.
@export var swing_pump_strength: float = 1.0
# Hard cap on angular speed, mostly as a safety net against pump input
# stacking with a fast fall indefinitely.
@export var swing_max_angular_velocity: float = 3.0
# How long dash must still be held, after the pull already started, before
# it converts into a swing. Released before this and it stays a normal tap
# pull — keep this comfortably above a quick tap's natural press duration.
@export var swing_hold_threshold: float = 0.15
# Multiplies velocity at the moment of a deliberate release (letting go of
# dash mid-swing) so flinging off actually feels like it. Swing speed is
# kept fairly low while attached (see swing_max_angular_velocity) so it
# stays controllable — this is where the payoff for timing the release
# well comes from. Doesn't apply if the swing ends by hitting something.
@export var swing_release_boost: float = 1.3

var _pause_timer: float = 0.0
var _moving: bool = false
var _speed_factor: float = 1.0
var _ramp_tween: Tween = null
var _pre_pause_velocity: Vector2 = Vector2.ZERO
var _abort_after_pause: bool = false
var _skip_consume: bool = false

# The point found by the raycast in start_dash — used as either the PULL
# target or the SWING anchor, decided once the wind-up pause ends based on
# whether dash is still held (see update_dash).
var _anchor_point: Vector2 = Vector2.ZERO

var _hold_check_timer: float = 0.0
var _hold_decided: bool = false

var _swinging: bool = false
var _rope_length: float = 0.0
var _swing_angle: float = 0.0  # 0 = hanging straight down from the anchor
var _swing_angular_velocity: float = 0.0

const MIN_ROPE_LENGTH: float = 8.0  # Avoids a near-zero rope causing huge angular acceleration


func start_dash(player: Player, dir: Vector2) -> void:
	# Reset per-dash flags so a previous aborted grapple can't leak state
	_abort_after_pause = false
	_skip_consume = false
	_swinging = false
	_hold_decided = false
	_hold_check_timer = swing_hold_threshold

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

	_anchor_point = target

	# If no hit was found, still do the pre-dash pause to allow animation, but don't move
	if not found_hit:
		# Activate ability so update_dash is called for the pause
		super.start_dash(player, dir)
		_abort_after_pause = true
		_skip_consume = true
		_pause_timer = float(pause_frames) / 60.0
		_moving = false
		_pre_pause_velocity = player.velocity
		player.dash_available = false
		return


	# Commit to dash now that checks passed
	super.start_dash(player, dir)

	# Apply speed multiplier and set dash velocity (used if this ends up
	# being a tap/PULL rather than a hold/SWING — see update_dash)
	var effective_speed: float = dash_speed * speed_multiplier
	dash_velocity = dash_direction.normalized() * effective_speed

	# No timer - dash only ends on collision detection, not by time

	# Start with a short pause so animation can play
	_pause_timer = float(pause_frames) / 60.0
	_moving = false
	# store current velocity to smoothly slide it down during pause
	_pre_pause_velocity = player.velocity

	# Consume dash but don't move until pause finishes (skip if this was an attempted miss)
	if not _skip_consume:
		player.dash_available = false
		player.dash_buffer_timer = 0.0


func update_dash(player: Player, delta: float) -> void:
	# Redraw every frame so the line always points at the real anchor from
	# the player's current position — it shrinks while pulling in and pivots
	# correctly while swinging, instead of just translating with the player
	# like a fixed offset (which is what happens if this is only set once).
	if player.has_method("show_dash_debug"):
		player.show_dash_debug(_anchor_point)

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
		_speed_factor = 0.0

		# Always start the pull immediately, exactly like a tap — this is
		# what keeps a genuine tap feeling identical to before. Whether this
		# turns into a swing is decided separately below, by whether dash is
		# STILL held a bit later; converting mid-pull (see _start_swing,
		# which reads whatever velocity the player currently has) feels like
		# the rope catching rather than an abrupt freeze-and-decide.
		#
		# Create tween for extreme speed ramp-up.
		# EASE_IN (not EASE_OUT) is what actually gives a slow start: EASE_OUT
		# rises fast immediately and only levels off near the end, so the grapple
		# was already near full speed within a couple frames. EASE_IN keeps
		# _speed_factor low for most of the ramp, then climbs quickly at the end.
		if _ramp_tween:
			_ramp_tween.kill()
		_ramp_tween = create_tween()
		_ramp_tween.set_trans(Tween.TRANS_CUBIC)
		_ramp_tween.set_ease(Tween.EASE_IN)
		_ramp_tween.tween_property(self, "_speed_factor", 1.0, float(ramp_frames) / 60.0)

	# Tap vs hold, decided after the pull has already started: release before
	# swing_hold_threshold and it just stays a normal pull (matches the old
	# behavior exactly). Still holding once the threshold passes converts it
	# into a swing.
	if not _swinging and not _hold_decided:
		if not Input.is_action_pressed("dash"):
			_hold_decided = true
		else:
			_hold_check_timer -= delta
			if _hold_check_timer <= 0.0:
				_hold_decided = true
				_start_swing(player)

	if _swinging:
		_update_swing(player, delta)
		return

	# PULL: maintain dash velocity (collision detection stops it)
	player.velocity = dash_velocity * _speed_factor


func _start_swing(player: Player) -> void:
	_swinging = true

	# May be converting mid-pull (see update_dash) — stop the pull's speed
	# ramp so it can't leak into anything after the swing takes over.
	if _ramp_tween:
		_ramp_tween.kill()

	_rope_length = maxf(player.global_position.distance_to(_anchor_point), MIN_ROPE_LENGTH)

	var offset: Vector2 = player.global_position - _anchor_point
	_swing_angle = atan2(offset.x, offset.y)

	# Carry whatever velocity the player already had into the swing as
	# angular velocity, so attaching doesn't feel like hitting a wall —
	# only the component of velocity tangent to the rope actually converts;
	# the rest (pulling toward/away from the anchor) is lost, same as a real
	# rope going taut.
	var tangent: Vector2 = Vector2(cos(_swing_angle), -sin(_swing_angle))
	_swing_angular_velocity = player.velocity.dot(tangent) / _rope_length


func _update_swing(player: Player, delta: float) -> void:
	# Plain pendulum physics: gravity's restoring torque is strongest out at
	# the sides and zero at the bottom, which on its own already produces a
	# slow top, a fast bottom, and a natural reversal at each peak — no
	# special-casing needed, that's just what the sine term does.
	var effective_gravity: float = player.gravity * swing_gravity_scale
	var angular_acceleration: float = -(effective_gravity / _rope_length) * sin(_swing_angle)

	# Input is just a small constant push in whichever direction is held,
	# the same as a person pumping their legs — it can add to or work
	# against gravity, nothing more.
	var input_x: float = Input.get_axis("move_left", "move_right")
	angular_acceleration += input_x * swing_pump_strength

	_swing_angular_velocity += angular_acceleration * delta
	_swing_angular_velocity = clamp(_swing_angular_velocity, -swing_max_angular_velocity, swing_max_angular_velocity)
	_swing_angle += _swing_angular_velocity * delta

	var offset: Vector2 = Vector2(sin(_swing_angle), cos(_swing_angle)) * _rope_length
	var target_position: Vector2 = _anchor_point + offset

	# Drive movement through velocity (not a direct position set) so the
	# normal move_and_slide/collision pipeline still applies — swinging into
	# a wall or spike correctly stops the swing via handle_slide_collision
	# below instead of clipping through it.
	player.velocity = (target_position - player.global_position) / delta

	# Release: letting go of dash detaches with a boosted version of whatever
	# velocity the swing currently has — timing the release is the whole
	# point, same as a real grapple-swing, and the boost is what makes that
	# timing actually pay off instead of just matching the swing's own speed.
	if not Input.is_action_pressed("dash"):
		player.velocity *= swing_release_boost
		cancel_dash(player)


func finish_dash(player: Player) -> void:
	is_active = false

	# For upward dashes, don't apply horizontal velocity (allows wall bouncing)
	# For downward/horizontal dashes, apply end velocity normally
	if dash_direction.y >= 0.0:
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
	_swinging = false
	player.exit_dash_state()
	dash_finished.emit()
	# Clear debug drawing
	if player.has_method("clear_dash_debug"):
		player.clear_dash_debug()


# Called from Player after move_and_slide when a slide collision occurred.
func handle_slide_collision(player: Player, collision) -> void:
	# Swinging into something just ends the swing where it is — dash_direction
	# is stale (it's whatever direction the initial cast aimed, not the
	# swing's current direction of travel), so none of the PULL-specific
	# wavedash/wall-bounce arming below applies here.
	if _swinging:
		cancel_dash(player)
		return

	# Accept either a slide-collision object with get_normal() or a Dictionary from intersect_ray
	var normal: Vector2 = Vector2.ZERO
	if typeof(collision) == TYPE_DICTIONARY:
		if collision.has("normal"):
			normal = collision.get("normal")
	else:
		if collision and collision.has_method("get_normal"):
			normal = collision.get_normal()

	# Check if this is a ground hit (normal pointing up)
	var is_ground_hit: bool = normal.y < -0.5 and dash_direction.y > 0.1

	# Check if this is a wall hit (normal pointing sideways) - works for both pure up and diagonal
	var is_wall_hit: bool = abs(normal.x) > 0.5 and dash_direction.y < 0.0

	# Set wavedash window if landing from downward dash (works for air or ground starts)
	if is_ground_hit:
		player.wavedash_window_timer = player.wavedash_input_window

	# Set wall bounce window if hitting a wall going upward (straight or diagonal).
	# Longer than the default window so panflute jumps can be buffered.
	if is_wall_hit:
		player.wall_bounce_window_timer = wall_bounce_window_time
		player.wall_bounce_normal = normal

	finish_dash(player)
