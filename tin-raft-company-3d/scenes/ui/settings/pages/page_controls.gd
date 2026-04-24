# PageControls.gd
extends VBoxContainer

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	_configure_layout()
	_build()

func _build() -> void:
	_add_section(_t("Мышь", "Mouse"))
	_add_row(_t("Чувствительность", "Sensitivity"), "", "mouse_sens", SettingRow.RowType.SLIDER)
	_add_row(_t("Инвертировать Y", "Invert Y"), "", "invert_y", SettingRow.RowType.TOGGLE)

	_add_section(_t("Движение", "Movement"))
	_add_keybind(_t("Вперёд", "Forward"), "move_forward")
	_add_keybind(_t("Назад", "Backward"), "move_back")
	_add_keybind(_t("Влево", "Left"), "move_left")
	_add_keybind(_t("Вправо", "Right"), "move_right")
	_add_keybind(_t("Прыжок", "Jump"), "jump")

	_add_section(_t("Взаимодействие", "Interaction"))
	_add_keybind(_t("Действие", "Interact"), "interact")
	_add_keybind(_t("Инвентарь", "Inventory"), "inventory")
	_add_keybind(_t("Слот 1", "Slot 1"), "hotbar_1")
	_add_keybind(_t("Слот 2", "Slot 2"), "hotbar_2")
	_add_keybind(_t("Слот 3", "Slot 3"), "hotbar_3")
	_add_keybind(_t("Слот 4", "Slot 4"), "hotbar_4")
	_add_keybind(_t("Слот 5", "Slot 5"), "hotbar_5")
	_add_keybind(_t("Слот 6", "Slot 6"), "hotbar_6")

func _add_section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate.a = 0.5
	content.add_child(lbl)
	content.add_child(HSeparator.new())

func _add_row(label: String, hint: String, key: String, type: SettingRow.RowType) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.hint_text   = hint
	row.setting_key = key
	row.row_type    = type
	content.add_child(row)

func _add_keybind(label: String, key: String) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.setting_key = key
	row.row_type    = SettingRow.RowType.KEYBIND
	content.add_child(row)

func refresh() -> void:
	for child in content.get_children():
		child.queue_free()
	_build()

func _configure_layout() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	$ScrollContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$ScrollContainer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)

func _t(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en
