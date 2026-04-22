# SettingsManager.gd
extends Node

const SAVE_PATH := "user://settings.cfg"

var data := {
	# Звук
	"vol_master":    80.0,
	"vol_music":     60.0,
	"vol_sfx":       90.0,
	"vol_radio":     75.0,
	"vol_static":    40.0,
	"alarm_enabled": true,
	"halluc_sound":  true,
	"output_device": 0,
	"mic_device":    0,

	# Экран
	"resolution":    0,
	"window_mode":   0,
	"fps_limit":     0,
	"vsync":         false,
	"quality":       1,
	"aa_mode":       2,
	"view_distance": 70.0,
	"crt_intensity": 65.0,
	"aberration":    30.0,
	"vignette":      true,
	"halluc_visual": true,

	# Управление
	"mouse_sens":    0.003,
	"invert_y":      false,
	"move_forward":   KEY_W,
	"move_back":      KEY_S,
	"move_left":      KEY_A,
	"move_right":     KEY_D,
	"jump":      KEY_SPACE,
	"interact":  KEY_E,
	"inventory": KEY_TAB,
	"slot1":     KEY_1,
	"slot2":     KEY_2,
	"slot3":     KEY_3,
	"slot4":     KEY_4,
	"slot5":     KEY_5,
	"slot6":     KEY_6,

	# Сеть
	"net_mode":      0,
	"port":          7777,
	"max_players":   4,
	"voice_mode":    0,
	"mic_threshold": 20.0,
	"noise_suppress":true,
	"lobby_visible": 0,
	"lobby_name":    "МОДУЛЬ #4471",
	"region":        0,
	"show_ping":     true,
	"net_log":       false,
}

var _defaults := {}

func _ready() -> void:
	_defaults = data.duplicate(true)
	load_settings()

func save() -> void:
	var cfg := ConfigFile.new()
	for key in data:
		cfg.set_value("settings", key, data[key])
	cfg.save(SAVE_PATH)
	_apply_audio()
	_apply_display()
	_apply_keybinds()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in data:
		if cfg.has_section_key("settings", key):
			data[key] = cfg.get_value("settings", key)

func reset_to_defaults() -> void:
	data = _defaults.duplicate(true)

func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		linear_to_db(data["vol_master"] / 100.0)
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		linear_to_db(data["vol_music"] / 100.0)
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"),
		linear_to_db(data["vol_sfx"] / 100.0)
	)

func _apply_display() -> void:
	var modes := [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_WINDOWED,
		DisplayServer.WINDOW_MODE_MAXIMIZED,
	]
	DisplayServer.window_set_mode(modes[data["window_mode"]])

	var vsync_mode := DisplayServer.VSYNC_ENABLED if data["vsync"] \
					  else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

func _apply_keybinds() -> void:
	var mapping := {
		"move_forward": "move_forward",
		"move_back":    "move_back",
		"move_left":    "move_left",
		"move_right":   "move_right",
		"jump":         "jump",
		"interact":     "interact",
	}
	for action in mapping.keys():
		var setting_key: String = mapping[action]  # "key_forward" и т.д.
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = data[setting_key] as Key      # data["key_forward"] и т.д.
		InputMap.action_add_event(action, ev)
