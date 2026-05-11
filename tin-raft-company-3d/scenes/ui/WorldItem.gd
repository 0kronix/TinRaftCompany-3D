extends NetworkReplicatedRigidBody

@export var item_data: ItemResource
@export var count: int = 1

@onready var label = $RemoteTransform3D/Label3D


func _enter_tree() -> void:
	super._enter_tree()
	_ensure_stable_name()


func _ready() -> void:
	Label3DHint.prepare_hidden(label)


func _ensure_stable_name() -> void:
	var n: String = str(name)
	if n.begins_with("@"):
		var p: String = get_scene_file_path()
		var base: String = p.get_file().get_basename() if p else "Item"
		name = base + "_%d" % (get_instance_id() & 0xfffff)


func show_hint() -> void:
	Label3DHint.tween_show(self, label)


func hide_hint() -> void:
	Label3DHint.tween_hide(self, label)


func interact(caller: Node3D) -> void:
	var command := build_interaction_command()
	NetworkManager.request_command(caller, command)


func build_interaction_command() -> Dictionary:
	return {
		"type":        "pickup_world_item",
		"target_path": get_path()
	}


func server_validate_interaction(actor: Node3D) -> bool:
	# When actor has no inventory (server running with a puppet), skip that check —
	# the inventory grant is handled by NetworkManager._rpc_grant_pickup.
	if actor.get_node_or_null("InventoryComponent") == null:
		return item_data != null and count > 0
	var inventory := actor.get_node_or_null("InventoryComponent")
	var hotbar    := actor.get_node_or_null("HotbarComponent")
	return inventory != null and hotbar != null and item_data != null and count > 0


func server_apply_interaction(actor: Node3D, _command: Dictionary = {}) -> bool:
	var inventory := actor.get_node_or_null("InventoryComponent")

	if inventory == null:
		# Server-authoritative path: proxy actor (client-initiated pickup).
		_despawn_server()
		return true

	# Local path: singleplayer or server-host's own player.
	var hotbar := actor.get_node_or_null("HotbarComponent")
	if hotbar == null:
		return false
	if inventory.add_item(item_data, count, hotbar.active_slot):
		_despawn_server()
		return true
	return false


## Remove this node on the server, notifying peers appropriately.
## Nodes under WorldObjects are tracked by MultiplayerSpawner — it handles
## broadcasting the despawn automatically when queue_free() is called.
## Static scene nodes (direct children of Inside) are NOT tracked by the
## spawner, so NetworkManager must broadcast their removal manually.
func _despawn_server() -> void:
	var world_objects := GameScenePaths.get_world_objects_node(get_tree())
	var spawner_managed := world_objects != null and get_parent() == world_objects
	if not spawner_managed and NetworkManager.is_session_active():
		NetworkManager.notify_node_despawned(self)
	queue_free()
