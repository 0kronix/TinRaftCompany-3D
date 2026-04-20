extends RigidBody3D

signal asteroid_despawned

@export var min_rotation_speed: float = 0.0
@export var max_rotation_speed: float = 1.5

@export var min_speed: float = 0.0
@export var max_speed: float = 2.0

@export var target_spread: float = 20.0
@export var despawn_distance: float = 150.0

@export var min_scale: float = 0.5
@export var max_scale: float = 2.0

var direction: Vector3
var current_speed: float
var rotation_axis: Vector3
var rotation_speed: float

func _ready():
	_randomize_rotation()
	_randomize_scale()
	
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
	
	# Применяем угловую скорость через физический движок
	angular_velocity = rotation_axis * rotation_speed

func _randomize_scale():
	var scale_factor = randf_range(min_scale, max_scale)
	scale = Vector3(scale_factor, scale_factor, scale_factor)
	
	mass = mass * scale_factor * scale_factor * scale_factor

func _set_random_trajectory():
	var target_pos = Vector3(
		randf_range(-target_spread, target_spread),
		randf_range(-target_spread, target_spread),
		randf_range(-target_spread, target_spread)
	)
	
	direction = (target_pos - global_position).normalized()
	current_speed = randf_range(min_speed, max_speed)
	
	# Используем линейную скорость физического движка
	linear_velocity = direction * current_speed

func _physics_process(_delta):
	if global_position.length() > despawn_distance:
		asteroid_despawned.emit()
		queue_free()
		return
