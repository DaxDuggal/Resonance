@tool
extends BTCondition
## Succeeds if the agent's ForwardRay is currently hitting something.
## Rays are repositioned/mirrored and force-updated by the agent every
## physics frame before the tree ticks, so this just reads the result.

func _generate_name() -> String:
	return "ForwardBlocked"


func _tick(_delta: float) -> Status:
	var forward_ray: RayCast2D = agent.get("forward_ray")
	if forward_ray.is_colliding():
		return SUCCESS
	return FAILURE
