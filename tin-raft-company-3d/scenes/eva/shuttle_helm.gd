extends StaticBody3D

## E — открывает подсказку по управлению; пилотом становится игрок, нажавший E (на сервере).
@export var ui_scene: PackedScene
@export var shuttle_path: NodePath

@onready var _label: Label3D = $Label3D


func _ready() -> void:
	if _label:
		_label.text = _hint_text()
		Label3DHint.prepare_hidden(_label)
	# Снаружи коллизия только на корне: у инстанс-панели отключаем, чтобы hit шёл в этот body.
	for ch in get_children():
		_disable_nested_collision(ch)
	# `instrument_panel.gd` в EVA даст [ NO SIGNAL ] — кратко подписываем назначение.
	var ip: Node = get_node_or_null("InstrumentPanel")
	if ip:
		var sl: Node = ip.get_node_or_null("StatusLabel")
		if sl and sl is Label3D:
			(sl as Label3D).text = (
				"== SHUTTLE ==\nE — подсказка, пробел — главн., Q/R — крен" if
				TranslationServer.get_locale().begins_with("ru") else
				"== SHUTTLE ==\nE — hints, Space — main, Q/R — roll"
			)


func _disable_nested_collision(n: Node) -> void:
	if n is CollisionObject3D:
		(n as CollisionObject3D).collision_layer = 0
		(n as CollisionObject3D).collision_mask = 0
	for c in n.get_children():
		_disable_nested_collision(c)


func _hint_text() -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		return "E — управление шаттлом"
	return "E — shuttle control"


func show_hint() -> void:
	pass


func hide_hint() -> void:
	pass


func interact(caller: Node3D) -> void:
	NetworkManager.request_command(caller, build_interaction_command())


func build_interaction_command() -> Dictionary:
	return {
		"type": "open_interactable_ui",
		"target_path": GameScenePaths.SHUTTLE_HELM,
	}


func _resolve_shuttle() -> RigidBody3D:
	var tree := get_tree()
	if tree == null:
		return null
	var n: Node = MultiplayerNodeResolver.resolve(tree, GameScenePaths.EVA_SHUTTLE)
	if n is RigidBody3D:
		return n as RigidBody3D
	n = get_node_or_null(shuttle_path)
	return n as RigidBody3D if n is RigidBody3D else null


func server_validate_interaction(_actor: Node3D) -> bool:
	return _resolve_shuttle() != null and ui_scene != null


func server_apply_interaction(_actor: Node3D, command: Dictionary = {}) -> bool:
	var ctype: String = str(command.get("type", "open_interactable_ui"))
	if ctype != "open_interactable_ui":
		return false
	if not server_validate_interaction(_actor):
		return false
	var shut: RigidBody3D = _resolve_shuttle()
	if shut != null:
		NetworkManager.synchronize_shuttle_pilot(str(shut.get_path()), _resolve_initiator_peer(command))
	return true


func _resolve_initiator_peer(command: Dictionary) -> int:
	var v := int(command.get("initiator_peer_id", 0))
	if v > 0:
		return v
	var rid: int = multiplayer.get_remote_sender_id()
	if rid > 0:
		return rid
	return multiplayer.get_unique_id()
