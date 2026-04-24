# PageNetwork.gd
extends VBoxContainer

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	_configure_layout()
	_build()

func _build() -> void:
	_add_section(_t("Сессия", "Session"))
	_add_row_select(_t("Режим подключения", "Connection mode"), "net_mode",
		["P2P", "Direct IP", "LAN"])
	_add_row(_t("Порт сервера", "Server port"), "", "port", SettingRow.RowType.INPUT_INT)
	_add_row_select(_t("Максимум игроков", "Max players"), "max_players", ["2", "4"])

	_add_section(_t("Отладка", "Debug"))
	_add_row(_t("Показывать пинг", "Show ping"), "", "show_ping", SettingRow.RowType.TOGGLE)
	_add_row(_t("Лог сети", "Network log"), _t("Вывод RPC в консоль", "Print RPC in console"), "net_log", SettingRow.RowType.TOGGLE)

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
