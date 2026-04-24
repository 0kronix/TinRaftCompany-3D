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

func _add_section(title: String) -> void:
	var lbl := Label.new()
	lbl.text = title.to_upper()
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate.a = 0.5
	content.add_child(lbl)
	var sep := HSeparator.new()
	content.add_child(sep)

func _add_row(label: String, hint: String, key: String, type: SettingRow.RowType) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text  = label
	row.hint_text   = hint
	row.setting_key = key
	row.row_type    = type
	content.add_child(row)

func _add_row_select(label: String, key: String, options: PackedStringArray) -> void:
	var row := preload("res://scenes/ui/settings/components/SettingRow.tscn").instantiate()
	row.label_text      = label
	row.setting_key     = key
	row.row_type        = SettingRow.RowType.SELECT
	row.select_options  = options
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
