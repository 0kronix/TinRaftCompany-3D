extends RefCounted
class_name FieldAsteroidSync
## Клиентский спавн и серверный снимок EVA-астероидов `AsteroidField_*`.
## RPC остаются на NetworkManager; здесь только детерминированная логика дерева.


static func spawn_one_client(
	tree: SceneTree,
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
	var scene_root: Node = tree.current_scene
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
	var sp: Node3D = MultiplayerNodeResolver.resolve(tree, spawner_path) as Node3D
	if sp:
		object.set("spawner_center", sp)
		if object.has_signal("despawned") and sp.has_method("_on_despawn"):
			object.despawned.connect(Callable(sp, "_on_despawn"))


static func spawn_from_record(tree: SceneTree, m: Dictionary, skip_if_exists: bool) -> void:
	spawn_one_client(
		tree,
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
		skip_if_exists
	)


static func collect_snapshot(inside_root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if inside_root == null or not is_instance_valid(inside_root):
		return out
	_collect_recursive(inside_root, out)
	return out


static func _collect_recursive(n: Node, out: Array[Dictionary]) -> void:
	for c: Node in n.get_children():
		var node_name := str(c.name)
		if node_name.begins_with("AsteroidField_") and c is RigidBody3D:
			var rb: RigidBody3D = c as RigidBody3D
			var sfp: String = rb.get_scene_file_path()
			if sfp.is_empty():
				_collect_recursive(c, out)
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
		_collect_recursive(c, out)


## Клиент: пакетное восстановление поля астероидов (late join).
static func apply_record_batch(tree: SceneTree, records: Array) -> void:
	for d: Variant in records:
		if d is Dictionary:
			spawn_from_record(tree, d as Dictionary, true)
