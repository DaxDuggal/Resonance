extends Enemy
class_name FlyingEnemy

@export_group("Movement")
@export var move_speed := 130.0
@export var hover_height := 40.0
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

@export_group("Swipe Attack")
@export var swipe_range := 72.0
@export var swipe_trigger_range := 100.0
@export var swipe_vertical_tolerance := 55.0
@export var swipe_approach_speed := 200.0
@export var swipe_vertical_approach_speed := 420.0
@export var swipe_startup_duration := 0.28
@export var swipe_active_duration := 0.16
@export var swipe_recovery_duration := 0.28

@export_group("Dive Attack")
@export var dive_horizontal_distance := 200.0
@export var dive_trigger_min_x := 50.0
@export var dive_trigger_range := 500.0
@export var dive_rise_height := 50.0
@export var dive_rise_speed := 330.0
@export var dive_below_hover_distance := 50.0
@export var min_chase_distance := 30.0

enum FlyingAttack { NONE, SWIPE, DIVE }
var selected_attack := FlyingAttack.NONE

var _dive_launched := false
var _dive_p0 := Vector2.ZERO
var _dive_p1 := Vector2.ZERO
var _dive_p2 := Vector2.ZERO
var _dive_p3 := Vector2.ZERO
var _swipe_hitbox_editor_position := Vector2.ZERO
var _swipe_hitbox_shape_editor_position := Vector2.ZERO

@onready var visual: Polygon2D = $Placeholder
@onready var ground_ray: RayCast2D = $GroundRay
@onready var bt_player: BTPlayer = $BTPlayer
@onready var swipe_hitbox: DamageHitbox = $SwipeHitbox
@onready var swipe_hitbox_shape: CollisionShape2D = $SwipeHitbox/CollisionShape2D
@onready var swipe_hitbox_visual: ColorRect = $SwipeHitbox/CollisionShape2D/Visual


func _ready() -> void:
	super._ready()
	_spawn_y = global_position.y
	_swipe_hitbox_editor_position = swipe_hitbox.position
	_swipe_hitbox_shape_editor_position = swipe_hitbox_shape.position
	swipe_hitbox.damage = attack_profile.damage
	swipe_hitbox.knockback_force = attack_profile.knockback_force
	swipe_hitbox.knockback_vertical_ratio = attack_profile.knockback_vertical_ratio
	swipe_hitbox.is_parryable = attack_profile.is_parryable
	_update_swipe_hitbox_transform()
	_sync_swipe_hitbox_visual()
	# BT now owns the horizontal decision (back away/chase/hold) and attack
	# triggering (BasicAttack/SpecialAttack) — see the leaves under
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
		_apply_player_overlap_push()
		return

	_tick_attack(delta)

	if _tick_knockback_stun(delta):
		move_and_slide()
		_apply_player_overlap_push()
		return

	_update_attack_visual()

	if is_attacking():
		_process_attack(delta)
		move_and_slide()
		_apply_player_overlap_push()
		return

	_apply_hover(delta)
	bt_player.update(delta)

	if absf(velocity.x) > 5.0:
		facing_direction = int(signf(velocity.x))
		_update_swipe_hitbox_transform()

	move_and_slide()
	_apply_player_overlap_push()


# Charging telegraph: flash red during STARTUP, same as Tusker.
func _update_attack_visual() -> void:
	if attack_phase == AttackPhase.STARTUP and selected_attack == FlyingAttack.DIVE:
		visual.modulate = Color(0.25, 0.55, 1.0)
	else:
		visual.modulate = Color(1.0, 0.3, 0.3) if attack_phase == AttackPhase.STARTUP else Color.WHITE
	swipe_hitbox_visual.visible = selected_attack == FlyingAttack.SWIPE and attack_phase == AttackPhase.ACTIVE


func _sync_swipe_hitbox_visual() -> void:
	var rectangle := swipe_hitbox_shape.shape as RectangleShape2D
	if rectangle == null:
		return
	swipe_hitbox_visual.position = -rectangle.size * 0.5
	swipe_hitbox_visual.size = rectangle.size


func _update_swipe_hitbox_transform() -> void:
	swipe_hitbox.position = _mirrored_position(_swipe_hitbox_editor_position)
	swipe_hitbox_shape.position = _mirrored_position(_swipe_hitbox_shape_editor_position)


func _mirrored_position(editor_position: Vector2) -> Vector2:
	var mirrored := editor_position
	mirrored.x = absf(editor_position.x) * facing_direction
	return mirrored


func stun(duration: float) -> void:
	super.stun(duration)
	if swipe_hitbox_shape:
		swipe_hitbox_shape.disabled = true
	if swipe_hitbox_visual:
		swipe_hitbox_visual.visible = false


func _cancel_attack() -> void:
	super._cancel_attack()
	if swipe_hitbox_shape:
		swipe_hitbox_shape.disabled = true
	if swipe_hitbox_visual:
		swipe_hitbox_visual.visible = false


# Vertical-only now — horizontal movement (back away/chase/hold) moved to
# the BT tree (bt_player_too_close.gd, bt_player_too_far.gd, bt_back_away.gd,
# bt_chase_horizontal.gd, bt_hold_horizontal.gd). Runs every non-attacking
# physics frame regardless of what the tree decides, same as
# MeleeGroundEnemy's _apply_gravity().
#
# Targets a fixed height above the ground directly below (via GroundRay);
# this line also doubles as the dive's "home" line (see _is_attack_ready).
#
# The hop is a sharp wingbeat, not a ballistic arc: hop_impulse fires it
# upward and hop_rise_drag burns that rise off quickly, independent of
# gravity, so it reads as a snappy pop rather than a floaty rise or an
# over-strong climb/fall.
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
	return distance_x < swipe_range


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


# Fixed, precomputed 4-point Bezier curve rather than a physics/floor
# reaction. P1/P2 use a shared control-point height, giving a flattened
# "hangs at the bottom" middle instead of a sharp V. The control-point height
# includes the rise height, so the curve's actual low point passes below the
# normal hover line before returning to launch height (P3 mirrors P0).
#
# Direction is locked in at launch, not homed on the player mid-dive.
# RECOVERY lets gravity settle it back into _apply_hover once the attack ends.
func _process_attack(delta: float) -> void:
	match attack_phase:
		AttackPhase.STARTUP:
			if selected_attack == FlyingAttack.DIVE:
				velocity.x = 0.0
				var rise_target_y := _spawn_y - dive_rise_height
				velocity.y = -dive_rise_speed if global_position.y > rise_target_y else 0.0
			elif selected_attack == FlyingAttack.SWIPE:
				var approach_direction := float(facing_direction)
				if Global.player:
					var to_player_x := Global.player.global_position.x - global_position.x
					if absf(to_player_x) > 1.0:
						approach_direction = signf(to_player_x)
						facing_direction = int(approach_direction)
				_update_swipe_hitbox_transform()
				velocity.x = approach_direction * swipe_approach_speed
				var vertical_difference := Global.player.global_position.y - global_position.y if Global.player else 0.0
				velocity.y = clampf(vertical_difference / attack_phase_timer, -swipe_vertical_approach_speed, swipe_vertical_approach_speed)
			else:
				velocity = Vector2.ZERO
			_dive_launched = false
			hop_timer = 0.0
		AttackPhase.ACTIVE:
			if selected_attack == FlyingAttack.SWIPE:
				velocity = Vector2.ZERO
				return

			if not _dive_launched:
				var dir := 1.0
				if Global.player:
					dir = signf(Global.player.global_position.x - global_position.x)
				if dir == 0.0:
					dir = float(facing_direction)
				facing_direction = int(signf(dir))

				_dive_p0 = Vector2.ZERO
				# The control-point offset includes the height gained during
				# startup, so the curve's real low point passes below the
				# normal hover line instead of ending above the player.
				var dive_control_y := (dive_rise_height + dive_below_hover_distance) / 0.75
				_dive_p1 = Vector2(dir * dive_horizontal_distance * 0.25, dive_control_y)
				_dive_p2 = Vector2(dir * dive_horizontal_distance * 0.75, dive_control_y)
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


func _is_swipe_ready() -> bool:
	if not can_start_attack() or not _player_in_range():
		return false
	var to_player := Global.player.global_position - global_position
	if absf(to_player.x) > 1.0:
		facing_direction = int(signf(to_player.x))
	_update_swipe_hitbox_transform()
	return absf(to_player.x) <= swipe_trigger_range and absf(to_player.y) <= swipe_vertical_tolerance


func start_swipe() -> bool:
	if not _is_swipe_ready():
		return false
	selected_attack = FlyingAttack.SWIPE
	_update_swipe_hitbox_transform()
	attack_phase = AttackPhase.STARTUP
	attack_phase_timer = swipe_startup_duration
	if contact_hitbox_shape:
		contact_hitbox_shape.disabled = true
	return true


func _is_dive_ready() -> bool:
	if not can_start_attack() or not _player_in_range():
		return false
	var distance_x := absf(Global.player.global_position.x - global_position.x)
	_face_player()
	return distance_x >= dive_trigger_min_x and distance_x <= dive_trigger_range


func start_dive() -> bool:
	if not _is_dive_ready():
		return false
	selected_attack = FlyingAttack.DIVE
	start_attack()
	return is_attacking()


func _is_basic_attack_ready() -> bool:
	return _is_swipe_ready()


func start_basic_attack() -> bool:
	return start_swipe()


func _is_special_attack_ready() -> bool:
	return _is_dive_ready()


func start_special_attack() -> bool:
	return start_dive()


func _face_player() -> void:
	if not Global.player:
		return
	var to_player_x := Global.player.global_position.x - global_position.x
	if absf(to_player_x) <= 1.0:
		return
	facing_direction = int(signf(to_player_x))
	_update_swipe_hitbox_transform()


# Swipe uses the same shared attack phases as the base class, but has its own
# short timing so it reads as a quick close-range attack instead of reusing
# the dive's longer profile.
func _tick_attack(delta: float) -> void:
	if selected_attack != FlyingAttack.SWIPE:
		super._tick_attack(delta)
		return

	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)
	if attack_phase == AttackPhase.NONE:
		return

	attack_phase_timer = maxf(attack_phase_timer - delta, 0.0)
	if attack_phase_timer > 0.0:
		return

	match attack_phase:
		AttackPhase.STARTUP:
			attack_phase = AttackPhase.ACTIVE
			attack_phase_timer = swipe_active_duration
			if swipe_hitbox_shape:
				swipe_hitbox_shape.disabled = false
		AttackPhase.ACTIVE:
			attack_phase = AttackPhase.RECOVERY
			attack_phase_timer = swipe_recovery_duration
			if swipe_hitbox_shape:
				swipe_hitbox_shape.disabled = true
		AttackPhase.RECOVERY:
			attack_phase = AttackPhase.NONE
			attack_cooldown_timer = attack_profile.cooldown
			if contact_hitbox_shape:
				contact_hitbox_shape.disabled = false
			selected_attack = FlyingAttack.NONE


# Plain cooldown/awareness/horizontal-range check, ticked every BT frame via
# the shared attack readiness leaves — same pattern as
# MeleeGroundEnemy. No hop-timing requirement: it can trigger the instant
# these conditions are true, not just right as a hop peaks.
func _is_attack_ready() -> bool:
	return _is_dive_ready()
