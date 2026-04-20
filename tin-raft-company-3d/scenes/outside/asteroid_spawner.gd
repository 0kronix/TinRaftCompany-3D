extends Node3D

# Просто перетащите сюда все сцены предметов
@export var item_scenes: Array[PackedScene] = []

# Шансы спавна (по порядку, соответствуют item_scenes)
@export var spawn_chances: Array[float] = []

@export var spawn_radius: float = 200.0
@export var despawn_radius: float = 210.0
@export var target_count: int = 50
@export var target_spread: float = 20.0
@export var min_speed: float = 0.0
@export var max_speed: float = 2.0
@export var min_scale: float = 0.5
@export var max_scale: float = 2.0

var rng = RandomNumberGenerator.new()
var current_count: int = 0

func _ready():
	rng.randomize()
	await get_tree().process_frame
	
	for i in range(target_count):
		_spawn_item()
		await get_tree().process_frame

func _pick_random_scene() -> PackedScene:
	if item_scenes.is_empty():
		return null
	
	# Суммируем все шансы
	var total = 0.0
	for c in spawn_chances:
		total += c
	
	# Случайное число от 0 до total
	var roll = rng.randf_range(0, total)
	
	# Ищем, какой предмет выпал
	var current = 0.0
	for i in range(item_scenes.size()):
		current += spawn_chances[i]
		if roll <= current:
			return item_scenes[i]
	
	return item_scenes[0]

func _spawn_item():
	var scene = _pick_random_scene()
	if scene == null:
		return
	
	var item = scene.instantiate()
	get_tree().current_scene.add_child(item)
	current_count += 1
	
	if item.has_signal("asteroid_despawned"):
		item.asteroid_despawned.connect(_on_item_despawned)
	
	var center = global_position
	var theta = rng.randf_range(0, 2 * PI)
	var phi = rng.randf_range(0, PI)
	
	item.global_position = Vector3(
		center.x + spawn_radius * sin(phi) * cos(theta),
		center.y + spawn_radius * sin(phi) * sin(theta),
		center.z + spawn_radius * cos(phi)
	)
	
	# Передаём параметры
	item.min_speed = min_speed
	item.max_speed = max_speed
	item.target_spread = target_spread
	item.despawn_distance = despawn_radius
	item.min_scale = min_scale
	item.max_scale = max_scale
	item.set("spawner_center", self)

func _on_item_despawned():
	current_count -= 1
	if current_count < target_count:
		_spawn_item()
