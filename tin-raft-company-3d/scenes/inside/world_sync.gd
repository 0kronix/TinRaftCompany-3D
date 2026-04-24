extends Node

## Attached to the root of the game scene.
## When a client loads the scene it asks the server for the list of
## objects already destroyed in this session, so late joiners see the
## same world state as everyone else.
func _ready() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_session_active():
		return
	if multiplayer.is_server():
		return
	# Wait one frame so the scene tree is fully initialised before despawning nodes.
	await get_tree().process_frame
	nm.request_world_sync()
