extends RefCounted
class_name ShuttleSyncService
## Пилот / ввод шаттла (RPC на NetworkManager).


var _host: Node


func _init(host_node: Node) -> void:
	_host = host_node


func set_pilot_peer_id(path_str: String, peer_id: int) -> void:
	var n: Node = MultiplayerNodeResolver.resolve(_host.get_tree(), path_str)
	if n is RigidBody3D:
		(n as RigidBody3D).set("pilot_peer_id", peer_id)


func apply_client_pilot_input(path_str: String, from_peer_id: int, bits: int) -> void:
	var n: Node = MultiplayerNodeResolver.resolve(_host.get_tree(), path_str)
	if not (n is RigidBody3D):
		return
	var rb: RigidBody3D = n as RigidBody3D
	if rb.get("pilot_peer_id") != from_peer_id:
		return
	if rb.has_method("apply_pilot_input_bits"):
		rb.apply_pilot_input_bits(bits)
