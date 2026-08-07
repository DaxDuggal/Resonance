extends Node

# ============================================================
# Save System
#
# Persists progress (checkpoint, health, dash unlock, currency/XP, deaths)
# to disk in slots. Separate from Preferences (which is settings, not
# progress, and applies across every slot the same way an Options menu
# isn't tied to a particular playthrough).
#
# Auto-saves on checkpoint activation and on quitting the game. Manual
# save/load and slot selection are exposed here for a save-select menu
# to call later — no UI wires into this yet.
# ============================================================

const SAVE_DIR := "user://saves/"
const SLOT_COUNT := 3
const DEFAULT_SCENE_PATH := "res://scenes/game.tscn"

# Which slot auto-save (checkpoint / quit) writes to. Defaults to 0 until
# a save-select menu exists and sets this via load_game().
var current_slot: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	# Handle quit ourselves so we can save before the game actually closes.
	get_tree().set_auto_accept_quit(false)
	_load_on_boot()


# Silently applies current_slot's save (if any) to Global at startup, before
# the main scene's nodes run their own _ready(). Doesn't change scene since
# we're already booting straight into game.tscn (there's no title/save-select
# screen yet). Once one exists, it should call load_game() explicitly instead
# and this can be removed.
func _load_on_boot() -> void:
	if not has_save(current_slot):
		return

	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(current_slot)) != OK:
		return

	_apply_slot_data(cfg)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(current_slot)
		get_tree().quit()


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.save" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func save_game(slot: int) -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("checkpoint", "position", Global.last_checkpoint_position)
	cfg.set_value("checkpoint", "scene", Global.last_checkpoint_scene)
	cfg.set_value("checkpoint", "has_checkpoint", Global.has_checkpoint)

	cfg.set_value("player", "dash_type", Global.current_dash_type)
	cfg.set_value("player", "current_health", Global.get_current_health())

	cfg.set_value("progress", "currency", Global.currency)
	cfg.set_value("progress", "xp", Global.xp)
	cfg.set_value("progress", "death_count", Global.death_count)

	var err := cfg.save(_slot_path(slot))
	if err != OK:
		push_warning("SaveManager: failed to save slot %d (%s)" % [slot, error_string(err)])


# Loads a slot's data into Global and switches to its scene. Returns false
# if the slot is empty/unreadable — caller should leave current game state
# untouched in that case.
func load_game(slot: int) -> bool:
	if not has_save(slot):
		return false

	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(slot)) != OK:
		return false

	current_slot = slot
	_apply_slot_data(cfg)

	get_tree().change_scene_to_file(Global.last_checkpoint_scene)
	return true


# Shared by _load_on_boot() (silent, no scene change) and load_game()
# (explicit, changes scene) so the two can't drift out of sync.
func _apply_slot_data(cfg: ConfigFile) -> void:
	Global.last_checkpoint_position = cfg.get_value("checkpoint", "position", Vector2.ZERO)
	Global.last_checkpoint_scene = cfg.get_value("checkpoint", "scene", DEFAULT_SCENE_PATH)
	Global.has_checkpoint = cfg.get_value("checkpoint", "has_checkpoint", false)

	Global.current_dash_type = cfg.get_value("player", "dash_type", 0)
	# Consumed once by Player._ready().
	Global.saved_current_health = cfg.get_value("player", "current_health", -1)

	Global.currency = cfg.get_value("progress", "currency", 0)
	Global.xp = cfg.get_value("progress", "xp", 0)
	Global.death_count = cfg.get_value("progress", "death_count", 0)


func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(_slot_path(slot))


# Lightweight peek at a slot's stats for a save-select menu, without
# actually loading it into Global.
func get_save_summary(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}

	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(slot)) != OK:
		return {}

	return {
		"currency": cfg.get_value("progress", "currency", 0),
		"xp": cfg.get_value("progress", "xp", 0),
		"death_count": cfg.get_value("progress", "death_count", 0),
	}
