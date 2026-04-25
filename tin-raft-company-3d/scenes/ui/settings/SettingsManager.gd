# SettingsManager.gd
extends Node

signal settings_applied

const SAVE_PATH := "user://settings.cfg"
const SUPPORTED_LANGUAGES: PackedStringArray = ["ru", "en"]

var _data_snapshot := {}
var _is_editing := false

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
	
	# Голосовой чат
	"voice_mode":      0,     # 0 = PTT, 1 = VOX
	"voice_volume":    80.0,  # общая громкость голоса (0–100 %)
	"mic_threshold":   20.0,  # порог активации для VOX
	"voice_ptt_key":   KEY_V, # клавиша Push-to-Talk
	"voice_mute_key":  KEY_M, # клавиша полного отключения микрофона

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
	"language":      0,

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
	"hotbar_1":  KEY_1,
	"hotbar_2":  KEY_2,
	"hotbar_3":  KEY_3,
	"hotbar_4":  KEY_4,
	"hotbar_5":  KEY_5,
	"hotbar_6":  KEY_6,
	"key_radio": KEY_V,

	# Сеть
	"net_mode":      0,
	"port":          7777,
	"max_players":   4,
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
	apply_all()

func save() -> void:
	var cfg := ConfigFile.new()
	for key in data:
		cfg.set_value("settings", key, data[key])
	cfg.save(SAVE_PATH)
	apply_all()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in data:
		if cfg.has_section_key("settings", key):
			data[key] = cfg.get_value("settings", key)

func reset_to_defaults() -> void:
	data = _defaults.duplicate(true)
	commit_edit()
	save()   

func apply_all() -> void:
	_apply_audio()
	_apply_display()
	_apply_keybinds()
	_apply_language()
	_apply_network()
	settings_applied.emit()

func _apply_audio() -> void:
	_apply_bus_volume_if_exists("Master", data["vol_master"] / 100.0)
	_apply_bus_volume_if_exists("Music", data["vol_music"] / 100.0)
	_apply_bus_volume_if_exists("SFX", data["vol_sfx"] / 100.0)
	_apply_bus_volume_if_exists("Radio", data["vol_radio"] / 100.0)
	_apply_bus_volume_if_exists("Static", data["vol_static"] / 100.0)

func _apply_display() -> void:
	var modes := [
		DisplayServer.WINDOW_MODE_WINDOWED,
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]
	var mode_index: int = clampi(int(data["window_mode"]), 0, modes.size() - 1)
	DisplayServer.window_set_mode(modes[mode_index])

	var vsync_mode := DisplayServer.VSYNC_ENABLED if data["vsync"] \
					  else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)

	var resolutions := [
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3840, 2160),
	]
	var resolution_index: int = clampi(int(data["resolution"]), 0, resolutions.size() - 1)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_size(resolutions[resolution_index])

	var fps_map := [0, 60, 120, 144]
	var fps_index: int = clampi(int(data["fps_limit"]), 0, fps_map.size() - 1)
	Engine.max_fps = fps_map[fps_index]

func _apply_keybinds() -> void:
	var mapping := {
		"move_forward": "move_forward",
		"move_back":    "move_back",
		"move_left":    "move_left",
		"move_right":   "move_right",
		"jump":         "jump",
		"interact":     "interact",
		"inventory":    "inventory",
		"hotbar_1":     "hotbar_1",
		"hotbar_2":     "hotbar_2",
		"hotbar_3":     "hotbar_3",
		"hotbar_4":     "hotbar_4",
		"hotbar_5":     "hotbar_5",
		"hotbar_6":     "hotbar_6",
		"key_radio":    "key_radio",
	}
	for action in mapping.keys():
		var setting_key: String = mapping[action]  # "key_forward" и т.д.
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = data[setting_key] as Key      # data["key_forward"] и т.д.
		InputMap.action_add_event(action, ev)

func _apply_language() -> void:
	var language_index: int = clampi(int(data["language"]), 0, SUPPORTED_LANGUAGES.size() - 1)
	TranslationServer.set_locale(SUPPORTED_LANGUAGES[language_index])

func _apply_network() -> void:
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.has_method("apply_runtime_settings"):
		network_manager.apply_runtime_settings({
			"net_mode": data["net_mode"],
			"port": data["port"],
			"max_players": data["max_players"],
			"voice_mode": data["voice_mode"],
			"mic_threshold": data["mic_threshold"],
			"noise_suppress": data["noise_suppress"],
			"lobby_visible": data["lobby_visible"],
			"lobby_name": data["lobby_name"],
			"region": data["region"],
			"show_ping": data["show_ping"],
			"net_log": data["net_log"],
		})

func get_mouse_sensitivity() -> float:
	return float(data.get("mouse_sens", 0.003))

func is_mouse_inverted_y() -> bool:
	return bool(data.get("invert_y", false))

func _apply_bus_volume_if_exists(bus_name: String, linear_value: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(linear_value, 0.0001, 1.0)))

func get_voice_volume() -> float:
	return float(data.get("voice_volume", 80.0))

func get_voice_mode() -> int:
	return int(data.get("voice_mode", 0))
	
func begin_edit() -> void:
	_data_snapshot = data.duplicate(true)
	_is_editing = true

func cancel_edit() -> void:
	if _is_editing:
		data = _data_snapshot.duplicate(true)
		_is_editing = false

func commit_edit() -> void:
	if _is_editing:
		_data_snapshot = data.duplicate(true)   # обновляем снимок
		_is_editing = false
		
func apply_and_save() -> void:
	save()
	commit_edit()
