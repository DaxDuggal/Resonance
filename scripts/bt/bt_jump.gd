@tool
extends BTAction
## Fires the agent's jump (sets velocity.y, starts its cooldown) if grounded
## and off cooldown, else fails without touching anything. The readiness
## check lives here rather than in a separate condition leaf — "am I ready"
## isn't an independently useful fact for anything else in the tree, it only
## ever matters as a precondition to actually jumping, so there's no reuse
## to gain from splitting it out. Reused as two separate node instances in
## the tree (hop-to-reach-player and hop-over-obstacle) — same check both
## times regardless of which branch led here.

func _generate_name() -> String:
	return "Jump"


func _tick(_delta: float) -> Status:
	var cooldown: float = agent.get("jump_cooldown_timer")
	var on_floor: bool = agent.is_on_floor()
	if cooldown > 0.0 or not on_floor:
		return FAILURE
	agent.call("_jump")
	return SUCCESS
