# VoiceThresholdBar.gd
extends Control

@export var max_value: float = 25.0          # верхняя граница шкалы индикатора (зелёной полосы)

var threshold: float = 20.0                 # порог VOX (0..100)
var current_level: float = 0.0

var _dragging := false
var _drag_start_pos: float = 0.0
var _drag_start_threshold: float = 0.0

func _ready() -> void:
	custom_minimum_size.y = 28
	mouse_filter = Control.MOUSE_FILTER_STOP
	_read_threshold_from_settings()

func _process(_delta: float) -> void:
	var vm := get_node_or_null("/root/VoiceManager")
	if vm:
		var value = vm.get("current_mic_level")
		if value != null:
			current_level = value
		else:
			current_level = 0.0
		queue_redraw()

func _read_threshold_from_settings() -> void:
	if SettingsManager:
		threshold = float(SettingsManager.data.get("mic_threshold", 20.0))
		queue_redraw()

func _draw() -> void:
	var rect := get_rect()
	var bar_height := 12.0
	var bar_y := rect.size.y / 2.0 - bar_height / 2.0

	# Фон
	draw_rect(Rect2(0, bar_y, rect.size.x, bar_height), Color(0.15, 0.15, 0.15))

	# Уровень микрофона (зелёный), масштабированный в max_value
	var filled_width: float = rect.size.x * (current_level / max_value)
	draw_rect(Rect2(0, bar_y, filled_width, bar_height), Color(0.2, 0.8, 0.3))

	# Вертикальная линия порога (0–100% шкалы)
	var threshold_x: float = rect.size.x * (threshold / 100.0)
	draw_line(Vector2(threshold_x, bar_y), Vector2(threshold_x, bar_y + bar_height), Color(1.0, 0.3, 0.3), 2.0)

	# Ручка ползунка
	var handle_w := 6.0
	var handle_h := 16.0
	var handle_x: float = threshold_x - handle_w / 2.0
	draw_rect(Rect2(handle_x, bar_y - 2, handle_w, handle_h), Color(1.0, 0.6, 0.6))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == 1:
		if event.pressed:
			_dragging = true
			_drag_start_pos = event.position.x
			_drag_start_threshold = threshold
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var dx: float = event.position.x - _drag_start_pos
		var ratio: float = dx / get_rect().size.x
		threshold = clampi(_drag_start_threshold + ratio * 100.0, 0.0, 100.0)
		if SettingsManager:
			SettingsManager.data["mic_threshold"] = threshold
		queue_redraw()
