extends Node

const LOBBY_SCENE := "res://scenes/network/lobby.tscn"

# ── Command system signals ────────────────────────────────────────────────────
signal command_accepted(command_type: String, actor_path: NodePath)
signal command_rejected(command_type: String, reason: String)

# ── Session signals ───────────────────────────────────────────────────────────
signal session_started(is_host: bool)
signal session_ended
signal player_joined(peer_id: int)
signal player_left(peer_id: int)
signal connection_failed

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_PEERS := 4

# ── Command system ────────────────────────────────────────────────────────────
var _server_rules: ServerRules
var _command_router: CommandRouter
var _commands: InteractionCommandService
var _runtime_settings: Dictionary = {}

# ── Network state ─────────────────────────────────────────────────────────────
var _peer: ENetMultiplayerPeer = null
var _despawn_tracker: StaticDespawnTracker
var _shuttle_sync: ShuttleSyncService

# Согласованные имена AsteroidField_%d (RPC/кэш путей) для серверного EVA-спавна.
var field_asteroid_next_id: int = 0


func take_field_asteroid_id() -> int:
	if not multiplayer.is_server():
		return 0
	var n := field_asteroid_next_id
	field_asteroid_next_id += 1
	return n


# ── World RigidBody transform (реплика без @rpc на RigidBody — иначе scene_cache + process_simplify_path) ──

func broadcast_world_rigid_transform(path_str: String, pos: Vector3, rot: Vector3) -> void:
	if not MultiplayerRuntime.has_active_session_for(self):
		return
	if not multiplayer.is_server():
		return
	_rpc_apply_world_rigid_transform.rpc(path_str, pos, rot)


## Высокая частота × сотни тел по **reliable** забивали очередь ENet — `PEER_ROUND_TRIP_TIME` (HUD «пинг») рос
## до сотен ms даже по LAN. Для позы важнее **последний** снапшот: `unreliable_ordered` отбрасывает устаревшее.
## Интерполятор на `NetworkReplicatedRigidBody` переживает пропуски лучше, чем очередь reliable.
@rpc("authority", "unreliable_ordered")
func _rpc_apply_world_rigid_transform(path_str: String, pos: Vector3, rot: Vector3) -> void:
	if multiplayer.is_server():
		return
	WorldRigidReplicaSync.relay_snapshot(get_tree(), path_str, pos, rot)


# ── EVA: поле астероидов — RPC здесь; дерево на клиенте — FieldAsteroidSync ────────────────

func broadcast_field_asteroid_spawn(
	sid: int,
	scene_path: String,
	xf: Transform3D,
	linear_vel: Vector3,
	angular_vel: Vector3,
	min_s: float,
	max_s: float,
	t_spread: float,
	desp_r: float,
	min_sc: float,
	max_sc: float,
	spawner_path: String
) -> void:
	if not MultiplayerRuntime.has_active_session_for(self):
		return
	if not multiplayer.is_server():
		return
	_rpc_replicate_field_asteroid.rpc(
		sid,
		scene_path,
		xf,
		linear_vel,
		angular_vel,
		min_s,
		max_s,
		t_spread,
		desp_r,
		min_sc,
		max_sc,
		spawner_path
	)


@rpc("authority", "reliable")
func _rpc_replicate_field_asteroid(
	sid: int,
	scene_path: String,
	xf: Transform3D,
	linear_vel: Vector3,
	angular_vel: Vector3,
	min_s: float,
	max_s: float,
	t_spread: float,
	desp_r: float,
	min_sc: float,
	max_sc: float,
	spawner_path: String
) -> void:
	if multiplayer.is_server():
		return
	FieldAsteroidSync.spawn_one_client(
		get_tree(),
		sid,
		scene_path,
		xf,
		linear_vel,
		angular_vel,
		min_s,
		max_s,
		t_spread,
		desp_r,
		min_sc,
		max_sc,
		spawner_path,
		true
	)


func _collect_field_asteroid_snapshot() -> Array[Dictionary]:
	if not multiplayer.is_server():
		return FieldAsteroidSync.collect_snapshot(null)
	var inside: Node = get_tree().root.get_node_or_null(GameScenePaths.INSIDE)
	return FieldAsteroidSync.collect_snapshot(inside)


func sync_field_asteroids_to_late_client(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id < 1:
		return
	var snap: Array[Dictionary] = _collect_field_asteroid_snapshot()
	if snap.is_empty():
		return
	_rpc_field_asteroid_batch.rpc_id(peer_id, snap)


@rpc("authority", "reliable")
func _rpc_field_asteroid_batch(records: Array) -> void:
	if multiplayer.is_server():
		return
	FieldAsteroidSync.apply_record_batch(get_tree(), records)


func _ready() -> void:
	_server_rules = ServerRules.new()
	_command_router = CommandRouter.new()
	_despawn_tracker = StaticDespawnTracker.new()
	_shuttle_sync = ShuttleSyncService.new(self)
	_commands = InteractionCommandService.new(
		self,
		_server_rules,
		_command_router,
		Callable(self, "send_grant_pickup_to_peer"),
		Callable(self, "send_airlock_teleport_to_peer"),
		Callable(self, "send_open_interactable_ui_to_peer")
	)


# ─────────────────────────────────────────────────────────────────────────────
# Session management
# ─────────────────────────────────────────────────────────────────────────────

func host(port: int) -> Error:
	_cleanup_session()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PEERS)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	session_started.emit(true)
	return OK


func join(ip: String, port: int) -> Error:
	_cleanup_session()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip, port)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func leave() -> void:
	_cleanup_session()
	session_ended.emit()


func is_session_active() -> bool:
	return _peer != null


func _cleanup_session() -> void:
	MultiplayerRuntime.disconnect_if_connected(multiplayer.peer_connected, _on_peer_connected)
	MultiplayerRuntime.disconnect_if_connected(multiplayer.peer_disconnected, _on_peer_disconnected)
	MultiplayerRuntime.disconnect_if_connected(multiplayer.connected_to_server, _on_connected_to_server)
	MultiplayerRuntime.disconnect_if_connected(multiplayer.connection_failed, _on_connection_failed)
	MultiplayerRuntime.disconnect_if_connected(multiplayer.server_disconnected, _on_server_disconnected)
	multiplayer.multiplayer_peer = null
	_peer = null
	if _despawn_tracker:
		_despawn_tracker.clear()
	field_asteroid_next_id = 0


func _on_peer_connected(peer_id: int) -> void:
	player_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	session_started.emit(false)


func _on_connection_failed() -> void:
	connection_failed.emit()
	_cleanup_session()


func _on_server_disconnected() -> void:
	_cleanup_session()
	session_ended.emit()
	get_tree().change_scene_to_file(LOBBY_SCENE)


# ─────────────────────────────────────────────────────────────────────────────
# Command system — RPC-фасад; логика в InteractionCommandService
# ─────────────────────────────────────────────────────────────────────────────

func request_command(actor: Node3D, command: Dictionary) -> bool:
	if is_session_active() and not multiplayer.is_server():
		_rpc_forward_command.rpc_id(1, multiplayer.get_unique_id(), actor.global_position, command)
		return true
	var cmd: Dictionary = command.duplicate(true)
	cmd["initiator_peer_id"] = multiplayer.get_unique_id()
	var ok: bool = _commands.execute_command_local(actor, cmd)
	if ok:
		if AirlockTeleportService.should_apply_local_after_command(command):
			AirlockTeleportService.apply(self, String(command.get("type", "")))
		_commands.open_interactable_ui_for_initiator(multiplayer.get_unique_id(), command)
	return ok


@rpc("any_peer", "reliable")
func _rpc_forward_command(sender_id: int, actor_pos: Vector3, command: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != sender_id:
		return
	_commands.process_forwarded_command(sender_id, actor_pos, command)


func send_grant_pickup_to_peer(peer_id: int, item_data_path: String, count: int) -> void:
	_rpc_grant_pickup.rpc_id(peer_id, item_data_path, count)


func send_airlock_teleport_to_peer(peer_id: int, teleport_type: String) -> void:
	_rpc_airlock_teleport.rpc_id(peer_id, teleport_type)


func send_open_interactable_ui_to_peer(peer_id: int, res_path: String, target_path_str: String) -> void:
	_rpc_open_interactable_ui.rpc_id(peer_id, res_path, target_path_str)


@rpc("authority", "reliable")
func _rpc_grant_pickup(item_data_path: String, count: int) -> void:
	InteractionCommandService.apply_pickup_grant_local(get_tree(), item_data_path, count)


@rpc("authority", "reliable")
func _rpc_open_interactable_ui(res_path: String, target_path_str: String) -> void:
	if multiplayer.is_server():
		return
	InteractionCommandService.show_interactable_ui_client(res_path, target_path_str)


# ─────────────────────────────────────────────────────────────────────────────
# Static-object despawn tracking
# ─────────────────────────────────────────────────────────────────────────────

func notify_node_despawned(node: Node) -> void:
	if not multiplayer.is_server():
		return
	var path_str := String(node.get_path())
	if _despawn_tracker.try_record(path_str):
		_rpc_despawn_node.rpc(NodePath(path_str))


func get_destroyed_paths() -> PackedStringArray:
	return _despawn_tracker.get_paths_copy()


@rpc("authority", "reliable")
func _rpc_despawn_node(node_path: NodePath) -> void:
	if multiplayer.is_server():
		return
	var node := get_tree().root.get_node_or_null(node_path)
	if node and is_instance_valid(node):
		node.queue_free()


# ─────────────────────────────────────────────────────────────────────────────
# Settings
# ─────────────────────────────────────────────────────────────────────────────

func apply_runtime_settings(settings: Dictionary) -> void:
	_runtime_settings = settings.duplicate(true)


func get_runtime_settings() -> Dictionary:
	return _runtime_settings.duplicate(true)


func _resolve_command_target_node(path_variant) -> Node:
	return MultiplayerNodeResolver.resolve(get_tree(), path_variant)


# ─────────────────────────────────────────────────────────────────────────────
# Airlock (EVA)
# ─────────────────────────────────────────────────────────────────────────────

@rpc("authority", "reliable")
func _rpc_airlock_teleport(teleport_type: String) -> void:
	AirlockTeleportService.apply(self, teleport_type)


# ─────────────────────────────────────────────────────────────────────────────
# Shuttle (EVA)
# ─────────────────────────────────────────────────────────────────────────────

func synchronize_shuttle_pilot(path_str: String, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_shuttle_sync.set_pilot_peer_id(path_str, peer_id)
	if MultiplayerRuntime.has_active_session_for(self) and is_session_active():
		_rpc_shuttle_pilot_sync.rpc(path_str, peer_id)


@rpc("authority", "reliable")
func _rpc_shuttle_pilot_sync(path_str: String, peer_id: int) -> void:
	if multiplayer.is_server():
		return
	_shuttle_sync.set_pilot_peer_id(path_str, peer_id)


func submit_shuttle_pilot_input(path_str: String, bits: int) -> void:
	if multiplayer.is_server():
		return
	_rpc_shuttle_pilot_input.rpc_id(1, path_str, bits)


@rpc("any_peer", "unreliable")
func _rpc_shuttle_pilot_input(path_str: String, bits: int) -> void:
	if not multiplayer.is_server():
		return
	var from_id: int = multiplayer.get_remote_sender_id()
	if from_id < 1:
		return
	_shuttle_sync.apply_client_pilot_input(path_str, from_id, bits)
