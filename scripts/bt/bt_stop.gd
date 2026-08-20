@tool
extends BTAction
## Zeroes the agent's velocity. Fallback branch for when there's nothing
## better to do (currently: player out of range) — without this, an enemy
## that loses its target mid-chase would keep flying in a straight line
## forever, since nothing else would ever touch its velocity again.

func _generate_name() -> String:
	return "Stop"


func _tick(_delta: float) -> Status:
	agent.velocity = Vector2.ZERO
	return SUCCESS
