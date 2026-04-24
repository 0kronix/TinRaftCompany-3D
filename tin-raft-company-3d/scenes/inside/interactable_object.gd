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
	var command := build_interaction_command()
	var network_manager := get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.request_command(_player, command)

func build_interaction_command() -> Dictionary:
	return {
		"type": "open_interactable_ui",
		"target_path": get_path()
	}

func server_validate_interaction(_actor: Node3D) -> bool:
	return ui_scene != null

func server_apply_interaction(_actor: Node3D) -> bool:
	emit_signal("interacted")
	if ui_scene:
		var services := get_node_or_null("/root/GameServices")
		if services and services.interaction_service:
			services.interaction_service.request_ui_open(ui_scene)
		else:
			UIManager.show_ui(ui_scene)
		return true
	return false
