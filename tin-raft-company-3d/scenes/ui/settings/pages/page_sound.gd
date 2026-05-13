# PageSound.gd
extends VBoxContainer

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer

var _voice_players_container: VBoxContainer = null

func _ready() -> void:
	_configure_layout()
	_build()

func _build() -> void:
	_add_section(_t("Звук", "Sound"))
	_add_row(_t("Общая громкость", "Master volume"), "", "vol_master", SettingRow.RowType.SLIDER)
	_add_row(_t("Музыка", "Music"), _t("Ambient / саундтрек", "Ambient / soundtrack"), "vol_music", SettingRow.RowType.SLIDER)
	_add_row(_t("Эффекты", "SFX"), _t("Системы и механика", "Systems and mechanics"), "vol_sfx", SettingRow.RowType.SLIDER)
	_add_row(_t("EVA: джетпак", "EVA: jetpack"), _t("Космос, реактивная тяга", "Space, jet thrust"), "vol_eva_jetpack", SettingRow.RowType.SLIDER)
	_add_row(_t("Шаттл: двигатели", "Shuttle: engines"), _t("Основной и манёвровые в космосе", "Main and RCS in space"), "vol_shuttle_engines", SettingRow.RowType.SLIDER)

	# ── Голосовой чат ──────────────────────────────────────────
	_add_section(_t("Голосовой чат", "Voice chat"))

	_add_row_select(_t("Режим передачи", "Transmission mode"), "voice_mode",
		PackedStringArray([_t("Push-to-Talk", "Push-to-Talk"), _t("Активация по голосу (VOX)", "Voice activation (VOX)")]))

	_add_row(_t("Клавиша PTT", "PTT key"), "", "voice_ptt_key", SettingRow.RowType.KEYBIND)
	_add_row(_t("Клавиша Mute", "Mute key"), "", "voice_mute_key", SettingRow.RowType.KEYBIND)
	_add_row(_t("Громкость голоса", "Voice volume"), "", "voice_volume", SettingRow.RowType.SLIDER)
	
	var threshold_bar: Control = load("res://scenes/ui/settings/components/VoiceThresholdBar.gd").new()
	threshold_bar.name = "ThresholdBar"
	threshold_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(threshold_bar)

	_add_player_volumes_section()

func _add_section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate.a = 0.5
	content.add_child(lbl)
	var sep := HSeparator.new()
	content.add_child(sep)

func _add_row(label: String, hint: String, key: String, type: SettingRow.RowType,
		slider_min: float = 0.0, slider_max: float = 100.0) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.hint_text   = hint
	row.setting_key = key
	row.row_type    = type
	row.slider_min  = slider_min
	row.slider_max  = slider_max
	content.add_child(row)

func _add_row_select(label: String, key: String, options: PackedStringArray) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text      = label
	row.setting_key     = key
	row.row_type        = SettingRow.RowType.SELECT
	row.select_options  = options
	content.add_child(row)

func _add_player_volumes_section() -> void:
	# Если контейнер ещё не создан – создаём, подключаем сигналы и наполняем.
	if _voice_players_container == null:
		_voice_players_container = VBoxContainer.new()
		_voice_players_container.name = "VoicePlayersVolumes"
		content.add_child(_voice_players_container)

		var vm := get_node_or_null("/root/VoiceManager")
		if vm:
			if not vm.voice_player_added.is_connected(_on_voice_player_added):
				vm.voice_player_added.connect(_on_voice_player_added.bind(_voice_players_container))
			if not vm.voice_player_removed.is_connected(_on_voice_player_removed):
				vm.voice_player_removed.connect(_on_voice_player_removed.bind(_voice_players_container))

			# Добавляем уже существующие плееры
			for peer_id in vm.peer_voice_players:
				_on_voice_player_added(peer_id, _voice_players_container)
	else:
		# Контейнер существует – возможно, после refresh его нужно вернуть в content
		if _voice_players_container.get_parent() == null:
			content.add_child(_voice_players_container)

func _on_voice_player_added(peer_id: int, container: VBoxContainer) -> void:
	if container.get_node_or_null("PlayerVol_%d" % peer_id):
		return

	var row := HBoxContainer.new()
	row.name = "PlayerVol_%d" % peer_id

	var lbl := Label.new()
	lbl.text = "Игрок %d" % peer_id
	lbl.custom_minimum_size.x = 120
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = SettingsManager.data.get("voice_volume", 80.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float):
		var vm := get_node_or_null("/root/VoiceManager")
		if vm:
			vm.set_player_volume(peer_id, v / 100.0)
	)
	row.add_child(slider)
	container.add_child(row)
	print("Voice volume slider added for peer ", peer_id)

func _on_voice_player_removed(peer_id: int, container: VBoxContainer) -> void:
	var row := container.get_node_or_null("PlayerVol_%d" % peer_id)
	if row:
		row.queue_free()
		print("Voice volume slider removed for peer ", peer_id)

func refresh() -> void:
	# Сохраняем контейнер со слайдерами перед очисткой
	var saved_voice = _voice_players_container
	if saved_voice and saved_voice.get_parent() == content:
		content.remove_child(saved_voice)

	# Очищаем содержимое
	for child in content.get_children():
		child.queue_free()

	_build()

	# Возвращаем сохранённый контейнер, если он был
	if saved_voice:
		_voice_players_container = saved_voice
		if saved_voice.get_parent() == null:
			content.add_child(saved_voice)

func _configure_layout() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	$ScrollContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$ScrollContainer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)

func _t(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en
