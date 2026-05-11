extends RefCounted
class_name LocalPlayerFinder
## Первый узел игрока с authority для текущего пира: группа `player` и fallback по пути куклы.


static func authority_player(tree: SceneTree) -> Node:
	if tree == null:
		return null
	for n: Node in tree.get_nodes_in_group("player"):
		if n.is_multiplayer_authority():
			return n
	return null


static func authority_character(tree: SceneTree, mp: MultiplayerAPI) -> CharacterBody3D:
	if tree == null:
		return null
	for n: Node in tree.get_nodes_in_group("player"):
		if n is CharacterBody3D and n.is_multiplayer_authority():
			return n as CharacterBody3D
	var my_id: int = mp.get_unique_id()
	if my_id == 0:
		my_id = 1
	var node := tree.root.get_node_or_null(GameScenePaths.player_puppet_path_str(my_id))
	if node is CharacterBody3D:
		return node as CharacterBody3D
	return null


static func authority_node3d(tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	for n: Node in tree.get_nodes_in_group("player"):
		if n is Node3D and n.is_multiplayer_authority():
			return n as Node3D
	return null


static func set_modal_ui_block_for_authority_player(tree: SceneTree, blocked: bool) -> void:
	if tree == null:
		return
	for p: Node in tree.get_nodes_in_group("player"):
		if p.is_multiplayer_authority() and p.has_method("set_modal_ui_block"):
			p.set_modal_ui_block(blocked)
			break
