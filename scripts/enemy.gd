extends CharacterBody2D
class_name Enemy

# Shared base for every enemy type: health, taking damage, dealing contact
# damage, and a lifetime cap. Deliberately does NOT own movement or gravity —
# a grounded chase-and-hop enemy and a future flying enemy won't move
# anything alike, so that's entirely up to each subclass's own
# _physics_process(). No shared "Creature" class with Player and no
# HealthComponent, per the earlier architecture decision — this duplicates
# the same small health block Player has rather than sharing one.

@export_group("Health")
@export var max_health := 2
var current_health := 2

@export_group("Lifetime")
@export var lifetime := 10.0  # seconds before this enemy despawns on its own, independent of health — a placeholder cap until real spawn/despawn triggers exist
var lifetime_timer := 0.0

@export_group("Contact Damage")
@export var contact_damage := 1

var is_dead := false


func _ready() -> void:
	current_health = max_health
	lifetime_timer = lifetime

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


# Placeholder: nothing calls into this yet since the player doesn't have a
# spatial attack hitbox to detect it with — take_damage() below is ready to
# be wired up the moment that exists.
func _on_hurtbox_area_entered(_area: Area2D) -> void:
	pass


func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	current_health = maxi(current_health - amount, 0)
	velocity += knockback

	if current_health <= 0:
		die()


func tick_lifetime(delta: float) -> void:
	if is_dead:
		return
	lifetime_timer = maxf(lifetime_timer - delta, 0.0)
	if lifetime_timer <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	queue_free()
