extends Control
class_name InteractionHintPanel
## Шаблон подсказки взаимодействия. Плавность — через `modulate.a` у `PanelContainer` (дочерний `HintLabel` затемняется вместе с рамкой).

@export var fade_in_seconds: float = 0.12
@export var fade_out_seconds: float = 0.08

@onready var _panel: PanelContainer = $PanelContainer
@onready var _label: Label = %HintLabel

var _tween: Tween
var _last_text: String = ""
var _panel_peak_alpha: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _panel:
		var c: Color = _panel.modulate
		_panel_peak_alpha = c.a if c.a > 0.01 else 1.0
		_panel.modulate = Color(c.r, c.g, c.b, 0.0)
		_panel.visible = false


func should_skip_duplicate(text: String) -> bool:
	var t: String = text.strip_edges()
	if t.is_empty() or _panel == null:
		return false
	return t == _last_text and _panel.visible and _panel.modulate.a > 0.9


func show_text(text: String) -> void:
	var t: String = text.strip_edges()
	if t.is_empty():
		hide_text()
		return
	if should_skip_duplicate(t):
		return
	if _label == null or _panel == null:
		return
	_last_text = t
	if _tween and is_instance_valid(_tween):
		_tween.kill()
	_label.text = t
	_panel.visible = true
	var c: Color = _panel.modulate
	_panel.modulate = Color(c.r, c.g, c.b, 0.0)
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", _panel_peak_alpha, fade_in_seconds)


func hide_text() -> void:
	_last_text = ""
	if _panel == null or not is_instance_valid(_panel):
		return
	if _tween and is_instance_valid(_tween):
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 0.0, fade_out_seconds)
	_tween.finished.connect(_on_hide_finished, Object.CONNECT_ONE_SHOT)


func _on_hide_finished() -> void:
	if _panel and is_instance_valid(_panel):
		_panel.visible = false


func _exit_tree() -> void:
	if _tween and is_instance_valid(_tween):
		_tween.kill()
