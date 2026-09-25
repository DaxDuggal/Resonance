@tool
extends BTCondition
## Succeeds when this enemy can react to a nearby player attack.

@export var reaction_range := 75.0
@export var vertical_tolerance := 40.0


func _generate_name() -> String:
	return "ParryReady"


func _tick(_delta: float) -> Status:
	if not agent.has_method("can_start_parry") or not agent.call("can_start_parry"):
		return FAILURE
	if not Global.player:
		return FAILURE

	var offset: Vector2 = Global.player.global_position - agent.global_position
	if offset.length() > reaction_range or absf(offset.y) > vertical_tolerance:
		return FAILURE
	return SUCCESS
