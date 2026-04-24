extends CharacterBody3D

const INTERP_SPEED := 12.0

var peer_id: int = 0

var _target_pos: Vector3 = Vector3.ZERO
var _target_rot_y: float = 0.0
var _target_head_rot_x: float = 0.0
var _initialized: bool = false

@onready var head_pivot: Node3D = $HeadPivot
@onready var name_label: Label3D = $HeadPivot/NameLabel

func _ready() -> void:
	_target_pos = global_position
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _initialized:
		return
	global_position = global_position.lerp(_target_pos, INTERP_SPEED * delta)
	rotation.y = lerp_angle(rotation.y, _target_rot_y, INTERP_SPEED * delta)
	head_pivot.rotation.x = lerp_angle(head_pivot.rotation.x, _target_head_rot_x, INTERP_SPEED * delta)

func apply_state(pos: Vector3, rot_y: float, head_rot_x: float) -> void:
	if not _initialized:
		global_position = pos
		rotation.y = rot_y
		head_pivot.rotation.x = head_rot_x
		_initialized = true
	_target_pos = pos
	_target_rot_y = rot_y
	_target_head_rot_x = head_rot_x

func set_player_name(player_name: String) -> void:
	if name_label:
		name_label.text = player_name
