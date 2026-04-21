extends HBoxContainer

@onready var inventory: InventoryComponent = get_tree().get_first_node_in_group("player").get_node("InventoryComponent")
@onready var hotbar: HotbarComponent = get_tree().get_first_node_in_group("player").get_node("HotbarComponent")

var slot_nodes: Array[Control] = []

func _ready() -> void:
	inventory.inventory_changed.connect(_refresh)
	hotbar.active_slot_changed.connect(_highlight)
	_build_slots()
	_refresh
	inventory.ready_for_ui.connect(_refresh)

func _build_slots():
	for i in hotbar.hotbar_size:
		var slot = preload("res://scenes/ui/HotbarSlot.tscn").instantiate()
		add_child(slot)

		slot.slot_index = i
		slot.inventory = inventory

		slot_nodes.append(slot)

func _refresh():
	for i in slot_nodes.size():
		var slot_data = inventory.get_slot(i)
		slot_nodes[i].set_item(slot_data)

func _highlight(active: int) -> void:
	for i in slot_nodes.size():
		var slot = slot_nodes[i]

		var target_scale = Vector2(1.15, 1.15) if i == active else Vector2(1.0, 1.0)
		var target_color = Color(1.2, 1.2, 1.2) if i == active else Color(0.85, 0.85, 0.85)

		var tween = get_tree().create_tween()
		tween.tween_property(slot, "scale", target_scale, 0.1)
		tween.tween_property(slot, "modulate", target_color, 0.1)
