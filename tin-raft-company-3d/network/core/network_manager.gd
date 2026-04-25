extends Node

const LOBBY_SCENE := "res://scenes/network/lobby.tscn"
const SCENE_EVA_SPACE    := "res://scenes/space.tscn"
const SCENE_CAPSULE_MAIN := "res://scenes/main.tscn"

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
var _runtime_settings: Dictionary = {}

# ── Network state ─────────────────────────────────────────────────────────────
var _peer: ENetMultiplayerPeer = null

# Paths of static scene nodes that have been destroyed this session.
# Used to bring late-joining clients up to date.
var _destroyed_paths: PackedStringArray = []

func _ready() -> void:
	_server_rules = ServerRules.new()
	_command_router = CommandRouter.new()


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


# ─────────────────────────────────────────────────────────────────────────────
# Internal session handlers
# ─────────────────────────────────────────────────────────────────────────────

func _cleanup_session() -> void:
	_disconnect_signal_safe(multiplayer.peer_connected,      _on_peer_connected)
	_disconnect_signal_safe(multiplayer.peer_disconnected,   _on_peer_disconnected)
	_disconnect_signal_safe(multiplayer.connected_to_server, _on_connected_to_server)
	_disconnect_signal_safe(multiplayer.connection_failed,   _on_connection_failed)
	_disconnect_signal_safe(multiplayer.server_disconnected, _on_server_disconnected)
	multiplayer.multiplayer_peer = null
	_peer = null
	_destroyed_paths.clear()


func _disconnect_signal_safe(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)


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
# Command system — server-authoritative interactions
# ─────────────────────────────────────────────────────────────────────────────

## Routes an interaction to the server when called on a client in multiplayer.
## In singleplayer or on the server itself, executes immediately.
func request_command(actor: Node3D, command: Dictionary) -> bool:
	if is_session_active() and not multiplayer.is_server():
		# Forward to server — optimistic return (client won't roll back visuals).
		_rpc_forward_command.rpc_id(1, multiplayer.get_unique_id(), actor.global_position, command)
		return true
	var ok: bool = _execute_command_local(actor, command)
	if ok:
		_on_local_teleport_command_succeeded(command)
	return ok


## Received by the server from a client peer.
@rpc("any_peer", "reliable")
func _rpc_forward_command(sender_id: int, actor_pos: Vector3, command: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	# Anti-spoof: the actual RPC sender must match the declared sender_id.
	if multiplayer.get_remote_sender_id() != sender_id:
		return

	# Resolve the target object.
	var target_path := NodePath(command.get("target_path", ""))
	var target := get_tree().root.get_node_or_null(target_path)
	if target == null or not is_instance_valid(target):
		return

	# Distance check using the sender's synced puppet; fall back to
	# client-reported position when the puppet hasn't spawned yet.
	if target is Node3D:
		var puppet := _find_puppet(sender_id)
		var check_pos := puppet.global_position if puppet != null else actor_pos
		if check_pos.distance_to((target as Node3D).global_position) > ServerRules.MAX_INTERACT_DISTANCE:
			return

	# For pickups: capture item data BEFORE the target is destroyed so we can
	# grant it to the requesting client afterwards.
	var item_data_path := ""
	var item_count     := 0
	if command.get("type") == "pickup_world_item":
		var item_data = target.get("item_data")
		if item_data is Resource and not (item_data as Resource).resource_path.is_empty():
			item_data_path = (item_data as Resource).resource_path
		var raw_count = target.get("count")
		item_count = raw_count if raw_count != null else 1

	# Execute via a proxy actor (puppet has no inventory on the server).
	var proxy := _make_position_proxy(actor_pos)
	var ok    := _execute_command_local(proxy, command)
	proxy.queue_free()

	# Send inventory grant to the requesting client on success.
	if ok and not item_data_path.is_empty():
		_rpc_grant_pickup.rpc_id(sender_id, item_data_path, item_count)

	# Airlock: only the requesting client must load a different scene.
	if ok and command.get("type", "") in ["airlock_exit", "airlock_return"]:
		_rpc_teleport_eva_scene.rpc_id(sender_id, String(command.get("type", "")))


## Sent by the server to a client after a successful pickup.
## The client adds the item to their own inventory.
@rpc("authority", "reliable")
func _rpc_grant_pickup(item_data_path: String, count: int) -> void:
	if item_data_path.is_empty():
		return
	var item_data := load(item_data_path)
	if item_data == null:
		return
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player.is_multiplayer_authority():
			var inventory := player.get_node_or_null("InventoryComponent")
			var hotbar    := player.get_node_or_null("HotbarComponent")
			if inventory and hotbar:
				inventory.add_item(item_data, count, hotbar.active_slot)
			break


func _execute_command_local(actor: Node3D, command: Dictionary) -> bool:
	if not _server_rules.validate_command(actor, command):
		_emit_rejected(command, "validation_failed")
		return false
	var ok := _command_router.execute_command(actor, command)
	if not ok:
		_emit_rejected(command, "execution_failed")
		return false
	command_accepted.emit(
		command.get("type", "unknown"),
		actor.get_path() if actor.is_inside_tree() else NodePath()
	)
	return true


func _emit_rejected(command: Dictionary, reason: String) -> void:
	command_rejected.emit(command.get("type", "unknown"), reason)


## Creates a temporary Node3D at the given world position for server-side
## distance checks when the real player puppet isn't available yet.
func _make_position_proxy(pos: Vector3) -> Node3D:
	var proxy := Node3D.new()
	get_tree().root.add_child(proxy)
	proxy.global_position = pos
	return proxy


# ─────────────────────────────────────────────────────────────────────────────
# Static-object despawn tracking
# ─────────────────────────────────────────────────────────────────────────────

## Call this on the SERVER before calling queue_free() on a static scene node.
## Records the path and broadcasts the removal to all connected clients.
func notify_node_despawned(node: Node) -> void:
	if not multiplayer.is_server():
		return
	var path_str := String(node.get_path())
	if not _destroyed_paths.has(path_str):
		_destroyed_paths.append(path_str)
	_rpc_despawn_node.rpc(NodePath(path_str))


## Returns the list of destroyed static-node paths (for late-joiner sync).
func get_destroyed_paths() -> PackedStringArray:
	return _destroyed_paths.duplicate()


## Received by each client peer; removes the static node from their scene.
@rpc("authority", "reliable")
func _rpc_despawn_node(node_path: NodePath) -> void:
	if multiplayer.is_server():
		return  # Server already freed the node before calling notify.
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


# ─────────────────────────────────────────────────────────────────────────────
# Airlock (EVA): scene change for only the local peer
# ─────────────────────────────────────────────────────────────────────────────

func _on_local_teleport_command_succeeded(command: Dictionary) -> void:
	if command.get("type", "") in ["airlock_exit", "airlock_return"]:
		_apply_airlock_scene(String(command.get("type", "")))


## Called on clients after a successful airlock interaction on the server.
@rpc("authority", "reliable")
func _rpc_teleport_eva_scene(teleport_type: String) -> void:
	_apply_airlock_scene(teleport_type)


func _apply_airlock_scene(teleport_type: String) -> void:
	if teleport_type == "airlock_exit":
		get_tree().change_scene_to_file(SCENE_EVA_SPACE)
	elif teleport_type == "airlock_return":
		get_tree().change_scene_to_file(SCENE_CAPSULE_MAIN)


## Puppets can live in main or in EVA — resolve for distance / interaction.
func _find_puppet(peer_id: int) -> Node3D:
	var n: Node3D = get_tree().root.get_node_or_null(
		"Inside/PlayerContainer/Player_%d" % peer_id
	) as Node3D
	if n:
		return n
	return get_tree().root.get_node_or_null(
		"Space/PlayerContainer/Player_%d" % peer_id
	) as Node3D
