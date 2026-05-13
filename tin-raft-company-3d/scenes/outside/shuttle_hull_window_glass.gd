extends MeshInstance3D
## Стекло на корпусе: картинка салона с `SubViewport` через `get_texture()` (без ViewportTexture — иначе фиолетовый на инстансах).

var _interior_vp: SubViewport
var _mat: StandardMaterial3D


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("interior_window_viewport"):
		if n is SubViewport:
			_interior_vp = n as SubViewport
			break
	if _interior_vp == null:
		push_warning("ShuttleHullWindowGlass: нет SubViewport в группе interior_window_viewport")
		return
	_mat = material_override as StandardMaterial3D
	if _mat == null:
		_mat = StandardMaterial3D.new()
		material_override = _mat
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(1, 1, 1, 0.92)
	_mat.metallic = 0.0
	_mat.roughness = 1.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_process(true)


func _process(_delta: float) -> void:
	if _interior_vp == null or _mat == null:
		return
	var tex: Texture2D = _interior_vp.get_texture()
	if tex:
		_mat.albedo_texture = tex
