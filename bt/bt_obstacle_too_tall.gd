@tool
extends BTCondition
## Succeeds if the obstacle blocking ForwardRay is tall enough to also block
## ObstacleTopRay — i.e. too tall to hop over, so the agent should turn
## around instead of jumping.

func _generate_name() -> String:
	return "ObstacleTooTall"


func _tick(_delta: float) -> Status:
	var obstacle_top_ray: RayCast2D = agent.get("obstacle_top_ray")
	if obstacle_top_ray.is_colliding():
		return SUCCESS
	return FAILURE
