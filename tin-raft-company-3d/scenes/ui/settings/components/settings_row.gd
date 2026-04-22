# SettingRow.gd
class_name SettingRow
extends HBoxContainer

enum RowType { SLIDER, TOGGLE, SELECT, KEYBIND, INPUT_INT, INPUT_TEXT }

@export var row_type: RowType = RowType.SLIDER
@export var label_text: String = "Настройка"
@export var hint_text: String = ""
@export var setting_key: String = ""
@export var select_options: PackedStringArray = []
@export var slider_min: float = 0.0
@export var slider_max: float = 100.0

var _control: Control

func _ready() -> void:
	var label_col := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	label_col.add_child(lbl)

	if hint_text != "":
		var hint := Label.new()
		hint.text = hint_text
		hint.add_theme_font_size_override("font_size", 10)
		hint.modulate.a = 0.5
		label_col.add_child(hint)

	add_child(label_col)

	# Spacer
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(sp)

	_control = _build_control()
	add_child(_control)

func _build_control() -> Control:
	match row_type:
		RowType.SLIDER:
			return _build_slider()
		RowType.TOGGLE:
			return _build_toggle()
		RowType.SELECT:
			return _build_select()
		RowType.KEYBIND:
			return KeybindButton.new()
		RowType.INPUT_INT:
			return _build_spinbox()
		RowType.INPUT_TEXT:
			return _build_lineedit()
	return Control.new()

func _build_slider() -> HBoxContainer:
	var slider_row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = slider_min
	slider.max_value = slider_max
	slider.value = SettingsManager.data.get(setting_key, slider_max * 0.7)
	slider.custom_minimum_size.x = 160

	var val_label := Label.new()
	val_label.text = str(int(slider.value)) + "%"
	val_label.custom_minimum_size.x = 36

	slider.value_changed.connect(func(v):
		SettingsManager.data[setting_key] = v
		val_label.text = str(int(v)) + "%"
	)
	slider_row.add_child(slider)
	slider_row.add_child(val_label)
	return slider_row

func _build_toggle() -> CheckButton:
	var toggle := CheckButton.new()
	toggle.button_pressed = SettingsManager.data.get(setting_key, false)
	toggle.toggled.connect(func(v): SettingsManager.data[setting_key] = v)
	return toggle

func _build_select() -> OptionButton:
	var opt := OptionButton.new()
	for item in select_options:
		opt.add_item(item)
	opt.selected = SettingsManager.data.get(setting_key, 0)
	opt.item_selected.connect(func(i): SettingsManager.data[setting_key] = i)
	return opt

func _build_spinbox() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1024
	spin.max_value = 65535
	spin.value = SettingsManager.data.get(setting_key, 7777)
	spin.value_changed.connect(func(v): SettingsManager.data[setting_key] = int(v))
	return spin

func _build_lineedit() -> LineEdit:
	var edit := LineEdit.new()
	edit.text = SettingsManager.data.get(setting_key, "")
	edit.custom_minimum_size.x = 160
	edit.text_changed.connect(func(v): SettingsManager.data[setting_key] = v)
	return edit
