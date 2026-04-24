extends Node

const InteractionServiceScript := preload("res://scripts/gameplay/interaction/interaction_service.gd")
const CapsuleStateServiceScript := preload("res://scripts/gameplay/survival/capsule_state_service.gd")

var interaction_service: Node = null
var capsule_state_service: Node = null

func _ready() -> void:
	_register_services()
	_bind_services()

func _register_services() -> void:
	# Сервис интеракций отделяет gameplay-команды от UI/сцены игрока.
	interaction_service = InteractionServiceScript.new()
	interaction_service.name = "InteractionService"
	add_child(interaction_service)
	capsule_state_service = CapsuleStateServiceScript.new()
	capsule_state_service.name = "CapsuleStateService"
	add_child(capsule_state_service)

func _bind_services() -> void:
	interaction_service.ui_requested.connect(_on_ui_requested)

func _on_ui_requested(ui_scene: PackedScene) -> void:
	UIManager.show_ui(ui_scene)
