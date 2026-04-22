# PageControls.gd
extends VBoxContainer

func _ready() -> void:
	_build()

func _build() -> void:
	_add_section("Мышь")
	_add_row("Чувствительность", "", "mouse_sens", SettingRow.RowType.SLIDER)
	_add_row("Инвертировать Y",  "", "invert_y",   SettingRow.RowType.TOGGLE)

	_add_section("Movement")
	_add_keybind("Forward",    "move_forward")
	_add_keybind("Назад",     "move_back")
	_add_keybind("Влево",     "move_left")
	_add_keybind("Вправо",    "move_right")
	_add_keybind("Прыжок",    "jump")

	_add_section("Items")
	_add_keybind("Interact", "interact")
	_add_keybind("Inventory",      "inventory")
	_add_keybind("Слот 1", "hotbar_1")
	_add_keybind("Слот 2", "hotbar_2")
	_add_keybind("Слот 3", "hotbar_3")
	_add_keybind("Слот 4", "hotbar_4")
	_add_keybind("Слот 5", "hotbar_5")
	_add_keybind("Слот 6", "hotbar_6")

func _add_section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate.a = 0.5
	add_child(lbl)
	add_child(HSeparator.new())

func _add_row(label: String, hint: String, key: String, type: SettingRow.RowType) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.hint_text   = hint
	row.setting_key = key
	row.row_type    = type
	add_child(row)

func _add_keybind(label: String, key: String) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.setting_key = key
	row.row_type    = SettingRow.RowType.KEYBIND
	add_child(row)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_build()
