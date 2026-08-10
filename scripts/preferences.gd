extends Node

# ============================================================
# Player Preferences
#
# System-wide settings (audio, screen shake, key bindings). This is
# deliberately separate from any save file — it lives in its own file on
# disk and applies across every save slot, the same way a game's "Options"
# menu isn't tied to a particular playthrough.
#
# Save files should store progress (health, level, unlocked dashes, etc).
# This autoload stores how the PLAYER wants the game to look/sound/control,
# regardless of which save they're playing.
# ============================================================

signal preferences_changed

const SAVE_PATH := "user://player_preferences.cfg"

# Actions the player is allowed to rebind from a settings/controls menu.
# Deliberately excludes ui_* actions (menu navigation) and esc (kept fixed
# so the player can never lock themselves out of the pause menu).
const REBINDABLE_ACTIONS := [
	"jump",
	"dash",
	"attack",
	"parry",
	"special",
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"interact",
]

# ---------- Audio ----------

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0

# ---------- Accessibility / Feel ----------

var screen_shake_enabled: bool = true

# ---------- Key Bindings ----------

# action_name -> Array[InputEvent]. Populated from InputMap the first time
# this runs (before any saved rebinds are applied) so "reset to default"
# has something to reset to, without needing to hardcode bindings twice.
var _default_bindings: Dictionary = {}


func _ready() -> void:
	_ensure_audio_buses()
	_capture_default_bindings()
	load_preferences()


# ============================================================
# Audio buses
# ============================================================

# The project only ships a "Master" bus by default. Create "Music" and "SFX"
# as children of Master if they don't already exist, so volume sliders have
# somewhere to route to regardless of whether anyone has set up buses in the
# editor yet.
func _ensure_audio_buses() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _linear_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0  # effectively silent, avoids -inf from linear_to_db(0)
	return linear_to_db(linear)


func apply_audio_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_volume_db(master_idx, _linear_to_db(master_volume))

	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, _linear_to_db(music_volume))

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, _linear_to_db(sfx_volume))


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_preferences()
	preferences_changed.emit()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_preferences()
	preferences_changed.emit()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_preferences()
	preferences_changed.emit()


# ============================================================
# Accessibility / feel
# ============================================================

func set_screen_shake_enabled(value: bool) -> void:
	screen_shake_enabled = value
	save_preferences()
	preferences_changed.emit()


# ============================================================
# Key bindings
# ============================================================

func _capture_default_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_bindings[action] = InputMap.action_get_events(action).duplicate()


# Rebinds a single action to a single new event, replacing whatever was
# there before. Keeping it to one event per action avoids stale bindings
# piling up across rebinds and repeated saves/loads.
func rebind_action(action_name: String, event: InputEvent) -> void:
	if not REBINDABLE_ACTIONS.has(action_name):
		push_warning("Preferences: '%s' is not rebindable" % action_name)
		return
	if not InputMap.has_action(action_name):
		return

	InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, event)
	save_preferences()
	preferences_changed.emit()


func reset_action_to_default(action_name: String) -> void:
	if not _default_bindings.has(action_name):
		return
	InputMap.action_erase_events(action_name)
	for event in _default_bindings[action_name]:
		InputMap.action_add_event(action_name, event)
	save_preferences()
	preferences_changed.emit()


func reset_all_bindings_to_default() -> void:
	for action in REBINDABLE_ACTIONS:
		reset_action_to_default(action)


# ============================================================
# Persistence
# ============================================================

func save_preferences() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)

	cfg.set_value("accessibility", "screen_shake_enabled", screen_shake_enabled)

	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			cfg.set_value("keybindings", action, InputMap.action_get_events(action))

	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Preferences: failed to save (%s)" % error_string(err))


func load_preferences() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)

	if err != OK:
		# No preferences file yet (first launch) — apply engine defaults and
		# write one out so settings persist from here on.
		apply_audio_settings()
		save_preferences()
		return

	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)

	screen_shake_enabled = cfg.get_value("accessibility", "screen_shake_enabled", screen_shake_enabled)

	for action in REBINDABLE_ACTIONS:
		var events = cfg.get_value("keybindings", action, null)
		if events != null and InputMap.has_action(action):
			InputMap.action_erase_events(action)
			for event in events:
				InputMap.action_add_event(action, event)

	apply_audio_settings()
	preferences_changed.emit()
