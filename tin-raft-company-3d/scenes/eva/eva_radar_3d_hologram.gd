extends Node3D
class_name EvaRadar3DHologram
## Голограмма: пул мешей; зум меняет только mapping, не scale корня приборки.

const T_SHUTTLE := 0
const T_ASTEROID := 1
const T_PLAYER := 2
const T_WORLD_ITEM := 3
const T_OTHER := 4

@export var hologram_zoom_min: float = 0.35
@export var hologram_zoom_max: float = 4.5

@onready var _hologram_root: Node3D = $HologramRoot
@onready var _pool_host: Node3D = $HologramRoot/HologramPool
@onready var _bubble: MeshInstance3D = $HologramRoot/HologramBubble as MeshInstance3D

var _mapping_range_factor: float = 1.0
var _pool: Array[MeshInstance3D] = []
var _pool_materials: Array[StandardMaterial3D] = []
var _last_bubble_mesh_radius: float = -1.0


func _ready() -> void:
	_build_pool(96)


func refresh_bubble_layout(hologram_span: float) -> void:
	_sync_bubble_radius(hologram_span)


func adjust_zoom_local(factor: float) -> void:
	_mapping_range_factor = clampf(_mapping_range_factor * factor, hologram_zoom_min, hologram_zoom_max)


func update_hologram_meshes(
	ref_xf: Transform3D,
	positions: PackedVector3Array,
	types: PackedByteArray,
	detection_radius: float,
	hologram_span: float,
) -> void:
	if _hologram_root == null or _pool.is_empty():
		return
	_sync_bubble_radius(hologram_span)
	var inv: Transform3D = ref_xf.inverse()
	var ref_origin: Vector3 = ref_xf.origin
	var r_lim: float = maxf(detection_radius, 0.01)
	var r_cut: float = r_lim + maxf(0.06, r_lim * 0.0025)
	var denom: float = maxf(detection_radius * _mapping_range_factor, 0.01)
	var scale_w: float = hologram_span / denom
	var marker_zoom_scale: float = 1.0 / maxf(_mapping_range_factor, 0.001)
	for i: int in range(_pool.size()):
		var mi: MeshInstance3D = _pool[i]
		if i >= positions.size():
			mi.visible = false
			continue
		if ref_origin.distance_to(positions[i]) > r_cut:
			mi.visible = false
			continue
		var lp: Vector3 = inv * positions[i]
		mi.position = lp * scale_w
		var bubble_r: float = maxf(hologram_span, 0.05)
		if mi.position.length_squared() > bubble_r * bubble_r:
			mi.visible = false
			continue
		mi.visible = true
		mi.scale = Vector3.ONE * marker_zoom_scale
		var t: int = int(types[i]) if i < types.size() else T_OTHER
		_pool_materials[i].albedo_color = _hologram_color(t)


func _sync_bubble_radius(hologram_span: float) -> void:
	if _bubble == null:
		return
	var br: float = maxf(hologram_span, 0.05)
	if is_equal_approx(_last_bubble_mesh_radius, br):
		return
	_last_bubble_mesh_radius = br
	var sm: SphereMesh = _bubble.mesh as SphereMesh
	if sm == null:
		sm = SphereMesh.new()
		_bubble.mesh = sm
	sm.radius = br
	sm.height = br * 2.0


func _hologram_color(t: int) -> Color:
	match t:
		T_SHUTTLE:
			return Color(0.25, 0.85, 1.0, 0.55)
		T_ASTEROID:
			return Color(0.95, 0.45, 0.15, 0.5)
		T_PLAYER:
			return Color(0.25, 1.0, 0.35, 0.55)
		T_WORLD_ITEM:
			return Color(0.95, 0.92, 0.25, 0.5)
		_:
			return Color(0.75, 0.72, 0.9, 0.45)


func _build_pool(count: int) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.07)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 0.09
	for i: int in range(count):
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.sorting_offset = 10.0
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.render_priority = 8
		mat.albedo_color = Color(1, 1, 1, 0.5)
		mi.material_override = mat
		match i % 5:
			0, 2:
				mi.mesh = sphere.duplicate() as Mesh
			1, 3:
				mi.mesh = box.duplicate() as Mesh
			_:
				mi.mesh = cyl.duplicate() as Mesh
		_pool_host.add_child(mi)
		mi.visible = false
		_pool.append(mi)
		_pool_materials.append(mat)
