extends StaticBody3D
signal interacted

@export var ui_scene: PackedScene
@export var interact_distance: float = 3.0

@onready var label = $Label3D 
@onready var mesh = $MeshInstance3D



func _ready():
	Label3DHint.prepare_hidden(label)

func show_hint():
	pass

func hide_hint():
	pass

func interact(_player):
	var command := build_interaction_command()
	NetworkManager.request_command(_player, command)

func build_interaction_command() -> Dictionary:
	return {
		"type": "open_interactable_ui",
		"target_path": get_path()
	}

func server_validate_interaction(_actor: Node3D) -> bool:
	return ui_scene != null

func server_apply_interaction(_actor: Node3D, _command: Dictionary = {}) -> bool:
	emit_signal("interacted")
	# Показ UI — у инициатора (NetworkManager после успеха, RPC с клиентом).
	return ui_scene != null
