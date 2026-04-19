extends StaticBody3D

signal interacted

@export var ui_scene: PackedScene
@export var interact_distance: float = 3.0

@onready var mesh = $MeshInstance3D


func interact():
	print("=== interact вызван ===")
	emit_signal("interacted")
	print("ui_scene есть: ", ui_scene != null)
	print("ui_scene: ", ui_scene)
	if ui_scene:
		print("вызываю UIManager...")
		UIManager.show_ui(ui_scene)
	else:
		print("ui_scene ПУСТОЙ - назначь его в инспекторе!")
