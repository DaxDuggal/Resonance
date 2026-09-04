@tool
extends BTCondition
## Succeeds if the agent's own attack-readiness check passes. The exact
## trigger conditions (cooldown, range, facing, vertical tolerance, etc.)
## differ per enemy and stay owned by _is_attack_ready() on the agent
## script itself. Pair with StartAttack in a sequence.

func _generate_name() -> String:
	return "AttackReady"


func _tick(_delta: float) -> Status:
	if agent.call("_is_attack_ready"):
		return SUCCESS
	return FAILURE
