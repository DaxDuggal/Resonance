@tool
extends BTCondition
## Succeeds while the player is in the attack state.

func _generate_name() -> String:
	return "PlayerAttacking"


func _tick(_delta: float) -> Status:
	if not Global.player:
		return FAILURE
	return SUCCESS if Global.player.has_flag(Player.Flag.ATTACKING) else FAILURE
