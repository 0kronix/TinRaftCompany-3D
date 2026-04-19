extends RigidBody3D

# ── Настройки ──────────────────────────────────────────────
@export var thruster_force: float = 0.1
@export var debug_draw: bool = true
@export var debug_force_scale: float = 0.05

# ── Направления тяги (локальные координаты корабля) ────────
const THRUSTER_DIRS: Dictionary = {
	"Pitch_T1": Vector3(0, 1, 0),
	"Pitch_T2": Vector3(0, -1, 0),
	"Pitch_T3": Vector3(0, 1, 0),
	"Pitch_T4": Vector3( 0, -1, 0),
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

# ───────────────────────────────────────────────────────────
func _ready() -> void:
	# Собираем все Marker3D из группы Thrusters
	for marker in $Thrusters.get_children():
		if marker is Marker3D:
			_thrusters[marker.name] = marker
			_active_thrusters[marker.name] = false



func _physics_process(_delta: float) -> void:
	# Сбрасываем активные двигатели
	for key in _active_thrusters:
		_active_thrusters[key] = false

	# ── W / S — Pitch (нос вверх / вниз) ───────────────────
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		_fire_maneuver("pitch_up")
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		_fire_maneuver("pitch_down")

	# ── A / D — Yaw (нос влево / вправо) ───────────────────
	if Input.is_key_pressed(KEY_A):
		_fire_maneuver("yaw_left")
	if Input.is_key_pressed(KEY_D):
		_fire_maneuver("yaw_right")

	# ── Q / E — Roll (крен влево / вправо) ─────────────────
	if Input.is_key_pressed(KEY_Q):
		_fire_maneuver("roll_left")
	if Input.is_key_pressed(KEY_E):
		_fire_maneuver("roll_right")


# ── Запускает группу двигателей по имени манёвра ───────────
func _fire_maneuver(maneuver: String) -> void:
	for thruster_name in MANEUVER_THRUSTERS[maneuver]:
		_apply_thruster(thruster_name, thruster_force)


# ── Применяет силу одного двигателя ────────────────────────
func _apply_thruster(thruster_name: String, force: float) -> void:
	if not _thrusters.has(thruster_name):
		push_warning("Thruster not found: " + thruster_name)
		return

	var marker: Marker3D = _thrusters[thruster_name]
	var local_dir: Vector3 = THRUSTER_DIRS[thruster_name]

	# Переводим направление в мировые координаты
	var world_force: Vector3 = global_transform.basis * (local_dir * force)

	# Смещение от центра масс (не от origin!)
	var offset: Vector3 = marker.global_position - global_position

	apply_force(world_force, offset)

	_active_thrusters[thruster_name] = true


# ── Дебаг: рисуем стрелки активных двигателей ──────────────
func _process(_delta: float) -> void:
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

			# Активный двигатель — ярко-оранжевый
			DebugDraw3D.draw_arrow(start, end, Color.ORANGE_RED, 0.1, true)
		else:
			# Неактивный — серая точка
			DebugDraw3D.draw_sphere(marker.global_position, 0.05, Color(0.4, 0.4, 0.4))
