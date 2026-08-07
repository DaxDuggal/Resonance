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

# Swap the player's dash and unpause. Safe if the player isn't in the scene yet.
func _select_dash(dash_type: Player.DashType) -> void:
	if is_instance_valid(Global.player):
		Global.player.set_dash_ability(dash_type)
	resume()

func _on_resume_pressed() -> void:
	resume()

func _on_basic_pressed() -> void:
	_select_dash(Player.DashType.BASIC)

func _on_conch_shell_pressed() -> void:
	_select_dash(Player.DashType.CONCHSHELL)

func _on_bongos_pressed() -> void:
	_select_dash(Player.DashType.BONGOS)

func _on_panflute_pressed() -> void:
	_select_dash(Player.DashType.PANFLUTE)

func _on_restart_pressed() -> void:
	resume()
	# Player._ready() teleports to Global.last_checkpoint_position whenever
	# has_checkpoint is true — clear it so a manual restart goes back to
	# the scene's original spawn instead of the last checkpoint.
	Global.has_checkpoint = false
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()

# Event-driven instead of polling every frame in _process
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("esc"):
		if get_tree().paused:
			resume()
		else:
			pause()
		get_viewport().set_input_as_handled()
