extends CharacterBody2D
class_name Enemy

@export_group("Health")
@export var max_health := 5.0
var current_health := 5.0

@export_group("Contact Damage")
@export var contact_damage := 1

@export_group("Knockback")
@export var knockback_stun_duration := 0.2
var knockback_stun_timer := 0.0

var is_dead := false

@export var world_state_id: String = ""

@export_group("Attack")
@export var attack_profile: AttackProfile

enum AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }
var attack_phase: AttackPhase = AttackPhase.NONE
var attack_phase_timer := 0.0
var attack_cooldown_timer := 0.0

# Sight/awareness: a facing-relative cone out to sight_range, occluded by
# World geometry (so a floor/wall between agent and player blocks it), plus
# a small point-blank radius that ignores facing and occlusion entirely —
# an enemy always notices something right up against it, even from directly
# behind. awareness_memory_time keeps is_aware_of_player true for a short
# grace window after sight is actually lost, so a single flickered frame
# doesn't read as the enemy instantly forgetting them.
#
# has_aggro is separate and stickier: once the agent has ever seen the
# player, it keeps chasing (ignoring facing/occlusion entirely) until either
# the player gets past aggro_leash_range, or _clear_aggro() is called (wired
# to the agent's VisibleOnScreenEnabler2D "screen_exited" signal in each
# enemy scene, so losing aggro currently just means "went off-screen").
@export_group("Awareness")
@export var sight_range := 350.0
@export var sight_angle_degrees := 100.0
@export var close_range_awareness := 70.0
@export var awareness_memory_time := 0.6
@export var aggro_leash_range := 900.0
@export var debug_show_awareness := true

var facing_direction := 1
var is_aware_of_player := false
var has_aggro := false
var _awareness_memory_timer := 0.0

@onready var attack_hitbox: DamageHitbox = get_node_or_null("AttackHitbox")
@onready var attack_hitbox_shape: CollisionShape2D = get_node_or_null("AttackHitbox/CollisionShape2D")
@onready var contact_hitbox_shape: CollisionShape2D = get_node_or_null("Hitbox/HitboxShape")


func _get_world_state_id() -> String:
	if world_state_id != "":
		return world_state_id
	return get_tree().current_scene.scene_file_path + "::" + str(get_path())


func _ready() -> void:
	if WorldState.is_resolved(_get_world_state_id()):
		is_dead = true
		queue_free()
		return

	current_health = max_health

	if has_node("Hitbox"):
		$Hitbox.damage = contact_damage

	if has_node("Hurtbox") and not $Hurtbox.is_connected("area_entered", Callable(self, "_on_hurtbox_area_entered")):
		$Hurtbox.connect("area_entered", Callable(self, "_on_hurtbox_area_entered"))

	if attack_hitbox and attack_profile:
		attack_hitbox.damage = attack_profile.damage
		attack_hitbox.knockback_force = attack_profile.knockback_force
		attack_hitbox.knockback_vertical_ratio = attack_profile.knockback_vertical_ratio
		attack_hitbox.is_parryable = attack_profile.is_parryable


# Generic windup -> active -> recovery -> cooldown state machine, driven by
# attack_profile (an AttackProfile resource) so any enemy can define its own
# attack timing/damage/knockback as data instead of duplicating this logic.
# Subclasses call _tick_attack(delta) every physics frame, read attack_phase
# to drive their own movement per phase (this base class only owns timing +
# the attack hitbox's enabled state, not motion), and call start_attack()
# once their own trigger condition (range, facing, altitude, whatever) is met.
func is_attacking() -> bool:
	return attack_phase != AttackPhase.NONE


func can_start_attack() -> bool:
	return not is_dead and attack_phase == AttackPhase.NONE and attack_cooldown_timer <= 0.0 and attack_profile != null


func start_attack() -> void:
	if not can_start_attack():
		return
	attack_phase = AttackPhase.STARTUP
	attack_phase_timer = attack_profile.startup_duration
	# Suppress the passive contact hitbox for the whole attack — otherwise it
	# and AttackHitbox can both be overlapping the player at once and double-hit.
	if contact_hitbox_shape:
		contact_hitbox_shape.disabled = true


func _tick_attack(delta: float) -> void:
	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)

	if attack_phase == AttackPhase.NONE:
		return

	attack_phase_timer = maxf(attack_phase_timer - delta, 0.0)
	if attack_phase_timer > 0.0:
		return

	match attack_phase:
		AttackPhase.STARTUP:
			attack_phase = AttackPhase.ACTIVE
			attack_phase_timer = attack_profile.active_duration
			if attack_hitbox_shape:
				attack_hitbox_shape.disabled = false
		AttackPhase.ACTIVE:
			attack_phase = AttackPhase.RECOVERY
			attack_phase_timer = attack_profile.recovery_duration
			if attack_hitbox_shape:
				attack_hitbox_shape.disabled = true
		AttackPhase.RECOVERY:
			attack_phase = AttackPhase.NONE
			attack_cooldown_timer = attack_profile.cooldown
			if contact_hitbox_shape:
				contact_hitbox_shape.disabled = false


func _update_awareness(delta: float) -> void:
	if _can_see_player():
		is_aware_of_player = true
		has_aggro = true
		_awareness_memory_timer = awareness_memory_time
	else:
		_awareness_memory_timer = maxf(_awareness_memory_timer - delta, 0.0)
		is_aware_of_player = _awareness_memory_timer > 0.0

	if has_aggro:
		if not Global.player or global_position.distance_to(Global.player.global_position) > aggro_leash_range:
			has_aggro = false
		else:
			is_aware_of_player = true

	if debug_show_awareness:
		queue_redraw()


# Debug-only visualization of the sight cone (yellow, turns red once
# aggro'd), the point-blank radius (white), and the aggro leash range while
# aggro'd (red outline). Toggle debug_show_awareness off per-enemy, or flip
# the default above, once you're done tuning these values.
func _draw() -> void:
	if not debug_show_awareness:
		return

	var cone_color := Color(1.0, 0.15, 0.15, 0.18) if has_aggro else Color(1.0, 0.9, 0.2, 0.18)
	var facing_vec := Vector2(float(facing_direction), 0.0)
	var half_angle := deg_to_rad(sight_angle_degrees * 0.5)
	var segments := 20
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var space := get_world_2d().direct_space_state
	for i in range(segments + 1):
		var t: float = lerp(-half_angle, half_angle, float(i) / float(segments))
		var dir := facing_vec.rotated(t)
		var reach := sight_range
		var params := PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = global_position + dir * sight_range
		params.collision_mask = 1  # World only — same mask the real sight check uses
		params.exclude = [self]
		var hit := space.intersect_ray(params)
		if hit:
			reach = global_position.distance_to(hit.position)
		points.append(dir * reach)
	draw_colored_polygon(points, cone_color)

	draw_arc(Vector2.ZERO, close_range_awareness, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.6), 2.0)

	if has_aggro:
		draw_arc(Vector2.ZERO, aggro_leash_range, 0.0, TAU, 48, Color(1.0, 0.2, 0.2, 0.4), 2.0)


# Fully drops aggro/awareness — wired to the agent's own VisibleOnScreenEnabler2D
# "screen_exited" signal, so going off-screen currently resets tracking rather
# than just pausing it (it comes back with a clean slate next time it's seen).
func _clear_aggro() -> void:
	has_aggro = false
	is_aware_of_player = false
	_awareness_memory_timer = 0.0


func _can_see_player() -> bool:
	if not Global.player:
		return false

	var to_player: Vector2 = Global.player.global_position - global_position
	var distance := to_player.length()
	if distance > sight_range:
		return false

	# Close range only waives the facing/cone requirement (so something
	# right up against the agent is noticed from any angle) — it must still
	# pass the occlusion check, otherwise a large enough radius can "see"
	# straight through a floor separating two stacked levels.
	if distance > close_range_awareness:
		var facing_vec := Vector2(float(facing_direction), 0.0)
		if rad_to_deg(absf(facing_vec.angle_to(to_player))) > sight_angle_degrees * 0.5:
			return false

	return _has_clear_sight_line()


func _has_clear_sight_line() -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.new()
	params.from = global_position
	params.to = Global.player.global_position
	params.collision_mask = 1  # World only
	params.exclude = [self]
	return space.intersect_ray(params).is_empty()


func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area is DamageHitbox:
		var hitbox := area as DamageHitbox
		var knockback_dir: Vector2
		if hitbox.knockback_direction_override != Vector2.ZERO:
			knockback_dir = hitbox.knockback_direction_override.normalized()
		else:
			var away_x := global_position.x - hitbox.global_position.x
			var horizontal_dir := signf(away_x) if absf(away_x) > 1.0 else 1.0
			knockback_dir = Vector2(horizontal_dir, -hitbox.knockback_vertical_ratio).normalized()
		var knockback := knockback_dir * hitbox.knockback_force
		take_damage(hitbox.damage, knockback)


func take_damage(amount: float, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	current_health = maxf(current_health - amount, 0.0)

	# Mid-attack (lunge/dive), knockback is ignored entirely — otherwise a
	# parry or a stray hit mid-swing shoves it off its attack path/timing,
	# which reads as the attack just breaking rather than committing.
	if knockback != Vector2.ZERO and not is_attacking():
		velocity += knockback
		knockback_stun_timer = knockback_stun_duration

	# Getting hit always alerts the agent, even from outside its sight cone
	# (a surprise attack from behind still gives away your position).
	has_aggro = true
	is_aware_of_player = true
	_awareness_memory_timer = awareness_memory_time

	if current_health <= 0.0:
		die()


func _tick_knockback_stun(delta: float) -> bool:
	knockback_stun_timer = maxf(knockback_stun_timer - delta, 0.0)
	return knockback_stun_timer > 0.0


func die() -> void:
	if is_dead:
		return
	is_dead = true
	WorldState.set_resolved(_get_world_state_id())
	queue_free()
