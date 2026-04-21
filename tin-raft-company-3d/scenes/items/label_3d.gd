extends Label3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _process(_delta):
	global_position = get_parent().global_position + Vector3(0, 0.5, 0)
