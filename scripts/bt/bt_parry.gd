@tool
extends BTAction
## Starts the shared Enemy parry window. The base Enemy owns the timing so
## this action works for every enemy subclass without subclass-specific BT
## leaves. Damage-resolution behavior can consume Enemy.is_parrying() later.
##
## Leave this leaf unwired until the enemy-side parry response is implemented.

func _generate_name() -> String:
	return "Parry"


func _tick(_delta: float) -> Status:
	if not agent.has_method("start_parry"):
		return FAILURE
	return SUCCESS if agent.call("start_parry") else FAILURE
