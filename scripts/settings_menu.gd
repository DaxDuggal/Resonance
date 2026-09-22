extends Control

# Shell created from the Start Menu scene. Settings behavior is intentionally
# deferred to a later implementation pass.

func _on_start_pressed() -> void:
	# Keep scene changes consistent with the rest of the game: a pending
	# hitstop should never carry across the transition into the gameplay scene.
	Global.reset_hitstop()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_settings_pressed() -> void:
	pass
