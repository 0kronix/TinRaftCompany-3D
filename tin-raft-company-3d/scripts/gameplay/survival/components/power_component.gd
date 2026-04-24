extends RefCounted
class_name PowerComponent

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 100.0

var value: float = 100.0
var passive_drain_per_second: float = 0.05
var repair_system_cost_per_second: float = 0.08
var recharge_per_second: float = 0.04

func tick(delta: float, heavy_load: bool) -> void:
	var load := passive_drain_per_second + (repair_system_cost_per_second if heavy_load else 0.0)
	var recharge := recharge_per_second if not heavy_load else 0.0
	value = clampf(value - load * delta + recharge * delta, MIN_VALUE, MAX_VALUE)

func has_energy() -> bool:
	return value > 5.0

func snapshot() -> float:
	return value
