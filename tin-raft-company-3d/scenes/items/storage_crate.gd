extends StaticBody3D
## Ящик с инвентарём (`InventoryComponent`). UI — `storage_crate_ui.tscn`.
## Вариант `is_ejector`: кнопка в UI выкидывает содержимое в `eject_marker_path` (глобальные координаты).

const _DEFAULT_DROP := preload("res://scenes/items/iron_ore.tscn")

@export var ui_scene: PackedScene
@export var is_ejector: bool = false
@export var eject_marker_path: NodePath = NodePath("EjectMarker")
## Если включено: точка выброса — `Shuttle/CrateEjectPort` (редактор), иначе запасной `EvaSpawn`, иначе `EjectMarker` у ящика.
@export var eject_at_shuttle_hatch: bool = true
@export var crate_slot_count: int = 10
@export var crate_mass_limit: float = 80.0

@onready var _label: Label3D = $Label3D
@onready var _crate_inv: InventoryComponent = $InventoryComponent


func _ready() -> void:
	if _crate_inv:
		_crate_inv.max_slots = crate_slot_count
		_crate_inv.max_mass = crate_mass_limit
		_crate_inv.slots.resize(_crate_inv.max_slots)
		_crate_inv.slots.fill(null)
	if _label:
		_label.text = "E — ящик" if TranslationServer.get_locale().begins_with("ru") else "E — crate"
		Label3DHint.prepare_hidden(_label)


func get_crate_inventory() -> InventoryComponent:
	return _crate_inv


func is_ejector_crate() -> bool:
	return is_ejector


func show_hint() -> void:
	pass


func hide_hint() -> void:
	pass


func interact(player: Node3D) -> void:
	NetworkManager.request_command(player, build_interaction_command())


func build_interaction_command() -> Dictionary:
	return {"type": "open_interactable_ui", "target_path": get_path()}


func server_validate_interaction(_actor: Node3D) -> bool:
	return ui_scene != null


func server_apply_interaction(_actor: Node3D, _command: Dictionary = {}) -> bool:
	return ui_scene != null


## Одиночная игра / без сессии: перенос без RPC.
func offline_player_to_crate(player_inv: InventoryComponent, player_slot: int, crate_slot: int) -> bool:
	var slot: Variant = player_inv.get_slot(player_slot)
	if slot == null:
		return false
	var it: ItemResource = slot["item"] as ItemResource
	if it == null:
		return false
	var cnt: int = int(slot["count"])
	var moved: int = _try_put_stack_in_crate(crate_slot, it, cnt)
	if moved <= 0:
		return false
	player_inv.remove_item(player_slot, moved)
	return true


func offline_crate_to_player(player_inv: InventoryComponent, crate_slot: int, player_slot: int) -> bool:
	var cslot: Variant = _crate_inv.get_slot(crate_slot)
	if cslot == null:
		return false
	var it: ItemResource = cslot["item"] as ItemResource
	if it == null:
		return false
	var cnt: int = int(cslot["count"])
	var moved: int = _try_put_stack_in_player(player_inv, player_slot, it, cnt)
	if moved <= 0:
		return false
	_crate_inv.remove_item(crate_slot, moved)
	return true


func offline_crate_swap(a: int, b: int) -> void:
	_crate_inv.swap_slots(a, b)


func offline_eject_all() -> void:
	if not is_ejector:
		return
	_server_eject_all_items()


# ── Клиент → сервер: синхронизация ящика ─────────────────────────────────────

@rpc("any_peer", "reliable")
func rpc_request_crate_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var pid: int = multiplayer.get_remote_sender_id()
	if pid <= 0:
		pid = multiplayer.get_unique_id()
	var st: Array = _crate_inv.export_state()
	if pid == multiplayer.get_unique_id():
		return
	rpc_sync_crate_state.rpc_id(pid, st)


@rpc("any_peer", "reliable")
func rpc_request_p2c(player_slot: int, crate_slot: int, item_path: String, move_count: int) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = multiplayer.get_remote_sender_id()
	if pid <= 0:
		pid = multiplayer.get_unique_id()
	if not _server_actor_near_crate(pid):
		return
	var p_inv := _server_player_inventory(pid)
	if p_inv == null:
		return
	var slot: Variant = p_inv.get_slot(player_slot)
	if slot == null:
		return
	var it: ItemResource = slot["item"] as ItemResource
	if it == null or it.resource_path != item_path:
		return
	var have: int = int(slot["count"])
	var cnt: int = clampi(move_count, 1, have)
	var moved: int = _try_put_stack_in_crate(crate_slot, it, cnt)
	if moved <= 0:
		return
	_rpc_or_local_player_remove(pid, player_slot, moved)
	_broadcast_crate_state()


@rpc("any_peer", "reliable")
func rpc_request_c2p(crate_slot: int, player_slot: int, item_path: String, move_count: int) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = multiplayer.get_remote_sender_id()
	if pid <= 0:
		pid = multiplayer.get_unique_id()
	if not _server_actor_near_crate(pid):
		return
	var cslot: Variant = _crate_inv.get_slot(crate_slot)
	if cslot == null:
		return
	var it: ItemResource = cslot["item"] as ItemResource
	if it == null or it.resource_path != item_path:
		return
	var have: int = int(cslot["count"])
	var cnt: int = clampi(move_count, 1, have)
	_crate_inv.remove_item(crate_slot, cnt)
	_rpc_or_local_player_add(pid, player_slot, item_path, cnt)
	_broadcast_crate_state()


@rpc("any_peer", "reliable")
func rpc_request_eject() -> void:
	if not multiplayer.is_server():
		return
	if not is_ejector:
		return
	var pid: int = multiplayer.get_remote_sender_id()
	if pid <= 0:
		pid = multiplayer.get_unique_id()
	if not _server_actor_near_crate(pid):
		return
	_server_eject_all_items()
	_broadcast_crate_state()


@rpc("any_peer", "reliable")
func rpc_player_remove_from_slot(slot: int, count: int) -> void:
	var p: Node = LocalPlayerFinder.authority_player(get_tree())
	if p == null:
		return
	var inv: InventoryComponent = p.get_node_or_null("InventoryComponent") as InventoryComponent
	if inv == null:
		return
	inv.remove_item(slot, count)


@rpc("any_peer", "reliable")
func rpc_player_add_or_merge(player_slot: int, item_path: String, count: int) -> void:
	var p: Node = LocalPlayerFinder.authority_player(get_tree())
	if p == null:
		return
	var inv: InventoryComponent = p.get_node_or_null("InventoryComponent") as InventoryComponent
	if inv == null:
		return
	var loaded: Resource = load(item_path)
	if loaded == null or not (loaded is ItemResource):
		return
	inv.add_item(loaded as ItemResource, count, player_slot)


@rpc("any_peer", "reliable")
func rpc_request_crate_internal_move(from_i: int, to_i: int) -> void:
	if not multiplayer.is_server():
		return
	var pid: int = multiplayer.get_remote_sender_id()
	if pid <= 0:
		pid = multiplayer.get_unique_id()
	if not _server_actor_near_crate(pid):
		return
	if from_i == to_i:
		return
	var from_s: Variant = _crate_inv.get_slot(from_i)
	if from_s == null:
		return
	var to_s: Variant = _crate_inv.get_slot(to_i)
	if to_s == null:
		_crate_inv.swap_slots(from_i, to_i)
	elif (from_s["item"] as ItemResource).id == (to_s["item"] as ItemResource).id:
		var max_stack: int = int((from_s["item"] as ItemResource).max_stack)
		var total: int = int(from_s["count"]) + int(to_s["count"])
		if total <= max_stack:
			to_s["count"] = total
			_crate_inv.slots[from_i] = null
		else:
			to_s["count"] = max_stack
			from_s["count"] = total - max_stack
		_crate_inv.emit_signal("inventory_changed")
	else:
		_crate_inv.swap_slots(from_i, to_i)
	_broadcast_crate_state()


@rpc("any_peer", "reliable")
func rpc_sync_crate_state(state: Array) -> void:
	if multiplayer.is_server():
		return
	_crate_inv.import_state(state)


## Сервер: обновить инвентарь игрока. На хосте `rpc_id(own_id)` запрещён — пишем в дерево напрямую.
func _rpc_or_local_player_remove(peer_id: int, slot: int, count: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		var inv_rm: InventoryComponent = _server_player_inventory(peer_id)
		if inv_rm:
			inv_rm.remove_item(slot, count)
		return
	rpc_player_remove_from_slot.rpc_id(peer_id, slot, count)


func _rpc_or_local_player_add(peer_id: int, player_slot: int, item_path: String, count: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		var inv_add: InventoryComponent = _server_player_inventory(peer_id)
		if inv_add == null:
			return
		var loaded_local: Resource = load(item_path)
		if loaded_local == null or not (loaded_local is ItemResource):
			return
		inv_add.add_item(loaded_local as ItemResource, count, player_slot)
		return
	rpc_player_add_or_merge.rpc_id(peer_id, player_slot, item_path, count)


func _broadcast_crate_state() -> void:
	if not NetworkManager.is_session_active():
		return
	if not multiplayer.is_server():
		return
	var st: Array = _crate_inv.export_state()
	for peer_id in multiplayer.get_peers():
		rpc_sync_crate_state.rpc_id(int(peer_id), st)


func _server_actor_near_crate(peer_id: int) -> bool:
	var body := _server_player_body(peer_id)
	if body == null:
		return false
	return body.global_position.distance_to(global_position) <= ServerRules.MAX_INTERACT_DISTANCE


func _server_player_body(peer_id: int) -> CharacterBody3D:
	var n: Node = get_tree().root.get_node_or_null(
		NodePath(GameScenePaths.player_puppet_path_str(peer_id))
	)
	return n as CharacterBody3D if n is CharacterBody3D else null


func _server_player_inventory(peer_id: int) -> InventoryComponent:
	var body := _server_player_body(peer_id)
	if body == null:
		return null
	return body.get_node_or_null("InventoryComponent") as InventoryComponent


## Сколько единиц реально поместилось (0 — нельзя).
func _try_put_stack_in_crate(crate_slot: int, item: ItemResource, count: int) -> int:
	if crate_slot < 0 or crate_slot >= _crate_inv.max_slots or count <= 0:
		return 0
	var existing: Variant = _crate_inv.get_slot(crate_slot)
	if existing == null:
		if _crate_inv._current_mass() + item.mass * count > _crate_inv.max_mass:
			return 0
		_crate_inv.slots[crate_slot] = {"item": item, "count": count}
		_crate_inv.emit_signal("inventory_changed")
		return count
	if (existing["item"] as ItemResource).id != item.id:
		return 0
	var max_stack: int = int((existing["item"] as ItemResource).max_stack)
	var cur: int = int(existing["count"])
	var space: int = max_stack - cur
	if space <= 0:
		return 0
	var add: int = mini(space, count)
	existing["count"] = cur + add
	_crate_inv.emit_signal("inventory_changed")
	return add


func _try_put_stack_in_player(p_inv: InventoryComponent, player_slot: int, item: ItemResource, count: int) -> int:
	if player_slot < 0 or player_slot >= p_inv.max_slots or count <= 0:
		return 0
	var existing: Variant = p_inv.get_slot(player_slot)
	if existing == null:
		if p_inv._current_mass() + item.mass * count > p_inv.max_mass:
			return 0
		p_inv.slots[player_slot] = {"item": item, "count": count}
		p_inv.emit_signal("inventory_changed")
		return count
	if (existing["item"] as ItemResource).id != item.id:
		return 0
	var max_stack: int = int((existing["item"] as ItemResource).max_stack)
	var cur: int = int(existing["count"])
	var space: int = max_stack - cur
	if space <= 0:
		return 0
	var add: int = mini(space, count)
	existing["count"] = cur + add
	p_inv.emit_signal("inventory_changed")
	return add


func _server_eject_all_items() -> void:
	if not is_ejector:
		return
	var marker: Node3D = get_node_or_null(eject_marker_path) as Node3D
	var origin: Vector3
	var eject_basis: Basis
	if eject_at_shuttle_hatch:
		var hatch: Node3D = get_tree().root.get_node_or_null(
			NodePath(GameScenePaths.EVA_SHUTTLE_CRATE_EJECT)
		) as Node3D
		if hatch == null:
			hatch = get_tree().root.get_node_or_null(NodePath(GameScenePaths.EVA_SHUTTLE_EVASPAWN)) as Node3D
		if hatch:
			eject_basis = hatch.global_basis
			# Скорость в `_spawn_dropped_item` — вдоль `-basis.z`; чуть сдвигаем старт наружу от корпуса.
			origin = hatch.global_position - eject_basis.z * 0.45
		else:
			origin = marker.global_position if marker else global_position
			eject_basis = marker.global_basis if marker else global_transform.basis
	else:
		origin = marker.global_position if marker else global_position
		eject_basis = marker.global_basis if marker else global_transform.basis
	var spawner: MultiplayerSpawner = _get_world_spawner()
	if spawner == null:
		push_warning("StorageCrate: нет WorldSpawner для выброса.")
		return
	var i: int = 0
	while i < _crate_inv.max_slots:
		var s: Variant = _crate_inv.get_slot(i)
		if s == null:
			i += 1
			continue
		var it: ItemResource = s["item"] as ItemResource
		var ct: int = int(s["count"])
		_spawn_dropped_item(spawner, it, ct, origin, eject_basis, i)
		_crate_inv.remove_item(i, 999999)
		i += 1


func _get_world_spawner() -> MultiplayerSpawner:
	var wo: Node = GameScenePaths.get_world_objects_node(get_tree())
	if wo == null:
		return null
	return wo.get_node_or_null("WorldSpawner") as MultiplayerSpawner


func _resolve_drop_scene(item: ItemResource) -> PackedScene:
	if item.world_item_scene != null:
		return item.world_item_scene
	match str(item.id):
		"walkie_talkie":
			return preload("res://scenes/items/walkie_talkie_radio.tscn")
		_:
			return _DEFAULT_DROP


func _spawn_dropped_item(
	spawner: MultiplayerSpawner,
	item: ItemResource,
	count: int,
	origin: Vector3,
	eject_basis: Basis,
	slot_index: int
) -> void:
	var scene: PackedScene = _resolve_drop_scene(item)
	if scene == null or scene.resource_path.is_empty():
		return
	var row_f: float = float(slot_index) / 5.0
	var jitter: Vector3 = eject_basis.x * (0.08 * float(slot_index % 5)) + eject_basis.y * (0.04 * row_f)
	var pos: Vector3 = origin + jitter
	var vel: Vector3 = eject_basis.z * (-1.8 - 0.35 * float(slot_index)) + eject_basis.y * 0.15
	var data: Dictionary = {
		"scene_path": scene.resource_path,
		"position": pos,
		"scale": 1.0,
		"velocity": vel,
	}
	for _k in range(maxi(1, count)):
		spawner.spawn(data)
