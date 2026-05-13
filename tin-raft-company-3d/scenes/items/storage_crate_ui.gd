extends Control
## UI ящика: игрок слева, ящик справа. Закрыть — Esc / кнопка.

const _SLOT := preload("res://scenes/items/inventory_transfer_slot.tscn")

@onready var _player_grid: HBoxContainer = $CanvasLayer/Panel/Margin/VBox/Grids/PlayerColumn/Slots
@onready var _crate_grid: GridContainer = $CanvasLayer/Panel/Margin/VBox/Grids/CrateColumn/Slots
@onready var _btn_close: Button = $CanvasLayer/Panel/Margin/VBox/Buttons/CloseButton
@onready var _btn_eject: Button = $CanvasLayer/Panel/Margin/VBox/Buttons/EjectButton

var _crate: Node = null
var _crate_inv: InventoryComponent
var _player_inv: InventoryComponent
var _player_slots: Array[Control] = []
var _crate_slots: Array[Control] = []


func set_interactable_target(path_str: String) -> void:
	if get_tree() == null:
		call_deferred("set_interactable_target", path_str)
		return
	_crate = get_tree().root.get_node_or_null(NodePath(path_str))
	if _crate and _crate.has_method("get_crate_inventory"):
		_crate_inv = _crate.call("get_crate_inventory") as InventoryComponent
	# UIManager вызывает это после add_child, но _ready уже отработал без ящика — догоняем привязку.
	if is_inside_tree():
		_bind_crate_after_target()


func set_helm_target(path_str: String) -> void:
	set_interactable_target(path_str)


func _ready() -> void:
	_player_inv = _find_player_inventory()
	if _btn_close:
		_btn_close.pressed.connect(_on_close)
	if _btn_eject:
		_btn_eject.visible = false
		_btn_eject.pressed.connect(_on_eject)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _player_inv:
		_player_inv.inventory_changed.connect(_refresh_player_only)
	_build_player_slots_only()
	_bind_crate_after_target()
	_refresh_all()


## Слоты и сигналы ящика: после set_interactable_target или из _ready если цель уже задана.
func _bind_crate_after_target() -> void:
	if _crate_inv == null or not is_instance_valid(_crate_inv):
		return
	if _btn_eject:
		_btn_eject.visible = (
			_crate != null
			and is_instance_valid(_crate)
			and _crate.has_method("is_ejector_crate")
			and bool(_crate.call("is_ejector_crate"))
		)
	if not _crate_inv.inventory_changed.is_connected(_refresh_crate_only):
		_crate_inv.inventory_changed.connect(_refresh_crate_only)
	if _crate_slots.is_empty() and _crate_grid:
		for i in _crate_inv.max_slots:
			var s2: Control = _SLOT.instantiate() as Control
			_crate_grid.add_child(s2)
			if s2.has_method("bind_host"):
				s2.bind_host(self, _crate_inv, i)
			_crate_slots.append(s2)
	call_deferred("_request_snapshot")
	_refresh_all()


func _exit_tree() -> void:
	if _crate_inv and is_instance_valid(_crate_inv):
		if _crate_inv.inventory_changed.is_connected(_refresh_crate_only):
			_crate_inv.inventory_changed.disconnect(_refresh_crate_only)
	if _player_inv and is_instance_valid(_player_inv):
		if _player_inv.inventory_changed.is_connected(_refresh_player_only):
			_player_inv.inventory_changed.disconnect(_refresh_player_only)


func _find_player_inventory() -> InventoryComponent:
	var p: Node = LocalPlayerFinder.authority_player(get_tree())
	if p == null:
		return null
	return p.get_node_or_null("InventoryComponent") as InventoryComponent


func _request_snapshot() -> void:
	if _crate == null or not is_instance_valid(_crate):
		return
	if not NetworkManager.is_session_active():
		return
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		return
	if _crate.has_method("rpc_request_crate_snapshot"):
		_crate.rpc_request_crate_snapshot.rpc_id(1)


func _build_player_slots_only() -> void:
	if _player_slots.size() > 0:
		return
	if _player_inv and _player_grid:
		for i in _player_inv.max_slots:
			var s: Control = _SLOT.instantiate() as Control
			_player_grid.add_child(s)
			if s.has_method("bind_host"):
				s.bind_host(self, _player_inv, i)
			_player_slots.append(s)


func _refresh_all() -> void:
	_refresh_player_only()
	_refresh_crate_only()


func _refresh_player_only() -> void:
	if _player_inv == null:
		return
	for i in _player_slots.size():
		var sl: Control = _player_slots[i]
		if sl.has_method("set_item"):
			sl.set_item(_player_inv.get_slot(i))


func _refresh_crate_only() -> void:
	if _crate_inv == null:
		return
	for i in _crate_slots.size():
		var sl: Control = _crate_slots[i]
		if sl.has_method("set_item"):
			sl.set_item(_crate_inv.get_slot(i))


func _on_close() -> void:
	queue_free()


func _on_eject() -> void:
	if _crate == null or not is_instance_valid(_crate):
		return
	if not bool(_crate.call("is_ejector_crate")):
		return
	if not NetworkManager.is_session_active() or not multiplayer.has_multiplayer_peer():
		_crate.call("offline_eject_all")
		_refresh_all()
		return
	if _crate.has_method("rpc_request_eject"):
		if multiplayer.is_server():
			_crate.rpc_request_eject()
		else:
			_crate.rpc_request_eject.rpc_id(1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_close"):
		_on_close()


func handle_inventory_drop(from_inv: InventoryComponent, from_i: int, to_inv: InventoryComponent, to_i: int) -> void:
	if from_inv == null or to_inv == null:
		return
	if from_inv == to_inv:
		_handle_same_inventory_swap(from_inv, from_i, to_i)
		return
	if from_inv == _player_inv and to_inv == _crate_inv:
		_handle_p2c(from_i, to_i)
		return
	if from_inv == _crate_inv and to_inv == _player_inv:
		_handle_c2p(from_i, to_i)
		return


func _handle_same_inventory_swap(inv: InventoryComponent, from_i: int, to_i: int) -> void:
	if from_i == to_i:
		return
	if inv == _crate_inv and NetworkManager.is_session_active() and multiplayer.has_multiplayer_peer():
		if _crate and _crate.has_method("rpc_request_crate_internal_move"):
			if multiplayer.is_server():
				_crate.rpc_request_crate_internal_move(from_i, to_i)
			else:
				_crate.rpc_request_crate_internal_move.rpc_id(1, from_i, to_i)
		_refresh_all()
		return
	var from_s: Variant = inv.get_slot(from_i)
	var to_s: Variant = inv.get_slot(to_i)
	if to_s == null:
		inv.swap_slots(from_i, to_i)
	elif from_s and (from_s["item"] as ItemResource).id == (to_s["item"] as ItemResource).id:
		var max_stack: int = int((from_s["item"] as ItemResource).max_stack)
		var total: int = int(from_s["count"]) + int(to_s["count"])
		if total <= max_stack:
			to_s["count"] = total
			inv.slots[from_i] = null
		else:
			to_s["count"] = max_stack
			from_s["count"] = total - max_stack
		inv.emit_signal("inventory_changed")
	else:
		inv.swap_slots(from_i, to_i)
	_refresh_all()


func _handle_p2c(from_i: int, to_i: int) -> void:
	var fs: Variant = _player_inv.get_slot(from_i)
	if fs == null:
		return
	var it: ItemResource = fs["item"] as ItemResource
	if it == null:
		return
	var move_n: int = _merge_move_count_player_to_crate(from_i, to_i)
	if move_n <= 0:
		return
	var path_str: String = it.resource_path
	if not NetworkManager.is_session_active() or not multiplayer.has_multiplayer_peer():
		if _crate:
			_crate.call("offline_player_to_crate", _player_inv, from_i, to_i)
		_refresh_all()
		return
	if _crate and _crate.has_method("rpc_request_p2c"):
		if multiplayer.is_server():
			_crate.rpc_request_p2c(from_i, to_i, path_str, move_n)
		else:
			_crate.rpc_request_p2c.rpc_id(1, from_i, to_i, path_str, move_n)
	_refresh_all()


func _handle_c2p(from_ci: int, to_pi: int) -> void:
	var fs: Variant = _crate_inv.get_slot(from_ci)
	if fs == null:
		return
	var it: ItemResource = fs["item"] as ItemResource
	if it == null:
		return
	var move_n: int = _merge_move_count_crate_to_player(from_ci, to_pi)
	if move_n <= 0:
		return
	var path_str: String = it.resource_path
	if not NetworkManager.is_session_active() or not multiplayer.has_multiplayer_peer():
		if _crate:
			_crate.call("offline_crate_to_player", _player_inv, from_ci, to_pi)
		_refresh_all()
		return
	if _crate and _crate.has_method("rpc_request_c2p"):
		if multiplayer.is_server():
			_crate.rpc_request_c2p(from_ci, to_pi, path_str, move_n)
		else:
			_crate.rpc_request_c2p.rpc_id(1, from_ci, to_pi, path_str, move_n)
	_refresh_all()


func _merge_move_count_player_to_crate(from_i: int, to_i: int) -> int:
	var fs: Variant = _player_inv.get_slot(from_i)
	var ts: Variant = _crate_inv.get_slot(to_i)
	if fs == null:
		return 0
	var full: int = int(fs["count"])
	if ts == null:
		return full
	if (ts["item"] as ItemResource).id != (fs["item"] as ItemResource).id:
		return 0
	var mx: int = int((fs["item"] as ItemResource).max_stack)
	var cur: int = int(ts["count"])
	return mini(mx - cur, full)


func _merge_move_count_crate_to_player(from_ci: int, to_pi: int) -> int:
	var fs: Variant = _crate_inv.get_slot(from_ci)
	var ts: Variant = _player_inv.get_slot(to_pi)
	if fs == null:
		return 0
	var full: int = int(fs["count"])
	if ts == null:
		return full
	if (ts["item"] as ItemResource).id != (fs["item"] as ItemResource).id:
		return 0
	var mx: int = int((fs["item"] as ItemResource).max_stack)
	var cur: int = int(ts["count"])
	return mini(mx - cur, full)
