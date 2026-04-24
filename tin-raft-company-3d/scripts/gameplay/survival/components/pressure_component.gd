extends RefCounted
class_name PressureComponent

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 100.0

var value: float = 100.0
var stabilization_per_second: float = 0.06
var leak_loss_per_second: float = 0.22

func tick(delta: float, has_hull_breach: bool) -> void:
	var delta_value := stabilization_per_second
	if has_hull_breach:
		delta_value -= leak_loss_per_second
	value = clampf(value + delta_value * delta, MIN_VALUE, MAX_VALUE)

func snapshot() -> float:
	return value
