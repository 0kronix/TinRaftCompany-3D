extends Camera3D

# ── Параметры покачивания ─────────────────────────────
@export var bob_frequency : float = 2   # шагов в секунду
@export var bob_amplitude_y : float = 0.02  # подброс вверх-вниз
@export var bob_amplitude_x : float = 0.02  # качание влево-вправо
@export var bob_roll : float = 1         # крен в градусах
@export var return_speed : float = 6.0    # возврат в 0 когда стоим

# ── Внутреннее состояние ──────────────────────────────
var _t : float = 0.0
var _default_pos : Vector3
var _bob_offset : Vector3 = Vector3.ZERO
var _bob_roll : float = 0.0


func _ready() -> void:
	_default_pos = position


func _process(delta: float) -> void:
	var speed = _get_horizontal_speed()
	var is_moving = speed > 0.1

	if is_moving:
		# тикаем таймер пропорционально скорости движения
		_t += delta * bob_frequency * TAU

		_bob_offset = Vector3(
			sin(_t * 0.5) * bob_amplitude_x,  # X — вдвое медленнее
			abs(sin(_t)) * bob_amplitude_y,    # Y — всегда вверх (abs)
			0.0
		)
		_bob_roll = sin(_t * 0.5) * deg_to_rad(bob_roll)
	else:
		# плавно возвращаемся в нейтраль
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, delta * return_speed)
		_bob_roll = lerp(_bob_roll, 0.0, delta * return_speed)

	position = _default_pos + _bob_offset
	rotation.z = _bob_roll


func _get_horizontal_speed() -> float:
	var body = owner  # всегда player (CharacterBody3D)
	if body is CharacterBody3D:
		return Vector2(body.velocity.x, body.velocity.z).length()
	return 0.0
