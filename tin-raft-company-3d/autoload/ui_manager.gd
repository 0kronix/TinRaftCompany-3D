extends Node

## Minimal UIManager autoload.
## Displays a UI scene in the local player's UILayer canvas layer.

func show_ui(ui_scene: PackedScene) -> void:
	if ui_scene == null:
		return
	# Find the UILayer of the local (authority) player.
	var ui_layer := _find_ui_layer()
	if ui_layer == null:
		push_warning("UIManager.show_ui: could not find UILayer for local player")
		return
	# Remove any previously opened UI in this layer.
	for child in ui_layer.get_children():
		child.queue_free()
	var ui := ui_scene.instantiate()
	ui_layer.add_child(ui)


func _find_ui_layer() -> CanvasLayer:
	# Try the dedicated UILayer in the game scene first.
	var game_scene := get_tree().current_scene
	if game_scene:
		var layer := game_scene.get_node_or_null("UILayer") as CanvasLayer
		if layer:
			return layer
	# Fallback: find via the local player node.
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player.is_multiplayer_authority():
			var layer := player.get_node_or_null("MenuLayer") as CanvasLayer
			if layer:
				return layer
	return null
