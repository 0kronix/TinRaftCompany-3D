extends RefCounted
class_name WorldRigidReplicaSync
## Клиент: либо в буфер для интерполяции (RigidBody со receive_net_physics_snapshot), либо мгновенный snap.


static func relay_snapshot(tree: SceneTree, path_str: String, pos: Vector3, rot_rad: Vector3) -> void:
	var n: Node = MultiplayerNodeResolver.resolve_world_rigid(tree, path_str)
	if not (n is RigidBody3D):
		return
	var rb: RigidBody3D = n as RigidBody3D
	if rb.is_multiplayer_authority():
		return
	if rb.has_method("receive_net_physics_snapshot"):
		rb.call("receive_net_physics_snapshot", pos, rot_rad)
	else:
		_apply_rigid_pose_immediate(rb, pos, rot_rad)


static func apply_remote_pose(tree: SceneTree, path_str: String, pos: Vector3, rot_rad: Vector3) -> void:
	var n: Node = MultiplayerNodeResolver.resolve_world_rigid(tree, path_str)
	if not (n is RigidBody3D):
		return
	var rb: RigidBody3D = n as RigidBody3D
	if rb.is_multiplayer_authority():
		return
	_apply_rigid_pose_immediate(rb, pos, rot_rad)


static func _apply_rigid_pose_immediate(rb: RigidBody3D, pos: Vector3, rot_rad: Vector3) -> void:
	rb.global_position = pos
	rb.global_rotation = rot_rad
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.reset_physics_interpolation()
