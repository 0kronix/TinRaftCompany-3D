extends RefCounted
class_name Label3DHint
## Подсветка подсказки на Label3D (Tween) — единые тайминги, меньше копипаста.


static func prepare_hidden(label: Label3D) -> void:
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)


static func tween_show(owner: Node, label: Label3D, fade_in_seconds: float = 0.15) -> void:
	var tween := owner.create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, fade_in_seconds)
	tween.tween_property(label, "outline_modulate:a", 1.0, fade_in_seconds)


static func tween_hide(owner: Node, label: Label3D, fade_out_seconds: float = 0.1) -> void:
	var tween := owner.create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, fade_out_seconds)
	tween.tween_property(label, "outline_modulate:a", 0.0, fade_out_seconds)
