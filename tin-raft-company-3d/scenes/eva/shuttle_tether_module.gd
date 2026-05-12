extends StaticBody3D
## Точка крепления кабеля к шаттлу: E — привязка / отвязка (только EVA).
## Параметры кабеля правятся здесь; при подключении копируются на персонажа.

@export_group("Кабель")
## Нижняя граница выпущенной длины (м); при подключении трос начинает с неё.
@export var tether_length_min: float = 5.0
## Верхняя граница выпущенной длины (м); игрок разматывает до этого предела (X / Z).
@export var tether_max_length: float = 34.0
## Шаг изменения длины по X / Z (м).
@export var tether_length_step: float = 0.75
## Доля длины без натяжения (0–0.45): выше — мягче «резинка» до упора.
@export_range(0.0, 0.45, 0.01) var tether_slack_ratio: float = 0.14
## Жёсткость пружины (чем больше — сильнее тянет к шаттлу при растяжении).
@export var tether_spring: float = 95.0
## Демпфирование вдоль троса (меньше дёрганий).
@export var tether_damping: float = 8.0
@export var tether_cable_radius: float = 0.038
@export_range(4, 32, 1) var tether_rope_segments: int = 18
## Радиус сферы столкновения узла верёвки (чуть больше визуального радиуса).
@export var tether_rope_collision_radius: float = 0.065
## Битмаска слоёв (как у CollisionObject): 1 — типичный мир/астероиды, 1<<10 — слой 11 (статика интерьера шаттла).
@export var tether_rope_collision_mask: int = 1025

@onready var label: Label3D = $Label3D
@onready var cable_anchor: Marker3D = $CableAnchor


func _ready() -> void:
	label.text = _hint_text()
	Label3DHint.prepare_hidden(label)


func _hint_text() -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		return "Кабель шаттла (E)"
	return "Shuttle tether (E)"


func show_hint() -> void:
	Label3DHint.tween_show(self, label)


func hide_hint() -> void:
	Label3DHint.tween_hide(self, label)


func interact(caller: Node3D) -> void:
	var command := build_interaction_command()
	NetworkManager.request_command(caller, command)


func build_interaction_command() -> Dictionary:
	return {
		"type": "shuttle_tether_toggle",
		"target_path": get_path()
	}


func server_validate_interaction(_actor: Node3D) -> bool:
	return true


func server_apply_interaction(_actor: Node3D, _command: Dictionary = {}) -> bool:
	return true


func get_tether_parameters() -> Dictionary:
	return {
		"length_min": tether_length_min,
		"length_max": tether_max_length,
		"length_step": tether_length_step,
		"max_length": tether_max_length,
		"slack_ratio": tether_slack_ratio,
		"spring": tether_spring,
		"damping": tether_damping,
		"cable_radius": tether_cable_radius,
		"rope_segments": tether_rope_segments,
		"rope_collision_radius": tether_rope_collision_radius,
		"rope_collision_mask": tether_rope_collision_mask,
	}
