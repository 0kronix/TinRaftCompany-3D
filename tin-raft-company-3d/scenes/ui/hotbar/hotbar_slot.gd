# HotbarSlot.gd
extends PanelContainer

@onready var icon: TextureRect = $MarginContainer/Icon
@onready var count_label: Label = $MarginContainer/CountLabel

var slot_index: int
var inventory: InventoryComponent
var is_dragging := false

func _ready():
	call_deferred("fix_pivot")

func fix_pivot():
	pivot_offset = size / 2

func set_item(slot):
	if slot == null:
		icon.texture = null
		count_label.text = ""
		return

	var item = slot["item"]
	var count = slot["count"]

	icon.texture = item.icon
	count_label.text = "" if item.max_stack == 1 else str(count)

func set_selected(selected: bool) -> void:
	# подсветка активного слота
	var style = get_theme_stylebox("panel").duplicate()
	style.border_color = Color.YELLOW if selected else Color.TRANSPARENT
	add_theme_stylebox_override("panel", style)
	
func _get_drag_data(_at_position):
	var slot = inventory.get_slot(slot_index)
	if slot == null:
		return null

	is_dragging = true

	var item = slot["item"]
	var count = slot["count"]

	# --- контейнер ---
	var preview = Control.new()
	preview.custom_minimum_size = Vector2(50, 50)

	# --- иконка ---
	var tex = TextureRect.new()
	tex.texture = item.icon
	tex.expand = true
	tex.size = Vector2(95, 95)
	preview.add_child(tex)

	# --- текст ---
	if count > 1:
		var label = Label.new()
		label.text = str(count)
		label.anchor_left = 1
		label.anchor_top = 1
		label.anchor_right = 1
		label.anchor_bottom = 1
		label.offset_left = -20
		label.offset_top = -20
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

		# читаемость
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color.BLACK)

		preview.add_child(label)

	set_drag_preview(preview)

	# скрываем слот
	icon.visible = false
	count_label.visible = false

	return {
		"from": slot_index
	}


func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		is_dragging = false
		icon.visible = true
		count_label.visible = true


func _can_drop_data(_at_position, data):
	return typeof(data) == TYPE_DICTIONARY and data.has("from")


func _drop_data(_at_position, data):
	var from = data["from"]
	var to = slot_index

	if from == to:
		return

	var from_slot = inventory.get_slot(from)
	var to_slot = inventory.get_slot(to)

	# --- если целевой пустой → просто перенос ---
	if to_slot == null:
		inventory.swap_slots(from, to)
		return

	# --- если одинаковые предметы → merge ---
	if from_slot["item"].id == to_slot["item"].id:
		var max_stack = from_slot["item"].max_stack

		var total = from_slot["count"] + to_slot["count"]

		if total <= max_stack:
			# полностью объединяем
			to_slot["count"] = total
			inventory.slots[from] = null
		else:
			# частично
			to_slot["count"] = max_stack
			from_slot["count"] = total - max_stack

		inventory.inventory_changed.emit()
		return

	# --- иначе swap ---
	inventory.swap_slots(from, to)
