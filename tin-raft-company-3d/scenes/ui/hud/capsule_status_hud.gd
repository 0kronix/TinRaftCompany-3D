extends VBoxContainer

@onready var health_value: Label = $HealthValue
@onready var oxygen_value: Label = $OxygenValue
@onready var oxygen_reserve_value: Label = $OxygenReserveValue
@onready var pressure_value: Label = $PressureValue

var _capsule_state_service: Node = null
var _local_player: Node = null

func _ready() -> void:
	_capsule_state_service = get_node_or_null("/root/GameServices/CapsuleStateService")
	if _capsule_state_service != null:
		_capsule_state_service.state_changed.connect(_on_state_changed)
		_on_state_changed(_capsule_state_service.get_snapshot())
	_resolve_local_player()
	set_process(true)


func _process(_delta: float) -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		_resolve_local_player()
	_update_player_vitals()

func _on_state_changed(snapshot: Dictionary) -> void:
	oxygen_reserve_value.text = "O2 запас: %.1f%%" % float(snapshot.get("ship_oxygen_reserve_percent", 0.0))


func _resolve_local_player() -> void:
	var parent_node := get_parent()
	if parent_node != null:
		var maybe_player := parent_node.get_parent()
		if maybe_player != null and maybe_player.has_method("get_vitals_snapshot"):
			_local_player = maybe_player
			return
	_local_player = LocalPlayerFinder.authority_player(get_tree())


func _update_player_vitals() -> void:
	if _local_player == null or not _local_player.has_method("get_vitals_snapshot"):
		health_value.text = "Здоровье: --"
		oxygen_value.text = "O2 игрока: --"
		pressure_value.text = "Давление: --"
		return
	var snapshot: Dictionary = _local_player.get_vitals_snapshot()
	health_value.text = "Здоровье: %.1f%%" % float(snapshot.get("health", 0.0))
	oxygen_value.text = "O2 игрока: %.1f%%" % float(snapshot.get("oxygen", 0.0))
	pressure_value.text = "Давление: %.1f%%" % float(snapshot.get("pressure", 0.0))
