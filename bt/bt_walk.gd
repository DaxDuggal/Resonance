@tool
extends BTAction
## Walks the agent at move_speed toward wherever facing_direction currently
## points (already kept aimed at the player by the agent's own
## _update_facing(), separate from this tree). Continuous action — always
## returns RUNNING.

func _generate_name() -> String:
	return "Walk"


func _tick(_delta: float) -> Status:
	var speed: float = agent.get("move_speed")
	var facing: int = agent.get("facing_direction")
	agent.velocity.x = speed * facing
	return RUNNING
