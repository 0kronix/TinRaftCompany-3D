extends Node

var current_ui: Control = null

func show_ui(ui_scene: PackedScene):
	print("show_ui вызван")
	
	if ui_scene == null:
		print("ui_scene не назначен!")
		return
	
	if current_ui != null and is_instance_valid(current_ui):
		current_ui.queue_free()
	
	current_ui = ui_scene.instantiate()
	get_tree().root.add_child(current_ui)
	print("UI открыт: ", current_ui.name)

func hide_ui():
	if current_ui != null and is_instance_valid(current_ui):
		current_ui.queue_free()
		current_ui = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
