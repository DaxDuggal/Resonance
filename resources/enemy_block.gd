extends Resource
class_name EnemyBlock

@export_range(0.0, 1.0) var damage_multiplier := 0.5
@export_range(0.0, 1.0) var player_recoil_multiplier := 0.15
@export_range(0.0, 1.0) var knockback_multiplier := 0.05
@export var stagger_duration := 0.05
@export var attack_lockout_duration := 0.8
@export_range(0.1, 100.0) var max_posture := 100.0
@export var posture_damage_per_hit := 20.0
@export var posture_damage_on_parry := 15.0
@export var posture_regen_delay := 1.5
@export var posture_regen_rate := 20.0
@export var guard_break_duration := 1.0
@export var posture_after_guard_break := 35.0
