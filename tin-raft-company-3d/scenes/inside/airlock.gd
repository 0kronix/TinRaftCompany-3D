extends StaticBody3D

## Шлюз: выход в сцену EVA или возврат в капсулу.
## Смена сцены (одиночная игра или хост без других подключённых): см. NetworkManager.
## Пока в сессии 2+ игроков, шлюз не открывается (смена main↔space ломала бы пиров).

enum AirlockMode { TO_SPACE, TO_CAPSULE }

@export var mode: AirlockMode = AirlockMode.TO_SPACE

@onready var label: Label3D = $Label3D


func _ready() -> void:
	label.text = _label_text()
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)


func _label_text() -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		return "Шлюз: EVA" if mode == AirlockMode.TO_SPACE else "К капсуле"
	return "EVA" if mode == AirlockMode.TO_SPACE else "To capsule"


func show_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)


func hide_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)


func interact(caller: Node3D) -> void:
	var command := build_interaction_command()
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.request_command(caller, command)


func build_interaction_command() -> Dictionary:
	return {
		"type":        "airlock_exit" if mode == AirlockMode.TO_SPACE else "airlock_return",
		"target_path": get_path()
	}


func _player_container() -> Node:
	var p := "Inside/PlayerContainer" if mode == AirlockMode.TO_SPACE else "Space/PlayerContainer"
	return get_tree().root.get_node_or_null(p)


func _other_players_present() -> bool:
	var pc := _player_container()
	return pc != null and pc.get_child_count() > 1


func server_validate_interaction(_actor: Node3D) -> bool:
	if _other_players_present():
		return false
	return true


func server_apply_interaction(_actor: Node3D) -> bool:
	return true
