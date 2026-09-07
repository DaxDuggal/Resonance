extends Enemy
class_name FlyingEnemy

@export_group("Movement")
@export var move_speed := 130.0
@export var hover_height := 140.0
@export var gravity := 220.0
@export var hop_impulse := 150.0
@export var hop_rise_drag := 400.0
@export var hop_interval := 0.6
@export var max_rise_speed := 140.0
@export var max_fall_speed := 220.0

var _spawn_y := 0.0
var hop_timer := 0.0
var _just_hopped := false

@export_group("Dive Attack")
@export var dive_drop_distance := 150.0
@export var dive_horizontal_distance := 195.0
@export var dive_trigger_min_x := 90.0
@export var dive_trigger_range := 300.0
@export var min_chase_distance := 170.0

var _dive_launched := false
var _dive_p0 := Vector2.ZERO
var _dive_p1 := Vector2.ZERO
var _dive_p2 := Vector2.ZERO
var _dive_p3 := Vector2.ZERO

@onready var visual: Polygon2D = $Placeholder
@onready var ground_ray: RayCast2D = $GroundRay
@onready var bt_player: BTPlayer = $BTPlayer


func _ready() -> void:
	super._ready()
	_spawn_y = global_position.y
	# BTPlayer defaults to auto-updating itself every physics frame. It's
	# fully unused now (see _physics_process), but left in the scene — force
	# it to MANUAL and never call .update() so it can't run itself in the
	# background and silently stomp velocity again.
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


# Movement here is fully script-owned rather than BTPlayer-driven — the old
# tree's non-attack branches (ChasePlayer/Stop) wrote directly to velocity,
# which fought with _apply_flight()'s incremental gravity/hop model (that
# function only *adds* gravity to whatever velocity.y already was, it
# doesn't reset it) and corrupted the hover height. The BTPlayer/BehaviorTree
# node is still in the scene but unused now — safe to delete whenever.
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_update_awareness(delta)
	_tick_attack(delta)

	if _tick_knockback_stun(delta):
		move_and_slide()
		return

	_update_attack_visual()

	if is_attacking():
		_process_attack(delta)
		move_and_slide()
		return

	_apply_flight(delta)

	# The dive only ever triggers in the same frame a hop fires — see
	# _apply_flight — so the jump itself becomes the dive's windup instead
	# of separately waiting to notice "it's currently above its patrol
	# line," which in practice was almost always mid-hop anyway and easy to
	# miss.
	if _just_hopped and _is_attack_ready():
		start_attack()

	move_and_slide()


# Charging telegraph: flash red during STARTUP, same as Tusker.
func _update_attack_visual() -> void:
	visual.modulate = Color(1.0, 0.3, 0.3) if attack_phase == AttackPhase.STARTUP else Color.WHITE


# Patrol/chase: horizontal keeps itself in the band it can actually dive
# from instead of just closing distance and stopping — too close (under
# dive_trigger_min_x) and it backs away to open up the room the dive needs;
# far enough but past min_chase_distance and it closes back in; in between,
# it holds still (that hold band is what gives the dive a real window to
# trigger, rather than requiring the player to be the one backing off).
# Vertical target is a fixed height above whatever ground is directly below
# (via GroundRay) — it always tries to sit at this line whenever it isn't
# attacking, which also doubles as the dive's "home" line (see
# _is_attack_ready).
#
# Vertical motion is a sharp wingbeat, not a ballistic hop: a strong upward
# impulse that gets burned off fast by its own drag (hop_rise_drag) rather
# than fighting a constant gravity the whole way up — that decoupling is
# what lets the flap read as a strong, snappy pop instead of either a weak
# floaty rise (gravity too low) or an equally harsh climb and fall (gravity
# raised to compensate). Once the rise has bled off, normal gravity takes
# over and it drops back down at a natural rate until the next hop.
func _apply_flight(delta: float) -> void:
	_just_hopped = false

	if ground_ray.is_colliding():
		_spawn_y = ground_ray.get_collision_point().y - hover_height

	if _player_in_range():
		var to_player_x := Global.player.global_position.x - global_position.x
		var distance_x := absf(to_player_x)
		if distance_x < dive_trigger_min_x:
			var away_dir := -signf(to_player_x) if to_player_x != 0.0 else -float(facing_direction)
			velocity.x = move_toward(velocity.x, away_dir * move_speed, move_speed * 4.0 * delta)
		elif distance_x > min_chase_distance:
			var direction_x := signf(to_player_x)
			velocity.x = move_toward(velocity.x, direction_x * move_speed, move_speed * 4.0 * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)

	if absf(velocity.x) > 5.0:
		facing_direction = signi(velocity.x)

	hop_timer = maxf(hop_timer - delta, 0.0)
	if global_position.y > _spawn_y and hop_timer <= 0.0:
		velocity.y = -hop_impulse
		hop_timer = hop_interval
		_just_hopped = true

	if velocity.y < 0.0:
		velocity.y = move_toward(velocity.y, 0.0, hop_rise_drag * delta)
	else:
		velocity.y += gravity * delta
	velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)


# Cubic Bezier helpers — B(t) is the point at t in [0, 1], B'(t) is its
# tangent (rate of change per unit t), both in the standard 4-control-point
# form.
static func _bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return p0 * (mt * mt * mt) + p1 * (3.0 * mt * mt * t) + p2 * (3.0 * mt * t * t) + p3 * (t * t * t)


static func _bezier_derivative(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return (p1 - p0) * (3.0 * mt * mt) + (p2 - p1) * (6.0 * mt * t) + (p3 - p2) * (3.0 * t * t)


# The dive is a fixed, precomputed 4-point Bezier curve, not a physics/floor
# reaction — that's what guarantees it always dips the same shallow amount
# and never actually reaches the floor, and that the shape is a clean,
# symmetric "down, a little horizontal, then back up" every time regardless
# of terrain underneath. P0 is the launch point (relative origin); P1 and
# P2 sit at the same depth (dive_drop_distance) a quarter and three-quarters
# of the way across, which is what gives the flattened, "hangs at the
# bottom for a beat" middle instead of a sharp V; P3 returns to the same
# height it launched from, a mirror of P0 — hence symmetric. The whole
# curve's direction (which way the horizontal reach points) is locked in
# once at launch rather than homing on the player mid-dive, so the shape
# stays intact. RECOVERY just lets gravity settle it the rest of the way
# back into _apply_flight's hover once the attack ends.
func _process_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.STARTUP:
			velocity = Vector2.ZERO
			_dive_launched = false
			hop_timer = 0.0
		AttackPhase.ACTIVE:
			if not _dive_launched:
				var dir := 1.0
				if Global.player:
					dir = signf(Global.player.global_position.x - global_position.x)
				if dir == 0.0:
					dir = float(facing_direction)
				facing_direction = signi(dir)

				_dive_p0 = Vector2.ZERO
				_dive_p1 = Vector2(dir * dive_horizontal_distance * 0.25, dive_drop_distance)
				_dive_p2 = Vector2(dir * dive_horizontal_distance * 0.75, dive_drop_distance)
				_dive_p3 = Vector2(dir * dive_horizontal_distance, 0.0)
				_dive_launched = true

			var duration := 1.0
			if attack_profile and attack_profile.active_duration > 0.0:
				duration = attack_profile.active_duration
			var t := clampf(1.0 - (attack_phase_timer / duration), 0.0, 1.0)
			var deriv := _bezier_derivative(_dive_p0, _dive_p1, _dive_p2, _dive_p3, t)
			velocity = deriv / duration
		AttackPhase.RECOVERY:
			# The curve's exit tangent leaves it with real horizontal speed
			# (that's what "a little horizontal" at the end of the rise
			# means) — nothing eased it back down before, so it just
			# coasted sideways at that same speed for the whole recovery
			# window instead of settling out.
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
			velocity.y += gravity * delta
			velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)


func _player_in_range() -> bool:
	return is_aware_of_player


# The height requirement is handled by the caller only checking this right
# when a hop just fired (see _physics_process/_apply_flight) — this just
# covers the remaining conditions (cooldown, awareness, horizontal range).
func _is_attack_ready() -> bool:
	if not can_start_attack():
		return false
	if not _player_in_range():
		return false
	var to_player := Global.player.global_position - global_position
	if absf(to_player.x) < dive_trigger_min_x:
		return false
	if absf(to_player.x) > dive_trigger_range:
		return false
	return true
