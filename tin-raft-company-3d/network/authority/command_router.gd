extends RefCounted
class_name CommandRouter

func execute_command(actor: Node3D, command: Dictionary) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false

	var target := _resolve_target(actor, command)
	if target == null:
		return false

	if target.has_method("server_apply_interaction"):
		return target.server_apply_interaction(actor, command)

	return false

func _resolve_target(actor: Node3D, command: Dictionary) -> Node:
	if not command.has("target_path"):
		return null
	var tree := actor.get_tree()
	if tree == null:
		return null
	return MultiplayerNodeResolver.resolve(tree, command.get("target_path"))
