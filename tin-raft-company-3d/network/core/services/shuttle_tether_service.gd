extends RefCounted
class_name ShuttleTetherService
## RPC на инициатора: переключить привязку к модулю кабеля на шаттле.


static func should_apply_local_after_command(command: Dictionary) -> bool:
	return command.get("type", "") == "shuttle_tether_toggle"


static func apply(host: Node, target_path_variant: Variant) -> void:
	var tree := host.get_tree()
	if tree == null:
		return
	var mp: MultiplayerAPI = host.multiplayer
	var p: CharacterBody3D = LocalPlayerFinder.authority_character(tree, mp)
	if p == null:
		return
	if host.is_session_active() and not p.is_multiplayer_authority():
		return
	var mod: Node = MultiplayerNodeResolver.resolve(tree, target_path_variant)
	if mod == null or not is_instance_valid(mod):
		return
	if p.has_method("toggle_shuttle_tether_at_module"):
		p.toggle_shuttle_tether_at_module(mod)
