# PageNetwork.gd
extends VBoxContainer

func _ready() -> void:
	_build()

func _build() -> void:
	_add_section("Соединение")
	_add_row_select("Режим подключения", "net_mode",
		["Steam P2P", "Прямой IP", "LAN"])
	_add_row("Порт сервера", "", "port", SettingRow.RowType.INPUT_INT)
	_add_row_select("Максимум игроков", "max_players",
		["2", "4"])

	_add_section("Голосовой чат")
	_add_row_select("Режим передачи", "voice_mode",
		["Push-to-talk", "Открытый микрофон", "Выключен"])
	_add_keybind("Кнопка рации (PTT)", "key_radio")
	_add_row("Порог активации", "Для открытого микрофона", "mic_threshold", SettingRow.RowType.SLIDER)
	_add_row("Подавление шума", "",                        "noise_suppress", SettingRow.RowType.TOGGLE)

	_add_section("Лобби")
	_add_row_select("Видимость", "lobby_visible",
		["Публичное", "Только друзья", "Приватное"])
	_add_row("Имя лобби", "", "lobby_name", SettingRow.RowType.INPUT_TEXT)
	_add_row_select("Регион", "region",
		["Авто", "Европа", "Сев. Америка", "Азия"])

	_add_section("Отладка")
	_add_row("Показывать пинг",  "",                      "show_ping", SettingRow.RowType.TOGGLE)
	_add_row("Лог синхронизации","Выводить RPC в консоль", "net_log",   SettingRow.RowType.TOGGLE)

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
