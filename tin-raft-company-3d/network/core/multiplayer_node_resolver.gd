extends RefCounted
class_name MultiplayerNodeResolver
## Единая точка разрешения NodePath из RPC/команд между корнем viewport,
## текущей сценой и префиксом `Inside/`.


static func resolve(tree: SceneTree, path_variant: Variant) -> Node:
	if tree == null or path_variant == null:
		return null
	var s := str(path_variant)
	if s.is_empty():
		return null

	# get_path() даёт вида `/root/Inside/…`; для get_node под tree.root нужен «хвост» без `/root`.
	var variants: Array[String] = [s]
	if s.begins_with("/root/"):
		var trimmed: String = s.trim_prefix("/root/").lstrip("/")
		if not trimmed.is_empty():
			variants.append(trimmed)

	var scene_root: Node = tree.current_scene
	var n: Node = null

	for v: String in variants:
		var pn := NodePath(v)
		n = tree.root.get_node_or_null(pn)
		if n != null and is_instance_valid(n):
			return n
		if scene_root != null:
			n = scene_root.get_node_or_null(pn)
			if n != null and is_instance_valid(n):
				return n
			# main.tscn: узел-сцена — Inside; нужен суффикс по EVA/…
			if v.begins_with("Inside/"):
				var suffix: String = v.trim_prefix("Inside/")
				n = scene_root.get_node_or_null(NodePath(suffix))
				if n != null and is_instance_valid(n):
					return n

	var primary: String = variants[variants.size() - 1] if variants.size() > 0 else s
	if not primary.begins_with("Inside/"):
		n = tree.root.get_node_or_null(NodePath("Inside/" + primary))
		if n != null and is_instance_valid(n):
			return n

	return null


static func resolve_world_rigid(tree: SceneTree, path_str: String) -> Node:
	if path_str.is_empty():
		return null
	var n: Node = resolve(tree, path_str)
	if n != null and is_instance_valid(n):
		return n
	if path_str.begins_with("/root/"):
		var t: String = path_str.trim_prefix("/root/").lstrip("/")
		n = resolve(tree, t)
	return n
