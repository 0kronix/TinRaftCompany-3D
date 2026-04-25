extends RefCounted
class_name CommandRouter

func execute_command(actor: Node3D, command: Dictionary) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false

	var target := _resolve_target(actor, command)
	if target == null:
		return false

	if target.has_method("server_apply_interaction"):
		return target.server_apply_interaction(actor)

	return false

func _resolve_target(actor: Node3D, command: Dictionary) -> Node:
	if not command.has("target_path"):
		return null
	var tree := actor.get_tree()
	if tree == null:
		return null
	var nm: Node = tree.root.get_node_or_null("NetworkManager")
	if nm and nm.has_method("_resolve_command_target_node"):
		var t: Node = nm._resolve_command_target_node(command.get("target_path"))
		if t and is_instance_valid(t):
			return t
	return tree.root.get_node_or_null(NodePath(String(command.get("target_path", ""))))
