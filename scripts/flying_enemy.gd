extends Enemy
class_name FlyingEnemy

@export_group("Movement")
@export var move_speed := 130.0
@export var hover_height := 90.0
@export var gravity := 220.0
@export var hop_impulse := 150.0
@export var hop_rise_drag := 400.0
@export var hop_interval := 0.6
@export var max_rise_speed := 140.0
@export var max_fall_speed := 220.0
# Shared accel rate for every horizontal flight-movement leaf (BackAway/
# ChaseHorizontal/HoldHorizontal) and the dive's recovery ease-out — named
# instead of the same "move_speed * 4.0" magic number repeated everywhere.
@export var flight_accel_mult := 4.0

var _spawn_y := 0.0
var hop_timer := 0.0

@export_group("Dive Attack")
@export var dive_drop_distance := 117.0
@export var dive_horizontal_distance := 152.0
@export var dive_trigger_min_x := 70.0
@export var dive_trigger_range := 234.0
@export var min_chase_distance := 133.0

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
	# BT now owns the horizontal decision (back away/chase/hold) and attack
	# triggering (AttackReady -> StartAttack) — see the leaves under
	# scripts/bt/. Default AUTO update_mode would tick it a second time on
	# top of our explicit call below, so force MANUAL and tick it ourselves
	# at the right point in _physics_process (same reason MeleeGroundEnemy
	# does this).
	bt_player.update_mode = BTPlayer.UpdateMode.MANUAL


# Hover physics (vertical) stay fully script-owned regardless of what the
# tree decides — it's a continuous simulation, not a decision, same as
# MeleeGroundEnemy's _apply_gravity(). BT only ever writes velocity.x.
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Same reasoning as Player._physics_process()'s own guard: a NaN/Inf
	# velocity here would otherwise feed into a knockback vector computed
	# from this enemy's position on the player's next hit, propagating the
	# corruption onto the player instead of staying contained to this enemy.
	if not velocity.is_finite():
		velocity = Vector2.ZERO

	_update_awareness(delta)

	if _tick_stun(delta):
		# Stunned means it can't flap — falls like a stone instead of
		# hovering, rather than being pinned in mid-air.
		velocity.x = 0.0
		velocity.y += gravity * delta
		velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)
		move_and_slide()
		return

	_tick_attack(delta)

	if _tick_knockback_stun(delta):
		move_and_slide()
		return

	_update_attack_visual()

	if is_attacking():
		_process_attack(delta)
		move_and_slide()
		return

	_apply_hover(delta)
	bt_player.update(delta)

	if absf(velocity.x) > 5.0:
		facing_direction = int(signf(velocity.x))

	move_and_slide()


# Charging telegraph: flash red during STARTUP, same as Tusker.
func _update_attack_visual() -> void:
	visual.modulate = Color(1.0, 0.3, 0.3) if attack_phase == AttackPhase.STARTUP else Color.WHITE


# Vertical-only now — the horizontal decision (back away/chase/hold) moved
# to the BT tree (see scripts/bt/bt_player_too_close.gd, bt_player_too_far.gd,
# bt_back_away.gd, bt_chase_horizontal.gd, bt_hold_horizontal.gd). This still
# runs every non-attacking physics frame regardless of what the tree decides,
# same as MeleeGroundEnemy's _apply_gravity().
#
# Target is a fixed height above whatever ground is directly below (via
# GroundRay) — it always tries to sit at this line whenever it isn't
# attacking, which also doubles as the dive's "home" line (see
# _is_attack_ready).
#
# Motion is a sharp wingbeat, not a ballistic hop: a strong upward impulse
# that gets burned off fast by its own drag (hop_rise_drag) rather than
# fighting a constant gravity the whole way up — that decoupling is what
# lets the flap read as a strong, snappy pop instead of either a weak floaty
# rise (gravity too low) or an equally harsh climb and fall (gravity raised
# to compensate). Once the rise has bled off, normal gravity takes over and
# it drops back down at a natural rate until the next hop.
func _apply_hover(delta: float) -> void:
	if ground_ray.is_colliding():
		_spawn_y = ground_ray.get_collision_point().y - hover_height

	hop_timer = maxf(hop_timer - delta, 0.0)
	if global_position.y > _spawn_y and hop_timer <= 0.0:
		velocity.y = -hop_impulse
		hop_timer = hop_interval

	if velocity.y < 0.0:
		velocity.y = move_toward(velocity.y, 0.0, hop_rise_drag * delta)
	else:
		velocity.y += gravity * delta
	velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)


# Thin wrappers for the BT condition leaves (bt_player_too_close.gd/
# bt_player_too_far.gd) — kept on the agent so the distance math has one
# home instead of being duplicated in the leaf scripts.
func _player_too_close() -> bool:
	if not _player_in_range():
		return false
	var distance_x := absf(Global.player.global_position.x - global_position.x)
	return distance_x < dive_trigger_min_x


func _player_too_far() -> bool:
	if not _player_in_range():
		return false
	var distance_x := absf(Global.player.global_position.x - global_position.x)
	return distance_x > min_chase_distance


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
# P2 sit at y = dive_drop_distance a quarter and three-quarters of the way
# across, which is what gives the flattened, "hangs at the bottom for a
# beat" middle instead of a sharp V; P3 returns to the same height it
# launched from, a mirror of P0 — hence symmetric.
#
# Note dive_drop_distance is the *control point's* offset, not the curve's
# actual lowest point — for this P1=P2 symmetric layout the true max depth
# works out to y(t) = 3*D*t*(1-t), which peaks at t=0.5 at 0.75*D. So the
# real dip below the launch point is 0.75 * dive_drop_distance, not
# dive_drop_distance itself (117 -> ~87.75px below the launch height, which
# is the 85-90px band this was tuned for).
#
# The whole curve's direction (which way the horizontal reach points) is
# locked in once at launch rather than homing on the player mid-dive, so
# the shape stays intact. RECOVERY just lets gravity settle it the rest of
# the way back into _apply_hover's hover once the attack ends.
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
				facing_direction = int(signf(dir))

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
			velocity.x = move_toward(velocity.x, 0.0, move_speed * flight_accel_mult * delta)
			velocity.y += gravity * delta
			velocity.y = clampf(velocity.y, -max_rise_speed, max_fall_speed)


func _player_in_range() -> bool:
	return is_aware_of_player


# Plain cooldown/awareness/horizontal-range check, ticked every BT frame via
# the AttackReady leaf (bt_attack_ready.gd) — same pattern as
# MeleeGroundEnemy. No hop-timing requirement: it can trigger the instant
# these conditions are true, not just right as a hop peaks.
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
