extends RefCounted
class_name ServerRules

## Метры: до pivot цели; панели/терминалы с большим мешем иначе ломают валидацию при 3 м.
const MAX_INTERACT_DISTANCE: float = 8.0

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

	var target: Node = MultiplayerNodeResolver.resolve(tree, command.get("target_path"))
	if target == null or not is_instance_valid(target):
		return false

	if str(command.get("type", "")) == "shuttle_tether_toggle":
		if target.has_method("server_validate_interaction"):
			return target.server_validate_interaction(actor)
		return true

	var ctype: String = str(command.get("type", ""))
	if ctype == "radar_set_mode" or ctype == "radar_cycle_peer":
		if target.has_method("server_validate_interaction"):
			return target.server_validate_interaction(actor)
		return true

	if target is Node3D:
		var distance := actor.global_position.distance_to(target.global_position)
		if distance > MAX_INTERACT_DISTANCE:
			return false

	if target.has_method("server_validate_interaction"):
		return target.server_validate_interaction(actor)

	return true
