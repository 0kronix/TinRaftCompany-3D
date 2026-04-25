extends Node

const LOBBY_SCENE := "res://scenes/network/lobby.tscn"
const SCENE_CAPSULE_MAIN := "res://scenes/main.tscn"
## Корень игровой сцены (main.tscn) — капсула и EVA в одном дереве.
const PATH_INSIDE := "Inside"

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
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	if not multiplayer.is_server():
		return
	_rpc_apply_world_rigid_transform.rpc(path_str, pos, rot)


@rpc("authority", "unreliable")
func _rpc_apply_world_rigid_transform(path_str: String, pos: Vector3, rot: Vector3) -> void:
	if multiplayer.is_server():
		return
	var n: Node = _resolve_world_rigid_path(path_str)
	if n is RigidBody3D:
		var rb: RigidBody3D = n as RigidBody3D
		if rb.is_multiplayer_authority():
			return
		rb.global_position = pos
		rb.global_rotation = rot


func _resolve_world_rigid_path(s: String) -> Node:
	if s.is_empty():
		return null
	var n: Node = _resolve_command_target_node(s)
	if n != null and is_instance_valid(n):
		return n
	if s.begins_with("/root/"):
		var t: String = s.trim_prefix("/root/").lstrip("/")
		n = _resolve_command_target_node(t)
		if n != null and is_instance_valid(n):
			return n
	return null


# ── EVA: поле астероидов — один RPC с NetworkManager; поздний join: пакет по снимку дерева ──

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
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
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
	_spawn_one_field_asteroid_client(
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


func _spawn_one_field_asteroid_client(
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
	spawner_path: String,
	skip_if_exists: bool
) -> void:
	var name_str := "AsteroidField_%d" % sid
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	if skip_if_exists and scene_root.get_node_or_null(name_str) != null:
		return
	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		return
	var object: Node = ps.instantiate()
	object.name = name_str
	scene_root.add_child(object)
	var rb: RigidBody3D = object as RigidBody3D
	if rb:
		rb.global_transform = xf
		rb.linear_velocity = linear_vel
		rb.angular_velocity = angular_vel
	object.set("min_speed", min_s)
	object.set("max_speed", max_s)
	object.set("target_spread", t_spread)
	object.set("despawn_distance", desp_r)
	object.set("min_scale", min_sc)
	object.set("max_scale", max_sc)
	var sp: Node3D = _resolve_command_target_node(spawner_path) as Node3D
	if sp:
		object.set("spawner_center", sp)
		if object.has_signal("despawned") and sp.has_method("_on_despawn"):
			object.despawned.connect(Callable(sp, "_on_despawn"))


func _collect_field_asteroid_snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not multiplayer.is_server():
		return out
	var inside: Node = get_tree().root.get_node_or_null("Inside")
	if inside == null or not is_instance_valid(inside):
		return out
	_collect_field_asteroid_recursive(inside, out)
	return out


func _collect_field_asteroid_recursive(n: Node, out: Array[Dictionary]) -> void:
	for c: Node in n.get_children():
		var node_name := str(c.name)
		if node_name.begins_with("AsteroidField_") and c is RigidBody3D:
			var rb: RigidBody3D = c as RigidBody3D
			var sfp: String = rb.get_scene_file_path()
			if sfp.is_empty():
				_collect_field_asteroid_recursive(c, out)
				continue
			var id_str2: String = node_name.trim_prefix("AsteroidField_")
			var field_id: int = id_str2.to_int()
			var sp: Variant = c.get("spawner_center")
			var spath: String = str((sp as Node).get_path()) if sp is Node and is_instance_valid(sp) else ""
			out.append({
				"sid": field_id,
				"scene_path": sfp,
				"xf": rb.global_transform,
				"lv": rb.linear_velocity,
				"av": rb.angular_velocity,
				"min_s": float(c.get("min_speed")),
				"max_s": float(c.get("max_speed")),
				"t_spread": float(c.get("target_spread")),
				"desp_r": float(c.get("despawn_distance")),
				"min_sc": float(c.get("min_scale")),
				"max_sc": float(c.get("max_scale")),
				"spawner_path": spath,
			})
		_collect_field_asteroid_recursive(c, out)


## Сервер: поздно подключившийся пир (после main + client_ready) — весь набор EVA-астероидов.
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
	for d: Variant in records:
		if not (d is Dictionary):
			continue
		var m: Dictionary = d as Dictionary
		_spawn_one_field_asteroid_client(
			int(m.get("sid", 0)),
			String(m.get("scene_path", "")),
			m.get("xf", Transform3D.IDENTITY) as Transform3D,
			m.get("lv", Vector3.ZERO) as Vector3,
			m.get("av", Vector3.ZERO) as Vector3,
			float(m.get("min_s", 0.0)),
			float(m.get("max_s", 0.0)),
			float(m.get("t_spread", 0.0)),
			float(m.get("desp_r", 0.0)),
			float(m.get("min_sc", 0.0)),
			float(m.get("max_sc", 0.0)),
			String(m.get("spawner_path", "")),
			true
		)


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
	field_asteroid_next_id = 0


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

	# Разрешаем цель: get_path() с клиента иногда не совпадает с root-узлом.
	var target: Node = _resolve_command_target_node(command.get("target_path", null))
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

	# Airlock: телепорт только у инициатора (капсула и EVA в одной сцене).
	if ok and command.get("type", "") in ["airlock_exit", "airlock_return"]:
		_rpc_airlock_teleport.rpc_id(sender_id, String(command.get("type", "")))


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


## Object path in RPC-commands may be relative to the scene instance — resolve robustly.
func _resolve_command_target_node(path_variant) -> Node:
	if path_variant == null:
		return null
	var s := str(path_variant)
	if s.is_empty():
		return null
	var p: NodePath = path_variant as NodePath if path_variant is NodePath else NodePath(s)
	# 1) От корня Viewport/Window
	var n: Node = get_tree().root.get_node_or_null(p)
	if n != null and is_instance_valid(n):
		return n
	# 2) Как дочерний путь к текущей сцене (часто корень = Inside)
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		n = scene_root.get_node_or_null(p)
		if n != null and is_instance_valid(n):
			return n
	# 3) С префиксом Inside/ (get_path() бывает без него)
	if not s.begins_with("Inside/"):
		n = get_tree().root.get_node_or_null("Inside/%s" % s)
		if n != null and is_instance_valid(n):
			return n
	return null


# ─────────────────────────────────────────────────────────────────────────────
# Airlock (EVA): телепорт через маркеры + группы
# ─────────────────────────────────────────────────────────────────────────────

func _on_local_teleport_command_succeeded(command: Dictionary) -> void:
	if command.get("type", "") in ["airlock_exit", "airlock_return"]:
		_apply_airlock_teleport(String(command.get("type", "")))


## Телепорт шлюза на peer, который нажал взаимодействие (authority на своём игроке).
@rpc("authority", "reliable")
func _rpc_airlock_teleport(teleport_type: String) -> void:
	_apply_airlock_teleport(teleport_type)


func _apply_airlock_teleport(teleport_type: String) -> void:
	var p := _get_local_player_for_airlock()
	if p == null:
		return
	# В сессии двигаем только персонажа с authority (тот, кого вызывали по RPC). В solo сессии нет.
	if is_session_active() and not p.is_multiplayer_authority():
		return
	var eva_m: Node3D = get_tree().get_first_node_in_group("eva_spawn") as Node3D
	if eva_m == null:
		eva_m = get_tree().root.get_node_or_null(
			"%s/EVA/EvaZone/EvaSpawn" % PATH_INSIDE) as Node3D
	var cap_m: Node3D = get_tree().get_first_node_in_group("capsule_return") as Node3D
	if cap_m == null:
		cap_m = get_tree().root.get_node_or_null(
			"%s/PlayerContainer/CapsuleReturn" % PATH_INSIDE) as Node3D

	if teleport_type == "airlock_exit":
		if eva_m and is_instance_valid(eva_m):
			p.global_position = eva_m.global_position
		p.eva_mode = true
	else:
		if cap_m and is_instance_valid(cap_m):
			p.global_position = cap_m.global_position
		p.eva_mode = false
	if p.has_method("align_after_airlock_teleport"):
		p.align_after_airlock_teleport(teleport_type == "airlock_exit")


func _get_local_player_for_airlock() -> CharacterBody3D:
	for n: Node in get_tree().get_nodes_in_group("player"):
		if n is CharacterBody3D and n.is_multiplayer_authority():
			return n as CharacterBody3D
	var my_id: int = multiplayer.get_unique_id()
	if my_id == 0:
		my_id = 1
	var by_path: Node = get_tree().root.get_node_or_null(
		"%s/PlayerContainer/Player_%d" % [PATH_INSIDE, my_id])
	if by_path is CharacterBody3D:
		return by_path as CharacterBody3D
	return null


## Кукла всегда в main.tscn (одна сцена, капсула + EVA).
func _find_puppet(peer_id: int) -> Node3D:
	return get_tree().root.get_node_or_null(
		"%s/PlayerContainer/Player_%d" % [PATH_INSIDE, peer_id]) as Node3D
