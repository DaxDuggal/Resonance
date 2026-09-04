@tool
extends BTCondition
## Succeeds if the player is in range but standing above the agent's lunge
## reach (e.g. perched directly on top of it). This is the "can't attack
## from here at all" case, distinct from just being on cooldown — paired
## with HaltHorizontal so the agent waits in place instead of turning
## around or walking into/under the player.

func _generate_name() -> String:
	return "PlayerOverhead"


func _tick(_delta: float) -> Status:
	if agent.call("_is_player_overhead"):
		return SUCCESS
	return FAILURE
