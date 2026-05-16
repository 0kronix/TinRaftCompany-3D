extends Node3D
class_name EvaRadar2DInstrument
## SubViewport + 2D-панель + quad-текстура для отображения радара.

@onready var _radar_vp: SubViewport = $Radar2DViewport
@onready var _radar_canvas: Control = $Radar2DViewport/RadarCanvas
@onready var _display: MeshInstance3D = $Radar2DViewportDisplay


func _ready() -> void:
	_setup_radar_display_material()
	if _radar_vp:
		_radar_vp.size_changed.connect(_on_vp_size)
	_on_vp_size()


func set_targets(local_xz: PackedVector2Array, types: PackedByteArray) -> void:
	if _radar_canvas and _radar_canvas.has_method("set_targets"):
		_radar_canvas.set_targets(local_xz, types)


func _setup_radar_display_material() -> void:
	if _display == null or _radar_vp == null:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = _radar_vp.get_texture()
	_display.material_override = mat


func _on_vp_size() -> void:
	if _radar_canvas and _radar_vp:
		_radar_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
