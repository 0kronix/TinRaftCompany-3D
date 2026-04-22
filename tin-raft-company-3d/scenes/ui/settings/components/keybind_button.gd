# KeybindButton.gd
class_name KeybindButton
extends Button

@export var setting_key: String = ""

var _listening := false

func _ready() -> void:
	var key_code: int = SettingsManager.data.get(setting_key, KEY_NONE)
	text = OS.get_keycode_string(key_code) if key_code != KEY_NONE else "—"
	pressed.connect(_start_listen)

func _start_listen() -> void:
	_listening = true
	text = "..."
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if not _listening:
		return
	if event is InputEventKey and event.is_pressed():
		var kc: Key = event.keycode
		SettingsManager.data[setting_key] = kc
		text = OS.get_keycode_string(kc)
		_listening = false
		set_process_unhandled_input(false)
		get_viewport().set_input_as_handled()
