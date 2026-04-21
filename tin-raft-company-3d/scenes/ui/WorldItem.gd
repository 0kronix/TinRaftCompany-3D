extends RigidBody3D

@export var item_data: ItemResource
@export var count: int = 1

@onready var label = $RemoteTransform3D/Label3D

func _ready():
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)

func show_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)

func hide_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)

func interact(caller):
	var inventory = caller.get_node_or_null("InventoryComponent")
	var hotbar = caller.get_node_or_null("HotbarComponent")

	if inventory and hotbar:
		if inventory.add_item(item_data, count, hotbar.active_slot):
			queue_free()
