class_name InventoryComponent
extends Node

signal ready_for_ui
signal inventory_changed()
signal item_added(item: ItemResource, slot: int)
signal item_removed(slot: int)

@export var max_slots: int = 5
@export var max_mass: float = 20.0

# каждый слот: { "item": ItemResource, "count": int } или null
var slots: Array = []

func _ready():
	slots.resize(max_slots)
	slots.fill(null)
	emit_signal("ready_for_ui")

func add_item(item: ItemResource, count: int = 1, preferred_slot: int = -1) -> bool:
	# --- 1. пытаемся положить в выбранный слот ---
	if preferred_slot >= 0 and preferred_slot < max_slots:
		var slot = slots[preferred_slot]

		if slot == null:
			slots[preferred_slot] = { "item": item, "count": count }
			emit_signal("item_added", item, preferred_slot)
			emit_signal("inventory_changed")
			return true

		elif slot["item"].id == item.id and slot["count"] < item.max_stack:
			var space = item.max_stack - slot["count"]
			var add = min(space, count)

			slot["count"] += add
			count -= add

			if count <= 0:
				emit_signal("inventory_changed")
				return true
				
				
	# сначала ищем стак того же предмета
	for i in range(max_slots):
		if slots[i] == null:
			continue
		if slots[i]["item"].id == item.id and slots[i].count < item.max_stack:
			slots[i].count += count
			emit_signal("inventory_changed")
			return true

	# потом ищем пустой слот
	for i in max_slots:
		if slots[i] == null:
			if _current_mass() + item.mass * count > max_mass:
				return false   # перегруз
			slots[i] = { "item": item, "count": count }
			emit_signal("item_added", item, i)
			emit_signal("inventory_changed")
			return true

	return false   # инвентарь полон

func remove_item(slot: int, count: int = 1) -> void:
	if slots[slot] == null:
		return
	slots[slot]["count"] -= count
	if slots[slot]["count"] <= 0:
		slots[slot] = null
		emit_signal("item_removed", slot)
	emit_signal("inventory_changed")

func swap_slots(a: int, b: int):
	var temp = slots[a]
	slots[a] = slots[b]
	slots[b] = temp
	emit_signal("inventory_changed")

func get_slot(slot: int):
	if slot < 0 or slot >= slots.size():
		return null
	return slots[slot]

func has_item(item_id: String, count: int = 1) -> bool:
	var found = 0
	for slot in slots:
		if slot and slot.item.id == item_id:
			found += slot.count
	return found >= count

func _current_mass() -> float:
	var total = 0.0
	for slot in slots:
		if slot:
			total += slot.item.mass * slot.count
	return total
