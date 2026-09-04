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
	velocity += knockback
	if knockback != Vector2.ZERO:
		knockback_stun_timer = knockback_stun_duration

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
