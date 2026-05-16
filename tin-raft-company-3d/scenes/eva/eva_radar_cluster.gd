extends Node3D
## EVA dual radar: координатор (снимки, режим, RPC), дочерние сцены 2D/3D.
## Paths (main.tscn / eva_zone):
##   This cluster: Inside/EVA/ShipInterior/EvaDualRadarCluster  (GameScenePaths.EVA_RADAR_CLUSTER)
##   2D instrument: .../VisualRoot/EvaRadar2DInstrument
##   3D hologram:   .../VisualRoot/EvaRadar3DHologram
##   Players:       Inside/EVA/Shuttle/ShipInterior/PlayerContainer/Player_*
##   WorldObjects:  Inside/WorldObjects
##   Shuttle:       Inside/EVA/Shuttle

const T_SHUTTLE := 0
const T_ASTEROID := 1
const T_PLAYER := 2
const T_WORLD_ITEM := 3
const T_OTHER := 4

enum RadarMode { SHIP, FOLLOW_PEER }

@export var detection_radius: float = 200.0
@export var snapshot_hz: float = 10.0
@export var hologram_span: float = 2.2
@export var zoom_wheel_max_distance: float = 5.0
@export var hologram_zoom_min: float = 0.35
@export var hologram_zoom_max: float = 4.5

@onready var _visual_root: Node3D = $VisualRoot
@onready var _instrument_2d: Node3D = $VisualRoot/EvaRadar2DInstrument
@onready var _instrument_3d: Node3D = $VisualRoot/EvaRadar3DHologram
@onready var _mode_label: Label3D = $VisualRoot/ModeStatusLabel

var _mode: RadarMode = RadarMode.SHIP
var _follow_peer_id: int = 1

var _last_world_positions: PackedVector3Array = PackedVector3Array()
var _last_types: PackedByteArray = PackedByteArray()

var _shuttle: Node3D
var _world_objects: Node
var _player_container: Node3D

var _snapshot_accum: float = 0.0
## Дедуп при обходе нескольких корней (шаттл, игроки, полное дерево сцены).
var _snapshot_seen: Dictionary = {}


func _ready() -> void:
	add_to_group("eva_radar_cluster")
	_shuttle = MultiplayerNodeResolver.resolve(get_tree(), GameScenePaths.EVA_SHUTTLE) as Node3D
	_world_objects = GameScenePaths.get_world_objects_node(get_tree())
	var pc: Node = MultiplayerNodeResolver.resolve(get_tree(), "%s/%s" % [GameScenePaths.INSIDE, GameScenePaths.PLAYER_CONTAINER])
	_player_container = pc as Node3D
	if _instrument_3d:
		_instrument_3d.hologram_zoom_min = hologram_zoom_min
		_instrument_3d.hologram_zoom_max = hologram_zoom_max
		_instrument_3d.refresh_bubble_layout(hologram_span)
	_refresh_session_ui()
	if not NetworkManager.session_started.is_connected(_on_nm_session):
		NetworkManager.session_started.connect(_on_nm_session)
	if not NetworkManager.session_ended.is_connected(_on_nm_session):
		NetworkManager.session_ended.connect(_on_nm_session)


func _exit_tree() -> void:
	if NetworkManager.session_started.is_connected(_on_nm_session):
		NetworkManager.session_started.disconnect(_on_nm_session)
	if NetworkManager.session_ended.is_connected(_on_nm_session):
		NetworkManager.session_ended.disconnect(_on_nm_session)


func _on_nm_session(_arg = null) -> void:
	_refresh_session_ui()


func _refresh_session_ui() -> void:
	var active: bool = NetworkManager.is_session_active()
	if _visual_root:
		_visual_root.visible = active
	set_process(active)
	set_process_input(active)
	if active:
		_snapshot_accum = 0.0
	_apply_mode_label()


func _process(delta: float) -> void:
	if not NetworkManager.is_session_active():
		return
	if multiplayer.is_server():
		_snapshot_accum += delta
		var step: float = 1.0 / maxf(snapshot_hz, 1.0)
		while _snapshot_accum >= step:
			_snapshot_accum -= step
			_server_emit_snapshot()
	_update_visuals_client(delta)


func _input(event: InputEvent) -> void:
	if not NetworkManager.is_session_active():
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		if not ek.pressed or ek.echo:
			return
		var plk: Node3D = LocalPlayerFinder.authority_node3d(get_tree())
		if plk == null or plk.global_position.distance_to(global_position) > zoom_wheel_max_distance:
			return
		match ek.keycode:
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				adjust_zoom_local(1.12)
			KEY_MINUS, KEY_KP_SUBTRACT:
				adjust_zoom_local(0.89)
			_:
				pass


func adjust_zoom_local(factor: float) -> void:
	if _instrument_3d:
		_instrument_3d.adjust_zoom_local(factor)


func get_radar_state_for_sync() -> Dictionary:
	return {"mode": int(_mode), "follow_peer_id": _follow_peer_id}


func apply_radar_state(mode: int, follow_peer_id: int) -> void:
	_mode = RadarMode.SHIP if mode == 0 else RadarMode.FOLLOW_PEER
	_follow_peer_id = follow_peer_id
	_apply_mode_label()


func apply_radar_snapshot(positions: PackedVector3Array, types: PackedByteArray) -> void:
	_last_world_positions = positions
	_last_types = types
	_update_visuals_client(0.0)


func server_validate_interaction(_actor: Node3D) -> bool:
	return NetworkManager.is_session_active()


func server_apply_interaction(_actor: Node3D, command: Dictionary = {}) -> bool:
	if not server_validate_interaction(_actor):
		return false
	var ctype: String = str(command.get("type", ""))
	if ctype == "radar_set_mode":
		if _mode == RadarMode.SHIP:
			_mode = RadarMode.FOLLOW_PEER
			_follow_peer_id = _first_peer_id_or(_follow_peer_id)
		else:
			_mode = RadarMode.SHIP
		_apply_mode_label()
		NetworkManager.broadcast_eva_radar_state(int(_mode), _follow_peer_id)
		return true
	if ctype == "radar_cycle_peer":
		if _mode != RadarMode.FOLLOW_PEER:
			_mode = RadarMode.FOLLOW_PEER
		var peers: Array[int] = _list_peer_ids()
		if peers.is_empty():
			return true
		var idx: int = peers.find(_follow_peer_id)
		if idx < 0:
			_follow_peer_id = peers[0]
		else:
			_follow_peer_id = peers[(idx + 1) % peers.size()]
		_apply_mode_label()
		NetworkManager.broadcast_eva_radar_state(int(_mode), _follow_peer_id)
		return true
	return false


func _apply_mode_label() -> void:
	if _mode_label == null:
		return
	if _mode == RadarMode.SHIP:
		_mode_label.text = "RADAR\nSHIP FRAME"
	else:
		_mode_label.text = "RADAR\nPEER %d" % _follow_peer_id


func _reference_transform() -> Transform3D:
	if _mode == RadarMode.FOLLOW_PEER:
		var puppet: Node3D = MultiplayerNodeResolver.resolve(
			get_tree(), GameScenePaths.player_puppet_path_str(_follow_peer_id)
		) as Node3D
		if puppet:
			return puppet.global_transform
	if _shuttle and is_instance_valid(_shuttle):
		return _shuttle.global_transform
	return global_transform


func _update_visuals_client(_delta_unused: float) -> void:
	var ref_xf: Transform3D = _reference_transform()
	var inv: Transform3D = ref_xf.inverse()
	var xz: PackedVector2Array = PackedVector2Array()
	xz.resize(_last_world_positions.size())
	for i: int in range(_last_world_positions.size()):
		var lp: Vector3 = inv * _last_world_positions[i]
		var n: float = maxf(detection_radius, 0.01)
		xz[i] = Vector2(lp.x, lp.z) / n
	if _instrument_2d:
		_instrument_2d.set_targets(xz, _last_types)
	if _instrument_3d:
		_instrument_3d.update_hologram_meshes(ref_xf, _last_world_positions, _last_types, detection_radius, hologram_span)


func _server_emit_snapshot() -> void:
	var positions: PackedVector3Array = PackedVector3Array()
	var types: PackedByteArray = PackedByteArray()
	var ref_xf: Transform3D = _reference_transform()
	var origin: Vector3 = ref_xf.origin
	var r: float = maxf(detection_radius, 0.01)
	var r2: float = r * r

	_snapshot_seen.clear()

	if _shuttle and is_instance_valid(_shuttle):
		_try_push_target(_shuttle, positions, types, origin, r2)

	# Полевые астероиды — дети корня сцены; статические EVA-астероиды — в EVA/Shuttle/ShipInterior/Items;
	# динамика и лут — под WorldObjects. Один обход корня игры покрывает всё релевантное.
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		_walk_collect(scene_root, positions, types, origin, r2)
	elif _world_objects:
		_walk_collect(_world_objects, positions, types, origin, r2)

	if _player_container:
		for c in _player_container.get_children():
			if c is Node3D and (c as Node3D).is_in_group("player"):
				_try_push_target(c as Node3D, positions, types, origin, r2)
			elif str(c.name).begins_with("Player_") and c is Node3D:
				_try_push_target(c as Node3D, positions, types, origin, r2)

	NetworkManager.broadcast_eva_radar_snapshot(types, positions)


func _walk_collect(node: Node, positions: PackedVector3Array, types: PackedByteArray, origin: Vector3, r2: float) -> void:
	for c in node.get_children():
		if c is Node3D and _is_branch_excluded(c as Node3D):
			continue
		if c is RigidBody3D or c is CharacterBody3D:
			_try_push_target(c as Node3D, positions, types, origin, r2)
		_walk_collect(c, positions, types, origin, r2)


func _is_branch_excluded(n: Node3D) -> bool:
	var p: String = str(n.get_path())
	if p.find("EvaDualRadarCluster") >= 0:
		return true
	# UI и чат не несут целей радара; обрезаем ветку целиком.
	if p.find("/UILayer") >= 0:
		return true
	return false


func _try_push_target(n: Node3D, positions: PackedVector3Array, types: PackedByteArray, origin: Vector3, r2: float) -> void:
	var sid: int = n.get_instance_id()
	if _snapshot_seen.has(sid):
		return
	var d2: float = n.global_position.distance_squared_to(origin)
	if d2 > r2:
		return
	_snapshot_seen[sid] = true
	var t: int = _classify_target(n)
	positions.append(n.global_position)
	types.append(t as int)


func _classify_target(n: Node3D) -> int:
	if _shuttle and n == _shuttle:
		return T_SHUTTLE
	var nm: String = str(n.name)
	if nm.begins_with("AsteroidField_"):
		return T_ASTEROID
	if n.is_in_group("player") or nm.begins_with("Player_"):
		return T_PLAYER
	if n.get("item_data") != null:
		return T_WORLD_ITEM
	var sc: Variant = n.get_script()
	if sc is Script:
		var path_s: String = (sc as Script).resource_path.to_lower()
		if path_s.find("asteroid") >= 0:
			return T_ASTEROID
		if path_s.find("worlditem") >= 0:
			return T_WORLD_ITEM
	return T_OTHER


func _list_peer_ids() -> Array[int]:
	var out: Array[int] = []
	if _player_container == null:
		return out
	for c in _player_container.get_children():
		var nm: String = str(c.name)
		if nm.begins_with("Player_"):
			var rest: String = nm.trim_prefix("Player_")
			if rest.is_valid_int():
				out.append(int(rest))
	out.sort()
	return out


func _first_peer_id_or(fallback: int) -> int:
	var p: Array[int] = _list_peer_ids()
	if p.is_empty():
		return fallback
	if p.has(fallback):
		return fallback
	return p[0]
