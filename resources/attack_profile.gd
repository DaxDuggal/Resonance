extends Resource
class_name AttackProfile

@export_range(0, 600, 1) var startup_frames := 24
@export_range(0, 600, 1) var active_frames := 9
@export_range(0, 600, 1) var recovery_frames := 18
@export_range(0, 600, 1) var cooldown_frames := 72

@export var damage := 1
@export var knockback_force := 50.0
@export var knockback_vertical_ratio := 0.35
@export var is_parryable := true
@export var can_be_interrupted := false
