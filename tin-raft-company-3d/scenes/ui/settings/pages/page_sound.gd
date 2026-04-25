# PageSound.gd
extends VBoxContainer

@onready var content: VBoxContainer = $ScrollContainer/VBoxContainer

func _ready() -> void:
	_configure_layout()
	_build()

func _build() -> void:
	_add_section(_t("Звук", "Sound"))
	_add_row(_t("Общая громкость", "Master volume"), "", "vol_master", SettingRow.RowType.SLIDER)
	_add_row(_t("Музыка", "Music"), _t("Ambient / саундтрек", "Ambient / soundtrack"), "vol_music", SettingRow.RowType.SLIDER)
	_add_row(_t("Эффекты", "SFX"), _t("Системы и механика", "Systems and mechanics"), "vol_sfx", SettingRow.RowType.SLIDER)

	# ── Голосовой чат ──────────────────────────────────────────
	_add_section(_t("Голосовой чат", "Voice chat"))

	_add_row_select(_t("Режим передачи", "Transmission mode"), "voice_mode",
		PackedStringArray([_t("Push-to-Talk", "Push-to-Talk"), _t("Активация по голосу (VOX)", "Voice activation (VOX)")]))

	_add_row(_t("Клавиша PTT", "PTT key"), "", "voice_ptt_key", SettingRow.RowType.KEYBIND)
	_add_row(_t("Клавиша Mute", "Mute key"), "", "voice_mute_key", SettingRow.RowType.KEYBIND)
	_add_row(_t("Громкость голоса", "Voice volume"), "", "voice_volume", SettingRow.RowType.SLIDER)
	_add_row(_t("Порог VOX", "VOX threshold"), "", "mic_threshold", SettingRow.RowType.SLIDER, 0.5, 30.0)

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
	var players_vbox := VBoxContainer.new()
	players_vbox.name = "VoicePlayersVolumes"
	content.add_child(players_vbox)

	# Подключаемся к сигналам напрямую через NetworkManager
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		if not nm.player_joined.is_connected(_on_player_joined_voice):
			nm.player_joined.connect(_on_player_joined_voice.bind(players_vbox))
		if not nm.player_left.is_connected(_on_player_left_voice):
			nm.player_left.connect(_on_player_left_voice.bind(players_vbox))

func _on_player_joined_voice(peer_id: int, container: VBoxContainer) -> void:
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

func _on_player_left_voice(peer_id: int, container: VBoxContainer) -> void:
	var row := container.get_node_or_null("PlayerVol_%d" % peer_id)
	if row:
		row.queue_free()
		print("Voice volume slider removed for peer ", peer_id)

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
