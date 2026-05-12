extends RefCounted
class_name AirlockTeleportService
## Телепорт шлюза: только peer с authority над своим игроком (или solo).


static func apply(host: Node, teleport_type: String) -> void:
	var tree := host.get_tree()
	var p := find_local_authority_player(tree, host.multiplayer)
	if p == null:
		return
	if host.is_session_active() and not p.is_multiplayer_authority():
		return

	var eva_m: Node3D = tree.get_first_node_in_group("eva_spawn") as Node3D
	if eva_m == null:
		eva_m = tree.root.get_node_or_null(GameScenePaths.EVA_SHUTTLE_EVASPAWN) as Node3D
	var cap_m: Node3D = tree.get_first_node_in_group("capsule_return") as Node3D
	if cap_m == null:
		cap_m = tree.root.get_node_or_null(
			"%s/%s/CapsuleReturn" % [GameScenePaths.INSIDE, GameScenePaths.PLAYER_CONTAINER]
		) as Node3D

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
	if teleport_type == "airlock_exit":
		_apply_shuttle_velocity_to_player(tree, p)


static func _apply_shuttle_velocity_to_player(tree: SceneTree, p: CharacterBody3D) -> void:
	var shuttle: RigidBody3D = tree.root.get_node_or_null(GameScenePaths.EVA_SHUTTLE) as RigidBody3D
	if shuttle == null:
		return
	var w: Vector3 = shuttle.angular_velocity
	var r: Vector3 = p.global_position - shuttle.global_position
	var v: Vector3 = shuttle.linear_velocity + w.cross(r)
	const V_MAX := 200.0
	if v.length_squared() > V_MAX * V_MAX:
		v = v.normalized() * V_MAX
	p.velocity = v


static func find_local_authority_player(tree: SceneTree, mp: MultiplayerAPI) -> CharacterBody3D:
	return LocalPlayerFinder.authority_character(tree, mp)


static func should_apply_local_after_command(command: Dictionary) -> bool:
	return command.get("type", "") in ["airlock_exit", "airlock_return"]
