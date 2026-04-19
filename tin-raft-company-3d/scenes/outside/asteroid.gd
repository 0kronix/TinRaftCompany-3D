extends RigidBody3D

# Добавляем сигнал для уведомления о деспавне
signal asteroid_despawned

@export var min_rotation_speed: float = 0.5
@export var max_rotation_speed: float = 3.0
@export var min_speed: float = 0.0
@export var max_speed: float = 2.0
@export var target_spread: float = 20.0
@export var despawn_distance: float = 150.0

var direction: Vector3
var current_speed: float
var rotation_axis: Vector3
var rotation_speed: float

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	
	_randomize_rotation()
	
	call_deferred("_set_random_trajectory")

func _randomize_rotation():
	# Случайная ось вращения
	rotation_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	
	# Случайная скорость вращения
	rotation_speed = randf_range(min_rotation_speed, max_rotation_speed)

func _set_random_trajectory():
	var target_pos = Vector3(
		randf_range(-target_spread, target_spread),
		randf_range(-target_spread, target_spread),
		randf_range(-target_spread, target_spread)
	)
	
	direction = (target_pos - global_position).normalized()
	current_speed = randf_range(min_speed, max_speed)
	
	# Вместо look_at() просто поворачиваем в направлении движения один раз
	if direction.length() > 0:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta):
	# Проверка удаления
	if global_position.length() > despawn_distance:
		asteroid_despawned.emit()  # Отправляем сигнал перед удалением
		queue_free()
		return
	
	# Ручное перемещение (игнорируем физический движок)
	global_position += direction * current_speed * delta
	
	rotate(rotation_axis, rotation_speed * delta)
