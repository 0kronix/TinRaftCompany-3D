extends Node3D
class_name ShuttleExteriorFeedCamera
## Камера на корпусе шаттла: SubViewport + `FeedMount`. Картинку показывают `ShuttleInteriorWindowFeed` / `ShuttleInteriorMonitorFeed` в салоне.
## `get_feed_subviewport()` не зависит от порядка `_ready`: узел `Shuttle` в сцене часто инициализируется позже `ShipInterior`.

@export_group("Узлы")
@export var feed_mount_path: NodePath = "FeedMount"
@export var subviewport_path: NodePath = "SubViewport"
@export var feed_camera_path: NodePath = "SubViewport/FeedCamera"

@export_group("Группа")
## Для салона: `shuttle_window_feed` (иллюминатор) и `shuttle_monitor_feed` (второй корм на шаттле).
@export var feed_camera_group: StringName = &"shuttle_window_feed"

@export_group("SubViewport")
@export var viewport_size: Vector2i = Vector2i(640, 360):
	set(v):
		viewport_size = v
		_apply_viewport_state()
@export var viewport_update_mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS:
	set(v):
		viewport_update_mode = v
		_apply_viewport_state()

@export_group("Камера")
@export_range(20.0, 120.0) var feed_fov: float = 58.0:
	set(v):
		feed_fov = v
		_apply_camera_params()
@export_range(0.02, 2.0) var feed_near: float = 0.06:
	set(v):
		feed_near = v
		_apply_camera_params()
@export_range(100.0, 20000.0) var feed_far: float = 8000.0:
	set(v):
		feed_far = v
		_apply_camera_params()
@export_flags_3d_render var feed_cull_mask: int = 0xFFFFF:
	set(v):
		feed_cull_mask = v
		_apply_camera_params()

var _feed_mount: Node3D
var _subviewport: SubViewport
var _feed_camera: Camera3D


func _enter_tree() -> void:
	if not feed_camera_group.is_empty():
		add_to_group(feed_camera_group)


func _ready() -> void:
	_resolve_nodes()
	_apply_viewport_state()
	_apply_camera_params()
	_hook_world_3d()
	set_process(true)


func get_feed_subviewport() -> SubViewport:
	# Дочерний SubViewport уже в дереве до `_ready` этого узла — иначе экран в салоне
	# не может подключиться, пока не отработает вся ветка ShipInterior.
	return get_node_or_null(subviewport_path) as SubViewport


func _resolve_nodes() -> void:
	_feed_mount = get_node_or_null(feed_mount_path) as Node3D
	_subviewport = get_node_or_null(subviewport_path) as SubViewport
	_feed_camera = get_node_or_null(feed_camera_path) as Camera3D


func _hook_world_3d() -> void:
	if _subviewport == null:
		return
	var vp := get_viewport()
	if vp and vp.world_3d:
		_subviewport.world_3d = vp.world_3d


func _apply_viewport_state() -> void:
	if _subviewport:
		_subviewport.size = viewport_size
		_subviewport.render_target_update_mode = viewport_update_mode


func _apply_camera_params() -> void:
	if _feed_camera == null:
		return
	_feed_camera.fov = feed_fov
	_feed_camera.near = feed_near
	_feed_camera.far = feed_far
	const interior_screen_layer: int = 1 << 4
	const interior_window_layer: int = 1 << 5
	_feed_camera.cull_mask = feed_cull_mask & ~interior_screen_layer & ~interior_window_layer
	# Для SubViewport эта камера должна быть активной, иначе кадр в текстуру не строится.
	_feed_camera.current = true


func _process(_delta: float) -> void:
	if _feed_camera and _feed_mount and is_instance_valid(_feed_mount):
		_feed_camera.global_transform = _feed_mount.global_transform


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		call_deferred("_hook_world_3d")
