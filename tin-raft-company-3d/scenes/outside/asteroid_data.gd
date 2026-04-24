extends RigidBody3D

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


func _ready() -> void:
	gravity_scale    = 0.0
	linear_damp      = 0.0
	angular_damp     = 0.0
	linear_damp_mode  = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE

	# Deterministic seed so rotation/scale/trajectory are identical on all peers
	# before the MultiplayerSynchronizer takes over position authority.
	seed(hash(str(get_path())))

	_randomize_rotation()
	_randomize_scale()
	call_deferred("_set_random_trajectory")

	# After all properties are set up, install the position synchronizer.
	call_deferred("_setup_position_sync")


# ── Multiplayer position sync ─────────────────────────────────────────────────

func _setup_position_sync() -> void:
	# Non-authority peers (clients) freeze local physics and let the server's
	# MultiplayerSynchronizer drive their position and rotation.
	if not is_multiplayer_authority():
		freeze      = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	var sync   := MultiplayerSynchronizer.new()
	sync.name  = "PositionSync"
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:position"))
	config.add_property(NodePath(".:rotation"))
	sync.replication_config   = config
	sync.replication_interval = 1.0 / 20.0  # 20 Hz
	add_child(sync)


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


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var center := spawner_center.global_position if spawner_center else Vector3.ZERO
	if global_position.distance_to(center) > despawn_distance:
		despawned.emit()
		queue_free()


# ── Interaction ───────────────────────────────────────────────────────────────

func interact(_player: Node3D) -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.request_command(_player, build_interaction_command())


func build_interaction_command() -> Dictionary:
	return {
		"type":        "break_asteroid",
		"target_path": get_path()
	}


func server_validate_interaction(_actor: Node3D) -> bool:
	return true


func server_apply_interaction(_actor: Node3D) -> bool:
	# Dust cloud is a local-only visual effect — not replicated.
	_spawn_dust_cloud()

	# Debris pieces go into WorldObjects; WorldSpawner replicates them with
	# their correct spawn positions via the spawn_function data dict.
	_spawn_debris()

	despawned.emit()

	# Broadcast this asteroid's removal to all peers and record for late-joiners.
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.is_session_active():
		nm.notify_node_despawned(self)
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
	dust.amount = int(20 * asteroid_radius * asteroid_radius)

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

	var world_objects: Node = get_node_or_null("/root/Inside/WorldObjects")
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

		if spawner != null:
			spawner.spawn({
				"scene_path": debris_scene.resource_path,
				"position":   position + offset,
				"scale":      s,
			})
		else:
			# Singleplayer fallback — no spawner configured yet.
			var debris := debris_scene.instantiate()
			debris.position = position + offset
			debris.scale    = Vector3(s, s, s)
			world_objects.add_child(debris, true)


func show_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a",         1.0, 0.15)
	tween.tween_property(label, "outline_modulate:a", 1.0, 0.15)


func hide_hint() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a",         0.0, 0.1)
	tween.tween_property(label, "outline_modulate:a", 0.0, 0.1)
