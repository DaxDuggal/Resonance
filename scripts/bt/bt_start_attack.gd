@tool
extends BTAction
## Starts the agent's attack (enters AttackPhase.STARTUP via the shared
## Enemy base class). Always place directly after AttackReady in a
## sequence — this assumes readiness was already confirmed this tick.

func _generate_name() -> String:
	return "StartAttack"


func _tick(_delta: float) -> Status:
	agent.call("start_attack")
	return SUCCESS
