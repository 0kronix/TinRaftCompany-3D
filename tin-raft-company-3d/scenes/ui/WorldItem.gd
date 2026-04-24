extends RigidBody3D

@export var item_data: ItemResource
@export var count: int = 1

@onready var label = $RemoteTransform3D/Label3D

func _ready() -> void:
	# Freeze physics so the item sits still identically on all peers.
	freeze = true
	label.modulate         = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)


func show_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a",         1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)


func hide_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a",         0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)


func interact(caller: Node3D) -> void:
	var command := build_interaction_command()
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.request_command(caller, command)


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


func server_apply_interaction(actor: Node3D) -> bool:
	var inventory := actor.get_node_or_null("InventoryComponent")
	var nm        := get_node_or_null("/root/NetworkManager")

	if inventory == null:
		# Server-authoritative path: proxy actor (client-initiated pickup).
		_despawn_server(nm)
		return true

	# Local path: singleplayer or server-host's own player.
	var hotbar := actor.get_node_or_null("HotbarComponent")
	if hotbar == null:
		return false
	if inventory.add_item(item_data, count, hotbar.active_slot):
		_despawn_server(nm)
		return true
	return false


## Remove this node on the server, notifying peers appropriately.
## Nodes under WorldObjects are tracked by MultiplayerSpawner — it handles
## broadcasting the despawn automatically when queue_free() is called.
## Static scene nodes (direct children of Inside) are NOT tracked by the
## spawner, so NetworkManager must broadcast their removal manually.
func _despawn_server(nm: Node) -> void:
	var world_objects := get_node_or_null("/root/Inside/WorldObjects")
	var spawner_managed := world_objects != null and get_parent() == world_objects
	if not spawner_managed and nm and nm.is_session_active():
		nm.notify_node_despawned(self)
	queue_free()
