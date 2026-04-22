# PageSound.gd
extends VBoxContainer

func _ready() -> void:
	_build()

func _build() -> void:
	_add_section("Основное")
	_add_row("Общая громкость",    "",                        "vol_master", SettingRow.RowType.SLIDER)
	_add_row("Музыка",             "Ambient / саундтрек",     "vol_music",  SettingRow.RowType.SLIDER)
	_add_row("Звуковые эффекты",   "Системы, механика",       "vol_sfx",    SettingRow.RowType.SLIDER)

	_add_section("Рация и голос")
	_add_row("Громкость рации",    "Входящий голос игроков",  "vol_radio",  SettingRow.RowType.SLIDER)
	_add_row("Помехи рации",       "Интенсивность шума",      "vol_static", SettingRow.RowType.SLIDER)
	_add_row("Звук тревоги",       "",                        "alarm_enabled", SettingRow.RowType.TOGGLE)
	_add_row("Когнитивный шум",    "Галлюцинации при гипоксии","halluc_sound",SettingRow.RowType.TOGGLE)

	_add_section("Устройство")
	_add_row_select("Устройство вывода", "output_device",
		["Системное", "Наушники", "Колонки"])
	_add_row_select("Микрофон", "mic_device",
		["Системный", "Гарнитура"])

func _add_section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate.a = 0.5
	add_child(lbl)
	var sep := HSeparator.new()
	add_child(sep)

func _add_row(label: String, hint: String, key: String, type: SettingRow.RowType) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.hint_text   = hint
	row.setting_key = key
	row.row_type    = type
	add_child(row)

func _add_row_select(label: String, key: String, options: PackedStringArray) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text      = label
	row.setting_key     = key
	row.row_type        = SettingRow.RowType.SELECT
	row.select_options  = options
	add_child(row)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_build()
