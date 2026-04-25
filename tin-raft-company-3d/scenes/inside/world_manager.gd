extends Node3D

## Прикреплён к корню игровой сцены (узел `Inside` в main.tscn).
## Капсула = отдельная «комната»; `EVA` = имитация космоса + `PlayerShip` (шаттл и шлюз
## возврата в капсулу), всё в одной сцене; телепорт — `NetworkManager._apply_airlock_teleport`.
##
## World objects (ores, asteroids) are STATIC nodes in main.tscn — they load
## for every peer automatically with no spawn packets.
##
## WorldObjects / WorldSpawner handles only DYNAMIC objects (debris from
## broken asteroids).  Using spawn_function (instead of add_spawnable_scene)
## lets us embed the initial transform in the spawn data so clients recreate
## debris at the exact same position as the server.
##
## When a static object is destroyed the server calls
## NetworkManager.notify_node_despawned() which broadcasts an RPC to all
## connected clients.  Late-joiners receive the full destroyed-paths list via
## _rpc_sync_destroyed after they signal readiness.

const PlayerScene := preload("res://scenes/inside/player.tscn")

const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-0.62, 1.95,  1.97),
	Vector3( 0.20, 1.95,  1.97),
	Vector3(-0.62, 1.95,  1.20),
	Vector3( 0.20, 1.95,  1.20),
]

@onready var player_container: Node3D            = $PlayerContainer
@onready var player_spawner:   MultiplayerSpawner = $PlayerContainer/PlayerSpawner
@onready var world_spawner:    MultiplayerSpawner = $WorldObjects/WorldSpawner


func _ready() -> void:
	player_spawner.add_spawnable_scene(PlayerScene.resource_path)

	# Custom spawn function: the data dict carries scene_path + transform so
	# clients recreate dynamic nodes (debris) at the correct position.
	world_spawner.spawn_function = _create_world_node

	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.player_left.connect(_on_player_left)

	if multiplayer.is_server():
		_spawn_player(1)
	else:
		# Wait one frame so spawner nodes are fully registered with the
		# multiplayer system before telling the server we are ready.
		await get_tree().process_frame
		_rpc_client_ready.rpc_id(1)


# ─────────────────────────────────────────────────────────────────────────────
# WorldSpawner custom spawn function
# ─────────────────────────────────────────────────────────────────────────────

## Called on BOTH server and clients when a node is spawned via world_spawner.spawn().
## data keys: "scene_path" (String), "position" (Vector3), "scale" (float)
func _create_world_node(data: Dictionary) -> Node:
	var scene_path: String = data.get("scene_path", "")
	if scene_path.is_empty():
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("world_manager: could not load scene: " + scene_path)
		return null
	var node: Node  = scene.instantiate()
	# Spawner/репликация иногда дают корню имя @RigidBody3D@N — пути к дочерним нодам ломаются
	var nname: String = str(node.name)
	if nname.begins_with("@") or nname == "":
		var base: String = scene_path.get_file().get_basename()
		node.name = base + "_%d" % (abs(int(hash(nname + scene_path + str(randi())))) % 1000000)
	node.position = data.get("position", Vector3.ZERO)
	var s: float  = data.get("scale", 1.0)
	node.scale    = Vector3(s, s, s)
	# Apply blast velocity for debris pieces. Setting linear_velocity before
	# the node enters the tree is picked up by the physics server on entry.
	# On authority (server) physics runs freely; clients are frozen by
	# _setup_physics_sync() and follow the server via MultiplayerSynchronizer.
	var velocity: Vector3 = data.get("velocity", Vector3.ZERO)
	if velocity != Vector3.ZERO and node is RigidBody3D:
		(node as RigidBody3D).linear_velocity = velocity
	return node


# ─────────────────────────────────────────────────────────────────────────────
# Player management
# ─────────────────────────────────────────────────────────────────────────────

## Called by the client once its game scene is fully loaded.
@rpc("any_peer", "reliable")
func _rpc_client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_spawn_player(peer_id)

	# Send the list of destroyed static objects so the late-joiner matches
	# the current server world state.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		var destroyed: PackedStringArray = nm.get_destroyed_paths()
		if not destroyed.is_empty():
			_rpc_sync_destroyed.rpc_id(peer_id, destroyed)


## Received by a newly joined client; removes nodes the server already destroyed.
@rpc("authority", "reliable")
func _rpc_sync_destroyed(paths: PackedStringArray) -> void:
	for path_str: String in paths:
		var node := get_tree().root.get_node_or_null(NodePath(path_str))
		if node and is_instance_valid(node):
			node.queue_free()


func _spawn_player(peer_id: int) -> void:
	# get_child_count() учитывал Spawner, CapsuleReturn, маркеры — избыточный idx и смещения
	var player_idx: int = 0
	for c in player_container.get_children():
		if c is CharacterBody3D and str(c.name).begins_with("Player_"):
			player_idx += 1
	var spawn_pos: Vector3 = SPAWN_POSITIONS[player_idx % SPAWN_POSITIONS.size()]

	var player: CharacterBody3D = PlayerScene.instantiate() as CharacterBody3D
	player.name = "Player_%d" % peer_id
	player.position = spawn_pos
	player_container.add_child(player, true)


## Called when any peer disconnects. The server removes the player node;
## MultiplayerSpawner replicates the despawn to all remaining clients.
func _on_player_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_node := player_container.get_node_or_null("Player_%d" % peer_id)
	if player_node and is_instance_valid(player_node):
		player_node.queue_free()
