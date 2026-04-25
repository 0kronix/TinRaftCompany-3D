extends Camera3D

@export var debug_eva_bob: bool = false
@export var debug_eva_bob_log_interval: int = 45

# ── Ходьба по полу (капсула) ────────────────────────────────────────────────
@export var bob_frequency: float = 2.0
@export var bob_amplitude_y: float = 0.02
@export var bob_amplitude_x: float = 0.02
@export var bob_roll: float = 1.0
@export var return_speed: float = 6.0

# ── EVA: плавный «толчок» камеры вдоль вектора движения (скорости) / тяги с места ─
@export var jetpack_wobble_freq: float = 3.0
@export var jetpack_wobble_amp: float = 0.018
@export var jetpack_sustain_push: float = 0.01
@export var jetpack_dir_smooth: float = 8.0
@export var jetpack_return_speed: float = 12.0
@export var jetpack_move_speed_threshold: float = 0.25
@export var jetpack_mag_smooth: float = 0.0
@export var jetpack_drift_min_speed: float = 0.2
@export var jetpack_drift_strength_per_mps: float = 0.1
@export var jetpack_drift_strength_max: float = 0.2
@export var jetpack_tilt_wobble_deg: float = 0.3
## Наклоны от ускорения: вдоль/против взгляда, влево-вправо, вверх-вниз (локаль головы)
@export var jetpack_accel_tilt_in_out_deg: float = 0.14
@export var jetpack_accel_tilt_lateral_deg: float = 0.12
@export var jetpack_accel_tilt_vertical_deg: float = 0.1

var _t: float = 0.0
var _default_pos: Vector3
var _bob_offset: Vector3 = Vector3.ZERO
var _bob_roll: float = 0.0
var _eva_bob_tilt_x: float = 0.0
var _eva_bob_tilt_y: float = 0.0
## Локаль Head: камера смотрит в -Z; сдвиг вдоль (0,0,±1) мало различается на экране
const _HEAD_LOOK: Vector3 = Vector3(0, 0, -1.0)
## Сглаженная ось в локале головы
var _eva_dir_head_smooth: Vector3 = Vector3.ZERO
## Только плавная амплитуда (сила не через lerp вектора к цели — он «съедал» эффект)
var _eva_jetpack_mag: float = 0.0
## Заполняет player.gd каждый _physics_process (get() с CharacterBody+скриптом ненадёжен)
var _feed_eva: bool = false
var _feed_thrust: float = 0.0
var _feed_tdir: Vector3 = Vector3.ZERO
var _feed_vel: Vector3 = Vector3.ZERO

var _debug_jetpack_skip_frames: int = 0
var _set_eva_log_n: int = 0


func set_eva_jetpack_state(p_eva: bool, p_thrust: float, p_tdir: Vector3, p_vel: Vector3) -> void:
	_feed_eva = p_eva
	_feed_thrust = p_thrust
	_feed_tdir = p_tdir
	_feed_vel = p_vel
	if debug_eva_bob and (p_eva and (p_thrust > 0.01 or p_vel.length() > 0.3)):
		_set_eva_log_n += 1
		var ph: int = Engine.get_physics_frames()
		if _set_eva_log_n <= 3 or _set_eva_log_n % maxi(1, debug_eva_bob_log_interval) == 0:
			print(
				"[EvaHeadBob] set_eva (ph=",
				ph,
				") eva=",
				p_eva,
				" thrust=",
				snappedf(p_thrust, 0.001),
				" tdir=",
				p_tdir,
				" vel|=",
				snappedf(p_vel.length(), 0.01)
			)


func _ready() -> void:
	_default_pos = position
	# Сила тяги EVA и velocity обновляются в _physics_process — совмещаем тряску с тем же кадром
	set_physics_process(true)
	if debug_eva_bob:
		print(
			"[EvaHeadBob] ready path=",
			get_path(),
			" physics_process=",
			is_physics_processing(),
			" process_mode=",
			process_mode
		)


## Ищем тело персонажа вверх по дереву: owner у камеры в рантайме не гарантируется
func _get_player_body() -> CharacterBody3D:
	var n: Node = get_parent()
	while n:
		if n is CharacterBody3D:
			return n as CharacterBody3D
		n = n.get_parent()
	return null


func _physics_process(delta: float) -> void:
	var ch: CharacterBody3D = _get_player_body()
	_debug_jetpack_skip_frames = Engine.get_physics_frames()
	if ch == null:
		if debug_eva_bob and _debug_jetpack_skip_frames % 120 == 1:
			print("[EvaHeadBob] _physics: CharacterBody3D not found (parent tree?)")
		return
	if ch.is_multiplayer_authority() == false:
		position = _default_pos
		rotation = Vector3.ZERO
		if debug_eva_bob and _debug_jetpack_skip_frames % 120 == 2:
			print("[EvaHeadBob] _physics: no authority, skip (puppet) peer=", multiplayer.get_unique_id())
		return

	# eva: из player.set_eva_jetpack_state
	if _feed_eva:
		_process_jetpack_bob(delta, ch)
	else:
		_eva_bob_tilt_x = 0.0
		_eva_bob_tilt_y = 0.0
		_process_walk_bob(delta, ch)

	if debug_eva_bob and _feed_eva and _debug_jetpack_skip_frames % maxi(1, debug_eva_bob_log_interval) == 0:
		print(
			"[EvaHeadBob] _physics eva: thrust=%.3f |bob|=%.5f off=%s feed_vel|=%.2f" % [
				_feed_thrust,
				_bob_offset.length(),
				_bob_offset,
				_feed_vel.length()
			]
		)

	position = _default_pos + _bob_offset
	if _feed_eva:
		rotation = Vector3(_eva_bob_tilt_x, _eva_bob_tilt_y, 0.0)
	else:
		rotation = Vector3(0.0, 0.0, _bob_roll)


func _process_walk_bob(delta: float, body: CharacterBody3D) -> void:
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length()
	var is_moving: bool = speed > 0.1

	if is_moving:
		_t += delta * bob_frequency * TAU
		_bob_offset = Vector3(
			sin(_t * 0.5) * bob_amplitude_x,
			abs(sin(_t)) * bob_amplitude_y,
			0.0
		)
		_bob_roll = sin(_t * 0.5) * deg_to_rad(bob_roll)
	else:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * return_speed)
		_bob_roll = lerpf(_bob_roll, 0.0, delta * return_speed)


func _process_jetpack_bob(delta: float, body: CharacterBody3D) -> void:
	var thrust: float = _feed_thrust
	var tdir: Vector3 = _feed_tdir
	var v: Vector3 = _feed_vel
	var speed: float = v.length()

	# 0..1: реальная тяга, либо «виртуальная» от инерциального дрейфа (сопла отпущены, но |v| есть)
	var effect: float = thrust
	if effect < 0.005 and speed >= jetpack_drift_min_speed:
		effect = minf(jetpack_drift_strength_max, speed * jetpack_drift_strength_per_mps)
	# Полный покой: тяга ноль и слишком мало инерции
	if effect < 0.002 and speed < jetpack_drift_min_speed * 0.4:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * jetpack_return_speed)
		_bob_roll = lerpf(_bob_roll, 0.0, delta * jetpack_return_speed)
		_eva_jetpack_mag = lerpf(_eva_jetpack_mag, 0.0, delta * jetpack_return_speed)
		_eva_bob_tilt_x = lerpf(_eva_bob_tilt_x, 0.0, delta * jetpack_return_speed)
		_eva_bob_tilt_y = lerpf(_eva_bob_tilt_y, 0.0, delta * jetpack_return_speed)
		if _bob_offset.length_squared() < 1e-6:
			_eva_dir_head_smooth = Vector3.ZERO
		return

	# Направление: в мире — по velocity, если движемся, иначе по вектору тяги
	var d_world: Vector3 = Vector3.ZERO
	if speed > jetpack_move_speed_threshold:
		d_world = v / speed
	elif tdir.length_squared() > 0.0001:
		d_world = body.global_transform.basis * tdir.normalized()
	elif speed > 0.04:
		d_world = v / speed
	if d_world.length_squared() < 1e-8:
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * jetpack_return_speed)
		_bob_roll = lerpf(_bob_roll, 0.0, delta * jetpack_return_speed)
		_eva_bob_tilt_x = lerpf(_eva_bob_tilt_x, 0.0, delta * jetpack_return_speed)
		_eva_bob_tilt_y = lerpf(_eva_bob_tilt_y, 0.0, delta * jetpack_return_speed)
		if debug_eva_bob:
			print(
				"[EvaHeadBob] jetpack: skip d_world=0: speed=",
				speed,
				" tdir=",
				tdir,
				" (нужен порог speed или tdir)"
			)
		return

	var head: Node3D = get_parent() as Node3D
	if head == null:
		_eva_bob_tilt_x = lerpf(_eva_bob_tilt_x, 0.0, delta * jetpack_return_speed)
		_eva_bob_tilt_y = lerpf(_eva_bob_tilt_y, 0.0, delta * jetpack_return_speed)
		if debug_eva_bob:
			print("[EvaHeadBob] jetpack: Head parent=null")
		return
	var d_h: Vector3 = head.global_transform.basis.inverse() * d_world
	if d_h.length_squared() < 1e-10:
		if debug_eva_bob:
			print("[EvaHeadBob] jetpack: d_h≈0 d_world=", d_world)
		return
	d_h = d_h.normalized()
	# lerp + normalized() на почти противоположных векторах даёт ноль — камера замирает; обходим
	if _eva_dir_head_smooth.length_squared() < 0.0001:
		_eva_dir_head_smooth = d_h
	else:
		var blended: Vector3 = _eva_dir_head_smooth.lerp(d_h, minf(1.0, delta * jetpack_dir_smooth))
		if blended.length_squared() < 1e-6:
			_eva_dir_head_smooth = d_h
		else:
			_eva_dir_head_smooth = blended.normalized()
	var axis: Vector3 = _eva_dir_head_smooth
	var a_para: float = axis.dot(_HEAD_LOOK)
	var a_perp: Vector3 = axis - _HEAD_LOOK * a_para
	if a_perp.length_squared() < 0.0002:
		var side: Vector3 = Vector3.UP.cross(_HEAD_LOOK)
		if side.length_squared() < 0.0001:
			side = _HEAD_LOOK.cross(Vector3.RIGHT)
		a_perp = side.normalized()
	else:
		a_perp = a_perp.normalized()
	# Смещение картинки — только вдоль a_perp: это реальная «сторона ускорения» на экране (лево/право, вверх/низ)
	_t += delta * jetpack_wobble_freq * TAU
	var wave: float = 0.5 + 0.5 * sin(_t)  # ~0..1, колебания вдоль той же оси, что и тяга
	var target_mag: float = effect * (jetpack_sustain_push + jetpack_wobble_amp * wave)
	if jetpack_mag_smooth > 0.01:
		_eva_jetpack_mag = lerpf(_eva_jetpack_mag, target_mag, minf(1.0, delta * jetpack_mag_smooth))
		_bob_offset = a_perp * _eva_jetpack_mag
	else:
		_eva_jetpack_mag = target_mag
		_bob_offset = a_perp * target_mag
	_bob_roll = lerpf(_bob_roll, 0.0, delta * jetpack_return_speed)
	# Слабая «шумовая» вибрация + читаемый крен в сторону ускорения (axis в локали головы: x=вбок, y=вверх, z взгляд)
	var tilt_s: float = effect * deg_to_rad(jetpack_tilt_wobble_deg)
	var te: float = effect
	_eva_bob_tilt_x = (
		sin(_t * 1.1) * tilt_s * 0.45
		- a_para * te * deg_to_rad(jetpack_accel_tilt_in_out_deg)
		+ axis.y * te * deg_to_rad(jetpack_accel_tilt_vertical_deg)
	)
	_eva_bob_tilt_y = (
		sin(_t * 0.86) * tilt_s * 0.4
		+ axis.x * te * deg_to_rad(jetpack_accel_tilt_lateral_deg)
	)
