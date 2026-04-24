extends Node
class_name InteractionService

signal ui_requested(ui_scene: PackedScene)

func request_ui_open(ui_scene: PackedScene) -> void:
	if ui_scene == null:
		return
	ui_requested.emit(ui_scene)
