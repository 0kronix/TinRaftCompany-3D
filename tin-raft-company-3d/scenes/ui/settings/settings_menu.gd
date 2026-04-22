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

var all_pages: Array[Control]
var all_nav: Array[Button]
var current_page: int = 0

func _ready() -> void:
	add_to_group("settings_menu")
	get_tree().root.size_changed.connect(_resize)
	_resize()
	all_pages = [page_sound, page_display, page_controls, page_network]
	all_nav   = [nav_sound, nav_display, nav_controls, nav_network]

	nav_sound.pressed.connect(func(): _switch_page(0))
	nav_display.pressed.connect(func(): _switch_page(1))
	nav_controls.pressed.connect(func(): _switch_page(2))
	nav_network.pressed.connect(func(): _switch_page(3))

	btn_apply.pressed.connect(_apply_settings)
	btn_reset.pressed.connect(_reset_settings)

	_switch_page(0)

func _switch_page(index: int) -> void:
	current_page = index
	for i in all_pages.size():
		all_pages[i].visible = (i == index)
		all_nav[i].button_pressed = (i == index)

func _apply_settings() -> void:
	SettingsManager.save()

func _reset_settings() -> void:
	SettingsManager.reset_to_defaults()
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
	var w := screen.x * 0.40
	var h := screen.y * 0.65
	panel.custom_minimum_size = Vector2(w, h)
	panel.size = Vector2(w, h)
	panel.position = (screen - panel.size) / 2.0
	
	# сайдбар = 1/4 ширины окна
	var sidebar := $WindowPanel/VBoxContainer/Body/SideBar
	sidebar.custom_minimum_size.x = w * 0.15
