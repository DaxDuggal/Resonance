@tool
extends BTAction
## Eases the agent's horizontal velocity away from Global.player at
## move_speed. Horizontal-only — vertical movement stays fully owned by
## the agent's own hover physics, which keeps running every physics frame
## regardless of what this tree decides. Continuous action, so it always
## returns RUNNING; the tree re-evaluates from the root every tick anyway
## since the agent calls BTPlayer.update() manually every physics frame.

func _generate_name() -> String:
	return "BackAway"


func _tick(delta: float) -> Status:
	if not Global.player:
		return FAILURE
	var move_speed: float = agent.get("move_speed")
	var accel_mult: float = agent.get("flight_accel_mult")
	var to_player_x: float = Global.player.global_position.x - agent.global_position.x
	var away_dir: float = -signf(to_player_x) if to_player_x != 0.0 else -float(agent.get("facing_direction"))
	agent.velocity.x = move_toward(agent.velocity.x, away_dir * move_speed, move_speed * accel_mult * delta)
	return RUNNING
