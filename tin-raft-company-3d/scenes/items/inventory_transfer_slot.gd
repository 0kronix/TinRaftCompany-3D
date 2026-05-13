extends PanelContainer
## Слот для перетаскивания между двумя `InventoryComponent` (игрок ↔ ящик). Родитель — `StorageCrateUI`.

@onready var icon: TextureRect = $MarginContainer/Icon
@onready var count_label: Label = $MarginContainer/CountLabel

var slot_index: int = 0
var inventory: InventoryComponent
var ui_host: Control
var is_dragging := false


func bind_host(host: Control, inv: InventoryComponent, idx: int) -> void:
	ui_host = host
	inventory = inv
	slot_index = idx


func _ready() -> void:
	call_deferred("_fix_pivot")


func _fix_pivot() -> void:
	pivot_offset = size / 2.0


func set_item(slot) -> void:
	if slot == null:
		icon.texture = null
		count_label.text = ""
		return
	var item: ItemResource = slot["item"] as ItemResource
	var count: int = int(slot["count"])
	icon.texture = item.icon if item else null
	count_label.text = "" if item == null or item.max_stack == 1 else str(count)


func _get_drag_data(_at_position: Vector2) -> Variant:
	var slot = inventory.get_slot(slot_index)
	if slot == null:
		return null
	is_dragging = true
	var item: ItemResource = slot["item"] as ItemResource
	var count: int = int(slot["count"])
	var preview := Control.new()
	preview.custom_minimum_size = Vector2(50, 50)
	var tex := TextureRect.new()
	tex.texture = item.icon
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.add_child(tex)
	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		label.offset_left = -24.0
		label.offset_top = -24.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_child(label)
	set_drag_preview(preview)
	icon.visible = false
	count_label.visible = false
	return {"inv": inventory, "slot": slot_index}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		is_dragging = false
		icon.visible = true
		count_label.visible = true


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("inv") and data.has("slot")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if ui_host and ui_host.has_method("handle_inventory_drop"):
		ui_host.handle_inventory_drop(data["inv"], int(data["slot"]), inventory, slot_index)
