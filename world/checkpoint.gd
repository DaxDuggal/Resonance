extends Sprite2D
class_name Checkpoint

# Placeholder visual feedback until there's real checkpoint art/animation.
@export var inactive_color: Color = Color(0.6, 0.6, 0.6)
@export var active_color: Color = Color(0.4, 1.0, 0.55)
@export var heal_on_activate: bool = true

var is_active: bool = false


func _ready() -> void:
	add_to_group("checkpoints")
	modulate = inactive_color

	# If this is the checkpoint the player last activated (e.g. the scene just
	# reloaded after death), show it as already active without needing the
	# player to walk back into it.
	if Global.has_checkpoint and Global.last_checkpoint_position == $RespawnPoint.global_position:
		_set_active()


func _on_area_2d_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	activate(body)


func activate(player: Player) -> void:
	# Respawn position is the marker, not this node's own position, so the
	# checkpoint's visual (sprite/collision) can be offset from the exact
	# spot the player lands at on respawn.
	Global.last_checkpoint_position = $RespawnPoint.global_position
	Global.last_checkpoint_scene = get_tree().current_scene.scene_file_path
	Global.has_checkpoint = true

	if heal_on_activate:
		player.current_health = player.max_health

	# Resting resets the world (Hollow Knight-style): enemies killed since
	# your last rest come back. Permanent state (future one-time pickups,
	# opened chests, etc.) is untouched by this.
	WorldState.reset_resettable()

	# Only one checkpoint should read as "current" at a time. Re-touching an
	# earlier checkpoint after a later one is fully supported (last touched
	# always wins, in either direction) — this just keeps the visual state
	# in sync with that instead of every checkpoint you've ever hit staying
	# lit up forever.
	get_tree().call_group("checkpoints", "_deactivate_if_not", self)
	_set_active()

	# Checkpoints double as save points (Hollow Knight bench style).
	SaveManager.save_game(SaveManager.current_slot)


func _deactivate_if_not(active_checkpoint: Checkpoint) -> void:
	if active_checkpoint == self:
		return
	is_active = false
	modulate = inactive_color


func _set_active() -> void:
	if is_active:
		return
	is_active = true
	modulate = active_color
	# TODO: play activation sound/particle effect once assets exist
