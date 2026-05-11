extends NetworkReplicatedRigidBody

@onready var label = $RemoteTransform3D/Label3D

@export var min_rotation_speed: float = 0.1
@export var max_rotation_speed: float = 1.0

@export var min_speed: float = 0.0
@export var max_speed: float = 2.0

@export var min_scale: float = 0.5
@export var max_scale: float = 2.0

@export var target_spread: float  = 20.0
@export var despawn_distance: float = 200.0

@export var debris_count:    int   = 3
@export var explosion_force: float = 1.0

@export var min_scale_debris: float = 0.5
@export var max_scale_debris: float = 2.0

@export var dust_cloud_scene: PackedScene
@export var debris_scene:     PackedScene

var direction:      Vector3
var current_speed:  float
var rotation_axis:  Vector3
var rotation_speed: float
var spawner_center: Node3D

signal despawned


func _enter_tree() -> void:
	super._enter_tree()
	_ensure_stable_name()


func _ready() -> void:
	if label:
		Label3DHint.prepare_hidden(label)
	gravity_scale    = 0.0
	linear_damp      = 0.0
	angular_damp     = 0.0
	linear_damp_mode  = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	if not is_multiplayer_authority():
		# Кукла с EVA-поля: физика и transform с сервера (NetworkReplicatedRigidBody + RPC).
		return
	# Одинаковый seed на лидере, траектория с сервера.
	seed(hash(str(get_path())))
	_randomize_rotation()
	_randomize_scale()
	call_deferred("_set_random_trajectory")


# ── Multiplayer position sync ─────────────────────────────────────────────────

func _ensure_stable_name() -> void:
	var n: String = str(name)
	if n.begins_with("@"):
		var p: String = get_scene_file_path()
		var base: String = p.get_file().get_basename() if p else "Asteroid"
		name = base + "_%d" % (get_instance_id() & 0xfffff)


# ── Physics (server / singleplayer only) ─────────────────────────────────────

func _randomize_rotation() -> void:
	rotation_axis = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	).normalized()
	rotation_speed   = randf_range(min_rotation_speed, max_rotation_speed)
	angular_velocity = rotation_axis * rotation_speed


func _randomize_scale() -> void:
	var s := randf_range(min_scale, max_scale)
	scale = Vector3(s, s, s)
	mass  = mass * s * s * s


func _set_random_trajectory() -> void:
	var center_pos := spawner_center.global_position if spawner_center else Vector3.ZERO
	var target_pos := Vector3(
		center_pos.x + randf_range(-target_spread, target_spread),
		center_pos.y + randf_range(-target_spread, target_spread),
		center_pos.z + randf_range(-target_spread, target_spread)
	)
	direction      = (target_pos - global_position).normalized()
	current_speed  = randf_range(min_speed, max_speed)
	linear_velocity = direction * current_speed


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_multiplayer_authority():
		return
	var center := spawner_center.global_position if spawner_center else Vector3.ZERO
	if global_position.distance_to(center) > despawn_distance:
		despawned.emit()
		if (
			NetworkManager.is_session_active()
			and str(name).begins_with("AsteroidField_")
		):
			NetworkManager.notify_node_despawned(self)
		queue_free()


# ── Interaction ───────────────────────────────────────────────────────────────

func interact(_player: Node3D) -> void:
	NetworkManager.request_command(_player, build_interaction_command())


func build_interaction_command() -> Dictionary:
	return {
		"type":        "break_asteroid",
		"target_path": get_path()
	}


func server_validate_interaction(_actor: Node3D) -> bool:
	return true


func server_apply_interaction(_actor: Node3D, _command: Dictionary = {}) -> bool:
	# Dust cloud is a local-only visual effect — not replicated.
	_spawn_dust_cloud()

	# Debris pieces go into WorldObjects; WorldSpawner replicates them with
	# their correct spawn positions via the spawn_function data dict.
	_spawn_debris()

	despawned.emit()

	# Broadcast this asteroid's removal to all peers and record for late-joiners.
	if NetworkManager.is_session_active():
		NetworkManager.notify_node_despawned(self)
	queue_free()
	return true


# ── Visual effects ────────────────────────────────────────────────────────────

func _spawn_dust_cloud() -> void:
	if dust_cloud_scene == null:
		return
	var dust := dust_cloud_scene.instantiate()
	get_tree().current_scene.add_child(dust)
	dust.global_position = global_position

	var asteroid_radius := (scale.x + scale.y + scale.z) / 3.0
	const MAX_DUST_PARTICLES: int = 72
	dust.amount = mini(MAX_DUST_PARTICLES, int(20 * asteroid_radius * asteroid_radius))

	if dust.process_material is ParticleProcessMaterial:
		var mat := dust.process_material as ParticleProcessMaterial
		mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = asteroid_radius

	var mesh: Mesh = dust.draw_pass_1
	if mesh is SphereMesh:
		var new_mesh      := SphereMesh.new()
		new_mesh.radius   = asteroid_radius * 0.25
		new_mesh.height   = asteroid_radius * 0.5
		new_mesh.material = mesh.material
		dust.draw_pass_1  = new_mesh

	dust.emitting = true
	dust.finished.connect(dust.queue_free)


func _spawn_debris() -> void:
	if debris_scene == null:
		push_warning("asteroid_data: debris_scene not assigned on " + name)
		return

	var world_objects: Node = GameScenePaths.get_world_objects_node(get_tree())
	if world_objects == null:
		world_objects = get_tree().current_scene

	# Get the MultiplayerSpawner that watches WorldObjects.  Using spawn(data)
	# (instead of add_child) lets us pass the spawn position in the data dict
	# so clients recreate the debris at the exact same location.
	var spawner := world_objects.get_node_or_null("WorldSpawner") as MultiplayerSpawner

	for i in range(debris_count):
		var offset := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		)
		var s := randf_range(min_scale_debris, max_scale_debris)
		var blast_dir := (offset + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))).normalized()
		var velocity  := blast_dir * explosion_force * randf_range(2.0, 5.0)

		if spawner != null:
			spawner.spawn({
				"scene_path": debris_scene.resource_path,
				"position":   position + offset,
				"scale":      s,
				"velocity":   velocity,
			})
		else:
			# Singleplayer fallback — no spawner configured yet.
			var debris := debris_scene.instantiate()
			debris.position = position + offset
			debris.scale    = Vector3(s, s, s)
			world_objects.add_child(debris, true)
			if debris is RigidBody3D:
				(debris as RigidBody3D).linear_velocity = velocity


func show_hint() -> void:
	Label3DHint.tween_show(self, label)


func hide_hint() -> void:
	Label3DHint.tween_hide(self, label)
