extends CanvasLayer

# Minimal placeholder HUD — plain text labels, no bars/icons/art yet (Phase
# 2 of TODO_ORDERED.md). Exists mainly so health/meter state is actually
# visible at all right now; expect this to get replaced with real UI later.

@onready var health_label: Label = $HealthLabel
@onready var meter_label: Label = $MeterLabel

var _player: Player


func _ready() -> void:
	visible = false
	Global.player_registered.connect(_on_player_registered)
	Global.player_unregistered.connect(_on_player_unregistered)
	if is_instance_valid(Global.player):
		_on_player_registered(Global.player)


func _on_player_registered(player_node: Node) -> void:
	var player := player_node as Player
	if player == null:
		return
	if is_instance_valid(_player):
		if _player.hud_stats_changed.is_connected(_update_stats):
			_player.hud_stats_changed.disconnect(_update_stats)
	_player = player
	_player.hud_stats_changed.connect(_update_stats)
	visible = true
	_update_stats()


func _on_player_unregistered(player_node: Node) -> void:
	if _player != player_node:
		return
	if is_instance_valid(_player) and _player.hud_stats_changed.is_connected(_update_stats):
		_player.hud_stats_changed.disconnect(_update_stats)
	_player = null
	visible = false


func _update_stats() -> void:
	if not is_instance_valid(_player):
		return
	health_label.text = "HP: %s / %s" % [_player.current_health, _player.max_health]
	meter_label.text = "Special: %s / %s" % [_player.current_meter, _player.max_meter]
