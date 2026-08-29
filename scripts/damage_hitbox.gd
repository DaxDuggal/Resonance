extends Area2D
class_name DamageHitbox

# Generic "this deals damage to whatever detects it" payload. Deliberately
# passive — it doesn't scan for anything itself (monitoring = false in the
# scene), it just sits there with monitorable = true and a damage value,
# waiting for something else's hurtbox to detect it and read the value off.
# Reusable for any future damage source (enemy contact, projectiles, etc.),
# not enemy-specific.
@export var damage := 1
@export var knockback_force := 420.0  # 0 = no knockback. Horizontal component of the push (away from this hitbox); see knockback_vertical_ratio for the vertical part.
@export var knockback_vertical_ratio := 0.35  # vertical "pop" as a fraction of knockback_force — kept deliberately smaller than horizontal so knockback reads as a sideways shove, not a launch

# If set (nonzero), whoever detects this hitbox should knock back exactly
# along this direction instead of computing "away from this hitbox's
# position" — used by the player's AttackHitbox/SpecialHitbox so an up/down
# attack sends enemies up/down rather than always sideways. Left at
# Vector2.ZERO for hitboxes that should keep the old position-based
# behavior (enemy contact Hitbox, hazards, etc.).
@export var knockback_direction_override := Vector2.ZERO
