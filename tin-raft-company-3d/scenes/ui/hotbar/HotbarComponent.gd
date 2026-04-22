class_name HotbarComponent
extends Node

signal active_slot_changed(slot: int)

@export var hotbar_size: int = 5
@export var inventory_path: NodePath
@onready var inventory = get_tree().get_first_node_in_group("player").get_node("InventoryComponent")

var active_slot: int = 0

func _ready():
	set_active_slot(0)

func _unhandled_input(event: InputEvent) -> void:
	if _is_menu_open():
		return
	# цифровые клавиши 1–5
	for i in range(hotbar_size):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			set_active_slot(i)
			return

	# скролл колёсиком
	if event.is_action_pressed("hotbar_next"):
		set_active_slot((active_slot + 1) % hotbar_size)
	if event.is_action_pressed("hotbar_prev"):
		set_active_slot((active_slot - 1 + hotbar_size) % hotbar_size)

func set_active_slot(slot: int) -> void:
	active_slot = slot
	emit_signal("active_slot_changed", slot)

func get_active_item() -> ItemResource:
	return inventory.get_item(active_slot)

func use_active_item() -> void:
	var item = get_active_item()
	if item and item.is_usable:
		# здесь вызов логики использования
		_use_item(item, active_slot)

func _use_item(_item: ItemResource, _slot: int) -> void:
	pass


func _is_menu_open() -> bool:
	var menu := get_tree().get_first_node_in_group("settings_menu")
	return menu != null and menu.visible
