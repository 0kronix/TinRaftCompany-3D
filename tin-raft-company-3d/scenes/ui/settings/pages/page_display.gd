# PageDisplay.gd
extends VBoxContainer

func _ready() -> void:
	_build()

func _build() -> void:
	_add_section("Разрешение и окно")
	_add_row_select("Разрешение", "resolution",
		["1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160"])
	_add_row_select("Режим окна", "window_mode",
		["Полноэкранный", "Оконный", "Без рамки"])
	_add_row_select("Частота обновления", "fps_limit",
		["Без ограничения", "60 Гц", "120 Гц", "144 Гц"])
	_add_row("V-Sync", "", "vsync", SettingRow.RowType.TOGGLE)

	_add_section("Графика")
	_add_row_select("Качество графики", "quality",
		["Низкое", "Среднее", "Высокое", "Ультра"])
	_add_row_select("Сглаживание", "aa_mode",
		["Выкл", "FXAA", "TAA", "MSAA 4x"])
	_add_row("Дальность обзора", "", "view_distance", SettingRow.RowType.SLIDER)

	_add_section("Атмосфера")
	_add_row("CRT-эффект",             "Сканлайны и свечение",    "crt_intensity", SettingRow.RowType.SLIDER)
	_add_row("Хроматическая аберрация","",                        "aberration",    SettingRow.RowType.SLIDER)
	_add_row("Виньетка",               "",                        "vignette",      SettingRow.RowType.TOGGLE)
	_add_row("Визуальные галлюцинации","Искажения при гипоксии",  "halluc_visual", SettingRow.RowType.TOGGLE)

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

func _add_row_select(label: String, key: String, options: PackedStringArray) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text     = label
	row.setting_key    = key
	row.row_type       = SettingRow.RowType.SELECT
	row.select_options = options
	add_child(row)

func refresh() -> void:
	for child in get_children():
		child.queue_free()
	_build()
