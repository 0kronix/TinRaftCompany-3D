extends Node3D

## Спавн игрока в open-space EVA. Логика как у world_manager, без world spawner + debris.
const PlayerScene := preload("res://scenes/inside/player.tscn")

@onready var player_container: Node3D = $PlayerContainer
@onready var player_spawner: MultiplayerSpawner = $PlayerContainer/PlayerSpawner

const EVA_SPAWN: Vector3 = Vector3(0, 2.0, 12.0)


func _ready() -> void:
	player_spawner.add_spawnable_scene(PlayerScene.resource_path)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.player_left.connect(_on_player_left)

	if multiplayer.is_server():
		_spawn_eva(1)
	else:
		await get_tree().process_frame
		_rpc_eva_client_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _rpc_eva_client_ready() -> void:
	if not multiplayer.is_server():
		return
	_spawn_eva(multiplayer.get_remote_sender_id())


func _spawn_eva(peer_id: int) -> void:
	var p: CharacterBody3D = PlayerScene.instantiate()
	p.name     = "Player_%d" % peer_id
	p.position = EVA_SPAWN
	if "eva_mode" in p:
		p.set("eva_mode", true)
	player_container.add_child(p, true)


func _on_player_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var n := player_container.get_node_or_null("Player_%d" % peer_id)
	if n and is_instance_valid(n):
		n.queue_free()
