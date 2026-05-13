extends Node
class_name CapsuleStateService

const SNAPSHOT_EMIT_INTERVAL: float = 0.2

signal state_changed(snapshot: Dictionary)
signal critical_state_entered(metric: String, value: float)

const OxygenComponentScript := preload("res://scripts/gameplay/survival/components/oxygen_component.gd")
const PressureComponentScript := preload("res://scripts/gameplay/survival/components/pressure_component.gd")
const TemperatureComponentScript := preload("res://scripts/gameplay/survival/components/temperature_component.gd")
const PowerComponentScript := preload("res://scripts/gameplay/survival/components/power_component.gd")

const SHIP_OXYGEN_RESERVE_MAX: float = 100.0

var oxygen: OxygenComponent
var pressure: PressureComponent
var temperature: TemperatureComponent
var power: PowerComponent
var ship_oxygen_reserve: float = SHIP_OXYGEN_RESERVE_MAX
var ship_oxygen_reserve_max: float = SHIP_OXYGEN_RESERVE_MAX

var _has_hull_breach: bool = false
var _heavy_load: bool = false
var _emergency_mode: bool = false
var _anomaly_level: float = 0.0
var _emit_timer: float = 0.0
var _last_snapshot: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process(true)
	_init_components()
	_emit_snapshot(true)

func _physics_process(delta: float) -> void:
	power.tick(delta, _heavy_load)
	pressure.tick(delta, _has_hull_breach)
	oxygen.tick(delta, _has_hull_breach, _emergency_mode)
	temperature.tick(delta, power.has_energy(), _anomaly_level)

	_emit_timer += delta
	if _emit_timer >= SNAPSHOT_EMIT_INTERVAL:
		_emit_timer = 0.0
		_emit_snapshot(false)

func set_hull_breach(enabled: bool) -> void:
	_has_hull_breach = enabled

func set_heavy_load(enabled: bool) -> void:
	_heavy_load = enabled

func set_emergency_mode(enabled: bool) -> void:
	_emergency_mode = enabled

func set_anomaly_level(level: float) -> void:
	_anomaly_level = clampf(level, -1.0, 1.0)

func get_snapshot() -> Dictionary:
	return _build_snapshot()


func consume_ship_oxygen(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var granted := minf(amount, ship_oxygen_reserve)
	ship_oxygen_reserve = maxf(0.0, ship_oxygen_reserve - granted)
	if granted > 0.0:
		_emit_snapshot(true)
	return granted


func set_ship_oxygen_reserve(current: float, max_value: float = SHIP_OXYGEN_RESERVE_MAX) -> void:
	ship_oxygen_reserve_max = maxf(max_value, 1.0)
	ship_oxygen_reserve = clampf(current, 0.0, ship_oxygen_reserve_max)
	_emit_snapshot(true)

func _init_components() -> void:
	oxygen = OxygenComponentScript.new()
	pressure = PressureComponentScript.new()
	temperature = TemperatureComponentScript.new()
	power = PowerComponentScript.new()

func _emit_snapshot(force: bool) -> void:
	var snapshot := _build_snapshot()
	if force or snapshot != _last_snapshot:
		_last_snapshot = snapshot
		state_changed.emit(snapshot)
		_check_critical(snapshot)

func _build_snapshot() -> Dictionary:
	var reserve_percent := ship_oxygen_reserve / ship_oxygen_reserve_max * 100.0
	return {
		"oxygen": oxygen.snapshot(),
		"ship_oxygen_reserve": ship_oxygen_reserve,
		"ship_oxygen_reserve_max": ship_oxygen_reserve_max,
		"ship_oxygen_reserve_percent": reserve_percent,
		"pressure": pressure.snapshot(),
		"temperature": temperature.snapshot(),
		"power": power.snapshot(),
		"hull_breach": _has_hull_breach,
		"heavy_load": _heavy_load,
		"emergency_mode": _emergency_mode,
		"anomaly_level": _anomaly_level
	}

func _check_critical(snapshot: Dictionary) -> void:
	if snapshot["oxygen"] <= 20.0:
		critical_state_entered.emit("oxygen", snapshot["oxygen"])
	if float(snapshot.get("ship_oxygen_reserve_percent", 100.0)) <= 20.0:
		critical_state_entered.emit("ship_oxygen_reserve", snapshot["ship_oxygen_reserve"])
	if snapshot["pressure"] <= 25.0:
		critical_state_entered.emit("pressure", snapshot["pressure"])
	if snapshot["power"] <= 15.0:
		critical_state_entered.emit("power", snapshot["power"])
