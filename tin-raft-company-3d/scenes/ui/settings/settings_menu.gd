# SettingsMenu.gd
class_name SettingsMenu
extends Control

@onready var page_sound    := $WindowPanel/VBoxContainer/Body/ContentContainer/PageStack/PageSound
@onready var page_display  := $WindowPanel/VBoxContainer/Body/ContentContainer/PageStack/PageDisplay
@onready var page_controls := $WindowPanel/VBoxContainer/Body/ContentContainer/PageStack/PageControls
@onready var page_network  := $WindowPanel/VBoxContainer/Body/ContentContainer/PageStack/PageNetwork

@onready var nav_sound    := $WindowPanel/VBoxContainer/Body/SideBar/NavButtonSound
@onready var nav_display  := $WindowPanel/VBoxContainer/Body/SideBar/NavButtonDisplay
@onready var nav_controls := $WindowPanel/VBoxContainer/Body/SideBar/NavButtonControls
@onready var nav_network  := $WindowPanel/VBoxContainer/Body/SideBar/NavButtonNetwork

@onready var btn_apply := $WindowPanel/VBoxContainer/Footer/HBoxContainer/BtnApply
@onready var btn_reset := $WindowPanel/VBoxContainer/Footer/HBoxContainer/BtnReset
@onready var btn_exit  := $WindowPanel/VBoxContainer/Footer/BtnExitToMenu
@onready var title_label: Label = $WindowPanel/VBoxContainer/Header/VBoxContainer/Tittle

var all_pages: Array[Control]
var all_nav: Array[Button]
var current_page: int = 0

func _ready() -> void:
	add_to_group("settings_menu")
	_apply_theme()
	get_tree().root.size_changed.connect(_resize)
	_resize()
	all_pages = [page_sound, page_display, page_controls, page_network]
	all_nav   = [nav_sound, nav_display, nav_controls, nav_network]
	for page in all_pages:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.offset_left = 0
		page.offset_top = 0
		page.offset_right = 0
		page.offset_bottom = 0

	nav_sound.pressed.connect(func(): _switch_page(0))
	nav_display.pressed.connect(func(): _switch_page(1))
	nav_controls.pressed.connect(func(): _switch_page(2))
	nav_network.pressed.connect(func(): _switch_page(3))

	btn_apply.pressed.connect(_apply_settings)
	btn_reset.pressed.connect(_reset_settings)
	btn_exit.pressed.connect(_exit_to_lobby)
	SettingsManager.settings_applied.connect(_on_settings_applied)

	_refresh_texts()
	_switch_page(0)

func _switch_page(index: int) -> void:
	current_page = index
	for i in all_pages.size():
		all_pages[i].visible = (i == index)
		all_nav[i].button_pressed = (i == index)
		all_nav[i].alignment = HORIZONTAL_ALIGNMENT_LEFT

func _apply_settings() -> void:
	SettingsManager.save()
	_refresh_all_pages()

func _reset_settings() -> void:
	SettingsManager.reset_to_defaults()
	SettingsManager.save()
	_refresh_all_pages()

func _refresh_all_pages() -> void:
	for page in all_pages:
		if page.has_method("refresh"):
			page.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		visible = false

func show_menu() -> void:
	visible = true
	modulate.a = 0.0
	$WindowPanel.scale = Vector2(0.96, 0.96)
	
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property($WindowPanel, "scale", Vector2.ONE, 0.15)\
		 .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_menu() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_property($WindowPanel, "scale", Vector2(0.96, 0.96), 0.1)
	await tween.finished
	visible = false

func _resize() -> void:
	var screen := get_viewport().get_visible_rect().size
	var panel := $WindowPanel
	var w := clampf(screen.x * 0.62, 820.0, 1120.0)
	var h := clampf(screen.y * 0.78, 560.0, 820.0)
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)
	panel.position = (screen - panel.size) / 2.0
	
	# Сайдбар фиксированной ширины для симметрии и ровных кликов.
	var sidebar := $WindowPanel/VBoxContainer/Body/SideBar
	sidebar.custom_minimum_size.x = 220

func _exit_to_lobby() -> void:
	if NetworkManager.is_session_active():
		NetworkManager.leave()
	get_tree().change_scene_to_file("res://scenes/network/lobby.tscn")

func _refresh_texts() -> void:
	title_label.text = _t("Настройки", "Settings")
	nav_sound.text = _t("Звук", "Sound")
	nav_display.text = _t("Экран", "Display")
	nav_controls.text = _t("Управление", "Controls")
	nav_network.text = _t("Сеть", "Network")
	btn_apply.text = _t("Применить", "Apply")
	btn_reset.text = _t("Сброс", "Reset")
	btn_exit.text = _t("Выйти в меню", "Exit to Lobby")

func _on_settings_applied() -> void:
	_refresh_texts()
	_refresh_all_pages()

func _t(ru: String, en: String) -> String:
	return ru if TranslationServer.get_locale().begins_with("ru") else en

func _apply_theme() -> void:
	var ui_theme := Theme.new()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.1, 0.96)
	panel_style.border_color = Color(0.16, 0.19, 0.24, 1.0)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 18
	panel_style.content_margin_top = 16
	panel_style.content_margin_right = 18
	panel_style.content_margin_bottom = 14
	ui_theme.set_stylebox("panel", "PanelContainer", panel_style)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.12, 0.14, 0.18, 1.0)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.content_margin_left = 12
	btn_normal.content_margin_top = 7
	btn_normal.content_margin_right = 12
	btn_normal.content_margin_bottom = 7
	ui_theme.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.17, 0.2, 0.26, 1.0)
	ui_theme.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.18, 0.36, 0.3, 1.0)
	ui_theme.set_stylebox("pressed", "Button", btn_pressed)
	ui_theme.set_stylebox("focus", "Button", btn_hover)
	ui_theme.set_color("font_color", "Button", Color(0.92, 0.95, 1.0))

	var nav_normal := btn_normal.duplicate()
	nav_normal.bg_color = Color(0.1, 0.12, 0.16, 1.0)
	ui_theme.set_stylebox("normal", "NavButton", nav_normal)
	ui_theme.set_stylebox("hover", "NavButton", btn_hover)
	ui_theme.set_stylebox("focus", "NavButton", btn_hover)
	ui_theme.set_stylebox("pressed", "NavButton", btn_pressed)
	ui_theme.set_color("font_color", "NavButton", Color(0.9, 0.94, 1.0))

	ui_theme.set_constant("separation", "VBoxContainer", 10)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	ui_theme.set_font_size("font_size", "Label", 14)
	ui_theme.set_font_size("font_size", "Button", 14)

	self.theme = ui_theme
