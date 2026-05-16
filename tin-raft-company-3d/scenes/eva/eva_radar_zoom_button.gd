extends StaticBody3D

enum ZoomDir { IN, OUT }
@export var dir: ZoomDir = ZoomDir.IN


func show_hint() -> void:
	pass


func hide_hint() -> void:
	pass


func interact(_caller: Node3D) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var f: float = 1.12 if dir == ZoomDir.IN else 0.89
	for n: Node in tree.get_nodes_in_group("eva_radar_cluster"):
		if n.has_method("adjust_zoom_local"):
			n.adjust_zoom_local(f)
			return
