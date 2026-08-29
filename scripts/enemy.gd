extends CharacterBody2D
class_name Enemy

# Shared base for every enemy type: health, taking damage, and dealing
# contact damage. Deliberately does NOT own movement or gravity — a grounded
# chase-and-hop enemy and a flying enemy won't move anything alike, so
# that's entirely up to each subclass's own _physics_process(). No shared
# "Creature" class with Player and no HealthComponent, per the earlier
# architecture decision — this duplicates the same small health block
# Player has rather than sharing one.
#
# Enemies live indefinitely for now — no time-based despawn. Death is
# purely health-driven (take_damage() -> die() at 0 HP) — a successful
# player parry no longer instant-kills, it just deals parry_damage like any
# other hit (see player.gd's _on_parry_success()).
#
# Health is a float, not an int: a normal attack currently does 1 damage but
# a parry only does 0.5 (player.gd's attack_damage / parry_damage), so whole
# numbers alone can't represent every valid health value. Placeholder
# balance numbers throughout — expect these to change.

@export_group("Health")
@export var max_health := 5.0
var current_health := 5.0

@export_group("Contact Damage")
@export var contact_damage := 1

@export_group("Knockback")
@export var knockback_stun_duration := 0.2  # how long a nonzero knockback hit suppresses this enemy's own movement/AI control — without it, each subclass's behavior tree hard-sets velocity every physics frame and stomps the knockback impulse before it's ever visible
var knockback_stun_timer := 0.0

var is_dead := false

# Optional manual override for the WorldState persistence ID — leave blank
# to auto-derive one from this instance's scene path + node path (stable as
# long as the node isn't moved/renamed in the tree), which is enough for
# every hand-placed enemy in a level. Only needed for edge cases an
# auto-derived ID can't cover, e.g. an enemy spawned dynamically at runtime
# rather than placed in the scene file.
@export var world_state_id: String = ""


func _get_world_state_id() -> String:
	if world_state_id != "":
		return world_state_id
	return get_tree().current_scene.scene_file_path + "::" + str(get_path())


func _ready() -> void:
	# Already killed since the last checkpoint rest — don't even set up,
	# just remove. Scene reload (every player death) re-instances this node
	# fresh from the .tscn with no memory of its own, so this check is the
	# only thing standing between "killed" and "back at full health at its
	# spawn point" on the very next death.
	if WorldState.is_resolved(_get_world_state_id()):
		is_dead = true
		queue_free()
		return

	current_health = max_health

	# Detection direction is player.gd -> enemy's Hitbox, not the other way
	# around: the Hitbox is a passive DamageHitbox (monitoring = false,
	# monitorable = true in the scene) and player.gd's own Hurtbox signal
	# handler reads its damage value directly when it detects it. This just
	# keeps that damage value in sync with contact_damage so it can still be
	# tuned in one place (this node's Inspector) per enemy type.
	if has_node("Hitbox"):
		$Hitbox.damage = contact_damage

	if has_node("Hurtbox") and not $Hurtbox.is_connected("area_entered", Callable(self, "_on_hurtbox_area_entered")):
		$Hurtbox.connect("area_entered", Callable(self, "_on_hurtbox_area_entered"))


# Player's AttackHitbox/SpecialHitbox (player.tscn) are DamageHitboxes on
# the layer named "PlayerHurtbox" in project settings (32) — a mislabel
# left over from earlier setup (the player's own damage-receiving Hurtbox
# actually sits on the layer named "PlayerHitbox", 8) but functionally it's
# just the free slot used for the player's outgoing attack hitboxes; each
# enemy's own Hurtbox mask includes it (48 = 16 | 32). Not touching the
# existing Hurtbox's layer to fix the naming mismatch — out of scope here
# and it works correctly as-is.
func _on_hurtbox_area_entered(area: Area2D) -> void:
	if area is DamageHitbox:
		# Explicit cast, not just the "if area is DamageHitbox" check above —
		# GDScript's static analyzer doesn't narrow area's declared type from
		# that check alone, so area.knockback_force etc. below would still
		# read as Variant and fail to infer the knockback Vector2's type.
		var hitbox := area as DamageHitbox
		var knockback_dir: Vector2
		if hitbox.knockback_direction_override != Vector2.ZERO:
			# Player attack hitboxes set this to attack_direction — an
			# up/down attack knocks straight up/down instead of always
			# sideways-away-from-the-hitbox.
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


# Call from each subclass's _physics_process, before it ticks its own AI —
# tick the timer and report whether movement/AI should be suppressed this
# frame so the knockback impulse above actually gets to move the enemy
# instead of being immediately overwritten.
func _tick_knockback_stun(delta: float) -> bool:
	knockback_stun_timer = maxf(knockback_stun_timer - delta, 0.0)
	return knockback_stun_timer > 0.0


func die() -> void:
	if is_dead:
		return
	is_dead = true
	# Resettable, not permanent: stays dead across ordinary deaths/reloads,
	# but comes back once the player rests at a checkpoint again (see
	# Checkpoint.activate() -> WorldState.reset_resettable()).
	WorldState.set_resolved(_get_world_state_id())
	queue_free()
