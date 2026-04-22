# NavButton.gd
class_name NavButton
extends Button

@export var label_text: String = "Раздел"
@export var number: String = "01"

func _ready() -> void:
	toggle_mode = true
	text = label_text
	# стиль задаётся через Theme в инспекторе
	# или программно:
	_setup_style()

func _setup_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.border_width_left = 2
	normal.border_color = Color.TRANSPARENT
	add_theme_stylebox_override("normal", normal)

	var pressed_style := StyleBoxFlat.new()
	pressed_style .bg_color = Color(0, 1, 0.6, 0.05)
	pressed_style .border_width_left = 2
	pressed_style .border_color = Color(0, 1, 0.6)
	add_theme_stylebox_override("pressed", pressed_style )
	add_theme_stylebox_override("focus", pressed_style )
