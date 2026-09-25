@tool
extends BTCondition
## Succeeds if the agent is grounded and LedgeRay finds no ground ahead —
## about to walk off a ledge. Only relevant while grounded; airborne agents
## skip this check entirely (matches original _decide_movement behavior).

func _generate_name() -> String:
	return "AtLedge"


func _tick(_delta: float) -> Status:
	var ledge_ray: RayCast2D = agent.get("ledge_ray")
	if agent.is_on_floor() and not ledge_ray.is_colliding():
		return SUCCESS
	return FAILURE
