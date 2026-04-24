# PageDisplay.gd
extends VBoxContainer

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	_configure_layout()
	_build()

func _build() -> void:
	_add_section(_t("Интерфейс", "Interface"))
	_add_row_select(_t("Язык", "Language"), "language", [_t("Русский", "Russian"), "English"])

	_add_section(_t("Окно", "Window"))
	_add_row_select(_t("Разрешение", "Resolution"), "resolution",
		["1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160"])
	_add_row_select(_t("Режим окна", "Window mode"), "window_mode",
		[_t("Оконный", "Windowed"), _t("Во весь экран", "Fullscreen"), _t("Эксклюзивный экран", "Exclusive fullscreen")])
	_add_row_select(_t("Ограничение FPS", "FPS limit"), "fps_limit",
		[_t("Без ограничения", "Unlimited"), "60", "120", "144"])
	_add_row("V-Sync", "", "vsync", SettingRow.RowType.TOGGLE)

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

func _add_row_select(label: String, key: String, options: PackedStringArray) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text     = label
	row.setting_key    = key
	row.row_type       = SettingRow.RowType.SELECT
	row.select_options = options
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
