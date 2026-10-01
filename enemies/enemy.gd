extends CharacterBody2D
class_name Enemy

@export_group("Health")
@export var max_health := 5.0
var current_health := 5.0

@export_group("Contact Damage")
@export var contact_damage := 1

@export_group("Body Push")
@export var body_push_radius := 13.0
@export var body_push_half_height := 11.0

@export_group("Knockback")
@export var knockback_stun_duration := 0.2
@export var knockback_multiplier := 1.0
@export var can_be_interrupted_while_attacking := false
var knockback_stun_timer := 0.0

@export_group("Block")
@export var block_profile: EnemyBlock
var block_attack_lockout_timer := 0.0
var _block_attack_lockout_started := false
var posture := 0.0
var posture_regen_timer := 0.0
var guard_break_timer := 0.0

enum CombatState { NEUTRAL, BLOCKING, ATTACK_STARTUP, ATTACK_ACTIVE, ATTACK_RECOVERY, GUARD_BROKEN, STUNNED, KNOCKBACK }

@export_group("Hurt")
@export var player_hit_hitstop_frames := 5

# A full stop, distinct from knockback stun — no damage, no shove, just
# unable to attack or move under its own power for stun_timer seconds.
# Gravity/physics still apply (it can still fall, land, slide to a stop).
var stun_timer := 0.0

func stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)
	if is_attacking():
		_cancel_attack()

func _tick_stun(delta: float) -> bool:
	if stun_timer <= 0.0:
		return false
	stun_timer = maxf(stun_timer - delta, 0.0)
	return true


func _cancel_attack() -> void:
	attack_phase = AttackPhase.NONE
	attack_phase_timer = 0.0
	if attack_hitbox_shape:
		attack_hitbox_shape.set_deferred("disabled", true)
	if contact_hitbox_shape:
		contact_hitbox_shape.set_deferred("disabled", false)
	if attack_profile:
		attack_cooldown_timer = attack_profile.cooldown


func _can_interrupt_current_attack() -> bool:
	return can_be_interrupted_while_attacking or (attack_profile != null and attack_profile.can_be_interrupted)


func _process(delta: float) -> void:
	block_attack_lockout_timer = maxf(block_attack_lockout_timer - delta, 0.0)
	if block_profile and posture > 0.0:
		posture_regen_timer = maxf(posture_regen_timer - delta, 0.0)
		if posture_regen_timer <= 0.0 and not is_attacking() and guard_break_timer <= 0.0:
			posture = maxf(posture - block_profile.posture_regen_rate * delta, 0.0)


func is_blocking() -> bool:
	return block_profile != null \
		and not is_dead \
		and not is_attacking() \
		and stun_timer <= 0.0 \
		and guard_break_timer <= 0.0


func get_combat_state() -> CombatState:
	if is_dead:
		return CombatState.NEUTRAL
	if guard_break_timer > 0.0:
		return CombatState.GUARD_BROKEN
	if stun_timer > 0.0:
		return CombatState.STUNNED
	if is_attacking():
		match attack_phase:
			AttackPhase.STARTUP:
				return CombatState.ATTACK_STARTUP
			AttackPhase.ACTIVE:
				return CombatState.ATTACK_ACTIVE
			AttackPhase.RECOVERY:
				return CombatState.ATTACK_RECOVERY
	if is_blocking():
		return CombatState.BLOCKING
	if knockback_stun_timer > 0.0:
		return CombatState.KNOCKBACK
	return CombatState.NEUTRAL


func _tick_guard_break(delta: float) -> bool:
	if guard_break_timer <= 0.0:
		return false
	guard_break_timer = maxf(guard_break_timer - delta, 0.0)
	if guard_break_timer <= 0.0:
		posture = minf(posture, block_profile.posture_after_guard_break)
		posture_regen_timer = block_profile.posture_regen_delay
		return false
	return true


func _break_guard() -> void:
	guard_break_timer = block_profile.guard_break_duration
	block_attack_lockout_timer = maxf(block_attack_lockout_timer, guard_break_timer)
	if is_attacking():
		_cancel_attack()


func apply_posture_damage(amount: float) -> void:
	if is_dead or block_profile == null or guard_break_timer > 0.0:
		return
	posture = minf(posture + maxf(amount, 0.0), block_profile.max_posture)
	posture_regen_timer = block_profile.posture_regen_delay
	if posture >= block_profile.max_posture:
		_break_guard()


func _begin_attack() -> void:
	_block_attack_lockout_started = false


func block_player_recoil_multiplier() -> float:
	if not is_blocking():
		return 1.0
	return block_profile.player_recoil_multiplier


# Call every physics frame (subclasses call this after their own
# move_and_slide()) so the player and this enemy never overlap, except when
# the player is in a state that intentionally ignores enemy overlap.
func _apply_player_overlap_push() -> void:
	var player := Global.player
	if not player or is_dead:
		return
	if player.should_ignore_enemy_overlap():
		return

	var offset := global_position - player.global_position
	var min_dist_x := body_push_radius + player.body_push_radius
	var min_dist_y := body_push_half_height + player.body_push_half_height

	if absf(offset.y) >= min_dist_y or absf(offset.x) >= min_dist_x:
		return

	# Dead-center overlap has no direction to push along — fall back to
	# facing_direction instead of feeding sign() a zero and pushing nowhere.
	var push_dir := signf(offset.x)
	if push_dir == 0.0:
		push_dir = 1.0 if facing_direction == 0 else float(facing_direction)

	var half_push := (min_dist_x - absf(offset.x)) * 0.5
	global_position.x += push_dir * half_push
	player.global_position.x -= push_dir * half_push

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
@export var aggro_loss_delay := 10.0
@export var debug_show_awareness := true
@export var reaction_delay_duration := 0.5

var facing_direction := 1
var is_aware_of_player := false
var has_aggro := false
var _awareness_memory_timer := 0.0
var _aggro_loss_timer := 0.0
var reaction_delay_timer := 0.0
var _reaction_contact_hitbox_disabled := false

@onready var attack_hitbox: DamageHitbox = get_node_or_null("AttackHitbox")
@onready var attack_hitbox_shape: CollisionShape2D = get_node_or_null("AttackHitbox/CollisionShape2D")
@onready var contact_hitbox_shape: CollisionShape2D = get_node_or_null("Hitbox/HitboxShape")


func _get_world_state_id() -> String:
	if world_state_id != "":
		return world_state_id
	return get_tree().current_scene.scene_file_path + "::" + str(get_path())


func _ready() -> void:
	add_to_group("enemies")
	if WorldState.is_resolved(_get_world_state_id()):
		is_dead = true
		queue_free()
		return

	if block_profile == null:
		block_profile = EnemyBlock.new()
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
	return not is_dead \
		and attack_phase == AttackPhase.NONE \
		and attack_cooldown_timer <= 0.0 \
		and block_attack_lockout_timer <= 0.0 \
		and guard_break_timer <= 0.0 \
		and reaction_delay_timer <= 0.0 \
		and stun_timer <= 0.0 \
		and knockback_stun_timer <= 0.0 \
		and attack_profile != null


func is_reacting_to_player() -> bool:
	return reaction_delay_timer > 0.0


func start_attack() -> void:
	if not can_start_attack():
		return
	_begin_attack()
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
	reaction_delay_timer = maxf(reaction_delay_timer - delta, 0.0)
	if _can_see_player():
		if not has_aggro and reaction_delay_duration > 0.0:
			reaction_delay_timer = reaction_delay_duration
			if contact_hitbox_shape:
				contact_hitbox_shape.set_deferred("disabled", true)
				_reaction_contact_hitbox_disabled = true
		is_aware_of_player = true
		has_aggro = true
		_awareness_memory_timer = awareness_memory_time
	else:
		_awareness_memory_timer = maxf(_awareness_memory_timer - delta, 0.0)
		is_aware_of_player = _awareness_memory_timer > 0.0

	if has_aggro:
		if not Global.player or global_position.distance_to(Global.player.global_position) > aggro_leash_range:
			_aggro_loss_timer = maxf(_aggro_loss_timer - delta, 0.0)
			if _aggro_loss_timer <= 0.0:
				has_aggro = false
		else:
			_aggro_loss_timer = aggro_loss_delay
			is_aware_of_player = true

	if reaction_delay_timer <= 0.0 and _reaction_contact_hitbox_disabled:
		contact_hitbox_shape.set_deferred("disabled", false)
		_reaction_contact_hitbox_disabled = false

	if debug_show_awareness:
		queue_redraw()


# Debug-only visualization of the sight cone (yellow, turns red once
# aggro'd), the point-blank radius (white), and the aggro leash range while
# aggro'd (red outline). Toggle debug_show_awareness off per-enemy, or flip
# the default above, once you're done tuning these values.
func _draw() -> void:
	if debug_show_awareness:
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
			params.collision_mask = 1
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
	if has_aggro:
		_aggro_loss_timer = aggro_loss_delay


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
		await Global.hitstop(Global.frames_to_seconds(player_hit_hitstop_frames))
		if is_dead or not is_instance_valid(hitbox):
			return
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

	var blocked_hit := is_blocking()
	var applied_knockback_stun_duration := knockback_stun_duration
	if blocked_hit:
		amount *= block_profile.damage_multiplier
		knockback *= block_profile.knockback_multiplier
		applied_knockback_stun_duration = block_profile.stagger_duration
		if not _block_attack_lockout_started:
			block_attack_lockout_timer = block_profile.attack_lockout_duration
			_block_attack_lockout_started = true

	apply_posture_damage(block_profile.posture_damage_per_hit)
	current_health = maxf(current_health - amount, 0.0)

	# Mid-attack knockback is ignored by default so a hit does not break a
	# committed attack. Tanky enemies/attacks can opt into interruption
	# through can_be_interrupted_while_attacking or AttackProfile.
	if knockback != Vector2.ZERO:
		if is_attacking() and _can_interrupt_current_attack():
			_cancel_attack()
		if not is_attacking():
			velocity += knockback * knockback_multiplier
			knockback_stun_timer = maxf(knockback_stun_timer, applied_knockback_stun_duration)
	if blocked_hit and not is_attacking():
		knockback_stun_timer = maxf(knockback_stun_timer, applied_knockback_stun_duration)

	# Getting hit always alerts the agent, even from outside its sight cone
	# (a surprise attack from behind still gives away your position).
	has_aggro = true
	is_aware_of_player = true
	_awareness_memory_timer = awareness_memory_time
	_aggro_loss_timer = aggro_loss_delay

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
