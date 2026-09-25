extends CanvasLayer

# Minimal placeholder HUD — plain text labels, no bars/icons/art yet (Phase
# 2 of TODO_ORDERED.md). Exists mainly so health/meter state is actually
# visible at all right now; expect this to get replaced with real UI later.

@onready var health_label: Label = $HealthLabel
@onready var meter_label: Label = $MeterLabel


func _process(_delta: float) -> void:
	if not Global.player:
		return
	var player := Global.player
	health_label.text = "HP: %s / %s" % [player.current_health, player.max_health]
	meter_label.text = "Special: %s / %s" % [player.current_meter, player.max_meter]
