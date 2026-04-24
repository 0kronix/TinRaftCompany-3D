extends RefCounted
class_name OxygenComponent

const MIN_VALUE: float = 0.0
const MAX_VALUE: float = 100.0

var value: float = 100.0
var base_drain_per_second: float = 0.08
var regen_per_second: float = 0.04

func tick(delta: float, has_leak: bool, emergency_mode: bool) -> void:
	var leak_factor := 2.0 if has_leak else 1.0
	var emergency_factor := 0.6 if emergency_mode else 1.0
	var drain := base_drain_per_second * leak_factor * emergency_factor
	var regen := regen_per_second if not has_leak else 0.0
	value = clampf(value - drain * delta + regen * delta, MIN_VALUE, MAX_VALUE)

func snapshot() -> float:
	return value
