extends Node

## Minimal UIManager autoload.
## Displays a UI scene in the local player's UILayer canvas layer.

func show_ui(ui_scene: PackedScene) -> void:
	_show_ui_impl(ui_scene, "", false)


## Модальное UI: курсор, блок ввода/движения на локальном игроке до закрытия (tree_exited).
func show_ui_for_local_player_with_block(ui_scene: PackedScene, interactable_target_path: String = "") -> void:
	_show_ui_impl(ui_scene, interactable_target_path, true)


func _show_ui_impl(ui_scene: PackedScene, interactable_target_path: String, with_modal_block: bool) -> void:
	if ui_scene == null:
		return
	var ui_layer := _find_ui_layer()
	if ui_layer == null:
		push_warning("UIManager: could not find UILayer for local player")
		return
	# `queue_free` откладывает выход: новый child + старый в одном кадре портит modal/tree_exited.
	for c: Node in ui_layer.get_children().duplicate():
		c.free()
	var ui: Node = ui_scene.instantiate()
	if not interactable_target_path.is_empty() and ui.has_method("set_helm_target"):
		ui.set_helm_target(interactable_target_path)
	ui_layer.add_child(ui)
	if not with_modal_block:
		return
	LocalPlayerFinder.set_modal_ui_block_for_authority_player(get_tree(), true)
	# Godot 4.x: Object.CONNECT_ONE_SHOT
	ui.tree_exited.connect(
		_on_modal_interactable_ui_exited, Object.CONNECT_ONE_SHOT
	)


func _on_modal_interactable_ui_exited() -> void:
	# После queue_free узла дерево может быть ещё невалидно в том же кадру.
	call_deferred("_release_modal_player_block")


func _release_modal_player_block() -> void:
	var tree := get_tree()
	if tree == null:
		return
	LocalPlayerFinder.set_modal_ui_block_for_authority_player(tree, false)
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _find_ui_layer() -> CanvasLayer:
	# Try the dedicated UILayer in the game scene first.
	var game_scene := get_tree().current_scene
	if game_scene:
		var layer := game_scene.get_node_or_null("UILayer") as CanvasLayer
		if layer:
			return layer
	var player: Node = LocalPlayerFinder.authority_player(get_tree())
	if player:
		var layer := player.get_node_or_null("MenuLayer") as CanvasLayer
		if layer:
			return layer
	return null
