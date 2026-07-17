extends Area2D

@onready var timer: Timer = $Timer

func _on_body_entered(body):
	print("Game Over")
	body.state = body.PlayerState.DEAD
	Engine.time_scale = 0.7
	timer.start()

func _on_timer_timeout() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()
