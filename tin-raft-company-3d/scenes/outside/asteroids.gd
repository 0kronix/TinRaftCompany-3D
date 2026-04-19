extends Node3D

@export var asteroid_scene: PackedScene
@export var spawn_radius: float = 100.0
@export var despawn_radius: float = 150.0
@export var target_asteroid_count: int = 20
@export var min_speed: float = 0.0
@export var max_speed: float = 2.0
@export var target_spread: float = 20.0

var rng = RandomNumberGenerator.new()
var current_asteroid_count: int = 0

func _ready():
	rng.randomize()
	
	# Проверка наличия сцены
	if asteroid_scene == null:
		push_error("ERROR: Asteroid Scene is not assigned in the Inspector!")
		return
	
	# Создаем начальные астероиды
	print("Spawning initial ", target_asteroid_count, " asteroids...")
	for i in range(target_asteroid_count):
		_spawn_asteroid()
		await get_tree().process_frame  # Небольшая задержка между спавнами
	
	print("Spawner ready. Target count: ", target_asteroid_count)

func _spawn_asteroid():
	if asteroid_scene == null:
		return
	
	var asteroid = asteroid_scene.instantiate()
	add_child(asteroid)
	current_asteroid_count += 1
	
	# Подключаем сигнал деспавна
	if asteroid.has_signal("asteroid_despawned"):
		asteroid.asteroid_despawned.connect(_on_asteroid_despawned)
	
	# Рассчитываем случайную позицию на сфере
	var theta = rng.randf_range(0, 2 * PI)
	var phi = rng.randf_range(0, PI)
	
	var x = spawn_radius * sin(phi) * cos(theta)
	var y = spawn_radius * sin(phi) * sin(theta)
	var z = spawn_radius * cos(phi)
	
	asteroid.global_position = Vector3(x, y, z)
	
	# Передаем параметры астероиду
	asteroid.min_speed = min_speed
	asteroid.max_speed = max_speed
	asteroid.target_spread = target_spread
	asteroid.despawn_distance = despawn_radius
	
	print("Asteroid spawned at distance: ", asteroid.global_position.length(), 
		  " | Count: ", current_asteroid_count, "/", target_asteroid_count)

func _on_asteroid_despawned():
	current_asteroid_count -= 1
	print("Asteroid despawned | Count: ", current_asteroid_count, "/", target_asteroid_count)
	
	# Восполняем количество
	_check_and_refill()

func _check_and_refill():
	# Создаем новые астероиды, пока не достигнем целевого количества
	while current_asteroid_count < target_asteroid_count:
		_spawn_asteroid()
		await get_tree().process_frame  # Небольшая задержка для плавности

# Вспомогательные функции для управления количеством
func get_asteroid_count() -> int:
	return current_asteroid_count

func set_target_count(new_count: int):
	target_asteroid_count = max(1, new_count)
	print("New target count: ", target_asteroid_count)
	_check_and_refill()

func increase_target_count(amount: int = 1):
	target_asteroid_count += amount
	print("Target count increased to: ", target_asteroid_count)
	_check_and_refill()

func decrease_target_count(amount: int = 1):
	target_asteroid_count = max(1, target_asteroid_count - amount)
	print("Target count decreased to: ", target_asteroid_count)
	# Ждем естественного деспавна, не удаляем существующие
