extends RefCounted
class_name InteractionCommandService
## Серверная очередь команд взаимодействия: валидация, прокси-акёр, pickup snapshot, RPC на инициатора.


var _host: Node
var _rules: ServerRules
var _router: CommandRouter
var _send_grant_pickup: Callable
var _send_airlock_teleport: Callable
var _send_open_interactable_ui: Callable


func _init(
	host_node: Node,
	rules: ServerRules,
	router: CommandRouter,
	send_grant_pickup_rpc: Callable,
	send_airlock_teleport_rpc: Callable,
	send_open_interactable_ui_rpc: Callable
) -> void:
	_host = host_node
	_rules = rules
	_router = router
	_send_grant_pickup = send_grant_pickup_rpc
	_send_airlock_teleport = send_airlock_teleport_rpc
	_send_open_interactable_ui = send_open_interactable_ui_rpc


func emit_rejected(command: Dictionary, reason: String) -> void:
	push_warning("InteractionCommand rejected: type=%s reason=%s" % [command.get("type", "?"), reason])
	_host.emit_signal("command_rejected", command.get("type", "unknown"), reason)


func execute_command_local(actor: Node3D, command: Dictionary) -> bool:
	if not _rules.validate_command(actor, command):
		emit_rejected(command, "validation_failed")
		return false
	var ok := _router.execute_command(actor, command)
	if not ok:
		emit_rejected(command, "execution_failed")
		return false
	_host.emit_signal(
		"command_accepted",
		command.get("type", "unknown"),
		actor.get_path() if actor.is_inside_tree() else NodePath()
	)
	return true


func process_forwarded_command(sender_id: int, actor_pos: Vector3, command: Dictionary) -> void:
	var tree := _host.get_tree()
	var tp: Variant = command.get("target_path", null)
	var target: Node = MultiplayerNodeResolver.resolve(tree, tp)
	if target == null or not is_instance_valid(target):
		push_warning("process_forwarded_command: target не найден path=%s" % str(tp))
		return
	# Дистанцию проверяет proxy в execute_command_local / ServerRules через actor_pos.
	# Раньше здесь бралась позиция куклы Player_N — она могла расходиться с actor_pos клиента и рвать всё без логов.

	var item_data_path := ""
	var item_count := 0
	if command.get("type") == "pickup_world_item":
		var item_data = target.get("item_data")
		if item_data is Resource and not (item_data as Resource).resource_path.is_empty():
			item_data_path = (item_data as Resource).resource_path
		var raw_count = target.get("count")
		item_count = raw_count if raw_count != null else 1

	var cmd: Dictionary = command.duplicate(true)
	cmd["initiator_peer_id"] = sender_id
	var proxy := _make_position_proxy(actor_pos)
	var ok := execute_command_local(proxy, cmd)
	proxy.queue_free()

	if ok and not item_data_path.is_empty():
		_send_grant_pickup.call(sender_id, item_data_path, item_count)

	if ok and command.get("type", "") in ["airlock_exit", "airlock_return"]:
		_send_airlock_teleport.call(sender_id, String(command.get("type", "")))
	if ok:
		open_interactable_ui_for_initiator(sender_id, command)


func open_interactable_ui_for_initiator(initiator_id: int, command: Dictionary) -> void:
	if str(command.get("type", "")) != "open_interactable_ui":
		return
	if not _host.multiplayer.is_server():
		return
	var target_path_variant: Variant = command.get("target_path", null)
	var t: Node = MultiplayerNodeResolver.resolve(_host.get_tree(), target_path_variant)
	if t == null or not is_instance_valid(t):
		push_warning("open_interactable_ui: target не найден (resolve): %s" % str(target_path_variant))
		return
	var us_var: Variant = t.get("ui_scene")
	if us_var == null or not (us_var is PackedScene):
		push_warning("open_interactable_ui: у %s нет ui_scene (PackedScene)." % str(t.get_path()))
		return
	var us: PackedScene = us_var as PackedScene
	if us.resource_path.is_empty():
		push_warning("open_interactable_ui: ui_scene без resource_path для %s." % str(t.get_path()))
		return
	var path_str: String = us.resource_path
	var target_path_str: String = str(command.get("target_path", ""))
	if initiator_id == _host.multiplayer.get_unique_id():
		UIManager.show_ui_for_local_player_with_block(us, target_path_str)
	else:
		_send_open_interactable_ui.call(initiator_id, path_str, target_path_str)


static func apply_pickup_grant_local(tree: SceneTree, item_data_path: String, count: int) -> void:
	if item_data_path.is_empty():
		return
	var item_data := load(item_data_path)
	if item_data == null:
		return
	var player: Node = LocalPlayerFinder.authority_player(tree)
	if player == null:
		return
	var inventory := player.get_node_or_null("InventoryComponent")
	var hotbar := player.get_node_or_null("HotbarComponent")
	if inventory and hotbar:
		inventory.add_item(item_data, count, hotbar.active_slot)


static func show_interactable_ui_client(res_path: String, target_path_str: String) -> void:
	if res_path.is_empty():
		push_warning("open_interactable_ui (RPC): пустой res_path.")
		return
	var us: PackedScene = load(res_path) as PackedScene
	if us == null:
		push_warning("open_interactable_ui (RPC): не загрузить сцену: %s" % res_path)
		return
	UIManager.show_ui_for_local_player_with_block(us, target_path_str)


func _make_position_proxy(pos: Vector3) -> Node3D:
	var proxy := Node3D.new()
	_host.get_tree().root.add_child(proxy)
	proxy.global_position = pos
	return proxy
