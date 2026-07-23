extends Control

func _ready():
	visible = false

func resume():
	get_tree().paused = false
	Global.is_paused = false
	visible = false

func pause():
	get_tree().paused = true
	Global.is_paused = true
	visible = true

func testEsc():
	if Input.is_action_just_pressed("esc") and get_tree().paused == false:
		pause()
	elif Input.is_action_just_pressed("esc") and get_tree().paused == true:
		resume()

func _on_resume_pressed() -> void:
	resume()

func _on_basic_pressed() -> void:
	Global.player.set_dash_ability(Player.DashType.BASIC)
	resume()

func _on_bongos_pressed() -> void:
	Global.player.set_dash_ability(Player.DashType.BONGOS)
	resume()

func _on_panflute_pressed() -> void:
	Global.player.set_dash_ability(Player.DashType.PANFLUTE)
	resume()

func _on_restart_pressed() -> void:
	resume()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _process(delta):
	testEsc()
