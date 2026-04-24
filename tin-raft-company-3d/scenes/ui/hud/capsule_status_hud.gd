extends VBoxContainer

@onready var oxygen_value: Label = $OxygenValue
@onready var pressure_value: Label = $PressureValue
@onready var temperature_value: Label = $TemperatureValue
@onready var power_value: Label = $PowerValue
@onready var status_value: Label = $StatusValue

var _capsule_state_service: Node = null

func _ready() -> void:
	_capsule_state_service = get_node_or_null("/root/GameServices/CapsuleStateService")
	if _capsule_state_service == null:
		return

	_capsule_state_service.state_changed.connect(_on_state_changed)
	_on_state_changed(_capsule_state_service.get_snapshot())

func _on_state_changed(snapshot: Dictionary) -> void:
	oxygen_value.text = "O2: %.1f%%" % float(snapshot.get("oxygen", 0.0))
	pressure_value.text = "P: %.1f%%" % float(snapshot.get("pressure", 0.0))
	temperature_value.text = "T: %.1fC" % float(snapshot.get("temperature", 0.0))
	power_value.text = "E: %.1f%%" % float(snapshot.get("power", 0.0))

	if bool(snapshot.get("hull_breach", false)):
		status_value.text = "Состояние: РАЗГЕРМЕТИЗАЦИЯ"
	elif bool(snapshot.get("emergency_mode", false)):
		status_value.text = "Состояние: АВАРИЙНЫЙ РЕЖИМ"
	else:
		status_value.text = "Состояние: НОРМА"
