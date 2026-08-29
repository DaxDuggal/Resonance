extends Control

func _ready() -> void:
	visible = false

func resume() -> void:
	get_tree().paused = false
	Global.is_paused = false
	visible = false

func pause() -> void:
	get_tree().paused = true
	Global.is_paused = true
	visible = true

func _on_resume_pressed() -> void:
	resume()

# Instrument buttons — no-ops until the attack system exists.
func _on_basic_pressed() -> void:
	pass

func _on_conch_shell_pressed() -> void:
	pass

func _on_bongos_pressed() -> void:
	pass

func _on_panflute_pressed() -> void:
	pass

func _on_restart_pressed() -> void:
	resume()
	Global.has_checkpoint = false
	# Reloading the scene alone only resets the checkpoint/player — enemy
	# deaths persist through WorldState independently of that (see
	# world_state.gd / Checkpoint.activate()), so without this, restarting
	# would still show already-killed enemies as gone.
	WorldState.reset_resettable()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("esc"):
		if get_tree().paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
