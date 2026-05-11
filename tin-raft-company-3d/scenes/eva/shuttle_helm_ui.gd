extends Control
## Короткая подсказка по управлению; закрыть — Esc / кнопка. Блок ввода — UIManager по tree_exited.

@onready var _btn_close: Button = $CanvasLayer/Panel/CloseButton


func _ready() -> void:
	if _btn_close:
		_btn_close.pressed.connect(_on_close)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _on_close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_close"):
		_on_close()
