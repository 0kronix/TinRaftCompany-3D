extends RefCounted
class_name TemperatureComponent

const MIN_VALUE: float = -100.0
const MAX_VALUE: float = 120.0
const TARGET_COMFORT_TEMP: float = 21.0

var value: float = TARGET_COMFORT_TEMP
var correction_per_second: float = 0.8
var anomaly_force_per_second: float = 1.6

func tick(delta: float, has_energy: bool, anomaly_level: float) -> void:
	var energy_factor := 1.0 if has_energy else 0.2
	var comfort_delta := (TARGET_COMFORT_TEMP - value) * correction_per_second * energy_factor
	var anomaly_delta := anomaly_force_per_second * anomaly_level
	value = clampf(value + (comfort_delta + anomaly_delta) * delta, MIN_VALUE, MAX_VALUE)

func snapshot() -> float:
	return value
