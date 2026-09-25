@tool
extends BTAction
## Zeroes only horizontal velocity, leaving vertical velocity untouched —
## unlike Stop (used by flying enemies), grounded agents still own gravity
## and jump arcs on the y-axis even while idle/blocked, so this must not
## clobber velocity.y. Instant, one-shot — always returns SUCCESS.

func _generate_name() -> String:
	return "HaltHorizontal"


func _tick(_delta: float) -> Status:
	agent.velocity.x = 0.0
	return SUCCESS
