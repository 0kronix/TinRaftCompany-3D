extends RigidBody3D

signal asteroid_despawned

@export var min_rotation_speed: float = 0.1
@export var max_rotation_speed: float = 1.0

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
var spawner_center: Node3D  # Ссылка на спавнер (цель)

func _ready():
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	
	_randomize_rotation()
	_randomize_scale()
	
	call_deferred("_set_random_trajectory")

func _randomize_rotation():
	rotation_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	
	rotation_speed = randf_range(min_rotation_speed, max_rotation_speed)
	angular_velocity = rotation_axis * rotation_speed

func _randomize_scale():
	var scale_factor = randf_range(min_scale, max_scale)
	scale = Vector3(scale_factor, scale_factor, scale_factor)
	mass = mass * scale_factor * scale_factor * scale_factor

func _set_random_trajectory():
	# Центр — позиция спавнера (если передан) или мировой центр
	var center_pos = spawner_center.global_position if spawner_center else Vector3.ZERO
	
	var target_pos = Vector3(
		center_pos.x + randf_range(-target_spread, target_spread),
		center_pos.y + randf_range(-target_spread, target_spread),
		center_pos.z + randf_range(-target_spread, target_spread)
	)
	
	direction = (target_pos - global_position).normalized()
	current_speed = randf_range(min_speed, max_speed)
	linear_velocity = direction * current_speed

func _physics_process(_delta):
	# Центр для проверки удаления
	var center = spawner_center.global_position if spawner_center else Vector3.ZERO
	
	# Проверка удаления по расстоянию от центра
	if global_position.distance_to(center) > despawn_distance:
		asteroid_despawned.emit()
		queue_free()
		return
