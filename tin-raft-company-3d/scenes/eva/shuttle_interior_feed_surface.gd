extends Node3D
class_name ShuttleInteriorFeedSurface
## Один экран (квад + шейдер) и один корм на шаттле. Сцены: `shuttle_interior_feed_window`, `shuttle_interior_feed_monitor`.
## Подключение: сначала `feed_node_path` (если задан), иначе первый узел в `feed_camera_group` с `get_feed_subviewport()`.

const LAYER_MONITOR: int = 1 << 4
const LAYER_WINDOW: int = 1 << 5

@export_group("Корм")
## Непустой путь — `get_node_or_null` относительно этого узла (если иерархия менялась — задайте вручную).
@export var feed_node_path: NodePath = NodePath("")
## Если путь пустой: `shuttle_window_feed` / `shuttle_monitor_feed` (см. ShuttleExteriorFeedCamera).
@export var feed_camera_group: StringName = &""

@export_group("Узлы")
@export var screen_mesh_path: NodePath = NodePath("Screen")
@export var porthole_frame_path: NodePath = NodePath("")

@export_group("Отрисовка")
@export var render_layer: int = LAYER_MONITOR:
	set(v):
		render_layer = v
		_apply_mesh_layer()

@export_group("Размер квада (локально)")
@export var screen_size: Vector2 = Vector2(0.95, 0.52):
	set(v):
		screen_size = v
		_apply_quad_size()
		_apply_porthole_frame()

enum DisplayProfile { FLAT, CRT_BULGE, PORTHOLE }
@export var display_profile: DisplayProfile = DisplayProfile.CRT_BULGE:
	set(v):
		display_profile = v
		_shader_apply()

@export_range(0.0, 0.45) var crt_barrel: float = 0.14:
	set(v):
		crt_barrel = v
		_shader_apply()
@export_range(0.35, 0.49) var porthole_radius: float = 0.46:
	set(v):
		porthole_radius = v
		_shader_apply()
@export_range(0.005, 0.12) var porthole_feather: float = 0.038:
	set(v):
		porthole_feather = v
		_shader_apply()

@export var show_porthole_frame: bool = true:
	set(v):
		show_porthole_frame = v
		_apply_porthole_frame()

@export_group("Помехи / пост")
@export_range(0.0, 0.45) var noise_amount: float = 0.035:
	set(v):
		noise_amount = v
		_shader_apply()
@export_range(0.0, 0.02) var chroma_aberration: float = 0.0035:
	set(v):
		chroma_aberration = v
		_shader_apply()
@export_range(0.0, 0.28) var scanline_strength: float = 0.055:
	set(v):
		scanline_strength = v
		_shader_apply()
@export_range(0.0, 0.55) var vignette_strength: float = 0.16:
	set(v):
		vignette_strength = v
		_shader_apply()
@export_range(0.5, 1.35) var global_brightness: float = 1.0:
	set(v):
		global_brightness = v
		_shader_apply()

@export_group("Плохой сигнал (стрим / монитор)")
## 1 — выкл.; ~32–64 — крупная «сетка» как при низком битрейте.
@export_range(0.0, 256.0) var bad_net_mosaic: float = 0.0:
	set(v):
		bad_net_mosaic = v
		_shader_apply()
@export_range(0.0, 0.025) var bad_net_tear: float = 0.0:
	set(v):
		bad_net_tear = v
		_shader_apply()
@export_range(0.0, 1.0) var bad_net_glitch: float = 0.0:
	set(v):
		bad_net_glitch = v
		_shader_apply()
@export_range(0.0, 1.0) var bad_net_dropout: float = 0.0:
	set(v):
		bad_net_dropout = v
		_shader_apply()
@export_range(0.0, 1.0) var bad_net_posterize: float = 0.0:
	set(v):
		bad_net_posterize = v
		_shader_apply()
@export_range(0.0, 0.35) var bad_net_chroma_snow: float = 0.0:
	set(v):
		bad_net_chroma_snow = v
		_shader_apply()

var _screen_mesh: MeshInstance3D
var _porthole_frame: MeshInstance3D
var _mat: ShaderMaterial
var _quad: QuadMesh
var _sub: SubViewport
var _feed_connect_attempts: int = 0
const _MAX_FEED_CONNECT_ATTEMPTS: int = 400


func _ready() -> void:
	_resolve_meshes()
	_ensure_material()
	_apply_quad_size()
	_apply_mesh_layer()
	_shader_apply()
	_apply_porthole_frame()
	call_deferred("_connect_feed")
	set_process(false)


func _resolve_meshes() -> void:
	_screen_mesh = get_node_or_null(screen_mesh_path) as MeshInstance3D
	if porthole_frame_path.is_empty():
		_porthole_frame = null
	else:
		_porthole_frame = get_node_or_null(porthole_frame_path) as MeshInstance3D


func _find_feeder() -> Node:
	if not feed_node_path.is_empty():
		var by_path: Node = get_node_or_null(feed_node_path)
		if by_path:
			return by_path
	if not feed_camera_group.is_empty() and is_inside_tree():
		for n in get_tree().get_nodes_in_group(feed_camera_group):
			if n and n.has_method("get_feed_subviewport"):
				return n
	return null


func _connect_feed() -> void:
	_feed_connect_attempts += 1
	var feeder: Node = _find_feeder()
	if feeder == null:
		if _feed_connect_attempts > _MAX_FEED_CONNECT_ATTEMPTS:
			push_warning(
				"%s: корм не найден (path=%s group=%s)."
				% [name, str(feed_node_path), str(feed_camera_group)]
			)
			return
		call_deferred("_connect_feed")
		return

	_sub = _get_subviewport_from_feeder(feeder)
	if _sub == null:
		if _feed_connect_attempts > _MAX_FEED_CONNECT_ATTEMPTS:
			push_warning("%s: у корма нет SubViewport." % name)
			return
		call_deferred("_connect_feed")
		return

	_feed_connect_attempts = 0
	set_process(true)


func _get_subviewport_from_feeder(feeder: Node) -> SubViewport:
	if feeder.has_method("get_feed_subviewport"):
		var sv: SubViewport = feeder.call("get_feed_subviewport") as SubViewport
		if sv != null:
			return sv
	return feeder.get_node_or_null(NodePath("SubViewport")) as SubViewport


func _ensure_material() -> void:
	var sh: Shader = load("res://shaders/shuttle_feed_screen.gdshader") as Shader
	if sh == null:
		push_error("%s: нет res://shaders/shuttle_feed_screen.gdshader" % name)
		return
	if _screen_mesh == null:
		push_warning("%s: нет MeshInstance по path %s" % [name, str(screen_mesh_path)])
		return
	if _screen_mesh.mesh is QuadMesh:
		_quad = _screen_mesh.mesh as QuadMesh
	else:
		_quad = QuadMesh.new()
		_screen_mesh.mesh = _quad
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_screen_mesh.material_override = _mat


func _apply_mesh_layer() -> void:
	if _screen_mesh:
		_screen_mesh.layers = render_layer
	if _porthole_frame:
		_porthole_frame.layers = render_layer


func _process(_delta: float) -> void:
	if _mat == null or _sub == null or not is_instance_valid(_sub):
		return
	var tex: Texture2D = _sub.get_texture()
	if tex:
		_mat.set_shader_parameter("screen_texture", tex)


func _apply_quad_size() -> void:
	if _quad:
		_quad.size = screen_size
	_apply_porthole_frame()


func _apply_porthole_frame() -> void:
	if _porthole_frame == null:
		return
	var use_frame: bool = show_porthole_frame and display_profile == DisplayProfile.PORTHOLE
	_porthole_frame.visible = use_frame
	if not use_frame:
		return
	const torus_hole_diameter: float = 0.9
	var side: float = maxf(screen_size.x, screen_size.y)
	var ring: float = clampf((side * 2.0 * porthole_radius) / torus_hole_diameter, 0.12, 50.0)
	_porthole_frame.scale = Vector3(ring, ring, ring)


func _shader_apply() -> void:
	if _mat == null or not is_instance_valid(_mat):
		return
	_mat.set_shader_parameter("display_profile", float(display_profile))
	_mat.set_shader_parameter("crt_barrel", crt_barrel)
	_mat.set_shader_parameter("porthole_radius", porthole_radius)
	_mat.set_shader_parameter("porthole_feather", porthole_feather)
	_mat.set_shader_parameter("noise_amount", noise_amount)
	_mat.set_shader_parameter("chroma_aberration", chroma_aberration)
	_mat.set_shader_parameter("scanline_strength", scanline_strength)
	_mat.set_shader_parameter("vignette_strength", vignette_strength)
	_mat.set_shader_parameter("global_brightness", global_brightness)
	_mat.set_shader_parameter("bad_net_mosaic", bad_net_mosaic)
	_mat.set_shader_parameter("bad_net_tear", bad_net_tear)
	_mat.set_shader_parameter("bad_net_glitch", bad_net_glitch)
	_mat.set_shader_parameter("bad_net_dropout", bad_net_dropout)
	_mat.set_shader_parameter("bad_net_posterize", bad_net_posterize)
	_mat.set_shader_parameter("bad_net_chroma_snow", bad_net_chroma_snow)
	_apply_porthole_frame()
