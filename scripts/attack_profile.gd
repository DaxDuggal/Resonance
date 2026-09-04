extends Resource
class_name AttackProfile

@export var startup_duration := 0.4
@export var active_duration := 0.15
@export var recovery_duration := 0.3
@export var cooldown := 1.2

@export var damage := 1
@export var knockback_force := 200.0
@export var knockback_vertical_ratio := 0.35
@export var is_parryable := true
