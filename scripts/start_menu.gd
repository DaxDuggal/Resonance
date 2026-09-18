extends Control

# Placeholder start screen (see TODO_ORDERED.md Phase 1) — just a full-screen
# rect and two buttons for now, no art/layout pass yet.

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_settings_pressed() -> void:
	pass  # Settings menu comes later — this button is a placeholder for now.
