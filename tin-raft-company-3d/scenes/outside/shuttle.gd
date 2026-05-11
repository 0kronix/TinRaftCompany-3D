extends NetworkReplicatedRigidBody

## Слой для дочерних StaticBody (шлюз и т.п.): они не должны сталкиваться с коллайдером корпуса,
## иначе Jolt каждый кадр резолвит «сам с собой» и скорость рвётся после отпускания тяги.
const INTERIOR_STATIC_LAYER: int = 11

# ── Настройки ──────────────────────────────────────────────
@export var thruster_force: float = 0.1
@export var main_thruster_force: float = 5.0  # Сила основного двигателя
@export var debug_draw: bool = false  # DebugDraw3D на все маркеры — тяжёло для Process; вкл. в инспекторе при отладке
@export var debug_force_scale: float = 0.05

# ── Направления тяги (локальные координаты корабля) ────────
const THRUSTER_DIRS: Dictionary = {
	"Pitch_T1": Vector3(0, -1, 0),
	"Pitch_T2": Vector3(0, 1, 0),
	"Pitch_T3": Vector3(0, -1, 0),
	"Pitch_T4": Vector3( 0, 1, 0),
	"Yaw_T5":   Vector3( 0, 0, 1),
	"Yaw_T6":   Vector3( 0, 0, -1),
	"Yaw_T7":   Vector3( 0, 0, 1),
	"Yaw_T8":   Vector3( 0, 0, -1),
	"Roll_T9":  Vector3( 0,  1, 0),
	"Roll_T10": Vector3( 0, -1, 0),
	"Roll_T11": Vector3( 0,  1, 0),
	"Roll_T12": Vector3( 0, -1, 0),
}

# ── Группы двигателей для каждого манёвра ──────────────────
const MANEUVER_THRUSTERS: Dictionary = {
	"pitch_up":    ["Pitch_T1", "Pitch_T4"],
	"pitch_down":  ["Pitch_T2", "Pitch_T3"],
	"yaw_left":    ["Yaw_T5",   "Yaw_T8"],
	"yaw_right":   ["Yaw_T6",   "Yaw_T7"],
	"roll_right":  ["Roll_T9",  "Roll_T12"],
	"roll_left":   ["Roll_T10", "Roll_T11"],
}

# ── Состояние активных двигателей (для дебага) ─────────────
var _active_thrusters: Dictionary = {}
var _thrusters: Dictionary = {}

# ── Мультиплеер: authority всегда 1 (сервер) — пилот задаётся отдельно, ввод с клиента по RPC. ──
## 0 = нет; 1 = хост; иначе peer_id пилота (открыл/нажал «слот» на штурвале).
@export var pilot_peer_id: int = 0
## Последняя пачка ввода с пилотского клиента (только несётся на сервер).
var _pilot_input_bits: int = 0
## Обновляется перед интеграцией; силы крутятся только из `_integrate_forces` (Jolt/FPS-стабильно).
var _thruster_bits: int = 0

# ── Основной двигатель ─────────────────────────────────────
var _main_thruster: Marker3D = null
var _main_thruster_active: bool = false


func _ready() -> void:
	## Корпус симулировать отдельно от иерархии EVA (иначе возможны паразитные связи трансформа).
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	## Космос: без сопротивления среды; на Jolt нужно явно обнулить damp (см. asteroid_data.gd).
	can_sleep = false
	linear_damp = 0.0
	angular_damp = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	for marker in $Thrusters.get_children():
		if marker is Marker3D:
			if marker.name == "Main_Engine":
				_main_thruster = marker
			else:
				_thrusters[marker.name] = marker
				_active_thrusters[marker.name] = false

	_exclude_interior_static_vs_hull()


func _exclude_interior_static_vs_hull() -> void:
	set_collision_mask_value(INTERIOR_STATIC_LAYER, false)
	for c in get_children():
		if c is StaticBody3D:
			var sb: StaticBody3D = c as StaticBody3D
			sb.collision_layer = 0
			sb.set_collision_layer_value(INTERIOR_STATIC_LAYER, true)


func _network_simulate_authority(_delta: float) -> void:
	_thruster_bits = _resolve_thruster_bits()


func _resolve_thruster_bits() -> int:
	if _is_offline():
		return _pack_input_from_keyboard()
	if is_multiplayer_authority():
		if pilot_peer_id == 0:
			return 0
		if pilot_peer_id == 1:
			return _pack_input_from_keyboard()
		return _pilot_input_bits
	return 0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if MultiplayerRuntime.has_active_session_for(self) and not is_multiplayer_authority():
		return
	if freeze:
		return
	for key in _active_thrusters:
		_active_thrusters[key] = false
	_main_thruster_active = false
	_apply_thruster_bits_state(state, _thruster_bits)


# ── Основной двигатель: толкает вперёд из центра кормы ─────
func _fire_main_engine_state(state: PhysicsDirectBodyState3D) -> void:
	if _main_thruster == null:
		push_warning("Main_Engine marker not found in Thrusters!")
		return

	var world_force: Vector3 = state.transform.basis * Vector3(0, 0, -1) * main_thruster_force
	var offset: Vector3 = _main_thruster.global_position - global_position

	state.apply_force(world_force, offset)
	_main_thruster_active = true


func _fire_maneuver_state(state: PhysicsDirectBodyState3D, maneuver: String) -> void:
	for thruster_name in MANEUVER_THRUSTERS[maneuver]:
		_apply_thruster_state(state, thruster_name, thruster_force)


func _apply_thruster_state(state: PhysicsDirectBodyState3D, thruster_name: String, force: float) -> void:
	if not _thrusters.has(thruster_name):
		push_warning("Thruster not found: " + thruster_name)
		return

	var marker: Marker3D = _thrusters[thruster_name]
	var local_dir: Vector3 = THRUSTER_DIRS[thruster_name]

	var world_force: Vector3 = state.transform.basis * (local_dir * force)
	var offset: Vector3 = marker.global_position - global_position

	state.apply_force(world_force, offset)
	_active_thrusters[thruster_name] = true


func _is_offline() -> bool:
	var p: MultiplayerPeer = multiplayer.multiplayer_peer
	return p == null or p is OfflineMultiplayerPeer


func _pack_input_from_keyboard() -> int:
	var b: int = 0
	if Input.is_action_pressed("jump"):
		b |= 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		b |= 2
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		b |= 4
	if Input.is_key_pressed(KEY_A):
		b |= 8
	if Input.is_key_pressed(KEY_D):
		b |= 16
	if Input.is_key_pressed(KEY_Q):
		b |= 32
	if Input.is_key_pressed(KEY_R):
		b |= 64
	return b


func _apply_thruster_bits_state(state: PhysicsDirectBodyState3D, bits: int) -> void:
	if bits & 1:
		_fire_main_engine_state(state)
	if bits & 2:
		_fire_maneuver_state(state, "pitch_up")
	if bits & 4:
		_fire_maneuver_state(state, "pitch_down")
	if bits & 8:
		_fire_maneuver_state(state, "yaw_left")
	if bits & 16:
		_fire_maneuver_state(state, "yaw_right")
	if bits & 32:
		_fire_maneuver_state(state, "roll_left")
	if bits & 64:
		_fire_maneuver_state(state, "roll_right")


func apply_pilot_input_bits(bits: int) -> void:
	_pilot_input_bits = bits


func _process(_delta: float) -> void:
	var _wp0: int = Time.get_ticks_usec() if WalkPerfProbe.sections_enabled() else 0
	# На клиенте кукла шаттла часто freeze (кинематика); ввод всё равно шлём с пира-пилота.
	if not _is_offline() and not multiplayer.is_server() and pilot_peer_id == multiplayer.get_unique_id():
		NetworkManager.submit_shuttle_pilot_input(str(get_path()), _pack_input_from_keyboard())
	if not debug_draw:
		return

	for thruster_name in _thrusters:
		var marker: Marker3D = _thrusters[thruster_name]
		var is_active: bool = _active_thrusters[thruster_name]

		if is_active:
			var local_dir: Vector3 = THRUSTER_DIRS[thruster_name]
			var world_dir: Vector3 = global_transform.basis * local_dir
			var start: Vector3 = marker.global_position
			var end: Vector3 = start + world_dir * thruster_force * debug_force_scale
			DebugDraw3D.draw_arrow(start, end, Color.ORANGE_RED, 0.1, true)
		else:
			DebugDraw3D.draw_sphere(marker.global_position, 0.05, Color(0.4, 0.4, 0.4))

	if _main_thruster != null:
		if _main_thruster_active:
			var world_dir: Vector3 = global_transform.basis * Vector3(0, 0, -1)
			var start: Vector3 = _main_thruster.global_position
			var end: Vector3 = start + world_dir * main_thruster_force * debug_force_scale
			DebugDraw3D.draw_arrow(start, end, Color.CYAN, 0.2, true)
		else:
			DebugDraw3D.draw_sphere(_main_thruster.global_position, 0.08, Color(0.2, 0.6, 0.8))
	if WalkPerfProbe.sections_enabled():
		WalkPerfProbe.record_section(&"shuttle_process", Time.get_ticks_usec() - _wp0)
