@tool
extends BTAction
## Eases the agent's horizontal velocity toward Global.player at
## move_speed. Horizontal-only — vertical movement stays fully owned by
## the agent's own hover physics. Continuous action, always returns
## RUNNING (see BackAway for why that's fine here).
##
## Distinct from bt_chase_player.gd, which drives full 2D velocity
## straight at the player and expects to own vertical movement too — not
## a fit for an agent whose altitude is a separate hover system.

func _generate_name() -> String:
	return "ChaseHorizontal"


func _tick(delta: float) -> Status:
	if not Global.player:
		return FAILURE
	var move_speed: float = agent.get("move_speed")
	var accel_mult: float = agent.get("flight_accel_mult")
	var to_player_x: float = Global.player.global_position.x - agent.global_position.x
	var direction: float = signf(to_player_x)
	agent.velocity.x = move_toward(agent.velocity.x, direction * move_speed, move_speed * accel_mult * delta)
	return RUNNING
