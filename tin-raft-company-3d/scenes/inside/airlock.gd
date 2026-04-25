extends StaticBody3D

## Шлюз: телепорт в зону EVA (узел EVA в main) или обратно к капсуле.
## Капсула и открытый космос в одной сцене — мультиплеер: каждый peer сам телепортирует своего игрока (RPC).

enum AirlockMode { TO_SPACE, TO_CAPSULE }

@export var mode: AirlockMode = AirlockMode.TO_SPACE

@onready var label: Label3D = $Label3D


func _ready() -> void:
	label.text = _label_text()
	label.modulate = Color(1, 1, 1, 0)
	label.outline_modulate = Color(0, 0, 0, 0)


func _label_text() -> String:
	if TranslationServer.get_locale().begins_with("ru"):
		if mode == AirlockMode.TO_SPACE:
			return "Шлюз: выход в космос"
		return "В корабль (капсулу)"
	return "Airlock: EVA" if mode == AirlockMode.TO_SPACE else "Enter ship"


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


func server_validate_interaction(_actor: Node3D) -> bool:
	return true


func server_apply_interaction(_actor: Node3D) -> bool:
	return true
