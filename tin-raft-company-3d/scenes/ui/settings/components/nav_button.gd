# NavButton.gd
class_name NavButton
extends Button

@export var label_text: String = "Раздел"

func _ready() -> void:
	toggle_mode = true
	text = label_text
