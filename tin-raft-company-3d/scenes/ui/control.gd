extends Control

func _ready():
	# При появлении UI — освобождаем мышь
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Panel/CloseButton.pressed.connect(close_ui)

func close_ui():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()  # или hide()

func _unhandled_input(event):
	if event.is_action_pressed("ui_close"):
		close_ui()
