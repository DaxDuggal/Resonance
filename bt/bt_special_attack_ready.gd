@tool
extends BTCondition
## Checks the enemy-specific special attack through a shared BT interface.

func _generate_name() -> String:
	return "SpecialAttackReady"


func _tick(_delta: float) -> Status:
	if not agent.has_method("_is_special_attack_ready"):
		return FAILURE
	return SUCCESS if agent.call("_is_special_attack_ready") else FAILURE
