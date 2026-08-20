@tool
extends BTAction
## Steers the agent's velocity straight at Global.player at agent.move_speed.
## Direct hover-chase per current scope — no altitude-holding, no obstacle
## avoidance. Continuous action, so it always returns RUNNING rather than
## SUCCESS; the tree re-evaluates from the root every tick anyway since
## FlyingEnemy calls BTPlayer.update() manually every physics frame.

func _generate_name() -> String:
	return "ChasePlayer"


func _tick(_delta: float) -> Status:
	if not Global.player:
		return FAILURE
	var speed: float = agent.get("move_speed")
	var direction: Vector2 = (Global.player.global_position - agent.global_position).normalized()
	agent.velocity = direction * speed
	return RUNNING
