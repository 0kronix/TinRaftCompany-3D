extends Node
## Подсказка взаимодействия: инстанс сцены `res://scenes/ui/interaction_hint_panel.tscn` на `UILayer`.

const _PANEL_SCENE: PackedScene = preload("res://scenes/ui/interaction_hint_panel.tscn")

var _hint_panel: InteractionHintPanel


func find_hint_provider(collider: Node) -> Node:
	var n: Node = collider
	while n:
		if n.has_method("show_hint") and n.has_method("hide_hint"):
			return n
		n = n.get_parent()
	return null


func resolve_hint_text(provider: Node) -> String:
	if provider == null:
		return ""
	if provider.has_method("get_interaction_hint"):
		var v: Variant = provider.call("get_interaction_hint")
		if v is String:
			return (v as String).strip_edges()
		return str(v).strip_edges()
	var lbl: Label3D = provider.get_node_or_null("Label3D") as Label3D
	if lbl:
		return lbl.text.strip_edges()
	lbl = _find_label3d_shallow(provider, 0)
	if lbl:
		return lbl.text.strip_edges()
	return ""


func _find_label3d_shallow(n: Node, depth: int) -> Label3D:
	if depth > 5:
		return null
	if n is Label3D:
		return n as Label3D
	for c in n.get_children():
		var r: Label3D = _find_label3d_shallow(c, depth + 1)
		if r:
			return r
	return null


func show_hint_text(text: String) -> void:
	var t: String = text.strip_edges()
	if t.is_empty():
		hide_hint_text()
		return
	_ensure_ui()
	if _hint_panel == null:
		return
	_hint_panel.show_text(t)


func hide_hint_text() -> void:
	if _hint_panel != null and is_instance_valid(_hint_panel):
		_hint_panel.hide_text()


func _ensure_ui() -> void:
	if _hint_panel != null and is_instance_valid(_hint_panel) and _hint_panel.is_inside_tree():
		return
	if _hint_panel != null and is_instance_valid(_hint_panel):
		_hint_panel.queue_free()
	_hint_panel = null
	var layer: CanvasLayer = _find_ui_layer()
	if layer == null:
		return
	var inst: Node = _PANEL_SCENE.instantiate()
	if not (inst is InteractionHintPanel):
		if is_instance_valid(inst):
			inst.queue_free()
		return
	_hint_panel = inst as InteractionHintPanel
	_hint_panel.name = "InteractionHintPanel"
	layer.add_child(_hint_panel)


func _find_ui_layer() -> CanvasLayer:
	var game_scene: Node = get_tree().current_scene
	if game_scene:
		var cl: CanvasLayer = game_scene.get_node_or_null("UILayer") as CanvasLayer
		if cl:
			return cl
	var p: Node = LocalPlayerFinder.authority_player(get_tree())
	if p:
		var ml: CanvasLayer = p.get_node_or_null("MenuLayer") as CanvasLayer
		if ml:
			return ml
	return null
