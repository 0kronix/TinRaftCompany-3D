extends StaticBody3D
signal interacted

@export var ui_scene: PackedScene
@export var interact_distance: float = 3.0

@onready var label = $Label3D 
@onready var mesh = $MeshInstance3D



func _ready():
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)

func show_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)

func hide_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)

func interact(_player):
	print("=== interact вызван ===")
	emit_signal("interacted")
	print("ui_scene есть: ", ui_scene != null)
	print("ui_scene: ", ui_scene)
	if ui_scene:
		print("вызываю UIManager...")
		UIManager.show_ui(ui_scene)
	else:
		print("ui_scene ПУСТОЙ - назначь его в инспекторе!")
