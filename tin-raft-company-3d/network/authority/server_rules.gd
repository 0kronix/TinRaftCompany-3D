extends RefCounted
class_name ServerRules

const MAX_INTERACT_DISTANCE: float = 3.0

func validate_command(actor: Node3D, command: Dictionary) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if command.is_empty():
		return false
	if not command.has("type"):
		return false
	if not command.has("target_path"):
		return false

	var tree := actor.get_tree()
	if tree == null:
		return false

	var target := tree.root.get_node_or_null(command["target_path"])
	if target == null or not is_instance_valid(target):
		return false

	if target is Node3D:
		var distance := actor.global_position.distance_to(target.global_position)
		if distance > MAX_INTERACT_DISTANCE:
			return false

	if target.has_method("server_validate_interaction"):
		return target.server_validate_interaction(actor)

	return true
