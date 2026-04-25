extends RigidBody3D
## Синхронизация transform с сервера (authority 1) через NetworkManager, без @rpc на этом узле
## (иначе process_simplify_path / scene cache по пути RigidBody остаётся в движке, см. #87426).

const NET_SYNC_HZ: float = 20.0

var _net_sync_accum: float = 0.0


func _replicated_rigidbody_enter() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		set_multiplayer_authority(1)
	if not is_multiplayer_authority():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _replicated_rigidbody_physics(delta: float) -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	if not is_multiplayer_authority():
		return
	_net_sync_accum += delta
	if _net_sync_accum < 1.0 / NET_SYNC_HZ:
		return
	_net_sync_accum = 0.0
	# @rpc нельзя вешать на RigidBody — process_simplify_path кэш по путям. См. NetworkManager.
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("broadcast_world_rigid_transform"):
		nm.broadcast_world_rigid_transform(str(get_path()), global_position, global_rotation)


func _enter_tree() -> void:
	_replicated_rigidbody_enter()


func _physics_process(delta: float) -> void:
	_replicated_rigidbody_physics(delta)
