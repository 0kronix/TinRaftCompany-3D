extends RigidBody3D

@onready var label = $RemoteTransform3D/Label3D

# Изменяемые значения -----------------
@export var min_rotation_speed: float = 0.1
@export var max_rotation_speed: float = 1.0

@export var min_speed: float = 0.0
@export var max_speed: float = 2.0

@export var min_scale: float = 0.5
@export var max_scale: float = 2.0

@export var target_spread: float = 20.0
@export var despawn_distance: float = 200.0

# Настройки разрушения
@export var debris_count: int = 3       
@export var explosion_force: float = 1.0

@export var min_scale_debris: float = 0.5
@export var max_scale_debris: float = 2.0
# ---------------------------------------

@export var dust_cloud_scene: PackedScene
@export var debris_scene: PackedScene

var direction: Vector3
var current_speed: float
var rotation_axis: Vector3
var rotation_speed: float
var spawner_center: Node3D  # Ссылка на спавнер (цель)

signal despawned

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
		despawned.emit()
		queue_free()
		return
		
# ВЗАИМОДЕЙСТВИЕ
func interact(_player):
	print("Asteroid destroyed!")
	
	# Создаём обломки и частицы
	_spawn_dust_cloud()
	_spawn_debris()
	
	# Отправляем сигнал деспавна и удаляемся
	despawned.emit()
	queue_free()

func _spawn_dust_cloud():
	if dust_cloud_scene == null:
		print("WARNING: dust_cloud_scene not assigned!")
		return
	
	var dust = dust_cloud_scene.instantiate()
	get_tree().current_scene.add_child(dust)
	dust.global_position = global_position
	
	# Получаем текущий радиус астероида (среднее от scale)
	var asteroid_radius = (scale.x + scale.y + scale.z) / 3.0
	
	# Рассчитываем количество частиц пропорционально объёму
	var base_amount = 20
	var amount_multiplier = asteroid_radius * asteroid_radius
	dust.amount = int(base_amount * amount_multiplier)
	
	# Применяем радиус к системе частиц
	if dust.process_material is ParticleProcessMaterial:
		var mat = dust.process_material as ParticleProcessMaterial
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = asteroid_radius
	
	# Изменяем размер сферы в draw_pass_1
	var mesh = dust.draw_pass_1
	if mesh is SphereMesh:
		var new_mesh = SphereMesh.new()
		new_mesh.radius = asteroid_radius * 0.25  # Частицы меньше астероида
		new_mesh.height = asteroid_radius * 0.5
		new_mesh.material = mesh.material  # Сохраняем материал
		dust.draw_pass_1 = new_mesh
	
	dust.emitting = true
	dust.finished.connect(dust.queue_free)

func _spawn_debris():
	if debris_scene == null:
		print("WARNING: debris_scene not assigned!")
		return
	
	for i in range(debris_count):
		var debris = debris_scene.instantiate()
		get_tree().current_scene.add_child(debris)
		
		# Случайное смещение от центра астероида
		var offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		)
		
		# Позиция обломка
		debris.global_position = global_position + offset
		
		# Случайный размер
		var s = randf_range(min_scale_debris, max_scale_debris)
		debris.scale = Vector3(s, s, s)
		
		if debris is RigidBody3D:
			# Основной импульс от центра
			debris.linear_velocity = direction * explosion_force
			
			# Добавляем немного случайности для естественности
			var random_offset = Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-0.5, 0.5),
				randf_range(-0.5, 0.5)
			)
			debris.linear_velocity += random_offset
			
			# Случайное вращение
			debris.angular_velocity = Vector3(
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0),
				randf_range(-2.0, 2.0)
			)

func show_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)

func hide_hint():
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)
