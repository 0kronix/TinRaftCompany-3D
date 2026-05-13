extends SubViewport
## Вид салона в текстуру для HullWindowGlass на шаттле (камера в салоне, не на шаттле).
## Узлы: InteriorWindowCam, позиция — InteriorWindowCamMount.

const GROUP_NAME := "interior_window_viewport"

@export var camera_mount_path: NodePath = NodePath("../InteriorWindowCamMount")
@export var camera_node_path: NodePath = NodePath("InteriorWindowCam")


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	# Только текстура с вьюпорта: без ALWAYS сабвьюпорт не рисуется (не в SubViewportContainer).
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	call_deferred("_hook_world_3d")
	call_deferred("_activate_camera")
	set_process(true)


func _activate_camera() -> void:
	var cam := get_node_or_null(camera_node_path) as Camera3D
	if cam:
		cam.current = true


func _hook_world_3d() -> void:
	var vp := get_viewport()
	if vp and vp.world_3d:
		world_3d = vp.world_3d


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		call_deferred("_hook_world_3d")


func _process(_delta: float) -> void:
	var cam := get_node_or_null(camera_node_path) as Camera3D
	var mnt := get_node_or_null(camera_mount_path) as Node3D
	if cam and mnt and is_instance_valid(mnt):
		cam.global_transform = mnt.global_transform
