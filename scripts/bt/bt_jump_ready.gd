@tool
extends BTCondition
## Succeeds if the agent is grounded and its jump cooldown has expired.
## Shared by both jump branches (hop-to-reach-player and hop-over-obstacle)
## so the cooldown/grounded rule only lives in one place.

func _generate_name() -> String:
	return "JumpReady"


func _tick(_delta: float) -> Status:
	var cooldown: float = agent.get("jump_cooldown_timer")
	if cooldown <= 0.0 and agent.is_on_floor():
		return SUCCESS
	return FAILURE
