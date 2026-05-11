extends Node3D

@export var item_scenes: Array[PackedScene] = []
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


func _ready() -> void:
	# Клиенты не спавнят поле — иначе имена instance_id не совпадают с хостом, ломается RPC/кэш путей.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	rng.randomize()
	await get_tree().process_frame

	for i in range(target_count):
		_spawn_item()
		await get_tree().process_frame


func _pick_random_scene() -> PackedScene:
	if item_scenes.is_empty():
		return null

	var total = 0.0
	for c in spawn_chances:
		total += c
	var roll = rng.randf_range(0, total)

	var current = 0.0
	for i in range(item_scenes.size()):
		current += spawn_chances[i]
		if roll <= current:
			return item_scenes[i]

	return item_scenes[0]


func _spawn_item() -> void:
	var scene := _pick_random_scene()
	if scene == null:
		return

	var object := scene.instantiate()
	var sid: int
	if multiplayer.is_server():
		sid = NetworkManager.take_field_asteroid_id()
	else:
		sid = current_count
	object.name = "AsteroidField_%d" % sid

	get_tree().current_scene.add_child(object)
	current_count += 1

	if object.has_signal("despawned"):
		object.despawned.connect(_on_despawn)

	var center := global_position
	var theta = rng.randf_range(0, 2 * PI)
	var phi = rng.randf_range(0, PI)

	object.global_position = Vector3(
		center.x + spawn_radius * sin(phi) * cos(theta),
		center.y + spawn_radius * sin(phi) * sin(theta),
		center.z + spawn_radius * cos(phi)
	)

	object.min_speed = min_speed
	object.max_speed = max_speed
	object.target_spread = target_spread
	object.despawn_distance = despawn_radius
	object.min_scale = min_scale
	object.max_scale = max_scale
	object.set("spawner_center", self)

	if MultiplayerRuntime.has_active_session_for(self) and multiplayer.is_server():
		await get_tree().process_frame
		var rb := object as RigidBody3D
		if rb == null:
			return
		NetworkManager.broadcast_field_asteroid_spawn(
			sid,
			scene.resource_path,
			rb.global_transform,
			rb.linear_velocity,
			rb.angular_velocity,
			min_speed,
			max_speed,
			target_spread,
			despawn_radius,
			min_scale,
			max_scale,
			str(get_path())
		)


func _on_despawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	current_count -= 1
	if current_count < target_count:
		_spawn_item()
